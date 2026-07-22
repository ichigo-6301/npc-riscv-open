#!/usr/bin/env python3
"""Dependency-free checks for the public runtime control plane.

These tests do not require Verilator or a private reference model.  They catch
the most damaging release mistakes early: a filelist escaping the repository,
an image parser regression, and a runner that cannot produce a deterministic
dry-run command.
"""

from __future__ import annotations

import importlib.util
import contextlib
import io
from pathlib import Path
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
RUNNER = ROOT / "sim/common/verilator_runner.py"


def load_runner():
    spec = importlib.util.spec_from_file_location("public_verilator_runner", RUNNER)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


class PublicRuntimeTests(unittest.TestCase):
    def test_smoke_image_has_stable_self_check_tail(self):
        words = []
        for line in (ROOT / "tests/rv32im_smoke.hex").read_text().splitlines():
            line = line.split("#", 1)[0].strip()
            words.extend(line.split())
        self.assertEqual(len(words), 28)
        self.assertEqual(words[0], "00100813")
        self.assertEqual(words[-2], "00100073")
        self.assertEqual(words[-1], "0000006f")

    def test_dry_run_is_stable_and_has_no_nvboard(self):
        runner = load_runner()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            filelist = root / "profile.f"
            # The source path is intentionally inside a temporary public root.
            source = root / "dummy.sv"
            source.write_text("module npc_public_sim_top(input logic clk, input logic rst_n); endmodule\n")
            filelist.write_text(f"{source}\n")
            # _read_filelist enforces the same closure rule used by the CLI.
            options, sources = runner._read_filelist(filelist, root)
            self.assertEqual(options, [])
            self.assertEqual(sources, [str(source.resolve())])
            command = " ".join(runner.shlex.quote(x) for x in sources)
            self.assertNotIn("nvboard", command.lower())

    def test_filelist_escape_is_rejected(self):
        runner = load_runner()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            filelist = root / "bad.f"
            filelist.write_text("/etc/passwd\n")
            with self.assertRaises(ValueError):
                runner._read_filelist(filelist, root)

    def test_dry_run_creates_no_build_or_vcd_directory(self):
        runner = load_runner()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            (root / "rtl/wrappers").mkdir(parents=True)
            (root / "filelists").mkdir()
            (root / "Kconfig").write_text("mainmenu \"test\"\n")
            (root / "dummy.sv").write_text(
                "module npc_public_sim_top(input logic clk, input logic rst_n); endmodule\n"
            )
            (root / "filelists/test.f").write_text("dummy.sv\n")
            original_root = runner._repo_root
            runner._repo_root = lambda: root
            try:
                with contextlib.redirect_stdout(io.StringIO()):
                    rc = runner.main([
                        "--profile", "test",
                        "--filelist", str(root / "filelists/test.f"),
                        "--build-dir", "build/no-side-effect",
                        "--vcd", "waves/no-side-effect.vcd",
                        "--dry-run",
                    ])
            finally:
                runner._repo_root = original_root
            self.assertEqual(rc, 0)
            self.assertFalse((root / "build").exists())
            self.assertFalse((root / "waves").exists())


if __name__ == "__main__":
    unittest.main()
