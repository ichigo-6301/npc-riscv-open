#!/usr/bin/env python3
"""Recover an audited handoff from a completed ORFS run after wrapper failure."""

import argparse
import json
import os
from pathlib import Path
import shutil
from typing import Dict

from sanitize_openroad_sdc import sanitize
from summarize_pnr import contract_values, parse_run, sha256_file


class RecoveryError(RuntimeError):
    pass


def write_json(path: Path, value: object) -> None:
    path.write_text(json.dumps(value, indent=2, sort_keys=True) + "\n", encoding="utf-8")


def require_file(path: Path, role: str, *, allow_empty: bool = False) -> None:
    if not path.is_file() or (not allow_empty and path.stat().st_size == 0):
        raise RecoveryError(f"missing completed ORFS artifact {role}: {path}")


def clean_route_gate(summary: dict) -> None:
    expected_zero = (
        "detail_route_drc_count",
        "antenna_net_count",
        "antenna_pin_count",
        "route_flow_error_count",
        "finish_flow_error_count",
    )
    failures = [f"{key}={summary.get(key)}" for key in expected_zero
                if summary.get(key) != 0]
    if summary.get("missing_metrics"):
        failures.append(f"missing_metrics={summary['missing_metrics']}")
    if summary.get("macro_count") != summary.get("expected_macro_count"):
        failures.append(
            f"macro_count={summary.get('macro_count')} expected={summary.get('expected_macro_count')}"
        )
    if summary.get("dc_constant_nets_found") != (
            summary.get("dc_constant_nets_normalized", -1) +
            summary.get("dc_constant_nets_already_signal", -1)):
        failures.append("DC constant-net normalization is incomplete")
    if failures:
        raise RecoveryError("source run is not eligible for handoff recovery: " + ", ".join(failures))


def copy_input_manifest(source_run: Path, output_run: Path) -> dict:
    source_path = source_run / "input_manifest.json"
    require_file(source_path, "input manifest")
    manifest = json.loads(source_path.read_text(encoding="utf-8"))
    source_input = (source_run / "input").resolve()
    output_input = output_run / "input"
    shutil.copytree(source_input, output_input)
    for item in manifest.get("files", {}).values():
        if not isinstance(item, dict) or not item.get("path"):
            continue
        old_path = Path(str(item["path"])).resolve()
        try:
            relative = old_path.relative_to(source_input)
        except ValueError:
            continue
        new_path = output_input / relative
        require_file(new_path, "recovered input")
        item["path"] = str(new_path)
        item["sha256"] = sha256_file(new_path)
    write_json(output_run / "input_manifest.json", manifest)
    return manifest


def write_checksums(handoff: Path, top: str) -> None:
    names = (
        f"{top}_postroute.v",
        f"{top}_postroute.sdc",
        f"{top}_postroute.spef",
        f"{top}_postroute.odb",
        f"{top}_postroute.def",
        f"{top}.gds",
    )
    lines = [f"{sha256_file(handoff / name)}  {name}\n" for name in names]
    (handoff / "SHA256SUMS").write_text("".join(lines), encoding="ascii")


def same_run_artifacts(output_run: Path, top: str, mapped: Path,
                       imported: Path) -> dict:
    handoff = output_run / "handoff"
    mapped_hash = sha256_file(mapped)
    imported_hash = sha256_file(imported)
    if mapped_hash != imported_hash:
        raise RecoveryError("FAIL_HANDOFF_IDENTITY: DC/ORFS mapped netlist hashes differ")
    return {
        "mapped_netlist": {
            "dc_output_sha256": mapped_hash,
            "pnr_input_sha256": mapped_hash,
            "orfs_import_sha256": imported_hash,
        },
        "routed_netlist": {
            "pnr_output_sha256": sha256_file(handoff / f"{top}_postroute.v"),
        },
        "routed_sdc": {
            "pnr_output_sha256": sha256_file(handoff / f"{top}_postroute.sdc"),
        },
        "routed_database": {
            "pnr_output_sha256": sha256_file(handoff / f"{top}_postroute.odb"),
            "openrcx_input_sha256": sha256_file(handoff / f"{top}_postroute.odb"),
        },
        "routed_def": {
            "pnr_output_sha256": sha256_file(handoff / f"{top}_postroute.def"),
        },
        "spef": {
            "openrcx_output_sha256": sha256_file(handoff / f"{top}_postroute.spef"),
        },
        "gds": {
            "pnr_output_sha256": sha256_file(handoff / f"{top}.gds"),
        },
    }


