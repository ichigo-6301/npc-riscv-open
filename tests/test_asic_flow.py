import importlib.util
import copy
import csv
import hashlib
import io
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest import mock


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "flows/scripts"
sys.path.insert(0, str(SCRIPTS))

import asicctl
import flowctl
from build_a3_cpi_identity import build as build_a3_cpi_identity
from calculate_floorplan import calculate, calculate_with_macros
from compare_a3_dc import A3_COMMIT, LEGACY_COMMIT, evaluate as evaluate_a3_dc
from prepare_pnr_sdc import retarget
from recover_pnr_handoff import RecoveryError, recover as recover_pnr_handoff
from sanitize_openroad_sdc import main as sanitize_openroad_sdc
from summarize_dc import parse_run
from summarize_pnr import parse_run as parse_pnr_run
from summarize_sta import parse_run as parse_sta_run


class AsicFlowTests(unittest.TestCase):
    def a3_matrix(self, mode, source_commit, delay, *, source_set="source-a3"):
        row = {
            "frequency_mhz": 400.0,
            "completed": True,
            "timing_loop_report_valid": True,
            "timing_loop_evidence": 0,
            "automatic_arc_break_evidence": 0,
            "check_design_ok": 1,
            "check_timing_ok": 1,
            "unresolved_reference_count": 0,
            "latch_count": 0,
            "unclocked_sync_endpoint_count": 0,
            "macro_count": 0,
            "blackbox_count": 0,
            "data_path_delay_ns": delay,
            "tns_ns": -9.0 if mode == "a3" else -10.0,
            "violating_paths": 90 if mode == "a3" else 100,
            "area": 104.0 if mode == "a3" else 100.0,
            "cell_count": 104 if mode == "a3" else 100,
            "setup_closed": True,
        }
        files = {
            role: {"sha256": "a" * 64}
            for role in ("constraint_sdc", "dc_setup", "stdcell_liberty", "stdcell_db")
        }
        return {
            "manifest": {
                "mode": mode,
                "source_commit": source_commit,
                "source_set_sha256": source_set,
                "liberty_sha256": "b" * 64,
                "db_sha256": "c" * 64,
                "frequencies_mhz": [400],
                "scan_policy": "wns_guided_quantized_v2",
                "memory_mode": "registers",
                "macro_count": 0,
                "timer_clock_hz": None,
                "files": files,
            },
            "rows": [row],
        }

    def a3_cpi_identity(self):
        return {
            "schema": "npc-riscv-open/a3-cycle-identity-v1",
            "source_commit": A3_COMMIT,
            "difftest_reference": {
                "profile": "rv32im_4k_v1",
                "nemu_commit": "a" * 40,
                "nemu_so_sha256": "b" * 64,
                "nemu_config_sha256": "c" * 64,
                "source_evidence_manifest_sha256": "d" * 64,
                "nemu_config_contract": {
                    "CONFIG_ISA": '"riscv32"',
                    "CONFIG_RISCV_FPGA_MMIO_LAYOUT": "y",
                    "CONFIG_DEVICE": "y",
                    "CONFIG_RTC_MMIO": "0xa0000048",
                },
                "mmio_policy": "private_ooo_dut_authoritative_skip_and_reference_resync",
                "public_bounded_adapter_used": False,
            },
            "rows": [
                {
                    "profile": profile,
                    "workload": workload,
                    "cycle_identity": True,
                    "instruction_identity": True,
                    "trace_identity": True,
                    "guard_status": "PASS",
                }
                for profile in ("ideal", "default")
                for workload in (
                    "coremark", "matrix-mul", "crc32", "quick-sort", "load-store",
                    "dhrystone", "microbench",
                )
            ],
        }

    def fixture(self, *, dpi=False):
        temporary = tempfile.TemporaryDirectory()
        root = Path(temporary.name)
        (root / "flows/asic/profiles").mkdir(parents=True)
        (root / "flows/asic/constraints").mkdir(parents=True)
        (root / "filelists/asic").mkdir(parents=True)
        (root / "provenance").mkdir()
        (root / "rtl").mkdir()
        top = root / "rtl/top.sv"
        top.write_text(
            "module cpu_top(input clk, input rst_n, "
            "output [31:0] ibus_axi_araddr, input [31:0] ibus_axi_rdata, "
            "output [31:0] dbus_axi_awaddr, input [31:0] dbus_axi_rdata); "
            "endmodule\n"
        )
        sram_top = root / "rtl/sram_top.sv"
        sram_top.write_text(
            "module cpu_top(input clk, input rst_n, "
            "output [31:0] ibus_axi_araddr, input [31:0] ibus_axi_rdata, "
            "output [31:0] dbus_axi_awaddr, input [31:0] dbus_axi_rdata); "
            "wire sram_binding = 1'b1; endmodule\n"
        )
        define = "+define+NPC_ASIC\n+define+NPC_USE_DPI\n" if dpi else "+define+NPC_ASIC\n"
        (root / "filelists/asic/rv32im_single_perf.f").write_text(
            define + "rtl/top.sv\n")
        (root / "filelists/asic/rv32im_single_perf_registers.f").write_text(
            define + "rtl/top.sv\n")
        (root / "filelists/asic/rv32im_single_perf_sram.f").write_text(
            define + "rtl/sram_top.sv\n")
        (root / "flows/asic/constraints/internal_clock.sdc").write_text(
            "create_clock -name npc_clk -period 2.0 [get_ports clk]\n")
        commit = "f76de57479b798aca7468f999c386bb4cb5fce02"
        base_digest = hashlib.sha256(top.read_bytes()).hexdigest()
        sram_digest = hashlib.sha256(sram_top.read_bytes()).hexdigest()
        register_source_set = asicctl.sha256_json({
            "source_commit": commit,
            "entries": [["rtl/top.sv", base_digest]],
        })
        sram_source_set = asicctl.sha256_json({
            "source_commit": commit,
            "entries": [["rtl/top.sv", sram_digest]],
        })
        (root / "provenance/source_allowlist.json").write_text(json.dumps({
            "project_id": "npc-riscv-open", "snapshot_id": "v0.1.0",
            "profiles": [{"profile_id": "rv32im_single_perf", "source_commit": commit,
                          "implementation_source_sets": {
                              "registers": {"source_set_sha256": register_source_set},
                              "sram": {"source_set_sha256": sram_source_set},
                          },
                          "memory_mode_overlays": [{
                              "destination": "rtl/sram_top.sv",
                              "logical_destination": "rtl/top.sv",
                              "sha256": sram_digest,
                              "bytes": sram_top.stat().st_size,
                              "roles": ["asic_sram"],
                              "source_commit": "1" * 40,
                              "memory_mode": "sram",
                              "comparison": "FUNCTIONAL_TOKEN_DIFFERENCE_NPC_ASIC_SRAM",
                              "overlay_reason": "fixture audited SRAM binding",
                          }],
                          "entries": [{
                              "destination": "rtl/top.sv",
                              "sha256": base_digest,
                              "bytes": top.stat().st_size,
                              "roles": ["simulation", "asic"],
                              "source_commit": commit,
                          }]}],
        }))
        (root / "flows/asic/profiles/register_expanded.json").write_text(json.dumps({
            "schema": "npc-riscv-open/asic-dual-memory-v1",
            "memory_modes": {
                "registers": {
                    "allowed_profiles": ["rv32im_single_perf"],
                    "expected_macro_count": 0,
                    "expected_blackbox_count": 0,
                    "extra_defines": [],
                },
            },
            "libraries": {},
            "orfs": {
                "commit": "a" * 40,
                "image_digest": "sha256:" + "b" * 64,
                "platform": "nangate45",
                "runtime_identity_policy":
                    asicctl.ORFS_RUNTIME_IDENTITY_POLICY,
            },
            "profiles": {"rv32im_single_perf": {
                "source_commit": commit, "top": "cpu_top", "clock_port": "clk",
                "reset_port": "rst_n", "filelist": "filelists/asic/rv32im_single_perf.f",
                "filelists_by_memory_mode": {
                    "registers": "filelists/asic/rv32im_single_perf_registers.f",
                    "sram": "filelists/asic/rv32im_single_perf_sram.f",
                },
                "dc_frequencies_mhz": [800, 700],
            }},
        }))
        config = root / ".config"
        config.write_text(
            "CONFIG_NPC_PROFILE_RV32IM_SINGLE_PERF=y\n"
            "# CONFIG_NPC_PROFILE_RV32IMA_SV32_LINUX is not set\n"
            "# CONFIG_NPC_PROFILE_RV32IM_OOO_4K is not set\n"
            'CONFIG_NPC_PROFILE_ID="rv32im_single_perf"\n'
            "CONFIG_NPC_ASIC_REGISTER_EXPANDED=y\n"
            'CONFIG_NPC_ASIC_MEMORY_MODE="registers"\n'
        )
        return temporary, root, config

    def test_config_contract_accepts_no_dpi_asic_filelist(self):
        temporary, root, config = self.fixture()
        try:
            contract = asicctl.build_contract(root, config, "auto")
            self.assertEqual(contract["profile"], "rv32im_single_perf")
            self.assertEqual(contract["mode"], "default")
        finally:
            temporary.cleanup()

    def test_flowctl_accepts_only_declared_asic_config_keys(self):
        self.assertIn("CONFIG_NPC_ASIC_REGISTER_EXPANDED", flowctl.ALLOWED_CONFIG_KEYS)
        self.assertIn("CONFIG_NPC_ASIC_MEMORY_MODE", flowctl.ALLOWED_CONFIG_KEYS)

    def test_config_contract_rejects_dpi(self):
        temporary, root, config = self.fixture(dpi=True)
        try:
            with self.assertRaisesRegex(asicctl.AsicError, "DPI"):
                asicctl.build_contract(root, config, "auto")
        finally:
            temporary.cleanup()

    def test_config_contract_selects_explicit_sram_mode(self):
        temporary, root, config = self.fixture()
        try:
            matrix_path = root / "flows/asic/profiles/register_expanded.json"
            matrix = json.loads(matrix_path.read_text())
            matrix["memory_modes"]["sram"] = {
                "allowed_profiles": ["rv32im_single_perf"],
                "expected_macro_count": 4,
                "expected_blackbox_count": 0,
                "extra_defines": ["NPC_ASIC_SRAM"],
            }
            matrix_path.write_text(json.dumps(matrix))
            config.write_text(config.read_text().replace(
                'CONFIG_NPC_ASIC_MEMORY_MODE="registers"',
                'CONFIG_NPC_ASIC_MEMORY_MODE="sram"'))
            contract = asicctl.build_contract(root, config, "auto", "sram")
            self.assertEqual(contract["memory_mode"], "sram")
            self.assertEqual(contract["expected_macro_count"], 4)
            self.assertEqual(contract["expected_blackbox_count"], 0)
        finally:
            temporary.cleanup()

    def test_source_role_hash_drift_is_rejected(self):
        temporary, root, config = self.fixture()
        try:
            contract = asicctl.build_contract(root, config, "auto")
            self.assertRegex(contract["source_role_sha256"], r"^[0-9a-f]{64}$")
            (root / "rtl/top.sv").write_text(
                (root / "rtl/top.sv").read_text() + "// unreviewed drift\n")
            with self.assertRaisesRegex(asicctl.AsicError, "source role SHA256 mismatch"):
                asicctl.build_contract(root, config, "auto")
        finally:
            temporary.cleanup()

    def test_memory_modes_have_distinct_implementation_source_identity(self):
        temporary, root, config = self.fixture()
        try:
            registers = asicctl.build_contract(root, config, "auto")
            matrix_path = root / "flows/asic/profiles/register_expanded.json"
            matrix = json.loads(matrix_path.read_text())
            matrix["memory_modes"]["sram"] = {
                "allowed_profiles": ["rv32im_single_perf"],
                "expected_macro_count": 4,
                "expected_blackbox_count": 0,
                "extra_defines": ["NPC_ASIC_SRAM"],
                "macros": {},
            }
            matrix["profiles"]["rv32im_single_perf"]["sram_dc_frequencies_mhz"] = [700, 200]
            matrix_path.write_text(json.dumps(matrix))
            config.write_text(config.read_text().replace(
                'CONFIG_NPC_ASIC_MEMORY_MODE="registers"',
                'CONFIG_NPC_ASIC_MEMORY_MODE="sram"'))
            sram = asicctl.build_contract(root, config, "auto")
            self.assertNotEqual(registers["source_role_sha256"], sram["source_role_sha256"])
            self.assertNotEqual(registers["source_set_sha256"], sram["source_set_sha256"])
            self.assertNotEqual(
                registers["implementation_source_sha256"],
                sram["implementation_source_sha256"])
        finally:
            temporary.cleanup()

    def test_single_linux_source_locks_and_four_asic_defconfigs(self):
        matrix = json.loads((
            ROOT / "flows/asic/profiles/register_expanded.json").read_text())
        expected = {
            "rv32im_single_perf": "f76de57479b798aca7468f999c386bb4cb5fce02",
            "rv32ima_sv32_linux": "0fc3de40c4e0b231c65945c9dc1711f084688c04",
        }
        self.assertEqual(
            {profile: matrix["profiles"][profile]["source_commit"] for profile in expected},
            expected)
        self.assertEqual(
            matrix["profiles"]["rv32im_single_perf"]["pnr_frequencies_mhz"],
            {"registers": 425, "sram": 475},
        )
        self.assertEqual(
            matrix["profiles"]["rv32ima_sv32_linux"]["pnr_frequencies_mhz"],
            {"registers": 200, "sram": 200},
        )
        for profile, mode in (
                ("rv32im_single_perf", "registers"),
                ("rv32im_single_perf", "sram"),
                ("rv32ima_sv32_linux", "registers"),
                ("rv32ima_sv32_linux", "sram")):
            suffix = "_sram" if mode == "sram" else ""
            config = asicctl.parse_config(
                ROOT / f"configs/{profile}{suffix}_asic_defconfig")
            self.assertEqual(asicctl.selected_profile(config), profile)
            self.assertEqual(config["CONFIG_NPC_ASIC_MEMORY_MODE"], mode)

    def test_single_overlay_and_linux_source_identity_are_explicit(self):
        manifest_path = ROOT / "provenance/source_allowlist.json"
        if not manifest_path.is_file():
            manifest_path = ROOT / "export/source_allowlist.json"
        manifest = json.loads(manifest_path.read_text())
        profiles = {item["profile_id"]: item for item in manifest["profiles"]}
        single = profiles["rv32im_single_perf"]
        linux = profiles["rv32ima_sv32_linux"]
        self.assertEqual(
            single["source_commit"], "f76de57479b798aca7468f999c386bb4cb5fce02")
        self.assertEqual(
            linux["source_commit"], "0fc3de40c4e0b231c65945c9dc1711f084688c04")
        overlays = single.get("memory_mode_overlays", [])
        self.assertEqual(len(overlays), 3)
        self.assertEqual(
            {item["source_commit"] for item in overlays},
            {"176d4fd74da61ec681816630854501b233213982"})
        self.assertTrue(all(item.get("overlay_reason") for item in overlays))
        self.assertEqual(
            {item.get("comparison") for item in overlays},
            {"FUNCTIONAL_TOKEN_DIFFERENCE_NPC_ASIC_SRAM"},
        )
        self.assertEqual(
            single["implementation_source_sets"]["registers"]["source_set_sha256"],
            "8124c7d9d41959d0827af3c4f54c4154b90a4a116e46074e197afe207c751f12",
        )
        self.assertEqual(
            single["implementation_source_sets"]["sram"]["source_set_sha256"],
            "d5296a9dbba4a47ef061b286d6fac90a49770b7a2d46f72f05a12dfbfc2bfccb",
        )

    def test_lc_output_contract_is_timestamped_and_non_mutating_for_dry_run(self):
        temporary, root, config = self.fixture()
        try:
            matrix_path = root / "flows/asic/profiles/register_expanded.json"
            matrix = json.loads(matrix_path.read_text())
            matrix["memory_modes"]["sram"] = {
                "allowed_profiles": ["rv32im_single_perf"],
                "expected_macro_count": 4,
                "expected_blackbox_count": 0,
                "extra_defines": ["NPC_ASIC_SRAM"],
                "macros": {"macro_a": {"expected_instances": 4}},
            }
            matrix["profiles"]["rv32im_single_perf"]["sram_dc_frequencies_mhz"] = [700, 200]
            matrix_path.write_text(json.dumps(matrix))
            config.write_text(config.read_text().replace(
                'CONFIG_NPC_ASIC_MEMORY_MODE="registers"',
                'CONFIG_NPC_ASIC_MEMORY_MODE="sram"'))
            args = mock.Mock(ooo_mode="auto", memory_mode="auto", output="", dry_run=True)
            output = io.StringIO()
            with mock.patch.dict(os.environ, {"NPC_ASIC_LC_OUTPUT": ""}), \
                    mock.patch("sys.stdout", new=output):
                self.assertEqual(asicctl.lc_macros(root, config, args), 0)
            self.assertIn("ASIC_LC_MACROS_DRY_RUN_PASS", output.getvalue())
            self.assertIn("YYYYMMDDTHHMMSSZ", output.getvalue())
            self.assertFalse((root / "build").exists())
            with mock.patch.dict(os.environ, {"NPC_ASIC_LC_OUTPUT": ""}):
                with self.assertRaisesRegex(asicctl.AsicError, "requires explicit"):
                    asicctl.resolve_lc_output(root, "", False)
                valid = asicctl.resolve_lc_output(
                    root, "build/asic/lc/20260729T120000Z", False)
                self.assertEqual(valid, root / "build/asic/lc/20260729T120000Z")
                with self.assertRaisesRegex(asicctl.AsicError, "UTC timestamp"):
                    asicctl.resolve_lc_output(root, "build/asic/lc/latest", False)
                valid.mkdir(parents=True)
                args.output = str(valid)
                args.dry_run = False
                with mock.patch("sys.stdout", new=io.StringIO()):
                    with self.assertRaisesRegex(asicctl.AsicError, "refusing to overwrite"):
                        asicctl.lc_macros(root, config, args)
        finally:
            temporary.cleanup()

    def test_pnr_sta_dry_run_contracts_need_no_handoff_and_do_not_write(self):
        temporary, root, config = self.fixture()
        try:
            pnr_args = mock.Mock(
                ooo_mode="auto", memory_mode="auto", dry_run=True,
                dc_run="", frequency_mhz=None, build_root="", run_id="",
            )
            sta_args = mock.Mock(
                ooo_mode="auto", memory_mode="auto", dry_run=True,
                pnr_run="", build_root="", run_id="",
            )
            output = io.StringIO()
            with mock.patch("sys.stdout", new=output):
                self.assertEqual(asicctl.pnr(root, config, pnr_args), 0)
                self.assertEqual(asicctl.sta(root, config, sta_args), 0)
            text = output.getvalue()
            self.assertIn("ASIC_PNR_DRY_RUN_PASS", text)
            self.assertIn("ASIC_STA_DRY_RUN_PASS", text)
            self.assertIn("orfs_commit=" + "a" * 40, text)
            self.assertIn("orfs_image_digest=sha256:" + "b" * 64, text)
            self.assertIn(
                "orfs_identity_policy=" + asicctl.ORFS_RUNTIME_IDENTITY_POLICY,
                text)
            self.assertIn("dc_mapped_netlist", text)
            self.assertIn("routed_netlist,routed_sdc,openrcx_spef", text)
            self.assertEqual(text.count("required_identity="), 2)
            for key in (
                    "source_set_sha256", "source_role_sha256",
                    "implementation_source_sha256", "config_sha256"):
                self.assertIn(key, text)
            self.assertFalse((root / "build").exists())

            pnr_args.dry_run = False
            with self.assertRaisesRegex(asicctl.AsicError, "real P&R requires"):
                asicctl.pnr(root, config, pnr_args)
            sta_args.dry_run = False
            with self.assertRaisesRegex(asicctl.AsicError, "real STA requires"):
                asicctl.sta(root, config, sta_args)
        finally:
            temporary.cleanup()

    def test_pnr_dry_run_rejects_absent_or_malformed_orfs_identity(self):
        temporary, root, config = self.fixture()
        try:
            matrix_path = root / "flows/asic/profiles/register_expanded.json"
            original = json.loads(matrix_path.read_text())
            args = mock.Mock(
                ooo_mode="auto", memory_mode="auto", dry_run=True,
                dc_run="", frequency_mhz=None, build_root="", run_id="",
            )
            cases = (
                ({}, "lacks required fields"),
                ({**original["orfs"], "commit": "a" * 39}, "full lowercase"),
                ({**original["orfs"], "image_digest": "sha256:bad"}, "full sha256"),
                ({**original["orfs"], "runtime_identity_policy": "legacy"},
                 "policy mismatch"),
            )
            for orfs, error in cases:
                with self.subTest(error=error):
                    matrix = copy.deepcopy(original)
                    matrix["orfs"] = orfs
                    matrix_path.write_text(json.dumps(matrix))
                    with self.assertRaisesRegex(asicctl.AsicError, error):
                        asicctl.pnr(root, config, args)
        finally:
            temporary.cleanup()

    def test_dc_to_pnr_rejects_wholesale_source_identity_deletion(self):
        temporary, root, config = self.fixture()
        try:
            contract = asicctl.build_contract(root, config, "auto")
            dc_run = root / "build/dc/fixture/dc_425mhz"
            dc_run.mkdir(parents=True)
            manifest = {
                "schema": "npc-riscv-open/d8-dc-input-v1",
                "profile": contract["profile"],
                "mode": contract["mode"],
                "memory_mode": contract["memory_mode"],
                "source_commit": contract["source_commit"],
                "source_set_sha256": contract["source_set_sha256"],
                "source_role_sha256": contract["source_role_sha256"],
                "implementation_source_sha256":
                    contract["implementation_source_sha256"],
                "config_sha256": contract["config_sha256"],
            }
            for key in (
                    "source_set_sha256", "source_role_sha256",
                    "implementation_source_sha256", "config_sha256"):
                manifest.pop(key)
            (dc_run.parent / "input_manifest.json").write_text(
                json.dumps(manifest))
            args = mock.Mock(
                ooo_mode="auto", memory_mode="auto", dry_run=False,
                dc_run=str(dc_run), frequency_mhz=None, build_root="", run_id="",
            )
            with self.assertRaisesRegex(
                    asicctl.AsicError,
                    "missing required identity fields: source_set_sha256"):
                asicctl.pnr(root, config, args)
        finally:
            temporary.cleanup()

    def test_pnr_to_sta_rejects_wholesale_source_identity_deletion(self):
        temporary, root, config = self.fixture()
        try:
            contract = asicctl.build_contract(root, config, "auto")
            pnr_run = root / "build/pnr/fixture"
            pnr_run.mkdir(parents=True)
            manifest = {
                "schema": "npc-riscv-open/d8-pnr-input-v1",
                "profile": contract["profile"],
                "mode": contract["mode"],
                "memory_mode": contract["memory_mode"],
                "source_commit": contract["source_commit"],
                "source_set_sha256": contract["source_set_sha256"],
                "source_role_sha256": contract["source_role_sha256"],
                "implementation_source_sha256":
                    contract["implementation_source_sha256"],
                "config_sha256": contract["config_sha256"],
            }
            for key in (
                    "source_set_sha256", "source_role_sha256",
                    "implementation_source_sha256", "config_sha256"):
                manifest.pop(key)
            (pnr_run / "input_manifest.json").write_text(json.dumps(manifest))
            args = mock.Mock(
                ooo_mode="auto", memory_mode="auto", dry_run=False,
                pnr_run=str(pnr_run), build_root="", run_id="",
            )
            with self.assertRaisesRegex(
                    asicctl.AsicError,
                    "missing required identity fields: source_set_sha256"):
                asicctl.sta(root, config, args)
        finally:
            temporary.cleanup()

    def test_pnr_rejects_d7_dc_manifest_without_complete_identity(self):
        temporary, root, config = self.fixture()
        try:
            dc_run = root / "build/dc/matrix/dc_700mhz"
            dc_run.mkdir(parents=True)
            (dc_run.parent / "input_manifest.json").write_text(json.dumps({
                "schema": "npc-riscv-open/d7-dc-input-v1",
            }))
            args = mock.Mock(
                ooo_mode="auto", memory_mode="auto", dry_run=False,
                dc_run=str(dc_run), frequency_mhz=None,
                build_root="", run_id="",
            )
            with self.assertRaisesRegex(asicctl.AsicError, "requires a D8"):
                asicctl.pnr(root, config, args)
        finally:
            temporary.cleanup()

    def test_linux_dc_dry_run_states_final_timer_contract(self):
        contract = {
            "profile": "rv32ima_sv32_linux",
            "mode": "default",
            "memory_mode": "registers",
            "source_commit": "0fc3de40c4e0b231c65945c9dc1711f084688c04",
            "frequencies_mhz": [280, 200],
            "navigation_quantum_mhz": 10,
            "pnr_frequency_mhz": 200,
        }
        args = mock.Mock(
            ooo_mode="auto", memory_mode="auto", dry_run=True,
            frequencies="", timer_clock_hz=None, build_root="", run_id="",
        )
        output = io.StringIO()
        with mock.patch.object(asicctl, "build_contract", return_value=contract), \
                mock.patch("sys.stdout", new=output):
            self.assertEqual(asicctl.dc_matrix(ROOT, ROOT / ".config", args), 0)
        self.assertIn(
            'ASIC_DC_ARGS="--timer-clock-hz 200000000" make dc-matrix',
            output.getvalue(),
        )

        args.timer_clock_hz = 200000000
        output = io.StringIO()
        with mock.patch.object(asicctl, "build_contract", return_value=contract), \
                mock.patch("sys.stdout", new=output):
            self.assertEqual(asicctl.dc_matrix(ROOT, ROOT / ".config", args), 0)
        self.assertIn(
            "linux_timer_contract=explicit timer_clock_hz=200000000",
            output.getvalue(),
        )

    def test_dc_matrix_fails_when_point_budget_exhausts_without_closed_point(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            constraint = root / "flows/asic/constraints/internal_clock.sdc"
            constraint.parent.mkdir(parents=True)
            constraint.write_text("create_clock -period 2.0 [get_ports clk]\n")
            setup = root / "dc_setup.tcl"
            liberty = root / "stdcell.lib"
            database = root / "stdcell.db"
            for path in (setup, liberty, database):
                path.write_text("fixture\n")
            contract = {
                "profile": "rv32im_single_perf",
                "mode": "default",
                "memory_mode": "registers",
                "source_commit": "a" * 40,
                "source_set_sha256": "b" * 64,
                "source_role_sha256": "c" * 64,
                "implementation_source_sha256": "d" * 64,
                "source_overlay_commits": [],
                "config_sha256": "e" * 64,
                "frequencies_mhz": [700, 200],
                "navigation_quantum_mhz": 25,
                "dc_max_points": 1,
                "expected_macro_count": 0,
                "expected_blackbox_count": 0,
                "memory_data": {"extra_defines": [], "macros": {}},
                "parameter_file": None,
                "top": "cpu_top",
                "clock_port": "clk",
                "reset_port": "rst_n",
                "filelist": root / "unused.f",
                "matrix": {"libraries": {
                    "liberty_sha256": asicctl.sha256_file(liberty),
                    "db_sha256": asicctl.sha256_file(database),
                }},
            }
            row = {
                "frequency_mhz": 700,
                "period_ns": 1000.0 / 700,
                "completed": True,
                "setup_closed": False,
                "missing_gate_fields": [],
                "timing_loop_report_valid": True,
                "timing_loop_evidence": 0,
                "automatic_arc_break_evidence": 0,
                "electrical_violations": 0,
                "check_design_errors": 0,
                "unresolved_reference_count": 0,
                "latch_count": 0,
                "unclocked_sync_endpoint_count": 0,
                "macro_count": 0,
                "expected_macro_count": 0,
                "blackbox_count": 0,
                "expected_blackbox_count": 0,
                "check_design_ok": 1,
                "check_timing_ok": 1,
                "wns_ns": -0.4,
                "tns_ns": -1.0,
                "violating_paths": 1,
            }
            args = mock.Mock(
                ooo_mode="auto", memory_mode="auto", dry_run=False,
                frequencies="", timer_clock_hz=None,
                build_root=str(root / "build"), run_id="budget_exhausted",
            )

            def fake_dc(*_args, **kwargs):
                (Path(kwargs["cwd"]) / "cpu_top_mapped.v").write_text(
                    "module cpu_top; endmodule\n")
                return mock.Mock(returncode=0)

            environment = {
                "NPC_ASIC_STDCELL_LIBERTY": str(liberty),
                "NPC_ASIC_STDCELL_DB": str(database),
                "NPC_ASIC_DC_SETUP": str(setup),
            }
            with mock.patch.object(asicctl, "build_contract", return_value=contract), \
                    mock.patch.object(asicctl, "require_tool", return_value=["dc_shell"]), \
                    mock.patch.object(asicctl, "parse_run", return_value=row), \
                    mock.patch.object(asicctl.subprocess, "run", side_effect=fake_dc), \
                    mock.patch.dict(os.environ, environment, clear=False):
                self.assertEqual(asicctl.dc_matrix(root, root / ".config", args), 2)
            verdict = json.loads((
                root / "build/rv32im_single_perf/default/registers/dc/"
                "budget_exhausted/verdict.json").read_text())
            self.assertEqual(verdict["status"], "DC_NO_CLOSED_POINT")
            self.assertEqual(verdict["stop_action"], "stop_point_budget_exhausted")

    def test_register_lc_and_predecessor_free_backend_dry_runs_pass(self):
        temporary, root, config = self.fixture()
        try:
            common = {"ooo_mode": "auto", "memory_mode": "auto", "dry_run": True}
            output = io.StringIO()
            with mock.patch("sys.stdout", new=output):
                self.assertEqual(
                    asicctl.lc_macros(
                        root, config, mock.Mock(**common, output="")
                    ),
                    0,
                )
                self.assertEqual(
                    asicctl.pnr(
                        root,
                        config,
                        mock.Mock(
                            **common, dc_run="", frequency_mhz=None,
                            build_root="", run_id=""
                        ),
                    ),
                    0,
                )
                self.assertEqual(
                    asicctl.sta(
                        root,
                        config,
                        mock.Mock(**common, pnr_run="", build_root="", run_id=""),
                    ),
                    0,
                )
            text = output.getvalue()
            self.assertIn("ASIC_LC_MACROS_DRY_RUN_NOT_APPLICABLE", text)
            self.assertIn("dc_run=<setup-closed-dc-run>", text)
            self.assertIn("pnr_run=<route-clean-pnr-run>", text)
            self.assertFalse((root / "build").exists())
        finally:
            temporary.cleanup()

    def test_linux_sram_profile_uses_exact_xpm_leaf_binding(self):
        matrix = json.loads((
            ROOT / "flows/asic/profiles/register_expanded.json").read_text())
        self.assertIn(
            "rv32ima_sv32_linux", matrix["memory_modes"]["sram"]["allowed_profiles"])
        self.assertEqual(
            matrix["profiles"]["rv32ima_sv32_linux"]["sram_dc_frequencies_mhz"],
            [400, 200])
        config = (ROOT / "configs/rv32ima_sv32_linux_sram_asic_defconfig").read_text()
        self.assertIn('CONFIG_NPC_ASIC_MEMORY_MODE="sram"', config)
        xpm = (ROOT / "rtl/asic/xpm_register_models.sv").read_text()
        self.assertIn("NPC_ASIC_SRAM", xpm)
        self.assertIn("npc_icache_data_1r1w_512x32 u_macro", xpm)
        self.assertIn("npc_dcache_data_1r1w_512x32_b8 u_macro", xpm)
        self.assertIn("npc_unsupported_sram_xpm_sdpram_configuration", xpm)
        self.assertIn("npc_unsupported_sram_xpm_tdpram_configuration", xpm)

    def test_floorplan_uses_required_area_formula_and_site_snap(self):
        result = calculate(300000.0)
        self.assertGreaterEqual(result["computed_core_area_um2"], 300000.0 * 1.25 / 0.30)
        x0, y0, x1, y1 = result["core_area"]
        self.assertAlmostEqual((x1 - x0) / 0.19, round((x1 - x0) / 0.19), places=6)
        self.assertAlmostEqual((y1 - y0) / 1.4, round((y1 - y0) / 1.4), places=6)
        self.assertEqual(result["place_density"], 0.55)

    def test_macro_floorplan_preserves_count_channel_and_boundary(self):
        macros = {
            "macro_a": {"expected_instances": 2, "width_um": 158.695, "height_um": 427.77},
            "macro_b": {"expected_instances": 2, "width_um": 158.695, "height_um": 427.77},
        }
        result = calculate_with_macros(250000.0, macros)
        placements = result["macro_placements"]
        self.assertEqual(len(placements), 4)
        self.assertEqual(result["macro_halo_um"], 20.0)
        self.assertEqual(result["macro_channel_um"], 30.0)
        x0, y0, x1, y1 = result["core_area"]
        for placement in placements:
            self.assertGreaterEqual(placement["x_um"] - x0, 40.0)
            self.assertGreaterEqual(placement["y_um"] - y0, 40.0)
            self.assertGreaterEqual(x1 - placement["x_um"] - placement["width_um"], 40.0)
            self.assertGreaterEqual(y1 - placement["y_um"] - placement["height_um"], 40.0)
        for left, right in zip(placements, placements[1:]):
            self.assertAlmostEqual(
                right["x_um"] - left["x_um"] - left["width_um"], 30.0)

    def test_openroad_contract_consumes_macro_views_and_hooks(self):
        config = (ROOT / "flows/asic/openroad/config.mk").read_text()
        for name in ("ADDITIONAL_LEFS", "ADDITIONAL_LIBS", "ADDITIONAL_GDS",
                     "MACRO_PLACEMENT_TCL", "PRE_PDN_TCL", "PRE_GLOBAL_ROUTE_TCL",
                     "HOLD_SLACK_MARGIN"):
            self.assertIn(name, config)
        runner = (ROOT / "flows/asic/openroad/run.sh").read_text()
        self.assertIn("NPC_ASIC_EXPECTED_MACRO_COUNT", runner)
        self.assertIn("FAIL_HANDOFF_IDENTITY", runner)
        self.assertIn("git -c safe.directory=/OpenROAD-flow-scripts", runner)
        self.assertIn("actual_orfs_commit", runner)
        self.assertIn("ORFS commit mismatch", runner)
        self.assertIn("image_digest_bound_no_vcs_metadata", runner)
        self.assertIn("test -e /OpenROAD-flow-scripts/.git", runner)
        self.assertIn("VCS metadata is present but HEAD verification failed", runner)
        self.assertIn("container_indexed_list", runner)
        self.assertIn("macro_view_mounts+=(", runner)
        self.assertNotIn("for path in $1", runner)

    def test_openroad_normalizes_only_dc_constant_nets(self):
        text = (ROOT / "flows/asic/openroad/normalize_dc_constant_nets.tcl").read_text()
        self.assertIn("foreach net [$block getNets]", text)
        self.assertIn("{(^|/)(one_|zero_)$}", text)
        self.assertIn("foreach name [lsort -dictionary $constant_names]", text)
        self.assertIn("$net setSigType SIGNAL", text)
        self.assertNotIn("setSigType SIGNAL", text.replace("$net setSigType SIGNAL", ""))
        self.assertNotIn("VDD", text)
        self.assertNotIn("VSS", text)

    def _openroad_runner_fixture(self, base, commit):
        root = base / "source"
        build = root / "build"
        root.mkdir()
        netlist = root / "mapped.v"
        sdc = root / "mapped.sdc"
        hook = root / "normalize.tcl"
        fake_docker = root / "fake-docker"
        netlist.write_text("module cpu_top; endmodule\n")
        sdc.write_text("create_clock -period 2.0 [get_ports clk]\n")
        hook.write_text("# fixture\n")
        fake_docker.write_text("#!/usr/bin/env bash\nexit 0\n")
        fake_docker.chmod(0o755)
        digest = "sha256:" + "0" * 64
        environment = os.environ.copy()
        environment.update({
            "NPC_ASIC_ROOT": str(root),
            "NPC_ASIC_BUILD_ROOT": str(build),
            "NPC_ASIC_TOP": "cpu_top",
            "NPC_ASIC_DESIGN_NICKNAME": "fixture",
            "NPC_ASIC_MAPPED_NETLIST": str(netlist),
            "NPC_ASIC_PNR_SDC": str(sdc),
            "NPC_ASIC_PNR_PERIOD_NS": "2.0",
            "NPC_ASIC_DIE_AREA": "0 0 100 100",
            "NPC_ASIC_CORE_AREA": "10 10 90 90",
            "NPC_ASIC_PLACE_DENSITY": "0.55",
            "NPC_ASIC_ORFS_IMAGE": "fixture@" + digest,
            "NPC_ASIC_ORFS_IMAGE_DIGEST": digest,
            "NPC_ASIC_ORFS_COMMIT": commit,
            "NPC_ASIC_MEMORY_MODE": "registers",
            "NPC_ASIC_EXPECTED_MACRO_COUNT": "0",
            "NPC_ASIC_HOLD_SLACK_MARGIN": "0.0",
            "NPC_ASIC_PRE_GLOBAL_ROUTE_TCL": str(hook),
            "NPC_ASIC_CONSTANT_NET_REPORT": str(build / "constant_net_report.txt"),
            "NPC_ASIC_DOCKER": str(fake_docker),
        })
        return environment, build

    def test_openroad_runner_rejects_malformed_orfs_commit(self):
        with tempfile.TemporaryDirectory() as temp:
            environment, _ = self._openroad_runner_fixture(
                Path(temp), "0" * 39)
            completed = subprocess.run(
                ["bash", str(ROOT / "flows/asic/openroad/run.sh")],
                env=environment, capture_output=True, text=True, check=False)
            self.assertEqual(completed.returncode, 2)
            self.assertIn("full lowercase Git commit", completed.stderr)

    def test_openroad_runner_rejects_untracked_image_digest(self):
        with tempfile.TemporaryDirectory() as temp:
            environment, _ = self._openroad_runner_fixture(
                Path(temp), "0" * 40)
            environment["NPC_ASIC_ORFS_IMAGE"] = (
                "fixture@sha256:" + "1" * 64)
            completed = subprocess.run(
                ["bash", str(ROOT / "flows/asic/openroad/run.sh")],
                env=environment, capture_output=True, text=True, check=False)
            self.assertEqual(completed.returncode, 2)
            self.assertIn("does not match the tracked repository digest", completed.stderr)

    def test_openroad_runner_requires_runtime_identity_report(self):
        with tempfile.TemporaryDirectory() as temp:
            environment, _ = self._openroad_runner_fixture(
                Path(temp), "0" * 40)
            completed = subprocess.run(
                ["bash", str(ROOT / "flows/asic/openroad/run.sh")],
                env=environment, capture_output=True, text=True, check=False)
            self.assertEqual(completed.returncode, 2)
            self.assertIn("Missing ORFS runtime identity report", completed.stderr)

    def test_openroad_runner_rejects_preexisting_runtime_identity_report(self):
        with tempfile.TemporaryDirectory() as temp:
            environment, build = self._openroad_runner_fixture(
                Path(temp), "0" * 40)
            build.mkdir()
            (build / "orfs_commit.txt").write_text("1" * 40 + "\n")
            completed = subprocess.run(
                ["bash", str(ROOT / "flows/asic/openroad/run.sh")],
                env=environment, capture_output=True, text=True, check=False)
            self.assertEqual(completed.returncode, 2)
            self.assertIn("pre-existing ORFS runtime identity report", completed.stderr)

    def test_openroad_runner_rejects_build_root_outside_source_root(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp)
            root = base / "source"
            build = base / "build"
            root.mkdir()
            build.mkdir()
            netlist = root / "mapped.v"
            sdc = root / "mapped.sdc"
            hook = root / "normalize.tcl"
            netlist.write_text("module cpu_top; endmodule\n")
            sdc.write_text("create_clock -period 2.0 [get_ports clk]\n")
            hook.write_text("# fixture\n")
            environment = os.environ.copy()
            environment.update({
                "NPC_ASIC_ROOT": str(root),
                "NPC_ASIC_BUILD_ROOT": str(build),
                "NPC_ASIC_TOP": "cpu_top",
                "NPC_ASIC_DESIGN_NICKNAME": "fixture",
                "NPC_ASIC_MAPPED_NETLIST": str(netlist),
                "NPC_ASIC_PNR_SDC": str(sdc),
                "NPC_ASIC_PNR_PERIOD_NS": "2.0",
                "NPC_ASIC_DIE_AREA": "0 0 100 100",
                "NPC_ASIC_CORE_AREA": "10 10 90 90",
                "NPC_ASIC_PLACE_DENSITY": "0.55",
                "NPC_ASIC_ORFS_IMAGE": "fixture@sha256:" + "0" * 64,
                "NPC_ASIC_ORFS_IMAGE_DIGEST": "sha256:" + "0" * 64,
                "NPC_ASIC_ORFS_COMMIT": "0" * 40,
                "NPC_ASIC_MEMORY_MODE": "registers",
                "NPC_ASIC_EXPECTED_MACRO_COUNT": "0",
                "NPC_ASIC_HOLD_SLACK_MARGIN": "0.0",
                "NPC_ASIC_PRE_GLOBAL_ROUTE_TCL": str(hook),
                "NPC_ASIC_CONSTANT_NET_REPORT": str(build / "constant_net_report.txt"),
            })
            completed = subprocess.run(
                ["bash", str(ROOT / "flows/asic/openroad/run.sh")],
                env=environment, capture_output=True, text=True, check=False)
            self.assertEqual(completed.returncode, 2)
            self.assertIn(
                "NPC_ASIC_BUILD_ROOT must be below NPC_ASIC_ROOT",
                completed.stderr)

    def test_openroad_runner_preserves_macro_paths_under_root_with_whitespace(self):
        with tempfile.TemporaryDirectory() as temp:
            base = Path(temp) / "NPC Project"
            base.mkdir()
            environment, _ = self._openroad_runner_fixture(base, "0" * 40)
            root = Path(environment["NPC_ASIC_ROOT"])
            docker_log = root / "docker-args.txt"
            fake_docker = Path(environment["NPC_ASIC_DOCKER"])
            fake_docker.write_text(
                "#!/usr/bin/env bash\nprintf '%s\\n' \"$@\" > \"$NPC_TEST_DOCKER_LOG\"\n")
            for role, suffix in (("LEF", "lef"), ("LIB", "lib"), ("GDS", "gds")):
                path = root / f"macro.{suffix}"
                path.write_text("fixture\n")
                environment[f"NPC_ASIC_MACRO_{role}_COUNT"] = "1"
                environment[f"NPC_ASIC_MACRO_{role}_0"] = str(path)
            placement = root / "macro_placement.tcl"
            report = root / "macro_placement_report.txt"
            pre_pdn = root / "pre_pdn.tcl"
            for path in (placement, report, pre_pdn):
                path.write_text("fixture\n")
            environment.update({
                "NPC_ASIC_MEMORY_MODE": "sram",
                "NPC_ASIC_EXPECTED_MACRO_COUNT": "4",
                "NPC_ASIC_MACRO_PLACEMENT_TCL": str(placement),
                "NPC_ASIC_MACRO_PLACEMENT_REPORT": str(report),
                "NPC_ASIC_PRE_PDN_TCL": str(pre_pdn),
                "NPC_TEST_DOCKER_LOG": str(docker_log),
            })
            completed = subprocess.run(
                ["bash", str(ROOT / "flows/asic/openroad/run.sh")],
                env=environment, capture_output=True, text=True, check=False)
            self.assertEqual(completed.returncode, 2)
            self.assertIn("Missing ORFS runtime identity report", completed.stderr)
            self.assertNotIn("Missing macro view", completed.stderr)
            arguments = docker_log.read_text()
            for role in ("LEF", "LIB", "GDS"):
                container_path = f"/npc_macro_views/NPC_ASIC_MACRO_{role}_0"
                self.assertIn(container_path, arguments)
                self.assertIn("NPC Project/source/macro.", arguments)

    def test_pnr_sdc_retargets_exactly_one_clock(self):
        source = "create_clock [get_ports clk] -name npc_clk -period 1.250000\n"
        result = retarget(source, 2.0)
        self.assertIn("-period 2.000000000", result)
        with self.assertRaisesRegex(ValueError, "exactly one"):
            retarget(source + source, 2.0)

    def test_routed_sdc_accepts_orfs_rounding_and_restores_exact_period(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "routed.sdc"
            output = root / "primetime.sdc"
            source.write_text(
                "current_design cpu_top\n"
                "create_clock -name npc_clk -period 2.3529 [get_ports {clk}]\n"
            )
            with mock.patch.object(sys, "argv", [
                    "sanitize_openroad_sdc.py", "--input", str(source),
                    "--output", str(output), "--expected-period-ns", "2.352941176"]):
                self.assertEqual(sanitize_openroad_sdc(), 0)
            self.assertIn("-period 2.352941176", output.read_text())

    def test_routed_sdc_rejects_value_outside_orfs_rounding_interval(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "routed.sdc"
            output = root / "primetime.sdc"
            source.write_text(
                "current_design cpu_top\n"
                "create_clock -name npc_clk -period 2.3528 [get_ports {clk}]\n"
            )
            with mock.patch.object(sys, "argv", [
                    "sanitize_openroad_sdc.py", "--input", str(source),
                    "--output", str(output), "--expected-period-ns", "2.352941176"]):
                with self.assertRaisesRegex(SystemExit, "period mismatch"):
                    sanitize_openroad_sdc()

    def test_dc_constraint_uses_native_capacitance_and_bounded_fanout(self):
        text = (ROOT / "flows/asic/constraints/internal_clock.sdc").read_text()
        self.assertIn("set_max_transition 0.20", text)
        self.assertIn("set_max_fanout 32", text)
        self.assertNotIn("set_max_capacitance", text)

    def test_dc_check_timing_uses_o2018_compatible_form(self):
        text = (ROOT / "flows/asic/dc/run.tcl").read_text()
        self.assertIn("set check_timing_ok [check_timing]", text)
        self.assertNotIn("check_timing -verbose", text)

    def test_dc_recipe_runs_incremental_cleanup_after_compile_ultra(self):
        text = (ROOT / "flows/asic/dc/run.tcl").read_text()
        compile_ultra = text.index("compile_ultra")
        cleanup = text.index("compile -incremental_mapping", compile_ultra)
        isolation = text.index("apply_sram_icache_write_data_isolation", cleanup)
        reports = text.index("set check_design_ok", isolation)
        self.assertLess(compile_ultra, cleanup)
        self.assertLess(cleanup, isolation)
        self.assertLess(isolation, reports)
        self.assertIn("set compile_recipe compile_ultra_then_incremental_mapping_v1", text)
        self.assertIn(
            "compile_ultra_then_incremental_mapping_then_sram_icache_din_isolation_v2",
            text)

    def test_dc_sram_input_isolation_is_exact_and_fail_closed(self):
        text = (ROOT / "flows/asic/dc/sram_input_isolation.tcl").read_text()
        self.assertIn("ref_name == npc_icache_data_1r1w_512x32", text)
        self.assertIn("name =~ din0*", text)
        self.assertIn("!= 64", text)
        self.assertIn("!= 32", text)
        self.assertIn("set_dont_touch $inserted_buf_cells true", text)
        self.assertIn("compile -incremental_mapping", text)
        self.assertNotIn("clk0", text)
        self.assertNotIn("clk1", text)
        controller = (ROOT / "flows/scripts/asicctl.py").read_text()
        self.assertIn('"sram_input_isolation_hook"', controller)

    def test_ooo_wrapper_binds_a3_only_for_a3_source(self):
        text = (ROOT / "rtl/wrappers/rv32im_ooo_4k_sim_top.sv").read_text()
        guard = text.index("`ifdef NPC_OOO_A3_ENABLE")
        end = text.index("`endif", guard)
        guarded = text[guard:end]
        self.assertIn(".STABLE_ENTRY_IQ_ENABLE(1'b1)", guarded)
        self.assertIn(".IQ_SPLIT_PAYLOAD_READ_ENABLE(1'b1)", guarded)
        self.assertIn(".ROB_INDEXED_SERVICE_LEVEL(1)", guarded)
        self.assertNotIn("`define NPC_OOO_A3_ENABLE 0", text)

    def test_dc_diagnostic_collection_failure_is_not_clean(self):
        text = (ROOT / "flows/asic/dc/run.tcl").read_text()
        self.assertIn("proc collection_count_or_invalid", text)
        self.assertIn("return -1", text)
        self.assertNotIn("collection_count_or_zero", text)
        self.assertIn("all_registers -level_sensitive", text)
        self.assertIn("is_logical_black_box == true", text)
        self.assertNotIn("is_latch == true", text)
        self.assertNotIn("is_unresolved == true", text)
        self.assertNotIn("get_designs -quiet *", text)

    def test_dc_summary_requires_loop_and_electrical_cleanliness(self):
        with tempfile.TemporaryDirectory() as temp:
            run = Path(temp)
            (run / "run.ok").write_text("ok\n")
            (run / "cpu_top_mapped.v").write_text("module cpu_top; endmodule\n")
            (run / "run_contract.txt").write_text(
                "top=cpu_top\nclock_period_ns=2.0\nmacro_count=0\nblackbox_count=0\n"
                "cell_count=100\nregister_count=20\nclocked_register_count=20\n"
                "unclocked_sync_endpoint_count=0\nlatch_count=0\n"
                "unresolved_reference_count=0\ncheck_design_ok=1\ncheck_timing_ok=1\n"
                "setup_wns_ns=0.05\nsetup_tns_ns=0.0\nsetup_violation_count=0\n"
                "hold_wns_ns=0.02\nhold_tns_ns=0.0\nhold_violation_count=0\n"
                "max_transition_violation_count=0\nmax_capacitance_violation_count=0\n"
                "max_fanout_violation_count=0\nmin_period_violation_count=0\n"
                "min_pulse_width_violation_count=0\ninferred_memory_bits=NA\n"
                "inferred_memory_bits_status=dc_o_2018_06_report_memory_unavailable\n"
                "rtl_defines=NPC_ASIC\n")
            (run / "qor.rpt").write_text(
                "Critical Path Slack: 0.05\nTotal Negative Slack: 0.00\n"
                "No. of Violating Paths: 0\nDesign Area: 1000.0\n")
            (run / "timing.rpt").write_text(
                "Startpoint: a_reg\nEndpoint: b_reg\nPath Group: npc_clk\n"
                "  data arrival time 1.80\n  slack (MET) 0.05\n")
            for name in ("constraints.rpt", "check_design.rpt", "check_timing.rpt",
                         "dc.log", "disabled_timing.rpt", "timing_loops.rpt"):
                (run / name).write_text("No timing loops found\n" if name == "timing_loops.rpt" else "clean\n")
            self.assertTrue(parse_run(run)["setup_closed"])
            (run / "timing_loops.rpt").write_text("Warning: found a combinational loop\n")
            self.assertFalse(parse_run(run)["setup_closed"])

    def test_dc_summary_fails_closed_when_tns_is_missing(self):
        with tempfile.TemporaryDirectory() as temp:
            run = Path(temp)
            (run / "run.ok").write_text("ok\n")
            (run / "cpu_top_mapped.v").write_text("module cpu_top; endmodule\n")
            (run / "run_contract.txt").write_text(
                "top=cpu_top\nclock_period_ns=2.0\nmacro_count=0\nblackbox_count=0\n"
                "check_design_ok=1\ncheck_timing_ok=1\nunresolved_reference_count=0\n"
                "latch_count=0\nunclocked_sync_endpoint_count=0\n"
                "setup_wns_ns=0.1\nsetup_violation_count=0\n"
                "max_transition_violation_count=0\nmax_capacitance_violation_count=0\n"
                "max_fanout_violation_count=0\nmin_period_violation_count=0\n"
                "min_pulse_width_violation_count=0\n")
            (run / "timing_loops.rpt").write_text("No timing loops found\n")
            self.assertIn("tns_ns", parse_run(run)["missing_gate_fields"])
            self.assertFalse(parse_run(run)["setup_closed"])

    def test_dc_sram_summary_requires_input_isolation_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            run = Path(temp)
            (run / "run.ok").write_text("ok\n")
            (run / "cpu_top_mapped.v").write_text("module cpu_top; endmodule\n")
            contract = (
                "top=cpu_top\nmemory_mode=sram\nclock_period_ns=2.0\n"
                "expected_macro_count=4\nmacro_count=4\n"
                "expected_blackbox_count=0\nblackbox_count=0\n"
                "cell_count=100\nregister_count=20\nclocked_register_count=20\n"
                "unclocked_sync_endpoint_count=0\nlatch_count=0\n"
                "unresolved_reference_count=0\ncheck_design_ok=1\ncheck_timing_ok=1\n"
                "setup_wns_ns=0.05\nsetup_tns_ns=0.0\nsetup_violation_count=0\n"
                "hold_wns_ns=0.02\nhold_tns_ns=0.0\nhold_violation_count=0\n"
                "max_transition_violation_count=0\nmax_capacitance_violation_count=0\n"
                "max_fanout_violation_count=0\nmin_period_violation_count=0\n"
                "min_pulse_width_violation_count=0\n"
            )
            (run / "run_contract.txt").write_text(contract)
            (run / "qor.rpt").write_text(
                "Critical Path Slack: 0.05\nTotal Negative Slack: 0.00\n"
                "No. of Violating Paths: 0\nDesign Area: 1000.0\n")
            (run / "timing.rpt").write_text(
                "Startpoint: a_reg\nEndpoint: b_reg\nPath Group: npc_clk\n"
                "  data arrival time 1.80\n  slack (MET) 0.05\n")
            for name in ("constraints.rpt", "check_design.rpt", "check_timing.rpt",
                         "dc.log", "disabled_timing.rpt", "timing_loops.rpt"):
                (run / name).write_text(
                    "No timing loops found\n" if name == "timing_loops.rpt" else "clean\n")
            missing = parse_run(run)
            self.assertFalse(missing["setup_closed"])
            self.assertIn(
                "sram_input_isolation_buffer_count", missing["missing_gate_fields"])
            (run / "run_contract.txt").write_text(contract +
                "compile_recipe=compile_ultra_then_incremental_mapping_then_sram_icache_din_isolation_v2\n"
                "sram_input_isolation_revision=single_icache_write_data_shared_buf_x16_v1\n"
                "sram_input_isolation_target_pin_count=64\n"
                "sram_input_isolation_expected_target_pin_count=64\n"
                "sram_input_isolation_buffer_count=32\n"
                "sram_input_isolation_expected_buffer_count=32\n")
            self.assertTrue(parse_run(run)["setup_closed"])

    def test_dc_frequency_navigation_quantizes_below_wns_estimate(self):
        row = {
            "completed": True,
            "period_ns": 1000.0 / 700.0,
            "wns_ns": -0.396732,
            "tns_ns": -13578.86,
            "violating_paths": 100,
            "setup_closed": False,
            "missing_gate_fields": [],
            "timing_loop_report_valid": True,
            "timing_loop_evidence": 0,
            "automatic_arc_break_evidence": 0,
            "electrical_violations": 0,
            "check_design_errors": 0,
            "check_design_ok": 1,
            "check_timing_ok": 1,
            "unresolved_reference_count": 0,
            "latch_count": 0,
            "unclocked_sync_endpoint_count": 0,
            "macro_count": 0,
            "blackbox_count": 0,
        }
        decision = asicctl.dc_frequency_decision([800, 700, 600, 500], 700, row)
        self.assertAlmostEqual(decision["estimated_fmax_mhz"], 547.854, places=3)
        self.assertEqual(decision["quantized_fmax_mhz"], 540)
        self.assertEqual(decision["next_frequency_mhz"], 540)
        self.assertEqual(decision["skipped_frequencies_mhz"], [600])

    def test_dc_frequency_navigation_accepts_generated_current_point(self):
        row = {
            "completed": True,
            "period_ns": 1000.0 / 540.0,
            "wns_ns": -0.05,
            "tns_ns": -10.0,
            "violating_paths": 10,
            "setup_closed": False,
            "missing_gate_fields": [],
            "timing_loop_report_valid": True,
            "timing_loop_evidence": 0,
            "automatic_arc_break_evidence": 0,
            "electrical_violations": 0,
            "check_design_errors": 0,
            "check_design_ok": 1,
            "check_timing_ok": 1,
            "unresolved_reference_count": 0,
            "latch_count": 0,
            "unclocked_sync_endpoint_count": 0,
            "macro_count": 0,
            "blackbox_count": 0,
        }
        decision = asicctl.dc_frequency_decision([800, 700, 600, 500], 540, row)
        self.assertEqual(decision["next_frequency_mhz"], 520)
        self.assertEqual(decision["skipped_frequencies_mhz"], [])

    def test_dc_frequency_navigation_stops_after_first_closed_point(self):
        decision = asicctl.dc_frequency_decision(
            [500, 400, 350], 500, {"setup_closed": True})
        self.assertEqual(decision["action"], "stop_closed")
        self.assertIsNone(decision["next_frequency_mhz"])
        self.assertEqual(decision["skipped_frequencies_mhz"], [400, 350])

    def test_dc_frequency_navigation_does_not_mask_non_timing_failure(self):
        row = {
            "completed": True,
            "period_ns": 2.0,
            "wns_ns": -0.5,
            "tns_ns": -10.0,
            "violating_paths": 10,
            "setup_closed": False,
            "missing_gate_fields": [],
            "timing_loop_report_valid": True,
            "timing_loop_evidence": 1,
            "automatic_arc_break_evidence": 0,
            "electrical_violations": 0,
            "check_design_errors": 0,
            "check_design_ok": 1,
            "check_timing_ok": 1,
            "unresolved_reference_count": 0,
            "latch_count": 0,
            "unclocked_sync_endpoint_count": 0,
            "macro_count": 0,
            "blackbox_count": 0,
        }
        decision = asicctl.dc_frequency_decision([500, 400, 300], 500, row)
        self.assertEqual(decision["action"], "stop_non_setup_failure")
        self.assertIsNone(decision["next_frequency_mhz"])
        self.assertEqual(decision["skipped_frequencies_mhz"], [400, 300])

    def test_dc_frequency_candidates_must_be_descending(self):
        with self.assertRaisesRegex(asicctl.AsicError, "descending"):
            asicctl.parse_frequency_list("500,600,400", [])

    def test_pnr_summary_requires_route_antenna_and_extraction_cleanliness(self):
        with tempfile.TemporaryDirectory() as temp:
            run = Path(temp)
            nickname = "fixture"
            top = "cpu_top"
            (run / "openroad_contract.txt").write_text(
                "design_nickname=fixture\ntop=cpu_top\nmemory_mode=registers\n"
                "pnr_period_ns=2.0\n")
            (run / "exit_status.txt").write_text("0\n")
            results = run / "orfs/results/nangate45" / nickname / "base"
            logs = run / "orfs/logs/nangate45" / nickname / "base"
            reports = run / "orfs/reports/nangate45" / nickname / "base"
            handoff = run / "handoff"
            for directory in (results, logs, reports, handoff):
                directory.mkdir(parents=True, exist_ok=True)
            (run / "constant_net_report.txt").write_text(
                "found=1\nnormalized=1\nalready_signal=0\n")
            for path in (
                results / "1_2_yosys.v", handoff / (top + "_postroute.odb"),
                handoff / (top + "_postroute.def"), handoff / (top + "_postroute.v"),
                handoff / (top + "_postroute.sdc"), handoff / (top + "_postroute.spef"),
                handoff / (top + ".gds"), reports / "5_route_drc.rpt",
            ):
                path.write_text(
                    "" if path == reports / "5_route_drc.rpt" else "fixture\n")
            route = {
                "detailedroute__route__drc_errors": 0,
                "detailedroute__antenna__violating__nets": 0,
                "detailedroute__antenna__violating__pins": 0,
                "detailedroute__flow__errors__count": 0,
            }
            final = {
                "finish__flow__errors__count": 0,
                "finish__design__instance__count__macros": 0,
                "finish__timing__drv__max_slew": 0,
                "finish__timing__drv__max_cap": 0,
                "finish__timing__drv__max_fanout": 0,
                "finish__timing__setup__ws": 0.1,
                "finish__timing__setup__tns": 0,
                "finish__timing__hold__ws": 0.02,
                "finish__timing__hold__tns": 0,
                "finish__timing__drv__setup_violation_count": 0,
                "finish__timing__drv__hold_violation_count": 0,
            }
            (logs / "5_2_route.json").write_text(json.dumps(route))
            (logs / "6_report.json").write_text(json.dumps(final))
            self.assertTrue(parse_pnr_run(run)["route_complete"])
            route["detailedroute__route__drc_errors"] = 1
            (logs / "5_2_route.json").write_text(json.dumps(route))
            self.assertFalse(parse_pnr_run(run)["route_complete"])

    def test_pnr_handoff_recovery_preserves_source_and_promotes_clean_orfs(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source"
            output = root / "recovered"
            nickname = "rv32im_single_perf_default_425m"
            top = "cpu_top"
            source.mkdir()
            identity = {
                "profile": "rv32im_single_perf",
                "mode": "default",
                "memory_mode": "registers",
                "source_commit": "d" * 40,
                "source_set_sha256": "e" * 64,
                "source_role_sha256": "f" * 64,
                "implementation_source_sha256": "1" * 64,
                "config_sha256": "2" * 64,
            }
            libraries = {
                "liberty_sha256": "3" * 64,
                "db_sha256": "4" * 64,
            }
            expected_contract = {
                **identity,
                "expected_macro_count": 0,
                "expected_blackbox_count": 0,
                "pnr_frequency_mhz": 425,
                "top": top,
                "matrix": {"libraries": libraries},
            }
            contract_patcher = mock.patch(
                "recover_pnr_handoff.build_contract",
                return_value=expected_contract,
            )
            contract_patcher.start()
            self.addCleanup(contract_patcher.stop)
            matrix_path = root / "flows/asic/profiles/register_expanded.json"
            matrix_path.parent.mkdir(parents=True)
            matrix_path.write_text(json.dumps({"orfs": {
                "commit": "a" * 40,
                "image_digest": "sha256:" + "b" * 64,
                "platform": "nangate45",
                "runtime_identity_policy": asicctl.ORFS_RUNTIME_IDENTITY_POLICY,
            }}))
            (source / "input").mkdir()
            mapped = source / "input/cpu_top_mapped.v"
            mapped.write_text("module cpu_top; endmodule\n")
            external_dc_manifest = root / "dc_run/input_manifest.json"
            external_dc_manifest.parent.mkdir()
            external_dc_manifest.write_text(json.dumps({
                "schema": "npc-riscv-open/d8-dc-input-v1",
                **identity,
                "expected_macro_count": 0,
                "expected_blackbox_count": 0,
                **libraries,
            }))
            dc_manifest_hash = asicctl.sha256_file(external_dc_manifest)
            (source / "input_manifest.json").write_text(json.dumps({
                "schema": "npc-riscv-open/d8-pnr-input-v1",
                **identity,
                "expected_macro_count": 0,
                "expected_blackbox_count": 0,
                "pnr_frequency_mhz": 425,
                "dc_input_schema": "npc-riscv-open/d8-dc-input-v1",
                "dc_input_manifest_sha256": dc_manifest_hash,
                "files": {
                    "dc_input_manifest": {
                        "path": str(external_dc_manifest),
                        "sha256": dc_manifest_hash,
                    },
                    "dc_mapped_netlist": {
                        "path": str(mapped), "sha256": asicctl.sha256_file(mapped),
                    },
                },
            }))
            (source / "openroad_contract.txt").write_text(
                f"design_nickname={nickname}\ntop=cpu_top\nplatform=nangate45\n"
                "memory_mode=registers\nexpected_macro_count=0\n"
                "pnr_period_ns=2.352941176\norfs_commit=" + "a" * 40 + "\n"
                "orfs_actual_commit=NA\norfs_commit_verification=pending\n"
                "orfs_image_digest=sha256:" + "b" * 64 + "\n"
                "orfs_image=fixture@sha256:" + "b" * 64 + "\n"
                "mapped_netlist_sha256=" + asicctl.sha256_file(mapped) + "\n"
                "orfs_import_netlist_sha256=NA\n"
            )
            (source / "constant_net_report.txt").write_text(
                "found=1\nnormalized=1\nalready_signal=0\n")
            (source / "floorplan.json").write_text("{}\n")
            (source / "openroad.log").write_text("wrapper period mismatch\n")
            (source / "exit_status.txt").write_text("1\n")
            (source / "summary.json").write_text("{}\n")
            results = source / "orfs/results/nangate45" / nickname / "base"
            logs = source / "orfs/logs/nangate45" / nickname / "base"
            reports = source / "orfs/reports/nangate45" / nickname / "base"
            for directory in (results, logs, reports):
                directory.mkdir(parents=True)
            for name in (
                    "1_2_yosys.v", "6_final.v", "6_final.odb", "6_final.def",
                    "6_final.spef", "6_final.gds"):
                (results / name).write_text(mapped.read_text())
            (results / "6_final.sdc").write_text(
                "current_design cpu_top\n"
                "create_clock -name npc_clk -period 2.3529 [get_ports {clk}]\n")
            route = {
                "detailedroute__route__drc_errors": 0,
                "detailedroute__antenna__violating__nets": 0,
                "detailedroute__antenna__violating__pins": 0,
                "detailedroute__flow__errors__count": 0,
            }
            final = {
                "finish__flow__errors__count": 0,
                "finish__design__instance__count__macros": 0,
                "finish__timing__drv__max_slew": 0,
                "finish__timing__drv__max_cap": 0,
                "finish__timing__drv__max_fanout": 0,
                "finish__timing__setup__ws": 0.1,
                "finish__timing__setup__tns": 0,
                "finish__timing__hold__ws": 0.02,
                "finish__timing__hold__tns": 0,
                "finish__timing__drv__setup_violation_count": 0,
                "finish__timing__drv__hold_violation_count": 0,
            }
            (logs / "5_2_route.json").write_text(json.dumps(route))
            (logs / "6_report.json").write_text(json.dumps(final))
            (reports / "5_route_drc.rpt").write_text("")

            with self.assertRaisesRegex(RecoveryError, "runtime identity report"):
                recover_pnr_handoff(source, output, root)
            (source / "orfs_commit.txt").write_text(
                "actual_commit=wrong\n"
                "verification=image_digest_bound_no_vcs_metadata\n")
            with self.assertRaisesRegex(
                    RecoveryError, "digest-bound runtime identity mismatch"):
                recover_pnr_handoff(source, output, root)
            (source / "orfs_commit.txt").write_text(
                "actual_commit=not_embedded\n"
                "verification=image_digest_bound_no_vcs_metadata\n")
            manifest_path = source / "input_manifest.json"
            manifest = json.loads(manifest_path.read_text())
            baseline_manifest = copy.deepcopy(manifest)
            bad_schema = copy.deepcopy(baseline_manifest)
            bad_schema["schema"] = "npc-riscv-open/d7-pnr-input-v1"
            manifest_path.write_text(json.dumps(bad_schema))
            bad_schema_output = root / "recovered_bad_pnr_schema"
            with self.assertRaisesRegex(RecoveryError, "requires a D8 P&R"):
                recover_pnr_handoff(source, bad_schema_output, root)
            self.assertFalse(bad_schema_output.exists())

            for field in asicctl.HANDOFF_IDENTITY_FIELDS:
                with self.subTest(recovery_identity_field=field):
                    mutated = copy.deepcopy(baseline_manifest)
                    mutated[field] = "wrong"
                    manifest_path.write_text(json.dumps(mutated))
                    bad_output = root / f"recovered_bad_identity_{field}"
                    with self.assertRaisesRegex(
                            RecoveryError, "identity validation|unsupported recovery"):
                        recover_pnr_handoff(source, bad_output, root)
                    self.assertFalse(bad_output.exists())
            missing_identity = copy.deepcopy(baseline_manifest)
            del missing_identity["config_sha256"]
            manifest_path.write_text(json.dumps(missing_identity))
            missing_identity_output = root / "recovered_missing_identity"
            with self.assertRaisesRegex(RecoveryError, "missing required identity"):
                recover_pnr_handoff(source, missing_identity_output, root)
            self.assertFalse(missing_identity_output.exists())

            dc_baseline = json.loads(external_dc_manifest.read_text())
            dc_mutated = copy.deepcopy(dc_baseline)
            dc_mutated["source_role_sha256"] = "0" * 64
            external_dc_manifest.write_text(json.dumps(dc_mutated))
            nested_mutation = copy.deepcopy(baseline_manifest)
            nested_hash = asicctl.sha256_file(external_dc_manifest)
            nested_mutation["dc_input_manifest_sha256"] = nested_hash
            nested_mutation["files"]["dc_input_manifest"]["sha256"] = nested_hash
            manifest_path.write_text(json.dumps(nested_mutation))
            bad_nested_output = root / "recovered_bad_nested_identity"
            with self.assertRaisesRegex(RecoveryError, "nested DC input identity"):
                recover_pnr_handoff(source, bad_nested_output, root)
            self.assertFalse(bad_nested_output.exists())
            external_dc_manifest.write_text(json.dumps(dc_baseline))
            manifest_path.write_text(json.dumps(baseline_manifest))

            contract_path = source / "openroad_contract.txt"
            contract_text = contract_path.read_text()
            contract_path.write_text(contract_text.replace(
                "top=cpu_top", "top=untracked_top"))
            bad_top_output = root / "recovered_bad_contract_top"
            with self.assertRaisesRegex(RecoveryError, "top differs"):
                recover_pnr_handoff(source, bad_top_output, root)
            self.assertFalse(bad_top_output.exists())
            contract_path.write_text(contract_text.replace(
                "expected_macro_count=0", "expected_macro_count=1"))
            bad_macro_output = root / "recovered_bad_contract_macro"
            with self.assertRaisesRegex(RecoveryError, "macro count differs"):
                recover_pnr_handoff(source, bad_macro_output, root)
            self.assertFalse(bad_macro_output.exists())
            contract_path.write_text(contract_text)

            manifest = copy.deepcopy(baseline_manifest)
            manifest["files"]["dc_mapped_netlist"]["sha256"] = "0" * 64
            manifest_path.write_text(json.dumps(manifest))
            with self.assertRaisesRegex(RecoveryError, "input manifest hash mismatch"):
                recover_pnr_handoff(source, root / "recovered_bad_input_hash", root)
            manifest["files"]["dc_mapped_netlist"]["sha256"] = asicctl.sha256_file(mapped)
            manifest_path.write_text(json.dumps(manifest))
            contract_path.write_text(contract_text.replace(
                "mapped_netlist_sha256=" + asicctl.sha256_file(mapped),
                "mapped_netlist_sha256=" + "0" * 64))
            with self.assertRaisesRegex(
                    RecoveryError, "contract mapped netlist hash mismatch"):
                recover_pnr_handoff(
                    source, root / "recovered_bad_contract_mapped_hash", root)
            contract_path.write_text(contract_text.replace(
                "orfs_import_netlist_sha256=NA",
                "orfs_import_netlist_sha256=" + "0" * 64))
            with self.assertRaisesRegex(
                    RecoveryError, "contract ORFS import hash mismatch"):
                recover_pnr_handoff(
                    source, root / "recovered_bad_contract_import_hash", root)
            contract_path.write_text(contract_text)
            contract_path.write_text(contract_text.replace(
                "orfs_commit=" + "a" * 40, "orfs_commit=" + "c" * 40))
            with self.assertRaisesRegex(RecoveryError, "tracked ASIC matrix"):
                recover_pnr_handoff(
                    source, root / "recovered_stale_orfs_identity", root)
            contract_path.write_text(contract_text)
            summary = recover_pnr_handoff(source, output, root)
            self.assertTrue(summary["route_complete"])
            self.assertFalse((source / "run.ok").exists())
            self.assertTrue((output / "run.ok").is_file())
            self.assertTrue((output / "orfs").is_dir())
            self.assertFalse((output / "orfs").is_symlink())
            recovered_sdc = (output / "handoff/cpu_top_postroute.sdc").read_text()
            self.assertIn("-period 2.352941176", recovered_sdc)
            roles = json.loads((output / "same_run_artifacts.json").read_text())
            self.assertIn("routed_def", roles)
            self.assertIn("gds", roles)
            recovered_contract = (output / "openroad_contract.txt").read_text()
            self.assertIn("orfs_actual_commit=not_embedded", recovered_contract)
            self.assertIn(
                "orfs_commit_verification=image_digest_bound_no_vcs_metadata",
                recovered_contract)
            self.assertTrue((output / "orfs_commit.txt").is_file())
            recovery = json.loads((output / "recovery_manifest.json").read_text())
            self.assertEqual(
                recovery["orfs_workspace_preservation"], "self_contained_copy")
            self.assertEqual(
                recovery["tracked_orfs_identity"]["runtime_identity_policy"],
                asicctl.ORFS_RUNTIME_IDENTITY_POLICY)
            self.assertEqual(
                recovery["recovered_external_input_roles"], ["dc_input_manifest"])
            self.assertEqual(recovery["validated_handoff_identity"], identity)
            self.assertEqual(
                recovery["validated_dc_input_schema"],
                "npc-riscv-open/d8-dc-input-v1",
            )
            recovered_manifest = json.loads((output / "input_manifest.json").read_text())
            recovered_external = Path(
                recovered_manifest["files"]["dc_input_manifest"]["path"])
            self.assertTrue(recovered_external.is_file())
            self.assertEqual(
                recovered_external.resolve().relative_to(output / "input").parts[0],
                "external_roles")
            external_dc_manifest.rename(root / "dc_run/input_manifest.moved")
            (source / "orfs").rename(source / "orfs_moved_after_recovery")
            self.assertTrue((
                output / f"orfs/results/nangate45/{nickname}/base/6_final.gds").is_file())
            self.assertTrue(parse_pnr_run(output)["route_complete"])
            self.assertEqual(asicctl.evidence_check(output), 0)

    def test_sta_summary_requires_setup_hold_coverage_and_parasitics(self):
        with tempfile.TemporaryDirectory() as temp:
            run = Path(temp)
            (run / "run_contract.txt").write_text(
                "top=cpu_top\nanalysis=postroute_extracted_internal_timing\n"
                "memory_mode=registers\nexpected_macro_count=0\nmacro_count=0\n"
                "clock_period_ns=2.0\nlink_ok=1\nread_sdc_ok=1\nread_parasitics_ok=1\n"
                "check_timing_ok=1\nsetup_wns_ns=0.1\nsetup_tns_ns=0.0\n"
                "setup_violation_count=0\nhold_wns_ns=0.02\nhold_tns_ns=0.0\n"
                "hold_violation_count=0\nregister_count=20\nclocked_register_count=20\n"
                "unclocked_sync_endpoint_count=0\nsynchronous_endpoint_coverage_percent=100.0\n"
                "max_transition_violation_count=0\nmax_capacitance_violation_count=0\n"
                "max_fanout_violation_count=0\nmin_period_violation_count=0\n"
                "min_pulse_width_violation_count=0\n")
            for name in (
                "setup_timing.rpt", "hold_timing.rpt", "setup_summary.rpt",
                "hold_summary.rpt", "constraint_violations.rpt", "analysis_coverage.rpt",
                "check_timing.rpt",
                "macro_instances.rpt",
            ):
                (run / name).write_text("clean\n")
            (run / "parasitic_annotation.rpt").write_text("All parasitics are annotated\n")
            (run / "primetime.log").write_text("PrimeTime complete\n")
            self.assertTrue(parse_sta_run(run)["sta_closed"])
            (run / "run_contract.txt").write_text(
                (run / "run_contract.txt").read_text().replace("hold_wns_ns=0.02", "hold_wns_ns=-0.01"))
            self.assertFalse(parse_sta_run(run)["sta_closed"])
            sram_contract = (run / "run_contract.txt").read_text()
            sram_contract = sram_contract.replace(
                "memory_mode=registers\nexpected_macro_count=0\nmacro_count=0",
                "memory_mode=sram\nexpected_macro_count=4\nmacro_count=4")
            (run / "run_contract.txt").write_text(sram_contract)
            self.assertEqual(
                parse_sta_run(run)["status"],
                "SRAM_IMPLEMENTATION_COMPLETE_TIMING_PARTIAL")

    def test_evidence_check_rejects_empty_root(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(asicctl.AsicError, "no ASIC input manifests"):
                asicctl.evidence_check(Path(temp))

    def test_evidence_check_rejects_input_hash_drift(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            artifact = root / "mapped.v"
            artifact.write_text("module cpu_top; endmodule\n")
            (root / "input_manifest.json").write_text(json.dumps({
                "schema": "npc-riscv-open/d7-dc-input-v1",
                "files": {
                    "mapped_netlist": {
                        "path": str(artifact),
                        "sha256": "0" * 64,
                    },
                },
            }))
            with self.assertRaisesRegex(asicctl.AsicError, "hash drift"):
                asicctl.evidence_check(root)

    def test_evidence_check_rejects_sta_without_same_run_identity(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            artifact = root / "postroute.v"
            artifact.write_text("module cpu_top; endmodule\n")
            (root / "input_manifest.json").write_text(json.dumps({
                "schema": "npc-riscv-open/d7-sta-input-v1",
                "files": {
                    "routed_netlist": {
                        "path": str(artifact),
                        "sha256": asicctl.sha256_file(artifact),
                    },
                },
            }))
            with self.assertRaisesRegex(asicctl.AsicError, "missing same_run_artifacts"):
                asicctl.evidence_check(root)

    def test_evidence_check_rejects_routed_def_and_gds_hash_drift(self):
        for role, filename in (("routed_def", "cpu_top_postroute.def"),
                               ("gds", "cpu_top.gds")):
            with self.subTest(role=role), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                handoff = root / "handoff"
                handoff.mkdir()
                artifacts = {
                    "routed_netlist": ("cpu_top_postroute.v", "pnr_output_sha256"),
                    "routed_sdc": ("cpu_top_postroute.sdc", "pnr_output_sha256"),
                    "routed_database": ("cpu_top_postroute.odb", "pnr_output_sha256"),
                    "routed_def": ("cpu_top_postroute.def", "pnr_output_sha256"),
                    "spef": ("cpu_top_postroute.spef", "openrcx_output_sha256"),
                    "gds": ("cpu_top.gds", "pnr_output_sha256"),
                }
                same = {"mapped_netlist": {
                    "dc_output_sha256": "a" * 64,
                    "pnr_input_sha256": "a" * 64,
                    "orfs_import_sha256": "a" * 64,
                }}
                for artifact_role, (name, key) in artifacts.items():
                    path = handoff / name
                    path.write_text(f"{artifact_role}\n")
                    same[artifact_role] = {key: asicctl.sha256_file(path)}
                same["routed_database"]["openrcx_input_sha256"] = (
                    same["routed_database"]["pnr_output_sha256"])
                (root / "same_run_artifacts.json").write_text(json.dumps(same))
                (root / "input_manifest.json").write_text(json.dumps({
                    "schema": "npc-riscv-open/d8-pnr-input-v1",
                    "files": {},
                }))
                (root / "openroad_contract.txt").write_text("top=cpu_top\n")
                (handoff / filename).write_text("corrupted\n")
                with self.assertRaisesRegex(asicctl.AsicError, f"hash drift for {role}"):
                    asicctl.evidence_check(root)

    def test_a3_dc_evaluation_passes_all_merge_guards(self):
        result = evaluate_a3_dc(
            self.a3_matrix("legacy", LEGACY_COMMIT, 2.0, source_set="legacy"),
            self.a3_matrix("a3_split_off", A3_COMMIT, 2.0),
            self.a3_matrix("a3", A3_COMMIT, 1.8),
            self.a3_cpi_identity(),
        )
        self.assertEqual(result["status"], "A3_DC_MERGE_PASS")
        self.assertTrue(result["merge_allowed"])

    def test_a3_dc_evaluation_fails_closed_on_loop(self):
        candidate = self.a3_matrix("a3", A3_COMMIT, 1.8)
        candidate["rows"][0]["timing_loop_evidence"] = 1
        result = evaluate_a3_dc(
            self.a3_matrix("legacy", LEGACY_COMMIT, 2.0, source_set="legacy"),
            self.a3_matrix("a3_split_off", A3_COMMIT, 2.0),
            candidate,
            self.a3_cpi_identity(),
        )
        self.assertEqual(result["status"], "A3_DC_INCONCLUSIVE_LOOP")
        self.assertFalse(result["merge_allowed"])

    def test_a3_dc_evaluation_requires_cpi_identity(self):
        cpi = copy.deepcopy(self.a3_cpi_identity())
        cpi["rows"][0]["cycle_identity"] = False
        result = evaluate_a3_dc(
            self.a3_matrix("legacy", LEGACY_COMMIT, 2.0, source_set="legacy"),
            self.a3_matrix("a3_split_off", A3_COMMIT, 2.0),
            self.a3_matrix("a3", A3_COMMIT, 1.8),
            cpi,
        )
        self.assertEqual(result["status"], "A3_DC_REJECT")
        self.assertFalse(result["merge_allowed"])

    def test_a3_dc_evaluation_rejects_public_bounded_adapter(self):
        cpi = copy.deepcopy(self.a3_cpi_identity())
        cpi["difftest_reference"]["public_bounded_adapter_used"] = True
        result = evaluate_a3_dc(
            self.a3_matrix("legacy", LEGACY_COMMIT, 2.0, source_set="legacy"),
            self.a3_matrix("a3_split_off", A3_COMMIT, 2.0),
            self.a3_matrix("a3", A3_COMMIT, 1.8),
            cpi,
        )
        self.assertEqual(result["status"], "A3_DC_REJECT")
        self.assertFalse(result["merge_allowed"])

    def test_a3_cpi_builder_requires_and_binds_all_rows(self):
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            csv_path = root / "a3.csv"
            fields = (
                "profile", "workload", "binary_sha256", "cycles", "instructions",
                "cpi", "commit_trace_lines", "commit_pc_instruction_sha256",
                "cycle_identity", "instruction_identity", "trace_identity", "guard_status",
            )
            with csv_path.open("w", newline="") as stream:
                writer = csv.DictWriter(stream, fieldnames=fields)
                writer.writeheader()
                for row in self.a3_cpi_identity()["rows"]:
                    writer.writerow({
                        **row,
                        "binary_sha256": "a" * 64,
                        "cycles": 10,
                        "instructions": 12,
                        "cpi": "0.833333333",
                        "commit_trace_lines": 11,
                        "commit_pc_instruction_sha256": "b" * 64,
                    })
            evidence = root / "evidence.txt"
            evidence.write_text(
                "profile=rv32im_4k_v1\n"
                "implementation_commit=354f2e4a2d8cc8c96bd76949d61dec24f7247afd\n"
                "functional_status=A3_CYCLE_IDENTITY_PASS\n"
                "evidence_002_sha256={}\n"
                "nemu_commit={}\n"
                "nemu_so_sha256={}\n".format(
                    asicctl.sha256_file(csv_path), "a" * 40, "b" * 64
                )
            )
            reference_so = root / "profile-reference.so"
            reference_so.write_bytes(b"profile-matched-reference")
            so_sha = asicctl.sha256_file(reference_so)
            evidence.write_text(
                evidence.read_text().replace("b" * 64, so_sha)
            )
            reference_config = root / ".config"
            reference_config.write_text(
                'CONFIG_ISA="riscv32"\n'
                "CONFIG_RISCV_FPGA_MMIO_LAYOUT=y\n"
                "CONFIG_DEVICE=y\n"
                "CONFIG_RTC_MMIO=0xa0000048\n"
            )
            result = build_a3_cpi_identity(
                csv_path, evidence, reference_so, reference_config
            )
            self.assertEqual(result["source_commit"], A3_COMMIT)
            self.assertEqual(result["row_count"], 14)
            self.assertEqual(result["status"], "A3_CYCLE_IDENTITY_PASS")
            self.assertEqual(
                result["difftest_reference"]["nemu_so_sha256"], so_sha
            )


if __name__ == "__main__":
    unittest.main()
