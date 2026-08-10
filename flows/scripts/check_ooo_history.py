#!/usr/bin/env python3
"""Validate bounded OoO performance, loop remediation and source history."""

from __future__ import print_function

import argparse
import hashlib
import json
import math
from pathlib import Path, PurePosixPath
import re
import shutil
import subprocess
import tempfile
from typing import Dict, Iterable, List, Mapping, MutableSequence, Optional, Set


COREMARK_PATH = "evidence/performance/ooo_coremark_history.json"
LOOP_PATH = "evidence/verification/ooo_loop_remediation.json"
LINEAGE_PATH = "provenance/upstream/rv32im_ooo_4k/history/source_lineage.json"
CLAIMS_PATH = "delivery/claims/claims.yaml"
NONCLAIMS_PATH = "delivery/claims/nonclaims.yaml"
EVIDENCE_MANIFEST_PATH = "delivery/evidence/manifest.yaml"
PROFILE_ROOT = PurePosixPath("rtl/profiles/rv32im_ooo_4k")

S9A_SOURCE = "7154e5a3d61fab18718a33f3fe2588891c1b291b"
P89_SOURCE = "0e1730b71b7c4ad699e919fc9404189a5e8729d6"
D12_SOURCE = "a8f689cc00213859fb6893b31b65ef5cb3cbd7eb"
CANONICAL_SOURCE = "99fcc2be539eabb078c0d73b26a7ef2c00071391"
P89_BINARY_SHA256 = "dc9a01a68109b14edf4f975ab2bb960d132b8b6d432e42ce43031fea72b17317"
P89_CONFIG_SHA256 = "582d996093bbc50b2fb8d2c6332b0246336fc66d6804c38fa151729764764ae0"
D12_EFFECTIVE_PARAMETERS_SHA256 = "a02ab21846471df9b10fe230d2a79c75ffd8698c15bd7fd8eab6913040d2e630"
D12_YOSYS_SOURCE_SET_SHA256 = "e5782d80dde8aceef10516f5cdaeab3fda8f21b5e4df051de39939da5002da12"
D12_SPYGLASS_SOURCE_SET_SHA256 = "8fa1ba69869e2a19b3bb5fb9ebc6393ce87f416af8f830eb4e4d578c5523ec62"
D12_PARAMETER_LOCK_SHA256 = "65c6c2b6d32a1ea2434ab0cba04e29d99d8270477139c16f8d1b1cd473cd0d2a"
D12_FILELIST_SHA256 = "c571279f3af6a4670a7a55653dfde7e6684d463f08fda652fa99cac9cb21c220"
D12_MACRO_VERILOG_SHA256 = "66f8308687803b3806ec9ba092658131b6021abacc938b63894b1b74cb1bf045"
CANONICAL_MANIFEST_SHA256 = "ec9f3fd31ecafbfd50941b74e8dec69c6b69cc9c4d71f77c956534f734c739d3"
P89_PATCH_SHA256 = "66e2c4970ea2ab2272a70a9b9c0d4bf4d894487e5fd7ddee5b0777f51f6231de"
P89_MANIFEST_SHA256 = "14d271ea3c06a1c1ea68607cf9f2eeb45f9140066e80d40a38b14bcb5b101e84"
D12_PATCH_SHA256 = "9433208a99d0d7f4aac920d3e7d6b8a5deeea91c658899293cfd34a77e496922"
D12_MANIFEST_SHA256 = "1bfc868e01f2f4f304c1794de86c9a72f102b78d05d2f2ccf284b62aa45dd21f"

COREMARK_CLAIMS = [
    "ooo_historical_s9a_coremark_whole_cpi",
    "ooo_historical_p89_coremark_whole_cpi",
    "ooo_historical_coremark_approx_speedup",
]
LOOP_CLAIMS = [
    "ooo_historical_comb_loop_zero",
    "ooo_historical_unoptflat_zero",
    "ooo_historical_pre_techmap_scc_zero",
    "ooo_historical_post_techmap_scc_zero",
    "ooo_historical_precise_retirement_preserved",
]
EVIDENCE_IDS = {
    "ooo_coremark_history_public": COREMARK_PATH,
    "ooo_loop_remediation_public": LOOP_PATH,
}
EXPECTED_CLAIMS = {
    "ooo_historical_s9a_coremark_whole_cpi": {
        "evidence": "ooo_coremark_history_public",
        "source_ref": S9A_SOURCE,
        "status": "partial",
        "value": 6.184799387499,
    },
    "ooo_historical_p89_coremark_whole_cpi": {
        "evidence": "ooo_coremark_history_public",
        "source_ref": P89_SOURCE,
        "status": "verified",
        "value": 1.097794842231,
    },
    "ooo_historical_coremark_approx_speedup": {
        "evidence": "ooo_coremark_history_public",
        "source_ref": "multiple_historical_refs",
        "status": "partial",
        "value": 5.633838992108,
    },
    "ooo_historical_comb_loop_zero": {
        "evidence": "ooo_loop_remediation_public",
        "source_ref": D12_SOURCE,
        "status": "verified",
        "value": 0,
    },
    "ooo_historical_unoptflat_zero": {
        "evidence": "ooo_loop_remediation_public",
        "source_ref": D12_SOURCE,
        "status": "verified",
        "value": 0,
    },
    "ooo_historical_pre_techmap_scc_zero": {
        "evidence": "ooo_loop_remediation_public",
        "source_ref": D12_SOURCE,
        "status": "verified",
        "value": 0,
    },
    "ooo_historical_post_techmap_scc_zero": {
        "evidence": "ooo_loop_remediation_public",
        "source_ref": D12_SOURCE,
        "status": "verified",
        "value": 0,
    },
    "ooo_historical_precise_retirement_preserved": {
        "evidence": "ooo_loop_remediation_public",
        "source_ref": D12_SOURCE,
        "status": "verified",
        "value": True,
    },
}
EXPECTED_NONCLAIMS = {
    "ooo_historical_coremark_strict_ab_not_claimed": {
        "evidence_id": "ooo_coremark_history_public",
        "evidence_status": "historical_partial_comparison",
        "source_commit": "multiple_historical_refs",
    },
    "ooo_loop_remediation_performance_not_inherited": {
        "evidence_id": "ooo_loop_remediation_public",
        "evidence_status": "historical_structural_only",
        "source_commit": D12_SOURCE,
    },
    "ooo_loop_remediation_current_backend_not_claimed": {
        "evidence_id": "ooo_loop_remediation_public",
        "evidence_status": "historical_structural_only",
        "source_commit": D12_SOURCE,
    },
}

