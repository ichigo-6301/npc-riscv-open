#!/usr/bin/env python3
"""Recover an audited handoff from a completed ORFS run after wrapper failure."""

import argparse
import json
from pathlib import Path
import re
import shutil
from typing import Dict

from sanitize_openroad_sdc import sanitize
from summarize_pnr import contract_values, parse_run, sha256_file


class RecoveryError(RuntimeError):
    pass


GIT_COMMIT_RE = re.compile(r"^[0-9a-f]{40}$")
OCI_DIGEST_RE = re.compile(r"^sha256:[0-9a-f]{64}$")
REPO_ROOT = Path(__file__).resolve().parents[2]
ASIC_MATRIX_REL = Path("flows/asic/profiles/register_expanded.json")
ORFS_RUNTIME_IDENTITY_POLICY = (
    "exact_oci_digest_git_head_when_vcs_metadata_present_v1")


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


def tracked_orfs_identity(repo_root: Path) -> dict:
    matrix_path = repo_root.resolve() / ASIC_MATRIX_REL
    require_file(matrix_path, "tracked ASIC matrix")
    try:
        matrix = json.loads(matrix_path.read_text(encoding="utf-8"))
    except json.JSONDecodeError as error:
        raise RecoveryError(f"malformed tracked ASIC matrix: {error}") from error
    identity = matrix.get("orfs")
    required = ("commit", "image_digest", "platform", "runtime_identity_policy")
    if not isinstance(identity, dict):
        raise RecoveryError("tracked ASIC matrix lacks ORFS identity")
    missing = [key for key in required if not identity.get(key)]
    if missing:
        raise RecoveryError(
            "tracked ASIC matrix ORFS identity lacks: " + ",".join(missing))
    if not GIT_COMMIT_RE.fullmatch(str(identity["commit"])):
        raise RecoveryError("tracked ASIC matrix has malformed ORFS commit")
    if not OCI_DIGEST_RE.fullmatch(str(identity["image_digest"])):
        raise RecoveryError("tracked ASIC matrix has malformed ORFS image digest")
    if identity["platform"] != "nangate45":
        raise RecoveryError("tracked ASIC matrix has unsupported ORFS platform")
    if identity["runtime_identity_policy"] != ORFS_RUNTIME_IDENTITY_POLICY:
        raise RecoveryError("tracked ASIC matrix ORFS identity policy mismatch")
    return identity


def runtime_identity(source_run: Path, contract: dict, tracked: dict) -> dict:
    report_path = source_run / "orfs_commit.txt"
    require_file(report_path, "ORFS runtime identity report")
    values: Dict[str, str] = {}
    for line in report_path.read_text(encoding="utf-8", errors="strict").splitlines():
        if "=" not in line:
            raise RecoveryError("malformed ORFS runtime identity report")
        key, value = line.split("=", 1)
        if key in values:
            raise RecoveryError(f"duplicate ORFS runtime identity field: {key}")
        values[key] = value
    if set(values) != {"actual_commit", "verification"}:
        raise RecoveryError("malformed ORFS runtime identity report fields")

    expected = contract["orfs_commit"]
    digest = contract["orfs_image_digest"]
    image = contract["orfs_image"]
    if not GIT_COMMIT_RE.fullmatch(expected):
        raise RecoveryError("source OpenROAD contract has malformed orfs_commit")
    if not OCI_DIGEST_RE.fullmatch(digest):
        raise RecoveryError("source OpenROAD contract has malformed orfs_image_digest")
    if image == "@" + digest or not image.endswith("@" + digest):
        raise RecoveryError("source OpenROAD image does not match its tracked digest")
    for contract_key, tracked_key in (
            ("orfs_commit", "commit"),
            ("orfs_image_digest", "image_digest"),
            ("platform", "platform")):
        if contract[contract_key] != tracked[tracked_key]:
            raise RecoveryError(
                f"source OpenROAD contract {contract_key} does not match tracked ASIC matrix")

    actual = values["actual_commit"]
    verification = values["verification"]
    if verification == "git_head":
        if not GIT_COMMIT_RE.fullmatch(actual) or actual != expected:
            raise RecoveryError("ORFS runtime Git identity mismatch")
    elif verification == "image_digest_bound_no_vcs_metadata":
        if actual != "not_embedded":
            raise RecoveryError("ORFS digest-bound runtime identity mismatch")
    else:
        raise RecoveryError("unsupported ORFS runtime identity verification mode")

    contract_identity = (
        contract["orfs_actual_commit"], contract["orfs_commit_verification"])
    if contract_identity not in (("NA", "pending"), (actual, verification)):
        raise RecoveryError("source OpenROAD contract/runtime identity mismatch")
    return {
        "expected_commit": expected,
        "actual_commit": actual,
        "verification": verification,
        "image_digest": digest,
        "image": image,
        "report_sha256": sha256_file(report_path),
    }


