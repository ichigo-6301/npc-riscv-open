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
D12_INPUT_BUNDLE_PATH = "provenance/upstream/rv32im_ooo_4k/history/d12_input_bundle.json"
D12_FUNCTIONAL_POINTS_PATH = "provenance/upstream/rv32im_ooo_4k/history/d12_functional_identity_points.json"
D12_EFFECTIVE_PARAMETERS_PATH = "provenance/upstream/rv32im_ooo_4k/history/d12_effective_parameters.json"
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
D12_INPUT_BUNDLE_SHA256 = "4735bea060c0cd397fadfee54094a1323f5f17ec610ac49d04f4e2996c46eb4b"
D12_INPUT_BUNDLE_SIZE = 6939
D12_FUNCTIONAL_POINTS_SHA256 = "1c6de6af32c3870b1be39090570e3579234e9847a87d528d965be64fc8d8897a"
D12_FUNCTIONAL_POINTS_SIZE = 7301
D12_EFFECTIVE_PARAMETERS_FILE_SHA256 = "3bb7935089d6f9353ceea5ae9ad7d61e0119cb2fc66f12ba8d45a43710a8f5db"
D12_EFFECTIVE_PARAMETERS_FILE_SIZE = 3405

EXPECTED_D12_ARTIFACTS = [
    {
        "role": "parameter_base",
        "schema": "npc-riscv-open/ooo-d12-tracked-parameter-lock-v1",
        "path": "provenance/upstream/rv32im_ooo_4k/history/rv32im_ooo_4k_legacy.tcl",
        "sha256": "34204e07c2ce9e097b96dc904dc9b8e27592e3f6534aaccf5bf693c40d49be1d",
        "size_bytes": 2397,
        "origin_logical_path": "npc/open/flows/asic/parameters/rv32im_ooo_4k_legacy.tcl",
    },
    {
        "role": "parameter_cache_overlay",
        "schema": "npc-riscv-open/ooo-d12-tracked-parameter-lock-v1",
        "path": "provenance/upstream/rv32im_ooo_4k/history/rv32im_ooo_4k_d10_line32.tcl",
        "sha256": "ca4f137857abf76fdee79d6e502733aa95ceed564e394aff809b50c2279571f1",
        "size_bytes": 300,
        "origin_logical_path": "npc/open/flows/asic/parameters/rv32im_ooo_4k_d10_line32.tcl",
    },
    {
        "role": "parameter_ownership_level1_overlay",
        "schema": "npc-riscv-open/ooo-d12-tracked-parameter-lock-v1",
        "path": "provenance/upstream/rv32im_ooo_4k/history/rv32im_ooo_4k_d12_level1.tcl",
        "sha256": "300d96918f2984df95b4f0885bb76b5e2cf3f3bd24142d551421c6cd407081b9",
        "size_bytes": 352,
        "origin_logical_path": "npc/open/flows/asic/parameters/rv32im_ooo_4k_d12_level1.tcl",
    },
    {
        "role": "parameter_ownership_level2_overlay",
        "schema": "npc-riscv-open/ooo-d12-tracked-parameter-lock-v1",
        "path": "provenance/upstream/rv32im_ooo_4k/history/rv32im_ooo_4k_d12_level2.tcl",
        "sha256": D12_PARAMETER_LOCK_SHA256,
        "size_bytes": 226,
        "origin_logical_path": "npc/open/flows/asic/parameters/rv32im_ooo_4k_d12_level2.tcl",
    },
    {
        "role": "effective_parameters",
        "schema": "npc-riscv-open/ooo-d12-effective-parameters-v1",
        "path": D12_EFFECTIVE_PARAMETERS_PATH,
        "sha256": D12_EFFECTIVE_PARAMETERS_FILE_SHA256,
        "size_bytes": D12_EFFECTIVE_PARAMETERS_FILE_SIZE,
        "effective_parameters_sha256": D12_EFFECTIVE_PARAMETERS_SHA256,
    },
    {
        "role": "tracked_structural_filelist",
        "schema": "npc-riscv-open/ooo-d12-tracked-filelist-v1",
        "path": "provenance/upstream/rv32im_ooo_4k/history/rv32im_ooo_4k_d12.f",
        "sha256": D12_FILELIST_SHA256,
        "size_bytes": 3388,
        "origin_logical_path": "npc/open/flows/asic/filelists/rv32im_ooo_4k_d12.f",
    },
    {
        "role": "tracked_macro_blackbox_verilog",
        "schema": "npc-riscv-open/ooo-d12-macro-blackbox-verilog-v1",
        "path": "provenance/upstream/rv32im_ooo_4k/history/d12_openram_blackboxes.sv",
        "sha256": D12_MACRO_VERILOG_SHA256,
        "size_bytes": 648,
        "origin_logical_path": "npc/tests/ooo_data_sector_cache_standalone/openram_blackboxes.sv",
        "modules": ["npc_dcache_data_1r1w_512x32_b8", "npc_ooo_data_word_1r1w_1024x32_b8"],
    },
]

