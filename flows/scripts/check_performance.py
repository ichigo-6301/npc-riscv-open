#!/usr/bin/env python3
"""Fail-closed validation for public benchmark contracts and metric evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import re


EXPECTED_STATUS = {
    "rv32im_single_perf": ("verified", "pass"),
    "rv32ima_sv32_linux": ("verified", "pass"),
    "rv32im_ooo_4k": ("provisional", "not_run_dual_retire_mmio_ambiguity"),
}
EXPECTED_CLAIMS = {
    "single_public_coremark_timed_cpi": ("rv32im_single_perf", "timed_cpi"),
    "single_public_coremark_per_mhz": ("rv32im_single_perf", "coremark_per_mhz"),
    "single_public_coremark_whole_cpi": ("rv32im_single_perf", "whole_cpi"),
    "linux_public_coremark_timed_cpi": ("rv32ima_sv32_linux", "timed_cpi"),
    "linux_public_coremark_per_mhz": ("rv32ima_sv32_linux", "coremark_per_mhz"),
    "linux_public_coremark_whole_cpi": ("rv32ima_sv32_linux", "whole_cpi"),
}


def load_object(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise RuntimeError(f"invalid JSON record {path}: {error}") from error
    if not isinstance(value, dict):
        raise RuntimeError(f"{path}: top level must be an object")
    return value


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def check_manifest(root: Path, errors: list[str]) -> dict:
    path = root / "delivery/benchmarks/coremark.json"
    try:
        data = load_object(path)
    except RuntimeError as error:
        errors.append(str(error))
        return {}
    if data.get("schema") != "npc-riscv-open/coremark-benchmark-v1":
        errors.append("CoreMark manifest schema mismatch")
    if data.get("iterations") != 10 or data.get("contexts") != 1:
        errors.append("CoreMark manifest must lock 10 iterations and one context")
    source = data.get("source", {})
    patch_name = source.get("benchmark_patch") if isinstance(source, dict) else None
    patch_hash = source.get("benchmark_patch_sha256") if isinstance(source, dict) else None
    patch = root / "delivery/benchmarks" / str(patch_name)
    if not patch.is_file() or sha256(patch) != patch_hash:
        errors.append("CoreMark benchmark patch is missing or has hash drift")
    profile_count: dict[str, int] = {}
    for variant_id, variant in data.get("variants", {}).items():
        if not isinstance(variant, dict):
            errors.append(f"CoreMark variant {variant_id} is not an object")
            continue
        for key in ("binary_sha256", "elf_sha256"):
            if re.fullmatch(r"[0-9a-f]{64}", str(variant.get(key, ""))) is None:
                errors.append(f"CoreMark variant {variant_id} has invalid {key}")
        for profile in variant.get("profiles", []):
            profile_count[str(profile)] = profile_count.get(str(profile), 0) + 1
    expected = {"rv32im_single_perf", "rv32ima_sv32_linux", "rv32im_ooo_4k"}
    if set(profile_count) != expected or any(count != 1 for count in profile_count.values()):
        errors.append("CoreMark variants must map every Profile exactly once")
    return data


def check_claims(root: Path, runs: dict, errors: list[str]) -> None:
    try:
        claims_data = load_object(root / "delivery/claims/claims.yaml")
    except RuntimeError as error:
        errors.append(str(error))
        return
    raw_claims = claims_data.get("claims")
    if not isinstance(raw_claims, list):
        errors.append("public claims metadata has no claims list")
        return
    claims = {
        str(item.get("id")): item for item in raw_claims
        if isinstance(item, dict) and item.get("id")
    }
    if set(claims) != set(EXPECTED_CLAIMS):
        errors.append("public verified CoreMark claim set has drifted")
    for claim_id, (profile, field) in EXPECTED_CLAIMS.items():
        claim = claims.get(claim_id)
        if claim is None or profile not in runs:
            continue
        if claim.get("profile") != profile or claim.get("status") != "verified":
            errors.append(f"public claim identity/status mismatch for {claim_id}")
        if claim.get("public") is not True or claim.get("evidence") != ["coremark_public_current"]:
            errors.append(f"public claim evidence binding mismatch for {claim_id}")
        if claim.get("source_ref") != runs[profile].get("source_commit"):
            errors.append(f"public claim source mismatch for {claim_id}")
        try:
            claim_value = float(claim.get("value"))
            run_value = float(runs[profile][field])
        except (KeyError, TypeError, ValueError):
            errors.append(f"public claim value missing for {claim_id}")
            continue
        if round(claim_value, 9) != round(run_value, 9):
            errors.append(f"public claim value drift for {claim_id}")


def check_evidence(root: Path, manifest: dict, errors: list[str]) -> None:
    path = root / "evidence/performance/coremark.json"
    try:
        evidence = load_object(path)
    except RuntimeError as error:
        errors.append(str(error))
        return
    if evidence.get("schema") != "npc-riscv-open/coremark-evidence-v1":
        errors.append("CoreMark evidence schema mismatch")
    if re.fullmatch(
        r"\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z",
        str(evidence.get("generated_at", "")),
    ) is None:
        errors.append("CoreMark evidence has no UTC generation time")
    tools = evidence.get("tools")
    if not isinstance(tools, dict) or any(
        not tools.get(key) for key in ("simulator", "reference", "compiler")
    ):
        errors.append("CoreMark evidence has incomplete tool identity")
    commands = evidence.get("commands")
    if not isinstance(commands, dict) or set(commands) != set(EXPECTED_STATUS):
        errors.append("CoreMark evidence has incomplete reproduction commands")
    if evidence.get("benchmark_manifest_sha256") != sha256(
        root / "delivery/benchmarks/coremark.json"
    ):
        errors.append("CoreMark evidence references a stale benchmark manifest")
    runs = evidence.get("runs")
    if not isinstance(runs, dict):
        errors.append("CoreMark evidence has no runs mapping")
        return
    if set(runs) != set(EXPECTED_STATUS):
        errors.append("CoreMark evidence must contain exactly the three public Profiles")
    documents = [
        root / "README.md", root / "README.en.md",
        root / "docs/performance.md", root / "docs/performance.en.md",
    ]
    for profile, record in runs.items():
        if not isinstance(record, dict):
            errors.append(f"CoreMark evidence run {profile} is not an object")
            continue
        expected = EXPECTED_STATUS.get(profile)
        if expected is None or (record.get("status"), record.get("difftest")) != expected:
            errors.append(f"CoreMark evidence status/difftest mismatch for {profile}")
        required = (
            "source_commit", "binary_sha256", "elf_sha256", "config_sha256",
            "raw_summary_sha256",
            "whole_cycles", "whole_instructions", "whole_cpi",
            "timed_cycles", "timed_instructions", "timed_cpi",
            "coremark_per_mhz", "difftest",
        )
        missing = [key for key in required if key not in record]
        if missing:
            errors.append(f"CoreMark evidence run {profile} lacks {','.join(missing)}")
            continue
        if re.fullmatch(r"[0-9a-f]{64}", str(record["raw_summary_sha256"])) is None:
            errors.append(f"CoreMark raw summary hash is invalid for {profile}")
        if record["whole_cycles"] != (
            record["pre_cycles"] + record["timed_cycles"] + record["post_cycles"]
        ):
            errors.append(f"CoreMark cycle partition does not conserve for {profile}")
        if record["whole_instructions"] != (
            record["pre_instructions"] + record["timed_instructions"] +
            record["post_instructions"]
        ):
            errors.append(f"CoreMark instruction partition does not conserve for {profile}")
        computed = {
            "whole_cpi": record["whole_cycles"] / record["whole_instructions"],
            "timed_cpi": record["timed_cycles"] / record["timed_instructions"],
            "coremark_per_mhz": 10_000_000 / record["timed_cycles"],
        }
        for field, value in computed.items():
            if round(float(record[field]), 9) != round(value, 9):
                errors.append(f"CoreMark derived metric mismatch for {profile}.{field}")
        matching_variants = [
            variant for variant in manifest.get("variants", {}).values()
            if isinstance(variant, dict) and profile in variant.get("profiles", [])
        ]
        if len(matching_variants) != 1:
            errors.append(f"CoreMark variant mapping mismatch for {profile}")
        elif (
            record.get("binary_sha256") != matching_variants[0].get("binary_sha256")
            or record.get("elf_sha256") != matching_variants[0].get("elf_sha256")
        ):
            errors.append(f"CoreMark input identity mismatch for {profile}")
        rendered = (
            f"{record['whole_cpi']:.9f}", f"{record['timed_cpi']:.9f}",
            f"{record['coremark_per_mhz']:.9f}",
        )
        for document in documents:
            if not document.is_file():
                errors.append(f"missing performance surface {document.relative_to(root)}")
                continue
            text = document.read_text(encoding="utf-8")
            for value in rendered:
                if value not in text:
                    errors.append(
                        f"{document.relative_to(root)} lacks {profile} metric {value}"
                    )
    parity = evidence.get("linux_parity")
    if not isinstance(parity, dict) or parity.get("status") != "verified":
        errors.append("Linux private/public parity evidence is missing")
    elif (
        parity.get("timed_match") is not True
        or parity.get("private_timed_cycles") != parity.get("public_timed_cycles")
        or parity.get("private_timed_instructions") != parity.get("public_timed_instructions")
    ):
        errors.append("Linux private/public timed interval does not match")
    diagnostic = evidence.get("linux_write_allocate_diagnostic")
    if not isinstance(diagnostic, dict):
        errors.append("Linux WRITE_ALLOCATE diagnostic is missing")
    else:
        wa0 = diagnostic.get("write_allocate_0", {})
        wa1 = diagnostic.get("write_allocate_1", {})
        if wa1.get("whole_cycles", 0) - wa0.get("whole_cycles", 0) != 54816:
            errors.append("Linux WRITE_ALLOCATE whole-cycle delta has drifted")
        if wa1.get("pre_cycles", 0) - wa0.get("pre_cycles", 0) != 54999:
            errors.append("Linux WRITE_ALLOCATE pre-marker delta has drifted")
    historical = evidence.get("historical_references", {})
    aggregate = historical.get("ooo_instruction_weighted_seven_workload_aggregate", {})
    try:
        aggregate_value = aggregate["total_cycles"] / aggregate["retired_instructions"]
        if round(float(aggregate["aggregate_cpi"]), 9) != round(aggregate_value, 9):
            errors.append("seven-workload aggregate CPI does not conserve")
        if len(aggregate.get("workloads", [])) != 7:
            errors.append("seven-workload aggregate must name seven workloads")
    except (KeyError, TypeError, ValueError, ZeroDivisionError):
        errors.append("seven-workload aggregate evidence is incomplete")
    check_claims(root, runs, errors)


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    root = args.root.resolve()
    errors: list[str] = []
    manifest = check_manifest(root, errors)
    if manifest:
        check_evidence(root, manifest, errors)
    if errors:
        raise SystemExit("PERFORMANCE_CHECK_FAILED\n  - " + "\n  - ".join(sorted(set(errors))))
    print("PERFORMANCE_CHECK_PASS profiles=3 benchmark=coremark")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
