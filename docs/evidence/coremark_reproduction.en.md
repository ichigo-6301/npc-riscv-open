# CoreMark public runtime evidence

This record describes auditable headless Verilator runs only. It does not upgrade
the numbers to a `verified` claim: the CoreMark inputs and build tree are external
files and are not committed to the project snapshot. The evidence state is
`provisional_external_input`.

## Fixed conditions

- Public source snapshot: `25cce067d41b37151c45acd8a3069c445dbcb7b5`; the
  documentation update does not change any RTL source-set hash.
- Profile source commits: Single `f76de57479b798aca7468f999c386bb4cb5fce02`,
  Linux `abf66cad0f9ad02efc8beb641d4005adeaeeae0b`, and OoO
  `99fcc2be539eabb078c0d73b26a7ef2c00071391`.
- Runner: `sim/common/verilator_runner.py`; Verilator `5.008`; seed `1`;
  watchdog `10000000`; VCD, itrace, mtrace, ftrace, and pmemtrace were off.
- CoreMark/AM source commit: `034e6c6b5902709546fa74ad70e3a3238ecee576`;
  the measurement configuration sets `ITERATIONS` to `10`, with
  `core_portme.h` SHA256 `beaafe65699ef47191d6153fa9d6913ab5928a5b98e6c6f8949a31aad892335e`;
  compiler: `riscv64-linux-gnu-gcc 11.4.0`.
- Retired-instruction definition: `commit` for Single/Linux, and
  `commit + commit2` for OoO, using valid wrapper commit packets.

## Current public headless runtime

The input binaries are not bundled. The hashes below are the identity to use
when obtaining and checking each external input:

Run these commands from the project root, replacing `external/...` with a local
input whose hash matches the table:

```sh
python3 sim/common/verilator_runner.py --profile rv32im_single_perf \
  --filelist filelists/rv32im_single_perf.f --build-dir build/coremark-public \
  --image external/coremark-riscv32-M-npc.bin --watchdog 10000000

python3 sim/common/verilator_runner.py --profile rv32ima_sv32_linux \
  --filelist filelists/rv32ima_sv32_linux.f --build-dir build/coremark-public \
  --image external/coremark-riscv32s-M-fpga.bin --watchdog 10000000 \
  --ifetch-latency 0 --lsu-latency 0 --memory-latency 0

python3 sim/common/verilator_runner.py --profile rv32im_ooo_4k \
  --filelist filelists/rv32im_ooo_4k.f --build-dir build/coremark-public \
  --image external/coremark-riscv32-M-npc.bin --watchdog 10000000
```

| Profile | Binary / ELF SHA256 | Runtime latency | Cycles | Retired instructions | CPI | CoreMark stop |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `rv32im_single_perf` | `coremark-riscv32-M-npc.bin` / `46c58bd81c055444cac483d7f83038774d9afd0c9c2f2c62ac4916f720e3a1bd` (ELF); binary `ea230c1a3766d7ea5726d8ff53f0a615bfa2cd7f7d2c98a69d0c829c432a663d` | `2/3/2` (IF/LSU/memory) | `4578475` | `3081067` | `1.486003063` | `CoreMark PASS`, ebreak |
| `rv32ima_sv32_linux` | `coremark-riscv32s-M-fpga.bin` / `8d6a55b2766fe039267ea3bc8b8457d296689872d45dccccb39861de960cc774` (ELF); binary `814002f10fb0f2e4338fb07d8b421dc7c3c4bb4f06e633d1426f867133f39cdb` | `0/0/0`; public filelist uses `NPC_DCACHE_WRITE_ALLOCATE=1` | `5668250` | `3252429` | `1.742774400` | `CoreMark PASS`, ebreak |
| `rv32im_ooo_4k` | `coremark-riscv32-M-npc.bin` / ELF `46c58bd81c055444cac483d7f83038774d9afd0c9c2f2c62ac4916f720e3a1bd`; binary `ea230c1a3766d7ea5726d8ff53f0a615bfa2cd7f7d2c98a69d0c829c432a663d` | `2/3/2` (IF/LSU/memory) | `2718694` | `3081098` (`2040454 + 1040644`) | `0.882378295` | `CoreMark PASS`, ebreak |

The corresponding `PUBLIC_SIM_PASS` lines are:

```text
single: PUBLIC_SIM_PASS cycles=4578475 commit=3081067 commit2=0
linux:  PUBLIC_SIM_PASS cycles=5668250 commit=3252429 commit2=0
ooo:    PUBLIC_SIM_PASS cycles=2718694 commit=2040454 commit2=1040644
```

OoO uses the M-mode binary. Placing the Linux/Sv32 binary in OoO stops in the
Sv32 trap handler and is not an OoO CoreMark result.

These runs did not enable difftest. Profile-matched adapter attempts produced:

- Single: the current `device=false` NEMU contract rejected legacy RTC access at
  `0xa0000048`;
- Linux: the same contract rejected AXI timer access at `0xa0000000`;
- OoO: a deterministic mismatch at commit ordinal 11 (`x8` reference `0`, DUT
  `0xb`).

The three rows are therefore “runtime PASS, difftest not accepted” provisional
data, not architecture-level verified claims. Host milliseconds and Marks in the
DPI runtime output are only stop sanity checks; without an implemented clock they
cannot be converted to CoreMark/MHz.

## Private rerun of the later Linux checkpoint

To confirm the historical `≈1.72`, the later source commit
`abf66cad0f9ad02efc8beb641d4005adeaeeae0b` was rerun with the same S-mode binary
and the private `NPC_DCACHE_WRITE_ALLOCATE=0` configuration:

```text
cycles=5613732
committed=3252492
CPI=1.7259787264657377
```

CoreMark PASS, GOOD TRAP, CPI-attribution mismatch `0`, and unknown `0`.
Private run log SHA256 is `25b995dd6e12d9e77284f5552667d149d7c77986f3bcb722e7e2aa62449b4451`;
the build log SHA256 is `13e01b226d40c4e633246e1cc08244d3a16ae3f976c4ed39425ef0a19839984d`;
the CoreMark build log SHA256 is `3a7ac0ed58723aa0d233ea2305daeb6e31fa1d82347488f9416191c706c24ba8`.
This confirms the historical `≈1.72` and also explains why it differs from the
current public Linux filelist (`WRITE_ALLOCATE=1`, CPI `1.742774400`); they are
not the same configuration.

The historical rerun remains `provisional`: the binary, full private build tree,
and NEMU/AM dependencies are not in the public repository. The public table keeps
the exact CPI and conditions; frequency, area, CoreMark/MHz, and seven-workload
weighted CPI remain empty.
