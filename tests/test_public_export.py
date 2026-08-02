#!/usr/bin/env python3
"""Fail-closed tests for the private-to-public NPC exporter."""

from __future__ import annotations

import copy
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock


OPEN_ROOT = Path(__file__).resolve().parents[1]
DELIVERY_ROOT = OPEN_ROOT.parent / "delivery"
EXPORTER_PATH = OPEN_ROOT / "export/export_public_repo.py"

exporter = None
if EXPORTER_PATH.is_file():
    SPEC = importlib.util.spec_from_file_location("npc_public_export", EXPORTER_PATH)
    assert SPEC is not None and SPEC.loader is not None
    exporter = importlib.util.module_from_spec(SPEC)
    SPEC.loader.exec_module(exporter)


@unittest.skipUnless(exporter is not None, "private exporter is not published")
class PublicExportPolicyTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.config = exporter.load_private_yaml(
            DELIVERY_ROOT / "release/public_ip.yaml"
        )
        cls.source_manifest = json.loads(
            (OPEN_ROOT / "export/source_allowlist.json").read_text()
        )
        cls.commits = {
            item["profile_id"]: item["source_commit"]
            for item in cls.source_manifest["profiles"]
        }
        cls.policy = exporter.load_release_policy(
            DELIVERY_ROOT / "release/policy.yaml"
        )

    def test_claim_and_nonclaim_exports_match_exact_selectors(self) -> None:
        claim_ids = exporter.selector_ids(self.config, "public_claim_ids")
        claims = exporter.public_claims(DELIVERY_ROOT, self.commits, claim_ids)
        self.assertEqual(claim_ids, [item["id"] for item in claims["claims"]])

        nonclaim_ids = exporter.selector_ids(self.config, "public_nonclaim_ids")
        nonclaims = exporter.public_nonclaims(
            DELIVERY_ROOT, self.commits, nonclaim_ids
        )
        self.assertEqual(
            nonclaim_ids, [item["id"] for item in nonclaims["nonclaims"]]
        )

    def test_unknown_and_duplicate_selectors_fail_closed(self) -> None:
        with self.assertRaisesRegex(SystemExit, "duplicate public_claim_ids"):
            exporter.selector_ids(
                {"public_claim_ids": ["duplicate", "duplicate"]},
                "public_claim_ids",
            )
        with self.assertRaisesRegex(SystemExit, "does not exist"):
            exporter.public_claims(
                DELIVERY_ROOT, self.commits, ["missing_public_claim"]
            )

    def test_selected_claim_source_drift_fails_closed(self) -> None:
        drifted = dict(self.commits)
        drifted["rv32im_single_perf"] = "0" * 40
        with self.assertRaisesRegex(SystemExit, "source drift"):
            exporter.public_claims(
                DELIVERY_ROOT,
                drifted,
                ["single_public_coremark_timed_cpi"],
            )

    def test_hygiene_rejects_paths_without_matching_checker_regex(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "checker.py").write_text(
                'PRIVATE_PATH_RE = re.compile(r"(?:/home/|/mnt/|[A-Za-z]:[\\\\/])")\n'
            )
            (root / "linux_leak.txt").write_text(
                'root = "' + "/" + 'home/user/private"\n'
            )
            (root / "mount_leak.txt").write_text(
                "root=" + "/" + "mnt/private\n"
            )
            (root / "windows_leak.txt").write_text(
                'root = "' + "C:" + '\\Users\\private"\n'
            )
            (root / "markdown_leak.md").write_text(
                "path: `" + "/" + "home/user/private`\n"
            )
            (root / "host_leak.txt").write_text(
                "host=" + "192." + "168.64.130\n"
            )
            findings = exporter.scan_public_tree(root)
            self.assertFalse(any("checker.py" in item for item in findings))
            for name in (
                "linux_leak.txt",
                "mount_leak.txt",
                "windows_leak.txt",
                "markdown_leak.md",
                "host_leak.txt",
            ):
                self.assertTrue(any(name in item for item in findings), findings)

    def test_asset_copy_rejects_protected_and_raw_eda_payloads(self) -> None:
        self.assertTrue(exporter.git_ignored_path(OPEN_ROOT / "tests/__pycache__"))
        for name in (
            ".config",
            "timing.rpt",
            "route.log",
            "fpga.bit",
            ".Xil/state.txt",
            "pdk/view.txt",
            "tool_cache/tool.bin.txt",
            "nvboard/payload.txt",
        ):
            with self.subTest(name=name), tempfile.TemporaryDirectory() as temp:
                root = Path(temp)
                source = root / "source"
                source.mkdir()
                payload = source / name
                payload.parent.mkdir(parents=True, exist_ok=True)
                payload.write_text("private payload\n")
                with self.assertRaisesRegex(
                    SystemExit, "forbidden generated/local asset|forbidden public asset"
                ):
                    exporter.copy_tree(source, root / "public")

    def test_release_policy_enforces_file_and_bundle_size_limits(self) -> None:
        policy = dict(self.policy)
        policy["max_file_bytes"] = 4
        policy["max_bundle_bytes"] = 6
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "source.txt"
            source.write_bytes(b"12345")
            with self.assertRaisesRegex(SystemExit, "max_file_bytes=4"):
                exporter.copy_file(source, root / "out.txt", policy=policy)

        policy["max_file_bytes"] = 10
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "left.txt").write_bytes(b"1234")
            (root / "right.txt").write_bytes(b"5678")
            findings = exporter.scan_public_tree(root, policy=policy)
            self.assertTrue(
                any("max_bundle_bytes=6" in item for item in findings), findings
            )

    def test_final_scan_rejects_empty_policy_directory_and_bitstream(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / ".Xil").mkdir()
            (root / "design.bit").write_bytes(b"bitstream")
            findings = exporter.scan_public_tree(root, policy=self.policy)
            self.assertTrue(any(".Xil" in item for item in findings), findings)
            self.assertTrue(any("design.bit" in item for item in findings), findings)

    def test_manifest_paths_and_verilog_defines_fail_closed(self) -> None:
        mutations = (
            (
                "include",
                lambda item: item["compile"]["include_dirs"].__setitem__(
                    0, "../../private"
                ),
            ),
            (
                "include whitespace",
                lambda item: item["compile"]["include_dirs"].__setitem__(
                    0, "rtl/private include"
                ),
            ),
            (
                "wrapper",
                lambda item: item.__setitem__("wrapper", "../../wrapper.sv"),
            ),
            (
                "destination",
                lambda item: item["entries"][0].__setitem__(
                    "destination", "../../rtl.sv"
                ),
            ),
            (
                "backslash destination",
                lambda item: item["entries"][0].__setitem__(
                    "destination", "rtl\\..\\private.sv"
                ),
            ),
            (
                "forbidden destination",
                lambda item: item["entries"][0].__setitem__(
                    "destination", "pdk/private.sv"
                ),
            ),
            (
                "define",
                lambda item: item["compile"]["verilog_defines"].__setitem__(
                    0, "NPC_OK\n../../private"
                ),
            ),
        )
        for name, mutate in mutations:
            with self.subTest(name=name):
                candidate = copy.deepcopy(self.source_manifest)
                mutate(candidate["profiles"][0])
                with self.assertRaises(SystemExit):
                    exporter.validate_export_manifest(candidate, self.policy)

    def test_overlay_must_replace_one_unique_base_asic_entry(self) -> None:
        single_index = next(
            index for index, item in enumerate(self.source_manifest["profiles"])
            if item["profile_id"] == "rv32im_single_perf"
        )

        outside = copy.deepcopy(self.source_manifest)
        outside["profiles"][single_index]["memory_mode_overlays"][0][
            "logical_destination"
        ] = "rtl/profiles/rv32im_single_perf/cache/NotInBase.v"
        with self.assertRaisesRegex(SystemExit, "does not name a base RTL entry"):
            exporter.validate_export_manifest(outside, self.policy)

        duplicate = copy.deepcopy(self.source_manifest)
        profile = duplicate["profiles"][single_index]
        extra = copy.deepcopy(profile["memory_mode_overlays"][0])
        extra["destination"] = (
            "rtl/asic/overlays/rv32im_single_perf_sram/cache/Duplicate.v"
        )
        profile["memory_mode_overlays"].append(extra)
        with self.assertRaisesRegex(SystemExit, "duplicate .* logical overlay"):
            exporter.validate_export_manifest(duplicate, self.policy)

    def test_reserved_generated_destinations_fail_before_export(self) -> None:
        for destination in (
            "provenance/imports.json",
            "filelists/rv32im_ooo_4k.f",
            "SHA256SUMS",
        ):
            with self.subTest(destination=destination):
                candidate = copy.deepcopy(self.source_manifest)
                ooo = next(
                    item for item in candidate["profiles"]
                    if item["profile_id"] == "rv32im_ooo_4k"
                )
                ooo["provenance_entries"][0]["destination"] = destination
                with self.assertRaisesRegex(SystemExit, "provenance destination"):
                    exporter.validate_export_manifest(candidate, self.policy)

        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            manifest = root / "manifest.json"
            output = root / "public"
            candidate = copy.deepcopy(self.source_manifest)
            ooo = next(
                item for item in candidate["profiles"]
                if item["profile_id"] == "rv32im_ooo_4k"
            )
            ooo["provenance_entries"][0]["destination"] = "provenance/imports.json"
            manifest.write_text(json.dumps(candidate), encoding="utf-8")
            completed = subprocess.run(
                [
                    sys.executable,
                    str(EXPORTER_PATH),
                    "--manifest",
                    str(manifest),
                    "--output",
                    str(output),
                ],
                check=False,
                capture_output=True,
                text=True,
            )
            self.assertNotEqual(completed.returncode, 0)
            self.assertIn("provenance destination", completed.stderr)

    def test_generated_writers_use_exclusive_create(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            target = root / "generated.json"
            target.write_text("allowlisted bytes\n", encoding="utf-8")
            with self.assertRaisesRegex(SystemExit, "target collision"):
                exporter.write_json(target, {"replacement": True})

            checksum = root / "SHA256SUMS"
            checksum.write_text("allowlisted bytes\n", encoding="utf-8")
            with self.assertRaisesRegex(SystemExit, "target collision"):
                exporter.write_checksums(root)

    def test_public_source_policy_cannot_disable_identity_gates(self) -> None:
        for gate in self.config["source_policy"]:
            with self.subTest(gate=gate):
                candidate = copy.deepcopy(self.config)
                candidate["source_policy"][gate] = False
                with self.assertRaisesRegex(SystemExit, "source_policy"):
                    exporter.validate_public_source_policy(candidate)

    def test_scan_rejects_account_password_and_license_server_values(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            payloads = {
                "account.txt": "ssh " + "ICer" + "@" + "host\n",
                "password.txt": "pass" + "word=hunter2\n",
                "license_var.txt": "LM_" + "LICENSE_FILE=27000" + "@" + "server\n",
                "license_endpoint.txt": "27000" + "@" + "license-host\n",
                "bearer.txt": "Bear" + "er abcdefghijklmnopqrstuvwxyz\n",
            }
            for name, value in payloads.items():
                (root / name).write_text(value)
            (root / "safe_refs.txt").write_text(
                "uses: actions/checkout@v4\n"
                "image: openroad/orfs@sha256:" + "0" * 64 + "\n"
            )
            findings = exporter.scan_public_tree(root, policy=self.policy)
            for name in payloads:
                self.assertTrue(any(name in item for item in findings), findings)
            self.assertFalse(any("safe_refs.txt" in item for item in findings), findings)

    def test_export_rtl_rejects_byte_and_git_blob_drift(self) -> None:
        data = b"module sample; endmodule\n"
        blob = "a" * 40
        entry = {
            "source": "rtl/sample.sv",
            "destination": "rtl/profiles/sample/sample.sv",
            "blob": blob,
            "sha256": exporter.sha256(data),
            "bytes": len(data),
            "roles": ["asic"],
        }
        profile = {
            "profile_id": "sample",
            "source_commit": "b" * 40,
            "wrapper": "rtl/wrappers/sample.sv",
            "compile": {
                "include_dirs": ["rtl"],
                "verilog_defines": ["NPC_ASIC"],
            },
            "entry_count": 1,
            "entries": [entry],
            "implementation_source_sets": {
                "registers": {
                    "logical_entry_count": 1,
                    "overlay_destinations": [],
                }
            },
        }

        with mock.patch.object(exporter, "git_show", return_value=data), \
                mock.patch.object(exporter, "git_blob_id", return_value=blob):
            with tempfile.TemporaryDirectory() as temp:
                candidate = {"profiles": [copy.deepcopy(profile)]}
                candidate["profiles"][0]["entries"][0]["bytes"] += 1
                with self.assertRaisesRegex(SystemExit, "byte-size drift"):
                    exporter.export_rtl(Path(temp), candidate, policy=self.policy)

            with tempfile.TemporaryDirectory() as temp:
                candidate = {"profiles": [copy.deepcopy(profile)]}
                candidate["profiles"][0]["entries"][0]["blob"] = "c" * 40
                with self.assertRaisesRegex(SystemExit, "Git blob drift"):
                    exporter.export_rtl(Path(temp), candidate, policy=self.policy)

    def _stage_evidence_payloads(self, out: Path) -> None:
        shutil.copytree(OPEN_ROOT / "evidence", out / "evidence")
        shutil.copytree(OPEN_ROOT / "docs/assets", out / "docs/assets")
        (out / "evidence/performance").mkdir(parents=True)
        shutil.copy2(
            OPEN_ROOT / "control/evidence/performance/coremark.json",
            out / "evidence/performance/coremark.json",
        )
        (out / "flows/scripts").mkdir(parents=True)
        shutil.copy2(
            OPEN_ROOT / "flows/scripts/generate_showcase_assets.py",
            out / "flows/scripts/generate_showcase_assets.py",
        )
        claims = exporter.public_claims(
            DELIVERY_ROOT,
            self.commits,
            exporter.selector_ids(self.config, "public_claim_ids"),
        )
        exporter.write_json(out / "delivery/claims/claims.yaml", claims)

    def test_evidence_export_matches_selectors_and_has_public_paths(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            self._stage_evidence_payloads(out)
            exporter.write_public_evidence_manifest(out, self.config)
            manifest_path = out / "delivery/evidence/manifest.yaml"
            manifest = json.loads(manifest_path.read_text())
            selected = exporter.selector_ids(self.config, "public_evidence_ids")
            self.assertEqual(selected, [item["id"] for item in manifest["evidence"]])
            text = manifest_path.read_text()
            self.assertNotIn("../open/", text)
            self.assertNotIn(str(OPEN_ROOT.parent.parent), text)
            for record in manifest["evidence"]:
                self.assertNotIn("open/", str(record["path"]))

    def test_evidence_hash_drift_fails_closed(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            self._stage_evidence_payloads(out)
            evidence = out / "evidence/implementation/nangate45_fixed_points.json"
            evidence.write_bytes(evidence.read_bytes() + b"\n")
            with self.assertRaisesRegex(SystemExit, "hash drift"):
                exporter.write_public_evidence_manifest(out, self.config)

    def test_every_nested_evidence_path_requires_matching_sha256(self) -> None:
        with tempfile.TemporaryDirectory() as temp:
            out = Path(temp)
            evidence = out / "evidence/source.json"
            evidence.parent.mkdir(parents=True)
            evidence.write_text("{}\n")
            relative = "../evidence/source.json"
            digest = exporter.sha256(evidence.read_bytes())

            exporter.validate_evidence_file_refs(
                out,
                {"source_files": [{"path": relative, "sha256": digest}]},
                "test_evidence",
            )
            with self.assertRaisesRegex(SystemExit, "lacks SHA256"):
                exporter.validate_evidence_file_refs(
                    out,
                    {"source_files": [{"path": relative}]},
                    "test_evidence",
                )
            with self.assertRaisesRegex(SystemExit, "hash drift"):
                exporter.validate_evidence_file_refs(
                    out,
                    {"generator": {"path": relative, "sha256": "0" * 64}},
                    "test_evidence",
                )


if __name__ == "__main__":
    unittest.main()
