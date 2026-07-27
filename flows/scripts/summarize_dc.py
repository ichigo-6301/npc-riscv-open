#!/usr/bin/env python3
"""Fail-closed summary for register-expanded Design Compiler runs."""

import argparse
import csv
import json
import re
from pathlib import Path
from typing import Dict, Optional


def number(pattern: str, text: str, default=None):
    match = re.search(pattern, text, re.I | re.M)
    return float(match.group(1)) if match else default


def integer(pattern: str, text: str, default=None):
    value = number(pattern, text, default)
    return int(value) if value is not None else default


def contract_values(text: str) -> Dict[str, str]:
    values: Dict[str, str] = {}
    for line in text.splitlines():
        if "=" not in line:
            continue
        key, value = line.split("=", 1)
        if re.fullmatch(r"[a-z_]+", key):
            values[key] = value.strip()
    return values


def metric_float(values: Dict[str, str], key: str) -> Optional[float]:
    raw = values.get(key)
    if raw in (None, "", "NA"):
        return None
    try:
        return float(raw)
    except ValueError:
        return None


def metric_int(values: Dict[str, str], key: str) -> Optional[int]:
    value = metric_float(values, key)
    return int(value) if value is not None else None


def loop_evidence(text: str) -> int:
    patterns = (
        r"found\s+(?:a\s+)?(?:combinational|timing)\s+loop",
        r"(?:combinational|timing)\s+loop\s+(?:detected|found)",
        r"breaking\s+(?:a\s+)?timing\s+loop",
        r"timing\s+loop[^\n]*(?:disabled|broken)",
    )
    return sum(len(re.findall(pattern, text, re.I)) for pattern in patterns)


def automatic_arc_break_evidence(text: str) -> int:
    patterns = (
        r"automatic(?:ally)?[^\n]*(?:disable|break)[^\n]*timing[^\n]*arc",
        r"timing[^\n]*arc[^\n]*(?:automatically\s+disabled|auto[^\n]*broken)",
        r"disabling\s+timing\s+arc[^\n]*(?:loop|cyclic)",
    )
    return sum(len(re.findall(pattern, text, re.I)) for pattern in patterns)


