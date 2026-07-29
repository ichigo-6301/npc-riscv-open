#!/usr/bin/env python3
"""Fail-closed checks for bounded public ASIC evidence and showcase assets."""

from __future__ import annotations

import argparse
from collections.abc import Mapping
import hashlib
import json
from pathlib import Path
import re
import sys
from types import MappingProxyType


IMPLEMENTATION_PATH = Path("evidence/implementation/nangate45_fixed_points.json")
SHOWCASE_PATH = Path("evidence/data/showcase.json")
ASSET_PROVENANCE_PATH = Path("evidence/data/showcase_assets.json")
SOURCE_MANIFEST_PATHS = (
    Path("provenance/source_allowlist.json"),
    Path("export/source_allowlist.json"),
)
IMPLEMENTATION_EVIDENCE_ID = "single_linux_nangate45_backend_public"
SHOWCASE_EVIDENCE_IDS = {
    "npc_showcase_data_public",
    "npc_showcase_asset_provenance_public",
    "npc_profile_portfolio_asset",
    "npc_nangate45_closure_asset",
}
SHA256_RE = re.compile(r"[0-9a-f]{64}\Z")
PRIVATE_UNIX_ROOTS = ("/" + "home" + "/", "/" + "mnt" + "/")
PRIVATE_PATH_RE = re.compile(
    r"(?:{}|[A-Za-z]:[\\/])".format(
        "|".join(re.escape(root) for root in PRIVATE_UNIX_ROOTS)
    )
)
PRIVATE_ADDRESS_RE = re.compile(r"(?:\d{1,3}\.){3}\d{1,3}")
CLAIM_MARKER_RE = re.compile(
    r"<!--\s*claim:([a-z0-9_]+)\s+maturity:([a-z_]+)\s*-->"
)
EVIDENCE_MARKER_RE = re.compile(r"<!--\s*evidence:([a-z0-9_]+)\s*-->")


EXPECTED_POINTS = {
    "rv32im_single_perf.registers": {
        "profile": "rv32im_single_perf",
        "source_commit": "f76de57479b798aca7468f999c386bb4cb5fce02",
        "memory_mode": "register_expanded",
        "macro_count": 0,
        "dc_mhz": 540,
        "postroute_mhz": 425,
        "standard_cell_area_mm2": 0.679497,
        "core_area_mm2": 2.614530,
        "setup_wns_ns": 0.025646,
        "hold_wns_ns": 0.063219,
        "analysis_coverage_untested": {
            "total": 19,
            "setup": 2,
            "hold": 2,
            "recovery": 5,
            "removal": 5,
            "min_pulse_width": 5,
        },
        "claims": (
            "single_registers_nangate45_dc_frequency",
            "single_registers_nangate45_postroute_frequency",
            "single_registers_nangate45_standard_cell_area",
            "single_registers_nangate45_core_area",
        ),
    },
    "rv32im_single_perf.sram": {
        "profile": "rv32im_single_perf",
        "source_commit": "f76de57479b798aca7468f999c386bb4cb5fce02",
        "memory_mode": "sram_macro",
        "macro_count": 4,
        "dc_mhz": 600,
        "postroute_mhz": 475,
        "standard_cell_area_mm2": 0.149292,
        "core_area_mm2": 0.858801,
        "setup_wns_ns": 0.013556,
        "hold_wns_ns": 0.047904,
        "analysis_coverage_untested": {
            "total": 0,
            "setup": 0,
            "hold": 0,
            "recovery": 0,
            "removal": 0,
            "min_pulse_width": 0,
        },
        "claims": (
            "single_sram_nangate45_dc_frequency",
            "single_sram_nangate45_postroute_frequency",
            "single_sram_nangate45_standard_cell_area",
            "single_sram_nangate45_core_area",
        ),
    },
    "rv32ima_sv32_linux.registers": {
        "profile": "rv32ima_sv32_linux",
        "source_commit": "0fc3de40c4e0b231c65945c9dc1711f084688c04",
        "memory_mode": "register_expanded",
        "macro_count": 0,
        "dc_mhz": 280,
        "postroute_mhz": 200,
        "standard_cell_area_mm2": 0.717964,
        "core_area_mm2": 2.825040,
        "setup_wns_ns": 0.387809,
        "hold_wns_ns": 0.032648,
        "analysis_coverage_untested": {
            "total": 90,
            "setup": 6,
            "hold": 6,
            "recovery": 26,
            "removal": 26,
            "min_pulse_width": 26,
        },
        "claims": (
            "linux_registers_nangate45_dc_frequency",
            "linux_registers_nangate45_postroute_frequency",
            "linux_registers_nangate45_standard_cell_area",
            "linux_registers_nangate45_core_area",
        ),
    },
    "rv32ima_sv32_linux.sram": {
        "profile": "rv32ima_sv32_linux",
        "source_commit": "0fc3de40c4e0b231c65945c9dc1711f084688c04",
        "memory_mode": "sram_macro",
        "macro_count": 4,
        "dc_mhz": 300,
        "postroute_mhz": 200,
        "standard_cell_area_mm2": 0.198085,
        "core_area_mm2": 1.049500,
        "setup_wns_ns": 0.720415,
        "hold_wns_ns": 0.039090,
        "analysis_coverage_untested": {
            "total": 2,
            "setup": 1,
            "hold": 1,
            "recovery": 0,
            "removal": 0,
            "min_pulse_width": 0,
        },
        "claims": (
            "linux_sram_nangate45_dc_frequency",
            "linux_sram_nangate45_postroute_frequency",
            "linux_sram_nangate45_standard_cell_area",
            "linux_sram_nangate45_core_area",
        ),
    },
}


