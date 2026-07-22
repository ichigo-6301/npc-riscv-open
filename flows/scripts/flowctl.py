#!/usr/bin/env python3
"""Public-safe dispatcher and release guard for NPC RISC-V profiles."""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import os
import re
import shlex
import shutil
import subprocess
import sys
from pathlib import Path
from typing import Any, Dict, Iterable, List, Mapping, Optional, Sequence, Tuple


RELEASE_IDENTITY = "npc-riscv-open-v0.1.0-rc1"
DEFAULT_PROFILE = "rv32im_ooo_4k"
PROFILE_SYMBOLS = {
    "rv32im_single_perf": "CONFIG_NPC_PROFILE_RV32IM_SINGLE_PERF",
    "rv32ima_sv32_linux": "CONFIG_NPC_PROFILE_RV32IMA_SV32_LINUX",
    "rv32im_ooo_4k": "CONFIG_NPC_PROFILE_RV32IM_OOO_4K",
}
PROFILE_WRAPPERS = {
    profile: "rtl/wrappers/{}_sim_top.sv".format(profile)
    for profile in PROFILE_SYMBOLS
}
PROFILE_FILELISTS = {
    profile: "filelists/{}.f".format(profile) for profile in PROFILE_SYMBOLS
}
WRAPPER_TOP = "npc_public_sim_top"
ALLOWED_CONFIG_KEYS = {
    *PROFILE_SYMBOLS.values(),
    "CONFIG_NPC_PROFILE_ID",
    "CONFIG_NPC_RELEASE_IDENTITY",
    "CONFIG_NPC_IMAGE",
    "CONFIG_NPC_WATCHDOG_CYCLES",
    "CONFIG_NPC_SEED",
    "CONFIG_NPC_DIFFTEST",
    "CONFIG_NPC_REFERENCE_SO",
    "CONFIG_NPC_VCD",
    "CONFIG_NPC_VCD_PATH",
    "CONFIG_NPC_ITRACE",
    "CONFIG_NPC_ITRACE_PATH",
    "CONFIG_NPC_RUN_LINT",
    "CONFIG_NPC_RUN_SMOKE",
    "CONFIG_NPC_RUN_REGRESSION",
}
# Profile maturity is a lifecycle label; individual stage statuses in the
# delivery manifests use the evidence ladder (verified/partial/...).
MATURITY_VALUES = {"stable", "development", "experimental", "archived"}
MIN_PYTHON = (3, 8)

OOO_ACCEPTED_WRAPPER_PARAMETERS = {
    "target_line_hit": "TARGET_LINE_HIT_ENABLE",
    "data_line_hit": "DATA_LINE_HIT_ENABLE",
    "sequential_line_hit": "SEQUENTIAL_LINE_HIT_ENABLE",
    "branch_window_line_delivery": "BRANCH_WINDOW_LINE_DELIVERY_ENABLE",
    "speculative_store_dispatch": "SPECULATIVE_STORE_DISPATCH_ENABLE",
    "correlated_predictor": "CORRELATED_PREDICTOR_ENABLE",
    "same_cycle_ras_forwarding": "SAME_CYCLE_RAS_UPDATE_FORWARDING_ENABLE",
    "ras_self_forward_exclusion": "RAS_SELF_FORWARD_EXCLUSION_ENABLE",
    "raw_completion_wakeup": "RAW_COMPLETION_WAKEUP_ENABLE",
    "same_cycle_dependency_forwarding": "SAME_CYCLE_DEPENDENCY_FORWARDING_ENABLE",
    "head_load_writeback_commit_bypass": "HEAD_LOAD_WRITEBACK_COMMIT_BYPASS_ENABLE",
    "load_response_completion_bypass": "LOAD_RESPONSE_COMPLETION_BYPASS_ENABLE",
    "head_alu_writeback_commit_bypass": "HEAD_ALU_WRITEBACK_COMMIT_BYPASS_ENABLE",
    "head_bru_writeback_commit_bypass": "HEAD_BRU_WRITEBACK_COMMIT_BYPASS_ENABLE",
    "pair_raw_to_final_bypass": "PAIR_RAW_TO_FINAL_BYPASS_ENABLE",
    "serial_ordinary_completion_concurrency": "SERIAL_ORDINARY_COMPLETION_CONCURRENCY_ENABLE",
    "same_cycle_dispatch_issue": "SAME_CYCLE_DISPATCH_ISSUE_ENABLE",
    "same_cycle_branch_dispatch_issue": "SAME_CYCLE_BRANCH_DISPATCH_ISSUE_ENABLE",
    "branch_ordinary_concurrent_issue": "BRANCH_ORDINARY_CONCURRENT_ISSUE_ENABLE",
    "branch_younger_ordinary_concurrent_issue": "BRANCH_YOUNGER_ORDINARY_CONCURRENT_ISSUE_ENABLE",
    "registered_bru_dispatch_ordinary_issue2": "REGISTERED_BRU_DISPATCH_ORDINARY_ISSUE2_ENABLE",
    "issue_operand_fallthrough": "ISSUE_OPERAND_FALLTHROUGH_ENABLE",
    "slot1_final_writeback_commit_bypass": "SLOT1_FINAL_WRITEBACK_COMMIT_BYPASS_ENABLE",
    "branch_issue_final_fallthrough": "BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE",
    "registered_branch_issue_final_fallthrough": "REGISTERED_BRANCH_ISSUE_FINAL_FALLTHROUGH_ENABLE",
    "store_issue_final_fallthrough": "STORE_ISSUE_FINAL_FALLTHROUGH_ENABLE",
    "mdu_mul_completion_fallthrough": "MDU_MUL_COMPLETION_FALLTHROUGH_ENABLE",
    "posted_store_response_ownership": "POSTED_STORE_RESPONSE_OWNERSHIP_ENABLE",
    "posted_store_response_pipeline": "POSTED_STORE_RESPONSE_PIPELINE_ENABLE",
    "dual_posted_store_response_owner": "DUAL_POSTED_STORE_RESPONSE_OWNER_ENABLE",
    "ifetch_same_edge_response_capture": "IFETCH_SAME_EDGE_RESPONSE_CAPTURE_ENABLE",
    "lsu_request_fallthrough": "LSU_REQUEST_FALLTHROUGH_ENABLE",
    "load_transaction_depth3": "LOAD_TRANSACTION_DEPTH3_ENABLE",
    "decode_dispatch_fallthrough": "DECODE_DISPATCH_FALLTHROUGH_ENABLE",
    "fetch_decode_fallthrough": "FETCH_DECODE_FALLTHROUGH_ENABLE",
    "fetch_response_credit_turnover": "FETCH_RESPONSE_CREDIT_TURNOVER_ENABLE",
    "correct_branch_dual_retire": "CORRECT_BRANCH_DUAL_RETIRE_ENABLE",
    "younger_slot1_control_dual_retire": "YOUNGER_SLOT1_CONTROL_DUAL_RETIRE_ENABLE",
    "post_selective_redirect_commit": "POST_SELECTIVE_REDIRECT_COMMIT_ENABLE",
    "selective_transaction_redirect_overlap": "SELECTIVE_TRANSACTION_REDIRECT_OVERLAP_ENABLE",
    "strong_branch_line_delivery": "STRONG_BRANCH_LINE_DELIVERY_ENABLE",
    "dual_trace_sink": "DUAL_TRACE_SINK_ENABLE",
    "cached_cross_line_rolling_carry": "CACHED_CROSS_LINE_ROLLING_CARRY_ENABLE",
    "data_line_same_word_miss_coalescing": "DATA_LINE_SAME_WORD_MISS_COALESCING_ENABLE",
    "data_line_store_response_update": "DATA_LINE_STORE_RESPONSE_UPDATE_ENABLE",
}
OOO_DERIVED_ACCEPTED = {"precise_store_buffer", "store_load_forwarding"}
OOO_DISABLED_WRAPPER_PARAMETERS = {
    "structural_oracle": "STRUCTURAL_THROUGHPUT_ORACLE_ENABLE",
    "singleton_coalesce_oracle": "SINGLETON_COALESCE_ORACLE_ENABLE",
    "partial_pair_oracle": "PARTIAL_PAIR_ORACLE_ENABLE",
}


