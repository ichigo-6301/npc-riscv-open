#!/usr/bin/env python3
"""Fail-closed controller for the D8 dual-memory ASIC flow."""

import argparse
import datetime as dt
import hashlib
import json
import math
import os
from pathlib import Path
import re
import shlex
import shutil
import subprocess
import sys
from typing import Dict, Iterable, List, Optional, Tuple

from calculate_floorplan import calculate, calculate_with_macros, format_box
from compare_a3_dc import run as compare_a3_dc
from prepare_pnr_sdc import retarget
from summarize_dc import parse_run
from summarize_pnr import parse_run as parse_pnr_run
from summarize_sta import parse_run as parse_sta_run


PROFILES = ("rv32im_single_perf", "rv32ima_sv32_linux", "rv32im_ooo_4k")
MANIFEST_REL = Path("flows/asic/profiles/register_expanded.json")
SOURCE_MANIFEST_REL = Path("provenance/source_allowlist.json")
CONFIG_PROFILE_SYMBOLS = {
    "CONFIG_NPC_PROFILE_RV32IM_SINGLE_PERF": "rv32im_single_perf",
    "CONFIG_NPC_PROFILE_RV32IMA_SV32_LINUX": "rv32ima_sv32_linux",
    "CONFIG_NPC_PROFILE_RV32IM_OOO_4K": "rv32im_ooo_4k",
}
FORBIDDEN_DEFINES = ("NPC_USE_DPI", "NPC_DPI_")
HANDOFF_IDENTITY_FIELDS = (
    "profile",
    "mode",
    "memory_mode",
    "source_commit",
    "source_set_sha256",
    "source_role_sha256",
    "implementation_source_sha256",
    "config_sha256",
)
ORFS_RUNTIME_IDENTITY_POLICY = (
    "exact_oci_digest_git_head_when_vcs_metadata_present_v1")


class AsicError(RuntimeError):
    pass


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def sha256_json(value: object) -> str:
    return hashlib.sha256(
        (json.dumps(value, sort_keys=True, separators=(",", ":")) + "\n").encode()
    ).hexdigest()


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise AsicError(f"invalid JSON {path}: {error}") from error
    if not isinstance(value, dict):
        raise AsicError(f"JSON top level must be an object: {path}")
    return value


def require_handoff_identity(record: dict, expected: dict, label: str) -> None:
    """Require a complete source/config identity before consuming a handoff."""
    missing = [key for key in HANDOFF_IDENTITY_FIELDS if key not in record]
    if missing:
        raise AsicError(
            "{} is missing required identity fields: {}".format(
                label, ",".join(missing)
            )
        )
    for key in HANDOFF_IDENTITY_FIELDS:
        if record[key] != expected[key]:
            raise AsicError(
                "{} identity mismatch for {}: {} != {}".format(
                    label, key, record[key], expected[key]
                )
            )


def require_orfs_runtime_identity(matrix: dict) -> dict:
    orfs = matrix.get("orfs")
    required = ("commit", "image_digest", "platform", "runtime_identity_policy")
    if not isinstance(orfs, dict):
        raise AsicError("ASIC matrix lacks ORFS runtime identity")
    missing = [key for key in required if not orfs.get(key)]
    if missing:
        raise AsicError(
            "ASIC matrix ORFS identity lacks required fields: " + ",".join(missing))
    if re.fullmatch(r"[0-9a-f]{40}", str(orfs["commit"])) is None:
        raise AsicError("ASIC matrix ORFS commit must be a full lowercase Git commit")
    if re.fullmatch(r"sha256:[0-9a-f]{64}", str(orfs["image_digest"])) is None:
        raise AsicError("ASIC matrix ORFS image digest must be a full sha256 digest")
    if orfs["platform"] != "nangate45":
        raise AsicError("ASIC matrix ORFS platform must be nangate45")
    if orfs["runtime_identity_policy"] != ORFS_RUNTIME_IDENTITY_POLICY:
        raise AsicError("ASIC matrix ORFS runtime identity policy mismatch")
    return orfs


def parse_config(path: Path) -> Dict[str, str]:
    if not path.is_file():
        raise AsicError(f"missing {path}; select an ASIC defconfig first")
    values: Dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if line.startswith("# CONFIG_") and line.endswith(" is not set"):
            values[line[2:-11]] = "n"
        elif line.startswith("CONFIG_") and "=" in line:
            key, value = line.split("=", 1)
            values[key] = value.strip().strip('"')
    return values


def selected_profile(config: Dict[str, str]) -> str:
    selected = [profile for symbol, profile in CONFIG_PROFILE_SYMBOLS.items()
                if config.get(symbol) == "y"]
    if len(selected) != 1:
        raise AsicError(f"expected exactly one selected Profile, found {selected}")
    if config.get("CONFIG_NPC_PROFILE_ID") != selected[0]:
        raise AsicError("CONFIG_NPC_PROFILE_ID disagrees with the selected Profile")
    if config.get("CONFIG_NPC_ASIC_REGISTER_EXPANDED") != "y":
        raise AsicError("select a checked-in *_asic_defconfig before running ASIC stages")
    return selected[0]


def resolve_memory_mode(config: Dict[str, str], matrix: dict, profile: str,
                        requested: str) -> Tuple[str, dict]:
    configured = config.get("CONFIG_NPC_ASIC_MEMORY_MODE", "")
    mode = configured if requested == "auto" else requested
    if mode not in ("registers", "sram"):
        raise AsicError(f"unsupported ASIC memory mode: {mode}")
    if requested != "auto" and configured != requested:
        raise AsicError(
            f"--memory-mode {requested} disagrees with CONFIG_NPC_ASIC_MEMORY_MODE={configured}")
    modes = matrix.get("memory_modes", {})
    data = modes.get(mode) if isinstance(modes, dict) else None
    if not isinstance(data, dict):
        raise AsicError(f"ASIC matrix lacks memory mode {mode}")
    if profile not in data.get("allowed_profiles", []):
        if profile == "rv32im_ooo_4k" and mode == "sram":
            raise AsicError("OoO SRAM is BLOCKED_BY_FRONTEND_RETIMING")
        raise AsicError(f"memory mode {mode} is not enabled for {profile}")
    return mode, data


def source_record(root: Path, profile: str) -> dict:
    manifest = load_json(root / SOURCE_MANIFEST_REL)
    records = [record for record in manifest.get("profiles", [])
               if isinstance(record, dict) and record.get("profile_id") == profile]
    if len(records) != 1:
        raise AsicError(f"source allowlist must contain one {profile} record")
    return records[0]


def source_role_identity(root: Path, source: dict, sources: List[Path],
                         profile_data: dict, memory_mode: str) -> dict:
    """Validate every ASIC filelist source against a public, hashed role."""
    base_commit = str(source.get("source_commit", ""))
    raw_entries = source.get("entries", [])
    if not isinstance(raw_entries, list):
        raise AsicError("source allowlist entries must be a list")
    entries: Dict[str, dict] = {}
    for entry in raw_entries:
        if not isinstance(entry, dict):
            raise AsicError("source allowlist contains a malformed entry")
        destination = entry.get("destination")
        if not isinstance(destination, str) or not destination:
            raise AsicError("source allowlist entry lacks a destination")
        if destination in entries:
            raise AsicError(f"duplicate source allowlist destination: {destination}")
        entries[destination] = entry

    raw_overlays = source.get("memory_mode_overlays", [])
    if not isinstance(raw_overlays, list):
        raise AsicError("source allowlist memory_mode_overlays must be a list")
    selected_overlays = {
        str(entry.get("destination")): entry
        for entry in raw_overlays
        if isinstance(entry, dict) and entry.get("memory_mode") == memory_mode
    }
    entries.update(selected_overlays)
    support = profile_data.get("support_sources", {})
    if not isinstance(support, dict):
        raise AsicError("ASIC profile support_sources must be an object")

    role_records: List[dict] = []
    used_support = set()
    overlay_commits = set()
    for path in sources:
        relative = path.relative_to(root).as_posix()
        entry = entries.get(relative)
        if entry is not None:
            roles = entry.get("roles", [])
            required_role = (
                "asic_sram" if relative in selected_overlays else "asic"
            )
            if not isinstance(roles, list) or required_role not in roles:
                raise AsicError(f"source role is not ASIC-authorized: {relative}")
            expected = str(entry.get("sha256", ""))
            entry_commit = str(entry.get("source_commit", base_commit))
            if re.fullmatch(r"[0-9a-f]{40}", entry_commit) is None:
                raise AsicError(f"source role has no fixed commit: {relative}")
            if entry_commit != base_commit:
                overlay = selected_overlays.get(relative)
                if (not isinstance(overlay, dict) or
                        overlay.get("source_commit") != entry_commit or
                        overlay.get("sha256") != expected or
                        overlay.get("comparison") !=
                        "FUNCTIONAL_TOKEN_DIFFERENCE_NPC_ASIC_SRAM" or
                        not str(overlay.get("overlay_reason", "")).strip()):
                    raise AsicError(f"source overlay identity is incomplete: {relative}")
                overlay_commits.add(entry_commit)
                identity = "audited_sram_functional_overlay"
            else:
                identity = "profile_source"
        else:
            item = support.get(relative)
            if not isinstance(item, dict):
                raise AsicError(f"ASIC filelist source lacks a hashed role: {relative}")
            expected = str(item.get("sha256", ""))
            entry_commit = "tracked_public_support"
            identity = str(item.get("identity", "")).strip()
            if not identity:
                raise AsicError(f"support source lacks an identity label: {relative}")
            used_support.add(relative)
        if re.fullmatch(r"[0-9a-f]{64}", expected) is None:
            raise AsicError(f"source role has an invalid SHA256: {relative}")
        actual = sha256_file(path)
        if actual != expected:
            raise AsicError(
                f"source role SHA256 mismatch for {relative}: {actual} != {expected}")
        role_records.append({
            "path": relative,
            "sha256": actual,
            "source_commit": entry_commit,
            "identity": identity,
        })
    stale_support = sorted(set(support) - used_support)
    if stale_support:
        raise AsicError("ASIC support source is absent from the filelist: " +
                        ",".join(stale_support))
    used_overlay_paths = {
        record["path"] for record in role_records
        if record["identity"] == "audited_sram_functional_overlay"
    }
    if used_overlay_paths != set(selected_overlays):
        raise AsicError(
            "ASIC filelist does not consume the exact selected memory-mode overlays"
        )
    return {
        "sha256": sha256_json({
            "profile_source_commit": base_commit,
            "roles": role_records,
        }),
        "roles": role_records,
        "overlay_commits": sorted(overlay_commits),
    }