EXPECTED_POINT_HASHES = MappingProxyType(
    {
        "rv32im_single_perf.registers": MappingProxyType(
            {
                "constraint_hashes": MappingProxyType(
                    {
                        "source_sdc_sha256": "66d4d4242384d8dc5f0f031e7540eae35855f0acf6c099eea97f3230ec431078",
                        "dc_mapped_sdc_sha256": "a461906af48ac83562b1b1d9e29016d5beb7bd1911fabb80a07fe467d1e48ede",
                        "pnr_input_sdc_sha256": "fcedb96f9ab1e498c3d1b225ba165a8084bd5085f75284c61756e36a0bf5a862",
                        "routed_sdc_pre_sanitize_sha256": "e2ef98ad0fab75bb61b4e17000401f7f8149812eec8eb3018994dd4ce2a9d47c",
                        "routed_sdc_sha256": "db199ca4f8a2fb3df7708e121ecad6913d33139bc4c82ebfd13cf5b782885834",
                    }
                ),
                "report_hashes": MappingProxyType(
                    {
                        "dc_input_manifest": "e443800748c2e2061a20e0da1248650b1763714a3363e8253866f46cd3685692",
                        "dc_log": "ccb6ca74a39852e457b821612fa09d56654049b82ec6f368eec908ed32734058",
                        "dc_timing_loops": "e31ee603d997cea26f5d8c1d742707546c0aac46493213aebfd376bfa877e44a",
                        "pnr_input_manifest": "1ef7b611792927357a5112e61b20c1e9d8acd4e44356c844a175cb1261a8ec8d",
                        "pnr_log": "2ee6893e6cd5ce6a820425b40329d3725f4add64859cb84649ddaadaaaea991c",
                        "pnr_recovery_manifest": "b31aa12351269cd4a0f236722f89ff8555ba401a212c4f36248b704c41ca3c0f",
                        "primetime_input_manifest": "3772681302e4eeb3283108ca823a3c78d9d6871a26e6ef8d6f709e6a70957381",
                        "primetime_log": "672d0bf9ac7c0a9d31c4bc8cce8a690fabdc9cf654e92712f9a978c0a58889a9",
                        "primetime_analysis_coverage": "ee76c317d098a0d84c6a80a65cdfbbae9a8678db5bb4788010f461186daefa94",
                    }
                ),
            }
        ),
        "rv32im_single_perf.sram": MappingProxyType(
            {
                "constraint_hashes": MappingProxyType(
                    {
                        "source_sdc_sha256": "66d4d4242384d8dc5f0f031e7540eae35855f0acf6c099eea97f3230ec431078",
                        "dc_mapped_sdc_sha256": "0edf409f22a67dd6e93b14e3592241e7f55b27dcf9d24c20ae9eaf106c800de5",
                        "pnr_input_sdc_sha256": "02b396a583942b3abda95edfabf85b16475fd4f636024ac8ea9fbb8ab1f13cf9",
                        "routed_sdc_sha256": "e8a140d44dc8d5e8d6944bc3258e55a9d05d2d5dd394abef08e82ae36d90c0b2",
                    }
                ),
                "report_hashes": MappingProxyType(
                    {
                        "dc_input_manifest": "e32364c87d81bbfd4facf804a4f8ebfbab536fd62668bb4f544383d5c6a9aa7e",
                        "dc_run_contract": "16367b34a55a8c9c49d1bc85f076014d5881f578352b0241231286c40f17e074",
                        "pnr_input_manifest": "09bc5763a708284253342676803e3997a98a77fda57f18fa0698a8f6d16906f2",
                        "pnr_log": "750d71da42fe9a068658738b2c4828fa0c5334e8a2ff2f22d3683d9dbe7c1fb6",
                        "pnr_same_run_manifest": "2e1c81bf08270f3f2ba2e249158a17f5d8d03fe27cc6c60984229cdd55321e9f",
                        "primetime_input_manifest": "43c337b5717cf32828f33d013999651391c7d0d81632c3b7325c2bb15f9f2c5a",
                        "primetime_log": "1b69263dd44b12290b28adcfcc7a20277bab914523166fd164c9760ec8d497cc",
                        "primetime_analysis_coverage": "07e698fddf81942e4f29b4e9ca544583eae9e16f572138302017541f8a9b06f6",
                    }
                ),
            }
        ),
        "rv32ima_sv32_linux.registers": MappingProxyType(
            {
                "constraint_hashes": MappingProxyType(
                    {
                        "source_sdc_sha256": "66d4d4242384d8dc5f0f031e7540eae35855f0acf6c099eea97f3230ec431078",
                        "dc_mapped_sdc_sha256": "5695c6ca6411b66c628d68269a471ea478b6a309b1be18e30e759b7163875d0e",
                        "pnr_input_sdc_sha256": "3622e2403484bdceacbdd1ede3a9c47f05d7915cc282da67f4d72d41ca692eef",
                        "routed_sdc_sha256": "d1f0677e04720688cd5a71c9b479ec96fc4fd31ef916161abe59fa1afbc21463",
                    }
                ),
                "report_hashes": MappingProxyType(
                    {
                        "dc_input_manifest": "e7350db01f7a82dcc8c378d31db22ac990d6c772587a0f923dbc46a5709d012f",
                        "dc_run_contract": "f8af3c066a2bfbd75785d968da4cbba7ee55c2425b645ab864a855d799e5a7ff",
                        "pnr_input_manifest": "db136cb5ac07b5b30a63e0e2e48bbccf4ce0d878fe48fc2f1e7f8929a4ff1340",
                        "pnr_log": "7e1aee965082c5ba75eda5de784347dbc44c6600d47c33f37e96e8ffe152fb92",
                        "pnr_same_run_manifest": "14fd157ac38576f341e7c8bcaefefaa5f050538b80f139bade2c6e769a9342bc",
                        "primetime_input_manifest": "eb62fffddb96245ce515a833d7a37085434df85f0180d8079ab9da83d688aa10",
                        "primetime_log": "dea705e89995e5a18ac2da7eadf7c6d68726885696af978a783fcf8a09d3c260",
                        "primetime_analysis_coverage": "63bbaa8914c552e400cc5559898d00a9a0b4fe6a9a89a2ce5a0f31f9c613fd33",
                    }
                ),
            }
        ),
        "rv32ima_sv32_linux.sram": MappingProxyType(
            {
                "constraint_hashes": MappingProxyType(
                    {
                        "source_sdc_sha256": "66d4d4242384d8dc5f0f031e7540eae35855f0acf6c099eea97f3230ec431078",
                        "dc_mapped_sdc_sha256": "9ed1518086d2df5a02ec4230a2fb13b49dcc2269379ff4a9aa93f2e3bccddd38",
                        "pnr_input_sdc_sha256": "f760c672479abc3359e941e6aac4e346015d756f0c8e6202046dc5387eef585f",
                        "routed_sdc_sha256": "d1f0677e04720688cd5a71c9b479ec96fc4fd31ef916161abe59fa1afbc21463",
                    }
                ),
                "report_hashes": MappingProxyType(
                    {
                        "dc_input_manifest": "dd2b83e792d32b86ef266ef4273277dd99d40a15af064f7c65df09addc184b5f",
                        "dc_run_contract": "2c53b5213531a078da11a2cfbe8e1a38c1efe4701cc7a87a6309a25c79ed03ec",
                        "pnr_input_manifest": "867c60f9eb7c48b15e0bb9bbeca06afa12f372798d79bf0fc1031b6ce2e4deba",
                        "pnr_log": "c9cd5a17251e1bc19cf6cfd7d8ec256fab529aa48758f46a257b2130e040cb5f",
                        "pnr_same_run_manifest": "609b72f7dd126f8ddad5636e7a46808ae7f0503d921a23355269968dac1b26ed",
                        "primetime_input_manifest": "f242142b7c95428d5db45e3241245045093737e93e8e8ab23c2e767d826f894c",
                        "primetime_log": "fb91caf2b6444f892f1b098d45bd6bef94ed19b0042f970cb49e96c76413773b",
                        "primetime_analysis_coverage": "4e797c43315a33a562583b0aeb1a75f40b910269d5eb8795257d1994a9d9f3d3",
                    }
                ),
            }
        ),
    }
)


