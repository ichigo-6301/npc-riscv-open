#!/usr/bin/env python3
"""Fail-closed tests for published historical performance/system/FPGA evidence."""

from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import shutil
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
CHECKER_PATH = ROOT / "flows/scripts/check_historical_evidence.py"
SPEC = importlib.util.spec_from_file_location("check_historical_evidence", CHECKER_PATH)
CHECKER = importlib.util.module_from_spec(SPEC)
assert SPEC.loader is not None
SPEC.loader.exec_module(CHECKER)


def load(relative: str) -> dict:
    return json.loads((ROOT / relative).read_text(encoding="utf-8"))


class HistoricalEvidenceTests(unittest.TestCase):
    def test_current_evidence_passes(self) -> None:
        self.assertEqual(CHECKER.run_checks(ROOT), [])

    def test_linux_arithmetic_and_boundary_mutations_fail(self) -> None:
        source = load(CHECKER.LINUX_AB_PATH)
        mutations = (
            lambda item: item["baseline"].__setitem__("cycles", 27929340),
            lambda item: item["optimized"].__setitem__("whole_program_cpi", 1.7),
            lambda item: item["derived"].__setitem__("value", 5.0),
            lambda item: item["lineage"].__setitem__("current_source_exact_rerun", "verified"),
        )
        for mutate in mutations:
            with self.subTest(mutate=mutate):
                candidate = copy.deepcopy(source)
                mutate(candidate)
                errors: list[str] = []
                CHECKER.check_linux_ab(candidate, errors)
                self.assertTrue(errors)

    def test_linux_boot_marker_and_current_source_mutations_fail(self) -> None:
        source = load(CHECKER.LINUX_BOOT_PATH)
        for mutate in (
            lambda item: item["observed_markers"].remove("=== shell ready ==="),
            lambda item: item["lineage"].__setitem__("current_source_deep_boot_status", "verified"),
        ):
            candidate = copy.deepcopy(source)
            mutate(candidate)
            errors: list[str] = []
            CHECKER.check_linux_boot(candidate, errors)
            self.assertTrue(errors)

    def test_ooo_denominator_ref_and_epoch_mutations_fail(self) -> None:
        source = load(CHECKER.OOO_PATH)
        mutations = (
            lambda item: item.__setitem__("epoch", "current"),
            lambda item: item["frontend_supply"].__setitem__("source_ref", "0" * 40),
            lambda item: item["branch_prediction"].__setitem__("redirect_denominator", "cycles"),
        )
        for mutate in mutations:
            candidate = copy.deepcopy(source)
            mutate(candidate)
            errors: list[str] = []
            CHECKER.check_ooo(candidate, errors)
            self.assertTrue(errors)

    def test_fpga_hash_maturity_and_old_xsa_promotion_fail(self) -> None:
        source = load(CHECKER.FPGA_PATH)
        mutations = (
            lambda item: item["snapshots"][0]["artifacts"].__setitem__("uart_log_sha256", "0" * 64),
            lambda item: item["snapshots"][0]["maturity"].pop("fpga_timing"),
            lambda item: item["snapshots"][1]["maturity"].__setitem__("fpga_bitstream", "verified"),
            lambda item: item["snapshots"][2]["artifacts"].__setitem__("copied_older_xsa_sha256", "f" * 64),
        )
        for mutate in mutations:
            candidate = copy.deepcopy(source)
            mutate(candidate)
            errors: list[str] = []
            CHECKER.check_fpga(candidate, errors)
            self.assertTrue(errors)

    def test_claim_reverse_link_mutation_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            paths = (
                CHECKER.LINUX_AB_PATH,
                CHECKER.LINUX_BOOT_PATH,
                CHECKER.OOO_PATH,
                CHECKER.FPGA_PATH,
                CHECKER.CLAIMS_PATH,
                CHECKER.MANIFEST_PATH,
            )
            for relative in paths:
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / relative, target)
            claims = load(CHECKER.CLAIMS_PATH)
            claim = next(item for item in claims["claims"] if item["id"] == "linux_historical_approx_speedup")
            claim["evidence"] = ["linux_boot_history_public"]
            (root / CHECKER.CLAIMS_PATH).write_text(json.dumps(claims), encoding="utf-8")
            records = [load(path) for path in (
                CHECKER.LINUX_AB_PATH, CHECKER.LINUX_BOOT_PATH,
                CHECKER.OOO_PATH, CHECKER.FPGA_PATH,
            )]
            errors: list[str] = []
            CHECKER.check_claim_and_manifest_links(root, records, errors)
            self.assertTrue(any("reverse link" in error or "evidence link" in error for error in errors), errors)

    def test_bilingual_numeric_drift_fails(self) -> None:
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for relative in (
                "README.md", "README.en.md",
                "docs/evidence/performance_history.md",
                "docs/evidence/performance_history.en.md",
                "docs/evidence/system_fpga_history.md",
                "docs/evidence/system_fpga_history.en.md",
            ):
                target = root / relative
                target.parent.mkdir(parents=True, exist_ok=True)
                shutil.copy2(ROOT / relative, target)
            english = root / "docs/evidence/performance_history.en.md"
            english.write_text(english.read_text(encoding="utf-8").replace("17.73", "17.72"), encoding="utf-8")
            errors: list[str] = []
            CHECKER.check_docs(root, errors)
            self.assertTrue(any("17.73" in error for error in errors), errors)


if __name__ == "__main__":
    unittest.main()