def recover(source_run: Path, output_run: Path) -> dict:
    source_run = source_run.resolve()
    output_run = output_run.resolve()
    if output_run.exists():
        raise RecoveryError(f"refusing to overwrite recovery run: {output_run}")
    if (source_run / "run.ok").exists():
        raise RecoveryError("source run is already complete; recovery is not applicable")
    source_summary = parse_run(source_run)
    clean_route_gate(source_summary)
    contract = contract_values(source_run / "openroad_contract.txt")
    for key in ("design_nickname", "top", "memory_mode", "expected_macro_count",
                "pnr_period_ns", "orfs_commit", "orfs_image"):
        if not contract.get(key):
            raise RecoveryError(f"source OpenROAD contract lacks {key}")
    nickname = contract["design_nickname"]
    top = contract["top"]
    period_ns = float(contract["pnr_period_ns"])
    results = source_run / "orfs/results/nangate45" / nickname / "base"
    logs = source_run / "orfs/logs/nangate45" / nickname / "base"
    reports = source_run / "orfs/reports/nangate45" / nickname / "base"
    required_results = (
        "1_2_yosys.v", "6_final.odb", "6_final.def", "6_final.v",
        "6_final.sdc", "6_final.spef", "6_final.gds",
    )
    for name in required_results:
        require_file(results / name, name)
    for name in ("5_2_route.json", "6_report.json"):
        require_file(logs / name, name)
    require_file(reports / "5_route_drc.rpt", "route DRC report", allow_empty=True)

    output_run.parent.mkdir(parents=True, exist_ok=True)
    output_run.mkdir()
    manifest = copy_input_manifest(source_run, output_run)
    for name in ("floorplan.json", "constant_net_report.txt", "openroad_contract.txt",
                 "resource_monitor.csv"):
        path = source_run / name
        if path.is_file():
            shutil.copy2(path, output_run / name)
    macro_report = source_run / "macro_placement_report.txt"
    if macro_report.is_file():
        shutil.copy2(macro_report, output_run / macro_report.name)
    os.symlink(source_run / "orfs", output_run / "orfs", target_is_directory=True)

    mapped = Path(manifest["files"]["dc_mapped_netlist"]["path"])
    require_file(mapped, "DC mapped netlist")
    imported = output_run / "orfs/results/nangate45" / nickname / "base/1_2_yosys.v"
    if sha256_file(mapped) != sha256_file(imported):
        raise RecoveryError("FAIL_HANDOFF_IDENTITY: mapped netlist differs from ORFS import")

    handoff = output_run / "handoff"
    handoff.mkdir()
    for source_name, output_name in (
        ("6_final.v", f"{top}_postroute.v"),
        ("6_final.spef", f"{top}_postroute.spef"),
        ("6_final.odb", f"{top}_postroute.odb"),
        ("6_final.def", f"{top}_postroute.def"),
        ("6_final.gds", f"{top}.gds"),
    ):
        shutil.copy2(results / source_name, handoff / output_name)
    source_period = sanitize(
        results / "6_final.sdc", handoff / f"{top}_postroute.sdc", period_ns)
    write_checksums(handoff, top)

    roles = same_run_artifacts(output_run, top, mapped, imported)
    write_json(output_run / "same_run_artifacts.json", roles)
    contract["mapped_netlist_sha256"] = sha256_file(mapped)
    contract["orfs_import_netlist_sha256"] = sha256_file(imported)
    contract["handoff_recovery"] = "postprocess_only_no_physical_rerun"
    (output_run / "openroad_contract.txt").write_text(
        "".join(f"{key}={value}\n" for key, value in contract.items()),
        encoding="utf-8",
    )
    source_exit = (source_run / "exit_status.txt").read_text().strip()
    source_hashes: Dict[str, str] = {
        "summary": sha256_file(source_run / "summary.json"),
        "openroad_log": sha256_file(source_run / "openroad.log"),
        "exit_status": sha256_file(source_run / "exit_status.txt"),
        "final_sdc": sha256_file(results / "6_final.sdc"),
        "final_gds": sha256_file(results / "6_final.gds"),
        "final_spef": sha256_file(results / "6_final.spef"),
    }
    recovery_tool_hashes = {
        "recover_pnr_handoff": sha256_file(Path(__file__).resolve()),
        "sanitize_openroad_sdc": sha256_file(
            Path(sanitize.__code__.co_filename).resolve()),
        "summarize_pnr": sha256_file(
            Path(parse_run.__code__.co_filename).resolve()),
    }
    write_json(output_run / "recovery_manifest.json", {
        "schema": "npc-riscv-open/d8-pnr-postprocess-recovery-v1",
        "source_run": str(source_run),
        "source_wrapper_exit_status": source_exit,
        "source_status": source_summary["status"],
        "source_missing_artifacts": source_summary["missing_artifacts"],
        "physical_implementation_rerun": False,
        "orfs_workspace_reused_read_only": True,
        "source_period_ns": source_period,
        "normalized_period_ns": period_ns,
        "source_artifact_sha256": source_hashes,
        "recovery_tool_sha256": recovery_tool_hashes,
        "same_run_artifacts": roles,
    })
    (output_run / "exit_status.txt").write_text("0\n", encoding="ascii")
    summary = parse_run(output_run)
    write_json(output_run / "summary.json", summary)
    if not summary["route_complete"]:
        raise RecoveryError(
            "recovered handoff did not pass route gate: "
            f"missing_artifacts={summary['missing_artifacts']} "
            f"missing_metrics={summary['missing_metrics']}"
        )
    (output_run / "run.ok").write_text("PNR_RCX_RECOVERED_POSTPROCESS_ONLY\n", encoding="ascii")
    return summary


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-run", required=True, type=Path)
    parser.add_argument("--output-run", required=True, type=Path)
    args = parser.parse_args()
    try:
        summary = recover(args.source_run, args.output_run)
    except (OSError, ValueError, KeyError, json.JSONDecodeError, RecoveryError) as error:
        raise SystemExit(f"PNR_HANDOFF_RECOVERY_FAILED: {error}") from error
    print(
        "PNR_HANDOFF_RECOVERY_PASS "
        f"run={args.output_run.resolve()} route_complete={summary['route_complete']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