def safe_root_path(root: Path, relative: str) -> Path:
    path = (root / relative).resolve()
    try:
        path.relative_to(root)
    except ValueError as error:
        raise AsicError(f"path escapes public root: {relative}") from error
    return path


def read_filelist(root: Path, path: Path) -> Tuple[List[str], List[str], List[Path]]:
    includes: List[str] = []
    defines: List[str] = []
    sources: List[Path] = []
    if not path.is_file():
        raise AsicError(f"missing ASIC filelist: {path}")
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.split("//", 1)[0].strip()
        if not line:
            continue
        if line.startswith("+incdir+"):
            for item in line[len("+incdir+"):].split("+"):
                directory = safe_root_path(root, item)
                if not directory.is_dir():
                    raise AsicError(f"missing ASIC include directory: {item}")
                includes.append(item)
        elif line.startswith("+define+"):
            defines.append(line[len("+define+"):])
        elif line.startswith("+"):
            raise AsicError(f"unsupported ASIC filelist directive: {line}")
        else:
            source = safe_root_path(root, line)
            if not source.is_file():
                raise AsicError(f"missing ASIC source: {line}")
            sources.append(source)
    if not sources:
        raise AsicError("ASIC filelist contains no RTL")
    return includes, defines, sources


def resolve_mode(profile: str, source_commit: str, profile_data: dict,
                 requested: str) -> Tuple[str, Optional[Path]]:
    if profile != "rv32im_ooo_4k":
        if requested not in ("auto", "default"):
            raise AsicError(f"--ooo-mode is invalid for {profile}")
        expected = str(profile_data.get("source_commit", ""))
        if source_commit != expected:
            raise AsicError(f"source lock drift for {profile}: {source_commit} != {expected}")
        return "default", None
    variants = profile_data.get("source_variants", {})
    variant = variants.get(source_commit) if isinstance(variants, dict) else None
    if not isinstance(variant, dict):
        raise AsicError(f"unsupported OoO source commit for D7: {source_commit}")
    mode = str(variant.get("default_mode")) if requested == "auto" else requested
    allowed = variant.get("allowed_modes", [])
    if mode not in allowed:
        raise AsicError(f"OoO mode {mode} is not allowed for source {source_commit}")
    parameter_files = profile_data.get("elaboration_parameter_files", {})
    relative = parameter_files.get(mode) if isinstance(parameter_files, dict) else None
    if not relative:
        raise AsicError(f"missing parameter lock for OoO mode {mode}")
    return mode, Path(str(relative))


def check_parameter_lock(path: Path, mode: str) -> None:
    text = path.read_text(encoding="utf-8")
    if mode == "legacy":
        for required in ("TARGET_LINE_ENTRY_COUNT=512", "TARGET_LINE_WAY_COUNT=1",
                         "DATA_LINE_COUNT=1024", "DATA_LINE_WAY_COUNT=1"):
            if required not in text:
                raise AsicError(f"OoO production parameter lock lacks {required}")
    elif mode in ("a3_split_off", "a3"):
        if "rv32im_ooo_4k_legacy.tcl" not in text:
            raise AsicError(f"{mode} must inherit the complete legacy parameter lock")
        expected = {
            "a3_split_off": ("STABLE_ENTRY_IQ_ENABLE=0", "IQ_SPLIT_PAYLOAD_READ_ENABLE=0",
                             "ROB_INDEXED_SERVICE_LEVEL=0"),
            "a3": ("STABLE_ENTRY_IQ_ENABLE=1", "IQ_SPLIT_PAYLOAD_READ_ENABLE=1",
                   "ROB_INDEXED_SERVICE_LEVEL=1"),
        }[mode]
        for required in expected:
            if required not in text:
                raise AsicError(f"{mode} parameter lock lacks {required}")


def build_contract(root: Path, config_path: Path, requested_mode: str,
                   requested_memory_mode: str = "auto") -> dict:
    config = parse_config(config_path)
    profile = selected_profile(config)
    matrix = load_json(root / MANIFEST_REL)
    if matrix.get("schema") != "npc-riscv-open/asic-dual-memory-v1":
        raise AsicError("ASIC matrix schema mismatch")
    profile_data = matrix.get("profiles", {}).get(profile)
    if not isinstance(profile_data, dict):
        raise AsicError(f"ASIC matrix lacks {profile}")
    source = source_record(root, profile)
    memory_mode, memory_data = resolve_memory_mode(
        config, matrix, profile, requested_memory_mode)
    source_commit = str(source.get("source_commit", ""))
    if re.fullmatch(r"[0-9a-f]{40}", source_commit) is None:
        raise AsicError("source allowlist has no fixed commit")
    mode, parameter_relative = resolve_mode(
        profile, source_commit, profile_data, requested_mode.replace("-", "_"))
    filelists = profile_data.get("filelists_by_memory_mode", {})
    filelist_value = (
        filelists.get(memory_mode) if isinstance(filelists, dict) else None
    ) or profile_data.get("filelist")
    if not isinstance(filelist_value, str) or not filelist_value:
        raise AsicError(f"ASIC matrix lacks a {memory_mode} filelist for {profile}")
    filelist = safe_root_path(root, filelist_value)
    includes, defines, sources = read_filelist(root, filelist)
    if "NPC_ASIC" not in defines:
        raise AsicError("ASIC filelist must define NPC_ASIC")
    forbidden = [define for define in defines
                 if any(define == prefix or define.startswith(prefix) for prefix in FORBIDDEN_DEFINES)]
    if forbidden:
        raise AsicError("DPI defines are forbidden in ASIC filelists: " + ",".join(forbidden))
    if any("wrappers/" in path.as_posix() for path in sources):
        raise AsicError("simulation wrapper leaked into ASIC filelist")
    top = str(profile_data["top"])
    top_pattern = re.compile(r"\bmodule\s+" + re.escape(top) + r"\b")
    top_sources = [path for path in sources if top_pattern.search(path.read_text(errors="ignore"))]
    if len(top_sources) != 1:
        raise AsicError(f"ASIC source set must declare top {top} exactly once")
    top_text = top_sources[0].read_text(encoding="utf-8", errors="replace")
    expected_ports = {
        "rv32im_single_perf": ("ibus_axi_araddr", "ibus_axi_rdata", "dbus_axi_awaddr", "dbus_axi_rdata"),
        "rv32ima_sv32_linux": ("ibus_axi_araddr", "ibus_axi_rdata", "dbus_axi_awaddr", "dbus_axi_rdata"),
        "rv32im_ooo_4k": ("if_req_valid_o", "if_rsp_valid_i", "fetch_pte_req_valid_o",
                           "mem_req_valid_o", "mem_rsp_valid_i"),
    }[profile]
    missing_ports = [name for name in expected_ports if re.search(r"\b" + name + r"\b", top_text) is None]
    if missing_ports:
        raise AsicError("ASIC external-memory interface lacks " + ",".join(missing_ports))
    source_roles = source_role_identity(
        root, source, sources, profile_data, memory_mode
    )
    extra_defines = memory_data.get("extra_defines", [])
    if not isinstance(extra_defines, list) or any(
            not isinstance(item, str) or not item for item in extra_defines):
        raise AsicError(f"invalid extra defines for memory mode {memory_mode}")
    if ((memory_mode == "sram") != ("NPC_ASIC_SRAM" in extra_defines)):
        raise AsicError("NPC_ASIC_SRAM must be enabled exactly for memory_mode=sram")
    implementation_source_hash = sha256_json({
        "source_role_sha256": source_roles["sha256"],
        "memory_mode": memory_mode,
        "extra_defines": extra_defines,
    })
    parameter_file: Optional[Path] = None
    if parameter_relative is not None:
        parameter_file = safe_root_path(root, parameter_relative.as_posix())
        if not parameter_file.is_file():
            raise AsicError(f"missing OoO parameter lock: {parameter_relative}")
        check_parameter_lock(parameter_file, mode)
    logical_entries = {
        str(entry.get("destination")): str(entry.get("sha256"))
        for entry in source.get("entries", []) if isinstance(entry, dict)
    }
    for overlay in source.get("memory_mode_overlays", []):
        if isinstance(overlay, dict) and overlay.get("memory_mode") == memory_mode:
            logical_entries[str(overlay.get("logical_destination"))] = str(
                overlay.get("sha256")
            )
    source_hash = sha256_json({
        "source_commit": source_commit,
        "entries": sorted(logical_entries.items()),
    })
    source_sets = source.get("implementation_source_sets", {})
    selected_source_set = (
        source_sets.get(memory_mode) if isinstance(source_sets, dict) else None
    )
    if (not isinstance(selected_source_set, dict) or
            selected_source_set.get("source_set_sha256") != source_hash):
        raise AsicError(
            f"audited implementation source-set mismatch for {profile}/{memory_mode}"
        )
    config_hash = sha256_json({
        "profile": profile,
        "mode": mode,
        "memory_mode": memory_mode,
        "memory_contract": memory_data,
        "filelist_sha256": sha256_file(filelist),
        "parameter_sha256": sha256_file(parameter_file) if parameter_file else None,
        "constraint_sha256": sha256_file(root / "flows/asic/constraints/internal_clock.sdc"),
        "defines": defines,
        "filelist_source_sha256": [(path.relative_to(root).as_posix(), sha256_file(path))
                                   for path in sources],
    })
    pnr_frequencies = profile_data.get("pnr_frequencies_mhz", {})
    if not isinstance(pnr_frequencies, dict):
        raise AsicError("pnr_frequencies_mhz must be an object")
    pnr_frequency = pnr_frequencies.get(memory_mode)
    if pnr_frequency is not None and (
            not isinstance(pnr_frequency, int) or pnr_frequency <= 0):
        raise AsicError(f"invalid P&R frequency for memory mode {memory_mode}")
    return {
        "profile": profile,
        "mode": mode,
        "memory_mode": memory_mode,
        "memory_data": memory_data,
        "expected_macro_count": int(memory_data["expected_macro_count"]),
        "expected_blackbox_count": int(memory_data["expected_blackbox_count"]),
        "source_commit": source_commit,
        "source_set_sha256": source_hash,
        "source_role_sha256": source_roles["sha256"],
        "implementation_source_sha256": implementation_source_hash,
        "source_roles": source_roles["roles"],
        "source_overlay_commits": source_roles["overlay_commits"],
        "config_sha256": config_hash,
        "top": top,
        "clock_port": str(profile_data["clock_port"]),
        "reset_port": str(profile_data["reset_port"]),
        "filelist": filelist,
        "parameter_file": parameter_file,
        "frequencies_mhz": [int(value) for value in profile_data.get(
            "sram_dc_frequencies_mhz" if memory_mode == "sram" else "dc_frequencies_mhz", [])],
        "pnr_frequency_mhz": pnr_frequency,
        "navigation_quantum_mhz": int(memory_data.get(
            "dc_navigation_quantum_mhz", matrix.get("dc_navigation_quantum_mhz", 10))),
        "dc_max_points": int(memory_data.get("dc_max_points", 0)),
        "matrix": matrix,
        "defines": defines,
        "sources": sources,
        "includes": includes,
    }


