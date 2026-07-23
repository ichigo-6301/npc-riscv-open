# CoreMark measurement and reproduction evidence

[中文](coremark_reproduction.md)

This page records the input identity, timing boundary, result state, and
reproduction procedure for the current headless Verilator CoreMark runs. The
machine-readable numeric source is
[`evidence/performance/coremark.json`](../../evidence/performance/coremark.json),
and the input contract is
[`delivery/benchmarks/coremark.json`](../../delivery/benchmarks/coremark.json).

## Fixed inputs

- AM/CoreMark commit: `034e6c6b5902709546fa74ad70e3a3238ecee576`.
- `ITERATIONS=10`, one context; patch SHA256:
  `586abb219713ac368b5e2d79289ce67a133af334346908328628f69d8e86279d`.
- Compiler: `riscv64-linux-gnu-gcc 11.4.0`; complete flags are in the benchmark manifest.
- Benchmark manifest SHA256:
  `d03f12046d34af83a2487db8594d62ad8b762c256bb6de38d66c0bab4e6f53d0`.
- Seed `1`; watchdog `20,000,000` cycles; VCD, itrace, mtrace, ftrace, and
  pmemtrace are disabled.

| Variant | Profiles | BIN SHA256 | ELF SHA256 | Start marker | Stop marker |
| --- | --- | --- | --- | --- | --- |
| `rv32im_m` | Single, OoO | `601f942b5a32d071dd0170425107875fdc287bb86549c6489622656ea7ff1742` | `0dec53590bd873d2fb4b0055e7f62bfc041eefad686b843e2eb2f867f8a615e3` | PC `0x800015dc`, instr `0x38a7a223` | PC `0x80001618`, instr `0x34a7a623` |
| `rv32ima_sv32` | Linux/Sv32 | `50840465ecda9da48a69a4361b1a479c42428b5331b114dc694658c6928be6c5` | `6aee51c5ea8084fde549169fc3f4360f2e5705057356fc824a2c55943d36bab2` | PC `0x80001788`, instr `0x7ca7a023` | PC `0x800017c4`, instr `0x78a7a423` |

The runner checks BIN, ELF, and the instruction word at each marker. A hash
mismatch, repeated or out-of-order marker, missing marker, or unclosed episode
fails immediately. If several complete episodes exist, the last is selected
while all episode counters remain in the JSON output.

## Measurement boundary

Cycle and global commit ordinal are sampled when the start/stop instruction
retires:

```text
timed_cycles       = stop_commit_cycle - start_commit_cycle
timed_instructions = stop_commit_ordinal - start_commit_ordinal
timed_cpi          = timed_cycles / timed_instructions
coremark_per_mhz   = 10 * 1,000,000 / timed_cycles
```

`whole` runs from reset to ebreak. The `pre`, `timed`, and `post` partitions
must conserve both cycles and retired instructions. Host wall-clock milliseconds
and project-specific `Marks` are sanity checks only and are not performance data.

## Current results

| Profile | Pre cycles/instr | Timed cycles/instr | Post cycles/instr | Timed CPI | CoreMark/MHz | Whole CPI | Difftest | State |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `rv32im_single_perf` | 21,270 / 14,176 | 4,542,529 / 3,059,106 | 14,266 / 7,803 | 1.484920431 | 2.201416876 | 1.485861312 | PASS, 466 MMIO skips | `verified` |
| `rv32ima_sv32_linux` | 313,878 / 184,284 | 5,278,164 / 3,059,140 | 21,561 / 9,057 | 1.725375105 | 1.894598197 | 1.725944902 | PASS, 932 MMIO skips | `verified` |
| `rv32im_ooo_4k` | 15,254 / 14,176 | 2,691,933 / 3,059,106 | 11,540 / 7,834 | 0.879973757 | 3.714802709 | 0.882383851 | Not run: dual-retire MMIO ambiguity | `provisional` |

The Single/Linux adapter decodes known Timer/UART MMIO from the REF state before
execution, performs deterministic skip-and-sync, and resumes PC/instruction/GPR
comparison. Unknown MMIO or a PMEM side effect fails. OoO can retire two packets
in one cycle. If one contains MMIO, the current ABI cannot determine the
reference execute/skip order unambiguously. This contract is not weakened, so
the OoO row is a provisional self-check and accounting result.

## Reproduction

External BIN/ELF files are not tracked. After obtaining local files matching
the manifest exactly:

```sh
make rv32im_single_perf_defconfig
NPC_OPEN_COREMARK_IMAGE=/path/to/coremark-riscv32-M-npc.bin \
NPC_OPEN_COREMARK_ELF=/path/to/coremark-riscv32-M-npc.elf \
make coremark-difftest

make rv32ima_sv32_linux_defconfig
NPC_OPEN_COREMARK_IMAGE=/path/to/coremark-riscv32s-M-fpga.bin \
NPC_OPEN_COREMARK_ELF=/path/to/coremark-riscv32s-M-fpga.elf \
make coremark-difftest

make rv32im_ooo_4k_defconfig
NPC_OPEN_COREMARK_IMAGE=/path/to/coremark-riscv32-M-npc.bin \
NPC_OPEN_COREMARK_ELF=/path/to/coremark-riscv32-M-npc.elf \
make coremark

make performance-check
```

`coremark-difftest` requires local NEMU adapters prepared as described in
[Simulation](../simulation.en.md). Each run emits `PUBLIC_SIM_PASS`,
`PUBLIC_BENCHMARK_EPISODE`, and `PUBLIC_BENCHMARK`, then writes one JSON summary
under `build/performance/<profile>/`.

## Linux parity and configuration interpretation

Private `abf66cad` RTL plus a measurement-only observer and the public wrapper
use the same Sv32 binary and `WRITE_ALLOCATE=0`. Both produce `5,278,164` timed
cycles, `3,059,140` timed instructions, and CPI `1.725375105`. The observer patch
SHA256 is `d3bd6c500dac32403eb6fa7f1fd92933cc4269e844231992f9cd98fdd5515623`.

Private/public whole-program counts are `5,613,479 / 3,252,449` and
`5,613,603 / 3,252,481`; the delta comes from reset/counter indexing and the
final UART/terminal boundary. The `WRITE_ALLOCATE=1` diagnostic has `5,668,419`
whole cycles but only `5,277,919` timed cycles. Relative to the default, the
extra `54,816` whole cycles are almost entirely the `54,999` cycles before the
start marker and do not show an approximately one-percent CoreMark-loop gain.

See [Performance](../performance.en.md), [Verification](../verification.en.md),
and [Limitations](../limitations.en.md).