EXPECTED_D12_STRUCTURAL_SOURCE_SET_IDENTITY = {
    "schema": "npc-riscv-open/ooo-d12-structural-source-set-identity-v1",
    "canonicalization": {
        "algorithm": "SHA256 over canonical records concatenated in tracked filelist order",
        "incdir_record": "literal +incdir+ followed by the historical-relative path and LF",
        "define_record": "the directive exactly as written followed by LF",
        "source_record": "historical-relative path, one NUL byte, lowercase SHA256 of file bytes, then LF",
        "path_mapping": {
            "public": "rtl/profiles/rv32im_ooo_4k",
            "historical": "vsrc_ooo",
        },
    },
    "yosys": {
        "status": "historical_verified_reconstructable",
        "filelist_role": "tracked_structural_filelist",
        "source_count": 61,
        "expected_source_set_sha256": D12_YOSYS_SOURCE_SET_SHA256,
        "public_reconstruction_complete": True,
    },
    "spyglass": {
        "status": "historical_partial_path_bound",
        "reported_source_set_sha256": D12_SPYGLASS_SOURCE_SET_SHA256,
        "public_reconstruction_complete": False,
        "reason": "the generated compatibility-stage relative path and derived filelist were not preserved in reachable Git, while that path is part of the historical digest",
    },
    "verilator": {
        "status": "historical_partial_log_only",
        "source_set_sha256": None,
        "log_sha256": "b76c0fb87c920af89c3c911686cbc6fc72e71dc0ef8ab920fccef1a5dbae1c8c",
        "public_reconstruction_complete": False,
        "reason": "the retained historical report binds a log digest but does not bind an independently reconstructable source-set identity",
    },
}

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
        "benchmark": "Historical CoreMark complete-image run from reset to terminal ebreak",
        "caveat": "Historical pre-loop-remediation endpoint; the baseline binary and configuration hashes are unavailable, so the documented settings are not hash-locked and this endpoint remains partial",
        "configuration": "source 7154e5a3d61fab18718a33f3fe2588891c1b291b; riscv32e-npc software family; rv32e_zicsr/ilp32e binary; hardware M_EXT=1; IF/LSU/memory=2/3/2; seed=1; difftest; 48,395,814 cycles / 7,824,961 retired instructions",
        "evidence": ["ooo_coremark_history_public"],
        "id": "ooo_historical_s9a_coremark_whole_cpi",
        "metric": "whole_program_CPI",
        "profile": "rv32im_ooo_4k",
        "public": True,
        "source_ref": S9A_SOURCE,
        "statement": "The historical S9A CoreMark complete-image run recorded whole-program CPI 6.184799387499",
        "status": "partial",
        "tool": "Historical RTL simulation with NEMU difftest and schema-v2 performance counters",
        "unit": "cycles_per_retired_instruction",
        "value": 6.184799387499,
    },
    "ooo_historical_p89_coremark_whole_cpi": {
        "benchmark": "Historical CoreMark complete-image run from reset to terminal ebreak",
        "caveat": "Verified only for historical P89 source 0e1730b7 in the pre-loop-remediation epoch; it is not current public RTL or loop-remediated performance",
        "configuration": "source 0e1730b71b7c4ad699e919fc9404189a5e8729d6; binary dc9a01a68109b14edf4f975ab2bb960d132b8b6d432e42ce43031fea72b17317; config 582d996093bbc50b2fb8d2c6332b0246336fc66d6804c38fa151729764764ae0; riscv32e-npc; IF/LSU/memory=2/3/2; seed=1; difftest; 8,590,215 cycles / 7,824,973 retired instructions",
        "evidence": ["ooo_coremark_history_public"],
        "id": "ooo_historical_p89_coremark_whole_cpi",
        "metric": "whole_program_CPI",
        "profile": "rv32im_ooo_4k",
        "public": True,
        "source_ref": P89_SOURCE,
        "statement": "The hash-locked historical P89 CoreMark complete-image run recorded whole-program CPI 1.097794842231",
        "status": "verified",
        "tool": "Historical RTL simulation with NEMU difftest, lifecycle and accounting checks",
        "unit": "cycles_per_retired_instruction",
        "value": 1.097794842231,
    },
    "ooo_historical_coremark_approx_speedup": {
        "benchmark": "Historical same-workload-family CoreMark complete-image comparison",
        "caveat": "Approximate only: the S9A binary and configuration hashes are unavailable and the endpoints differ by 12 retired instructions; this is a multi-stage architecture evolution, not a strict fixed-binary, fixed-config or fixed-source A/B",
        "configuration": "48,395,814 / 8,590,215 total cycles at equal clock; tracked documentation records IF/LSU/memory=2/3/2, seed=1 and the riscv32e-npc workload family for both endpoints, but the S9A config is not hash-locked",
        "evidence": ["ooo_coremark_history_public"],
        "id": "ooo_historical_coremark_approx_speedup",
        "metric": "same_frequency_whole_program_execution_speedup",
        "profile": "rv32im_ooo_4k",
        "public": True,
        "source_ref": "multiple_historical_refs",
        "statement": "The historical OoO architecture evolution reduces equal-clock CoreMark whole-program execution cycles by approximately 5.6338x",
        "status": "partial",
        "tool": "Derived from bounded historical CoreMark counters",
        "unit": "x",
        "value": 5.633830352325,
    },
    "ooo_historical_comb_loop_zero": {
        "benchmark": "D12 whole-core causal-ownership structural qualification",
        "caveat": "Historical D12 report only; the path-bound compatibility-stage source identity cannot be reconstructed from reachable Git, so this zero count remains partial and inherits no P89 performance or backend result",
        "configuration": "source a8f689cc00213859fb6893b31b65ef5cb3cbd7eb; reported source-set 8fa1ba69869e2a19b3bb5fb9ebc6393ce87f416af8f830eb4e4d578c5523ec62; exact generated stage path and derived filelist unavailable",
        "evidence": ["ooo_loop_remediation_public"],
        "id": "ooo_historical_comb_loop_zero",
        "metric": "whole_core_spyglass_comb_loop_count",
        "profile": "rv32im_ooo_4k",
        "public": True,
        "source_ref": D12_SOURCE,
        "statement": "The historical D12 typed registered-ownership source reports zero whole-core SpyGlass CombLoop findings",
        "status": "partial",
        "tool": "SpyGlass L2016.06 lint/lint_rtl",
        "unit": "count",
        "value": 0,
    },
    "ooo_historical_unoptflat_zero": {
        "benchmark": "D12 whole-core causal-ownership structural qualification",
        "caveat": "Historical D12 log only; no independently reconstructable source-set identity is bound to this zero count, so it remains partial and does not claim complete lint or physical timing closure",
        "configuration": "source a8f689cc00213859fb6893b31b65ef5cb3cbd7eb; retained log SHA256 b76c0fb87c920af89c3c911686cbc6fc72e71dc0ef8ab920fccef1a5dbae1c8c; source-set identity unavailable",
        "evidence": ["ooo_loop_remediation_public"],
        "id": "ooo_historical_unoptflat_zero",
        "metric": "whole_core_verilator_unoptflat_count",
        "profile": "rv32im_ooo_4k",
        "public": True,
        "source_ref": D12_SOURCE,
        "statement": "The historical D12 typed registered-ownership source reports zero Verilator UNOPTFLAT findings",
        "status": "partial",
        "tool": "Verilator 5.008 structural lint",
        "unit": "count",
        "value": 0,
    },
    "ooo_historical_pre_techmap_scc_zero": {
        "benchmark": "D12 whole-core causal-ownership structural qualification",
        "caveat": "Historical D12 source only; the source-set digest is publicly reconstructed from 61 ordered RTL sources, while the RTLIL graph result is not a mapped timing or area claim",
        "configuration": "source a8f689cc00213859fb6893b31b65ef5cb3cbd7eb; source-set e5782d80dde8aceef10516f5cdaeab3fda8f21b5e4df051de39939da5002da12",
        "evidence": ["ooo_loop_remediation_public"],
        "id": "ooo_historical_pre_techmap_scc_zero",
        "metric": "whole_core_yosys_pre_techmap_scc_count",
        "profile": "rv32im_ooo_4k",
        "public": True,
        "source_ref": D12_SOURCE,
        "statement": "The historical D12 source reports zero Yosys pre-techmap strongly connected components",
        "status": "verified",
        "tool": "Yosys 0.52+139 RTLIL graph check",
        "unit": "count",
        "value": 0,
    },
    "ooo_historical_post_techmap_scc_zero": {
        "benchmark": "D12 whole-core causal-ownership structural qualification",
        "caveat": "Historical D12 source only; the source-set digest is publicly reconstructed from 61 ordered RTL sources, while the techmapped graph result is not a Design Compiler, frequency, area or physical-implementation claim",
        "configuration": "source a8f689cc00213859fb6893b31b65ef5cb3cbd7eb; source-set e5782d80dde8aceef10516f5cdaeab3fda8f21b5e4df051de39939da5002da12",
        "evidence": ["ooo_loop_remediation_public"],
        "id": "ooo_historical_post_techmap_scc_zero",
        "metric": "whole_core_yosys_post_techmap_scc_count",
        "profile": "rv32im_ooo_4k",
        "public": True,
        "source_ref": D12_SOURCE,
        "statement": "The historical D12 source reports zero Yosys post-techmap strongly connected components",
        "status": "verified",
        "tool": "Yosys 0.52+139 techmapped graph check",
        "unit": "count",
        "value": 0,
    },
    "ooo_historical_precise_retirement_preserved": {
        "benchmark": "D12 seven-workload aggregate functional qualification across ideal and default profiles",
        "caveat": "Historical D12 source only; tracked evidence reports 14/14 aggregate passes, but per-point binary/config hashes, normalized trace digests and counters are unavailable, so precise retirement remains partial and transfers no performance or backend claim",
        "configuration": "source a8f689cc00213859fb6893b31b65ef5cb3cbd7eb; seven workloads x ideal/default = 14 reported aggregate points; common RV32IM/ilp32, seed=1 and difftest; per-point binary/config/trace/counter identity unavailable",
        "evidence": ["ooo_loop_remediation_public"],
        "id": "ooo_historical_precise_retirement_preserved",
        "metric": "aggregate_reported_precise_retirement",
        "profile": "rv32im_ooo_4k",
        "public": True,
        "source_ref": D12_SOURCE,
        "statement": "The historical D12 report records ordered architectural retirement across 14/14 aggregate workload/profile points; per-point identity is not independently reconstructable",
        "status": "partial",
        "tool": "Aggregate historical RTL simulation report with NEMU difftest, protocol, lifecycle and conservation checks",
        "unit": "boolean",
        "value": True,
    },
}
EXPECTED_NONCLAIMS = {
    "ooo_historical_coremark_strict_ab_not_claimed": {
        "conditions": "The S9A baseline binary and configuration hashes are unavailable and the S9A/P89 endpoints differ by 12 retired instructions; shared workload-family, latency, seed and difftest settings come from tracked documentation rather than an S9A hash lock",
        "evidence_id": "ooo_coremark_history_public",
        "evidence_status": "historical_partial_comparison",
        "id": "ooo_historical_coremark_strict_ab_not_claimed",
        "profile": "rv32im_ooo_4k",
        "public": True,
        "reason": "Source and counter provenance support an approximate architecture-lineage comparison, not a binary-identical, fixed-config or fixed-source experiment",
        "source_commit": "multiple_historical_refs",
        "statement": "The historical CoreMark 6.184799-to-1.097795 evolution is not claimed as a strict fixed-binary, fixed-config or fixed-source A/B",
        "status": "not_claimed",
    },
    "ooo_loop_remediation_performance_not_inherited": {
        "conditions": "The P89 CoreMark counters predate D12 causal-ownership remediation; D12 structural qualification intentionally carries no matching CoreMark counter claim",
        "evidence_id": "ooo_loop_remediation_public",
        "evidence_status": "historical_structural_only",
        "id": "ooo_loop_remediation_performance_not_inherited",
        "profile": "rv32im_ooo_4k",
        "public": True,
        "reason": "Performance-first and loop-remediated source epochs must remain separate until an exact matching benchmark is published",
        "source_commit": D12_SOURCE,
        "statement": "The P89 CoreMark CPI and approximate speedup are not claimed for the D12 loop-remediated source",
        "status": "not_claimed",
    },
    "ooo_loop_remediation_current_backend_not_claimed": {
        "conditions": "D12 verifies registered ownership and structural loop gates only; the canonical public Profile remains source lock 99fcc2be and no source-matched DC or physical implementation is published",
        "evidence_id": "ooo_loop_remediation_public",
        "evidence_status": "historical_structural_only",
        "id": "ooo_loop_remediation_current_backend_not_claimed",
        "profile": "rv32im_ooo_4k",
        "public": True,
        "reason": "A reconstructable historical source delta is not a current Profile promotion or implementation result",
        "source_commit": D12_SOURCE,
        "statement": "Current-source performance, Design Compiler frequency or area, P&R, STA, Fmax and signoff are not claimed from the D12 structural evidence",
        "status": "not_claimed",
    },
    "ooo_loop_remediation_point_identity_not_claimed": {
        "conditions": "Reachable Git evidence preserves the seven-workload ideal/default enumeration and aggregate 14/14 pass counts, but not per-point binary/config hashes, normalized trace digests, cycles or retired instructions",
        "evidence_id": "ooo_loop_remediation_public",
        "evidence_status": "historical_partial_aggregate_only",
        "id": "ooo_loop_remediation_point_identity_not_claimed",
        "profile": "rv32im_ooo_4k",
        "public": True,
        "reason": "Aggregate historical pass reporting cannot establish independently replayable identity for every workload/profile point",
        "source_commit": D12_SOURCE,
        "statement": "Per-point D12 binary/config/trace/counter identity and strict replayability are not claimed",
        "status": "not_claimed",
    },
    "ooo_loop_remediation_non_yosys_input_identity_not_claimed": {
        "conditions": "The historical SpyGlass digest includes a generated compatibility-stage relative path and derived filelist that were not preserved in reachable Git; the Verilator report retains a log digest but no source-set identity",
        "evidence_id": "ooo_loop_remediation_public",
        "evidence_status": "historical_partial_input_identity",
        "id": "ooo_loop_remediation_non_yosys_input_identity_not_claimed",
        "profile": "rv32im_ooo_4k",
        "public": True,
        "reason": "The published inputs can reconstruct the Yosys source-set exactly, but cannot reproduce the historical SpyGlass path-bound digest or bind the Verilator log to an exact source set",
        "source_commit": D12_SOURCE,
        "statement": "Exact reconstructable input identity is not claimed for the historical SpyGlass CombLoop or Verilator UNOPTFLAT reports",
        "status": "not_claimed",
    },
}