def utc_id() -> str:
    return dt.datetime.now(dt.timezone.utc).strftime("%Y%m%dT%H%M%SZ")


UTC_RUN_ID_RE = re.compile(r"[0-9]{8}T[0-9]{6}Z")


def resolve_lc_output(root: Path, requested: str, dry_run: bool) -> Path:
    environment_value = os.environ.get("NPC_ASIC_LC_OUTPUT", "").strip()
    requested_value = str(requested or "").strip()
    if requested_value and environment_value:
        requested_path = Path(requested_value).expanduser()
        environment_path = Path(environment_value).expanduser()
        if requested_path != environment_path:
            raise AsicError("--output disagrees with NPC_ASIC_LC_OUTPUT")
    value = requested_value or environment_value
    if not value:
        if not dry_run:
            raise AsicError(
                "real lc-macros requires explicit NPC_ASIC_LC_OUTPUT or --output")
        return (root / "build/asic/lc-macros-dry-run/YYYYMMDDTHHMMSSZ").resolve()
    candidate = Path(value).expanduser()
    output = (candidate if candidate.is_absolute() else root / candidate).resolve()
    if not dry_run and not any(UTC_RUN_ID_RE.fullmatch(part) for part in output.parts):
        raise AsicError("Library Compiler output must contain a UTC timestamp YYYYMMDDTHHMMSSZ")
    return output


def split_tool(value: str) -> List[str]:
    result = shlex.split(value)
    if not result:
        raise AsicError("empty tool command")
    return result


def require_tool(value: str) -> List[str]:
    command = split_tool(value)
    if shutil.which(command[0]) is None and not Path(command[0]).is_file():
        raise AsicError(f"tool executable not found: {command[0]}")
    return command


def require_hash(path: Path, expected: str, role: str) -> None:
    if not path.is_file():
        raise AsicError(f"missing {role}: {path}")
    actual = sha256_file(path)
    if actual != expected:
        raise AsicError(f"{role} SHA256 mismatch: {actual} != {expected}")


def write_json(path: Path, value: object) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def manifest_file(root: Path, record: dict, role: str) -> Path:
    relative = record.get("path")
    if not isinstance(relative, str) or not relative or Path(relative).is_absolute():
        raise AsicError(f"invalid handoff path for {role}")
    path = (root / relative).resolve()
    try:
        path.relative_to(root.resolve())
    except ValueError as error:
        raise AsicError(f"handoff path escapes root for {role}") from error
    require_hash(path, str(record.get("sha256", "")), role)
    return path


def load_sram_handoff(contract: dict) -> dict:
    location = os.environ.get("NPC_ASIC_SRAM_HANDOFF", "")
    if not location:
        raise AsicError("SRAM mode requires NPC_ASIC_SRAM_HANDOFF")
    candidate = Path(location).expanduser().resolve()
    manifest_path = candidate / "handoff_manifest.json" if candidate.is_dir() else candidate
    manifest = load_json(manifest_path)
    if manifest.get("schema") != "npc-riscv-open/d8-sram-handoff-v2":
        raise AsicError("SRAM handoff schema mismatch")
    if manifest.get("memory_mode") != "sram":
        raise AsicError("SRAM handoff memory mode mismatch")
    expected = contract["memory_data"]
    if manifest.get("openram_commit") != expected.get("openram_commit"):
        raise AsicError("SRAM handoff OpenRAM commit mismatch")
    if int(manifest.get("macro_count", -1)) != contract["expected_macro_count"]:
        raise AsicError("SRAM handoff macro count mismatch")
    if manifest.get("liberty_override") != expected.get("liberty_override"):
        raise AsicError("SRAM handoff Liberty override contract mismatch")
    root = manifest_path.parent
    macros = manifest.get("macros", {})
    if set(macros) != set(expected.get("macros", {})):
        raise AsicError("SRAM handoff macro family mismatch")
    resolved = {}
    for name, expected_macro in expected["macros"].items():
        record = macros[name]
        if int(record.get("expected_instances", -1)) != int(expected_macro["expected_instances"]):
            raise AsicError(f"{name}: expected instance count mismatch")
        files = record.get("files", {})
        resolved[name] = {
            role: manifest_file(root, files[role], f"{name} {role}")
            for role in ("v", "lib", "canonical_lib", "lef", "gds", "normalized_lef")
        }
        original_hashes = expected_macro["original_view_sha256"]
        for role in ("v", "lef", "gds"):
            if files[role].get("sha256") != original_hashes[role]:
                raise AsicError(f"{name}: tracked {role} identity mismatch")
        if files.get("canonical_lib", {}).get("sha256") != original_hashes["lib"]:
            raise AsicError(f"{name}: canonical Liberty identity mismatch")
        if files["lib"].get("sha256") != expected_macro["timing_view_sha256"]:
            raise AsicError(f"{name}: timing Liberty identity mismatch")
    return {
        "manifest": manifest,
        "manifest_path": manifest_path,
        "manifest_sha256": sha256_file(manifest_path),
        "files": resolved,
    }


def load_macro_db_manifest(contract: dict, handoff: dict) -> dict:
    location = os.environ.get("NPC_ASIC_MACRO_DB_MANIFEST", "")
    if not location:
        raise AsicError("SRAM DC/STA requires NPC_ASIC_MACRO_DB_MANIFEST")
    path = Path(location).expanduser().resolve()
    record = load_json(path)
    if record.get("schema") != "npc-riscv-open/d8-lc-output-v1":
        raise AsicError("Library Compiler manifest schema mismatch")
    if record.get("handoff_manifest_sha256") != handoff["manifest_sha256"]:
        raise AsicError("Library Compiler manifest is not bound to this SRAM handoff")
    files = {}
    for name in contract["memory_data"]["macros"]:
        item = record.get("macros", {}).get(name)
        if not isinstance(item, dict):
            raise AsicError(f"Library Compiler manifest lacks {name}")
        files[name] = manifest_file(path.parent, item["db"], f"{name} DB")
    return {"manifest": record, "manifest_path": path, "files": files}


def lc_macros(root: Path, config_path: Path, args: argparse.Namespace) -> int:
    contract = build_contract(root, config_path, args.ooo_mode, args.memory_mode)
    if contract["memory_mode"] != "sram":
        if args.dry_run:
            print(
                "ASIC_LC_MACROS_DRY_RUN_NOT_APPLICABLE "
                f"profile={contract['profile']} memory=registers"
            )
            print("ASIC_LC_MACROS_DRY_RUN_PASS")
            return 0
        raise AsicError("lc-macros is only valid for memory_mode=sram")
    output = resolve_lc_output(root, args.output, args.dry_run)
    tool_value = os.environ.get("NPC_ASIC_LC_SHELL", "lc_shell")
    command = [*split_tool(tool_value), "-f",
               str(root / "flows/asic/library_compiler/run.tcl")]
    print(f"ASIC_LC_MACROS profile={contract['profile']} output={output}")
    print("lc_command: " + " ".join(shlex.quote(item) for item in command))
    print("macro_families: " + ",".join(sorted(contract["memory_data"]["macros"])))
    if args.dry_run:
        print("ASIC_LC_MACROS_DRY_RUN_PASS")
        return 0
    if output.exists():
        raise AsicError(f"refusing to overwrite Library Compiler output: {output}")
    handoff = load_sram_handoff(contract)
    tool = require_tool(tool_value)
    output.mkdir(parents=True)
    macros = {}
    for name in sorted(contract["memory_data"]["macros"]):
        liberty = handoff["files"][name]["lib"]
        text = liberty.read_text(encoding="utf-8", errors="replace")
        match = re.search(r"\blibrary\s*\(\s*([^\s)]+)\s*\)", text)
        if match is None:
            raise AsicError(f"{name}: Liberty library name not found")
        db = output / f"{name}.db"
        log_path = output / f"{name}.lc.log"
        environment = os.environ.copy()
        environment.update({
            "LC_ALL": "C",
            "NPC_ASIC_MACRO_LIBERTY": str(liberty),
            "NPC_ASIC_MACRO_LIBRARY_NAME": match.group(1),
            "NPC_ASIC_MACRO_DB": str(db),
        })
        with log_path.open("w", encoding="utf-8") as log:
            completed = subprocess.run(
                [*tool, "-f", str(root / "flows/asic/library_compiler/run.tcl")],
                cwd=output, env=environment, stdout=log, stderr=subprocess.STDOUT,
                check=False)
        if completed.returncode != 0 or not db.is_file() or db.stat().st_size == 0:
            raise AsicError(f"Library Compiler failed for {name}; log={log_path}")
        macros[name] = {
            "liberty_sha256": sha256_file(liberty),
            "library_name": match.group(1),
            "db": {
                "path": db.relative_to(output).as_posix(),
                "sha256": sha256_file(db),
                "bytes": db.stat().st_size,
            },
            "log_sha256": sha256_file(log_path),
        }
    manifest = {
        "schema": "npc-riscv-open/d8-lc-output-v1",
        "profile": contract["profile"],
        "memory_mode": "sram",
        "run_id": next(part for part in reversed(output.parts)
                       if UTC_RUN_ID_RE.fullmatch(part)),
        "source_commit": contract["source_commit"],
        "source_set_sha256": contract["source_set_sha256"],
        "source_role_sha256": contract["source_role_sha256"],
        "implementation_source_sha256": contract["implementation_source_sha256"],
        "config_sha256": contract["config_sha256"],
        "handoff_manifest_sha256": handoff["manifest_sha256"],
        "macros": macros,
    }
    write_json(output / "lc_manifest.json", manifest)
    print(f"ASIC_LC_MACROS_PASS manifest={output / 'lc_manifest.json'}")
    return 0