EXPECTED_COUNTERS = {
    "baseline": (48395814, 7824961, 6.184799387498544),
    "optimized": (8590215, 7824973, 1.0977948422314046),
}
EXPECTED_SPEEDUP = EXPECTED_COUNTERS["baseline"][2] / EXPECTED_COUNTERS["optimized"][2]
EXPECTED_RETIRED_DELTA = 12

SHA256_RE = re.compile(r"^[0-9a-f]{64}$")
DIFF_HEADER_RE = re.compile(r"^diff --git (\S+) (\S+)$")
FILE_HEADER_RE = re.compile(r"^(?:---|\+\+\+) (\S+)(?:\t.*)?$")
FORBIDDEN_LOOP_METRIC_KEYS = {
    "cycles", "cpi", "whole_program_cpi", "timed_cpi", "speedup",
    "frequency", "frequency_mhz", "clock_period", "clock_period_ns",
    "wns", "wns_ns", "tns", "tns_ns", "area", "cell_area",
    "total_cell_area", "power",
}
EXPECTED_LOOP_NONCLAIMS = [
    "No performance metric is inherited from the pre-remediation S9S or P89 checkpoints.",
    "No DC, mapped netlist, timing, frequency, area, P&R, power or signoff result is claimed.",
    "The bounded structural gates do not claim zero messages across every lint policy.",
    "The D12 snapshot is not claimed as the current canonical public RTL.",
]
EXPECTED_COREMARK_SOURCES = [
    {
        "role": "baseline_bounded_analysis",
        "git_ref": "d7376dde657a33213f966e0d69f8032b7ffcb3f9",
        "logical_path": "npc/docs/perf/s9a_pipeline_performance_baseline.md",
        "sha256": "70bbe524b936868a08fc2dc2bf8d67981e84ba2db63b0ee9fbd14fd696b4cfc9",
    },
    {
        "role": "optimized_decision",
        "git_ref": "3a947f180f3bf01dcac8cd88044cc2ae64cbd630",
        "logical_path": "npc/docs/perf/s9r_p89_load_transaction_depth3_status.md",
        "sha256": "6315bce70ce55bd0325a7337b49ab8a867bfc13ec2db173690e51d3db5260db5",
    },
    {
        "role": "optimized_run_manifest",
        "git_ref": "3a947f180f3bf01dcac8cd88044cc2ae64cbd630",
        "logical_path": "npc/docs/perf/s9r_p89_load_transaction_depth3_seven_on_manifest.txt",
        "sha256": "9f8c6daa23934bf9edd9b41c39d2bb2284e1167040117a4db2b86fed89ff7e9e",
    },
    {
        "role": "optimized_bounded_summary",
        "git_ref": "3a947f180f3bf01dcac8cd88044cc2ae64cbd630",
        "logical_path": "npc/docs/perf/s9r_p89_load_transaction_depth3_seven_on_summary.csv",
        "sha256": "dd98af1f37189d8e61c892a7d17eaa91ce81aaa21488135938635989550db830",
    },
]
EXPECTED_LOOP_SOURCES = [
    {
        "role": "bounded_d12_result",
        "git_ref": "c47c7dc2e9333de9fc798e56b7ed65d70c88dbd6",
        "logical_path": "npc/docs/synth/d12_ooo_causal_ownership_backbone.json",
        "sha256": "757b70f98d0b36005fff88a4cfc714f98d5817341ce46e45968e2cb656a368e9",
    }
]


def load_object(path: Path) -> dict:
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError) as error:
        raise RuntimeError("invalid JSON record {}: {}".format(path, error))
    if not isinstance(value, dict):
        raise RuntimeError("{}: top level must be an object".format(path))
    return value


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def close(left: object, right: object, tolerance: float = 1e-9) -> bool:
    try:
        return math.isclose(float(left), float(right), rel_tol=0.0, abs_tol=tolerance)
    except (TypeError, ValueError):
        return False


def require_sha256(value: object, label: str, errors: MutableSequence[str]) -> None:
    if not isinstance(value, str) or SHA256_RE.fullmatch(value) is None:
        errors.append("{} must be a lowercase SHA256".format(label))


def require_exact(record: Mapping[str, object], expected: Mapping[str, object],
                  label: str, errors: MutableSequence[str]) -> None:
    for field, value in expected.items():
        if record.get(field) != value:
            errors.append("{} identity drift: {}".format(label, field))


def require_keys(record: Mapping[str, object], expected: Iterable[str],
                 label: str, errors: MutableSequence[str]) -> None:
    expected_set = set(expected)
    if set(record) != expected_set:
        errors.append("{} field set drift: missing={} extra={}".format(
            label, sorted(expected_set.difference(record)),
            sorted(set(record).difference(expected_set))))