class FlowError(RuntimeError):
    """A user-facing validation or flow error."""


def parse_config(path: Path) -> Dict[str, str]:
    if not path.is_file():
        raise FlowError("missing {}; run 'make defconfig' first".format(path))
    values: Dict[str, str] = {}
    for number, raw in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        line = raw.strip()
        if not line:
            continue
        if line.startswith("# CONFIG_") and line.endswith(" is not set"):
            values[line[2:-11]] = "n"
            continue
        if not line.startswith("CONFIG_") or "=" not in line:
            raise FlowError("{}:{}: unsupported config syntax".format(path, number))
        key, raw_value = line.split("=", 1)
        value = raw_value.strip()
        if value.startswith('"'):
            try:
                value = str(ast.literal_eval(value))
            except (SyntaxError, ValueError) as error:
                raise FlowError("{}:{}: invalid quoted value: {}".format(path, number, error))
        values[key] = value
    return values


def bool_value(config: Mapping[str, str], key: str) -> bool:
    return config.get(key, "n") == "y"


def require_int(config: Mapping[str, str], key: str, minimum: int = 0) -> int:
    raw = config.get(key, "")
    try:
        value = int(raw, 10)
    except ValueError:
        raise FlowError("{} must be a decimal integer".format(key))
    if value < minimum:
        raise FlowError("{} must be at least {}".format(key, minimum))
    return value


def selected_profile(config: Mapping[str, str]) -> str:
    selected = [profile for profile, symbol in PROFILE_SYMBOLS.items() if bool_value(config, symbol)]
    if len(selected) != 1:
        raise FlowError("exactly one public profile must be selected; got {}".format(selected))
    profile = selected[0]
    if config.get("CONFIG_NPC_PROFILE_ID") != profile:
        raise FlowError("CONFIG_NPC_PROFILE_ID does not match selected profile {}".format(profile))
    return profile


def load_yaml(path: Path) -> Dict[str, Any]:
    if not path.is_file():
        raise FlowError("missing delivery manifest: {}".format(path))
    try:
        import yaml  # type: ignore
    except ImportError:
        try:
            value = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError):
            raise FlowError("PyYAML is required to read {}".format(path))
    else:
        try:
            value = yaml.safe_load(path.read_text(encoding="utf-8"))
        except Exception as error:
            raise FlowError("invalid YAML {}: {}".format(path, error))
    if not isinstance(value, dict):
        raise FlowError("{} must contain a YAML mapping".format(path))
    return value


def manifest_path(root: Path, group: str, identifier: str) -> Path:
    for suffix in (".yaml", ".yml"):
        candidate = root / "delivery" / group / (identifier + suffix)
        if candidate.is_file():
            return candidate
    return root / "delivery" / group / (identifier + ".yaml")


def list_value(value: Any) -> List[str]:
    if value is None:
        return []
    if isinstance(value, str):
        return [value]
    if isinstance(value, list) and all(isinstance(item, str) for item in value):
        return list(value)
    raise FlowError("manifest value must be a string or string list")


def relative_public_path(value: str, field: str) -> str:
    path = Path(value)
    if path.is_absolute() or ".." in path.parts or not value.strip():
        raise FlowError("{} must be a non-empty repository-relative path: {}".format(field, value))
    return path.as_posix()


def profile_manifests(root: Path, profile: str) -> Tuple[Dict[str, Any], Dict[str, Any]]:
    profile_data = load_yaml(manifest_path(root, "profiles", profile))
    if profile_data.get("profile_id") != profile:
        raise FlowError("profile manifest identity mismatch for {}".format(profile))
    source_set_id = profile_data.get("source_set")
    if not isinstance(source_set_id, str) or not source_set_id:
        raise FlowError("{} profile is missing source_set".format(profile))
    source_data = load_yaml(manifest_path(root, "source_sets", source_set_id))
    if source_data.get("source_set_id") != source_set_id:
        raise FlowError("source-set identity mismatch for {}".format(source_set_id))
    if source_data.get("profile") != profile:
        raise FlowError("source set {} is bound to a different profile".format(source_set_id))
    return profile_data, source_data


def find_named_config(root: Path, group: str, name: Any, key_names: Sequence[str]) -> Optional[Path]:
    if not isinstance(name, str) or not name:
        return None
    direct_candidates = [
        root / "delivery" / "configs" / group / name,
        root / "delivery" / "configs" / group / (name + ".yaml"),
        root / "delivery" / "configs" / group / (name + ".yml"),
    ]
    for candidate in direct_candidates:
        if candidate.is_file():
            return candidate
    directory = root / "delivery" / "configs" / group
    if not directory.is_dir():
        return None
    for candidate in sorted([*directory.glob("*.yaml"), *directory.glob("*.yml")]):
        try:
            data = load_yaml(candidate)
        except FlowError:
            continue
        if any(data.get(key) == name for key in key_names):
            return candidate
    return None