def stage_sram_views(run: Path, contract: dict, handoff: dict) -> dict:
    destination = run / "input/macro_views"
    destination.mkdir(parents=True, exist_ok=True)
    result = {"lib": [], "lef": [], "gds": []}
    for name in sorted(contract["memory_data"]["macros"]):
        for source_role, output_role in (("lib", "lib"), ("normalized_lef", "lef"),
                                         ("gds", "gds")):
            source = handoff["files"][name][source_role]
            target = destination / source.name
            shutil.copy2(source, target)
            result[output_role].append(target)
    return result


def write_macro_placement(path: Path, floorplan: dict) -> None:
    placements = floorplan.get("macro_placements", [])
    refs = sorted({str(item["ref"]) for item in placements})
    lines = [
        "set npc_macro_report [open $::env(NPC_ASIC_MACRO_PLACEMENT_REPORT) w]",
        "set npc_block [ord::get_db_block]",
        "puts $npc_macro_report \"schema=npc-riscv-open/d8-macro-placement-v1\"",
    ]
    ref_variables = {ref: f"npc_names_{index}" for index, ref in enumerate(refs)}
    for ref in refs:
        lines.append(f"set {ref_variables[ref]} [list]")
    lines.extend([
        "foreach npc_inst [$npc_block getInsts] {",
        "  set npc_ref [[$npc_inst getMaster] getName]",
    ])
    for ref in refs:
        lines.append(
            f"  if {{$npc_ref eq \"{ref}\"}} {{lappend {ref_variables[ref]} [$npc_inst getName]}}")
    lines.append("}")
    for ref in refs:
        expected = sum(1 for item in placements if item["ref"] == ref)
        variable = ref_variables[ref]
        lines.extend([
            f"set {variable} [lsort ${variable}]",
            f"if {{[llength ${variable}] != {expected}}} {{",
            f"  error \"Expected {expected} macros of {ref}, found [llength ${variable}]\"",
            "}",
        ])
        for index, item in enumerate(item for item in placements if item["ref"] == ref):
            x = float(item["x_um"])
            y = float(item["y_um"])
            width = float(item["width_um"])
            height = float(item["height_um"])
            orientation = str(item["orientation"])
            lines.extend([
                f"set npc_name [lindex ${variable} {index}]",
                f"place_macro -macro_name $npc_name -location {{{x:.3f} {y:.3f}}} -orientation {orientation}",
                (f"puts $npc_macro_report \"instance=$npc_name ref={ref} "
                 f"x_um={x:.3f} y_um={y:.3f} width_um={width:.3f} "
                 f"height_um={height:.3f} bbox_um={x:.3f},{y:.3f},"
                 f"{x + width:.3f},{y + height:.3f} orientation={orientation}\""),
            ])
    lines.extend(["close $npc_macro_report", ""])
    path.write_text("\n".join(lines), encoding="ascii")


def parse_frequency_list(raw: str, defaults: Iterable[int]) -> List[int]:
    if not raw:
        values = list(defaults)
    else:
        values = [int(item) for item in raw.split(",") if item]
    if not values or any(value <= 0 for value in values) or len(set(values)) != len(values):
        raise AsicError("frequencies must be unique positive comma-separated MHz values")
    if values != sorted(values, reverse=True):
        raise AsicError("frequencies must be listed in strictly descending order")
    return values


def wns_navigation_eligible(row: dict) -> bool:
    """Return true only when lowering the clock addresses the sole failed gate."""
    required_zero = (
        "timing_loop_evidence", "automatic_arc_break_evidence",
        "electrical_violations", "check_design_errors", "unresolved_reference_count",
        "latch_count", "unclocked_sync_endpoint_count",
    )
    return bool(
        row.get("completed") and not row.get("missing_gate_fields") and
        row.get("timing_loop_report_valid") and
        all(row.get(key) == 0 for key in required_zero) and
        row.get("macro_count") == row.get("expected_macro_count", 0) and
        row.get("blackbox_count") == row.get("expected_blackbox_count", 0) and
        row.get("check_design_ok") == 1 and row.get("check_timing_ok") == 1 and
        row.get("wns_ns") is not None and float(row["wns_ns"]) < -0.0005 and
        row.get("tns_ns") is not None and float(row["tns_ns"]) < -0.0005 and
        row.get("violating_paths") is not None and int(row["violating_paths"]) > 0
    )


def dc_frequency_decision(frequencies: List[int], current: int, row: dict,
                          quantum_mhz: int = 10) -> dict:
    """Choose a quantized point below the Fmax estimated from setup WNS."""
    if quantum_mhz <= 0:
        raise AsicError("DC navigation quantum must be positive")
    floor_mhz = min(frequencies)
    remaining = [frequency for frequency in frequencies if frequency < current]
    base = {
        "frequency_mhz": current,
        "frequency_floor_mhz": floor_mhz,
        "navigation_quantum_mhz": quantum_mhz,
        "period_ns": row.get("period_ns"),
        "wns_ns": row.get("wns_ns"),
        "next_frequency_mhz": None,
        "skipped_frequencies_mhz": [],
        "estimated_required_period_ns": None,
        "estimated_fmax_mhz": None,
    }
    if row.get("setup_closed"):
        base.update({
            "action": "stop_closed",
            "reason": "highest_executed_candidate_is_setup_closed",
            "skipped_frequencies_mhz": remaining,
        })
        return base
    if not wns_navigation_eligible(row):
        base.update({
            "action": "stop_non_setup_failure",
            "reason": "result_is_not_a_clean_setup_only_failure",
            "skipped_frequencies_mhz": remaining,
        })
        return base

    period = float(row["period_ns"])
    wns = float(row["wns_ns"])
    required_period = period - wns
    if not math.isfinite(required_period) or required_period <= 0.0:
        base.update({
            "action": "stop_invalid_estimate",
            "reason": "period_minus_wns_is_not_positive_and_finite",
            "skipped_frequencies_mhz": remaining,
        })
        return base
    estimate = 1000.0 / required_period
    base["estimated_required_period_ns"] = round(required_period, 9)
    base["estimated_fmax_mhz"] = round(estimate, 6)
    next_frequency = int(math.floor((estimate + 1.0e-9) / quantum_mhz) * quantum_mhz)
    if next_frequency >= current:
        next_frequency = current - quantum_mhz
    base["quantized_fmax_mhz"] = next_frequency
    if next_frequency < floor_mhz:
        base.update({
            "action": "stop_below_candidate_floor",
            "reason": "quantized_wns_estimate_is_below_frequency_floor",
            "skipped_frequencies_mhz": remaining,
        })
        return base

    base.update({
        "action": "run_quantized_wns_candidate",
        "reason": "floor_wns_estimated_fmax_to_navigation_quantum",
        "next_frequency_mhz": next_frequency,
        "skipped_frequencies_mhz": [
            frequency for frequency in remaining if next_frequency < frequency < current
        ],
    })
    return base


