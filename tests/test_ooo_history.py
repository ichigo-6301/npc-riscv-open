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
            lambda item: item["optimized"].__setitem__("source_ref", "0" * 40),
            lambda item: item["optimized"].__setitem__("binary_sha256", "0" * 63),
            lambda item: item.__setitem__("epoch", "current"),
            lambda item: item["comparability_domain"]["default_profile"].__setitem__(
                "ifetch_latency", 3),
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
            lambda item: item["source"].__setitem__("filelist_sha256", "0" * 64),
            lambda item: item["structural"]["spyglass"].__setitem__("comb_loop", 1),
            lambda item: item["structural"]["verilator"].__setitem__("unoptflat", 1),
            lambda item: item["structural"]["yosys"].__setitem__("pre_techmap_scc", 1),
            lambda item: item["structural"]["yosys"].__setitem__("post_techmap_scc", 1),
            lambda item: item["functional"].__setitem__("identity_points_passed", 13),
            lambda item: item["functional"].__setitem__("precise_retirement_preserved", False),
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


if __name__ == "__main__":
    unittest.main()