# These canonical section digests bind the public record to the reviewed D11
# audit without publishing raw reports or private paths. Field-level checks
# below retain useful diagnostics; these digests reject otherwise well-formed
# substitutions of source/config, run, artifact, tool, or library identity.
EXPECTED_GLOBAL_SECTION_SHA256 = MappingProxyType(
    {
        "audit_source": "dc78f1137c945bf8fb85e32fe2eed11abe6717f9a50ee24a1c8ad7af4f05e2d0",
        "platform_identity": "502cabbd8d4729d4a9cf95ba087fb1643aaaa62004ad66a47bdd388a2fd192b4",
        "sram_identity": "c6d06c2752352e10b1dfe48492fbd4cbc7fc6fa30cbe5c0b657a6765a6f93013",
    }
)
EXPECTED_POINT_SECTION_SHA256 = MappingProxyType(
    {
        "rv32im_single_perf.registers": MappingProxyType(
            {
                "identity": "78983364ddaf396c069e96d93df1e0cd6115a9a426150e2a01edc0912803ec2d",
                "run_identity": "2e11f9d2b01fa54f407267e8679d337dde09ef9ae44d0b6297670f5195e50210",
                "role_hashes": "b205b30a8d3f28342c73791207a9ec06b041704b258031d4ac03de009433cbe2",
            }
        ),
        "rv32im_single_perf.sram": MappingProxyType(
            {
                "identity": "c93feedcc2dec4b9c91e95d85abf7d6603c9676fc7d1c1f10e34073c6e7f3736",
                "run_identity": "a994d606dd66ad71cdfd2b75516ccc69e44b4a09a59e6b953a9dacc8ec8a0b62",
                "role_hashes": "777b783cf6d45f7f2835b7be208eaff91e5633a424501d1133af951428479370",
            }
        ),
        "rv32ima_sv32_linux.registers": MappingProxyType(
            {
                "identity": "f095577aa83aee54e419ed6c6eae97d27c78eff265c73efc95b568893bf1f2a7",
                "run_identity": "3c672b08daa3e762776c37fef4486ddd009ea622d6c5505cb9927e42f3f3c03c",
                "role_hashes": "7eaf4de05dc5d1d298233c3db6372b3c3ded5bbf044001f749fd8e3031c9b6e6",
            }
        ),
        "rv32ima_sv32_linux.sram": MappingProxyType(
            {
                "identity": "e03e61bc79abcade19bac59f59b2d5edf186a75f8d292c0a5667925a4e0a7d99",
                "run_identity": "9b5a1025d97a48a4a5d05092e64807e19e05a0385fe998a7bb52fd3e76f8c49c",
                "role_hashes": "76fec128c633b67d859ed74af01ec04d90ccf446aaeccf1dc179559201fe43e3",
            }
        ),
    }
)


def claim_contracts() -> dict[str, dict]:
    contracts: dict[str, dict] = {}
    fields = (
        ("dc_frequency", "dc_fixed_frequency", "dc_mhz", "MHz"),
        ("postroute_frequency", "postroute_fixed_frequency", "postroute_mhz", "MHz"),
        ("standard_cell_area", "pnr_standard_cell_area", "standard_cell_area_mm2", "mm2"),
        ("core_area", "pnr_core_area", "core_area_mm2", "mm2"),
    )
    for point_id, expected in EXPECTED_POINTS.items():
        for claim_id, (_, metric, field, unit) in zip(expected["claims"], fields):
            contracts[claim_id] = {
                "point_id": point_id,
                "profile": expected["profile"],
                "source_ref": expected["source_commit"],
                "metric": metric,
                "value": expected[field],
                "unit": unit,
            }
    return contracts


EXPECTED_CLAIMS = claim_contracts()
EXPECTED_README_CLAIMS = set(EXPECTED_CLAIMS) | {
    "single_public_coremark_timed_cpi",
    "single_public_coremark_per_mhz",
    "single_public_coremark_whole_cpi",
}


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def canonical_record_sha256(value: object) -> str:
    payload = json.dumps(
        value, sort_keys=True, separators=(",", ":"), ensure_ascii=True
    ).encode("ascii")
    return hashlib.sha256(payload).hexdigest()


def require_section_identity(value: object, expected_sha256: str,
                             context: str, errors: list[str]) -> None:
    if not isinstance(value, dict):
        errors.append("{} is not an identity mapping".format(context))
        return
    if canonical_record_sha256(value) != expected_sha256:
        errors.append("{} identity digest drift".format(context))