def dc_matrix(root: Path, config_path: Path, args: argparse.Namespace) -> int:
    contract = build_contract(root, config_path, args.ooo_mode, args.memory_mode)
    if args.timer_clock_hz is not None:
        if contract["profile"] != "rv32ima_sv32_linux":
            raise AsicError("--timer-clock-hz is only valid for the Linux Profile")
        if args.timer_clock_hz <= 0:
            raise AsicError("--timer-clock-hz must be positive")
    frequencies = parse_frequency_list(args.frequencies, contract["frequencies_mhz"])
    quantum_mhz = contract["navigation_quantum_mhz"]
    if quantum_mhz <= 0:
        raise AsicError("dc_navigation_quantum_mhz must be positive")
    build_root = Path(args.build_root).resolve() if args.build_root else root / "build/asic"
    run_id = args.run_id or utc_id()
    matrix_root = (build_root / contract["profile"] / contract["mode"] /
                   contract["memory_mode"] / "dc" / run_id)
    tool_value = os.environ.get("NPC_ASIC_DC_SHELL", "dc_shell")
    command = [*split_tool(tool_value), "-f", str(root / "flows/asic/dc/run.tcl")]
    print("ASIC_DC_MATRIX profile={} mode={} memory={} source={} run_id={} policy=wns_quantized".format(
        contract["profile"], contract["mode"], contract["memory_mode"],
        contract["source_commit"], run_id))
    print("dc_initial_candidate_{}mhz: {}".format(
        frequencies[0], " ".join(shlex.quote(item) for item in command)))
    print("dc_navigation_quantum_mhz={} dc_frequency_floor_mhz={}".format(
        quantum_mhz, min(frequencies)))
    if contract["profile"] == "rv32ima_sv32_linux":
        fixed_pnr_mhz = contract.get("pnr_frequency_mhz")
        required_timer_hz = (
            fixed_pnr_mhz * 1_000_000 if fixed_pnr_mhz is not None else None
        )
        if args.timer_clock_hz is None:
            if required_timer_hz is not None:
                print(
                    "linux_timer_contract=scan_uses_rtl_default; "
                    "final_handoff_requires=ASIC_DC_ARGS=\"--timer-clock-hz {}\" "
                    "make dc-matrix".format(required_timer_hz)
                )
            else:
                print(
                    "linux_timer_contract=scan_uses_rtl_default; "
                    "final_handoff_requires=--timer-clock-hz_<pnr_mhz_x_1000000>"
                )
        else:
            print(
                "linux_timer_contract=explicit timer_clock_hz={} "
                "audited_fixed_point_timer_hz={}".format(
                    args.timer_clock_hz,
                    required_timer_hz if required_timer_hz is not None else "NA",
                )
            )
    if args.dry_run:
        print("ASIC_DC_MATRIX_DRY_RUN_PASS")
        return 0

    tool = require_tool(tool_value)
    liberty = Path(os.environ.get("NPC_ASIC_STDCELL_LIBERTY", "")).expanduser().resolve()
    database = Path(os.environ.get("NPC_ASIC_STDCELL_DB", "")).expanduser().resolve()
    setup = Path(os.environ.get(
        "NPC_ASIC_DC_SETUP", root / "flows/local/asic/dc_setup.tcl")).resolve()
    library_data = contract["matrix"]["libraries"]
    require_hash(liberty, str(library_data["liberty_sha256"]), "Nangate45 Liberty")
    require_hash(database, str(library_data["db_sha256"]), "Nangate45 DB")
    if not setup.is_file():
        raise AsicError(f"missing local DC setup: {setup}")
    handoff = None
    macro_dbs = None
    if contract["memory_mode"] == "sram":
        handoff = load_sram_handoff(contract)
        macro_dbs = load_macro_db_manifest(contract, handoff)
    if matrix_root.exists():
        raise AsicError(f"refusing to overwrite existing DC matrix: {matrix_root}")
    matrix_root.mkdir(parents=True)
    compile_recipe = (
        "compile_ultra_then_incremental_mapping_then_sram_icache_din_isolation_v2"
        if contract["memory_mode"] == "sram"
        else "compile_ultra_then_incremental_mapping_v1"
    )
    input_manifest = {
        "schema": "npc-riscv-open/d8-dc-input-v1",
        "profile": contract["profile"], "mode": contract["mode"],
        "source_commit": contract["source_commit"],
        "source_set_sha256": contract["source_set_sha256"],
        "source_role_sha256": contract["source_role_sha256"],
        "implementation_source_sha256": contract["implementation_source_sha256"],
        "source_overlay_commits": contract["source_overlay_commits"],
        "config_sha256": contract["config_sha256"],
        "frequencies_mhz": frequencies,
        "frequency_start_mhz": frequencies[0],
        "frequency_floor_mhz": min(frequencies),
        "navigation_quantum_mhz": quantum_mhz,
        "scan_policy": "wns_guided_quantized_v2",
        "compile_recipe": compile_recipe,
        "wns_estimate_formula": "estimated_fmax_mhz=1000/(period_ns-wns_ns)",
        "next_frequency_formula": "floor(estimated_fmax_mhz/navigation_quantum_mhz)*navigation_quantum_mhz",
        "memory_mode": contract["memory_mode"],
        "expected_macro_count": contract["expected_macro_count"],
        "expected_blackbox_count": contract["expected_blackbox_count"],
        "liberty_sha256": sha256_file(liberty), "db_sha256": sha256_file(database),
        "timer_clock_hz": args.timer_clock_hz,
        "files": {
            "constraint_sdc": {
                "path": str(root / "flows/asic/constraints/internal_clock.sdc"),
                "sha256": sha256_file(root / "flows/asic/constraints/internal_clock.sdc"),
            },
            "dc_setup": {"path": str(setup), "sha256": sha256_file(setup)},
            "stdcell_liberty": {"path": str(liberty), "sha256": sha256_file(liberty)},
            "stdcell_db": {"path": str(database), "sha256": sha256_file(database)},
        },
    }
    if contract["parameter_file"]:
        input_manifest["files"]["elaboration_parameters"] = {
            "path": str(contract["parameter_file"]),
            "sha256": sha256_file(contract["parameter_file"]),
        }
    if handoff is not None and macro_dbs is not None:
        isolation_hook = root / "flows/asic/dc/sram_input_isolation.tcl"
        if not isolation_hook.is_file():
            raise AsicError(f"missing SRAM input isolation hook: {isolation_hook}")
        input_manifest["sram_handoff_manifest_sha256"] = handoff["manifest_sha256"]
        input_manifest["files"]["sram_input_isolation_hook"] = {
            "path": str(isolation_hook), "sha256": sha256_file(isolation_hook),
        }
        input_manifest["files"]["sram_handoff_manifest"] = {
            "path": str(handoff["manifest_path"]), "sha256": handoff["manifest_sha256"],
        }
        input_manifest["files"]["macro_db_manifest"] = {
            "path": str(macro_dbs["manifest_path"]),
            "sha256": sha256_file(macro_dbs["manifest_path"]),
        }
        for name, path in sorted(macro_dbs["files"].items()):
            input_manifest["files"][f"macro_db_{name}"] = {
                "path": str(path), "sha256": sha256_file(path),
            }
    write_json(matrix_root / "input_manifest.json", input_manifest)
    failed_tools = 0
    rows: List[dict] = []
    decisions: List[dict] = []
    frequency: Optional[int] = frequencies[0]
    while frequency is not None:
        run = matrix_root / f"dc_{frequency}mhz"
        run.mkdir()
        period = 1000.0 / frequency
        extra_defines: List[str] = list(contract["memory_data"].get("extra_defines", []))
        if args.timer_clock_hz is not None:
            extra_defines.extend([
                f"NPC_TIMER_CLK_HZ={args.timer_clock_hz}", "NPC_TIMEBASE_HZ=1000000",
            ])
        environment = os.environ.copy()
        environment.update({
            "LC_ALL": "C",
            "NPC_ASIC_ROOT": str(root),
            "NPC_ASIC_PROFILE": contract["profile"],
            "NPC_ASIC_TOP": contract["top"],
            "NPC_ASIC_FILELIST": str(contract["filelist"]),
            "NPC_ASIC_SDC": str(root / "flows/asic/constraints/internal_clock.sdc"),
            "NPC_ASIC_OUTPUT_DIR": str(run),
            "NPC_ASIC_DC_SETUP": str(setup),
            "NPC_ASIC_STDCELL_DB": str(database),
            "NPC_ASIC_CLOCK_PERIOD_NS": f"{period:.9f}",
            "NPC_ASIC_CLOCK_PORT": contract["clock_port"],
            "NPC_ASIC_RESET_PORT": contract["reset_port"],
            "NPC_ASIC_EXTRA_DEFINES": ",".join(extra_defines),
            "NPC_ASIC_PARAMETER_FILE": str(contract["parameter_file"] or ""),
            "NPC_ASIC_MEMORY_MODE": contract["memory_mode"],
            "NPC_ASIC_EXPECTED_MACRO_COUNT": str(contract["expected_macro_count"]),
            "NPC_ASIC_EXPECTED_BLACKBOX_COUNT": str(contract["expected_blackbox_count"]),
            "NPC_ASIC_EXPECTED_MACROS": ",".join(
                f"{name}={data['expected_instances']}"
                for name, data in sorted(contract["memory_data"].get("macros", {}).items())),
            "NPC_ASIC_MACRO_DBS": os.pathsep.join(
                str(path) for path in (macro_dbs["files"].values() if macro_dbs else [])),
        })
        with (run / "dc.log").open("w", encoding="utf-8") as log:
            completed = subprocess.run(
                [*tool, "-f", str(root / "flows/asic/dc/run.tcl")],
                cwd=run, env=environment, stdout=log, stderr=subprocess.STDOUT,
                check=False,
            )
        (run / "exit_status.txt").write_text(str(completed.returncode) + "\n")
        mapped = run / f"{contract['top']}_mapped.v"
        if completed.returncode == 0 and mapped.is_file():
            (run / "run.ok").write_text("DC_RUN_COMPLETED\n")
        else:
            failed_tools += 1
        row = parse_run(run)
        rows.append(row)
        decision = dc_frequency_decision(frequencies, frequency, row, quantum_mhz)
        decisions.append(decision)
        if contract["dc_max_points"] and len(decisions) >= contract["dc_max_points"]:
            if decision["next_frequency_mhz"] is not None:
                decision["budgeted_next_frequency_mhz"] = decision["next_frequency_mhz"]
                decision["next_frequency_mhz"] = None
                decision["action"] = "stop_point_budget_exhausted"
                decision["reason"] = "memory_mode_dc_max_points_reached"
        print("ASIC_DC_STEP frequency_mhz={} wns_ns={} action={} next_mhz={} skipped={}".format(
            frequency, row.get("wns_ns"), decision["action"],
            decision["next_frequency_mhz"], decision["skipped_frequencies_mhz"]))
        frequency = decision["next_frequency_mhz"]
    scan = {
        "policy": "wns_guided_quantized_v2",
        "frequency_anchors_mhz": frequencies,
        "navigation_quantum_mhz": quantum_mhz,
        "executed_frequencies_mhz": [int(decision["frequency_mhz"])
                                     for decision in decisions],
        "decisions": decisions,
        "stop_action": decisions[-1]["action"] if decisions else "no_run",
        "stop_reason": decisions[-1]["reason"] if decisions else "no_run",
    }
    write_json(matrix_root / "scan_decisions.json", scan)
    write_json(matrix_root / "summary.json", {
        "input": input_manifest, "scan": scan, "runs": rows,
    })
    if rows:
        import csv
        with (matrix_root / "summary.csv").open("w", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=list(rows[0]))
            writer.writeheader(); writer.writerows(rows)
    closed = [row for row in rows if row["setup_closed"]]
    selected = max(closed, key=lambda row: row["frequency_mhz"]) if closed else None
    write_json(matrix_root / "verdict.json", {
        "status": "DC_CLOSED_POINT_AVAILABLE" if selected else "DC_NO_CLOSED_POINT",
        "selected": selected, "tool_failures": failed_tools,
        "scan_policy": scan["policy"], "stop_action": scan["stop_action"],
        "stop_reason": scan["stop_reason"],
    })
    print("ASIC_DC_MATRIX_COMPLETE root={} closed_points={} tool_failures={} executed={}".format(
        matrix_root, len(closed), failed_tools, scan["executed_frequencies_mhz"]))
    return 0 if failed_tools == 0 else 2


