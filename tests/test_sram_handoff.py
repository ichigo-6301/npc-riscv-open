import hashlib
import json
import os
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "flows/scripts"
sys.path.insert(0, str(SCRIPTS))

from prepare_sram_handoff import audit_liberty_override, parse_liberty_overrides
import asicctl


def sha256(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


class SramHandoffTests(unittest.TestCase):
    def test_liberty_overrides_require_exact_macro_coverage(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "macro.lib"
            path.write_text("library (fixture) {}\n")
            result = parse_liberty_overrides([f"macro={path}"], {"macro"})
            self.assertEqual(result, {"macro": path.resolve()})
            with self.assertRaisesRegex(ValueError, "cover every macro"):
                parse_liberty_overrides([], {"macro"})
            with self.assertRaisesRegex(ValueError, "duplicate"):
                parse_liberty_overrides([f"macro={path}", f"macro={path}"], {"macro"})

    def test_liberty_override_audits_identity_pvt_period_and_grid(self):
        name = "macro"
        liberty = '''
library (macro_TT_1p0V_25C_lib) {
  time_unit : "1ns";
  nom_voltage : 1.0;
  nom_temperature : 25;
  cell (macro) {
    pin (dout) { max_capacitance : 0.0066912; max_transition : 0.32; }
    pin (clk) {
      timing () {
        timing_type : "minimum_period";
        values ("1.106");
      }
    }
  }
}
'''
        grid = {
            "time_unit": "1ns", "voltage_v": 1.0, "temperature_c": 25,
            "max_capacitance_f": 0.0066912, "max_transition_ns": 0.32,
        }
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "macro.lib"
            path.write_text(liberty)
            expected = {"timing_view_sha256": sha256(path), "minimum_period_ns": 1.106}
            audit_liberty_override(name, path, expected, grid)
            expected["minimum_period_ns"] = 1.076
            with self.assertRaisesRegex(ValueError, "minimum period"):
                audit_liberty_override(name, path, expected, grid)

    def test_loader_hashes_canonical_and_timing_liberty_separately(self):
        name = "macro"
        grid = {"revision": "grid-v1", "analytical_delay": True}
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            files = {}
            for role in ("v", "lib", "canonical_lib", "lef", "gds", "normalized_lef"):
                path = root / f"macro.{role}"
                path.write_text(role)
                files[role] = {
                    "path": path.name, "sha256": sha256(path), "bytes": path.stat().st_size,
                }
            manifest = {
                "schema": "npc-riscv-open/d8-sram-handoff-v2",
                "memory_mode": "sram",
                "openram_commit": "a" * 40,
                "macro_count": 1,
                "liberty_override": grid,
                "macros": {name: {"expected_instances": 1, "files": files}},
            }
            manifest_path = root / "handoff_manifest.json"
            manifest_path.write_text(json.dumps(manifest))
            contract = {
                "expected_macro_count": 1,
                "memory_data": {
                    "openram_commit": "a" * 40,
                    "liberty_override": grid,
                    "macros": {name: {
                        "expected_instances": 1,
                        "timing_view_sha256": files["lib"]["sha256"],
                        "original_view_sha256": {
                            role: files[role]["sha256"]
                            for role in ("v", "lib", "lef", "gds")
                        } | {"lib": files["canonical_lib"]["sha256"]},
                    }},
                },
            }
            with mock.patch.dict(os.environ, {"NPC_ASIC_SRAM_HANDOFF": str(root)}):
                loaded = asicctl.load_sram_handoff(contract)
            self.assertEqual(loaded["files"][name]["lib"], root / "macro.lib")
            (root / "macro.canonical_lib").write_text("tampered")
            with mock.patch.dict(os.environ, {"NPC_ASIC_SRAM_HANDOFF": str(root)}):
                with self.assertRaisesRegex(asicctl.AsicError, "SHA256 mismatch"):
                    asicctl.load_sram_handoff(contract)


if __name__ == "__main__":
    unittest.main()