def check_coremark(data: dict, errors: MutableSequence[str]) -> None:
    if data.get("schema") != "npc-riscv-open/ooo-coremark-history-v1":
        errors.append("OoO CoreMark history schema mismatch")
        return
    require_keys(data, {
        "schema", "generated_at", "profile", "epoch", "benchmark",
        "comparison_status", "comparability_domain", "baseline", "optimized",
        "derived", "lineage", "evidence_sources", "claim_ids", "caveat",
    }, "OoO CoreMark", errors)
    require_exact(data, {
        "profile": "rv32im_ooo_4k",
        "epoch": "pre_combinational_loop_remediation",
        "benchmark": "AM CoreMark, whole-program reset-to-ebreak window",
        "comparison_status": "partial",
    }, "OoO CoreMark", errors)
    if data.get("claim_ids") != COREMARK_CLAIMS:
        errors.append("OoO CoreMark claim set/order drift")

    domain = data.get("comparability_domain", {})
    if not isinstance(domain, dict):
        errors.append("OoO CoreMark comparability domain is missing")
        domain = {}
    require_keys(domain, {
        "runner", "isa", "benchmark_binary_isa", "benchmark_binary_abi",
        "hardware_m_extension", "default_profile", "seed", "difftest",
        "measurement_window", "metric", "workload_identity", "strict_fixed_binary_ab",
    }, "OoO CoreMark comparability domain", errors)
    profile = domain.get("default_profile", {})
    if not isinstance(profile, dict):
        errors.append("OoO CoreMark default-profile identity is missing")
        profile = {}
    require_exact(profile, {
        "ifetch_latency": 2,
        "lsu_latency": 3,
        "memory_latency": 2,
    }, "OoO CoreMark default profile", errors)
    require_exact(domain, {
        "runner": "pipeline backend under riscv32e-npc runner naming",
        "isa": "RV32IM",
        "benchmark_binary_isa": "rv32e_zicsr",
        "benchmark_binary_abi": "ilp32e",
        "hardware_m_extension": True,
        "seed": 1,
        "difftest": True,
        "measurement_window": "whole_program_reset_to_ebreak",
        "metric": "cycles / retired_instructions",
        "workload_identity": "same_benchmark_family",
        "strict_fixed_binary_ab": False,
    }, "OoO CoreMark comparability domain", errors)

    expected_sources = {"baseline": S9A_SOURCE, "optimized": P89_SOURCE}
    expected_status = {"baseline": "partial", "optimized": "historical_verified"}
    expected_ids = {
        "baseline": ("s9a_pipeline_performance_baseline", "d7376dde657a33213f966e0d69f8032b7ffcb3f9"),
        "optimized": ("s9r_p89_load_transaction_depth3", "3a947f180f3bf01dcac8cd88044cc2ae64cbd630"),
    }
    for role in ("baseline", "optimized"):
        record = data.get(role, {})
        if not isinstance(record, dict):
            errors.append("OoO CoreMark {} record is missing".format(role))
            continue
        expected_fields = {
            "id", "source_ref", "evidence_ref", "cycles", "retired_instructions",
            "whole_program_cpi", "binary_sha256", "config_sha256", "status",
        }
        if role == "baseline":
            expected_fields.add("status_reason")
        else:
            expected_fields.update({"feature", "production_default_at_checkpoint"})
        require_keys(record, expected_fields, "OoO CoreMark {}".format(role), errors)
        cycles, retired, expected_cpi = EXPECTED_COUNTERS[role]
        require_exact(record, {
            "id": expected_ids[role][0],
            "source_ref": expected_sources[role],
            "evidence_ref": expected_ids[role][1],
            "cycles": cycles,
            "retired_instructions": retired,
            "status": expected_status[role],
        }, "OoO CoreMark {}".format(role), errors)
        if not close(record.get("whole_program_cpi"), cycles / retired):
            errors.append("OoO CoreMark {} CPI arithmetic mismatch".format(role))
        if not close(record.get("whole_program_cpi"), expected_cpi):
            errors.append("OoO CoreMark {} CPI identity drift".format(role))
    baseline = data.get("baseline", {})
    optimized = data.get("optimized", {})
    if isinstance(baseline, dict):
        if baseline.get("binary_sha256") is not None or baseline.get("config_sha256") is not None:
            errors.append("OoO CoreMark missing-baseline-artifact boundary was weakened")
        if baseline.get("status") != "partial":
            errors.append("OoO CoreMark baseline must remain partial")
    if isinstance(optimized, dict):
        require_exact(optimized, {
            "binary_sha256": P89_BINARY_SHA256,
            "config_sha256": P89_CONFIG_SHA256,
            "feature": "load_transaction_depth3 explicitly enabled within the retained performance stack",
            "production_default_at_checkpoint": False,
        }, "OoO P89 artifact", errors)

    derived = data.get("derived", {})
    if not isinstance(derived, dict):
        errors.append("OoO CoreMark derived comparison is missing")
        derived = {}
    require_keys(derived, {
        "metric", "formula", "value", "display_value", "retired_instruction_delta",
        "status", "status_reason",
    }, "OoO CoreMark derived comparison", errors)
    require_exact(derived, {
        "metric": "same_benchmark_family_speedup",
        "formula": "baseline.whole_program_cpi / optimized.whole_program_cpi",
        "status": "partial",
        "retired_instruction_delta": EXPECTED_RETIRED_DELTA,
    }, "OoO CoreMark derived comparison", errors)
    if not close(derived.get("value"), EXPECTED_SPEEDUP):
        errors.append("OoO CoreMark approximate speedup arithmetic mismatch")

    lineage = data.get("lineage", {})
    if not isinstance(lineage, dict):
        errors.append("OoO CoreMark lineage is missing")
        lineage = {}
    require_keys(lineage, {
        "canonical_public_source_ref", "canonical_workbench_source_ref",
        "relationship", "reconstruction", "inheritance",
    }, "OoO CoreMark lineage", errors)
    require_exact(lineage, {
        "canonical_public_source_ref": CANONICAL_SOURCE,
        "canonical_workbench_source_ref": "8c004f4ac7d8c99fa71b8adde35a319f7472c93a",
    }, "OoO CoreMark lineage", errors)
    core_reconstruction = lineage.get("reconstruction", {})
    if not isinstance(core_reconstruction, dict):
        errors.append("OoO CoreMark reconstruction binding is missing")
        core_reconstruction = {}
    require_keys(core_reconstruction, {"patch", "source_set_manifest", "file_count"},
                 "OoO CoreMark reconstruction", errors)
    inheritance = lineage.get("inheritance", {})
    if inheritance != {"current": False, "loop_free": False, "dc": False, "ppa": False}:
        errors.append("OoO CoreMark current/loop-free/DC/PPA non-inheritance boundary drift")
    if data.get("evidence_sources") != EXPECTED_COREMARK_SOURCES:
        errors.append("OoO CoreMark evidence-source identity drift")