def pnr(root: Path, config_path: Path, args: argparse.Namespace) -> int:
    contract = build_contract(root, config_path, args.ooo_mode, args.memory_mode)
    orfs_identity = require_orfs_runtime_identity(contract["matrix"])
    if args.dry_run:
        predecessor = str(args.dc_run).strip() or "<setup-closed-dc-run>"
        print(
            "ASIC_PNR_DRY_RUN_CONTRACT "
            f"profile={contract['profile']} mode={contract['mode']} "
            f"memory={contract['memory_mode']} macros={contract['expected_macro_count']} "
            f"dc_run={predecessor} orfs_commit={orfs_identity['commit']} "
            f"orfs_image_digest={orfs_identity['image_digest']} "
            f"orfs_identity_policy={orfs_identity['runtime_identity_policy']}"
        )
        print(
            "required_roles=dc_input_manifest,dc_mapped_netlist,dc_mapped_sdc,"
            "setup_closed_summary,standard_cell_library_identity"
        )
        print("required_identity=" + ",".join(HANDOFF_IDENTITY_FIELDS))
        print(
            "pnr_command: bash "
            + str(root / "flows/asic/openroad/run.sh")
        )
        print("ASIC_PNR_DRY_RUN_PASS")
        return 0
    if not str(args.dc_run).strip():
        raise AsicError("real P&R requires --dc-run with a setup-closed DC handoff")
    dc_run = Path(args.dc_run).resolve()
    dc_input_path = dc_run.parent / "input_manifest.json"
    dc_input = load_json(dc_input_path)
    if dc_input.get("schema") not in (
            "npc-riscv-open/d7-dc-input-v1", "npc-riscv-open/d8-dc-input-v1"):
        raise AsicError("P&R requires a recognized DC input manifest")
    dc_identity = {
        "profile": contract["profile"],
        "mode": contract["mode"],
        "memory_mode": contract["memory_mode"],
        "source_commit": contract["source_commit"],
        "source_set_sha256": contract["source_set_sha256"],
        "source_role_sha256": contract["source_role_sha256"],
        "implementation_source_sha256": contract["implementation_source_sha256"],
        "config_sha256": contract["config_sha256"],
    }
    identity_input = dict(dc_input)
    if (dc_input["schema"] == "npc-riscv-open/d7-dc-input-v1" and
            "memory_mode" not in identity_input):
        # D7 predates dual-memory handoff and can only represent registers.
        identity_input["memory_mode"] = "registers"
    require_handoff_identity(identity_input, dc_identity, "DC input")
    libraries = contract["matrix"]["libraries"]
    if (dc_input.get("liberty_sha256") != libraries["liberty_sha256"] or
            dc_input.get("db_sha256") != libraries["db_sha256"]):
        raise AsicError("DC input standard-cell library identity mismatch")
    row = parse_run(dc_run)
    if not row["setup_closed"]:
        raise AsicError("P&R requires a setup-closed, loop-free DC run")
    if row.get("compile_recipe") != dc_input.get("compile_recipe"):
        raise AsicError("DC handoff compile recipe differs from its input manifest")
    if row.get("memory_mode", "registers") != contract["memory_mode"]:
        raise AsicError("DC handoff memory mode differs from selected configuration")
    if (row.get("macro_count") != contract["expected_macro_count"] or
            row.get("blackbox_count") != contract["expected_blackbox_count"]):
        raise AsicError("DC handoff macro/blackbox count differs from selected configuration")
    dc_frequency = float(row["frequency_mhz"])
    frequency = int(
        args.frequency_mhz
        or contract["pnr_frequency_mhz"]
        or (math.floor((0.80 * dc_frequency) / 25.0) * 25)
    )
    if frequency <= 0 or frequency > dc_frequency:
        raise AsicError("P&R frequency must be positive and no higher than closed DC")
    if contract["profile"] == "rv32ima_sv32_linux":
        expected_timer = frequency * 1_000_000
        if row.get("timer_clock_hz") != expected_timer:
            raise AsicError(
                "Linux handoff requires a final DC run with NPC_TIMER_CLK_HZ={}"
                .format(expected_timer))
    mapped = dc_run / f"{contract['top']}_mapped.v"
    mapped_sdc = dc_run / f"{contract['top']}_mapped.sdc"
    for path in (mapped, mapped_sdc):
        if not path.is_file():
            raise AsicError(f"missing DC handoff: {path}")
    if contract["memory_mode"] == "sram":
        floorplan = calculate_with_macros(
            float(row["standard_cell_area"]), contract["memory_data"]["macros"])
    else:
        floorplan = calculate(float(row["area"]))
    run_id = args.run_id or utc_id()
    build_root = Path(args.build_root).resolve() if args.build_root else root / "build/asic"
    try:
        build_root.relative_to(root)
    except ValueError as error:
        raise AsicError("P&R build root must be below the source root") from error
    run = (build_root / contract["profile"] / contract["mode"] /
           contract["memory_mode"] / "pnr" / run_id / f"pnr_{frequency}mhz")
    print("ASIC_PNR profile={} mode={} memory={} dc_mhz={} pnr_mhz={} run={}".format(
        contract["profile"], contract["mode"], contract["memory_mode"],
        dc_frequency, frequency, run))
    if run.exists():
        raise AsicError(f"refusing to overwrite existing P&R run: {run}")
    input_dir = run / "input"
    input_dir.mkdir(parents=True)
    mapped_copy = input_dir / mapped.name
    sdc_copy = input_dir / mapped_sdc.name
    shutil.copy2(mapped, mapped_copy)
    shutil.copy2(mapped_sdc, sdc_copy)
    pnr_sdc = input_dir / f"{contract['top']}_pnr_{frequency}mhz.sdc"
    pnr_sdc.write_text(retarget(
        sdc_copy.read_text(encoding="ascii"), 1000.0 / frequency), encoding="ascii")
    handoff = load_sram_handoff(contract) if contract["memory_mode"] == "sram" else None
    macro_views = stage_sram_views(run, contract, handoff) if handoff else {
        "lib": [], "lef": [], "gds": []}
    macro_placement = None
    if handoff:
        macro_placement = input_dir / "macro_placement.tcl"
        write_macro_placement(macro_placement, floorplan)
    write_json(run / "floorplan.json", floorplan)
    write_json(run / "input_manifest.json", {
        "schema": "npc-riscv-open/d8-pnr-input-v1",
        "profile": contract["profile"], "mode": contract["mode"],
        "source_commit": contract["source_commit"],
        "source_set_sha256": contract["source_set_sha256"],
        "source_role_sha256": contract["source_role_sha256"],
        "implementation_source_sha256": contract["implementation_source_sha256"],
        "config_sha256": contract["config_sha256"],
        "dc_frequency_mhz": dc_frequency, "pnr_frequency_mhz": frequency,
        "memory_mode": contract["memory_mode"],
        "expected_macro_count": contract["expected_macro_count"],
        "expected_blackbox_count": contract["expected_blackbox_count"],
        "dc_input_schema": dc_input["schema"],
        "dc_input_manifest_sha256": sha256_file(dc_input_path),
        "files": {
            "dc_input_manifest": {"path": str(dc_input_path), "sha256": sha256_file(dc_input_path)},
            "dc_mapped_netlist": {"path": str(mapped_copy), "sha256": sha256_file(mapped_copy)},
            "dc_mapped_sdc": {"path": str(sdc_copy), "sha256": sha256_file(sdc_copy)},
            "pnr_sdc": {"path": str(pnr_sdc), "sha256": sha256_file(pnr_sdc)},
        },
        "floorplan": floorplan,
    })
    pnr_manifest_path = run / "input_manifest.json"
    pnr_manifest = load_json(pnr_manifest_path)
    if handoff:
        pnr_manifest["sram_handoff_manifest_sha256"] = handoff["manifest_sha256"]
        for role, paths in macro_views.items():
            for index, path in enumerate(paths):
                pnr_manifest["files"][f"macro_{role}_{index}"] = {
                    "path": str(path), "sha256": sha256_file(path),
                }
        pnr_manifest["files"]["macro_placement_tcl"] = {
            "path": str(macro_placement), "sha256": sha256_file(macro_placement),
        }
        write_json(pnr_manifest_path, pnr_manifest)
    image = os.environ.get("NPC_ASIC_ORFS_IMAGE", "")
    digest = str(orfs_identity["image_digest"])
    if not image.endswith("@" + digest):
        raise AsicError(f"NPC_ASIC_ORFS_IMAGE must end with @{digest}")
    tool = require_tool(os.environ.get("NPC_ASIC_OPENROAD_RUNNER", "bash"))
    nickname = re.sub(r"[^A-Za-z0-9_]", "_", "{}_{}_{}m".format(
        contract["profile"], contract["mode"], frequency))
    environment = os.environ.copy()
    environment.update({
        "NPC_ASIC_ROOT": str(root), "NPC_ASIC_BUILD_ROOT": str(run),
        "NPC_ASIC_TOP": contract["top"], "NPC_ASIC_DESIGN_NICKNAME": nickname,
        "NPC_ASIC_MAPPED_NETLIST": str(mapped_copy), "NPC_ASIC_PNR_SDC": str(pnr_sdc),
        "NPC_ASIC_PNR_PERIOD_NS": f"{1000.0 / frequency:.9f}",
        "NPC_ASIC_DIE_AREA": format_box(floorplan["die_area"]),
        "NPC_ASIC_CORE_AREA": format_box(floorplan["core_area"]),
        "NPC_ASIC_PLACE_DENSITY": str(floorplan["place_density"]),
        "NPC_ASIC_ORFS_COMMIT": str(orfs_identity["commit"]),
        "NPC_ASIC_ORFS_IMAGE_DIGEST": digest,
        "NPC_ASIC_MEMORY_MODE": contract["memory_mode"],
        "NPC_ASIC_EXPECTED_MACRO_COUNT": str(contract["expected_macro_count"]),
        "NPC_ASIC_MACRO_LEFS": " ".join(str(path) for path in macro_views["lef"]),
        "NPC_ASIC_MACRO_LIBS": " ".join(str(path) for path in macro_views["lib"]),
        "NPC_ASIC_MACRO_GDS": " ".join(str(path) for path in macro_views["gds"]),
        "NPC_ASIC_MACRO_PLACEMENT_TCL": str(macro_placement or ""),
        "NPC_ASIC_MACRO_PLACEMENT_REPORT": (
            str(run / "macro_placement_report.txt") if handoff else ""),
        "NPC_ASIC_PRE_PDN_TCL": (
            str(root / "flows/asic/openroad/connect_openram_power.tcl") if handoff else ""),
        "NPC_ASIC_PRE_GLOBAL_ROUTE_TCL": str(
            root / "flows/asic/openroad/normalize_dc_constant_nets.tcl"),
        "NPC_ASIC_CONSTANT_NET_REPORT": str(run / "constant_net_report.txt"),
        "NPC_ASIC_MACRO_REFS": " ".join(
            sorted(contract["memory_data"].get("macros", {}))),
        "NPC_ASIC_HOLD_SLACK_MARGIN": "-0.05" if handoff else "0.0",
    })
    (run / "openroad_contract.txt").write_text(
        "design_nickname={}\n"
        "top={}\n"
        "platform=nangate45\n"
        "memory_mode={}\n"
        "expected_macro_count={}\n"
        "pnr_period_ns={:.9f}\n"
        "orfs_commit={}\n"
        "orfs_actual_commit=NA\n"
        "orfs_commit_verification=pending\n"
        "orfs_image_digest={}\n"
        "orfs_image={}\n"
        "mapped_netlist_sha256={}\n"
        "orfs_import_netlist_sha256=NA\n".format(
            nickname, contract["top"], contract["memory_mode"],
            contract["expected_macro_count"], 1000.0 / frequency,
            orfs_identity["commit"], digest, image,
            sha256_file(mapped_copy)),
        encoding="utf-8",
    )
    with (run / "openroad.log").open("w", encoding="utf-8") as log:
        completed = subprocess.run(
            [*tool, str(root / "flows/asic/openroad/run.sh")], cwd=run,
            env=environment, stdout=log, stderr=subprocess.STDOUT, check=False)
    (run / "exit_status.txt").write_text(str(completed.returncode) + "\n")
    if completed.returncode != 0:
        write_json(run / "summary.json", parse_pnr_run(run))
        print(f"ASIC_PNR_PARTIAL run={run}")
        return 2
    handoff = run / "handoff"
    mapped_hashes = {
        "dc_output_sha256": sha256_file(mapped_copy),
        "pnr_input_sha256": sha256_file(mapped_copy),
        "orfs_import_sha256": sha256_file(
            run / "orfs/results/nangate45" / nickname / "base/1_2_yosys.v"),
    }
    if len(set(mapped_hashes.values())) != 1:
        raise AsicError("FAIL_HANDOFF_IDENTITY: DC/ORFS mapped netlist hashes differ")
    roles = {
        "mapped_netlist": mapped_hashes,
        "routed_netlist": {
            "pnr_output_sha256": sha256_file(handoff / f"{contract['top']}_postroute.v"),
        },
        "routed_sdc": {
            "pnr_output_sha256": sha256_file(handoff / f"{contract['top']}_postroute.sdc"),
        },
        "routed_database": {
            "pnr_output_sha256": sha256_file(handoff / f"{contract['top']}_postroute.odb"),
            "openrcx_input_sha256": sha256_file(handoff / f"{contract['top']}_postroute.odb"),
        },
        "routed_def": {
            "pnr_output_sha256": sha256_file(handoff / f"{contract['top']}_postroute.def"),
        },
        "spef": {
            "openrcx_output_sha256": sha256_file(handoff / f"{contract['top']}_postroute.spef"),
        },
        "gds": {
            "pnr_output_sha256": sha256_file(handoff / f"{contract['top']}.gds"),
        },
    }
    write_json(run / "same_run_artifacts.json", roles)
    summary = parse_pnr_run(run)
    write_json(run / "summary.json", summary)
    if not summary["route_complete"]:
        print(f"ASIC_PNR_PARTIAL run={run}")
        return 2
    (run / "run.ok").write_text("PNR_RCX_COMPLETED\n")
    print(f"ASIC_PNR_COMPLETE run={run}")
    return 0


