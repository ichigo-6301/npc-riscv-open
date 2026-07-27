#!/usr/bin/env python3
"""Build bounded A3 cycle-identity evidence from the reviewed 14-row CSV."""

import argparse
import csv
import hashlib
import json
from pathlib import Path

from compare_a3_dc import A3_COMMIT, REQUIRED_CPI_PROFILES, REQUIRED_WORKLOADS


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


def build(path: Path) -> dict:
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
        "source_csv_sha256": sha256_file(path),
        "row_count": len(rows),
        "aggregate": aggregate,
        "rows": rows,
        "status": "A3_CYCLE_IDENTITY_PASS",
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--csv", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    result = build(args.csv)
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n",
                           encoding="utf-8")
    print("A3_CPI_IDENTITY_BUILD_PASS rows={} output={}".format(
        result["row_count"], args.output))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
