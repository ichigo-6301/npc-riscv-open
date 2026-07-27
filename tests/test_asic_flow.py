import importlib.util
import copy
import csv
import json
from pathlib import Path
import sys
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SCRIPTS = ROOT / "flows/scripts"
sys.path.insert(0, str(SCRIPTS))

import asicctl
import flowctl
from build_a3_cpi_identity import build as build_a3_cpi_identity
from calculate_floorplan import calculate
from compare_a3_dc import A3_COMMIT, LEGACY_COMMIT, evaluate as evaluate_a3_dc
from prepare_pnr_sdc import retarget
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
        (root / "rtl/top.sv").write_text(
            "module cpu_top(input clk, input rst_n, "
            "output [31:0] ibus_axi_araddr, input [31:0] ibus_axi_rdata, "
            "output [31:0] dbus_axi_awaddr, input [31:0] dbus_axi_rdata); "
            "endmodule\n"
        )
        define = "+define+NPC_ASIC\n+define+NPC_USE_DPI\n" if dpi else "+define+NPC_ASIC\n"
        (root / "filelists/asic/rv32im_single_perf.f").write_text(
            define + "rtl/top.sv\n")
        (root / "flows/asic/constraints/internal_clock.sdc").write_text(
            "create_clock -name npc_clk -period 2.0 [get_ports clk]\n")
        commit = "f76de57479b798aca7468f999c386bb4cb5fce02"
        (root / "provenance/source_allowlist.json").write_text(json.dumps({
            "project_id": "npc-riscv-open", "snapshot_id": "v0.1.0",
            "profiles": [{"profile_id": "rv32im_single_perf", "source_commit": commit,
                          "entries": [{"destination": "rtl/top.sv", "sha256": "0" * 64}]}],
        }))
        (root / "flows/asic/profiles/register_expanded.json").write_text(json.dumps({
            "schema": "npc-riscv-open/asic-register-expanded-v1",
            "libraries": {}, "orfs": {},
            "profiles": {"rv32im_single_perf": {
                "source_commit": commit, "top": "cpu_top", "clock_port": "clk",
                "reset_port": "rst_n", "filelist": "filelists/asic/rv32im_single_perf.f",
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

    def test_floorplan_uses_required_area_formula_and_site_snap(self):
        result = calculate(300000.0)
        self.assertGreaterEqual(result["computed_core_area_um2"], 300000.0 * 1.25 / 0.30)
        x0, y0, x1, y1 = result["core_area"]
        self.assertAlmostEqual((x1 - x0) / 0.19, round((x1 - x0) / 0.19), places=6)
        self.assertAlmostEqual((y1 - y0) / 1.4, round((y1 - y0) / 1.4), places=6)
        self.assertEqual(result["place_density"], 0.55)

    def test_pnr_sdc_retargets_exactly_one_clock(self):
        source = "create_clock [get_ports clk] -name npc_clk -period 1.250000\n"
        result = retarget(source, 2.0)
        self.assertIn("-period 2.000000000", result)
        with self.assertRaisesRegex(ValueError, "exactly one"):
            retarget(source + source, 2.0)

    def test_dc_constraint_uses_native_capacitance_and_bounded_fanout(self):
        text = (ROOT / "flows/asic/constraints/internal_clock.sdc").read_text()
        self.assertIn("set_max_transition 0.20", text)
        self.assertIn("set_max_fanout 32", text)
        self.assertNotIn("set_max_capacitance", text)

    def test_dc_check_timing_uses_o2018_compatible_form(self):
        text = (ROOT / "flows/asic/dc/run.tcl").read_text()
        self.assertIn("set check_timing_ok [check_timing]", text)
        self.assertNotIn("check_timing -verbose", text)

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
            for path in (
                results / "1_2_yosys.v", handoff / (top + "_postroute.odb"),
                handoff / (top + "_postroute.def"), handoff / (top + "_postroute.v"),
                handoff / (top + "_postroute.sdc"), handoff / (top + "_postroute.spef"),
                handoff / (top + ".gds"), reports / "5_route_drc.rpt",
            ):
                path.write_text("fixture\n")
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

    def test_sta_summary_requires_setup_hold_coverage_and_parasitics(self):
        with tempfile.TemporaryDirectory() as temp:
            run = Path(temp)
            (run / "run_contract.txt").write_text(
                "top=cpu_top\nanalysis=postroute_extracted_internal_timing\nmacro_count=0\n"
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
            ):
                (run / name).write_text("clean\n")
            (run / "parasitic_annotation.rpt").write_text("All parasitics are annotated\n")
            (run / "primetime.log").write_text("PrimeTime complete\n")
            self.assertTrue(parse_sta_run(run)["sta_closed"])
            (run / "run_contract.txt").write_text(
                (run / "run_contract.txt").read_text().replace("hold_wns_ns=0.02", "hold_wns_ns=-0.01"))
            self.assertFalse(parse_sta_run(run)["sta_closed"])

    def test_evidence_check_rejects_empty_root(self):
        with tempfile.TemporaryDirectory() as temp:
            with self.assertRaisesRegex(asicctl.AsicError, "no D7 input manifests"):
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
