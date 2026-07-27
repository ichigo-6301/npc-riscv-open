#!/usr/bin/env python3
"""Fail-closed three-way Design Compiler evaluation for the OoO A3 branch."""

import argparse
import json
from pathlib import Path
from typing import Dict, List, Optional

from summarize_dc import parse_run


LEGACY_COMMIT = "99fcc2be539eabb078c0d73b26a7ef2c00071391"
A3_COMMIT = "94ae2c6fb82d5f077d5cc7a2c131d982ce53e3b0"
REQUIRED_CPI_PROFILES = ("ideal", "default")
REQUIRED_WORKLOADS = (
    "coremark", "matrix-mul", "crc32", "quick-sort", "load-store",
    "dhrystone", "microbench",
)


class ComparisonError(RuntimeError):
    pass


def load_json(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise ComparisonError("invalid JSON {}: {}".format(path, error))
    if not isinstance(value, dict):
        raise ComparisonError("JSON top level must be an object: {}".format(path))
    return value


def load_matrix(path: Path, expected_mode: str, expected_commit: str) -> dict:
    root = path.resolve()
    manifest = load_json(root / "input_manifest.json")
    if manifest.get("schema") != "npc-riscv-open/d7-dc-input-v1":
        raise ComparisonError("unexpected DC manifest schema: {}".format(root))
    if manifest.get("profile") != "rv32im_ooo_4k":
        raise ComparisonError("A3 comparison requires the OoO Profile: {}".format(root))
    if manifest.get("mode") != expected_mode:
        raise ComparisonError("{} mode is {}, expected {}".format(
            root, manifest.get("mode"), expected_mode))
    if manifest.get("source_commit") != expected_commit:
        raise ComparisonError("{} source is {}, expected {}".format(
            root, manifest.get("source_commit"), expected_commit))
    rows = [parse_run(run) for run in sorted(root.glob("dc_*mhz")) if run.is_dir()]
    frequencies = [row.get("frequency_mhz") for row in rows]
    if not rows or any(value is None for value in frequencies):
        raise ComparisonError("DC matrix has no parseable rows: {}".format(root))
    if len(set(frequencies)) != len(frequencies):
        raise ComparisonError("DC matrix repeats a frequency: {}".format(root))
    return {"root": str(root), "manifest": manifest, "rows": rows}


def graph_valid(row: dict) -> bool:
    return bool(
        row.get("completed") and row.get("timing_loop_report_valid") and
        row.get("timing_loop_evidence") == 0 and
        row.get("automatic_arc_break_evidence") == 0 and
        row.get("check_design_ok") == 1 and row.get("check_timing_ok") == 1 and
        row.get("unresolved_reference_count") == 0 and row.get("latch_count") == 0 and
        row.get("unclocked_sync_endpoint_count") == 0 and
        row.get("macro_count") == 0 and row.get("blackbox_count") == 0
    )


def comparison_metrics_present(row: dict) -> bool:
    return all(row.get(key) is not None for key in (
        "data_path_delay_ns", "tns_ns", "violating_paths", "area", "cell_count",
    ))


def row_map(matrix: dict) -> Dict[float, dict]:
    return {float(row["frequency_mhz"]): row for row in matrix["rows"]}


def highest_closed(matrix: dict) -> Optional[float]:
    values = [float(row["frequency_mhz"]) for row in matrix["rows"]
              if row.get("setup_closed") and graph_valid(row)]
    return max(values) if values else None


def validate_recipe_identity(matrices: List[dict]) -> List[str]:
    reasons: List[str] = []
    manifests = [matrix["manifest"] for matrix in matrices]
    for key in ("liberty_sha256", "db_sha256", "frequencies_mhz", "scan_policy",
                "memory_mode", "macro_count", "timer_clock_hz"):
        values = [manifest.get(key) for manifest in manifests]
        if any(value != values[0] for value in values[1:]):
            reasons.append("recipe mismatch: {}".format(key))
    for role in ("constraint_sdc", "dc_setup", "stdcell_liberty", "stdcell_db"):
        values = [manifest.get("files", {}).get(role, {}).get("sha256")
                  for manifest in manifests]
        if any(not value for value in values) or any(value != values[0] for value in values[1:]):
            reasons.append("recipe file mismatch: {}".format(role))
    split_manifest, candidate_manifest = manifests[1], manifests[2]
    if split_manifest.get("source_set_sha256") != candidate_manifest.get("source_set_sha256"):
        reasons.append("A3 split-off and enabled source-set hashes differ")
    return reasons


def validate_cpi(record: dict) -> dict:
    reasons: List[str] = []
    if record.get("schema") != "npc-riscv-open/a3-cycle-identity-v1":
        reasons.append("unexpected CPI evidence schema")
    if record.get("source_commit") != A3_COMMIT:
        reasons.append("CPI evidence source commit mismatch")
    reference = record.get("difftest_reference")
    if not isinstance(reference, dict):
        reasons.append("CPI evidence has no Profile-bound difftest reference")
    else:
        if reference.get("profile") != "rv32im_4k_v1":
            reasons.append("CPI difftest reference profile mismatch")
        for key in (
            "nemu_commit", "nemu_so_sha256", "nemu_config_sha256",
            "source_evidence_manifest_sha256",
        ):
            value = reference.get(key)
            width = 40 if key == "nemu_commit" else 64
            if (not isinstance(value, str) or len(value) != width or
                    any(ch not in "0123456789abcdef" for ch in value)):
                reasons.append("CPI difftest reference has invalid {}".format(key))
        expected_contract = {
            "CONFIG_ISA": '"riscv32"',
            "CONFIG_RISCV_FPGA_MMIO_LAYOUT": "y",
            "CONFIG_DEVICE": "y",
            "CONFIG_RTC_MMIO": "0xa0000048",
        }
        if reference.get("nemu_config_contract") != expected_contract:
            reasons.append("CPI difftest NEMU configuration mismatch")
        if reference.get("mmio_policy") != (
                "private_ooo_dut_authoritative_skip_and_reference_resync"):
            reasons.append("CPI difftest MMIO policy mismatch")
        if reference.get("public_bounded_adapter_used") is not False:
            reasons.append("public bounded adapter cannot qualify A3 CPI")
    rows = record.get("rows")
    if not isinstance(rows, list):
        rows = []
        reasons.append("CPI evidence rows missing")
    indexed = {}
    for row in rows:
        if not isinstance(row, dict):
            reasons.append("malformed CPI row")
            continue
        key = (row.get("profile"), row.get("workload"))
        if key in indexed:
            reasons.append("duplicate CPI row {}:{}".format(*key))
        indexed[key] = row
    for profile in REQUIRED_CPI_PROFILES:
        for workload in REQUIRED_WORKLOADS:
            row = indexed.get((profile, workload))
            if row is None:
                reasons.append("missing CPI row {}:{}".format(profile, workload))
                continue
            for key in ("cycle_identity", "instruction_identity", "trace_identity"):
                if row.get(key) is not True:
                    reasons.append("{} failed for {}:{}".format(key, profile, workload))
            if row.get("guard_status") != "PASS":
                reasons.append("guard failed for {}:{}".format(profile, workload))
    return {"pass": not reasons, "reasons": reasons, "row_count": len(indexed)}


def evaluate(legacy: dict, split_off: dict, candidate: dict, cpi: dict) -> dict:
    reasons = validate_recipe_identity([legacy, split_off, candidate])
    cpi_result = validate_cpi(cpi)
    reasons.extend(cpi_result["reasons"])
    maps = [row_map(matrix) for matrix in (legacy, split_off, candidate)]
    common = sorted(set(maps[0]) & set(maps[1]) & set(maps[2]), reverse=True)
    comparable = [frequency for frequency in common
                  if all(graph_valid(rows[frequency]) and
                         comparison_metrics_present(rows[frequency]) for rows in maps)]
    if not comparable:
        return {
            "schema": "npc-riscv-open/a3-dc-evaluation-v1",
            "status": "A3_DC_INCONCLUSIVE_LOOP",
            "merge_allowed": False,
            "reasons": reasons + ["no common three-way frequency has a complete valid timing graph"],
            "cpi_identity": cpi_result,
        }

    frequency = comparable[0]
    legacy_row, split_row, candidate_row = [rows[frequency] for rows in maps]
    references = {"public_legacy": legacy_row, "a3_split_off": split_row}
    comparisons = {}
    for name, reference in references.items():
        comparisons[name] = {
            "delay_improvement_percent": 100.0 * (
                float(reference["data_path_delay_ns"]) -
                float(candidate_row["data_path_delay_ns"])) /
                float(reference["data_path_delay_ns"]),
            "tns_nonworse": float(candidate_row["tns_ns"]) >= float(reference["tns_ns"]) - 0.0005,
            "violating_paths_nonworse": int(candidate_row["violating_paths"]) <= int(reference["violating_paths"]),
            "area_growth_percent": 100.0 * (
                float(candidate_row["area"]) / float(reference["area"]) - 1.0),
            "cell_growth_percent": 100.0 * (
                float(candidate_row["cell_count"]) / float(reference["cell_count"]) - 1.0),
        }
    closed = {
        "public_legacy_mhz": highest_closed(legacy),
        "a3_split_off_mhz": highest_closed(split_off),
        "a3_mhz": highest_closed(candidate),
    }
    delay_gate = all(item["delay_improvement_percent"] >= 5.0
                     for item in comparisons.values())
    frequency_gate = bool(
        closed["a3_mhz"] is not None and
        closed["public_legacy_mhz"] is not None and
        closed["a3_split_off_mhz"] is not None and
        closed["a3_mhz"] - closed["public_legacy_mhz"] >= 50.0 and
        closed["a3_mhz"] - closed["a3_split_off_mhz"] >= 50.0
    )
    quality_gate = all(
        item["tns_nonworse"] and item["violating_paths_nonworse"] and
        item["area_growth_percent"] <= 5.0 and item["cell_growth_percent"] <= 5.0
        for item in comparisons.values()
    )
    if closed["a3_mhz"] is None:
        reasons.append("A3 has no setup-closed DC point")
    if not (delay_gate or frequency_gate):
        reasons.append("neither 5% same-frequency delay nor 50 MHz closed-point gate passed")
    if not quality_gate:
        reasons.append("TNS/path-count or 5% area/cell guard failed")
    merge = bool(not reasons and closed["a3_mhz"] is not None and
                 (delay_gate or frequency_gate) and quality_gate and cpi_result["pass"])
    return {
        "schema": "npc-riscv-open/a3-dc-evaluation-v1",
        "status": "A3_DC_MERGE_PASS" if merge else "A3_DC_REJECT",
        "merge_allowed": merge,
        "comparison_frequency_mhz": frequency,
        "rows": {
            "public_legacy": legacy_row,
            "a3_split_off": split_row,
            "a3": candidate_row,
        },
        "comparisons": comparisons,
        "highest_closed": closed,
        "delay_gate": delay_gate,
        "frequency_gate": frequency_gate,
        "quality_gate": quality_gate,
        "cpi_identity": cpi_result,
        "reasons": reasons,
    }


def run(legacy_root: Path, split_root: Path, candidate_root: Path,
        cpi_path: Path, output: Path) -> int:
    result = evaluate(
        load_matrix(legacy_root, "legacy", LEGACY_COMMIT),
        load_matrix(split_root, "a3_split_off", A3_COMMIT),
        load_matrix(candidate_root, "a3", A3_COMMIT),
        load_json(cpi_path),
    )
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print("{} output={}".format(result["status"], output))
    return 0 if result["merge_allowed"] else 2


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--legacy", type=Path, required=True)
    parser.add_argument("--split-off", type=Path, required=True)
    parser.add_argument("--a3", type=Path, required=True)
    parser.add_argument("--cpi-summary", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    return run(args.legacy, args.split_off, args.a3, args.cpi_summary, args.output)


if __name__ == "__main__":
    raise SystemExit(main())