def nested_keys(value: object) -> Iterable[str]:
    if isinstance(value, dict):
        for key, child in value.items():
            yield str(key)
            for nested in nested_keys(child):
                yield nested
    elif isinstance(value, list):
        for child in value:
            for nested in nested_keys(child):
                yield nested


def check_loop_remediation(data: dict, errors: MutableSequence[str]) -> None:
    if data.get("schema") != "npc-riscv-open/ooo-loop-remediation-v1":
        errors.append("OoO loop-remediation schema mismatch")
        return
    require_keys(data, {
        "schema", "generated_at", "profile", "epoch", "status", "claim_scope",
        "source", "architecture", "structural", "functional", "evidence_sources",
        "inheritance", "claim_ids", "nonclaims",
    }, "OoO loop remediation", errors)
    require_exact(data, {
        "profile": "rv32im_ooo_4k",
        "epoch": "d12_registered_causal_ownership",
        "status": "historical_verified",
        "claim_scope": "structural_and_functional_only",
    }, "OoO loop remediation", errors)
    if data.get("claim_ids") != LOOP_CLAIMS:
        errors.append("OoO loop-remediation claim set/order drift")

    source = data.get("source", {})
    if not isinstance(source, dict):
        errors.append("OoO loop-remediation source identity is missing")
        source = {}
    require_keys(source, {
        "base_commit", "implementation_commit", "parameter_lock_role",
        "parameter_lock_sha256", "effective_parameters_sha256", "filelist_sha256",
        "macro_verilog_sha256", "relationship_to_canonical", "reconstruction",
    }, "OoO loop-remediation source", errors)
    require_exact(source, {
        "base_commit": "a698a882",
        "implementation_commit": D12_SOURCE,
        "parameter_lock_role": "rv32im_ooo_4k_d12_level2",
        "parameter_lock_sha256": D12_PARAMETER_LOCK_SHA256,
        "effective_parameters_sha256": D12_EFFECTIVE_PARAMETERS_SHA256,
        "filelist_sha256": D12_FILELIST_SHA256,
        "macro_verilog_sha256": D12_MACRO_VERILOG_SHA256,
    }, "OoO loop-remediation source", errors)
    for field in (
        "parameter_lock_sha256", "effective_parameters_sha256",
        "filelist_sha256", "macro_verilog_sha256",
    ):
        require_sha256(source.get(field), "OoO D12 {}".format(field), errors)
    loop_reconstruction = source.get("reconstruction", {})
    if not isinstance(loop_reconstruction, dict):
        errors.append("OoO D12 reconstruction binding is missing")
        loop_reconstruction = {}
    require_keys(loop_reconstruction, {"patch", "source_set_manifest", "file_count"},
                 "OoO D12 reconstruction", errors)
    architecture = data.get("architecture", {})
    if not isinstance(architecture, dict):
        errors.append("OoO loop-remediation architecture record is missing")
        architecture = {}
    require_keys(architecture, {
        "registered_boundaries", "precise_retirement", "forbidden_live_feedback_restored",
    }, "OoO loop-remediation architecture", errors)
    boundaries = architecture.get("registered_boundaries")
    expected_boundaries = [
        "typed ROB outcome and retire ownership",
        "depth-3 core-memory request and response ownership",
        "typed completion and registered service ownership",
        "persistent recovery token and RAS preview ownership",
    ]
    if boundaries != expected_boundaries:
        errors.append("OoO registered ownership-boundary set drift")
    if architecture.get("precise_retirement") is not True:
        errors.append("OoO precise-retirement preservation is missing")
    if architecture.get("forbidden_live_feedback_restored") is not False:
        errors.append("OoO forbidden live feedback boundary was weakened")

    structural = data.get("structural", {})
    if not isinstance(structural, dict) or structural.get("status") != "pass":
        errors.append("OoO structural closure status drift")
        structural = structural if isinstance(structural, dict) else {}
    require_keys(structural, {"status", "spyglass", "verilator", "yosys"},
                 "OoO structural gate", errors)
    spyglass = structural.get("spyglass", {})
    verilator = structural.get("verilator", {})
    yosys = structural.get("yosys", {})
    if not isinstance(spyglass, dict):
        spyglass = {}
    if not isinstance(verilator, dict):
        verilator = {}
    if not isinstance(yosys, dict):
        yosys = {}
    require_keys(spyglass, {
        "source_commit", "source_set_sha256", "design_read_errors", "comb_loop",
        "waived_errors", "forbidden_project_controls",
    }, "OoO SpyGlass loop gate", errors)
    require_keys(verilator, {"unoptflat"}, "OoO Verilator loop gate", errors)
    require_keys(yosys, {
        "source_commit", "source_set_sha256", "pre_techmap_scc", "post_techmap_scc",
        "pre_techmap_check_clean", "post_techmap_check_clean",
    }, "OoO Yosys SCC gate", errors)
    require_exact(spyglass, {
        "source_commit": D12_SOURCE,
        "source_set_sha256": D12_SPYGLASS_SOURCE_SET_SHA256,
        "design_read_errors": 0,
        "comb_loop": 0,
        "waived_errors": 0,
        "forbidden_project_controls": [],
    }, "OoO SpyGlass loop gate", errors)
    require_exact(verilator, {"unoptflat": 0}, "OoO Verilator loop gate", errors)
    require_exact(yosys, {
        "source_commit": D12_SOURCE,
        "source_set_sha256": D12_YOSYS_SOURCE_SET_SHA256,
        "pre_techmap_scc": 0,
        "post_techmap_scc": 0,
        "pre_techmap_check_clean": True,
        "post_techmap_check_clean": True,
    }, "OoO Yosys SCC gate", errors)

    functional = data.get("functional", {})
    if not isinstance(functional, dict):
        errors.append("OoO loop-remediation functional record is missing")
        functional = {}
    require_keys(functional, {
        "status", "identity_points_passed", "identity_points_total",
        "protocol_lifecycle_conservation_errors", "precise_retirement_preserved",
    }, "OoO loop-remediation functional gate", errors)
    require_exact(functional, {
        "status": "pass",
        "identity_points_passed": 14,
        "identity_points_total": 14,
        "protocol_lifecycle_conservation_errors": 0,
        "precise_retirement_preserved": True,
    }, "OoO loop-remediation functional gate", errors)

    if data.get("inheritance") != {"performance": False, "dc": False, "ppa": False}:
        errors.append("OoO loop-remediation performance/DC/PPA non-inheritance boundary drift")
    forbidden = sorted(FORBIDDEN_LOOP_METRIC_KEYS.intersection(nested_keys(data)))
    if forbidden:
        errors.append("OoO loop-remediation record contains forbidden metric keys: {}".format(
            ", ".join(forbidden)))
    if data.get("nonclaims") != EXPECTED_LOOP_NONCLAIMS:
        errors.append("OoO loop-remediation nonclaim boundary drift")
    if data.get("evidence_sources") != EXPECTED_LOOP_SOURCES:
        errors.append("OoO loop-remediation evidence-source identity drift")


