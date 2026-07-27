#!/usr/bin/env python3
"""Fail-closed OpenROAD/OpenRCX summary for one D7 physical run."""

import json
from pathlib import Path
from typing import Dict, Optional


def sha256_file(path: Path) -> str:
    import hashlib
    digest = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024 * 1024), b""):
            digest.update(block)
    return digest.hexdigest()


def contract_values(path: Path) -> Dict[str, str]:
    values: Dict[str, str] = {}
    if not path.is_file():
        return values
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "=" in line:
            key, value = line.split("=", 1)
            values[key.strip()] = value.strip()
    return values


def read_metrics(path: Path) -> Dict[str, float]:
    if not path.is_file() or path.stat().st_size == 0:
        return {}
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}
    if isinstance(value, dict) and isinstance(value.get("metrics"), dict):
        value = value["metrics"]
    if not isinstance(value, dict):
        return {}
    return {str(key): item for key, item in value.items()
            if isinstance(item, (int, float))}


def metric(metrics: Dict[str, float], name: str) -> Optional[float]:
    value = metrics.get(name)
    return float(value) if isinstance(value, (int, float)) else None


def parse_run(run: Path) -> dict:
    contract = contract_values(run / "openroad_contract.txt")
    nickname = contract.get("design_nickname", "")
    top = contract.get("top", "")
    base = run / "orfs"
    results = base / "results/nangate45" / nickname / "base"
    logs = base / "logs/nangate45" / nickname / "base"
    reports = base / "reports/nangate45" / nickname / "base"
    handoff = run / "handoff"
    route_metrics_path = logs / "5_2_route.json"
    final_metrics_path = logs / "6_report.json"
    route = read_metrics(route_metrics_path)
    final = read_metrics(final_metrics_path)
    expected = {
        "orfs_import_netlist": results / "1_2_yosys.v",
        "routed_database": handoff / (top + "_postroute.odb"),
        "routed_def": handoff / (top + "_postroute.def"),
        "routed_netlist": handoff / (top + "_postroute.v"),
        "routed_sdc": handoff / (top + "_postroute.sdc"),
        "spef": handoff / (top + "_postroute.spef"),
        "gds": handoff / (top + ".gds"),
        "route_drc_report": reports / "5_route_drc.rpt",
        "route_metrics": route_metrics_path,
        "final_metrics": final_metrics_path,
    }
    missing_artifacts = [role for role, path in expected.items()
                         if not path.is_file() or path.stat().st_size == 0]
    drc = metric(route, "detailedroute__route__drc_errors")
    antenna_nets = metric(route, "detailedroute__antenna__violating__nets")
    antenna_pins = metric(route, "detailedroute__antenna__violating__pins")
    route_errors = metric(route, "detailedroute__flow__errors__count")
    finish_errors = metric(final, "finish__flow__errors__count")
    macro_count = metric(final, "finish__design__instance__count__macros")
    max_slew = metric(final, "finish__timing__drv__max_slew")
    max_cap = metric(final, "finish__timing__drv__max_cap")
    max_fanout = metric(final, "finish__timing__drv__max_fanout")
    setup_wns = metric(final, "finish__timing__setup__ws")
    setup_tns = metric(final, "finish__timing__setup__tns")
    hold_wns = metric(final, "finish__timing__hold__ws")
    hold_tns = metric(final, "finish__timing__hold__tns")
    setup_violations = metric(final, "finish__timing__drv__setup_violation_count")
    hold_violations = metric(final, "finish__timing__drv__hold_violation_count")
    required_metrics = {
        "detail_route_drc_count": drc,
        "antenna_net_count": antenna_nets,
        "antenna_pin_count": antenna_pins,
        "route_flow_error_count": route_errors,
        "finish_flow_error_count": finish_errors,
        "macro_count": macro_count,
        "max_transition_violations": max_slew,
        "max_capacitance_violations": max_cap,
        "max_fanout_violations": max_fanout,
        "setup_wns_ns": setup_wns,
        "setup_tns_ns": setup_tns,
        "hold_wns_ns": hold_wns,
        "hold_tns_ns": hold_tns,
        "setup_violating_paths": setup_violations,
        "hold_violating_paths": hold_violations,
    }
    missing_metrics = [key for key, value in required_metrics.items() if value is None]
    exit_status = None
    try:
        exit_status = int((run / "exit_status.txt").read_text().strip())
    except (OSError, ValueError):
        pass
    route_clean = bool(
        exit_status == 0 and not missing_artifacts and not missing_metrics and
        drc == 0 and antenna_nets == 0 and antenna_pins == 0 and
        route_errors == 0 and finish_errors == 0 and macro_count == 0
    )
    electrical_clean = bool(
        max_slew == 0 and max_cap == 0 and max_fanout == 0
        if not missing_metrics else False
    )
    setup_closed = bool(
        setup_wns is not None and setup_tns is not None and setup_violations is not None and
        setup_wns >= -0.0005 and setup_tns >= -0.0005 and setup_violations == 0
    )
    hold_closed = bool(
        hold_wns is not None and hold_tns is not None and hold_violations is not None and
        hold_wns >= -0.0005 and hold_tns >= -0.0005 and hold_violations == 0
    )
    hashes = {role: sha256_file(path) for role, path in expected.items()
              if path.is_file() and path.stat().st_size > 0}
    return {
        "status": "PNR_RCX_COMPLETE" if route_clean else "PNR_RCX_PARTIAL",
        "top": top,
        "design_nickname": nickname,
        "period_ns": float(contract["pnr_period_ns"]) if contract.get("pnr_period_ns") else None,
        "memory_mode": contract.get("memory_mode"),
        "macro_count": int(macro_count) if macro_count is not None else None,
        "detail_route_drc_count": int(drc) if drc is not None else None,
        "antenna_net_count": int(antenna_nets) if antenna_nets is not None else None,
        "antenna_pin_count": int(antenna_pins) if antenna_pins is not None else None,
        "unrouted_net_count": 0 if route_clean else None,
        "unrouted_net_audit": "ORFS detail_route.tcl design_is_routed hard gate",
        "route_flow_error_count": int(route_errors) if route_errors is not None else None,
        "finish_flow_error_count": int(finish_errors) if finish_errors is not None else None,
        "setup_wns_ns": setup_wns,
        "setup_tns_ns": setup_tns,
        "setup_violating_paths": int(setup_violations) if setup_violations is not None else None,
        "hold_wns_ns": hold_wns,
        "hold_tns_ns": hold_tns,
        "hold_violating_paths": int(hold_violations) if hold_violations is not None else None,
        "max_transition_violations": int(max_slew) if max_slew is not None else None,
        "max_capacitance_violations": int(max_cap) if max_cap is not None else None,
        "max_fanout_violations": int(max_fanout) if max_fanout is not None else None,
        "die_area_um2": metric(final, "finish__design__die__area"),
        "core_area_um2": metric(final, "finish__design__core__area"),
        "standard_cell_area_um2": metric(final, "finish__design__instance__area__stdcell"),
        "standard_cell_count": metric(final, "finish__design__instance__count__stdcell"),
        "utilization": metric(final, "finish__design__instance__utilization"),
        "route_complete": route_clean,
        "openroad_setup_closed": setup_closed,
        "openroad_hold_closed": hold_closed,
        "openroad_electrical_clean": electrical_clean,
        "missing_artifacts": missing_artifacts,
        "missing_metrics": missing_metrics,
        "artifact_sha256": hashes,
    }