def load_object(path: Path, errors: list[str]) -> dict:
    try:
        text = path.read_text(encoding="utf-8")
    except OSError as error:
        errors.append("invalid dependency-free JSON record {}: {}".format(path, error))
        return {}
    try:
        value = json.loads(text)
    except json.JSONDecodeError as json_error:
        try:
            import yaml  # Private overlay fallback; public exports are JSON.
            value = yaml.safe_load(text)
        except (ImportError, ValueError, TypeError) as yaml_error:
            errors.append(
                "invalid JSON/YAML record {}: {}; {}".format(
                    path, json_error, yaml_error
                )
            )
            return {}
    if not isinstance(value, dict):
        errors.append("{} top level is not an object".format(path))
        return {}
    return value


def require_hashes(mapping: object, context: str, errors: list[str]) -> None:
    if not isinstance(mapping, dict) or not mapping:
        errors.append("{} has no hash mapping".format(context))
        return
    for role, value in mapping.items():
        if SHA256_RE.fullmatch(str(value)) is None:
            errors.append("{}.{} is not SHA256".format(context, role))


def require_exact_hashes(mapping: object, expected_hashes: Mapping[str, str],
                         context: str, errors: list[str]) -> None:
    if not isinstance(mapping, dict):
        errors.append("{} is not a hash mapping".format(context))
        return
    expected_roles = set(expected_hashes)
    actual_roles = set(mapping)
    missing = sorted(expected_roles - actual_roles)
    unexpected = sorted(actual_roles - expected_roles)
    if missing or unexpected:
        errors.append(
            "{} role set mismatch: missing [{}]; unexpected [{}]".format(
                context, ", ".join(missing), ", ".join(unexpected)
            )
        )
    for role, value in mapping.items():
        if SHA256_RE.fullmatch(str(value)) is None:
            errors.append("{}.{} is not SHA256".format(context, role))
    for role in sorted(actual_roles & expected_roles):
        if mapping[role] != expected_hashes[role]:
            errors.append("{}.{} hash identity drift".format(context, role))


def check_equal_roles(point_id: str, roles: dict, errors: list[str]) -> None:
    groups = (
        ("mapped netlist", "dc_mapped_netlist", "pnr_input_netlist", "pnr_imported_netlist"),
        ("routed netlist", "pnr_routed_netlist", "primetime_routed_netlist"),
        ("routed SDC", "pnr_routed_sdc", "primetime_routed_sdc"),
        ("routed database", "pnr_routed_database", "openrcx_input_database"),
        ("SPEF", "openrcx_spef", "primetime_spef"),
    )
    for label, *names in groups:
        values = [roles.get(name) for name in names]
        if any(SHA256_RE.fullmatch(str(value)) is None for value in values):
            errors.append("{} {} handoff has a missing or malformed hash".format(point_id, label))
        elif len(set(values)) != 1:
            errors.append("{} {} handoff identity mismatch".format(point_id, label))