def safe_repo_path(value: object, label: str, errors: MutableSequence[str]) -> Optional[PurePosixPath]:
    if not isinstance(value, str) or not value.strip() or "\\" in value:
        errors.append("{} is not a portable repository path".format(label))
        return None
    path = PurePosixPath(value)
    if not path.parts or path.is_absolute() or ".." in path.parts or path.parts[0] in ("", "."):
        errors.append("{} escapes the repository".format(label))
        return None
    return path


def validate_patch_paths(patch: Path, errors: MutableSequence[str]) -> Set[str]:
    try:
        lines = patch.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        errors.append("cannot read source reconstruction patch {}: {}".format(patch, error))
        return set()
    touched = set()  # type: Set[str]
    diff_count = 0
    for line in lines:
        match = DIFF_HEADER_RE.match(line)
        if match:
            diff_count += 1
            candidates = match.groups()
        else:
            header = FILE_HEADER_RE.match(line)
            if not header:
                continue
            candidates = (header.group(1),)
        for candidate in candidates:
            if candidate == "/dev/null":
                continue
            if candidate.startswith("a/") or candidate.startswith("b/"):
                candidate = candidate[2:]
            parsed = safe_repo_path(candidate, "patch path", errors)
            if parsed is None:
                continue
            if tuple(parsed.parts[:len(PROFILE_ROOT.parts)]) != PROFILE_ROOT.parts:
                errors.append("patch path is outside the OoO profile: {}".format(candidate))
                continue
            touched.add(parsed.as_posix())
    if diff_count == 0 or not touched:
        errors.append("source reconstruction patch contains no bounded file changes")
    return touched


def parse_source_manifest(path: Path, errors: MutableSequence[str]) -> Dict[str, str]:
    try:
        lines = path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        errors.append("cannot read target source-set manifest {}: {}".format(path, error))
        return {}
    entries = {}  # type: Dict[str, str]
    for number, line in enumerate(lines, 1):
        match = re.fullmatch(r"([0-9a-f]{64})  (.+)", line)
        if not match:
            errors.append("{}:{} invalid source-set manifest entry".format(path, number))
            continue
        digest, relative = match.groups()
        parsed = safe_repo_path(relative, "source-set manifest path", errors)
        if parsed is None:
            continue
        if tuple(parsed.parts[:len(PROFILE_ROOT.parts)]) != PROFILE_ROOT.parts:
            errors.append("source-set manifest path is outside the OoO profile: {}".format(relative))
            continue
        if relative in entries:
            errors.append("duplicate source-set manifest role: {}".format(relative))
            continue
        entries[relative] = digest
    if not entries:
        errors.append("source-set manifest is empty")
    return entries


