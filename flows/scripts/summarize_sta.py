#!/usr/bin/env python3
"""Fail-closed PrimeTime summary for one D8 post-route run."""

import re
from pathlib import Path
from typing import Dict, Optional


def values(path: Path) -> Dict[str, str]:
    result: Dict[str, str] = {}
    if not path.is_file():
        return result
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            result[key.strip()] = value.strip()
    return result


def floating(record: Dict[str, str], key: str) -> Optional[float]:
    raw = record.get(key)
    if raw in (None, "", "NA"):
        return None
    try:
        return float(raw)
    except ValueError:
        return None


def integer(record: Dict[str, str], key: str) -> Optional[int]:
    value = floating(record, key)
    return int(value) if value is not None else None


def unannotated_parasitic_count(path: Path) -> Optional[int]:
    if not path.is_file():
        return None
    text = path.read_text(encoding="utf-8", errors="replace")
    if "unavailable" in text.lower():
        return None
    total = None
    pattern = re.compile(
        r"^\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|\s*[0-9]+\s*\|"
        r"\s*[0-9]+\s*\|\s*([0-9]+)\s*\|\s*$"
    )
    for line in text.splitlines():
        match = pattern.match(line)
        if match:
            total = int(match.group(1))
    if total is None and re.search(r"(?i)all\s+parasitics\s+(?:are\s+)?annotated", text):
        total = 0
    return total