def check_point(point_id: str, point: object, errors: list[str]) -> None:
    expected = EXPECTED_POINTS[point_id]
    if not isinstance(point, dict):
        errors.append("missing closure point {}".format(point_id))
        return
    identity = point.get("identity", {})
    section_hashes = EXPECTED_POINT_SECTION_SHA256[point_id]
    require_section_identity(
        identity, section_hashes["identity"],
        "{}.identity".format(point_id), errors,
    )
    for field in ("profile", "source_commit", "memory_mode", "macro_count"):
        if identity.get(field) != expected[field]:
            errors.append("{} identity drift for {}".format(point_id, field))
    if identity.get("blackbox_count") != 0 or identity.get("top_module") != "cpu_top":
        errors.append("{} top or blackbox identity mismatch".format(point_id))
    for field in ("execution_head", "source_set_sha256", "config_sha256"):
        value = identity.get(field)
        required_length = 40 if field == "execution_head" else 64
        if re.fullmatch(r"[0-9a-f]{{{}}}".format(required_length), str(value)) is None:
            errors.append("{} has invalid {}".format(point_id, field))

    runs = point.get("run_identity", {})
    require_section_identity(
        runs, section_hashes["run_identity"],
        "{}.run_identity".format(point_id), errors,
    )
    required_runs = (
        "dc_run_id", "route_run_id", "primetime_run_id", "routed_netlist_run_id",
        "routed_sdc_run_id", "spef_run_id",
    )
    if any(not runs.get(name) for name in required_runs):
        errors.append("{} has incomplete run identity".format(point_id))
    elif len({runs[name] for name in required_runs[3:]}) != 1 or runs["route_run_id"] != runs["routed_netlist_run_id"]:
        errors.append("{} routed artifacts do not share the route run identity".format(point_id))

    frequency = point.get("frequency", {})
    area = point.get("area", {})
    for field in ("dc_mhz", "postroute_mhz"):
        if frequency.get(field) != expected[field]:
            errors.append("{} frequency drift for {}".format(point_id, field))
    for field in ("standard_cell_area_mm2", "core_area_mm2"):
        if area.get(field) != expected[field]:
            errors.append("{} area drift for {}".format(point_id, field))
    if not all(float(frequency.get(name, 0)) > 0 for name in ("dc_period_ns", "pnr_period_ns", "primetime_period_ns")):
        errors.append("{} has invalid clock period identity".format(point_id))
    if not all(float(area.get(name, 0)) > 0 for name in ("standard_cell_area_um2", "core_area_um2", "die_area_um2")):
        errors.append("{} has incomplete physical area identity".format(point_id))

    expected_hashes = EXPECTED_POINT_HASHES[point_id]
    constraints = point.get("constraint_hashes")
    roles = point.get("role_hashes")
    require_exact_hashes(
        constraints,
        expected_hashes["constraint_hashes"],
        "{}.constraint_hashes".format(point_id),
        errors,
    )
    require_hashes(roles, "{}.role_hashes".format(point_id), errors)
    require_section_identity(
        roles, section_hashes["role_hashes"],
        "{}.role_hashes".format(point_id), errors,
    )
    if isinstance(roles, dict):
        check_equal_roles(point_id, roles, errors)
        for required in ("routed_def", "gds", "standard_cell_liberty", "standard_cell_db"):
            if SHA256_RE.fullmatch(str(roles.get(required))) is None:
                errors.append("{} lacks role hash {}".format(point_id, required))
        if expected["macro_count"] == 4:
            for required in ("dcache_liberty", "dcache_db", "icache_liberty", "icache_db"):
                if SHA256_RE.fullmatch(str(roles.get(required))) is None:
                    errors.append("{} lacks SRAM role hash {}".format(point_id, required))

    dc = point.get("dc_integrity", {})
    for field in ("link_ok", "check_design_ok", "check_timing_ok"):
        if dc.get(field) is not True:
            errors.append("{} DC {} is not true".format(point_id, field))
    for field in (
        "timing_loop_count", "automatic_arc_break_count", "latch_count",
        "unclocked_synchronous_endpoint_count", "unresolved_reference_count",
        "blackbox_count", "electrical_violation_count",
    ):
        if dc.get(field) != 0:
            errors.append("{} DC {} is not zero".format(point_id, field))
    if dc.get("macro_count") != expected["macro_count"]:
        errors.append("{} DC macro count mismatch".format(point_id))
    if dc.get("register_count", 0) <= 0 or dc.get("clocked_register_count") != dc.get("register_count"):
        errors.append("{} DC clocked-register coverage mismatch".format(point_id))
    if float(dc.get("setup_wns_ns", -1)) < 0 or float(dc.get("setup_tns_ns", -1)) != 0:
        errors.append("{} DC setup is not closed".format(point_id))

    stages = point.get("stage_completeness", {})
    required_stages = ("placement", "cts", "detailed_route", "gds", "openrcx", "primetime_reports")
    if any(stages.get(field) is not True for field in required_stages):
        errors.append("{} has an incomplete physical/STA stage".format(point_id))
    require_exact_hashes(
        point.get("report_hashes"),
        expected_hashes["report_hashes"],
        "{}.report_hashes".format(point_id),
        errors,
    )

    route = point.get("route_result", {})
    for field in ("route_drc_count", "antenna_net_count", "antenna_pin_count", "unrouted_net_count"):
        if route.get(field) != 0:
            errors.append("{} route {} is not zero".format(point_id, field))
    if route.get("gds_generated") is not True:
        errors.append("{} has no GDS completion marker".format(point_id))

    sta = point.get("primetime_result", {})
    for field in ("setup_wns_ns", "hold_wns_ns"):
        if sta.get(field) != expected[field]:
            errors.append("{} PrimeTime {} drift".format(point_id, field))
    for field in ("setup_tns_ns", "hold_tns_ns"):
        if float(sta.get(field, -1)) != 0:
            errors.append("{} PrimeTime {} is not zero".format(point_id, field))
    for field in ("setup_violating_paths", "hold_violating_paths", "unclocked_synchronous_endpoint_count"):
        if sta.get(field) != 0:
            errors.append("{} PrimeTime {} is not zero".format(point_id, field))
    if sta.get("constrained_path_coverage_percent") != 100.0:
        errors.append("{} constrained path coverage is not 100 percent".format(point_id))
    if sta.get("analysis_coverage_untested") != expected["analysis_coverage_untested"]:
        errors.append("{} PrimeTime untested-check coverage drift".format(point_id))
    if sta.get("electrical_clean") is not False or sta.get("external_io_model_status") != "not_closed":
        errors.append("{} electrical/IO boundary was weakened".format(point_id))

    maturity = point.get("result_maturity", {})
    expected_maturity = {
        "implementation_chain_status": "verified",
        "postroute_timing_status": "verified",
        "electrical_exceptions_status": "partial",
        "full_io_timing_status": "not_claimed",
        "ocv_mmmc_status": "not_claimed",
        "dft_status": "not_claimed",
        "foundry_signoff_status": "not_claimed",
        "overall_profile_maturity": "partial",
    }
    for field, value in expected_maturity.items():
        if maturity.get(field) != value:
            errors.append("{} maturity drift for {}".format(point_id, field))
    if expected["macro_count"] == 4:
        if maturity.get("macro_model_status") != "partial_analytical_characterization":
            errors.append("{} SRAM analytical model boundary is missing".format(point_id))
        if maturity.get("macro_physical_signoff_status") != "not_closed":
            errors.append("{} SRAM macro signoff boundary is missing".format(point_id))
        joined = " ".join(str(item) for item in point.get("caveats", []))
        for fragment in (
            "OpenRAM analytical FreePDK45 TT, 1.0 V, 25 C",
            "Nangate45 typical, 1.1 V, 25 C",
            "RC-004",
            "Macro DRC/LVS/PEX",
            "OCV/MMMC",
            "DFT",
            "formal LEC",
            "power",
        ):
            if fragment not in joined:
                errors.append("{} SRAM caveat lacks {}".format(point_id, fragment))
    nonclaims = set(point.get("nonclaims", []))
    for required in ("maximum frequency", "complete electrical closure", "foundry signoff", "silicon result"):
        if required not in nonclaims:
            errors.append("{} nonclaims lack {}".format(point_id, required))
    if tuple(point.get("claim_ids", ())) != expected["claims"]:
        errors.append("{} claim ID mapping drift".format(point_id))


