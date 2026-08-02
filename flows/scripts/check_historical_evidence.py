#!/usr/bin/env python3
"""Validate bounded Linux, OoO and FPGA historical evidence."""

from __future__ import annotations

import argparse
import hashlib
import json
import math
from pathlib import Path
import re


LINUX_AB_PATH = "evidence/performance/linux_coremark_ab.json"
LINUX_BOOT_PATH = "evidence/system/linux_boot.json"
OOO_PATH = "evidence/performance/ooo_frontend_branch_ab.json"
FPGA_PATH = "evidence/fpga/single_xc7z100_history.json"
CLAIMS_PATH = "delivery/claims/claims.yaml"
MANIFEST_PATH = "delivery/evidence/manifest.yaml"

SHA256_RE = re.compile(r"[0-9a-f]{64}")
SHA1_RE = re.compile(r"[0-9a-f]{40}")

EXPECTED_EVIDENCE = {
    "linux_coremark_history_public": LINUX_AB_PATH,
    "linux_boot_history_public": LINUX_BOOT_PATH,
    "ooo_historical_optimization_public": OOO_PATH,
    "single_xc7z100_history_public": FPGA_PATH,
}

EXPECTED_CLAIM_STATUS = {
    "linux_historical_no_tlb_whole_cpi": "partial",
    "linux_historical_optimized_whole_cpi": "verified",
    "linux_historical_approx_speedup": "partial",
    "linux_historical_boot_to_initramfs_shell": "verified",
    "ooo_historical_frontend_empty_baseline_percent": "verified",
    "ooo_historical_frontend_empty_s9b_percent": "verified",
    "ooo_historical_redirect_direct_jal_percent": "verified",
    "ooo_historical_redirect_btfnt_percent": "verified",
    "ooo_historical_redirect_btb_bht_percent": "verified",
    "ooo_historical_redirect_jalr_ras_percent": "verified",
    "single_fpga_original_routed_frequency": "verified",
    "single_fpga_original_setup_wns": "verified",
    "single_fpga_original_hold_whs": "verified",
    "single_fpga_historical_board_observation": "partial",
    "single_fpga_forward_routed_frequency": "verified",
    "single_fpga_forward_setup_wns": "verified",
    "single_fpga_forward_hold_whs": "verified",
    "single_fpga_predict_routed_frequency": "verified",
    "single_fpga_predict_setup_wns": "verified",
    "single_fpga_predict_hold_whs": "verified",
}

FPGA_DIMENSIONS = {
    "fpga_source_ready",
    "fpga_rtl_simulation",
    "fpga_synthesis",
    "fpga_implementation",
    "fpga_timing",
    "fpga_bitstream",
    "fpga_board_smoke",
    "fpga_workload_validation",
}