def parse_run(run: Path) -> dict:
    read = lambda name: (run / name).read_text(errors="replace") if (run / name).is_file() else ""
    qor = read("qor.rpt")
    contract = read("run_contract.txt")
    values = contract_values(contract)
    timing = read("timing.rpt")
    constraints = read("constraints.rpt")
    check_design = read("check_design.rpt")
    dc_log = read("dc.log")
    timing_loops = read("timing_loops.rpt")
    check = "\n".join((read("check_timing.rpt"), dc_log, timing_loops))
    period = number(r"clock_period_ns=([-+0-9.eE]+)", contract)
    wns = metric_float(values, "setup_wns_ns")
    if wns is None:
        wns = number(r"Critical Path Slack:\s*([-+0-9.eE]+)", qor)
    if wns is None:
        wns = number(r"slack\s*\([^)]*\)\s*([-+0-9.eE]+)", timing)
    tns = metric_float(values, "setup_tns_ns")
    if tns is None:
        tns = number(r"Total Negative Slack:\s*([-+0-9.eE]+)", qor)
    violations = metric_int(values, "setup_violation_count")
    if violations is None:
        violations = integer(r"No\. of Violating Paths:\s*([0-9]+)", qor)
    area = number(r"Design Area:\s*([-+0-9.eE]+)", qor)
    if area is None:
        area = number(r"Total cell area:\s*([-+0-9.eE]+)", read("area.rpt"))
    macro_count = metric_int(values, "macro_count")
    blackbox_count = metric_int(values, "blackbox_count")
    cell_count = metric_int(values, "cell_count")
    register_count = metric_int(values, "register_count")
    loops = loop_evidence(check)
    auto_arcs = automatic_arc_break_evidence(dc_log)
    startpoint = re.search(r"^Startpoint:\s*(.+)$", timing, re.M)
    endpoint = re.search(r"^Endpoint:\s*(.+)$", timing, re.M)
    path_group = re.search(r"^Path Group:\s*(.+)$", timing, re.M)
    data_arrival = number(r"^\s*data arrival time\s+([-+0-9.eE]+)\s*$", timing)
    electrical_fields = (
        "max_transition_violation_count", "max_capacitance_violation_count",
        "max_fanout_violation_count", "min_period_violation_count",
        "min_pulse_width_violation_count",
    )
    electrical_counts = {key: metric_int(values, key) for key in electrical_fields}
    electrical_violations = (
        sum(electrical_counts.values())
        if all(value is not None for value in electrical_counts.values()) else None
    )
    if electrical_violations is None and constraints:
        electrical_violations = len(re.findall(r"(?i)\(VIOLATED\)", constraints))
    check_design_errors = len(re.findall(r"(?im)^\s*(?:Error:|\*\*ERROR)", check_design))
    completed = (run / "run.ok").is_file() and (run / "{}_mapped.v".format(
        re.search(r"^top=(\S+)", contract, re.M).group(1) if re.search(r"^top=(\S+)", contract, re.M) else "missing"
    )).is_file()
    required_native = {
        "check_design_ok": metric_int(values, "check_design_ok"),
        "check_timing_ok": metric_int(values, "check_timing_ok"),
        "unresolved_reference_count": metric_int(values, "unresolved_reference_count"),
        "latch_count": metric_int(values, "latch_count"),
        "unclocked_sync_endpoint_count": metric_int(values, "unclocked_sync_endpoint_count"),
    }
    missing_gate_fields = [key for key, value in {
        "period_ns": period, "wns_ns": wns, "tns_ns": tns,
        "violating_paths": violations, "macro_count": macro_count,
        "blackbox_count": blackbox_count,
        "electrical_violations": electrical_violations,
        **required_native,
    }.items() if value is None]
    loop_report_valid = bool(timing_loops) and "unavailable" not in timing_loops.lower()
    closed = bool(
        completed and not missing_gate_fields and loop_report_valid and
        wns >= -0.0005 and tns >= -0.0005 and violations == 0 and
        macro_count == 0 and blackbox_count == 0 and loops == 0 and auto_arcs == 0 and
        electrical_violations == 0 and check_design_errors == 0 and
        required_native["check_design_ok"] == 1 and
        required_native["check_timing_ok"] == 1 and
        required_native["unresolved_reference_count"] == 0 and
        required_native["latch_count"] == 0 and
        required_native["unclocked_sync_endpoint_count"] == 0
    )
    return {
        "run": run.name,
        "period_ns": period,
        "frequency_mhz": round(1000.0 / period, 6) if period else None,
        "wns_ns": wns,
        "tns_ns": tns,
        "violating_paths": violations,
        "area": area,
        "cell_count": cell_count,
        "register_count": register_count,
        "clocked_register_count": metric_int(values, "clocked_register_count"),
        "unclocked_sync_endpoint_count": required_native["unclocked_sync_endpoint_count"],
        "latch_count": required_native["latch_count"],
        "unresolved_reference_count": required_native["unresolved_reference_count"],
        "macro_count": macro_count,
        "blackbox_count": blackbox_count,
        "check_design_ok": required_native["check_design_ok"],
        "check_timing_ok": required_native["check_timing_ok"],
        "timing_loop_report_valid": loop_report_valid,
        "timing_loop_evidence": loops,
        "automatic_arc_break_evidence": auto_arcs,
        "electrical_violations": electrical_violations,
        **electrical_counts,
        "check_design_errors": check_design_errors,
        "hold_wns_ns": metric_float(values, "hold_wns_ns"),
        "hold_tns_ns": metric_float(values, "hold_tns_ns"),
        "hold_violating_paths": metric_int(values, "hold_violation_count"),
        "inferred_memory_bits": metric_int(values, "inferred_memory_bits"),
        "inferred_memory_bits_status": values.get("inferred_memory_bits_status"),
        "data_path_delay_ns": data_arrival,
        "startpoint": startpoint.group(1).strip() if startpoint else None,
        "endpoint": endpoint.group(1).strip() if endpoint else None,
        "path_group": path_group.group(1).strip() if path_group else None,
        "timer_clock_hz": integer(r"NPC_TIMER_CLK_HZ=([0-9]+)", values.get("rtl_defines", "")),
        "completed": completed,
        "missing_gate_fields": missing_gate_fields,
        "setup_closed": closed,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--matrix-root", type=Path, required=True)
    parser.add_argument("--json", type=Path, required=True)
    parser.add_argument("--csv", type=Path, required=True)
    args = parser.parse_args()
    rows = [parse_run(path) for path in sorted(args.matrix_root.glob("dc_*mhz")) if path.is_dir()]
    args.json.parent.mkdir(parents=True, exist_ok=True)
    args.json.write_text(json.dumps({"runs": rows}, indent=2, sort_keys=True) + "\n")
    with args.csv.open("w", newline="") as handle:
        writer = csv.DictWriter(handle, fieldnames=list(rows[0]) if rows else ["run"])
        writer.writeheader()
        writer.writerows(rows)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