def snapshot_records(data: dict, errors: MutableSequence[str]) -> Dict[str, dict]:
    values = data.get("snapshots")
    if not isinstance(values, list):
        errors.append("OoO source-lineage snapshots are missing")
        return {}
    records = {}  # type: Dict[str, dict]
    for value in values:
        if not isinstance(value, dict) or not isinstance(value.get("id"), str):
            errors.append("OoO source-lineage snapshot identity is malformed")
            continue
        snapshot_id = value["id"]
        if snapshot_id in records:
            errors.append("duplicate OoO source-lineage snapshot {}".format(snapshot_id))
            continue
        records[snapshot_id] = value
    return records


def resolve_bound_file(root: Path, record: Mapping[str, object], field: str,
                       label: str, errors: MutableSequence[str]) -> Optional[Path]:
    binding = record.get(field)
    if not isinstance(binding, dict):
        errors.append("{} {} binding is missing".format(label, field))
        return None
    relative = safe_repo_path(binding.get("path"), "{} {} path".format(label, field), errors)
    require_sha256(binding.get("sha256"), "{} {}".format(label, field), errors)
    if relative is None:
        return None
    path = root / relative.as_posix()
    if not path.is_file():
        errors.append("{} {} is missing: {}".format(label, field, relative))
        return None
    if sha256(path) != binding.get("sha256"):
        errors.append("{} {} SHA256 drift".format(label, field))
    return path


def reconstruct_snapshot(root: Path, snapshot: Mapping[str, object],
                         label: str, errors: MutableSequence[str]) -> None:
    patch = resolve_bound_file(root, snapshot, "patch", label, errors)
    manifest_path = resolve_bound_file(root, snapshot, "source_set_manifest", label, errors)
    if patch is None or manifest_path is None:
        return
    touched = validate_patch_paths(patch, errors)
    expected = parse_source_manifest(manifest_path, errors)
    if not touched or not expected:
        return
    declared_count = snapshot.get("file_count")
    if declared_count != len(expected):
        errors.append("{} file-count identity drift".format(label))
    declared_roles = snapshot.get("roles")
    if not isinstance(declared_roles, list) or declared_roles != sorted(expected):
        errors.append("{} complete source-role set drift".format(label))
    declared_changed = snapshot.get("changed")
    declared_added = snapshot.get("added")
    declared_removed = snapshot.get("removed")
    if not all(isinstance(value, list) for value in (declared_changed, declared_added, declared_removed)):
        errors.append("{} patch change-set identity is incomplete".format(label))

    source_root = root / PROFILE_ROOT.as_posix()
    if not source_root.is_dir():
        errors.append("canonical OoO source root is missing")
        return
    canonical_roles = {
        path.relative_to(root).as_posix()
        for path in source_root.rglob("*")
        if path.is_file() and not path.is_symlink()
    }
    target_roles = set(expected)
    classified = {
        "changed": sorted(touched.intersection(canonical_roles).intersection(target_roles)),
        "added": sorted(touched.intersection(target_roles.difference(canonical_roles))),
        "removed": sorted(touched.intersection(canonical_roles.difference(target_roles))),
    }
    unclassified = touched.difference(
        set(classified["changed"] + classified["added"] + classified["removed"]))
    if unclassified:
        errors.append("{} patch has unclassified roles: {}".format(label, sorted(unclassified)))
    if all(isinstance(value, list) for value in (declared_changed, declared_added, declared_removed)):
        declared = {
            "changed": declared_changed,
            "added": declared_added,
            "removed": declared_removed,
        }
        for kind in ("changed", "added", "removed"):
            if declared[kind] != classified[kind]:
                errors.append("{} patch {}-role set drift".format(label, kind))
        declared_touched = set(declared_changed + declared_added + declared_removed)
        if declared_touched != touched:
            errors.append("{} patch touched-role set drift".format(label))
    with tempfile.TemporaryDirectory(prefix="npc-ooo-history-") as temporary:
        temporary_root = Path(temporary)
        target_root = temporary_root / PROFILE_ROOT.as_posix()
        target_root.parent.mkdir(parents=True, exist_ok=True)
        shutil.copytree(str(source_root), str(target_root), symlinks=True)
        command = ["git", "apply", "--check", "--whitespace=nowarn", str(patch.resolve())]
        checked = subprocess.run(command, cwd=str(temporary_root), stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, universal_newlines=True)
        if checked.returncode != 0:
            errors.append("{} patch does not apply to canonical source: {}".format(
                label, checked.stderr.strip()))
            return
        command.remove("--check")
        applied = subprocess.run(command, cwd=str(temporary_root), stdout=subprocess.PIPE,
                                 stderr=subprocess.PIPE, universal_newlines=True)
        if applied.returncode != 0:
            errors.append("{} patch reconstruction failed: {}".format(
                label, applied.stderr.strip()))
            return
        actual = {}  # type: Dict[str, str]
        for path in target_root.rglob("*"):
            if path.is_symlink():
                errors.append("{} reconstruction contains a symlink: {}".format(
                    label, path.relative_to(temporary_root).as_posix()))
                continue
            if path.is_file():
                relative = path.relative_to(temporary_root).as_posix()
                actual[relative] = sha256(path)
        if set(actual) != set(expected):
            missing = sorted(set(expected) - set(actual))
            extra = sorted(set(actual) - set(expected))
            errors.append("{} reconstructed source-role set mismatch: missing={} extra={}".format(
                label, missing, extra))
        for relative in sorted(set(actual).intersection(expected)):
            if actual[relative] != expected[relative]:
                errors.append("{} reconstructed source SHA256 drift: {}".format(label, relative))