def sta(root: Path, config_path: Path, args: argparse.Namespace) -> int:
    contract = build_contract(root, config_path, args.ooo_mode, args.memory_mode)
    if args.dry_run:
        predecessor = str(args.pnr_run).strip() or "<route-clean-pnr-run>"
        print(
            "ASIC_STA_DRY_RUN_CONTRACT "
            f"profile={contract['profile']} mode={contract['mode']} "
            f"memory={contract['memory_mode']} macros={contract['expected_macro_count']} "
            f"pnr_run={predecessor}"
        )
        print(
            "required_roles=routed_netlist,routed_sdc,openrcx_spef,"
            "same_run_artifacts,standard_cell_db"
        )
        print("required_identity=" + ",".join(HANDOFF_IDENTITY_FIELDS))
        print(
            "sta_command: pt_shell -f "
            + str(root / "flows/asic/primetime/run.tcl")
        )
        print("ASIC_STA_DRY_RUN_PASS")
        return 0
    if not str(args.pnr_run).strip():
        raise AsicError("real STA requires --pnr-run with a route-clean P&R handoff")
    pnr_run = Path(args.pnr_run).resolve()
    pnr_input = load_json(pnr_run / "input_manifest.json")
    if pnr_input.get("schema") != "npc-riscv-open/d8-pnr-input-v1":
        raise AsicError("STA requires a recognized P&R input manifest")
    pnr_identity = {
        "profile": contract["profile"],
        "mode": contract["mode"],
        "memory_mode": contract["memory_mode"],
        "source_commit": contract["source_commit"],
        "source_set_sha256": contract["source_set_sha256"],
        "source_role_sha256": contract["source_role_sha256"],
        "implementation_source_sha256": contract["implementation_source_sha256"],
        "config_sha256": contract["config_sha256"],
    }
    require_handoff_identity(pnr_input, pnr_identity, "P&R handoff")
    if int(pnr_input.get("expected_macro_count", -1)) != contract["expected_macro_count"]:
        raise AsicError("P&R handoff expected macro count differs from selected configuration")
    pnr_summary = load_json(pnr_run / "summary.json")
    if not (pnr_run / "run.ok").is_file() or not pnr_summary.get("route_complete"):
        raise AsicError("PrimeTime requires a route-clean P&R/OpenRCX handoff")
    frequency = int(pnr_input["pnr_frequency_mhz"])
    handoff = pnr_run / "handoff"
    netlist = handoff / f"{contract['top']}_postroute.v"
    sdc = handoff / f"{contract['top']}_postroute.sdc"
    spef = handoff / f"{contract['top']}_postroute.spef"
    same_run = load_json(pnr_run / "same_run_artifacts.json")
    current = {
        "routed_netlist": sha256_file(netlist),
        "routed_sdc": sha256_file(sdc),
        "spef": sha256_file(spef),
    }
    expected = {
        "routed_netlist": same_run.get("routed_netlist", {}).get("pnr_output_sha256"),
        "routed_sdc": same_run.get("routed_sdc", {}).get("pnr_output_sha256"),
        "spef": same_run.get("spef", {}).get("openrcx_output_sha256"),
    }
    for role, digest in current.items():
        if expected.get(role) != digest:
            raise AsicError(f"FAIL_HANDOFF_IDENTITY: {role} hash drift")
    build_root = Path(args.build_root).resolve() if args.build_root else root / "build/asic"
    run_id = args.run_id or utc_id()
    run = (build_root / contract["profile"] / contract["mode"] /
           contract["memory_mode"] / "sta" / run_id / f"sta_{frequency}mhz")
    print("ASIC_STA profile={} mode={} memory={} frequency_mhz={} run={}".format(
        contract["profile"], contract["mode"], contract["memory_mode"], frequency, run))
    database = Path(os.environ.get("NPC_ASIC_STDCELL_DB", "")).expanduser().resolve()
    expected_db = str(contract["matrix"]["libraries"]["db_sha256"])
    require_hash(database, expected_db, "Nangate45 DB")
    setup = Path(os.environ.get(
        "NPC_ASIC_PRIMETIME_SETUP", root / "flows/local/asic/primetime_setup.tcl")).resolve()
    if not setup.is_file():
        raise AsicError(f"missing local PrimeTime setup: {setup}")
    tool = require_tool(os.environ.get("NPC_ASIC_PT_SHELL", "pt_shell"))
    handoff_views = None
    macro_dbs = None
    if contract["memory_mode"] == "sram":
        handoff_views = load_sram_handoff(contract)
        macro_dbs = load_macro_db_manifest(contract, handoff_views)
    if run.exists():
        raise AsicError(f"refusing to overwrite existing STA run: {run}")
    run.mkdir(parents=True)
    input_manifest = {
        "schema": "npc-riscv-open/d8-sta-input-v1",
        "profile": contract["profile"], "mode": contract["mode"],
        "source_commit": contract["source_commit"], "frequency_mhz": frequency,
        "source_set_sha256": contract["source_set_sha256"],
        "source_role_sha256": contract["source_role_sha256"],
        "implementation_source_sha256": contract["implementation_source_sha256"],
        "config_sha256": contract["config_sha256"],
        "memory_mode": contract["memory_mode"],
        "expected_macro_count": contract["expected_macro_count"],
        "db_sha256": sha256_file(database),
        "same_run_artifacts": {
            "routed_netlist": {
                "pnr_output_sha256": expected["routed_netlist"],
                "sta_input_sha256": current["routed_netlist"],
            },
            "routed_sdc": {
                "pnr_output_sha256": expected["routed_sdc"],
                "sta_input_sha256": current["routed_sdc"],
            },
            "spef": {
                "openrcx_output_sha256": expected["spef"],
                "sta_input_sha256": current["spef"],
            },
        },
        "files": {
            "routed_netlist": {"path": str(netlist), "sha256": current["routed_netlist"]},
            "routed_sdc": {"path": str(sdc), "sha256": current["routed_sdc"]},
            "spef": {"path": str(spef), "sha256": current["spef"]},
            "stdcell_db": {"path": str(database), "sha256": sha256_file(database)},
            "primetime_setup": {"path": str(setup), "sha256": sha256_file(setup)},
        },
    }
    if handoff_views is not None and macro_dbs is not None:
        input_manifest["sram_handoff_manifest_sha256"] = handoff_views["manifest_sha256"]
        input_manifest["files"]["macro_db_manifest"] = {
            "path": str(macro_dbs["manifest_path"]),
            "sha256": sha256_file(macro_dbs["manifest_path"]),
        }
        for name, path in sorted(macro_dbs["files"].items()):
            input_manifest["files"][f"macro_db_{name}"] = {
                "path": str(path), "sha256": sha256_file(path),
            }
    write_json(run / "input_manifest.json", input_manifest)
    environment = os.environ.copy()
    environment.update({
        "LC_ALL": "C", "NPC_ASIC_TOP": contract["top"],
        "NPC_ASIC_OUTPUT_DIR": str(run), "NPC_ASIC_STDCELL_DB": str(database),
        "NPC_ASIC_PRIMETIME_SETUP": str(setup),
        "NPC_ASIC_POSTROUTE_NETLIST": str(netlist),
        "NPC_ASIC_POSTROUTE_SDC": str(sdc), "NPC_ASIC_POSTROUTE_SPEF": str(spef),
        "NPC_ASIC_CLOCK_PERIOD_NS": f"{1000.0 / frequency:.9f}",
        "NPC_ASIC_MEMORY_MODE": contract["memory_mode"],
        "NPC_ASIC_EXPECTED_MACRO_COUNT": str(contract["expected_macro_count"]),
        "NPC_ASIC_EXPECTED_MACROS": ",".join(
            f"{name}={data['expected_instances']}"
            for name, data in sorted(contract["memory_data"].get("macros", {}).items())),
        "NPC_ASIC_MACRO_MIN_PERIODS": ",".join(
            f"{name}={data['minimum_period_ns']}"
            for name, data in sorted(contract["memory_data"].get("macros", {}).items())),
        "NPC_ASIC_MACRO_DBS": os.pathsep.join(
            str(path) for path in (macro_dbs["files"].values() if macro_dbs else [])),
    })
    with (run / "primetime.log").open("w", encoding="utf-8") as log:
        completed = subprocess.run(
            [*tool, "-f", str(root / "flows/asic/primetime/run.tcl")],
            cwd=run, env=environment, stdout=log, stderr=subprocess.STDOUT, check=False)
    (run / "exit_status.txt").write_text(str(completed.returncode) + "\n")
    if completed.returncode != 0 or not (run / "run_contract.txt").is_file():
        print(f"ASIC_STA_PARTIAL run={run}")
        return 2
    summary = parse_sta_run(run)
    summary["same_run_artifacts"] = load_json(run / "input_manifest.json")["same_run_artifacts"]
    write_json(run / "summary.json", summary)
    if not summary["sta_closed"]:
        print(f"ASIC_STA_PARTIAL run={run}")
        return 2
    (run / "run.ok").write_text("PRIMETIME_COMPLETED\n")
    print(f"ASIC_STA_COMPLETE run={run}")
    return 0