def check_implementation(root: Path, errors: list[str]) -> dict:
    path = root / IMPLEMENTATION_PATH
    data = load_object(path, errors)
    if not data:
        return {}
    if data.get("schema") != "npc-riscv-open/nangate45-backend-evidence-v1":
        errors.append("implementation evidence schema mismatch")
    if data.get("evidence_id") != IMPLEMENTATION_EVIDENCE_ID:
        errors.append("implementation evidence ID mismatch")
    if data.get("audit_verdict") != "AUDIT_CONFIRMED_EXISTING_BACKEND_RESULTS":
        errors.append("D11 audit verdict mismatch")
    audit = data.get("audit_source", {})
    require_section_identity(
        audit, EXPECTED_GLOBAL_SECTION_SHA256["audit_source"],
        "audit_source", errors,
    )
    if audit.get("rerun_performed") is not False or audit.get("heavy_stage_rerun_count") != 0:
        errors.append("bounded evidence incorrectly records a heavy-stage rerun")
    boundary = data.get("claim_boundary", {})
    if boundary.get("classification") != "fixed-frequency Nangate45 academic closure points":
        errors.append("fixed-frequency academic claim boundary is missing")
    if boundary.get("not_fmax") is not True or boundary.get("foundry_signoff_status") != "not_claimed":
        errors.append("Fmax/foundry nonclaim boundary is missing")
    platform = data.get("platform_identity", {})
    require_section_identity(
        platform, EXPECTED_GLOBAL_SECTION_SHA256["platform_identity"],
        "platform_identity", errors,
    )
    if platform.get("rc_source") != "PDK_PROVIDED_ACADEMIC_RC":
        errors.append("academic RC source identity mismatch")
    for field in (
        "standard_cell_liberty_sha256", "standard_cell_db_sha256",
        "technology_lef_sha256", "standard_cell_macro_lef_sha256",
        "standard_cell_gds_sha256", "source_sdc_sha256", "openrcx_rules_sha256",
    ):
        if SHA256_RE.fullmatch(str(platform.get(field))) is None:
            errors.append("platform identity lacks {}".format(field))
    tools = platform.get("tools", {})
    for tool in ("design_compiler", "openroad", "openrcx", "primetime", "library_compiler", "klayout"):
        if not isinstance(tools.get(tool), dict) or not tools[tool].get("version"):
            errors.append("platform tool identity lacks {}".format(tool))
    sram = data.get("sram_identity", {})
    require_section_identity(
        sram, EXPECTED_GLOBAL_SECTION_SHA256["sram_identity"],
        "sram_identity", errors,
    )
    if (
        sram.get("macro_count_per_design") != 4
        or sram.get("mixed_pvt") is not True
        or sram.get("macro_drc_lvs_pex_status") != "not_closed"
        or sram.get("rc004_retained") is not True
    ):
        errors.append("global SRAM model/signoff boundary mismatch")
    require_hashes(sram.get("macro_view_hashes"), "sram_identity.macro_view_hashes", errors)

    points = data.get("closure_points")
    if not isinstance(points, dict) or set(points) != set(EXPECTED_POINTS):
        errors.append("implementation evidence must contain exactly four closure points")
        points = points if isinstance(points, dict) else {}
    for point_id in EXPECTED_POINTS:
        check_point(point_id, points.get(point_id), errors)

    text = path.read_text(encoding="utf-8")
    if PRIVATE_PATH_RE.search(text):
        errors.append("implementation evidence contains an absolute private path")
    if PRIVATE_ADDRESS_RE.search(text):
        errors.append("implementation evidence contains a private host address")
    return data


def check_source_alignment(root: Path, implementation: dict,
                           errors: list[str]) -> None:
    manifest_path = next(
        (root / relative for relative in SOURCE_MANIFEST_PATHS
         if (root / relative).is_file()),
        None,
    )
    if manifest_path is None:
        errors.append("public source allowlist is missing")
        return
    manifest = load_object(manifest_path, errors)
    records = manifest.get("profiles", []) if manifest else []
    profiles = {
        item.get("profile_id"): item
        for item in records
        if isinstance(item, dict) and item.get("profile_id")
    }
    points = implementation.get("closure_points", {})
    for point_id, mode in (
        ("rv32im_single_perf.registers", "registers"),
        ("rv32im_single_perf.sram", "sram"),
        ("rv32ima_sv32_linux.registers", "registers"),
        ("rv32ima_sv32_linux.sram", "sram"),
    ):
        point = points.get(point_id, {})
        identity = point.get("identity", {}) if isinstance(point, dict) else {}
        profile_id = identity.get("profile")
        profile = profiles.get(profile_id)
        if not isinstance(profile, dict):
            errors.append("source allowlist lacks {}".format(profile_id))
            continue
        if profile.get("source_commit") != identity.get("source_commit"):
            errors.append("{} source commit is not aligned to the allowlist".format(point_id))
        source_sets = profile.get("implementation_source_sets", {})
        source_set = source_sets.get(mode) if isinstance(source_sets, dict) else None
        if not isinstance(source_set, dict):
            errors.append("{} lacks an implementation source-set lock".format(point_id))
        elif source_set.get("source_set_sha256") != identity.get("source_set_sha256"):
            errors.append("{} source-set SHA256 is not aligned to evidence".format(point_id))

    single = profiles.get("rv32im_single_perf", {})
    overlays = single.get("memory_mode_overlays", []) if isinstance(single, dict) else []
    expected_overlay_paths = {
        "rtl/profiles/rv32im_single_perf/cache/CacheDataArray1R1W.v",
        "rtl/profiles/rv32im_single_perf/cache/DCache.v",
        "rtl/profiles/rv32im_single_perf/cache/ICache.v",
    }
    actual_overlay_paths = {
        item.get("logical_destination")
        for item in overlays
        if isinstance(item, dict)
    }
    if actual_overlay_paths != expected_overlay_paths or len(overlays) != 3:
        errors.append("Single SRAM must use the exact three audited cache overlays")
    for item in overlays:
        if not isinstance(item, dict):
            errors.append("Single SRAM source overlay is malformed")
            continue
        if (
            item.get("memory_mode") != "sram"
            or item.get("source_commit")
            != "176d4fd74da61ec681816630854501b233213982"
            or item.get("comparison")
            != "FUNCTIONAL_TOKEN_DIFFERENCE_NPC_ASIC_SRAM"
            or item.get("overlay_reason")
            != "D8_AUDITED_SRAM_BINDING_FUNCTIONAL_DELTA"
            or item.get("roles") != ["asic_sram"]
            or SHA256_RE.fullmatch(str(item.get("sha256"))) is None
        ):
            errors.append("Single SRAM functional overlay identity is incomplete")