def check_source_lineage(root: Path, data: dict, errors: MutableSequence[str]) -> None:
    if data.get("schema") != "npc-riscv-open/ooo-source-lineage-v1":
        errors.append("OoO source-lineage schema mismatch")
        return
    require_keys(data, {
        "schema", "generated_at", "profile", "canonical", "snapshots",
        "evidence_bindings", "caveat",
    }, "OoO source lineage", errors)
    require_exact(data, {"profile": "rv32im_ooo_4k"}, "OoO source lineage", errors)
    canonical = data.get("canonical")
    if not isinstance(canonical, dict):
        errors.append("OoO canonical source identity is missing")
        canonical = {}
    require_keys(canonical, {
        "source_ref", "workbench_source_ref", "source_root",
        "source_set_manifest", "file_count",
    }, "OoO canonical source", errors)
    require_exact(canonical, {"source_ref": CANONICAL_SOURCE}, "OoO canonical source", errors)
    require_exact(canonical, {
        "workbench_source_ref": "8c004f4ac7d8c99fa71b8adde35a319f7472c93a",
        "source_root": PROFILE_ROOT.as_posix(),
        "source_set_manifest": {
            "path": "provenance/source_sets/rv32im_ooo_4k.sha256",
            "sha256": CANONICAL_MANIFEST_SHA256,
        },
        "file_count": 63,
    }, "OoO canonical source", errors)
    canonical_manifest = resolve_bound_file(
        root, canonical, "source_set_manifest", "OoO canonical source", errors)
    if canonical_manifest is not None:
        canonical_entries = parse_source_manifest(canonical_manifest, errors)
        actual_entries = {}  # type: Dict[str, str]
        source_root = root / PROFILE_ROOT.as_posix()
        for path in source_root.rglob("*"):
            if path.is_file() and not path.is_symlink():
                actual_entries[path.relative_to(root).as_posix()] = sha256(path)
        if actual_entries != canonical_entries:
            errors.append("OoO canonical source-set manifest does not match the public RTL tree")

    records = snapshot_records(data, errors)
    if set(records) != {"p89", "d12"}:
        errors.append("OoO source-lineage snapshot set drift")
    expected_sources = {"p89": P89_SOURCE, "d12": D12_SOURCE}
    expected_artifacts = {
        "p89": {
            "patch": {
                "path": "provenance/upstream/rv32im_ooo_4k/history/p89_from_public_s9s.patch",
                "sha256": P89_PATCH_SHA256,
            },
            "source_set_manifest": {
                "path": "provenance/upstream/rv32im_ooo_4k/history/p89_source_set.sha256",
                "sha256": P89_MANIFEST_SHA256,
            },
            "file_count": 63,
        },
        "d12": {
            "patch": {
                "path": "provenance/upstream/rv32im_ooo_4k/history/d12_from_public_s9s.patch",
                "sha256": D12_PATCH_SHA256,
            },
            "source_set_manifest": {
                "path": "provenance/upstream/rv32im_ooo_4k/history/d12_source_set.sha256",
                "sha256": D12_MANIFEST_SHA256,
            },
            "file_count": 71,
        },
    }
    for snapshot_id in ("p89", "d12"):
        record = records.get(snapshot_id)
        if record is None:
            continue
        require_keys(record, {
            "id", "source_ref", "base_source_ref", "relationship", "patch",
            "source_set_manifest", "file_count", "roles", "changed", "added", "removed",
        }, "OoO {} source snapshot".format(snapshot_id.upper()), errors)
        require_exact(record, {
            "source_ref": expected_sources[snapshot_id],
            "base_source_ref": CANONICAL_SOURCE,
            "patch": expected_artifacts[snapshot_id]["patch"],
            "source_set_manifest": expected_artifacts[snapshot_id]["source_set_manifest"],
            "file_count": expected_artifacts[snapshot_id]["file_count"],
        }, "OoO {} source snapshot".format(snapshot_id.upper()), errors)
        reconstruct_snapshot(root, record, "OoO {}".format(snapshot_id.upper()), errors)

    bindings = data.get("evidence_bindings")
    expected_bindings = {
        "p89": COREMARK_PATH,
        "d12": LOOP_PATH,
    }
    if bindings != expected_bindings:
        errors.append("OoO source-lineage evidence bindings drift")


def check_evidence_reconstruction_bindings(coremark: dict, loop: dict, lineage: dict,
                                           errors: MutableSequence[str]) -> None:
    records = snapshot_records(lineage, errors)
    p89 = records.get("p89", {})
    d12 = records.get("d12", {})
    core_reconstruction = coremark.get("lineage", {}).get("reconstruction", {})
    loop_reconstruction = loop.get("source", {}).get("reconstruction", {})
    for label, evidence_binding, lineage_record in (
        ("P89", core_reconstruction, p89),
        ("D12", loop_reconstruction, d12),
    ):
        if not isinstance(evidence_binding, dict):
            errors.append("{} evidence reconstruction binding is missing".format(label))
            continue
        for field in ("patch", "source_set_manifest"):
            if evidence_binding.get(field) != lineage_record.get(field):
                errors.append("{} evidence/source-lineage {} binding drift".format(label, field))
        if evidence_binding.get("file_count") != lineage_record.get("file_count"):
            errors.append("{} evidence/source-lineage file-count binding drift".format(label))


def index_records(values: object, label: str,
                  errors: MutableSequence[str]) -> Dict[str, dict]:
    if not isinstance(values, list):
        errors.append("{} record list is missing".format(label))
        return {}
    records = {}  # type: Dict[str, dict]
    for value in values:
        if not isinstance(value, dict) or not isinstance(value.get("id"), str):
            errors.append("{} record identity is malformed".format(label))
            continue
        record_id = value["id"]
        if record_id in records:
            errors.append("duplicate {} record {}".format(label, record_id))
            continue
        records[record_id] = value
    return records