EXPECTED_FPGA = {
    "single_board_20260507": {
        "date": "2026-05-07",
        "source_manifest_sha256": "22b79e835c05ea34c7628997d2e2880c85065eea24ad125c66b9b52a6669ae48",
        "setup_wns_ns": 0.083,
        "hold_whs_ns": 0.044,
        "drc_warnings": 4,
        "artifacts": {
            "synthesis_checkpoint_sha256": "31a8eb245fae4ddd36ac64736924b4348dacfbded0328545e5d5e96d0e061a91",
            "routed_checkpoint_sha256": "34552602573ff2f89fbdfc85de5c9ea4c8dcea3b58a3cb6db53bdfec01fd8cc6",
            "timing_report_sha256": "09cb5a8d92a8aa2a0ccfe734e4605f19fbbcab805414e0b77232406a23b00b73",
            "route_report_sha256": "03d32fc54a7e4fb6975336f9cded73dbbda2068a13c5b655c18176177ffd2b0d",
            "drc_report_sha256": "a8804e4481e8a0d1ff221f93843c148a54f294779848f040d96231a0220ad7ee",
            "implementation_bitstream_sha256": "224c4e5fd078d130d5ca45d264561316bc6b8e0c128ae9168bf9b71a4dfa7795",
            "debug_probes_sha256": "804b7f8a37c249baeccd0ddb80ecf4cd6552569d457ea7eaa39d67698603c887",
            "vitis_xsa_sha256": "17abc3ec67509473f9139e746d6c426f76e94f538c0afa7f328b8ee821e34cd0",
            "vitis_bitstream_sha256": "025ed26a8653e58eb0f9db2a05e7281ff68b1c6b027183cccd60cbd69b6757a4",
            "vitis_software_elf_sha256": "37d07f71bc2e40e003fcb719a85e302e84ce61e01432ba3a093a307c09dc2d2c",
            "uart_log_sha256": "0de04b5b0c193b439aa857babfce2723e0c6eb958188f479d7c1ffcd48b69bd5",
            "ila_csv_sha256": "ed8562025618ef35b18ae6d8c692a35938920e38a8b79498e3841c96735e4511",
        },
    },
    "single_forward_20260512": {
        "date": "2026-05-12",
        "source_manifest_sha256": "dc9ac7981ee3c6c4cade2a427409af3e8f3f5c56045a390b75efc472c73a7256",
        "setup_wns_ns": 0.010,
        "hold_whs_ns": 0.040,
        "drc_warnings": 6,
        "artifacts": {
            "synthesis_checkpoint_sha256": "2c1736bcb499b2731723937e9742c88b14ad3de9606d24f0524bcb785dc4a293",
            "routed_checkpoint_sha256": "facbdd113e237773d6a7194f9df7f0a390843d83d7ff506ef3bdca8908e567d7",
            "timing_report_sha256": "bd43f1af0f37d57df2f5b6e64f390cdde2e0a929a9cae5c423966143a9ccecab",
            "route_report_sha256": "62227cbd96a34810dd6fcfa4fff89864a9361b94f0819d004b824c782f6315f8",
            "drc_report_sha256": "811ac13af96480f59bfe2e76eee114e7719ab83fb8c8600c5c202e43c2619270",
            "copied_older_xsa_sha256": "17abc3ec67509473f9139e746d6c426f76e94f538c0afa7f328b8ee821e34cd0",
        },
    },
    "single_predict_20260515": {
        "date": "2026-05-15",
        "source_manifest_sha256": "58e3681a0455c11ba24a9d3640ea0152c4d4d8c22ff5c59733f131940af32d4d",
        "setup_wns_ns": 0.010,
        "hold_whs_ns": 0.045,
        "drc_warnings": 6,
        "artifacts": {
            "synthesis_checkpoint_sha256": "25ca9e123e4e2a6ba65889d59b8a8faf64aad38b37d753a86b415daab2faf05c",
            "routed_checkpoint_sha256": "19191b1f2f6f49e1ff7784dea24572af0745ee7da1191a366494ca6dc2532642",
            "timing_report_sha256": "f91dd1d8533b6eeb026d17cf1005976622cbfa7c1a067ce6f3228f216762236a",
            "route_report_sha256": "ad4ff27082664a3540b3a284f20b046ccd96fee9ff43636e741504fa97df92af",
            "drc_report_sha256": "c24bec078622d586eeccd899ee453308b53e9a0fb7189e3754ddd6151fd0af9c",
            "copied_older_xsa_sha256": "17abc3ec67509473f9139e746d6c426f76e94f538c0afa7f328b8ee821e34cd0",
        },
    },
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


def close(left: float, right: float, digits: int = 9) -> bool:
    return round(float(left), digits) == round(float(right), digits)


def check_linux_ab(data: dict, errors: list[str]) -> None:
    if data.get("schema") != "npc-riscv-open/linux-coremark-history-v1":
        errors.append("Linux A/B schema mismatch")
        return
    baseline = data.get("baseline", {})
    optimized = data.get("optimized", {})
    derived = data.get("derived", {})
    expected = (
        (baseline, 27929341, 3252477, 8.587098694),
        (optimized, 5613603, 3252481, 1.725944902),
    )
    for record, cycles, instructions, cpi in expected:
        if record.get("cycles") != cycles or record.get("retired_instructions") != instructions:
            errors.append("Linux A/B counter identity drift")
            continue
        if not close(record.get("whole_program_cpi", -1), cycles / instructions):
            errors.append("Linux A/B CPI arithmetic mismatch")
        if not close(record.get("whole_program_cpi", -1), cpi):
            errors.append("Linux A/B CPI identity drift")
    if baseline.get("binary_sha256") is not None or baseline.get("status") != "partial":
        errors.append("Linux baseline missing-binary boundary was weakened")
    if optimized.get("status") != "historical_verified":
        errors.append("Linux optimized historical status drift")
    speedup = baseline.get("whole_program_cpi", 0) / optimized.get("whole_program_cpi", 1)
    if not close(derived.get("value", -1), speedup) or derived.get("status") != "partial":
        errors.append("Linux approximate speedup contract mismatch")
    lineage = data.get("lineage", {})
    if lineage.get("current_source_exact_rerun") != "not_reverified":
        errors.append("Linux current-source rerun boundary was weakened")


def check_linux_boot(data: dict, errors: list[str]) -> None:
    if data.get("schema") != "npc-riscv-open/linux-boot-history-v1":
        errors.append("Linux boot schema mismatch")
    if data.get("source_ref") != "e3a1cc91c4c00040f7180eec5e385326d9964893":
        errors.append("Linux boot source identity drift")
    if data.get("status") != "historical_verified":
        errors.append("Linux historical boot status drift")
    expected_markers = {
        "DTB loaded",
        "Domain0 Next Mode: S-mode",
        "Linux version 6.6.141",
        "Run /init as init process",
        "=== initramfs entered ===",
        "=== shell ready ===",
    }
    if not expected_markers.issubset(set(data.get("observed_markers", []))):
        errors.append("Linux boot marker set is incomplete")
    raw = data.get("raw_log", {})
    if raw.get("published") is not False or raw.get("sha256") != "70f3d55326039c47e6ccb0213db225f5fd04e61fd36e54b2322fdae99f75dd42":
        errors.append("Linux raw-log publication/hash boundary drift")
    if data.get("lineage", {}).get("current_source_deep_boot_status") != "not_reverified":
        errors.append("Linux current-source deep-boot boundary was weakened")


def check_ooo(data: dict, errors: list[str]) -> None:
    if data.get("schema") != "npc-riscv-open/ooo-historical-optimization-v1":
        errors.append("OoO historical schema mismatch")
        return
    if data.get("epoch") != "pre_combinational_loop_remediation":
        errors.append("OoO historical epoch boundary was weakened")
    frontend = data.get("frontend_supply", {})
    expected_frontend = {
        "source_ref": "8a6aaa3f366baac67fb9420bb6dc7819b15a4f28",
        "baseline_cycles": 68362971,
        "optimized_cycles": 58630924,
        "baseline_frontend_empty_percent": 53.76,
        "optimized_frontend_empty_percent": 23.29,
        "frontend_empty_lost_slot_denominator": "total_dispatch_slots",
    }
    for field, value in expected_frontend.items():
        if frontend.get(field) != value:
            errors.append(f"OoO frontend identity drift: {field}")
    branch = data.get("branch_prediction", {})
    if branch.get("redirect_denominator") != "control_completions":
        errors.append("OoO redirect denominator drift")
    stages = branch.get("stages", [])
    expected_stages = (
        ("direct_jal", "62d4085047a31add16f74e5ee1d81725590f4434", 59.38),
        ("btfnt", "a247ac438579adc514caca107f12bc862b436511", 24.84),
        ("tagged_btb_bht", "712b3633f4780bcd5da7c685883df2c30ce00b18", 22.66),
        ("jalr_btb_ras", "87a0bbc45ca2817c8ae9fb3eedbd6e98f7f6cd12", 17.73),
    )
    observed = [(item.get("id"), item.get("source_ref"), item.get("redirect_percent")) for item in stages]
    if observed != list(expected_stages):
        errors.append("OoO staged redirect identity drift")


def check_fpga(data: dict, errors: list[str]) -> None:
    if data.get("schema") != "npc-riscv-open/fpga-history-v1":
        errors.append("FPGA history schema mismatch")
        return
    if data.get("tool") != "Vivado 2022.2" or data.get("part") != "xc7z100ffg900-2":
        errors.append("FPGA tool/part identity drift")
    if data.get("clock", {}).get("frequency_mhz") != 200:
        errors.append("FPGA clock identity drift")
    snapshots = {item.get("id"): item for item in data.get("snapshots", []) if isinstance(item, dict)}
    if set(snapshots) != set(EXPECTED_FPGA):
        errors.append("FPGA snapshot set mismatch")
        return
    for snapshot_id, expected in EXPECTED_FPGA.items():
        item = snapshots[snapshot_id]
        if item.get("date") != expected["date"]:
            errors.append(f"{snapshot_id}: date drift")
        if item.get("source_identity", {}).get("source_manifest_sha256") != expected["source_manifest_sha256"]:
            errors.append(f"{snapshot_id}: source manifest drift")
        maturity = item.get("maturity", {})
        if set(maturity) != FPGA_DIMENSIONS:
            errors.append(f"{snapshot_id}: FPGA maturity dimensions incomplete")
        timing = item.get("timing", {})
        if timing.get("setup_wns_ns") != expected["setup_wns_ns"] or timing.get("hold_whs_ns") != expected["hold_whs_ns"]:
            errors.append(f"{snapshot_id}: timing identity drift")
        route = item.get("route", {})
        if route.get("routing_errors") != 0 or route.get("routed_drc_warnings") != expected["drc_warnings"] or route.get("drc_clean") is not False:
            errors.append(f"{snapshot_id}: route/DRC boundary drift")
        if item.get("artifacts") != expected["artifacts"]:
            errors.append(f"{snapshot_id}: artifact hash identity drift")
    original = snapshots["single_board_20260507"]
    workload = original.get("workload", {})
    if workload.get("ila_valid_commit_samples") != 49 or workload.get("ila_binary_instruction_matches") != 49:
        errors.append("FPGA ILA-to-binary match contract drift")
    if workload.get("standardized_coremark_score_claimed") is not False:
        errors.append("FPGA standardized CoreMark score boundary was weakened")
    if original.get("maturity", {}).get("fpga_board_smoke") != "partial" or original.get("maturity", {}).get("fpga_workload_validation") != "partial":
        errors.append("FPGA board/workload partial boundary was weakened")
    old_xsa = original.get("artifacts", {}).get("vitis_xsa_sha256")
    for snapshot_id in ("single_forward_20260512", "single_predict_20260515"):
        item = snapshots[snapshot_id]
        maturity = item.get("maturity", {})
        if any(maturity.get(key) != "not_claimed" for key in ("fpga_bitstream", "fpga_board_smoke", "fpga_workload_validation")):
            errors.append(f"{snapshot_id}: unsupported downstream FPGA maturity")
        if item.get("artifacts", {}).get("copied_older_xsa_sha256") != old_xsa:
            errors.append(f"{snapshot_id}: copied-old-XSA identity drift")
    if data.get("current_profile_board_status") != "not_claimed":
        errors.append("Current Single source board boundary was weakened")


def check_claim_and_manifest_links(root: Path, records: list[dict], errors: list[str]) -> None:
    claims_data = load_object(root / CLAIMS_PATH)
    manifest_data = load_object(root / MANIFEST_PATH)
    claims = {item.get("id"): item for item in claims_data.get("claims", []) if isinstance(item, dict)}
    evidence = {item.get("id"): item for item in manifest_data.get("evidence", []) if isinstance(item, dict)}
    for claim_id, status in EXPECTED_CLAIM_STATUS.items():
        claim = claims.get(claim_id)
        if not claim:
            errors.append(f"missing historical claim {claim_id}")
            continue
        if claim.get("status") != status or claim.get("public") is not True:
            errors.append(f"historical claim status/public mismatch for {claim_id}")
        links = claim.get("evidence", [])
        if len(links) != 1 or links[0] not in EXPECTED_EVIDENCE:
            errors.append(f"historical claim evidence link mismatch for {claim_id}")
    for evidence_id, path in EXPECTED_EVIDENCE.items():
        item = evidence.get(evidence_id)
        if not item:
            errors.append(f"missing historical evidence manifest entry {evidence_id}")
            continue
        expected_path = "../" + path
        if item.get("path") != expected_path:
            errors.append(f"historical evidence path mismatch for {evidence_id}")
        # Manifest paths are portable repository paths prefixed with "../" to
        # match the existing public evidence convention, not filesystem paths
        # relative to delivery/evidence/manifest.yaml.
        evidence_path = root / expected_path.removeprefix("../")
        if not evidence_path.is_file() or item.get("sha256") != sha256(evidence_path):
            errors.append(f"historical evidence SHA256 drift for {evidence_id}")
        record = next((entry for entry in records if entry.get("claim_ids") == item.get("claims")), None)
        if record is None:
            errors.append(f"historical evidence claim set mismatch for {evidence_id}")
        for claim_id in item.get("claims", []):
            if claims.get(claim_id, {}).get("evidence") != [evidence_id]:
                errors.append(f"claim/evidence reverse link mismatch for {claim_id}")


def check_docs(root: Path, errors: list[str]) -> None:
    pairs = (
        ("README.md", "README.en.md"),
        ("docs/evidence/performance_history.md", "docs/evidence/performance_history.en.md"),
        ("docs/evidence/system_fpga_history.md", "docs/evidence/system_fpga_history.en.md"),
    )
    required_by_prefix = {
        "docs/evidence/performance_history": (
            "8.587098694", "1.725944902", "4.9753", "53.76", "23.29",
            "59.38", "24.84", "22.66", "17.73",
        ),
        "docs/evidence/system_fpga_history": (
            "Linux `6.6.141`", "200 MHz", "0.083", "0.044", "0.010", "0.040", "0.045",
        ),
    }
    for left, right in pairs:
        for path_name in (left, right):
            path = root / path_name
            if not path.is_file():
                errors.append(f"missing historical evidence surface {path_name}")
                continue
            text = path.read_text(encoding="utf-8")
            for prefix, required in required_by_prefix.items():
                if not path_name.startswith(prefix):
                    continue
                for value in required:
                    if value not in text:
                        errors.append(f"{path_name}: missing synchronized value {value}")
    readmes = [(root / name).read_text(encoding="utf-8") for name in ("README.md", "README.en.md")]
    for evidence_id in EXPECTED_EVIDENCE:
        marker = f"evidence:{evidence_id}"
        if any(marker not in text for text in readmes):
            errors.append(f"README bilingual evidence marker missing for {evidence_id}")


def run_checks(root: Path) -> list[str]:
    errors: list[str] = []
    try:
        linux_ab = load_object(root / LINUX_AB_PATH)
        linux_boot = load_object(root / LINUX_BOOT_PATH)
        ooo = load_object(root / OOO_PATH)
        fpga = load_object(root / FPGA_PATH)
    except RuntimeError as error:
        return [str(error)]
    check_linux_ab(linux_ab, errors)
    check_linux_boot(linux_boot, errors)
    check_ooo(ooo, errors)
    check_fpga(fpga, errors)
    check_claim_and_manifest_links(root, [linux_ab, linux_boot, ooo, fpga], errors)
    check_docs(root, errors)
    for record in (linux_ab, linux_boot, ooo, fpga):
        for claim_id in record.get("claim_ids", []):
            if claim_id not in EXPECTED_CLAIM_STATUS:
                errors.append(f"unexpected historical claim id {claim_id}")
    return sorted(set(errors))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    errors = run_checks(args.root.resolve())
    if errors:
        raise SystemExit("HISTORICAL_EVIDENCE_CHECK_FAILED\n  - " + "\n  - ".join(errors))
    print("HISTORICAL_EVIDENCE_CHECK_PASS linux=2 ooo=1 fpga_snapshots=3 claims={}".format(len(EXPECTED_CLAIM_STATUS)))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
