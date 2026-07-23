#!/usr/bin/env python3
"""Validate hash-locked benchmark inputs for the public Verilator runner."""

from __future__ import annotations

import hashlib
import json
from pathlib import Path
import re
from typing import Any, Mapping


SCHEMA = "npc-riscv-open/coremark-benchmark-v1"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def _hex_u32(value: object, field: str) -> int:
    if not isinstance(value, str) or re.fullmatch(r"0x[0-9a-fA-F]{1,8}", value) is None:
        raise ValueError(f"{field} must be a 32-bit hexadecimal string")
    return int(value, 16)


def _sha256(value: object, field: str) -> str:
    if not isinstance(value, str) or re.fullmatch(r"[0-9a-f]{64}", value) is None:
        raise ValueError(f"{field} must be a lowercase SHA256")
    return value


def load_contract(manifest: Path, profile: str, image: Path, elf: Path) -> dict[str, Any]:
    try:
        data = json.loads(manifest.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise ValueError(f"invalid benchmark manifest {manifest}: {error}") from error
    if not isinstance(data, Mapping) or data.get("schema") != SCHEMA:
        raise ValueError(f"unsupported benchmark manifest schema in {manifest}")
    if data.get("benchmark") != "coremark":
        raise ValueError("benchmark manifest must describe coremark")
    iterations = data.get("iterations")
    contexts = data.get("contexts")
    if not isinstance(iterations, int) or iterations <= 0 or contexts != 1:
        raise ValueError("coremark manifest requires positive iterations and one context")
    variants = data.get("variants")
    if not isinstance(variants, Mapping):
        raise ValueError("benchmark manifest has no variants")
    matches = []
    for variant_id, raw in variants.items():
        if not isinstance(raw, Mapping):
            continue
        profiles = raw.get("profiles")
        if isinstance(profiles, list) and profile in profiles:
            matches.append((str(variant_id), raw))
    if len(matches) != 1:
        raise ValueError(f"profile {profile!r} maps to {len(matches)} benchmark variants")
    variant_id, variant = matches[0]
    expected_image = _sha256(variant.get("binary_sha256"), "binary_sha256")
    expected_elf = _sha256(variant.get("elf_sha256"), "elf_sha256")
    actual_image = sha256_file(image)
    actual_elf = sha256_file(elf)
    if actual_image != expected_image:
        raise ValueError(f"CoreMark binary SHA256 mismatch: {actual_image} != {expected_image}")
    if actual_elf != expected_elf:
        raise ValueError(f"CoreMark ELF SHA256 mismatch: {actual_elf} != {expected_elf}")
    image_base = _hex_u32(variant.get("image_base"), "image_base")
    markers = variant.get("markers")
    if not isinstance(markers, Mapping):
        raise ValueError("benchmark variant has no markers")
    parsed_markers: dict[str, dict[str, int]] = {}
    image_bytes = image.read_bytes()
    for name in ("start", "stop"):
        marker = markers.get(name)
        if not isinstance(marker, Mapping):
            raise ValueError(f"benchmark variant has no {name} marker")
        pc = _hex_u32(marker.get("pc"), f"markers.{name}.pc")
        instr = _hex_u32(marker.get("instr"), f"markers.{name}.instr")
        offset = pc - image_base
        if offset < 0 or offset + 4 > len(image_bytes):
            raise ValueError(f"{name} marker is outside the binary image")
        actual_instr = int.from_bytes(image_bytes[offset : offset + 4], "little")
        if actual_instr != instr:
            raise ValueError(
                f"{name} marker instruction mismatch at 0x{pc:08x}: "
                f"0x{actual_instr:08x} != 0x{instr:08x}"
            )
        parsed_markers[name] = {"pc": pc, "instr": instr}
    return {
        "name": "coremark",
        "variant": variant_id,
        "iterations": iterations,
        "contexts": contexts,
        "image_sha256": actual_image,
        "elf_sha256": actual_elf,
        "manifest_sha256": sha256_file(manifest),
        "start": parsed_markers["start"],
        "stop": parsed_markers["stop"],
    }
