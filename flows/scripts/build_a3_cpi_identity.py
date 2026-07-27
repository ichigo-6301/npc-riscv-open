#!/usr/bin/env python3
"""Build bounded A3 cycle-identity evidence from the reviewed 14-row CSV.

The A3 performance campaign used the private OoO difftest harness, not the
minimal public NEMU adapter.  Bind the generated result to that exact
reference binary and its adjacent configuration snapshot so a later DC merge
decision cannot silently substitute a different Profile's reference model.
"""

import argparse
import csv
import hashlib
import json
from pathlib import Path
from typing import Dict

from compare_a3_dc import A3_COMMIT, REQUIRED_CPI_PROFILES, REQUIRED_WORKLOADS


A3_IMPLEMENTATION_COMMIT = "354f2e4a2d8cc8c96bd76949d61dec24f7247afd"
A3_PERFORMANCE_PROFILE = "rv32im_4k_v1"


def sha256_file(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def boolean(value: str, field: str) -> bool:
    if value == "True":
        return True
    if value == "False":
        return False
    raise ValueError("{} must be True or False, got {!r}".format(field, value))


def load_flat_manifest(path: Path) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if "=" not in line:
            raise ValueError("invalid evidence manifest line {}: {}".format(number, raw))
        key, value = line.split("=", 1)
        if not key or key in result:
            raise ValueError("duplicate or empty evidence key at line {}".format(number))
        result[key] = value
    return result


def load_nemu_config(path: Path) -> Dict[str, str]:
    result: Dict[str, str] = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        result[key] = value
    required = {
        "CONFIG_ISA": '"riscv32"',
        "CONFIG_RISCV_FPGA_MMIO_LAYOUT": "y",
        "CONFIG_DEVICE": "y",
        "CONFIG_RTC_MMIO": "0xa0000048",
    }
    for key, expected in required.items():
        if result.get(key) != expected:
            raise ValueError(
                "A3 NEMU config {}={!r}, expected {!r}".format(
                    key, result.get(key), expected
                )
            )
    return {key: result[key] for key in required}


def difftest_reference(evidence_path: Path, nemu_so: Path,
                       nemu_config: Path, csv_sha256: str) -> dict:
    evidence = load_flat_manifest(evidence_path)
    required = {
        "profile": A3_PERFORMANCE_PROFILE,
        "implementation_commit": A3_IMPLEMENTATION_COMMIT,
        "functional_status": "A3_CYCLE_IDENTITY_PASS",
        "evidence_002_sha256": csv_sha256,
    }
    for key, expected in required.items():
        if evidence.get(key) != expected:
            raise ValueError(
                "A3 evidence manifest {}={!r}, expected {!r}".format(
                    key, evidence.get(key), expected
                )
            )
    nemu_commit = evidence.get("nemu_commit", "")
    expected_so = evidence.get("nemu_so_sha256", "")
    actual_so = sha256_file(nemu_so)
    if len(nemu_commit) != 40 or any(ch not in "0123456789abcdef" for ch in nemu_commit):
        raise ValueError("A3 evidence manifest has an invalid NEMU commit")
    if len(expected_so) != 64 or actual_so != expected_so:
        raise ValueError(
            "A3 NEMU shared-object hash mismatch: {} != {}".format(
                actual_so, expected_so
            )
        )
    config_contract = load_nemu_config(nemu_config)
    return {
        "profile": A3_PERFORMANCE_PROFILE,
        "nemu_commit": nemu_commit,
        "nemu_so_sha256": actual_so,
        "nemu_config_sha256": sha256_file(nemu_config),
        "nemu_config_contract": config_contract,
        "source_evidence_manifest_sha256": sha256_file(evidence_path),
        "mmio_policy": "private_ooo_dut_authoritative_skip_and_reference_resync",
        "public_bounded_adapter_used": False,
    }


def build(path: Path, evidence_manifest: Path, nemu_so: Path,
          nemu_config: Path) -> dict:
    csv_sha256 = sha256_file(path)
    reference = difftest_reference(
        evidence_manifest, nemu_so, nemu_config, csv_sha256
    )
    with path.open(newline="", encoding="utf-8") as stream:
        source_rows = list(csv.DictReader(stream))
    indexed = {}
    rows = []
    for source in source_rows:
        key = (source.get("profile"), source.get("workload"))
        if key in indexed:
            raise ValueError("duplicate A3 CPI row {}:{}".format(*key))
        indexed[key] = source
    expected = {(profile, workload) for profile in REQUIRED_CPI_PROFILES
                for workload in REQUIRED_WORKLOADS}
    if set(indexed) != expected:
        missing = sorted(expected - set(indexed))
        extra = sorted(set(indexed) - expected)
        raise ValueError("A3 CPI row set mismatch: missing={} extra={}".format(missing, extra))
    for profile in REQUIRED_CPI_PROFILES:
        for workload in REQUIRED_WORKLOADS:
            source = indexed[(profile, workload)]
            row = {
                "profile": profile,
                "workload": workload,
                "binary_sha256": source["binary_sha256"],
                "cycles": int(source["cycles"]),
                "instructions": int(source["instructions"]),
                "cpi": float(source["cpi"]),
                "commit_trace_lines": int(source["commit_trace_lines"]),
                "commit_pc_instruction_sha256": source["commit_pc_instruction_sha256"],
                "cycle_identity": boolean(source["cycle_identity"], "cycle_identity"),
                "instruction_identity": boolean(
                    source["instruction_identity"], "instruction_identity"),
                "trace_identity": boolean(source["trace_identity"], "trace_identity"),
                "guard_status": source["guard_status"],
            }
            if not (row["cycle_identity"] and row["instruction_identity"] and
                    row["trace_identity"] and row["guard_status"] == "PASS"):
                raise ValueError("A3 identity guard failed for {}:{}".format(profile, workload))
            rows.append(row)
    aggregate = {}
    for profile in REQUIRED_CPI_PROFILES:
        selected = [row for row in rows if row["profile"] == profile]
        cycles = sum(row["cycles"] for row in selected)
        instructions = sum(row["instructions"] for row in selected)
        aggregate[profile] = {
            "cycles": cycles,
            "instructions": instructions,
            "cpi": cycles / instructions,
        }
    return {
        "schema": "npc-riscv-open/a3-cycle-identity-v1",
        "source_commit": A3_COMMIT,
        "evidence_class": "cycle-accurate Verilator plus NEMU difftest",
        "source_csv_sha256": csv_sha256,
        "difftest_reference": reference,
        "row_count": len(rows),
        "aggregate": aggregate,
        "rows": rows,
        "status": "A3_CYCLE_IDENTITY_PASS",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, required=True)
    parser.add_argument("--evidence-manifest", type=Path, required=True)
    parser.add_argument("--nemu-so", type=Path, required=True)
    parser.add_argument("--nemu-config", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(
        args.csv, args.evidence_manifest, args.nemu_so, args.nemu_config
    )
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n",
                           encoding="utf-8")
    print("A3_CPI_IDENTITY_BUILD_PASS rows={} output={}".format(
        result["row_count"], args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
