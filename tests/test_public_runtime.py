#!/usr/bin/env python3
"""Dependency-free checks for the public runtime control plane.

These tests do not require Verilator or a private reference model.  They catch
the most damaging packaging mistakes early: a filelist escaping the repository,
an image parser regression, and a runner that cannot produce a deterministic
dry-run command.
"""

from __future__ import annotations

import importlib.util
import contextlib
import hashlib
import io
import json
from pathlib import Path
import shutil
import subprocess
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

    def test_benchmark_contract_accepts_hash_locked_markers(self):
        runner = load_runner()
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            image = root / "coremark.bin"
            elf = root / "coremark.elf"
            manifest = root / "coremark.json"
            image.write_bytes(
                (0x11111113).to_bytes(4, "little") +
                (0x22222223).to_bytes(4, "little")
            )
            elf.write_bytes(b"ELF-test")
            manifest.write_text(json.dumps({
                "schema": "npc-riscv-open/coremark-benchmark-v1",
                "benchmark": "coremark",
                "iterations": 10,
                "contexts": 1,
                "variants": {
                    "test": {
                        "profiles": ["test"],
                        "image_base": "0x80000000",
                        "binary_sha256": hashlib.sha256(image.read_bytes()).hexdigest(),
                        "elf_sha256": hashlib.sha256(elf.read_bytes()).hexdigest(),
                        "markers": {
                            "start": {"pc": "0x80000000", "instr": "0x11111113"},
                            "stop": {"pc": "0x80000004", "instr": "0x22222223"},
                        },
                    }
                },
            }))
            contract = runner.load_contract(manifest, "test", image, elf)
            self.assertEqual(contract["variant"], "test")
            self.assertEqual(contract["iterations"], 10)
            image.write_bytes(b"bad")
            with self.assertRaisesRegex(ValueError, "SHA256 mismatch"):
                runner.load_contract(manifest, "test", image, elf)

    def test_benchmark_tracker_rejects_open_and_duplicate_episodes(self):
        compiler = shutil.which("g++")
        if compiler is None:
            self.skipTest("g++ is not installed")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "tracker_test.cpp"
            binary = root / "tracker_test"
            source.write_text(r'''
#include "benchmark_tracker.hpp"
int main() {
  using namespace npc_public;
  BenchmarkTracker ok({0x1000, 0x11111113}, {0x1004, 0x22222223});
  if (!ok.observe(10, 5, 0x1000, 0x11111113)) return 1;
  if (!ok.observe(20, 15, 0x1004, 0x22222223)) return 2;
  if (!ok.observe(30, 25, 0x1000, 0x11111113)) return 3;
  if (!ok.observe(40, 35, 0x1004, 0x22222223)) return 4;
  if (!ok.finalize() || ok.episodes().size() != 2) return 5;
  BenchmarkTracker open({0x1000, 1}, {0x1004, 2});
  if (!open.observe(1, 1, 0x1000, 1) || open.finalize()) return 6;
  BenchmarkTracker duplicate({0x1000, 1}, {0x1004, 2});
  if (!duplicate.observe(1, 1, 0x1000, 1)) return 7;
  if (duplicate.observe(2, 2, 0x1000, 1)) return 8;
  return 0;
}
''')
            subprocess.run([
                compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                "-I", str(ROOT / "sim/include"), str(source), "-o", str(binary),
            ], check=True)
            subprocess.run([str(binary)], check=True)

    def test_runtime_axi_timer_and_uartlite_status(self):
        compiler = shutil.which("g++")
        if compiler is None:
            self.skipTest("g++ is not installed")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            source = root / "mmio_test.cpp"
            binary = root / "mmio_test"
            source.write_text(r'''
#include <cstdint>
extern "C" void npc_mem_reset(void);
extern "C" void npc_mem_tick(void);
extern "C" uint32_t pmem_read(uint32_t, int);
extern "C" void pmem_write(uint32_t, int, uint32_t);
int main() {
  npc_mem_reset();
  pmem_write(0xa0000004u, 4, 5u);
  pmem_write(0xa0000014u, 4, 0u);
  pmem_write(0xa0000000u, 4, 0x820u);
  pmem_write(0xa0000010u, 4, 0x20u);
  pmem_write(0xa0000010u, 4, 0x80u);
  pmem_write(0xa0000000u, 4, 0x880u);
  npc_mem_tick(); npc_mem_tick(); npc_mem_tick();
  if (pmem_read(0xa0000008u, 4) != 8u) return 1;
  if (pmem_read(0xa0000018u, 4) != 0u) return 2;
  if (pmem_read(0xa0010008u, 4) != 4u) return 3;
  return 0;
}
''')
            subprocess.run([
                compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                str(ROOT / "sim/common/dpi_memory.cpp"), str(source), "-o", str(binary),
            ], check=True)
            subprocess.run([str(binary)], check=True)

    def test_nemu_adapter_syncs_ooo_reset_state_and_single_mmio(self):
        compiler = shutil.which("g++")
        if compiler is None:
            self.skipTest("g++ is not installed")
        with tempfile.TemporaryDirectory() as temp:
            root = Path(temp)
            fake_source = root / "fake_nemu.cpp"
            fake_source.write_text(r'''
#include <cstddef>
#include <cstdint>
#include <cstring>
static uint32_t gpr[32];
static uint32_t pc;
static uint8_t memory[4096];
extern "C" void difftest_init(int) {
  std::memset(gpr, 0, sizeof(gpr));
  std::memset(memory, 0, sizeof(memory));
  pc = 0x80000000u;
}
extern "C" void difftest_memcpy(uint32_t addr, void *buf, size_t size,
                                bool to_ref) {
  uint8_t *target = memory + (addr - 0x80000000u);
  if (to_ref) std::memcpy(target, buf, size);
  else std::memcpy(buf, target, size);
}
extern "C" void difftest_regcpy(void *opaque, bool to_ref) {
  auto *words = static_cast<uint32_t *>(opaque);
  if (to_ref) {
    std::memcpy(gpr, words, sizeof(gpr));
    pc = words[32];
  } else {
    std::memcpy(words, gpr, sizeof(gpr));
    words[32] = pc;
  }
}
extern "C" void difftest_exec(uint64_t count) {
  while (count-- != 0) {
    uint32_t instr = 0;
    std::memcpy(&instr, memory + (pc - 0x80000000u), sizeof(instr));
    const uint32_t opcode = instr & 0x7fu;
    const uint32_t rd = (instr >> 7) & 0x1fu;
    if (opcode == 0x13u) {
      const int32_t imm = static_cast<int32_t>(instr) >> 20;
      gpr[rd] = gpr[(instr >> 15) & 0x1fu] + static_cast<uint32_t>(imm);
    } else if (opcode == 0x37u) {
      gpr[rd] = instr & 0xfffff000u;
    }
    gpr[0] = 0;
    pc += 4;
  }
}
''')
            fake_raw = root / "nemu-ref.so"
            subprocess.run([
                compiler, "-std=c++17", "-shared", "-fPIC", "-Wall",
                "-Wextra", "-Werror", str(fake_source), "-o", str(fake_raw),
            ], check=True)
            harness_source = root / "adapter_test.cpp"
            harness_source.write_text(r'''
#include <cstdint>
#include <cstdlib>
#include <dlfcn.h>
#include <string>
using Init = int (*)(uint32_t, const char *, const char *, uint32_t);
using Step = int (*)(uint64_t, uint32_t, uint32_t, uint32_t, uint32_t,
                     uint32_t, const uint32_t *, uint32_t);
using Fini = void (*)();
template <typename T> T sym(void *handle, const char *name) {
  return reinterpret_cast<T>(dlsym(handle, name));
}
int main(int argc, char **argv) {
  if (argc != 4) return 1;
  void *handle = dlopen(argv[1], RTLD_NOW | RTLD_LOCAL);
  if (!handle) return 2;
  Init init = sym<Init>(handle, "npc_public_difftest_init_v2");
  Step step = sym<Step>(handle, "npc_public_difftest_step");
  Fini fini = sym<Fini>(handle, "npc_public_difftest_fini");
  if (!init || !step || !fini || init(2, argv[2], argv[3], 0x80000000u)) return 3;
  uint32_t gpr[32] = {};
  int status = 0;
  if (std::string(argv[2]) == "rv32im_ooo_4k") {
    for (uint32_t i = 1; i < 32; ++i) gpr[i] = i;
    gpr[8] = 11;
    status = step(1, 0, 0x80000000u, 0x00058413u, 0x80000004u,
                  0x80000004u, gpr, 1);
  } else {
    gpr[6] = 0xa0000000u;
    status = step(1, 0, 0x80000000u, 0xa0000337u, 0x80000004u,
                  0x80000004u, gpr, 1);
    gpr[5] = 1234;
    if (!status) status = step(2, 0, 0x80000004u, 0x00832283u,
                               0x80000008u, 0x80000008u, gpr, 1);
  }
  fini();
  dlclose(handle);
  return status;
}
''')
            harness = root / "adapter_test"
            subprocess.run([
                compiler, "-std=c++17", "-Wall", "-Wextra", "-Werror",
                str(harness_source), "-ldl", "-o", str(harness),
            ], check=True)
            scenarios = (
                ("rv32im_ooo_4k", 1, [0x00058413]),
                ("rv32im_single_perf", 0, [0xA0000337, 0x00832283]),
            )
            for profile, sentinel, words in scenarios:
                scenario = root / profile
                scenario.mkdir()
                shutil.copy2(fake_raw, scenario / "nemu-ref.so")
                image = scenario / "program.bin"
                image.write_bytes(b"".join(word.to_bytes(4, "little") for word in words))
                adapter = scenario / "npc-public-nemu-adapter.so"
                subprocess.run([
                    compiler, "-std=c++17", "-O2", "-shared", "-fPIC",
                    "-Wall", "-Wextra", "-Werror",
                    f'-DNPC_NEMU_PROFILE_ID="{profile}"',
                    '-DNPC_NEMU_RAW_BASENAME="nemu-ref.so"',
                    f"-DNPC_NEMU_DEBUG_SENTINEL={sentinel}",
                    "-I", str(ROOT / "sim/include"),
                    str(ROOT / "sim/adapters/nemu_public_adapter.cpp"),
                    "-ldl", "-o", str(adapter),
                ], check=True)
                subprocess.run([
                    str(harness), str(adapter), profile, str(image),
                ], check=True)


if __name__ == "__main__":
    unittest.main()