def check_showcase(root: Path, implementation: dict, errors: list[str]) -> None:
    showcase_path = root / SHOWCASE_PATH
    data = load_object(showcase_path, errors)
    if not data:
        return
    if data.get("schema") != "npc-riscv-open/showcase-data-v1":
        errors.append("showcase data schema mismatch")
    source = data.get("implementation_evidence", {})
    if source.get("id") != IMPLEMENTATION_EVIDENCE_ID:
        errors.append("showcase source evidence ID mismatch")
    if source.get("path") != IMPLEMENTATION_PATH.as_posix():
        errors.append("showcase implementation evidence path mismatch")
    implementation_path = root / IMPLEMENTATION_PATH
    if implementation_path.is_file() and source.get("sha256") != sha256(implementation_path):
        errors.append("showcase implementation evidence hash is stale")
    profile_rows = data.get("profiles", [])
    profile_ids = [row.get("id") for row in profile_rows if isinstance(row, dict)]
    if profile_ids != ["rv32im_single_perf", "rv32ima_sv32_linux", "rv32im_ooo_4k"]:
        errors.append("showcase profile order/set mismatch")
    for row in profile_rows:
        if not isinstance(row, dict):
            continue
        backend = row.get("backend", {})
        expected_status = "planned" if row.get("id") == "rv32im_ooo_4k" else "verified_fixed_point"
        if backend != {"registers": expected_status, "sram": expected_status}:
            errors.append("showcase backend matrix drift for {}".format(row.get("id")))
    points = implementation.get("closure_points", {}) if isinstance(implementation, dict) else {}
    rows = data.get("closure_points", [])
    if [row.get("id") for row in rows if isinstance(row, dict)] != list(EXPECTED_POINTS):
        errors.append("showcase closure point order/set mismatch")
    for row in rows:
        if not isinstance(row, dict) or row.get("id") not in EXPECTED_POINTS:
            continue
        point_id = row["id"]
        point = points.get(point_id, {})
        expected_fields = {
            "dc_mhz": point.get("frequency", {}).get("dc_mhz"),
            "postroute_mhz": point.get("frequency", {}).get("postroute_mhz"),
            "standard_cell_area_mm2": point.get("area", {}).get("standard_cell_area_mm2"),
            "core_area_mm2": point.get("area", {}).get("core_area_mm2"),
            "macro_count": point.get("identity", {}).get("macro_count"),
            "claim_ids": point.get("claim_ids"),
        }
        for field, value in expected_fields.items():
            if row.get(field) != value:
                errors.append("showcase {}.{} does not match evidence".format(point_id, field))

    provenance = load_object(root / ASSET_PROVENANCE_PATH, errors)
    if not provenance:
        return
    if provenance.get("schema") != "npc-riscv-open/showcase-asset-provenance-v1":
        errors.append("asset provenance schema mismatch")
    generator = provenance.get("generator", {})
    generator_path = root / str(generator.get("path", ""))
    if not generator_path.is_file() or generator.get("sha256") != sha256(generator_path):
        errors.append("showcase generator identity is stale")
    if generator.get("command") != "python3 flows/scripts/generate_showcase_assets.py --write":
        errors.append("showcase generator command mismatch")
    source_records = {
        item.get("id"): item for item in provenance.get("source_evidence", [])
        if isinstance(item, dict) and item.get("id")
    }
    expected_sources = {
        "npc_showcase_data_public": SHOWCASE_PATH,
        IMPLEMENTATION_EVIDENCE_ID: IMPLEMENTATION_PATH,
    }
    for evidence_id, relative in expected_sources.items():
        record = source_records.get(evidence_id, {})
        path = root / relative
        if record.get("path") != relative.as_posix() or not path.is_file() or record.get("sha256") != sha256(path):
            errors.append("asset provenance source mismatch for {}".format(evidence_id))
    assets = {item.get("id"): item for item in provenance.get("assets", []) if isinstance(item, dict)}
    expected_assets = {
        "npc_profile_portfolio_asset": Path("docs/assets/profile_portfolio.svg"),
        "npc_nangate45_closure_asset": Path("docs/assets/nangate45_closure_points.svg"),
    }
    for evidence_id, relative in expected_assets.items():
        record = assets.get(evidence_id, {})
        path = root / relative
        if record.get("path") != relative.as_posix() or not path.is_file():
            errors.append("asset provenance lacks {}".format(evidence_id))
            continue
        if record.get("sha256") != sha256(path) or record.get("size_bytes") != path.stat().st_size:
            errors.append("asset output identity is stale for {}".format(evidence_id))
        if evidence_id == "npc_nangate45_closure_asset" and set(record.get("claim_ids", [])) != set(EXPECTED_CLAIMS):
            errors.append("closure asset claim coverage mismatch")


def public_document_path(root: Path, relative: Path) -> Path:
    path = root / relative
    if path.is_file() or relative.parts[0] != "README.md" and relative.parts[0] != "README.en.md":
        return path
    return root / "control" / relative


def read_document(root: Path, relative: Path, errors: list[str]) -> str:
    path = public_document_path(root, relative)
    try:
        return path.read_text(encoding="utf-8")
    except OSError as error:
        errors.append("missing public document {}: {}".format(relative, error))
        return ""


def claim_markers(text: str, label: str, errors: list[str]) -> dict[str, str]:
    result: dict[str, str] = {}
    for claim_id, maturity in CLAIM_MARKER_RE.findall(text):
        if claim_id in result:
            errors.append("{} has duplicate claim marker {}".format(label, claim_id))
        result[claim_id] = maturity
    return result


def check_marker_pair(root: Path, left: Path, right: Path,
                      expected_claims: set[str], expected_evidence: set[str],
                      errors: list[str]) -> None:
    left_text = read_document(root, left, errors)
    right_text = read_document(root, right, errors)
    if not left_text or not right_text:
        return
    left_claims = claim_markers(left_text, left.as_posix(), errors)
    right_claims = claim_markers(right_text, right.as_posix(), errors)
    if left_claims != right_claims:
        errors.append("bilingual claim marker drift: {} != {}".format(left, right))
    if set(left_claims) != expected_claims:
        errors.append("{} claim marker set does not match governed claims".format(left))
    if any(maturity != "verified" for maturity in left_claims.values()):
        errors.append("{} contains a non-verified governed claim marker".format(left))
    left_evidence = set(EVIDENCE_MARKER_RE.findall(left_text))
    right_evidence = set(EVIDENCE_MARKER_RE.findall(right_text))
    if left_evidence != right_evidence:
        errors.append("bilingual evidence marker drift: {} != {}".format(left, right))
    if not expected_evidence.issubset(left_evidence):
        errors.append("{} lacks governed evidence markers".format(left))