def same_claim_value(observed: object, expected: object) -> bool:
    if isinstance(expected, bool):
        return observed is expected
    if isinstance(expected, float):
        return isinstance(observed, (int, float)) and not isinstance(observed, bool) and close(
            observed, expected, tolerance=1e-12)
    return observed == expected and type(observed) is type(expected)


def check_delivery_links(root: Path, coremark: dict, loop: dict,
                         errors: MutableSequence[str]) -> None:
    try:
        claims_data = load_object(root / CLAIMS_PATH)
        nonclaims_data = load_object(root / NONCLAIMS_PATH)
        manifest_data = load_object(root / EVIDENCE_MANIFEST_PATH)
    except RuntimeError as error:
        errors.append(str(error))
        return
    claims = index_records(claims_data.get("claims"), "claim", errors)
    nonclaims = index_records(nonclaims_data.get("nonclaims"), "nonclaim", errors)
    evidence = index_records(manifest_data.get("evidence"), "evidence manifest", errors)

    for claim_id, expected in EXPECTED_CLAIMS.items():
        claim = claims.get(claim_id)
        if claim is None:
            errors.append("missing OoO history claim {}".format(claim_id))
            continue
        require_exact(claim, {
            "profile": "rv32im_ooo_4k",
            "public": True,
            "source_ref": expected["source_ref"],
            "status": expected["status"],
            "evidence": [expected["evidence"]],
        }, "OoO history claim {}".format(claim_id), errors)
        if not same_claim_value(claim.get("value"), expected["value"]):
            errors.append("OoO history claim value drift: {}".format(claim_id))

    for nonclaim_id, expected in EXPECTED_NONCLAIMS.items():
        nonclaim = nonclaims.get(nonclaim_id)
        if nonclaim is None:
            errors.append("missing OoO history nonclaim {}".format(nonclaim_id))
            continue
        require_exact(nonclaim, {
            "profile": "rv32im_ooo_4k",
            "public": True,
            "status": "not_claimed",
            "evidence_id": expected["evidence_id"],
            "evidence_status": expected["evidence_status"],
            "source_commit": expected["source_commit"],
        }, "OoO history nonclaim {}".format(nonclaim_id), errors)

    expected_evidence = {
        "ooo_coremark_history_public": {
            "claims": COREMARK_CLAIMS,
            "path": COREMARK_PATH,
            "source_ref": "multiple_historical_refs",
            "status": "partial",
        },
        "ooo_loop_remediation_public": {
            "claims": LOOP_CLAIMS,
            "path": LOOP_PATH,
            "source_ref": D12_SOURCE,
            "status": "verified",
        },
    }
    records_by_id = {
        "ooo_coremark_history_public": coremark,
        "ooo_loop_remediation_public": loop,
    }
    for evidence_id, expected in expected_evidence.items():
        item = evidence.get(evidence_id)
        if item is None:
            errors.append("missing OoO history evidence manifest entry {}".format(evidence_id))
            continue
        manifest_path = "../" + expected["path"]
        require_exact(item, {
            "project_id": "npc-riscv-open",
            "public": True,
            "path": manifest_path,
            "claims": expected["claims"],
            "source_ref": expected["source_ref"],
            "status": expected["status"],
        }, "OoO history evidence manifest {}".format(evidence_id), errors)
        evidence_path = root / expected["path"]
        if not evidence_path.is_file():
            errors.append("OoO history evidence payload is missing: {}".format(expected["path"]))
            continue
        if item.get("sha256") != sha256(evidence_path):
            errors.append("OoO history evidence manifest SHA256 drift: {}".format(evidence_id))
        if item.get("size_bytes") != evidence_path.stat().st_size:
            errors.append("OoO history evidence manifest size drift: {}".format(evidence_id))
        record = records_by_id[evidence_id]
        if record.get("claim_ids") != expected["claims"]:
            errors.append("OoO history evidence claim list drift: {}".format(evidence_id))
        for claim_id in expected["claims"]:
            if claims.get(claim_id, {}).get("evidence") != [evidence_id]:
                errors.append("OoO history claim/evidence reverse-link drift: {}".format(claim_id))
        linked_nonclaims = {
            item_id for item_id, nonclaim in nonclaims.items()
            if nonclaim.get("evidence_id") == evidence_id and item_id in EXPECTED_NONCLAIMS
        }
        expected_linked_nonclaims = {
            item_id for item_id, nonclaim in EXPECTED_NONCLAIMS.items()
            if nonclaim["evidence_id"] == evidence_id
        }
        if linked_nonclaims != expected_linked_nonclaims:
            errors.append("OoO history evidence/nonclaim reverse-link drift: {}".format(evidence_id))


def run_checks(root: Path) -> List[str]:
    errors = []  # type: List[str]
    try:
        coremark = load_object(root / COREMARK_PATH)
        loop = load_object(root / LOOP_PATH)
        lineage = load_object(root / LINEAGE_PATH)
    except RuntimeError as error:
        return [str(error)]
    check_coremark(coremark, errors)
    check_loop_remediation(loop, errors)
    check_source_lineage(root, lineage, errors)
    check_evidence_reconstruction_bindings(coremark, loop, lineage, errors)
    check_delivery_links(root, coremark, loop, errors)
    return sorted(set(errors))


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--root", type=Path, required=True)
    args = parser.parse_args()
    errors = run_checks(args.root.resolve())
    if errors:
        raise SystemExit("OOO_HISTORY_CHECK_FAILED\n  - " + "\n  - ".join(errors))
    print("OOO_HISTORY_CHECK_PASS coremark_snapshots=2 source_reconstructions=2 loop_gates=4 identity=14/14")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
