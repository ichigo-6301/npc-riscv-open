#!/usr/bin/env python3
"""Fail-closed tests for bounded OoO history evidence."""

from __future__ import print_function

import copy
import hashlib
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CHECKER_PATH = ROOT / "flows/scripts/check_ooo_history.py"
SPEC = importlib.util.spec_from_file_location("check_ooo_history", str(CHECKER_PATH))
CHECKER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(CHECKER)
DOCS_CHECKER_PATH = ROOT / "flows/scripts/check_docs.py"
DOCS_SPEC = importlib.util.spec_from_file_location("check_docs_for_ooo_history", str(DOCS_CHECKER_PATH))
DOCS_CHECKER = importlib.util.module_from_spec(DOCS_SPEC)
assert DOCS_SPEC.loader is not None
DOCS_SPEC.loader.exec_module(DOCS_CHECKER)


def load(relative):
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class OooHistoryTests(unittest.TestCase):
    def test_current_evidence_passes(self):
        self.assertEqual(CHECKER.run_checks(ROOT), [])

    def test_coremark_counter_status_source_and_domain_mutations_fail(self):
        source = load(CHECKER.COREMARK_PATH)
        mutations = (
            lambda item: item["baseline"].__setitem__("cycles", 48395813),
            lambda item: item["optimized"].__setitem__("whole_program_cpi", 1.0),
            lambda item: item["derived"].__setitem__("value", 5.0),
            lambda item: item["derived"].__setitem__("retired_instruction_delta", 11),
            lambda item: item["baseline"].__setitem__("status", "historical_verified"),
            lambda item: item.__setitem__("generated_at", "2026-08-11T00:00:00Z"),
            lambda item: item.__setitem__("caveat", "Current loop-free DC result"),
            lambda item: item["optimized"].__setitem__("source_ref", "0" * 40),
            lambda item: item["optimized"].__setitem__("binary_sha256", "0" * 63),
            lambda item: item.__setitem__("epoch", "current"),
            lambda item: item["comparability_domain"]["default_profile"].__setitem__(
                "ifetch_latency", 3),
            lambda item: item["lineage"].__setitem__("relationship", "ancestor"),
            lambda item: item["lineage"]["inheritance"].__setitem__("loop_free", True),
            lambda item: item["claim_ids"].pop(),
        )
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                candidate = copy.deepcopy(source)
                mutate(candidate)
                errors = []
                CHECKER.check_coremark(candidate, errors)
                self.assertTrue(errors)

    def test_loop_gate_identity_and_nonclaim_mutations_fail(self):
        source = load(CHECKER.LOOP_PATH)
        mutations = (
            lambda item: item["source"].__setitem__("implementation_commit", "0" * 40),
            lambda item: item["source"].__setitem__("relationship_to_canonical", "ancestor"),
            lambda item: item["source"].__setitem__("filelist_sha256", "0" * 64),
            lambda item: item["source"]["input_bundle"].__setitem__("sha256", "0" * 64),
            lambda item: item["structural"]["spyglass"].__setitem__("comb_loop", 1),
            lambda item: item["structural"]["verilator"].__setitem__("unoptflat", 1),
            lambda item: item["structural"]["yosys"].__setitem__("pre_techmap_scc", 1),
            lambda item: item["structural"]["yosys"].__setitem__("post_techmap_scc", 1),
            lambda item: item["functional"].__setitem__("identity_points_reported_passed", 13),
            lambda item: item["functional"].__setitem__("precise_retirement_preserved", True),
            lambda item: item["architecture"]["precise_retirement_semantics"].__setitem__(
                "evidence_maturity", "verified"),
            lambda item: item["functional"].__setitem__(
                "per_point_binary_config_trace_identity_complete", True),
            lambda item: item["inheritance"].__setitem__("performance", True),
            lambda item: item.__setitem__("whole_program_cpi", 1.1),
            lambda item: item["claim_ids"].pop(),
        )
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                candidate = copy.deepcopy(source)
                mutate(candidate)
                errors = []
                CHECKER.check_loop_remediation(candidate, errors)
                self.assertTrue(errors)

    def test_patch_path_traversal_is_rejected(self):
        malicious = (
            "diff --git a/../escape.sv b/rtl/profiles/rv32im_ooo_4k/core/escape.sv\n"
            "--- a/../escape.sv\n"
            "+++ b/rtl/profiles/rv32im_ooo_4k/core/escape.sv\n"
            "@@ -1 +1 @@\n-old\n+new\n"
        )
        with tempfile.TemporaryDirectory() as temporary:
            patch = Path(temporary) / "escape.patch"
            patch.write_text(malicious, encoding="utf-8")
            errors = []
            CHECKER.validate_patch_paths(patch, errors)
            self.assertTrue(any("escapes" in error for error in errors), errors)

    def test_lineage_source_hash_role_and_binding_mutations_fail(self):
        source = load(CHECKER.LINEAGE_PATH)
        records = CHECKER.snapshot_records(source, [])
        mutations = (
            lambda item: next(entry for entry in item["snapshots"] if entry["id"] == "p89").__setitem__(
                "source_ref", "0" * 40),
            lambda item: next(entry for entry in item["snapshots"] if entry["id"] == "p89").__setitem__(
                "relationship", "current"),
            lambda item: next(entry for entry in item["snapshots"] if entry["id"] == "d12").__setitem__(
                "relationship", "ancestor"),
            lambda item: next(entry for entry in item["snapshots"] if entry["id"] == "d12")["roles"].pop(),
            lambda item: next(entry for entry in item["snapshots"] if entry["id"] == "p89")["patch"].__setitem__(
                "sha256", "0" * 64),
            lambda item: item["evidence_bindings"].__setitem__("d12", CHECKER.COREMARK_PATH),
        )
        self.assertEqual(set(records), {"p89", "d12"})
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                candidate = copy.deepcopy(source)
                mutate(candidate)
                errors = []
                CHECKER.check_source_lineage(ROOT, candidate, errors)
                self.assertTrue(errors)

    def test_patch_and_source_manifest_payload_mutations_fail(self):
        lineage = load(CHECKER.LINEAGE_PATH)
        records = CHECKER.snapshot_records(lineage, [])
        for snapshot_id, binding_name in (("p89", "patch"), ("d12", "source_set_manifest")):
            with self.subTest(snapshot=snapshot_id, binding=binding_name), tempfile.TemporaryDirectory() as temporary:
                temporary_root = Path(temporary)
                shutil.copytree(str(ROOT / "rtl"), str(temporary_root / "rtl"))
                source_history = ROOT / Path(CHECKER.LINEAGE_PATH).parent
                target_history = temporary_root / Path(CHECKER.LINEAGE_PATH).parent
                target_history.parent.mkdir(parents=True, exist_ok=True)
                shutil.copytree(str(source_history), str(target_history))
                canonical_manifest = lineage["canonical"]["source_set_manifest"]["path"]
                source_canonical = ROOT / canonical_manifest
                target_canonical = temporary_root / canonical_manifest
                if not target_canonical.exists():
                    target_canonical.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(str(source_canonical), str(target_canonical))

                candidate = copy.deepcopy(lineage)
                snapshot = next(item for item in candidate["snapshots"] if item["id"] == snapshot_id)
                payload = temporary_root / snapshot[binding_name]["path"]
                if binding_name == "patch":
                    payload.write_bytes(payload.read_bytes() + b"\n")
                else:
                    lines = payload.read_text(encoding="utf-8").splitlines()
                    payload.write_text("\n".join(lines[:-1]) + "\n", encoding="utf-8")
                errors = []
                CHECKER.check_source_lineage(temporary_root, candidate, errors)
                self.assertTrue(any("SHA256 drift" in error for error in errors), errors)

    def test_coordinated_missing_role_and_role_hash_mutations_still_fail(self):
        original = load(CHECKER.LINEAGE_PATH)
        for mode in ("missing", "hash"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory() as temporary:
                temporary_root = Path(temporary)
                shutil.copytree(str(ROOT / "rtl"), str(temporary_root / "rtl"))
                source_history = ROOT / Path(CHECKER.LINEAGE_PATH).parent
                target_history = temporary_root / Path(CHECKER.LINEAGE_PATH).parent
                target_history.parent.mkdir(parents=True, exist_ok=True)
                shutil.copytree(str(source_history), str(target_history))
                canonical_manifest = original["canonical"]["source_set_manifest"]["path"]
                target_canonical = temporary_root / canonical_manifest
                if not target_canonical.exists():
                    target_canonical.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copy2(str(ROOT / canonical_manifest), str(target_canonical))

                candidate = copy.deepcopy(original)
                snapshot = next(item for item in candidate["snapshots"] if item["id"] == "p89")
                manifest = temporary_root / snapshot["source_set_manifest"]["path"]
                lines = manifest.read_text(encoding="utf-8").splitlines()
                if mode == "missing":
                    lines.pop()
                    snapshot["roles"].pop()
                    snapshot["file_count"] -= 1
                else:
                    digest_value, relative = lines[0].split("  ", 1)
                    lines[0] = "{}  {}".format("0" * 64, relative)
                manifest.write_text("\n".join(lines) + "\n", encoding="utf-8")
                new_hash = digest(manifest)
                snapshot["source_set_manifest"]["sha256"] = new_hash

                lineage_path = temporary_root / CHECKER.LINEAGE_PATH
                lineage_path.write_text(json.dumps(candidate, indent=2) + "\n", encoding="utf-8")
                errors = []
                CHECKER.check_source_lineage(temporary_root, candidate, errors)
                if mode == "missing":
                    self.assertTrue(any("source-role set mismatch" in error for error in errors), errors)
                else:
                    self.assertTrue(any("source SHA256 drift" in error for error in errors), errors)

    def test_coordinated_manifest_hash_and_status_promotion_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary_root = Path(temporary)
            for relative in (
                CHECKER.COREMARK_PATH,
                CHECKER.LOOP_PATH,
                CHECKER.CLAIMS_PATH,
                CHECKER.NONCLAIMS_PATH,
                CHECKER.EVIDENCE_MANIFEST_PATH,
            ):
                target = temporary_root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(str(ROOT / relative), str(target))

            coremark = load(CHECKER.COREMARK_PATH)
            coremark["comparison_status"] = "verified"
            coremark["baseline"]["status"] = "historical_verified"
            coremark["derived"]["status"] = "verified"
            coremark_path = temporary_root / CHECKER.COREMARK_PATH
            coremark_path.write_text(json.dumps(coremark, indent=2) + "\n", encoding="utf-8")

            claims_path = temporary_root / CHECKER.CLAIMS_PATH
            claims = json.loads(claims_path.read_text(encoding="utf-8"))
            promoted = {
                "ooo_historical_s9a_coremark_whole_cpi",
                "ooo_historical_coremark_approx_speedup",
            }
            for claim in claims["claims"]:
                if claim.get("id") in promoted:
                    claim["status"] = "verified"
            claims_path.write_text(json.dumps(claims, indent=2) + "\n", encoding="utf-8")

            manifest_path = temporary_root / CHECKER.EVIDENCE_MANIFEST_PATH
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            item = next(entry for entry in manifest["evidence"]
                        if entry.get("id") == "ooo_coremark_history_public")
            item["status"] = "verified"
            item["sha256"] = digest(coremark_path)
            item["size_bytes"] = coremark_path.stat().st_size
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

            loop = json.loads((temporary_root / CHECKER.LOOP_PATH).read_text(encoding="utf-8"))
            errors = []
            CHECKER.check_coremark(coremark, errors)
            CHECKER.check_delivery_links(temporary_root, coremark, loop, errors)
            self.assertTrue(any("partial" in error or "status" in error for error in errors), errors)

            nonclaims_path = temporary_root / CHECKER.NONCLAIMS_PATH
            nonclaims = json.loads(nonclaims_path.read_text(encoding="utf-8"))
            item = next(entry for entry in nonclaims["nonclaims"]
                        if entry.get("id") == "ooo_loop_remediation_performance_not_inherited")
            item["status"] = "verified"
            nonclaims_path.write_text(json.dumps(nonclaims, indent=2) + "\n", encoding="utf-8")
            errors = []
            CHECKER.check_delivery_links(temporary_root, coremark, loop, errors)
            self.assertTrue(any("nonclaim" in error and "status" in error for error in errors), errors)

    def test_coordinated_coremark_caveat_and_manifest_hash_mutation_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary_root = Path(temporary)
            for relative in (
                CHECKER.COREMARK_PATH,
                CHECKER.LOOP_PATH,
                CHECKER.CLAIMS_PATH,
                CHECKER.NONCLAIMS_PATH,
                CHECKER.EVIDENCE_MANIFEST_PATH,
            ):
                target = temporary_root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(str(ROOT / relative), str(target))

            coremark_path = temporary_root / CHECKER.COREMARK_PATH
            coremark = json.loads(coremark_path.read_text(encoding="utf-8"))
            coremark["caveat"] = "Current loop-free DC result"
            coremark_path.write_text(json.dumps(coremark, indent=2) + "\n", encoding="utf-8")

            manifest_path = temporary_root / CHECKER.EVIDENCE_MANIFEST_PATH
            manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
            entry = next(item for item in manifest["evidence"]
                         if item.get("id") == "ooo_coremark_history_public")
            entry["sha256"] = digest(coremark_path)
            entry["size_bytes"] = coremark_path.stat().st_size
            manifest_path.write_text(json.dumps(manifest, indent=2) + "\n", encoding="utf-8")

            loop = json.loads((temporary_root / CHECKER.LOOP_PATH).read_text(encoding="utf-8"))
            errors = []
            CHECKER.check_coremark(coremark, errors)
            CHECKER.check_delivery_links(temporary_root, coremark, loop, errors)
            self.assertTrue(any("caveat" in error for error in errors), errors)

    def test_all_claim_and_nonclaim_semantics_are_locked(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary_root = Path(temporary)
            for relative in (
                CHECKER.COREMARK_PATH,
                CHECKER.LOOP_PATH,
                CHECKER.CLAIMS_PATH,
                CHECKER.NONCLAIMS_PATH,
                CHECKER.EVIDENCE_MANIFEST_PATH,
            ):
                target = temporary_root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(str(ROOT / relative), str(target))
            coremark = json.loads((temporary_root / CHECKER.COREMARK_PATH).read_text(encoding="utf-8"))
            loop = json.loads((temporary_root / CHECKER.LOOP_PATH).read_text(encoding="utf-8"))

            claims_path = temporary_root / CHECKER.CLAIMS_PATH
            original_claims = json.loads(claims_path.read_text(encoding="utf-8"))
            for claim_id in CHECKER.EXPECTED_CLAIMS:
                with self.subTest(claim=claim_id):
                    claims = copy.deepcopy(original_claims)
                    item = next(entry for entry in claims["claims"] if entry.get("id") == claim_id)
                    item["statement"] += " drift"
                    claims_path.write_text(json.dumps(claims, indent=2) + "\n", encoding="utf-8")
                    errors = []
                    CHECKER.check_delivery_links(temporary_root, coremark, loop, errors)
                    self.assertTrue(any("claim" in error and "statement" in error for error in errors), errors)
            claims_path.write_text(json.dumps(original_claims, indent=2) + "\n", encoding="utf-8")

            nonclaims_path = temporary_root / CHECKER.NONCLAIMS_PATH
            original_nonclaims = json.loads(nonclaims_path.read_text(encoding="utf-8"))
            for nonclaim_id in CHECKER.EXPECTED_NONCLAIMS:
                with self.subTest(nonclaim=nonclaim_id):
                    nonclaims = copy.deepcopy(original_nonclaims)
                    item = next(entry for entry in nonclaims["nonclaims"]
                                if entry.get("id") == nonclaim_id)
                    item["reason"] += " drift"
                    nonclaims_path.write_text(json.dumps(nonclaims, indent=2) + "\n", encoding="utf-8")
                    errors = []
                    CHECKER.check_delivery_links(temporary_root, coremark, loop, errors)
                    self.assertTrue(any("nonclaim" in error and "reason" in error for error in errors), errors)

    def test_extra_incoming_claim_nonclaim_and_manifest_links_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            temporary_root = Path(temporary)
            for relative in (
                CHECKER.COREMARK_PATH,
                CHECKER.LOOP_PATH,
                CHECKER.CLAIMS_PATH,
                CHECKER.NONCLAIMS_PATH,
                CHECKER.EVIDENCE_MANIFEST_PATH,
            ):
                target = temporary_root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(str(ROOT / relative), str(target))
            coremark = json.loads((temporary_root / CHECKER.COREMARK_PATH).read_text(encoding="utf-8"))
            loop = json.loads((temporary_root / CHECKER.LOOP_PATH).read_text(encoding="utf-8"))

            cases = ("claim", "nonclaim", "manifest_claim", "manifest_nonclaim")
            for mode in cases:
                with self.subTest(mode=mode):
                    claims = json.loads((ROOT / CHECKER.CLAIMS_PATH).read_text(encoding="utf-8"))
                    nonclaims = json.loads((ROOT / CHECKER.NONCLAIMS_PATH).read_text(encoding="utf-8"))
                    manifest = json.loads((ROOT / CHECKER.EVIDENCE_MANIFEST_PATH).read_text(encoding="utf-8"))
                    if mode == "claim":
                        extra = copy.deepcopy(next(item for item in claims["claims"]
                                                   if item["id"] == CHECKER.COREMARK_CLAIMS[0]))
                        extra["id"] = "unexpected_ooo_history_claim"
                        claims["claims"].append(extra)
                    elif mode == "nonclaim":
                        extra = copy.deepcopy(next(item for item in nonclaims["nonclaims"]
                                                   if item["id"] in CHECKER.EXPECTED_NONCLAIMS))
                        extra["id"] = "unexpected_ooo_history_nonclaim"
                        nonclaims["nonclaims"].append(extra)
                    else:
                        extra = copy.deepcopy(manifest["evidence"][0])
                        extra["id"] = "unexpected_ooo_history_manifest"
                        extra["claims"] = [CHECKER.COREMARK_CLAIMS[0]] if mode == "manifest_claim" else []
                        extra["nonclaims"] = (["ooo_historical_coremark_strict_ab_not_claimed"]
                                              if mode == "manifest_nonclaim" else [])
                        manifest["evidence"].append(extra)
                    (temporary_root / CHECKER.CLAIMS_PATH).write_text(
                        json.dumps(claims, indent=2) + "\n", encoding="utf-8")
                    (temporary_root / CHECKER.NONCLAIMS_PATH).write_text(
                        json.dumps(nonclaims, indent=2) + "\n", encoding="utf-8")
                    (temporary_root / CHECKER.EVIDENCE_MANIFEST_PATH).write_text(
                        json.dumps(manifest, indent=2) + "\n", encoding="utf-8")
                    errors = []
                    CHECKER.check_delivery_links(temporary_root, coremark, loop, errors)
                    self.assertTrue(any("set drift" in error for error in errors), errors)

    def test_bilingual_ooo_history_annotations_numbers_and_boundaries_fail_closed(self):
        pages = tuple(DOCS_CHECKER.OOO_HISTORY_REQUIRED_TEXT)
        mutations = {
            "claim_id": lambda text: text.replace(
                "claim:ooo_historical_s9a_coremark_whole_cpi",
                "claim:unexpected_claim", 1),
            "maturity": lambda text: text.replace(
                "claim:ooo_historical_s9a_coremark_whole_cpi maturity:partial",
                "claim:ooo_historical_s9a_coremark_whole_cpi maturity:verified", 1),
            "marker_value": lambda text: text.replace(
                "value:6.184799387499 epoch:pre_combinational_loop_remediation",
                "value:6.0 epoch:pre_combinational_loop_remediation", 1),
            "marker_epoch": lambda text: text.replace(
                "value:6.184799387499 epoch:pre_combinational_loop_remediation",
                "value:6.184799387499 epoch:current", 1),
            "number": lambda text: text.replace("6.184799", "6.184798", 1),
            "epoch": lambda text: text.replace(
                "组合环整改前的 epoch" if "组合环整改前的 epoch" in text
                else "historical performance-first epoch before",
                "current epoch", 1),
            "noninheritance": lambda text: text.replace(
                "不继承 P89" if "不继承 P89" in text else "does not inherit P89",
                "inherits P89", 1),
        }
        for page in pages:
            for label, mutate in mutations.items():
                with self.subTest(page=page, mutation=label), tempfile.TemporaryDirectory() as temporary:
                    temporary_root = Path(temporary)
                    for relative in pages:
                        target = temporary_root / relative
                        target.parent.mkdir(parents=True, exist_ok=True)
                        shutil.copy2(str(ROOT / relative), str(target))
                    target = temporary_root / page
                    text = target.read_text(encoding="utf-8")
                    mutated = mutate(text)
                    self.assertNotEqual(mutated, text)
                    target.write_text(mutated, encoding="utf-8")
                    errors = []
                    DOCS_CHECKER.check_ooo_history_pages(temporary_root, errors)
                    self.assertTrue(errors)

    def test_d12_per_point_identity_cannot_be_promoted_or_populated(self):
        source = load(CHECKER.D12_FUNCTIONAL_POINTS_PATH)
        mutations = (
            lambda item: item.__setitem__("status", "historical_verified"),
            lambda item: item["points"][0].__setitem__("binary_sha256", "0" * 64),
            lambda item: item["points"][0].__setitem__("result", "verified"),
            lambda item: item["per_point_missing_identity"].pop("config_sha256"),
            lambda item: item.__setitem__("whole_program_cpi", 1.0),
        )
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                candidate = copy.deepcopy(source)
                mutate(candidate)
                errors = []
                CHECKER.check_d12_functional_points(candidate, errors)
                self.assertTrue(errors)

    def test_d12_bound_config_and_point_payload_mutations_fail(self):
        loop = load(CHECKER.LOOP_PATH)
        lineage = load(CHECKER.LINEAGE_PATH)
        payloads = (
            CHECKER.D12_EFFECTIVE_PARAMETERS_PATH,
            "provenance/upstream/rv32im_ooo_4k/history/rv32im_ooo_4k_d12.f",
            "provenance/upstream/rv32im_ooo_4k/history/d12_openram_blackboxes.sv",
            CHECKER.D12_FUNCTIONAL_POINTS_PATH,
        )
        for relative in payloads:
            with self.subTest(payload=relative), tempfile.TemporaryDirectory() as temporary:
                temporary_root = Path(temporary)
                shutil.copytree(str(ROOT / "provenance"), str(temporary_root / "provenance"))
                payload = temporary_root / relative
                payload.write_bytes(payload.read_bytes() + b"\n")
                errors = []
                CHECKER.check_d12_provenance(temporary_root, loop, lineage, errors)
                self.assertTrue(any("drift" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