def parse_run(run: Path) -> dict:
    record = values(run / "run_contract.txt")
    numeric_fields = (
        "clock_period_ns", "setup_wns_ns", "setup_tns_ns",
        "setup_violation_count", "hold_wns_ns", "hold_tns_ns",
        "hold_violation_count", "register_count", "clocked_register_count",
        "unclocked_sync_endpoint_count", "synchronous_endpoint_coverage_percent",
        "max_transition_violation_count", "max_capacitance_violation_count",
        "max_fanout_violation_count", "min_period_violation_count",
        "min_pulse_width_violation_count", "expected_macro_count", "macro_count", "link_ok",
        "read_sdc_ok", "read_parasitics_ok", "check_timing_ok",
    )
    parsed = {key: floating(record, key) for key in numeric_fields}
    missing_fields = [key for key, value in parsed.items() if value is None]
    required_reports = (
        "setup_timing.rpt", "hold_timing.rpt", "setup_summary.rpt",
        "hold_summary.rpt", "constraint_violations.rpt",
        "analysis_coverage.rpt", "check_timing.rpt", "parasitic_annotation.rpt",
        "macro_instances.rpt",
    )
    missing_reports = [name for name in required_reports
                       if not (run / name).is_file() or (run / name).stat().st_size == 0]
    unannotated = unannotated_parasitic_count(run / "parasitic_annotation.rpt")
    check_text = (run / "check_timing.rpt").read_text(
        encoding="utf-8", errors="replace") if (run / "check_timing.rpt").is_file() else ""
    native_log = (run / "primetime.log").read_text(
        encoding="utf-8", errors="replace") if (run / "primetime.log").is_file() else ""
    rc004_count = check_text.count("RC-004") + native_log.count("RC-004")
    no_driving_count = sum(int(value) for value in re.findall(
        r"(?im)^Warning:\s+There\s+(?:is|are)\s+([0-9]+)\s+ports?\s+"
        r"with parasitics but with no driving cell\.\s*$", check_text + "\n" + native_log))
    native_errors = [line.strip() for line in re.findall(
        r"(?im)^\s*(?:Error|Fatal):.*$", native_log)]
    setup_closed = bool(
        parsed["setup_wns_ns"] is not None and parsed["setup_tns_ns"] is not None and
        parsed["setup_violation_count"] is not None and
        parsed["setup_wns_ns"] >= -0.0005 and
        parsed["setup_tns_ns"] >= -0.0005 and parsed["setup_violation_count"] == 0
    )
    hold_closed = bool(
        parsed["hold_wns_ns"] is not None and parsed["hold_tns_ns"] is not None and
        parsed["hold_violation_count"] is not None and
        parsed["hold_wns_ns"] >= -0.0005 and
        parsed["hold_tns_ns"] >= -0.0005 and parsed["hold_violation_count"] == 0
    )
    electrical_fields = (
        "max_transition_violation_count", "max_capacitance_violation_count",
        "max_fanout_violation_count", "min_period_violation_count",
        "min_pulse_width_violation_count",
    )
    electrical_clean = all(parsed[key] == 0 for key in electrical_fields)
    coverage_clean = bool(
        parsed["register_count"] is not None and parsed["register_count"] > 0 and
        parsed["clocked_register_count"] == parsed["register_count"] and
        parsed["unclocked_sync_endpoint_count"] == 0 and
        parsed["synchronous_endpoint_coverage_percent"] is not None and
        abs(parsed["synchronous_endpoint_coverage_percent"] - 100.0) < 1e-6
    )
    complete = bool(
        not missing_fields and not missing_reports and not native_errors and
        parsed["link_ok"] == 1 and parsed["read_sdc_ok"] == 1 and
        parsed["read_parasitics_ok"] == 1 and parsed["check_timing_ok"] == 1 and
        parsed["macro_count"] == parsed["expected_macro_count"] and
        unannotated == 0 and coverage_clean
    )
    timing_closed = bool(complete and setup_closed and hold_closed)
    all_constraints_clean = bool(timing_closed and electrical_clean)
    memory_mode = record.get("memory_mode", "registers")
    if all_constraints_clean:
        status = "STA_CLOSED"
    elif timing_closed:
        status = "STA_TIMING_CLOSED_ELECTRICAL_PARTIAL"
    elif memory_mode == "sram" and complete and setup_closed and not hold_closed:
        status = "SRAM_IMPLEMENTATION_COMPLETE_TIMING_PARTIAL"
    else:
        status = "STA_PARTIAL"
    return {
        "status": status,
        "top": record.get("top"),
        "analysis": record.get("analysis"),
        "memory_mode": memory_mode,
        "expected_macro_count": integer(record, "expected_macro_count"),
        "macro_count": integer(record, "macro_count"),
        "macro_minimum_period_contract": record.get("macro_minimum_period_contract", ""),
        "clock_period_ns": parsed["clock_period_ns"],
        "setup_wns_ns": parsed["setup_wns_ns"],
        "setup_tns_ns": parsed["setup_tns_ns"],
        "setup_violating_paths": integer(record, "setup_violation_count"),
        "hold_wns_ns": parsed["hold_wns_ns"],
        "hold_tns_ns": parsed["hold_tns_ns"],
        "hold_violating_paths": integer(record, "hold_violation_count"),
        "register_count": integer(record, "register_count"),
        "clocked_register_count": integer(record, "clocked_register_count"),
        "unclocked_sync_endpoint_count": integer(record, "unclocked_sync_endpoint_count"),
        "synchronous_endpoint_coverage_percent": parsed["synchronous_endpoint_coverage_percent"],
        "max_transition_violations": integer(record, "max_transition_violation_count"),
        "max_capacitance_violations": integer(record, "max_capacitance_violation_count"),
        "max_fanout_violations": integer(record, "max_fanout_violation_count"),
        "min_period_violations": integer(record, "min_period_violation_count"),
        "min_pulse_width_violations": integer(record, "min_pulse_width_violation_count"),
        "unannotated_parasitic_count": unannotated,
        "rc004_count": rc004_count,
        "no_driving_cell_port_count": no_driving_count,
        "coverage_clean": coverage_clean,
        "setup_closed": setup_closed,
        "hold_closed": hold_closed,
        "electrical_clean": electrical_clean,
        "sta_complete": complete,
        "timing_closed": timing_closed,
        "sta_closed": timing_closed,
        "all_constraints_clean": all_constraints_clean,
        "missing_fields": missing_fields,
        "missing_reports": missing_reports,
        "native_errors": native_errors,
    }
