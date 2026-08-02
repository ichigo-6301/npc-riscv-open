import copy
import importlib.util
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CHECKER_PATH = ROOT / "flows/scripts/check_implementation.py"
DOCS_CHECKER_PATH = ROOT / "flows/scripts/check_docs.py"
GENERATOR_PATH = ROOT / "flows/scripts/generate_showcase_assets.py"

SPEC = importlib.util.spec_from_file_location("check_implementation", CHECKER_PATH)
CHECKER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(CHECKER)

DOCS_SPEC = importlib.util.spec_from_file_location("check_docs", DOCS_CHECKER_PATH)
DOCS_CHECKER = importlib.util.module_from_spec(DOCS_SPEC)
assert DOCS_SPEC.loader is not None
DOCS_SPEC.loader.exec_module(DOCS_CHECKER)


class ImplementationEvidenceTests(unittest.TestCase):
    def test_current_bounded_evidence_and_showcase_pass(self):
        self.assertEqual(CHECKER.run_checks(ROOT, governance=False), [])

    def test_expected_four_fixed_points_and_independent_claims(self):
        evidence = json.loads((ROOT / CHECKER.IMPLEMENTATION_PATH).read_text())
        self.assertEqual(
            set(evidence["closure_points"]), set(CHECKER.EXPECTED_POINTS)
        )
        self.assertEqual(len(CHECKER.EXPECTED_CLAIMS), 16)
        for point_id, expected in CHECKER.EXPECTED_POINTS.items():
            point = evidence["closure_points"][point_id]
            self.assertEqual(tuple(point["claim_ids"]), expected["claims"])
            self.assertEqual(point["frequency"]["dc_mhz"], expected["dc_mhz"])
            self.assertEqual(
                point["frequency"]["postroute_mhz"], expected["postroute_mhz"]
            )

    def test_role_hash_mismatch_is_rejected(self):
        evidence = json.loads((ROOT / CHECKER.IMPLEMENTATION_PATH).read_text())
        point_id = "rv32im_single_perf.registers"
        point = copy.deepcopy(evidence["closure_points"][point_id])
        point["role_hashes"]["pnr_input_netlist"] = "0" * 64
        errors = []
        CHECKER.check_point(point_id, point, errors)
        self.assertTrue(
            any("mapped netlist handoff identity mismatch" in error for error in errors),
            errors,
        )

    def test_d11_point_identity_sections_reject_well_formed_substitution(self):
        evidence = json.loads((ROOT / CHECKER.IMPLEMENTATION_PATH).read_text())
        mutations = (
            ("identity", "execution_head", "0" * 40),
            ("run_identity", "dc_run_id", "forged_dc_run"),
        )
        for point_id in CHECKER.EXPECTED_POINTS:
            for section, field, replacement in mutations:
                with self.subTest(point_id=point_id, section=section):
                    point = copy.deepcopy(evidence["closure_points"][point_id])
                    point[section][field] = replacement
                    errors = []
                    CHECKER.check_point(point_id, point, errors)
                    self.assertTrue(
                        any(
                            "{}.{} identity digest drift".format(point_id, section)
                            in error
                            for error in errors
                        ),
                        errors,
                    )

            with self.subTest(point_id=point_id, section="role_hashes"):
                point = copy.deepcopy(evidence["closure_points"][point_id])
                point["role_hashes"] = {
                    role: "0" * 64 for role in point["role_hashes"]
                }
                errors = []
                CHECKER.check_point(point_id, point, errors)
                self.assertTrue(
                    any(
                        "{}.role_hashes identity digest drift".format(point_id)
                        in error
                        for error in errors
                    ),
                    errors,
                )

    def test_d11_global_identity_sections_reject_well_formed_substitution(self):
        source = json.loads((ROOT / CHECKER.IMPLEMENTATION_PATH).read_text())
        mutations = (
            ("audit_source", lambda item: item.__setitem__("sha256", "0" * 64)),
            (
                "platform_identity",
                lambda item: item["tools"]["openroad"].__setitem__(
                    "container_digest", "sha256:" + "0" * 64
                ),
            ),
            (
                "sram_identity",
                lambda item: item.__setitem__("openram_commit", "0" * 40),
            ),
        )
        for section, mutate in mutations:
            with self.subTest(section=section), tempfile.TemporaryDirectory() as temporary:
                root = Path(temporary)
                path = root / CHECKER.IMPLEMENTATION_PATH
                path.parent.mkdir(parents=True)
                evidence = copy.deepcopy(source)
                mutate(evidence[section])
                path.write_text(json.dumps(evidence), encoding="utf-8")
                errors = []
                CHECKER.check_implementation(root, errors)
                self.assertTrue(
                    any(
                        "{} identity digest drift".format(section) in error
                        for error in errors
                    ),
                    errors,
                )

    def test_primetime_untested_check_coverage_is_fail_closed(self):
        evidence = json.loads((ROOT / CHECKER.IMPLEMENTATION_PATH).read_text())
        for point_id in CHECKER.EXPECTED_POINTS:
            with self.subTest(point_id=point_id):
                point = copy.deepcopy(evidence["closure_points"][point_id])
                point["primetime_result"]["analysis_coverage_untested"]["total"] += 1
                errors = []
                CHECKER.check_point(point_id, point, errors)
                self.assertTrue(
                    any("untested-check coverage drift" in error for error in errors),
                    errors,
                )

    def test_missing_constraint_hash_role_is_rejected_for_every_point(self):
        evidence = json.loads((ROOT / CHECKER.IMPLEMENTATION_PATH).read_text())
        for point_id, expected_hashes in CHECKER.EXPECTED_POINT_HASHES.items():
            with self.subTest(point_id=point_id):
                point = copy.deepcopy(evidence["closure_points"][point_id])
                missing_role = next(iter(expected_hashes["constraint_hashes"]))
                del point["constraint_hashes"][missing_role]
                errors = []
                CHECKER.check_point(point_id, point, errors)
                self.assertTrue(
                    any(
                        "constraint_hashes role set mismatch" in error
                        and missing_role in error
                        for error in errors
                    ),
                    errors,
                )

    def test_unrelated_constraint_hash_map_is_rejected_for_every_point(self):
        evidence = json.loads((ROOT / CHECKER.IMPLEMENTATION_PATH).read_text())
        for point_id in CHECKER.EXPECTED_POINT_HASHES:
            with self.subTest(point_id=point_id):
                point = copy.deepcopy(evidence["closure_points"][point_id])
                point["constraint_hashes"] = {"unrelated_constraint": "a" * 64}
                errors = []
                CHECKER.check_point(point_id, point, errors)
                self.assertTrue(
                    any(
                        "constraint_hashes role set mismatch" in error
                        and "unrelated_constraint" in error
                        for error in errors
                    ),
                    errors,
                )

    def test_missing_report_hash_role_is_rejected_for_every_point(self):
        evidence = json.loads((ROOT / CHECKER.IMPLEMENTATION_PATH).read_text())
        for point_id, expected_hashes in CHECKER.EXPECTED_POINT_HASHES.items():
            with self.subTest(point_id=point_id):
                point = copy.deepcopy(evidence["closure_points"][point_id])
                missing_role = next(iter(expected_hashes["report_hashes"]))
                del point["report_hashes"][missing_role]
                errors = []
                CHECKER.check_point(point_id, point, errors)
                self.assertTrue(
                    any(
                        "report_hashes role set mismatch" in error
                        and missing_role in error
                        for error in errors
                    ),
                    errors,
                )

    def test_unrelated_report_hash_map_is_rejected_for_every_point(self):
        evidence = json.loads((ROOT / CHECKER.IMPLEMENTATION_PATH).read_text())
        for point_id in CHECKER.EXPECTED_POINT_HASHES:
            with self.subTest(point_id=point_id):
                point = copy.deepcopy(evidence["closure_points"][point_id])
                point["report_hashes"] = {"unrelated_report": "b" * 64}
                errors = []
                CHECKER.check_point(point_id, point, errors)
                self.assertTrue(
                    any(
                        "report_hashes role set mismatch" in error
                        and "unrelated_report" in error
                        for error in errors
                    ),
                    errors,
                )

    def test_valid_but_different_required_hash_is_rejected_for_every_point(self):
        evidence = json.loads((ROOT / CHECKER.IMPLEMENTATION_PATH).read_text())
        for point_id, expected_hashes in CHECKER.EXPECTED_POINT_HASHES.items():
            for section in ("constraint_hashes", "report_hashes"):
                with self.subTest(point_id=point_id, section=section):
                    point = copy.deepcopy(evidence["closure_points"][point_id])
                    role = next(iter(expected_hashes[section]))
                    replacement = "0" * 64
                    if expected_hashes[section][role] == replacement:
                        replacement = "f" * 64
                    point[section][role] = replacement
                    errors = []
                    CHECKER.check_point(point_id, point, errors)
                    self.assertTrue(
                        any(
                            "{}.{} hash identity drift".format(section, role)
                            in error
                            for error in errors
                        ),
                        errors,
                    )

    def test_sram_caveat_and_macro_maturity_are_fail_closed(self):
        evidence = json.loads((ROOT / CHECKER.IMPLEMENTATION_PATH).read_text())
        point_id = "rv32ima_sv32_linux.sram"
        point = copy.deepcopy(evidence["closure_points"][point_id])
        point["caveats"] = [
            caveat for caveat in point["caveats"] if "RC-004" not in caveat
        ]
        point["result_maturity"]["macro_physical_signoff_status"] = "verified"
        errors = []
        CHECKER.check_point(point_id, point, errors)
        self.assertTrue(any("RC-004" in error for error in errors), errors)
        self.assertTrue(any("macro signoff boundary" in error for error in errors), errors)

    def test_bilingual_markers_and_numeric_rows_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "control").mkdir()
            (root / "docs/evidence").mkdir(parents=True)
            readme_source = ROOT / "control"
            if not readme_source.is_dir():
                readme_source = ROOT
            for name in ("README.md", "README.en.md"):
                shutil.copy2(readme_source / name, root / "control" / name)
            for relative in (
                "docs/evidence/backend_closure.md",
                "docs/evidence/backend_closure.en.md",
                "docs/performance.md",
                "docs/performance.en.md",
            ):
                shutil.copy2(ROOT / relative, root / relative)

            errors = []
            CHECKER.check_document_surfaces(root, errors)
            self.assertEqual(errors, [])

            backend_english = root / "docs/evidence/backend_closure.en.md"
            backend_english.write_text(
                backend_english.read_text().replace(
                    "540 / 425 MHz", "540 / 424 MHz", 1),
                encoding="utf-8",
            )
            errors = []
            CHECKER.check_document_surfaces(root, errors)
            self.assertTrue(any("numeric row" in error for error in errors), errors)

            shutil.copy2(
                ROOT / "docs/evidence/backend_closure.en.md", backend_english)
            english = root / "control/README.en.md"
            marker = (
                "<!-- claim:single_registers_nangate45_dc_frequency "
                "maturity:verified -->"
            )
            english.write_text(english.read_text().replace(marker, "", 1), encoding="utf-8")
            errors = []
            CHECKER.check_document_surfaces(root, errors)
            self.assertTrue(any("claim marker drift" in error for error in errors), errors)

    def test_readme_key_results_summary_is_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name in ("README.md", "README.en.md"):
                shutil.copy2(ROOT / name, root / name)
            errors = []
            DOCS_CHECKER.check_readme_showcase(root, errors)
            self.assertEqual(errors, [])

            english = root / "README.en.md"
            english.write_text(
                english.read_text().replace("1.4849", "1.4848", 1),
                encoding="utf-8",
            )
            errors = []
            DOCS_CHECKER.check_readme_showcase(root, errors)
            self.assertTrue(
                any("key-results row" in error and "1.4849" in error for error in errors),
                errors,
            )

    def test_source_set_and_functional_overlay_alignment_fail_closed(self):
        implementation = json.loads((ROOT / CHECKER.IMPLEMENTATION_PATH).read_text())
        errors = []
        CHECKER.check_source_alignment(ROOT, implementation, errors)
        self.assertEqual(errors, [])

        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "provenance").mkdir()
            source = ROOT / "provenance/source_allowlist.json"
            if not source.is_file():
                source = ROOT / "export/source_allowlist.json"
            manifest = json.loads(source.read_text())
            single = next(
                item for item in manifest["profiles"]
                if item["profile_id"] == "rv32im_single_perf"
            )
            single["implementation_source_sets"]["sram"]["source_set_sha256"] = "0" * 64
            single["memory_mode_overlays"][0]["comparison"] = "LEXICALLY_EQUIVALENT"
            (root / "provenance/source_allowlist.json").write_text(
                json.dumps(manifest), encoding="utf-8"
            )
            errors = []
            CHECKER.check_source_alignment(root, implementation, errors)
            self.assertTrue(any("source-set SHA256" in error for error in errors), errors)
            self.assertTrue(any("overlay identity" in error for error in errors), errors)

    def test_claim_evidence_binding_is_bidirectional(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / "delivery/claims").mkdir(parents=True)
            (root / "delivery/evidence").mkdir(parents=True)
            (root / CHECKER.IMPLEMENTATION_PATH.parent).mkdir(parents=True)
            shutil.copy2(
                ROOT / CHECKER.IMPLEMENTATION_PATH,
                root / CHECKER.IMPLEMENTATION_PATH,
            )
            claims = []
            for claim_id, expected in CHECKER.EXPECTED_CLAIMS.items():
                claims.append(
                    {
                        "id": claim_id,
                        "profile": expected["profile"],
                        "statement": "fixture statement",
                        "metric": expected["metric"],
                        "value": expected["value"],
                        "unit": expected["unit"],
                        "benchmark": "fixture benchmark",
                        "configuration": "fixture configuration",
                        "source_ref": expected["source_ref"],
                        "tool": "fixture tool",
                        "evidence": [CHECKER.IMPLEMENTATION_EVIDENCE_ID],
                        "status": "verified",
                        "caveat": "fixture caveat",
                        "public": True,
                    }
                )
            evidence = [
                {
                    "id": CHECKER.IMPLEMENTATION_EVIDENCE_ID,
                    "claims": list(CHECKER.EXPECTED_CLAIMS),
                    "sha256": CHECKER.sha256(root / CHECKER.IMPLEMENTATION_PATH),
                    "status": "verified",
                    "public": True,
                }
            ]
            evidence.extend({"id": evidence_id} for evidence_id in CHECKER.SHOWCASE_EVIDENCE_IDS)
            (root / "delivery/claims/claims.yaml").write_text(
                json.dumps({"claims": claims}), encoding="utf-8"
            )
            (root / "delivery/evidence/manifest.yaml").write_text(
                json.dumps({"evidence": evidence}), encoding="utf-8"
            )
            errors = []
            CHECKER.check_governance(root, errors)
            self.assertEqual(errors, [])
            claims[0]["evidence"] = []
            (root / "delivery/claims/claims.yaml").write_text(
                json.dumps({"claims": claims}), encoding="utf-8"
            )
            errors = []
            CHECKER.check_governance(root, errors)
            self.assertTrue(any("evidence binding mismatch" in error for error in errors))

    def test_generator_check_rejects_stale_svg(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative in ("evidence", "docs/assets"):
                shutil.copytree(ROOT / relative, root / relative)
            (root / "flows/scripts").mkdir(parents=True)
            shutil.copy2(GENERATOR_PATH, root / "flows/scripts/generate_showcase_assets.py")
            clean = subprocess.run(
                [sys.executable, str(root / "flows/scripts/generate_showcase_assets.py"),
                 "--root", str(root), "--check"],
                check=False, capture_output=True, text=True,
            )
            self.assertEqual(clean.returncode, 0, clean.stderr)
            asset = root / "docs/assets/nangate45_closure_points.svg"
            asset.write_text(asset.read_text() + "\n<!-- stale -->\n")
            stale = subprocess.run(
                [sys.executable, str(root / "flows/scripts/generate_showcase_assets.py"),
                 "--root", str(root), "--check"],
                check=False, capture_output=True, text=True,
            )
            self.assertEqual(stale.returncode, 1)
            self.assertIn("stale or missing", stale.stderr)


if __name__ == "__main__":
    unittest.main()
