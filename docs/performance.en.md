# Performance and implementation data

[中文](performance.md)

This page separates the timed CoreMark interval, whole-program CPI,
CoreMark/MHz, a finite workload aggregate, and physical implementation metrics.
All current numbers come from
[`evidence/performance/coremark.json`](../evidence/performance/coremark.json).
`make performance-check` validates formulas, input hashes, claims, and both
language surfaces.

## Metric definitions

```text
timed CPI       = stop_commit_cycle - start_commit_cycle
                  ---------------------------------------
                  stop_commit_ordinal - start_commit_ordinal

whole CPI       = reset-to-ebreak cycles / retired instructions

CoreMark/MHz    = iterations * 1,000,000 / timed cycles  # evidence:coremark_public_current
```

This measurement fixes `ITERATIONS=10` and one context. CoreMark/MHz is the
number of iterations per million simulated cycles. It is neither the host
runtime's `Marks` output nor an absolute CoreMark score at an implemented clock;
the latter remains `—`.

## Current CoreMark results

| Profile | Timed cycles / instructions | Timed CPI | CoreMark/MHz | Whole cycles / instructions | Whole CPI | State |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `rv32im_single_perf` | 4,542,529 / 3,059,106 | 1.484920431 | 2.201416876 | 4,578,065 / 3,081,085 | 1.485861312 | `verified`, difftest PASS; `evidence:coremark_public_current` |
| `rv32ima_sv32_linux` | 5,278,164 / 3,059,140 | 1.725375105 | 1.894598197 | 5,613,603 / 3,252,481 | 1.725944902 | `verified`, difftest PASS; `evidence:coremark_public_current` |
| `rv32im_ooo_4k` | 2,691,933 / 3,059,106 | 0.879973757 | 3.714802709 | 2,718,727 / 3,081,116 | 0.882383851 | `provisional`, self-check PASS and dual-retire MMIO difftest ambiguity; `evidence:coremark_public_current` / `nonclaim:ooo_public_coremark_runtime_provisional` |

Single/OoO use the same hash-locked M-mode binary; Linux uses a hash-locked
Sv32 S-mode binary. All three close the CoreMark marker interval and pass the
self-check, good trap, and watchdog. Single/Linux also pass Profile-matched NEMU
difftest. OoO does not force-skip an ambiguous dual-retire MMIO packet, so its
row remains provisional.

| Profile | Binary SHA256 | Config SHA256 | IF/LSU/memory latency | Evidence |
| --- | --- | --- | --- | --- |
| `rv32im_single_perf` | `601f942b5a32d071dd0170425107875fdc287bb86549c6489622656ea7ff1742` | `f397f1899ed896023c81f2a16e9eb9523eb2599a5539b923c7132ae69881528e` | `2/2/2` | `evidence:coremark_public_current` |
| `rv32ima_sv32_linux` | `50840465ecda9da48a69a4361b1a479c42428b5331b114dc694658c6928be6c5` | `82a3448b6c29355e3249a1123f9f15f51b60b02a327a8f2950f000093eb169ea` | `0/0/0` | `evidence:coremark_public_current` |
| `rv32im_ooo_4k` | `601f942b5a32d071dd0170425107875fdc287bb86549c6489622656ea7ff1742` | `b72d4c86e1c7e12bc110d15d298748942b08f8502c7563b491f187f1397ae24f` | `2/3/2` | `evidence:coremark_public_current` |

## Linux private/public parity

The public Profile and private history both lock RTL commit
`abf66cad0f9ad02efc8beb641d4005adeaeeae0b` and
`NPC_DCACHE_WRITE_ALLOCATE=0`. The same canonical Sv32 binary has an identical
CoreMark marker interval in both harnesses:

| Harness | Pre cycles / instructions | Timed cycles / instructions | Post cycles / instructions | Whole cycles / instructions | Evidence |
| --- | ---: | ---: | ---: | ---: | --- |
| Private NPC plus measurement-only observer | 313,889 / 184,284 | 5,278,164 / 3,059,140 | 21,426 / 9,025 | 5,613,479 / 3,252,449 | `evidence:coremark_public_current` |
| Public headless runtime | 313,878 / 184,284 | 5,278,164 / 3,059,140 | 21,561 / 9,057 | 5,613,603 / 3,252,481 | `evidence:coremark_public_current` |

Both timed CPI values are 1.725375105 (`evidence:coremark_public_current`). The
whole-program difference is explained by the old harness reset/counter index
and final UART/terminal boundary, not RTL or the CoreMark loop. The current
public Linux number is therefore synchronized with the faster checkpoint.

### WRITE_ALLOCATE diagnostic

| Setting | Pre cycles | Timed cycles | Timed CPI | Whole cycles | Whole CPI | Evidence |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `WRITE_ALLOCATE=0` | 313,878 | 5,278,164 | 1.725375105 | 5,613,603 | 1.725944902 | `evidence:coremark_public_current` |
| `WRITE_ALLOCATE=1` | 368,877 | 5,277,919 | 1.725295018 | 5,668,419 | 1.742798498 | `evidence:coremark_public_current` / `nonclaim:linux_write_allocate_coremark_speedup_not_claimed` |

Enabling write allocation adds 54,816 whole-program cycles (`evidence:coremark_public_current`), of which 54,999
are before the start marker; the timed interval is instead 245 cycles shorter (`evidence:coremark_public_current`)
(`evidence:coremark_public_current`). The old `1.7428` versus `1.7259`
whole-program difference is therefore a startup-boundary effect, not an
approximately one-percent CoreMark-loop speedup.

## Instruction-weighted seven-workload aggregate CPI

The historical OoO suite contains CoreMark, matrix-mul, crc32, quick-sort,
load-store, Dhrystone, and microbench:

```text
instruction-weighted aggregate CPI = 5,157,299 / 5,649,752 = 0.912836351  # evidence:coremark_public_current
```

This is total cycles divided by total retired instructions, not the arithmetic
mean of seven CPI values and not a CoreMark score. The exact external workload
set has not yet been rerun through the current public entrypoint, so it remains
`provisional` (`nonclaim:ooo_public_cpi_not_yet_claimed`).

The earlier Linux checkpoint `e3a1cc91c4c00040f7180eec5e385326d9964893`
has only an approximate historical CoreMark CPI of 1.98 (`nonclaim:linux_prior_checkpoint_cpi_not_claimed`); it is not a result of the
current `abf66cad` Profile.

## Implementation data

| Profile | Absolute CoreMark score | Closed frequency | Area | Power | State |
| --- | ---: | ---: | ---: | ---: | --- |
| `rv32im_single_perf` | — | — | — | — | `not_claimed` |
| `rv32ima_sv32_linux` | — | — | — | — | `not_claimed` |
| `rv32im_ooo_4k` | — | — | — | — | `not_claimed` |

Simulation CPI or CoreMark/MHz cannot establish frequency, area, or power.
Historical DC stress records remain in machine-readable nonclaims but do not
populate the current implementation table. See the
[CoreMark evidence](evidence/coremark_reproduction.en.md),
[Verification](verification.en.md), and [Limitations](limitations.en.md).