def check_numeric_surface(root: Path, relative: Path, errors: list[str]) -> None:
    text = read_document(root, relative, errors)
    if not text:
        return
    lines = text.splitlines()
    for point_id, expected in EXPECTED_POINTS.items():
        frequency = "{} / {} MHz".format(
            expected["dc_mhz"], expected["postroute_mhz"]
        )
        matches = [line for line in lines if frequency in line]
        if len(matches) != 1:
            errors.append(
                "{} must contain exactly one numeric row for {}".format(
                    relative, point_id
                )
            )
            continue
        row = matches[0]
        required = (
            "+{:.6f} / +{:.6f} ns".format(
                expected["setup_wns_ns"], expected["hold_wns_ns"]
            ),
            "{:.6f} / {:.6f} mm\u00b2".format(
                expected["standard_cell_area_mm2"], expected["core_area_mm2"]
            ),
            "| {} |".format(expected["macro_count"]),
        )
        for token in required:
            if token not in row:
                errors.append(
                    "{} numeric drift for {}: missing {}".format(
                        relative, point_id, token
                    )
                )


def check_document_surfaces(root: Path, errors: list[str]) -> None:
    check_marker_pair(
        root,
        Path("README.md"),
        Path("README.en.md"),
        EXPECTED_README_CLAIMS,
        {IMPLEMENTATION_EVIDENCE_ID, "coremark_public_current"},
        errors,
    )
    check_marker_pair(
        root,
        Path("docs/evidence/backend_closure.md"),
        Path("docs/evidence/backend_closure.en.md"),
        set(EXPECTED_CLAIMS),
        {IMPLEMENTATION_EVIDENCE_ID},
        errors,
    )
    for relative in (
        Path("README.md"),
        Path("README.en.md"),
        Path("docs/evidence/backend_closure.md"),
        Path("docs/evidence/backend_closure.en.md"),
        Path("docs/performance.md"),
        Path("docs/performance.en.md"),
    ):
        check_numeric_surface(root, relative, errors)


def check_governance(root: Path, errors: list[str]) -> None:
    delivery_root = root / "delivery"
    if not delivery_root.is_dir() and (root.parent / "delivery").is_dir():
        delivery_root = root.parent / "delivery"
    claims_path = delivery_root / "claims/claims.yaml"
    manifest_path = delivery_root / "evidence/manifest.yaml"
    claims_data = load_object(claims_path, errors)
    manifest_data = load_object(manifest_path, errors)
    if not claims_data or not manifest_data:
        return
    raw_claims = claims_data.get("claims")
    raw_evidence = manifest_data.get("evidence")
    if not isinstance(raw_claims, list) or not isinstance(raw_evidence, list):
        errors.append("public claims/evidence metadata has an invalid list contract")
        return
    claims = {item.get("id"): item for item in raw_claims if isinstance(item, dict) and item.get("id")}
    evidence = {item.get("id"): item for item in raw_evidence if isinstance(item, dict) and item.get("id")}
    if len(claims) != len([item for item in raw_claims if isinstance(item, dict) and item.get("id")]):
        errors.append("public claims have duplicate IDs")
    if len(evidence) != len([item for item in raw_evidence if isinstance(item, dict) and item.get("id")]):
        errors.append("public evidence has duplicate IDs")
    for claim_id, expected in EXPECTED_CLAIMS.items():
        claim = claims.get(claim_id)
        if not isinstance(claim, dict):
            errors.append("missing implementation claim {}".format(claim_id))
            continue
        for field in ("profile", "source_ref", "metric", "value", "unit"):
            if claim.get(field) != expected[field]:
                errors.append("claim {} drift for {}".format(claim_id, field))
        if claim.get("status") != "verified" or claim.get("public") is not True:
            errors.append("claim {} is not public verified".format(claim_id))
        if claim.get("evidence") != [IMPLEMENTATION_EVIDENCE_ID]:
            errors.append("claim {} evidence binding mismatch".format(claim_id))
        for required in ("statement", "benchmark", "configuration", "tool", "caveat"):
            if not claim.get(required):
                errors.append("claim {} lacks {}".format(claim_id, required))
    implementation_entry = evidence.get(IMPLEMENTATION_EVIDENCE_ID)
    if not isinstance(implementation_entry, dict):
        errors.append("delivery evidence lacks implementation entry")
    else:
        if set(implementation_entry.get("claims", [])) != set(EXPECTED_CLAIMS):
            errors.append("implementation evidence reverse claim binding mismatch")
        implementation_path = root / IMPLEMENTATION_PATH
        if implementation_path.is_file() and implementation_entry.get("sha256") != sha256(implementation_path):
            errors.append("delivery implementation evidence SHA256 is stale")
        if implementation_entry.get("status") != "verified" or implementation_entry.get("public") is not True:
            errors.append("implementation evidence is not public verified")
    for evidence_id in SHOWCASE_EVIDENCE_IDS:
        if evidence_id not in evidence:
            errors.append("delivery evidence lacks showcase entry {}".format(evidence_id))


def run_checks(root: Path, governance: bool = True) -> list[str]:
    errors: list[str] = []
    implementation = check_implementation(root, errors)
    if implementation:
        check_source_alignment(root, implementation, errors)
        check_showcase(root, implementation, errors)
        check_document_surfaces(root, errors)
    if governance:
        check_governance(root, errors)
    return sorted(set(errors))


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--root",
        type=Path,
        default=Path(__file__).resolve().parents[2],
        help="exported public repository root",
    )
    parser.add_argument(
        "--evidence-only",
        action="store_true",
        help="check source evidence/assets before public JSON governance is exported",
    )
    args = parser.parse_args()
    errors = run_checks(args.root.resolve(), governance=not args.evidence_only)
    if errors:
        print("IMPLEMENTATION_CHECK_FAILED", file=sys.stderr)
        for error in errors:
            print("  - {}".format(error), file=sys.stderr)
        return 1
    print(
        "IMPLEMENTATION_CHECK_PASS points=4 claims={} role_equalities=20 assets=2".format(
            len(EXPECTED_CLAIMS)
        )
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