def evidence_check(path: Path) -> int:
    root = path.resolve()
    errors: List[str] = []
    manifests = list(root.rglob("input_manifest.json"))
    if not manifests:
        errors.append(f"{root}: no D7 input manifests found")
    for manifest_path in manifests:
        try:
            record = load_json(manifest_path)
        except AsicError as error:
            errors.append(str(error)); continue
        files = record.get("files", {})
        if isinstance(files, dict):
            for role, item in files.items():
                if not isinstance(item, dict):
                    errors.append(f"{manifest_path}: malformed role {role}"); continue
                candidate = Path(str(item.get("path", "")))
                if not candidate.is_file():
                    errors.append(f"{manifest_path}: missing role {role}"); continue
                if sha256_file(candidate) != item.get("sha256"):
                    errors.append(f"{manifest_path}: hash drift for {role}")
        if (record.get("schema") in (
                "npc-riscv-open/d7-sta-input-v1", "npc-riscv-open/d8-sta-input-v1") and
                not isinstance(record.get("same_run_artifacts"), dict)):
            errors.append(f"{manifest_path}: missing same_run_artifacts")
    for same_path in root.rglob("same_run_artifacts.json"):
        record = load_json(same_path)
        mapped_record = record.get("mapped_netlist", {})
        mapped = [mapped_record.get(key) for key in (
            "dc_output_sha256", "pnr_input_sha256", "orfs_import_sha256")]
        if any(not value for value in mapped) or len(set(mapped)) != 1:
            errors.append(f"{same_path}: FAIL_HANDOFF_IDENTITY")
        database = record.get("routed_database", {})
        database_roles = [database.get("pnr_output_sha256"),
                          database.get("openrcx_input_sha256")]
        if any(not value for value in database_roles) or len(set(database_roles)) != 1:
            errors.append(f"{same_path}: FAIL_HANDOFF_IDENTITY routed_database")
        for role, key in (("routed_netlist", "pnr_output_sha256"),
                          ("routed_sdc", "pnr_output_sha256"),
                          ("spef", "openrcx_output_sha256")):
            if not record.get(role, {}).get(key):
                errors.append(f"{same_path}: missing {role}.{key}")
        manifest_path = same_path.parent / "input_manifest.json"
        manifest = load_json(manifest_path) if manifest_path.is_file() else {}
        if manifest.get("schema") == "npc-riscv-open/d8-pnr-input-v1":
            for role in ("routed_def", "gds"):
                if not record.get(role, {}).get("pnr_output_sha256"):
                    errors.append(f"{same_path}: missing {role}.pnr_output_sha256")
    for manifest_path in root.rglob("input_manifest.json"):
        record = load_json(manifest_path)
        if record.get("schema") not in (
                "npc-riscv-open/d7-sta-input-v1", "npc-riscv-open/d8-sta-input-v1"):
            continue
        same = record.get("same_run_artifacts", {})
        pairs = (
            ("routed_netlist", "pnr_output_sha256", "sta_input_sha256"),
            ("routed_sdc", "pnr_output_sha256", "sta_input_sha256"),
            ("spef", "openrcx_output_sha256", "sta_input_sha256"),
        )
        for role, source_key, sink_key in pairs:
            item = same.get(role, {})
            if not item.get(source_key) or item.get(source_key) != item.get(sink_key):
                errors.append(f"{manifest_path}: FAIL_HANDOFF_IDENTITY {role}")
    if errors:
        raise AsicError("ASIC_EVIDENCE_CHECK_FAILED\n  - " + "\n  - ".join(errors))
    print(f"ASIC_EVIDENCE_CHECK_PASS manifests={len(manifests)} root={root}")
    return 0


def parser() -> argparse.ArgumentParser:
    result = argparse.ArgumentParser(description=__doc__)
    result.add_argument("--root", type=Path, default=Path(__file__).resolve().parents[2])
    result.add_argument("--config", type=Path, default=Path(".config"))
    commands = result.add_subparsers(dest="command")
    commands.required = True
    check = commands.add_parser("config-check")
    check.add_argument("--ooo-mode", default="auto",
                       choices=("auto", "legacy", "a3-split-off", "a3"))
    check.add_argument("--memory-mode", default="auto",
                       choices=("auto", "registers", "sram"))
    lc = commands.add_parser("lc-macros")
    lc.add_argument("--dry-run", action="store_true")
    lc.add_argument("--ooo-mode", default="auto",
                    choices=("auto", "legacy", "a3-split-off", "a3"))
    lc.add_argument("--memory-mode", default="auto",
                    choices=("auto", "registers", "sram"))
    lc.add_argument("--output", default="")
    dc = commands.add_parser("dc-matrix")
    dc.add_argument("--dry-run", action="store_true")
    dc.add_argument("--ooo-mode", default="auto",
                    choices=("auto", "legacy", "a3-split-off", "a3"))
    dc.add_argument("--memory-mode", default="auto",
                    choices=("auto", "registers", "sram"))
    dc.add_argument("--frequencies", default="")
    dc.add_argument("--timer-clock-hz", type=int)
    dc.add_argument("--build-root", default="")
    dc.add_argument("--run-id", default="")
    pnr_parser = commands.add_parser("pnr")
    pnr_parser.add_argument("--dry-run", action="store_true")
    pnr_parser.add_argument("--ooo-mode", default="auto",
                            choices=("auto", "legacy", "a3-split-off", "a3"))
    pnr_parser.add_argument("--memory-mode", default="auto",
                            choices=("auto", "registers", "sram"))
    pnr_parser.add_argument("--dc-run", required=True)
    pnr_parser.add_argument("--frequency-mhz", type=int)
    pnr_parser.add_argument("--build-root", default="")
    pnr_parser.add_argument("--run-id", default="")
    sta_parser = commands.add_parser("sta")
    sta_parser.add_argument("--dry-run", action="store_true")
    sta_parser.add_argument("--ooo-mode", default="auto",
                            choices=("auto", "legacy", "a3-split-off", "a3"))
    sta_parser.add_argument("--memory-mode", default="auto",
                            choices=("auto", "registers", "sram"))
    sta_parser.add_argument("--pnr-run", required=True)
    sta_parser.add_argument("--build-root", default="")
    sta_parser.add_argument("--run-id", default="")
    evidence = commands.add_parser("evidence-check")
    evidence.add_argument("--build-root", required=True, type=Path)
    a3_eval = commands.add_parser("a3-dc-eval")
    a3_eval.add_argument("--legacy", type=Path, required=True)
    a3_eval.add_argument("--split-off", type=Path, required=True)
    a3_eval.add_argument("--a3", type=Path, required=True)
    a3_eval.add_argument("--cpi-summary", type=Path, required=True)
    a3_eval.add_argument("--output", type=Path, required=True)
    return result


def main(argv: Optional[List[str]] = None) -> int:
    args = parser().parse_args(argv)
    root = args.root.resolve()
    config_path = args.config if args.config.is_absolute() else root / args.config
    try:
        if args.command == "config-check":
            contract = build_contract(root, config_path, args.ooo_mode, args.memory_mode)
            print("ASIC_CONFIG_CHECK_PASS profile={} mode={} memory={} macros={} source={} source_set={} config={}".format(
                contract["profile"], contract["mode"], contract["memory_mode"],
                contract["expected_macro_count"], contract["source_commit"],
                contract["source_set_sha256"], contract["config_sha256"]))
            print("ASIC_SOURCE_ROLE_IDENTITY role_source={} implementation_source={} overlays={}".format(
                contract["source_role_sha256"],
                contract["implementation_source_sha256"],
                ",".join(contract["source_overlay_commits"])))
            return 0
        if args.command == "lc-macros":
            return lc_macros(root, config_path, args)
        if args.command == "dc-matrix":
            return dc_matrix(root, config_path, args)
        if args.command == "pnr":
            return pnr(root, config_path, args)
        if args.command == "sta":
            return sta(root, config_path, args)
        if args.command == "evidence-check":
            return evidence_check(args.build_root)
        if args.command == "a3-dc-eval":
            return compare_a3_dc(
                args.legacy, args.split_off, args.a3, args.cpi_summary, args.output)
        raise AsicError(f"unsupported command {args.command}")
    except (AsicError, OSError, ValueError, KeyError, RuntimeError,
            subprocess.SubprocessError) as error:
        print(f"asicctl: error: {error}", file=sys.stderr)
        return 2


if __name__ == "__main__":
    raise SystemExit(main())