def nested_mapping(data: Mapping[str, Any], *keys: str) -> Mapping[str, Any]:
    value: Any = data
    for key in keys:
        if not isinstance(value, Mapping):
            return {}
        value = value.get(key)
    return value if isinstance(value, Mapping) else {}


def is_power_of_two(value: Any) -> bool:
    return isinstance(value, int) and value > 0 and (value & (value - 1)) == 0


def require_wrapper_parameter(wrapper_text: str, name: str, enabled: bool) -> None:
    value = "1'b1" if enabled else "1'b0"
    pattern = r"\.{}\s*\(\s*{}\s*\)".format(re.escape(name), re.escape(value))
    if re.search(pattern, wrapper_text) is None:
        raise FlowError("OoO wrapper must lock {} to {}".format(name, value))


def validate_ooo_release_contract(root: Path, info: Mapping[str, Any]) -> None:
    if info["profile"] != "rv32im_ooo_4k":
        return
    design = info["design_data"].get("parameters", {})
    required_design = {
        "isa": "RV32IM",
        "abi": "ilp32",
        "architectural_registers": 32,
        "physical_registers": 64,
        "dispatch_width": 2,
        "issue_width": 2,
        "completion_width": 2,
        "commit_width": 2,
        "rob_entries": 8,
        "iq_entries": 8,
        "branch_checkpoint_entries": 2,
        "conditional_predictor_entries": 256,
        "accepted_mechanisms": 47,
        "observation_oracles_enabled": 0,
    }
    for key, expected in required_design.items():
        if design.get(key) != expected:
            raise FlowError("OoO release design drift: {} must be {}".format(key, expected))
    pair = design.get("instruction_pair_storage", {})
    data = design.get("data_word_cache", {})
    if not isinstance(pair, Mapping) or not isinstance(data, Mapping):
        raise FlowError("OoO release cache/storage declarations are missing")
    for label, mapping, entries, bits, payload in (
        ("instruction_pair_storage", pair, 512, 64, 4096),
        ("data_word_cache", data, 1024, 32, 4096),
    ):
        if mapping.get("entries") != entries or mapping.get("payload_bits_per_entry") != bits or mapping.get("payload_bytes") != payload:
            raise FlowError("OoO {} declaration drift".format(label))
        if mapping.get("ways") != 1 or not is_power_of_two(mapping.get("entries")):
            raise FlowError("OoO {} must remain one-way with power-of-two capacity".format(label))

    constraints = info["run_data"].get("constraints", {})
    for key, expected in (
        ("ifetch_latency_cycles", 2),
        ("lsu_latency_cycles", 3),
        ("dpi_memory_latency_cycles", 2),
        ("accounting_level", 0),
        ("structural_oracles", False),
    ):
        if constraints.get(key) != expected:
            raise FlowError("OoO release run drift: {} must be {}".format(key, expected))

    upstream = root / "provenance/upstream/rv32im_ooo_4k/release_manifest.json"
    if not upstream.is_file():
        return
    try:
        release = json.loads(upstream.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise FlowError("invalid OoO upstream release manifest: {}".format(error))
    accepted = release.get("accepted_mechanisms")
    disabled = release.get("disabled_oracles")
    config = release.get("config")
    if not isinstance(accepted, list) or len(accepted) != 47:
        raise FlowError("OoO upstream release must contain 47 accepted mechanisms")
    if not isinstance(disabled, list) or len(disabled) != 17:
        raise FlowError("OoO upstream release must contain 17 disabled Oracles")
    if set(accepted) != set(OOO_ACCEPTED_WRAPPER_PARAMETERS) | OOO_DERIVED_ACCEPTED:
        raise FlowError("OoO wrapper contract does not match the upstream accepted mechanism list")
    if not isinstance(config, Mapping) or config.get("target_line_entries") != "512" or config.get("data_line_entries") != "1024":
        raise FlowError("OoO upstream release capacity manifest drift")

    wrapper = root / str(info["wrapper_file"])
    wrapper_text = wrapper.read_text(encoding="utf-8")
    for mechanism, parameter in OOO_ACCEPTED_WRAPPER_PARAMETERS.items():
        require_wrapper_parameter(wrapper_text, parameter, True)
    for oracle, parameter in OOO_DISABLED_WRAPPER_PARAMETERS.items():
        if oracle not in disabled:
            raise FlowError("OoO upstream manifest is missing disabled Oracle {}".format(oracle))
        require_wrapper_parameter(wrapper_text, parameter, False)
    for parameter, value in (
        ("TARGET_LINE_ENTRY_COUNT", "512"),
        ("TARGET_LINE_WAY_COUNT", "1"),
        ("CONDITIONAL_PRED_ENTRIES", "256"),
        ("DATA_LINE_COUNT", "1024"),
        ("DATA_LINE_WAY_COUNT", "1"),
    ):
        if re.search(r"\.{}\s*\(\s*{}\s*\)".format(parameter, value), wrapper_text) is None:
            raise FlowError("OoO wrapper capacity drift: {}".format(parameter))


def validate_compile_contract(info: Mapping[str, Any]) -> None:
    rtl = nested_mapping(info["source_data"], "groups", "rtl")
    defines = set(list_value(rtl.get("verilog_defines")))
    profile = str(info["profile"])
    required = {
        "rv32im_single_perf": {
            "NPC_USE_DPI", "NPC_M_EXTENSION", "NPC_DPI_MEM_LATENCY=2",
        },
        "rv32ima_sv32_linux": {
            "NPC_USE_DPI", "NPC_M_EXTENSION", "NPC_DPI_MEM_LATENCY=0",
            "NPC_BRANCH_PRED", "NPC_IF_HIT_PIPELINE", "NPC_LSU_HIT_PIPELINE",
            "NPC_LSU_LOAD_BYPASS", "NPC_EX_MEM_SKID", "NPC_STORE_BUFFER_ENABLE",
            "NPC_STORE_BUFFER_ENTRIES=2", "NPC_FAST_MUL",
            "NPC_FAST_MUL_LATENCY=2", "NPC_HAS_MMU=1", "NPC_HAS_ITLB=1",
            "NPC_HAS_DTLB=1", "NPC_ITLB_ENTRIES=16", "NPC_DTLB_ENTRIES=16",
        },
        "rv32im_ooo_4k": {
            "NPC_USE_DPI", "NPC_M_EXTENSION", "NPC_DPI_MEM_LATENCY=2",
            "NPC_DPI_IFETCH_LATENCY=2", "NPC_DPI_LSU_LATENCY=3",
            "NPC_OOO_DISPATCH_WIDTH=2", "NPC_OOO_COMMIT_WIDTH=2",
            "NPC_OOO_FRONTEND_IF2_PAIR=1", "NPC_OOO_DUAL_WB=1",
            "NPC_OOO_BACKEND_PIPELINE=1", "NPC_OOO_COMPLETION_ARB_FIXED=1",
            "NPC_OOO_ALU_SCHED_ALU0_ONLY=1",
        },
    }[profile]
    missing = sorted(required - defines)
    if missing:
        raise FlowError("{} compile contract is missing {}".format(profile, missing))
    forbidden_tokens = ("ORACLE", "NVBOARD", "XPM")
    forbidden = sorted(value for value in defines if any(token in value for token in forbidden_tokens))
    if forbidden:
        raise FlowError("{} compile contract enables forbidden release define(s): {}".format(profile, forbidden))


def profile_info(root: Path, profile: str) -> Dict[str, Any]:
    profile_data, source_data = profile_manifests(root, profile)
    config_links = (
        ("design", profile_data.get("design_config"), ("design_id",)),
        ("profile", profile, ("profile_config_id",)),
        ("target", profile_data.get("target_config"), ("target_id",)),
        ("run", profile_data.get("default_run_config"), ("run_id",)),
    )
    linked_configs: Dict[str, Dict[str, Any]] = {}
    for group, name, key_names in config_links:
        config_path = find_named_config(root, group, name, key_names)
        if config_path is None:
            raise FlowError("{} profile references missing {} config {}".format(profile, group, name))
        linked_configs[group] = load_yaml(config_path)
    rtl_group = nested_mapping(source_data, "groups", "rtl")
    declared_filelists = list_value(rtl_group.get("filelists"))
    filelist = profile_data.get("public_filelist") or profile_data.get("filelist")
    if not isinstance(filelist, str):
        filelist = declared_filelists[0] if declared_filelists else PROFILE_FILELISTS[profile]
    filelist = relative_public_path(filelist, "public filelist")
    if filelist != PROFILE_FILELISTS[profile]:
        raise FlowError("{} must use public filelist {}".format(profile, PROFILE_FILELISTS[profile]))

    wrapper_file = profile_data.get("wrapper_file") or PROFILE_WRAPPERS[profile]
    if not isinstance(wrapper_file, str):
        raise FlowError("wrapper_file must be a string")
    wrapper_file = relative_public_path(wrapper_file, "wrapper_file")
    if wrapper_file != PROFILE_WRAPPERS[profile]:
        raise FlowError("{} must use wrapper {}".format(profile, PROFILE_WRAPPERS[profile]))

    wrapper_top = profile_data.get("wrapper_top_module", WRAPPER_TOP)
    if wrapper_top != WRAPPER_TOP:
        raise FlowError("all public profiles must use wrapper top {}".format(WRAPPER_TOP))
    native_top = profile_data.get("top_module")
    if not isinstance(native_top, str) or not re.fullmatch(r"[A-Za-z_][A-Za-z0-9_$]*", native_top):
        raise FlowError("{} has an invalid native top_module".format(profile))

    commit_sha = profile_data.get("commit_sha")
    source_ref = profile_data.get("source_ref")
    source_root = profile_data.get("source_root")
    if not isinstance(commit_sha, str) or not re.fullmatch(r"[0-9a-f]{40}", commit_sha):
        raise FlowError("{} commit_sha must be a full lowercase Git SHA".format(profile))
    if not isinstance(source_ref, str) or not source_ref.strip():
        raise FlowError("{} source_ref is missing".format(profile))
    if not isinstance(source_root, str):
        raise FlowError("{} source_root is missing".format(profile))
    relative_public_path(source_root or ".", "source_root")
    for key in ("source_ref", "commit_sha", "source_root"):
        if source_data.get(key) != profile_data.get(key):
            raise FlowError("{} differs between profile and source-set manifests".format(key))

    maturity = profile_data.get("maturity")
    if maturity not in MATURITY_VALUES:
        raise FlowError("{} has unsupported maturity {}".format(profile, maturity))

    design_data = linked_configs["design"]
    design_parameters = design_data.get("parameters")
    if not isinstance(design_parameters, Mapping):
        raise FlowError("{} design config has no parameters mapping".format(profile))
    if design_parameters.get("native_top_module") != native_top:
        raise FlowError("{} native top differs between profile and design config".format(profile))
    if source_data.get("native_top_module") != native_top:
        raise FlowError("{} native top differs between profile and source set".format(profile))
    if source_data.get("public_wrapper") != wrapper_file:
        raise FlowError("{} wrapper differs between profile and source set".format(profile))
    if source_data.get("public_filelist") != filelist:
        raise FlowError("{} filelist differs between profile and source set".format(profile))

    run_data = linked_configs["run"]
    expected_run_links = {
        "profile": profile,
        "design": profile_data.get("design_config"),
        "target": profile_data.get("target_config"),
        "source_ref": source_ref,
        "commit_sha": commit_sha,
    }
    for key, expected in expected_run_links.items():
        if run_data.get(key) != expected:
            raise FlowError("{} differs between profile and default run config".format(key))
    constraints = run_data.get("constraints")
    if not isinstance(constraints, Mapping) or constraints.get("architectural_overrides_allowed") is not False:
        raise FlowError("{} default run must reject architectural overrides".format(profile))
    target_data = linked_configs["target"]
    if target_data.get("target_kind") != "simulation":
        raise FlowError("{} public target must be a simulation target".format(profile))

    return {
        "profile": profile,
        "profile_data": profile_data,
        "source_data": source_data,
        "filelist": filelist,
        "wrapper_file": wrapper_file,
        "wrapper_top": wrapper_top,
        "native_top": native_top,
        "commit_sha": commit_sha,
        "source_ref": source_ref,
        "source_root": source_root,
        "maturity": maturity,
        "design_data": design_data,
        "target_data": target_data,
        "run_data": run_data,
    }


def validate_config(root: Path, config: Mapping[str, str]) -> Dict[str, Any]:
    unknown = sorted(set(config) - ALLOWED_CONFIG_KEYS)
    if unknown:
        raise FlowError("unknown or architectural config override(s): {}".format(", ".join(unknown)))
    profile = selected_profile(config)
    if config.get("CONFIG_NPC_RELEASE_IDENTITY") != RELEASE_IDENTITY:
        raise FlowError("release identity must be {}".format(RELEASE_IDENTITY))
    require_int(config, "CONFIG_NPC_WATCHDOG_CYCLES", minimum=1)
    require_int(config, "CONFIG_NPC_SEED", minimum=0)
    if bool_value(config, "CONFIG_NPC_DIFFTEST") and not config.get("CONFIG_NPC_REFERENCE_SO"):
        raise FlowError("difftest is enabled but CONFIG_NPC_REFERENCE_SO is empty")
    info = profile_info(root, profile)
    validate_compile_contract(info)
    validate_ooo_release_contract(root, info)
    if profile != "rv32ima_sv32_linux" and "SV32" in str(info["profile_data"].get("isa", "")).upper():
        raise FlowError("Sv32 is only valid for the Linux profile")
    return info


def config_display(config: Mapping[str, str], info: Mapping[str, Any]) -> List[Tuple[str, str]]:
    design_parameters = info["design_data"]["parameters"]
    constraints = info["run_data"].get("constraints", {})
    rows = [
        ("release_identity", RELEASE_IDENTITY),
        ("profile_id", str(info["profile"])),
        ("source_ref", str(info["source_ref"])),
        ("source_commit", str(info["commit_sha"])),
        ("maturity", str(info["maturity"])),
        ("isa", str(design_parameters.get("isa", "not-declared"))),
        ("native_top", str(info["native_top"])),
        ("wrapper_top", str(info["wrapper_top"])),
        ("filelist", str(info["filelist"])),
        ("watchdog_cycles", config["CONFIG_NPC_WATCHDOG_CYCLES"]),
        ("seed", config["CONFIG_NPC_SEED"]),
        ("difftest", "1" if bool_value(config, "CONFIG_NPC_DIFFTEST") else "0"),
        ("vcd", "1" if bool_value(config, "CONFIG_NPC_VCD") else "0"),
        ("itrace", "1" if bool_value(config, "CONFIG_NPC_ITRACE") else "0"),
    ]
    for key in ("dispatch_width", "issue_width", "completion_width", "commit_width"):
        if key in design_parameters:
            rows.append((key, str(design_parameters[key])))
    rows.extend([
        ("ifetch_latency_cycles", str(constraints.get("ifetch_latency_cycles", constraints.get("dpi_memory_latency_cycles", "not-declared")))),
        ("lsu_latency_cycles", str(constraints.get("lsu_latency_cycles", constraints.get("dpi_memory_latency_cycles", "not-declared")))),
        ("memory_latency_cycles", str(constraints.get("dpi_memory_latency_cycles", "not-declared"))),
    ])
    if info["profile"] == "rv32im_ooo_4k":
        rows.extend([
            ("instruction_pair_entries", str(design_parameters["instruction_pair_storage"]["entries"])),
            ("data_word_cache_entries", str(design_parameters["data_word_cache"]["entries"])),
            ("accepted_mechanisms", str(design_parameters["accepted_mechanisms"])),
            ("enabled_oracles", str(design_parameters["observation_oracles_enabled"])),
        ])
    return rows


def strip_filelist_comment(line: str) -> str:
    return line.split("#", 1)[0].split("//", 1)[0].strip()


def filelist_entries(root: Path, filelist: Path) -> Tuple[List[Path], List[Path], List[str]]:
    sources: List[Path] = []
    includes: List[Path] = []
    defines: List[str] = []
    for number, raw in enumerate(filelist.read_text(encoding="utf-8").splitlines(), 1):
        line = strip_filelist_comment(raw)
        if not line:
            continue
        if line.startswith("+incdir+"):
            values = [value for value in line.split("+incdir+", 1)[1].split("+") if value]
            for value in values:
                includes.append(safe_entry(root, value, filelist, number))
            continue
        if line.startswith("+define+"):
            defines.append(line[len("+define+"):])
            continue
        if line.startswith("-D"):
            defines.append(line[2:])
            continue
        if line.startswith(("--language", "--timescale")):
            continue
        if line.startswith("-"):
            raise FlowError("{}:{}: unsupported filelist option {}".format(filelist, number, line))
        sources.append(safe_entry(root, line, filelist, number))
    return sources, includes, defines


def safe_entry(root: Path, value: str, filelist: Path, number: int) -> Path:
    path = Path(value)
    if path.is_absolute() or ".." in path.parts:
        raise FlowError("{}:{}: non-public filelist path {}".format(filelist, number, value))
    resolved = (root / path).resolve()
    try:
        resolved.relative_to(root.resolve())
    except ValueError:
        raise FlowError("{}:{}: path escapes repository: {}".format(filelist, number, value))
    return resolved


def declared_allowlist(root: Path, profile: str, source_data: Mapping[str, Any]) -> List[Dict[str, str]]:
    rtl = nested_mapping(source_data, "groups", "rtl")
    inline = list_value(rtl.get("allowlist"))
    if inline:
        return [{"destination": value, "sha256": ""} for value in inline]
    manifest_name = source_data.get("allowlist_manifest")
    if not isinstance(manifest_name, str) or not manifest_name:
        raise FlowError("source set {} has no allowlist or allowlist_manifest".format(profile))
    candidates = [
        root / manifest_name,
        root / "provenance/source_allowlist.json",
        root / "export/source_allowlist.json",
    ]
    manifest_path = next((path for path in candidates if path.is_file()), None)
    if manifest_path is None:
        raise FlowError("source allowlist is missing (looked for {})".format(", ".join(str(path) for path in candidates)))
    try:
        manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
    except (OSError, json.JSONDecodeError) as error:
        raise FlowError("invalid source allowlist {}: {}".format(manifest_path, error))
    profiles = manifest.get("profiles") if isinstance(manifest, dict) else None
    if not isinstance(profiles, list):
        raise FlowError("source allowlist {} has no profiles list".format(manifest_path))
    key = source_data.get("allowlist_profile_key", profile)
    for item in profiles:
        if isinstance(item, dict) and item.get("profile_id") == key:
            entries = item.get("entries")
            if isinstance(entries, list) and entries:
                result = []
                for entry in entries:
                    if not isinstance(entry, dict):
                        raise FlowError("invalid source allowlist entry for {}".format(profile))
                    destination = entry.get("destination")
                    digest = entry.get("sha256")
                    if not isinstance(destination, str) or not isinstance(digest, str):
                        raise FlowError("incomplete source allowlist entry for {}".format(profile))
                    result.append({"destination": destination, "sha256": digest})
                return result
    raise FlowError("source allowlist {} has no entries for {}".format(manifest_path, key))


def check_source_closure(root: Path, info: Mapping[str, Any]) -> Dict[str, int]:
    profile = str(info["profile"])
    filelist = root / str(info["filelist"])
    wrapper = root / str(info["wrapper_file"])
    if not filelist.is_file():
        raise FlowError("missing public filelist {}".format(info["filelist"]))
    if not wrapper.is_file():
        raise FlowError("missing public wrapper {}".format(info["wrapper_file"]))
    sources, includes, defines = filelist_entries(root, filelist)
    rtl_contract = nested_mapping(info["source_data"], "groups", "rtl")
    expected_include_dirs = list_value(rtl_contract.get("public_include_dirs")) + ["sim/include"]
    actual_include_dirs = [path.relative_to(root).as_posix() for path in includes]
    if actual_include_dirs != expected_include_dirs:
        raise FlowError("{} include roots differ from the source-set compile contract".format(info["filelist"]))
    expected_defines = list_value(rtl_contract.get("verilog_defines"))
    if defines != expected_defines:
        raise FlowError("{} defines differ from the source-set compile contract".format(info["filelist"]))
    if wrapper.resolve() not in [path.resolve() for path in sources]:
        raise FlowError("{} must include its profile wrapper".format(info["filelist"]))
    missing = [path for path in [*sources, *includes] if not path.exists()]
    if missing:
        raise FlowError("missing source closure: {}".format(", ".join(str(path.relative_to(root)) for path in missing)))

    other_profiles = set(PROFILE_SYMBOLS) - {profile}
    for path in [*sources, *includes]:
        relative = path.relative_to(root).as_posix()
        for other in other_profiles:
            if "rtl/profiles/{}/".format(other) in relative + "/":
                raise FlowError("{} references another profile source set: {}".format(profile, relative))

    modules: Dict[str, Path] = {}
    duplicates: List[str] = []
    module_pattern = re.compile(r"\bmodule\s+([A-Za-z_][A-Za-z0-9_$]*)")
    include_pattern = re.compile(r"`include\s+\"([^\"]+)\"")
    for source in sources:
        if source.suffix.lower() not in {".v", ".sv", ".vh", ".svh"}:
            raise FlowError("unsupported RTL source extension: {}".format(source.relative_to(root)))
        text = source.read_text(encoding="utf-8", errors="replace")
        for include_name in include_pattern.findall(text):
            include_path = Path(include_name)
            if include_path.is_absolute() or ".." in include_path.parts:
                raise FlowError("unsafe RTL include {} in {}".format(include_name, source.relative_to(root)))
            # Public filelists use explicit include roots; relying on a tool's
            # current-source-directory policy is non-portable across versions.
            candidates = [directory / include_path for directory in includes]
            if not any(candidate.is_file() for candidate in candidates):
                raise FlowError(
                    "unresolved RTL include {} in {}; add the profile-local include root to {}".format(
                        include_name, source.relative_to(root), info["filelist"]
                    )
                )
        for name in module_pattern.findall(text):
            if name in modules and modules[name] != source:
                duplicates.append("{} ({} and {})".format(name, modules[name].relative_to(root), source.relative_to(root)))
            modules[name] = source
    if duplicates:
        raise FlowError("duplicate modules in selected source set: {}".format("; ".join(duplicates)))
    if WRAPPER_TOP not in modules:
        raise FlowError("wrapper module {} not found in selected filelist".format(WRAPPER_TOP))

    allowlist = declared_allowlist(root, profile, info["source_data"])
    if not allowlist:
        raise FlowError("source set has an empty RTL allowlist")
    expected_sources = {entry["destination"]: entry["sha256"] for entry in allowlist}
    actual_sources = {
        path.relative_to(root).as_posix(): path
        for path in sources
        if path.resolve() != wrapper.resolve()
    }
    if set(actual_sources) != set(expected_sources):
        missing = sorted(set(expected_sources) - set(actual_sources))
        extra = sorted(set(actual_sources) - set(expected_sources))
        raise FlowError("filelist/allowlist mismatch; missing={} extra={}".format(missing, extra))
    for relative, source in actual_sources.items():
        expected_digest = expected_sources[relative]
        if expected_digest:
            actual_digest = hashlib.sha256(source.read_bytes()).hexdigest()
            if actual_digest != expected_digest:
                raise FlowError("source SHA256 drift: {}".format(relative))
    return {"sources": len(sources), "includes": len(includes), "modules": len(modules), "allowlist": len(allowlist)}


def tracked_or_present_files(root: Path) -> Iterable[Path]:
    if (root / ".git").exists() and shutil.which("git"):
        completed = subprocess.run(
            ["git", "-C", str(root), "ls-files", "-z"],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            check=False,
        )
        if completed.returncode == 0:
            for raw in completed.stdout.split(b"\0"):
                if raw:
                    yield root / raw.decode("utf-8", errors="strict")
            return
    skipped = {".git", "build", "obj_dir", "waves", ".cache", "__pycache__"}
    for path in sorted(root.rglob("*")):
        relative = path.relative_to(root)
        if any(part in skipped for part in relative.parts):
            continue
        if path.is_file() or path.is_symlink():
            yield path


def hygiene_check(root: Path) -> Dict[str, int]:
    errors: List[str] = []
    files = 0
    text_files = 0
    protected_suffixes = {".db", ".ddc", ".gds", ".gds2", ".lef", ".lib", ".ndm", ".spef"}
    secret_patterns = [
        re.compile(r"ghp_[A-Za-z0-9]{20,}"),
        re.compile(r"github_pat_[A-Za-z0-9_]{20,}"),
        re.compile(r"AKIA[0-9A-Z]{16}"),
        re.compile(r"-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----"),
    ]
    absolute_patterns = [
        re.compile(r"(?:^|[\s\"'=])/(?:home|mnt|Users|private|scratch|workspace)/"),
        re.compile(r"\b[A-Za-z]:[\\/](?:Users|master|project|work|src)[\\/]"),
    ]
    forbidden_ui = ("nv" + "board").casefold()
    forbidden_tree = ("ne" + "mu").casefold()
    dependency_pattern = re.compile(
        r"(?i)(?:#\s*include|\bimport\b|\brequire\b|\bsource\b|\bexec(?:ute)?\b|"
        r"\bfile(?:list)?\b|\bpath\b|\blink\b|\bload\b)[^\n]*"
    )

    def code_without_comments(value: str) -> str:
        value = re.sub(r"/\*.*?\*/", "", value, flags=re.S)
        value = re.sub(r"//[^\n]*", "", value)
        lines = []
        for line in value.splitlines():
            if re.match(r"^\s*#\s*include\b", line):
                lines.append(line)
            else:
                lines.append(line.split("#", 1)[0])
        return "\n".join(lines)
    for path in tracked_or_present_files(root):
        files += 1
        relative = path.relative_to(root).as_posix()
        folded = relative.casefold()
        if path.is_symlink():
            errors.append("symlink is not allowed in the public bundle: {}".format(relative))
            continue
        if path.suffix.casefold() in protected_suffixes:
            errors.append("protected implementation artifact: {}".format(relative))
        if forbidden_ui in folded or forbidden_tree in folded:
            errors.append("excluded private/board dependency in path: {}".format(relative))
        if path.stat().st_size > 10 * 1024 * 1024:
            errors.append("oversized public file (>10 MiB): {}".format(relative))
            continue
        raw = path.read_bytes()
        if b"\0" in raw:
            continue
        try:
            text = raw.decode("utf-8")
        except UnicodeDecodeError:
            errors.append("non-UTF-8 text or unapproved binary: {}".format(relative))
            continue
        text_files += 1
        # Provenance and documentation may name excluded dependencies. In
        # source/simulation/test assets only an actual include/import/path-like
        # reference is rejected; ordinary explanatory comments are harmless.
        public_metadata = relative.startswith(("docs/", "delivery/", "provenance/"))
        dependency_lines = "\n".join(
            match.group(0) for match in dependency_pattern.finditer(code_without_comments(text))
        )
        if forbidden_ui in dependency_lines.casefold() and not public_metadata:
            errors.append("excluded board dependency referenced by {}".format(relative))
        if forbidden_tree in dependency_lines.casefold() and relative.startswith(("rtl/", "sim/", "tests/", "filelists/")):
            errors.append("excluded reference-source dependency referenced by {}".format(relative))
        for pattern in absolute_patterns:
            if pattern.search(text):
                errors.append("host absolute path found in {}".format(relative))
                break
        for pattern in secret_patterns:
            if pattern.search(text):
                errors.append("credential-like text found in {}".format(relative))
                break
    if errors:
        raise FlowError("public hygiene failed:\n  - " + "\n  - ".join(sorted(set(errors))))
    return {"files": files, "text_files": text_files}


def executable(name: str) -> str:
    resolved = shutil.which(name)
    if not resolved:
        raise FlowError("tool not found on PATH: {}".format(name))
    return resolved


def quote_command(command: Sequence[str]) -> str:
    return " ".join(shlex.quote(item) for item in command)


def run_command(command: Sequence[str], root: Path, environment: Optional[Mapping[str, str]] = None, dry_run: bool = False) -> None:
    print("command: " + quote_command(command))
    if dry_run:
        return
    completed = subprocess.run(list(command), cwd=str(root), env=dict(environment) if environment else None)
    if completed.returncode != 0:
        raise FlowError("command failed with exit status {}".format(completed.returncode))


def runtime_environment(config: Mapping[str, str], reference_so: str = "") -> Dict[str, str]:
    environment = os.environ.copy()
    environment["NPC_OPEN_SEED"] = config["CONFIG_NPC_SEED"]
    environment["NPC_OPEN_ITRACE"] = "1" if bool_value(config, "CONFIG_NPC_ITRACE") else "0"
    environment["NPC_OPEN_ITRACE_PATH"] = config.get("CONFIG_NPC_ITRACE_PATH", "")
    environment["NPC_OPEN_DIFFTEST"] = "1" if reference_so else "0"
    if reference_so:
        environment["NPC_OPEN_REFERENCE_SO"] = reference_so
    return environment


def image_argument(config: Mapping[str, str], fallback: Optional[Path] = None, required: bool = True) -> str:
    value = os.environ.get("NPC_OPEN_IMAGE", "") or config.get("CONFIG_NPC_IMAGE", "")
    if not value and fallback is not None and fallback.is_file():
        value = str(fallback)
    if required and not value:
        raise FlowError("no program image selected; set NPC_OPEN_IMAGE or CONFIG_NPC_IMAGE")
    return value


def runner_command(root: Path, config: Mapping[str, str], info: Mapping[str, Any], image: str, dry_run: bool, build_only: bool = False, reference_so: str = "") -> List[str]:
    runner = root / "sim/common/verilator_runner.py"
    if not runner.is_file():
        raise FlowError("missing shared Verilator runner: sim/common/verilator_runner.py")
    constraints = info["run_data"].get("constraints", {})
    memory_latency = constraints.get("dpi_memory_latency_cycles")
    if not isinstance(memory_latency, int) or memory_latency < 0:
        raise FlowError("default run must declare a non-negative dpi_memory_latency_cycles")
    ifetch_latency = constraints.get("ifetch_latency_cycles", memory_latency)
    lsu_latency = constraints.get("lsu_latency_cycles", memory_latency)
    if not isinstance(ifetch_latency, int) or ifetch_latency < 0 or not isinstance(lsu_latency, int) or lsu_latency < 0:
        raise FlowError("default run contains an invalid IF/LSU latency")
    command = [
        sys.executable,
        str(runner),
        "--profile",
        str(info["profile"]),
        "--top",
        str(info["wrapper_top"]),
        "--filelist",
        str(info["filelist"]),
        "--build-dir",
        "build/{}".format(info["profile"]),
        "--watchdog",
        config["CONFIG_NPC_WATCHDOG_CYCLES"],
        "--seed",
        config["CONFIG_NPC_SEED"],
        "--ifetch-latency",
        str(ifetch_latency),
        "--lsu-latency",
        str(lsu_latency),
        "--memory-latency",
        str(memory_latency),
    ]
    if image:
        command.extend(["--image", image])
    if build_only:
        command.append("--build-only")
    if reference_so:
        command.extend(["--difftest-so", reference_so])
    if bool_value(config, "CONFIG_NPC_VCD"):
        command.extend(["--trace", "--vcd", config.get("CONFIG_NPC_VCD_PATH", "build/waves/sim.vcd")])
    if dry_run:
        command.append("--dry-run")
    return command


def run_sim(root: Path, config: Mapping[str, str], info: Mapping[str, Any], image: str, dry_run: bool, build_only: bool = False, reference_so: str = "") -> None:
    command = runner_command(root, config, info, image, dry_run, build_only, reference_so)
    run_command(command, root, runtime_environment(config, reference_so), dry_run=False)


def lint(root: Path, info: Mapping[str, Any], dry_run: bool) -> None:
    check_source_closure(root, info)
    tool = os.environ.get("VERILATOR", "verilator")
    if not dry_run:
        tool = executable(tool)
    command = [
        tool,
        "--lint-only",
        "--language",
        "1800-2012",
        "--Wall",
        "--Wno-fatal",
        "--top-module",
        str(info["wrapper_top"]),
        "-f",
        str(info["filelist"]),
    ]
    run_command(command, root, dry_run=dry_run)


def regression_cases(root: Path, profile: str) -> List[Path]:
    manifest = root / "tests" / profile / "regression.json"
    if manifest.is_file():
        data = json.loads(manifest.read_text(encoding="utf-8"))
        raw_cases = data.get("cases") if isinstance(data, dict) else None
        if not isinstance(raw_cases, list):
            raise FlowError("{} must contain a cases list".format(manifest))
        result: List[Path] = []
        for item in raw_cases:
            image = item.get("image") if isinstance(item, dict) else item
            if not isinstance(image, str):
                raise FlowError("invalid regression case in {}".format(manifest))
            path = root / relative_public_path(image, "regression image")
            if isinstance(item, dict) and "sha256" in item:
                digest = item.get("sha256")
                if not isinstance(digest, str) or re.fullmatch(r"[0-9a-f]{64}", digest) is None:
                    raise FlowError("invalid regression SHA256 in {}".format(manifest))
                if path.is_file() and hashlib.sha256(path.read_bytes()).hexdigest() != digest:
                    raise FlowError("regression image SHA256 drift: {}".format(path.relative_to(root)))
            result.append(path)
        return result
    return sorted((root / "tests" / profile / "regression").glob("*.hex"))


def dispatch(root: Path, config_path: Path, args: argparse.Namespace) -> None:
    if args.command == "defconfig":
        source = Path(args.source)
        if not source.is_absolute():
            source = root / source
        if not source.is_file():
            raise FlowError("defconfig does not exist: {}".format(source))
        config_path.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(str(source), str(config_path))
        print("wrote {}".format(config_path))
        return

    config = parse_config(config_path)
    if args.command == "hygiene":
        summary = hygiene_check(root)
        print("PUBLIC_HYGIENE_PASS files={} text_files={}".format(summary["files"], summary["text_files"]))
        return
    info = validate_config(root, config)
    if args.command == "show-config":
        for key, value in config_display(config, info):
            print("{}={}".format(key, value))
        return
    if args.command == "config-check":
        print("CONFIG_CHECK_PASS profile={} release={}".format(info["profile"], RELEASE_IDENTITY))
        return
    if args.command == "source-check":
        summary = check_source_closure(root, info)
        print("SOURCE_CHECK_PASS profile={} sources={} includes={} modules={} allowlist={}".format(
            info["profile"], summary["sources"], summary["includes"], summary["modules"], summary["allowlist"]
        ))
        return
    if args.command == "lint":
        lint(root, info, args.dry_run)
        return
    if args.command == "sim":
        image = image_argument(config, required=not args.dry_run)
        run_sim(root, config, info, image, args.dry_run)
        return
    if args.command == "smoke":
        fallback = root / "tests" / str(info["profile"]) / "smoke.hex"
        declared = regression_cases(root, str(info["profile"]))
        if fallback not in declared:
            raise FlowError("profile smoke must be hash-locked in regression.json")
        image = image_argument(config, fallback=fallback)
        run_sim(root, config, info, image, False)
        return
    if args.command == "regression":
        cases = regression_cases(root, str(info["profile"]))
        if not cases:
            raise FlowError("no regression cases declared for {}".format(info["profile"]))
        for image in cases:
            if not image.is_file():
                raise FlowError("missing regression image {}".format(image.relative_to(root)))
            run_sim(root, config, info, str(image), False)
        return
    if args.command == "difftest":
        reference_so = os.environ.get("NPC_OPEN_REFERENCE_SO", "") or config.get("CONFIG_NPC_REFERENCE_SO", "")
        if not reference_so:
            raise FlowError("difftest requires NPC_OPEN_REFERENCE_SO or CONFIG_NPC_REFERENCE_SO")
        if not Path(reference_so).is_file():
            raise FlowError("external reference adapter does not exist: {}".format(reference_so))
        fallback = root / "tests" / str(info["profile"]) / "smoke.hex"
        image = image_argument(config, fallback=fallback)
        run_sim(root, config, info, image, False, reference_so=reference_so)
        return
    if args.command == "opensbi-smoke":
        if info["profile"] != "rv32ima_sv32_linux":
            raise FlowError("opensbi-smoke is only defined for rv32ima_sv32_linux")
        raw_image = os.environ.get("NPC_OPEN_OPENSBI_IMAGE", "")
        fallback = root / "tests/rv32ima_sv32_linux/opensbi-smoke.bin"
        image = raw_image or (str(fallback) if fallback.is_file() else "")
        if not image:
            raise FlowError("set NPC_OPEN_OPENSBI_IMAGE to a bounded external firmware image")
        run_sim(root, config, info, image, False)
        return
    raise FlowError("unsupported command {}".format(args.command))


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", default=Path(__file__).resolve().parents[2])
    parser.add_argument("--config", default=".config")
    subparsers = parser.add_subparsers(dest="command")
    defconfig = subparsers.add_parser("defconfig")
    defconfig.add_argument("--source", required=True)
    subparsers.add_parser("show-config")
    subparsers.add_parser("config-check")
    subparsers.add_parser("source-check")
    subparsers.add_parser("hygiene")
    lint_parser = subparsers.add_parser("lint")
    lint_parser.add_argument("--dry-run", action="store_true")
    sim_parser = subparsers.add_parser("sim")
    sim_parser.add_argument("--dry-run", action="store_true")
    subparsers.add_parser("smoke")
    subparsers.add_parser("regression")
    subparsers.add_parser("difftest")
    subparsers.add_parser("opensbi-smoke")
    return parser


def main() -> int:
    if sys.version_info < MIN_PYTHON:
        print("flowctl: error: Python 3.8 or newer is required", file=sys.stderr)
        return 2
    parser = build_parser()
    args = parser.parse_args()
    if args.command is None:
        parser.print_help()
        return 2
    root = Path(args.root).resolve()
    config_path = Path(args.config)
    if not config_path.is_absolute():
        config_path = root / config_path
    try:
        dispatch(root, config_path, args)
    except (FlowError, OSError, json.JSONDecodeError) as error:
        print("flowctl: error: {}".format(error), file=sys.stderr)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main())