EXPECTED_COUNTERS = {
    "baseline": (48395814, 7824961, 6.184799387498544),
    "optimized": (8590215, 7824973, 1.0977948422314046),
}
EXPECTED_SPEEDUP = EXPECTED_COUNTERS["baseline"][0] / EXPECTED_COUNTERS["optimized"][0]
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
    "The historical report records 14/14 aggregate identity points, but per-point binary/config hashes and normalized trace digests were not preserved in reachable Git evidence; precise retirement therefore remains a partial aggregate report.",
    "The exact SpyGlass compatibility-stage path and derived filelist and any Verilator source-set binding were not preserved; their reported zero findings therefore remain partial.",
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
        "generated_at": "2026-08-10T00:00:00Z",
        "profile": "rv32im_ooo_4k",
        "epoch": "pre_combinational_loop_remediation",
        "benchmark": "AM CoreMark, whole-program reset-to-ebreak window",
        "comparison_status": "partial",
        "caveat": "This is a historical same-benchmark-family comparison from the pre-loop-remediation performance epoch, not a current loop-free RTL, DC, FPGA, backend or silicon result.",
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
            "whole_program_cpi", "binary_sha256", "config_sha256",
            "binary_identity_status", "configuration_identity_status", "status",
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
        require_exact(baseline, {
            "binary_identity_status": "unavailable",
            "configuration_identity_status": "documented_not_hash_locked",
            "status_reason": "The tracked historical baseline preserves source, documented profile settings and counters, but its binary and configuration hashes are unavailable.",
        }, "OoO CoreMark baseline identity boundary", errors)
        if baseline.get("status") != "partial":
            errors.append("OoO CoreMark baseline must remain partial")
    if isinstance(optimized, dict):
        require_exact(optimized, {
            "binary_sha256": P89_BINARY_SHA256,
            "config_sha256": P89_CONFIG_SHA256,
            "binary_identity_status": "sha256_locked",
            "configuration_identity_status": "sha256_locked",
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
        "metric": "same_frequency_whole_program_execution_speedup",
        "formula": "baseline.cycles / optimized.cycles",
        "display_value": "approximately 5.63x",
        "status": "partial",
        "status_reason": "The baseline binary and configuration hashes are unavailable and the two historical runs differ by 12 retired instructions; this is not a strict fixed-binary or fixed-config A/B.",
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
        "relationship": "The P89 source is an ancestor of the canonical public S9S source; the published numbers remain bound to the P89 historical checkpoint.",
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
        "generated_at": "2026-08-10T00:00:00Z",
        "profile": "rv32im_ooo_4k",
        "epoch": "d12_registered_causal_ownership",
        "status": "historical_partial",
        "claim_scope": "structural_mixed_maturity_and_functional_aggregate_partial_only",
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
        "macro_verilog_sha256", "input_bundle", "relationship_to_canonical",
        "reconstruction",
    }, "OoO loop-remediation source", errors)
    require_exact(source, {
        "base_commit": "a698a882",
        "implementation_commit": D12_SOURCE,
        "parameter_lock_role": "rv32im_ooo_4k_d12_level2",
        "parameter_lock_sha256": D12_PARAMETER_LOCK_SHA256,
        "effective_parameters_sha256": D12_EFFECTIVE_PARAMETERS_SHA256,
        "filelist_sha256": D12_FILELIST_SHA256,
        "macro_verilog_sha256": D12_MACRO_VERILOG_SHA256,
        "input_bundle": {
            "schema": "npc-riscv-open/ooo-d12-input-bundle-v1",
            "path": D12_INPUT_BUNDLE_PATH,
            "sha256": D12_INPUT_BUNDLE_SHA256,
            "size_bytes": D12_INPUT_BUNDLE_SIZE,
            "parameter_reconstruction_algorithm": "recursively expand the four same-directory tracked TCL locks, apply later-value override, then hash the sorted compact JSON parameter map",
            "filelist_source_prefix_map": {
                "historical": "vsrc_ooo",
                "public": "rtl/profiles/rv32im_ooo_4k",
            },
        },
        "relationship_to_canonical": "D12 is a bounded historical ownership-remediation snapshot reconstructed from the canonical public source content; it is not represented as an ancestor of the canonical S9S source.",
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
        "registered_boundaries", "precise_retirement_semantics",
        "forbidden_live_feedback_restored",
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
    if architecture.get("precise_retirement_semantics") != {
            "design_contract": "ordered_architectural_retirement",
            "evidence_maturity": "aggregate_reported_partial",
    }:
        errors.append("OoO precise-retirement design/evidence boundary drift")
    if architecture.get("forbidden_live_feedback_restored") is not False:
        errors.append("OoO forbidden live feedback boundary was weakened")

    structural = data.get("structural", {})
    if not isinstance(structural, dict) or structural.get("status") != "historical_mixed_maturity":
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
        "evidence_maturity", "identity_status", "source_commit",
        "reported_source_set_sha256", "input_manifest_sha256", "log_sha256",
        "report_sha256", "summary_sha256", "design_read_errors", "comb_loop",
        "waived_errors", "forbidden_project_controls",
    }, "OoO SpyGlass loop gate", errors)
    require_keys(verilator, {
        "evidence_maturity", "identity_status", "log_sha256", "unoptflat",
    }, "OoO Verilator loop gate", errors)
    require_keys(yosys, {
        "evidence_maturity", "identity_status", "source_commit", "source_set_sha256",
        "pre_techmap_scc", "post_techmap_scc", "pre_techmap_check_clean",
        "post_techmap_check_clean",
    }, "OoO Yosys SCC gate", errors)
    require_exact(spyglass, {
        "evidence_maturity": "partial",
        "identity_status": "historical_report_path_bound_not_reconstructable",
        "source_commit": D12_SOURCE,
        "reported_source_set_sha256": D12_SPYGLASS_SOURCE_SET_SHA256,
        "input_manifest_sha256": "6baa3e23b23324a7c12d58b30714b858b166672f69cce7bc4ac4398569856df0",
        "log_sha256": "3883bc81b2fea58d8012d3ebf7bf29f83e875385e1c2134f5beb6b47aea95c6b",
        "report_sha256": "83600454c7192d37b90301be3b87f5cfc2d45325f4cae65791bea93bea652b6f",
        "summary_sha256": "3e45a307a3b762503806a98779f5f334e1b2844e4bfc9a1180b278a2f254999f",
        "design_read_errors": 0,
        "comb_loop": 0,
        "waived_errors": 0,
        "forbidden_project_controls": [],
    }, "OoO SpyGlass loop gate", errors)
    require_exact(verilator, {
        "evidence_maturity": "partial",
        "identity_status": "historical_log_only_no_source_set_binding",
        "log_sha256": "b76c0fb87c920af89c3c911686cbc6fc72e71dc0ef8ab920fccef1a5dbae1c8c",
        "unoptflat": 0,
    }, "OoO Verilator loop gate", errors)
    require_exact(yosys, {
        "evidence_maturity": "verified",
        "identity_status": "publicly_reconstructable",
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
        "status", "identity_status", "identity_points_reported_passed",
        "identity_points_total", "protocol_lifecycle_conservation_errors",
        "precise_retirement_preserved", "claim_maturity",
        "per_point_binary_config_trace_identity_complete", "point_identity_artifact",
    }, "OoO loop-remediation functional gate", errors)
    require_exact(functional, {
        "status": "historical_partial",
        "identity_status": "aggregate_reported_only",
        "identity_points_reported_passed": 14,
        "identity_points_total": 14,
        "protocol_lifecycle_conservation_errors": 0,
        "precise_retirement_preserved": "reported_aggregate_only",
        "claim_maturity": "partial",
        "per_point_binary_config_trace_identity_complete": False,
        "point_identity_artifact": {
            "schema": "npc-riscv-open/ooo-d12-functional-identity-points-v1",
            "path": D12_FUNCTIONAL_POINTS_PATH,
            "sha256": D12_FUNCTIONAL_POINTS_SHA256,
            "size_bytes": D12_FUNCTIONAL_POINTS_SIZE,
        },
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


def check_bound_payload(root: Path, observed: object, expected: Mapping[str, object],
                        label: str, errors: MutableSequence[str]) -> Optional[Path]:
    if not isinstance(observed, dict):
        errors.append("{} binding is missing".format(label))
        return None
    require_keys(observed, expected, label, errors)
    require_exact(observed, expected, label, errors)
    relative = safe_repo_path(observed.get("path"), "{} path".format(label), errors)
    if relative is None:
        return None
    path = root / relative.as_posix()
    if not path.is_file():
        errors.append("{} payload is missing: {}".format(label, relative))
        return None
    if sha256(path) != observed.get("sha256"):
        errors.append("{} payload SHA256 drift".format(label))
    if path.stat().st_size != observed.get("size_bytes"):
        errors.append("{} payload size drift".format(label))
    return path


TCL_SOURCE_RE = re.compile(
    r"^\s*source\s+\[file join \[file dirname \[info script\]\] ([A-Za-z0-9_.-]+)\]\s*$"
)
TCL_PARAMETER_RE = re.compile(r"\b([A-Z][A-Z0-9_]*)=([^\s\\\]]+)")


def expand_d12_parameters(entry: Path, allowed: Set[Path], errors: MutableSequence[str],
                          stack: Optional[List[Path]] = None) -> Dict[str, str]:
    stack = [] if stack is None else stack
    resolved = entry.resolve()
    if resolved not in allowed:
        errors.append("D12 parameter source escapes the tracked input bundle: {}".format(entry.name))
        return {}
    if resolved in stack:
        errors.append("D12 parameter source recursion detected: {}".format(entry.name))
        return {}
    try:
        lines = entry.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        errors.append("cannot read D12 parameter source {}: {}".format(entry, error))
        return {}
    parameters = {}  # type: Dict[str, str]
    next_stack = stack + [resolved]
    for line in lines:
        source = TCL_SOURCE_RE.match(line)
        if source:
            nested = (entry.parent / source.group(1)).resolve()
            parameters.update(expand_d12_parameters(nested, allowed, errors, next_stack))
            continue
        for name, value in TCL_PARAMETER_RE.findall(line):
            parameters[name] = value
    return parameters


def check_d12_effective_parameters(root: Path, bundle: dict,
                                   errors: MutableSequence[str]) -> None:
    artifacts = bundle.get("artifacts", [])
    if not isinstance(artifacts, list):
        return
    records = {
        item.get("role"): item for item in artifacts
        if isinstance(item, dict) and isinstance(item.get("role"), str)
    }
    effective_record = records.get("effective_parameters", {})
    effective_path = root / D12_EFFECTIVE_PARAMETERS_PATH
    if not effective_path.is_file():
        return
    effective = load_object(effective_path)
    require_keys(effective, {
        "schema", "source_commit", "algorithm", "parameter_count", "parameters",
        "effective_parameters_sha256",
    }, "D12 effective parameter map", errors)
    require_exact(effective, {
        "schema": "npc-riscv-open/ooo-d12-effective-parameters-v1",
        "source_commit": D12_SOURCE,
        "algorithm": "recursive tracked TCL source expansion; later assignments override earlier values; SHA256 of canonical JSON parameters map with sorted keys and compact separators",
        "parameter_count": 64,
        "effective_parameters_sha256": D12_EFFECTIVE_PARAMETERS_SHA256,
    }, "D12 effective parameter map", errors)
    if effective_record.get("effective_parameters_sha256") != D12_EFFECTIVE_PARAMETERS_SHA256:
        errors.append("D12 input-bundle effective-parameter identity drift")

    tcl_roles = (
        "parameter_base", "parameter_cache_overlay",
        "parameter_ownership_level1_overlay", "parameter_ownership_level2_overlay",
    )
    allowed = {
        (root / records[role]["path"]).resolve()
        for role in tcl_roles if role in records and isinstance(records[role].get("path"), str)
    }
    entry = records.get("parameter_ownership_level2_overlay", {}).get("path")
    if not isinstance(entry, str):
        errors.append("D12 Level-2 parameter entry is missing")
        return
    reconstructed = expand_d12_parameters(root / entry, allowed, errors)
    if set(allowed) != {
        (root / records[role]["path"]).resolve() for role in tcl_roles
        if role in records and isinstance(records[role].get("path"), str)
    } or len(allowed) != 4:
        errors.append("D12 tracked parameter source set drift")
    if effective.get("parameters") != reconstructed:
        errors.append("D12 effective parameter reconstruction mismatch")
    if effective.get("parameter_count") != len(reconstructed):
        errors.append("D12 effective parameter count drift")
    canonical = json.dumps(reconstructed, sort_keys=True, separators=(",", ":")).encode("utf-8")
    if hashlib.sha256(canonical).hexdigest() != D12_EFFECTIVE_PARAMETERS_SHA256:
        errors.append("D12 effective parameter canonical SHA256 drift")


def recompute_d12_yosys_source_set(filelist_path: Path, source_manifest_path: Path,
                                   errors: MutableSequence[str]) -> tuple:
    manifest_entries = parse_source_manifest(source_manifest_path, errors)
    digest = hashlib.sha256()
    source_count = 0
    try:
        lines = filelist_path.read_text(encoding="utf-8").splitlines()
    except (OSError, UnicodeError) as error:
        errors.append("cannot read D12 structural filelist: {}".format(error))
        return "", 0
    for number, raw in enumerate(lines, 1):
        line = raw.strip()
        if not line or line.startswith("//"):
            continue
        if line.startswith("+incdir+") or line.startswith("+define+"):
            digest.update((line + "\n").encode("utf-8"))
            continue
        if not line.startswith("vsrc_ooo/") or ".." in PurePosixPath(line).parts:
            errors.append("D12 filelist contains unsupported entry at line {}".format(number))
            continue
        mapped = "rtl/profiles/rv32im_ooo_4k/" + line[len("vsrc_ooo/"):]
        role_sha256 = manifest_entries.get(mapped)
        if role_sha256 is None:
            errors.append("D12 filelist source is absent from reconstructed role set: {}".format(
                mapped))
            continue
        digest.update(line.encode("utf-8"))
        digest.update(b"\0")
        digest.update(role_sha256.encode("ascii"))
        digest.update(b"\n")
        source_count += 1
    if source_count != 61:
        errors.append("D12 Yosys source-set source count drift: {} != 61".format(source_count))
    return digest.hexdigest(), source_count


def check_d12_filelist_and_macro(root: Path, bundle: dict,
                                 errors: MutableSequence[str]) -> str:
    records = {
        item.get("role"): item for item in bundle.get("artifacts", [])
        if isinstance(item, dict) and isinstance(item.get("role"), str)
    }
    filelist_record = records.get("tracked_structural_filelist", {})
    filelist_path = root / str(filelist_record.get("path", ""))
    source_manifest_path = root / "provenance/upstream/rv32im_ooo_4k/history/d12_source_set.sha256"
    yosys_source_set_sha256 = ""
    if filelist_path.is_file() and source_manifest_path.is_file():
        yosys_source_set_sha256, _ = recompute_d12_yosys_source_set(
            filelist_path, source_manifest_path, errors)
        if yosys_source_set_sha256 != D12_YOSYS_SOURCE_SET_SHA256:
            errors.append("D12 Yosys source-set SHA256 reconstruction drift")

    macro_record = records.get("tracked_macro_blackbox_verilog", {})
    macro_path = root / str(macro_record.get("path", ""))
    if macro_path.is_file():
        modules = re.findall(r"(?m)^module\s+([A-Za-z_][A-Za-z0-9_]*)\s*\(",
                             macro_path.read_text(encoding="utf-8"))
        if modules != macro_record.get("modules"):
            errors.append("D12 macro-blackbox module identity drift")
    return yosys_source_set_sha256


def check_d12_functional_points(data: dict, errors: MutableSequence[str]) -> None:
    require_keys(data, {
        "schema", "source_commit", "evidence_commit", "status", "scope",
        "common_identity", "preserved_aggregate_artifact_identities", "points",
        "reported_aggregate_result", "per_point_missing_identity", "maturity_boundary",
    }, "D12 functional identity points", errors)
    require_exact(data, {
        "schema": "npc-riscv-open/ooo-d12-functional-identity-points-v1",
        "source_commit": D12_SOURCE,
        "evidence_commit": "c47c7dc2e9333de9fc798e56b7ed65d70c88dbd6",
        "status": "historical_partial",
        "scope": "seven workloads x ideal/default",
        "common_identity": {
            "arch": "riscv32-M-npc", "config_profile": "rv32im_4k_v1", "seed": 1,
            "deterministic_rtc": True, "difftest": True, "commit_trace": True,
            "candidate_causal_ownership_level": 2, "baseline_causal_ownership_level": 0,
            "parameter_lock_sha256": D12_PARAMETER_LOCK_SHA256,
            "effective_parameters_sha256": D12_EFFECTIVE_PARAMETERS_SHA256,
            "lq_response_causal_cut": 0, "stable_entry_iq": 1,
            "iq_split_payload_read": 1, "rob_indexed_service_level": 1,
            "data_sectored_cache": 1, "data_sector_line_bytes": 32,
            "data_sector_ways": 2, "data_cache_capacity_bytes": 4096,
        },
        "preserved_aggregate_artifact_identities": {
            "level0_manifest_sha256": "ef53d1c4213aec0d1e5bbe5b44f934eb907e772796ea388555ea513e292240eb",
            "level0_summary_sha256": "ab4d4f111ccf224564271765a45722a097116485d77e7fe882a40954af90c452",
            "level2_manifest_sha256": "db26e49a0bf6431b01cfce95f4023716f1335907db071531a0490cbacf212d57",
            "level2_summary_sha256": "0dee41c83912b4c67e85304ed563c753d9323f226f0d49f43c1afa1cb1543e4d",
            "analysis_json_sha256": "701ba843044cfb7a62ae9529838328be8592a67da6a450a6dbc01c2c4a763f14",
            "analysis_csv_sha256": "328215280b79f7a3fc82ce51e98bf07e84d2a2a1a41184b7654513b790b49cce",
        },
        "reported_aggregate_result": {
            "identity_points_reported_passed": 14, "identity_points_total": 14,
            "retired_instruction_counts_reported_match": True,
            "normalized_architectural_commit_traces_reported_match": True,
            "good_trap_difftest_watchdog_reported_pass": True,
            "protocol_lifecycle_conservation_errors_reported": 0,
        },
        "per_point_missing_identity": {
            "binary_sha256": "not preserved in reachable Git evidence",
            "config_sha256": "not preserved per point; only the shared manifest contract and aggregate manifest hashes remain",
            "baseline_normalized_trace_sha256": "not preserved in reachable Git evidence",
            "candidate_normalized_trace_sha256": "not preserved in reachable Git evidence",
            "cycles": "not preserved per point",
            "instructions": "not preserved per point",
        },
        "maturity_boundary": "The 14 points enumerate the historical aggregate report. Missing per-point binaries, config hashes, trace digests and counters prevent independently revalidating precise-retirement identity; this evidence is partial and is not a verified performance claim.",
    }, "D12 functional identity points", errors)
    points = data.get("points")
    workloads = ["coremark", "matrix-mul", "crc32", "quick-sort", "load-store",
                 "dhrystone", "microbench"]
    expected_points = []
    for profile, latency in (("ideal", [0, 0, 0]), ("default", [2, 3, 2])):
        for workload in workloads:
            expected_points.append({
                "workload": workload, "profile": profile,
                "ifetch_lsu_memory_latency": latency,
                "binary_sha256": None, "config_sha256": None,
                "baseline_normalized_trace_sha256": None,
                "candidate_normalized_trace_sha256": None,
                "identity_status": "aggregate_reported_only",
                "result": "reported_pass_not_independently_auditable",
            })
    if points != expected_points:
        errors.append("D12 per-point functional identity/missing-hash contract drift")
    performance_keys = FORBIDDEN_LOOP_METRIC_KEYS.union({"instructions", "weighted_cpi"})
    auditable = {key: value for key, value in data.items() if key != "per_point_missing_identity"}
    forbidden = sorted(performance_keys.intersection(nested_keys(auditable)))
    if forbidden:
        errors.append("D12 functional provenance contains forbidden performance keys: {}".format(
            ", ".join(forbidden)))


def check_d12_provenance(root: Path, loop: dict, lineage: dict,
                         errors: MutableSequence[str]) -> None:
    bundle_binding = loop.get("source", {}).get("input_bundle", {})
    expected_bundle_binding = {
        "schema": "npc-riscv-open/ooo-d12-input-bundle-v1",
        "path": D12_INPUT_BUNDLE_PATH,
        "sha256": D12_INPUT_BUNDLE_SHA256,
        "size_bytes": D12_INPUT_BUNDLE_SIZE,
        "parameter_reconstruction_algorithm": "recursively expand the four same-directory tracked TCL locks, apply later-value override, then hash the sorted compact JSON parameter map",
        "filelist_source_prefix_map": {
            "historical": "vsrc_ooo", "public": "rtl/profiles/rv32im_ooo_4k",
        },
    }
    bundle_path = check_bound_payload(root, bundle_binding, expected_bundle_binding,
                                      "D12 input bundle", errors)
    point_binding = loop.get("functional", {}).get("point_identity_artifact", {})
    expected_point_binding = {
        "schema": "npc-riscv-open/ooo-d12-functional-identity-points-v1",
        "path": D12_FUNCTIONAL_POINTS_PATH,
        "sha256": D12_FUNCTIONAL_POINTS_SHA256,
        "size_bytes": D12_FUNCTIONAL_POINTS_SIZE,
    }
    points_path = check_bound_payload(root, point_binding, expected_point_binding,
                                      "D12 functional identity points", errors)
    records = snapshot_records(lineage, errors)
    d12 = records.get("d12", {})
    expected_lineage_bundle = {
        "schema": "npc-riscv-open/ooo-d12-input-bundle-v1",
        "path": D12_INPUT_BUNDLE_PATH, "sha256": D12_INPUT_BUNDLE_SHA256,
        "size_bytes": D12_INPUT_BUNDLE_SIZE,
        "effective_parameters_sha256": D12_EFFECTIVE_PARAMETERS_SHA256,
        "tracked_filelist_sha256": D12_FILELIST_SHA256,
        "macro_verilog_sha256": D12_MACRO_VERILOG_SHA256,
    }
    expected_lineage_points = dict(expected_point_binding)
    expected_lineage_points.update({
        "status": "historical_partial", "identity_status": "aggregate_reported_only",
    })
    require_exact(d12, {
        "config_bundle": expected_lineage_bundle,
        "functional_identity": expected_lineage_points,
    }, "D12 source-lineage provenance", errors)
    if bundle_path is not None:
        bundle = load_object(bundle_path)
        require_keys(bundle, {
            "schema", "source_commit", "evidence_commit", "top", "status", "artifacts",
            "parameter_reconstruction", "source_reconstruction",
            "structural_source_set_identity", "related_functional_identity", "nonclaims",
        }, "D12 input bundle", errors)
        require_exact(bundle, {
            "schema": "npc-riscv-open/ooo-d12-input-bundle-v1",
            "source_commit": D12_SOURCE,
            "evidence_commit": "c47c7dc2e9333de9fc798e56b7ed65d70c88dbd6",
            "top": "ooo_pipeline_synth_core_top",
            "status": "historical_reconstructable_input_identity",
            "artifacts": EXPECTED_D12_ARTIFACTS,
            "parameter_reconstruction": {
                "entry": "rv32im_ooo_4k_d12_level2.tcl",
                "algorithm": "recursively expand same-directory tracked TCL source directives, parse NAME=VALUE tokens, and let later assignments override earlier values",
                "canonicalization": "JSON object of the final parameter map, sorted keys, compact separators",
                "expected_parameter_count": 64,
                "expected_effective_parameters_sha256": D12_EFFECTIVE_PARAMETERS_SHA256,
            },
            "source_reconstruction": {
                "source_patch": "provenance/upstream/rv32im_ooo_4k/history/d12_from_public_s9s.patch",
                "source_set_manifest": "provenance/upstream/rv32im_ooo_4k/history/d12_source_set.sha256",
                "historical_source_prefix": "vsrc_ooo",
                "public_source_prefix": "rtl/profiles/rv32im_ooo_4k",
                "mapping_algorithm": "replace the leading vsrc_ooo path component in source and +incdir+ entries with rtl/profiles/rv32im_ooo_4k after applying the bounded D12 patch",
                "unsupported_directives": "fail closed",
                "macro_role": "blackbox interface only; no Liberty, LEF, GDS, PDK or commercial-library payload is included",
            },
            "structural_source_set_identity": EXPECTED_D12_STRUCTURAL_SOURCE_SET_IDENTITY,
            "related_functional_identity": dict(expected_point_binding, status="historical_partial"),
            "nonclaims": [
                "This bundle does not include raw logs, generated libraries, PDK data or host paths.",
                "The macro artifact is the exact tracked blackbox interface used by the structural gates, not a characterized memory view.",
                "This bundle does not establish performance, DC, frequency, area, P&R or signoff results.",
                "Only the Yosys source-set identity is reconstructable from the published inputs; SpyGlass and Verilator input identity remains partial.",
            ],
        }, "D12 input bundle", errors)
        for artifact in EXPECTED_D12_ARTIFACTS:
            check_bound_payload(root, artifact, artifact,
                                "D12 artifact {}".format(artifact["role"]), errors)
        forbidden_bundle = sorted(FORBIDDEN_LOOP_METRIC_KEYS.intersection(nested_keys(bundle)))
        if forbidden_bundle:
            errors.append("D12 input provenance contains forbidden performance keys: {}".format(
                ", ".join(forbidden_bundle)))
        check_d12_effective_parameters(root, bundle, errors)
        recomputed_yosys = check_d12_filelist_and_macro(root, bundle, errors)
        observed_yosys = loop.get("structural", {}).get("yosys", {}).get("source_set_sha256")
        if recomputed_yosys != observed_yosys:
            errors.append("D12 recomputed/loop-evidence Yosys source-set identity drift")
        source_identity = bundle.get("structural_source_set_identity", {})
        if source_identity != EXPECTED_D12_STRUCTURAL_SOURCE_SET_IDENTITY:
            errors.append("D12 structural source-set identity schema drift")
        if recomputed_yosys != source_identity.get("yosys", {}).get(
                "expected_source_set_sha256"):
            errors.append("D12 recomputed/bundle Yosys source-set identity drift")
        if loop.get("structural", {}).get("spyglass", {}).get(
                "reported_source_set_sha256") != source_identity.get("spyglass", {}).get(
                    "reported_source_set_sha256"):
            errors.append("D12 bundle/loop SpyGlass reported identity drift")
        if loop.get("structural", {}).get("verilator", {}).get(
                "log_sha256") != source_identity.get("verilator", {}).get("log_sha256"):
            errors.append("D12 bundle/loop Verilator log identity drift")
    if points_path is not None:
        check_d12_functional_points(load_object(points_path), errors)


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
    require_exact(data, {
        "generated_at": "2026-08-10T00:00:00Z",
        "profile": "rv32im_ooo_4k",
        "caveat": "The patches reconstruct bounded historical source snapshots from the canonical public role set; they do not change the canonical production RTL.",
    }, "OoO source lineage", errors)
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
    expected_relationships = {
        "p89": "historical ancestor reconstructed by reversing later canonical changes",
        "d12": "divergent historical ownership-remediation snapshot reconstructed from canonical public content",
    }
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
        expected_fields = {
            "id", "source_ref", "base_source_ref", "relationship", "patch",
            "source_set_manifest", "file_count", "roles", "changed", "added", "removed",
        }
        if snapshot_id == "d12":
            expected_fields.update({"config_bundle", "functional_identity"})
        require_keys(record, expected_fields,
                     "OoO {} source snapshot".format(snapshot_id.upper()), errors)
        require_exact(record, {
            "source_ref": expected_sources[snapshot_id],
            "base_source_ref": CANONICAL_SOURCE,
            "relationship": expected_relationships[snapshot_id],
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


def record_links_evidence(record: Mapping[str, object], evidence_id: str) -> bool:
    value = record.get("evidence")
    if isinstance(value, list):
        return evidence_id in value
    return value == evidence_id


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
        require_keys(claim, expected, "OoO history claim {}".format(claim_id), errors)
        require_exact(claim, {
            field: value for field, value in expected.items() if field != "value"
        }, "OoO history claim {}".format(claim_id), errors)
        if not same_claim_value(claim.get("value"), expected["value"]):
            errors.append("OoO history claim value drift: {}".format(claim_id))

    for nonclaim_id, expected in EXPECTED_NONCLAIMS.items():
        nonclaim = nonclaims.get(nonclaim_id)
        if nonclaim is None:
            errors.append("missing OoO history nonclaim {}".format(nonclaim_id))
            continue
        require_keys(nonclaim, expected, "OoO history nonclaim {}".format(nonclaim_id), errors)
        require_exact(nonclaim, expected, "OoO history nonclaim {}".format(nonclaim_id), errors)

    expected_evidence = {
        "ooo_coremark_history_public": {
            "claims": COREMARK_CLAIMS,
            "nonclaims": ["ooo_historical_coremark_strict_ab_not_claimed"],
            "path": COREMARK_PATH,
            "source_ref": "multiple_historical_refs",
            "status": "partial",
            "caveat": "Historical pre-loop-remediation CoreMark lineage only; the baseline binary and configuration hashes are unavailable and the endpoints differ by 12 retired instructions, so the approximately 5.63x equal-clock cycle comparison remains partial and is not inherited by current, loop-free, DC, FPGA or ASIC results",
            "configuration": "Historical S9A and P89 CoreMark whole-program endpoints; rv32e_zicsr/ilp32e benchmark family on RV32IM hardware with M extension; tracked documentation records IF/LSU/memory 2/3/2, seed 1 and difftest, while only P89 retains binary/config SHA256",
            "generated_time": "2026-08-10T00:00:00Z",
            "snapshot_id": "main-ooo-history-v1",
            "tool": "Historical RTL simulation, profile-matched NEMU difftest and bounded counter summaries",
            "type": "bounded_historical_coremark_lineage_summary",
        },
        "ooo_loop_remediation_public": {
            "claims": LOOP_CLAIMS,
            "nonclaims": [
                "ooo_loop_remediation_performance_not_inherited",
                "ooo_loop_remediation_current_backend_not_claimed",
                "ooo_loop_remediation_point_identity_not_claimed",
                "ooo_loop_remediation_non_yosys_input_identity_not_claimed",
            ],
            "path": LOOP_PATH,
            "source_ref": D12_SOURCE,
            "status": "partial",
            "caveat": "Historical D12 Yosys SCC evidence has a publicly reconstructable source-set identity; SpyGlass CombLoop, Verilator UNOPTFLAT and precise retirement remain partial because their complete input or per-point identity is unavailable; no P89 performance, current-source or backend result is inherited",
            "configuration": "D12 typed registered ownership across Issue/WB/Commit/LSU; published parameter locks, effective parameters, filelist and macro blackbox identity; Yosys source-set reconstructed from 61 ordered RTL sources; SpyGlass/Verilator reports retained with partial input identity; aggregate 14/14 functional reporting",
            "generated_time": "2026-08-10T00:00:00Z",
            "snapshot_id": "main-ooo-history-v1",
            "tool": "Reconstructable Yosys SCC checks, bounded historical SpyGlass/Verilator reports and aggregate RTL functional reporting",
            "type": "bounded_historical_structural_remediation_summary",
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
        semantic = {
            "caveat": expected["caveat"],
            "claims": expected["claims"],
            "nonclaims": expected["nonclaims"],
            "configuration": expected["configuration"],
            "generated_time": expected["generated_time"],
            "id": evidence_id,
            "snapshot_id": expected["snapshot_id"],
            "tool": expected["tool"],
            "type": expected["type"],
            "project_id": "npc-riscv-open",
            "public": True,
            "path": manifest_path,
            "source_ref": expected["source_ref"],
            "status": expected["status"],
        }
        require_keys(item, set(semantic).union({"sha256", "size_bytes"}),
                     "OoO history evidence manifest {}".format(evidence_id), errors)
        require_exact(item, semantic,
                      "OoO history evidence manifest {}".format(evidence_id), errors)
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
        incoming_claims = {
            claim_id for claim_id, claim in claims.items()
            if record_links_evidence(claim, evidence_id)
        }
        if incoming_claims != set(expected["claims"]):
            errors.append("OoO history incoming claim/evidence set drift: {}".format(evidence_id))
        linked_nonclaims = {
            item_id for item_id, nonclaim in nonclaims.items()
            if nonclaim.get("evidence_id") == evidence_id
        }
        if linked_nonclaims != set(expected["nonclaims"]):
            errors.append("OoO history incoming nonclaim/evidence set drift: {}".format(evidence_id))

        for claim_id in expected["claims"]:
            incoming_manifests = {
                item_id for item_id, manifest in evidence.items()
                if isinstance(manifest.get("claims"), list)
                and claim_id in manifest.get("claims", [])
            }
            if incoming_manifests != {evidence_id}:
                errors.append("OoO history claim/manifest reverse-link set drift: {}".format(
                    claim_id))
        for nonclaim_id in expected["nonclaims"]:
            incoming_manifests = {
                item_id for item_id, manifest in evidence.items()
                if isinstance(manifest.get("nonclaims"), list)
                and nonclaim_id in manifest.get("nonclaims", [])
            }
            if incoming_manifests != {evidence_id}:
                errors.append("OoO history nonclaim/manifest reverse-link set drift: {}".format(
                    nonclaim_id))


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
    check_d12_provenance(root, loop, lineage, errors)
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
    print("OOO_HISTORY_CHECK_PASS coremark_snapshots=2 source_reconstructions=2 loop_gates=4 aggregate_report=14/14 maturity=partial")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