def copy_input_manifest(source_run: Path, output_run: Path) -> dict:
    source_path = source_run / "input_manifest.json"
    require_file(source_path, "input manifest")
    manifest = json.loads(source_path.read_text(encoding="utf-8"))
    source_input = (source_run / "input").resolve()
    output_input = output_run / "input"
    files = manifest.get("files")
    if not isinstance(files, dict) or not files:
        raise RecoveryError("source input manifest lacks files")
    source_files = {}
    for role, item in files.items():
        if not isinstance(item, dict) or not item.get("path") or not item.get("sha256"):
            raise RecoveryError(f"source input manifest has malformed role: {role}")
        old_path = Path(str(item["path"])).resolve()
        require_file(old_path, f"source input {role}")
        actual = sha256_file(old_path)
        if not re.fullmatch(r"[0-9a-f]{64}", str(item["sha256"])) or actual != item["sha256"]:
            raise RecoveryError(f"source input manifest hash mismatch: {role}")
        source_files[role] = old_path
    shutil.copytree(source_input, output_input)
    for role, item in files.items():
        old_path = source_files[role]
        try:
            relative = old_path.relative_to(source_input)
        except ValueError:
            continue
        new_path = output_input / relative
        require_file(new_path, "recovered input")
        if sha256_file(new_path) != item["sha256"]:
            raise RecoveryError(f"recovered input hash mismatch: {role}")
        item["path"] = str(new_path)
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


def recover(source_run: Path, output_run: Path, repo_root: Path = REPO_ROOT) -> dict:
    source_run = source_run.resolve()
    output_run = output_run.resolve()
    if output_run.exists():
        raise RecoveryError(f"refusing to overwrite recovery run: {output_run}")
    if (source_run / "run.ok").exists():
        raise RecoveryError("source run is already complete; recovery is not applicable")
    tracked_identity = tracked_orfs_identity(repo_root)
    contract = contract_values(source_run / "openroad_contract.txt")
    for key in ("design_nickname", "top", "memory_mode", "expected_macro_count",
                "platform", "pnr_period_ns", "orfs_commit", "orfs_actual_commit",
                "orfs_commit_verification", "orfs_image_digest", "orfs_image",
                "mapped_netlist_sha256", "orfs_import_netlist_sha256"):
        if not contract.get(key):
            raise RecoveryError(f"source OpenROAD contract lacks {key}")
    identity = runtime_identity(source_run, contract, tracked_identity)
    contract["orfs_actual_commit"] = identity["actual_commit"]
    contract["orfs_commit_verification"] = identity["verification"]
    source_summary = parse_run(source_run)
    clean_route_gate(source_summary)
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
                 "orfs_commit.txt", "resource_monitor.csv"):
        path = source_run / name
        if path.is_file():
            shutil.copy2(path, output_run / name)
    macro_report = source_run / "macro_placement_report.txt"
    if macro_report.is_file():
        shutil.copy2(macro_report, output_run / macro_report.name)
    shutil.copytree(source_run / "orfs", output_run / "orfs", copy_function=shutil.copy2)

    mapped = Path(manifest["files"]["dc_mapped_netlist"]["path"])
    require_file(mapped, "DC mapped netlist")
    imported = output_run / "orfs/results/nangate45" / nickname / "base/1_2_yosys.v"
    mapped_hash = sha256_file(mapped)
    imported_hash = sha256_file(imported)
    if contract["mapped_netlist_sha256"] != mapped_hash:
        raise RecoveryError("source OpenROAD contract mapped netlist hash mismatch")
    if contract["orfs_import_netlist_sha256"] not in ("NA", imported_hash):
        raise RecoveryError("source OpenROAD contract ORFS import hash mismatch")
    if mapped_hash != imported_hash:
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
    contract["mapped_netlist_sha256"] = mapped_hash
    contract["orfs_import_netlist_sha256"] = imported_hash
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
        "orfs_runtime_identity": identity["report_sha256"],
    }
    recovery_tool_hashes = {
        "recover_pnr_handoff": sha256_file(Path(__file__).resolve()),
        "sanitize_openroad_sdc": sha256_file(
            Path(sanitize.__code__.co_filename).resolve()),
        "summarize_pnr": sha256_file(
            Path(parse_run.__code__.co_filename).resolve()),
    }
    write_json(output_run / "recovery_manifest.json", {
        "schema": "npc-riscv-open/d8-pnr-postprocess-recovery-v2",
        "source_run": str(source_run),
        "source_wrapper_exit_status": source_exit,
        "source_status": source_summary["status"],
        "source_missing_artifacts": source_summary["missing_artifacts"],
        "physical_implementation_rerun": False,
        "orfs_workspace_reused_read_only": False,
        "orfs_workspace_preservation": "self_contained_copy",
        "tracked_orfs_identity": tracked_identity,
        "source_period_ns": source_period,
        "normalized_period_ns": period_ns,
        "orfs_runtime_identity": identity,
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
    parser.add_argument("--repo-root", type=Path, default=REPO_ROOT)
    args = parser.parse_args()
    try:
        summary = recover(args.source_run, args.output_run, args.repo_root)
    except (OSError, ValueError, KeyError, json.JSONDecodeError, RecoveryError) as error:
        raise SystemExit(f"PNR_HANDOFF_RECOVERY_FAILED: {error}") from error
    print(
        "PNR_HANDOFF_RECOVERY_PASS "
        f"run={args.output_run.resolve()} route_complete={summary['route_complete']}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
