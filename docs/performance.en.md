# Performance and implementation data

[中文](performance.md)

This page separates the timed CoreMark interval, whole-program CPI,
CoreMark/MHz, a finite workload aggregate, and physical implementation metrics.
CoreMark numbers come from
[`evidence/performance/coremark.json`](../evidence/performance/coremark.json),
while backend numbers come from
[`evidence/implementation/nangate45_fixed_points.json`](../evidence/implementation/nangate45_fixed_points.json).
`make performance-check` validates benchmark formulas and input identity;
`make implementation-check` validates backend claims, D11 identity, role
hashes, and both language surfaces.

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
| `rv32ima_sv32_linux` | 5,278,164 / 3,059,140 | 1.725375105 | 1.894598197 | 5,613,603 / 3,252,481 | 1.725944902 | `historical_verified` at `abf66cad`, difftest PASS; E1 is not promoted yet |
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

### Historical optimization A/B

Whole-program counters from the same Sv32 CoreMark benchmark family record a
no-TLB point of `27,929,341 / 3,252,477 = 8.587098694 CPI` (`evidence:linux_coremark_history_public`).
The optimized point is `5,613,603 / 3,252,481 = 1.725944902 CPI` (`evidence:linux_coremark_history_public`). Same-clock
execution efficiency is approximately `4.9753x` (`evidence:linux_coremark_history_public`).
This A/B is `partial`: the baseline
binary hash is unavailable, retired counts differ by four, and current
`0fc3de40` has not been rerun with the same inputs. Resume wording may round it
to "about 8.59 to 1.73, about 4.98x," but must not call it a strict same-binary
A/B. See [Performance optimization history](evidence/performance_history.en.md).

The historical CoreMark evidence in the table locks RTL commit
`abf66cad0f9ad02efc8beb641d4005adeaeeae0b`; the current public Profile and ASIC
source lock have moved to `0fc3de40c4e0b231c65945c9dc1711f084688c04`.
Both source points use `NPC_DCACHE_WRITE_ALLOCATE=0`. The same canonical Sv32
binary has an identical CoreMark marker interval in the historical private and
public harnesses:

| Harness | Pre cycles / instructions | Timed cycles / instructions | Post cycles / instructions | Whole cycles / instructions | Evidence |
| --- | ---: | ---: | ---: | ---: | --- |
| Private NPC plus measurement-only observer | 313,889 / 184,284 | 5,278,164 / 3,059,140 | 21,426 / 9,025 | 5,613,479 / 3,252,449 | `evidence:coremark_public_current` |
| Public headless runtime | 313,878 / 184,284 | 5,278,164 / 3,059,140 | 21,561 / 9,057 | 5,613,603 / 3,252,481 | `evidence:coremark_public_current` |

Both timed CPI values are 1.725375105 (`evidence:coremark_public_current`). This
evidence is locked to `abf66cad`; current source lock `0fc3de40` contains the
E1 I-cache exception-metadata ownership change, DCache, trigger, store-buffer
drain-valid, DTLB translated-address, memory-response, and top-level control declaration-order fixes, a CSR reset expansion active only under `NPC_ASIC`, and explicit non-DPI statistic-net widths. The production
simulation path is unchanged, but it still needs the same binary/config
rerun before promotion. The
whole-program difference is explained by the old harness reset/counter index
and final UART/terminal boundary, not RTL or the CoreMark loop. The current
historical public Linux number is synchronized with that faster checkpoint and is not relabeled as E1.

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
has only an approximate historical CoreMark CPI of 1.98 (`nonclaim:linux_prior_checkpoint_cpi_not_claimed`); it is neither a result of the
current public `0fc3de40` source lock nor the `abf66cad` CoreMark evidence point
above.

In the historical pre-loop-remediation seven-workload simulation epoch, OoO
frontend-empty rate moved from `53.76%` to `23.29%` using total dispatch slots
as the denominator. The branch-prediction chain moved redirects per control
completion through `59.38%`, `24.84%`, `22.66%`, and `17.73%`. These values
describe historical mechanism effects only; they do not transfer to current
loop-free RTL or any backend result. See
[Performance optimization history](evidence/performance_history.en.md)
(`evidence:ooo_historical_optimization_public`).

## Nangate45 academic fixed-frequency points

The four rows below come from the D11 source/config/tool/library identity audit.
The DC point and OpenROAD/OpenRCX/PrimeTime point use independent clocks. The
physical frequency is not inferred from DC WNS and is not called Fmax.

| Profile / memory | DC / physical | PT setup / hold WNS | P&R std-cell / core area | Macros | Maturity |
| --- | ---: | ---: | ---: | ---: | --- |
| `rv32im_single_perf` / registers | 540 / 425 MHz | +0.025646 / +0.063219 ns | 0.679497 / 2.614530 mm² | 0 | internal fixed point `verified`; `evidence:single_linux_nangate45_backend_public` |
| `rv32im_single_perf` / SRAM | 600 / 475 MHz | +0.013556 / +0.047904 ns | 0.149292 / 0.858801 mm² | 4 | P&R/timing `verified`, macro model `partial`; `evidence:single_linux_nangate45_backend_public` |
| `rv32ima_sv32_linux` / registers | 280 / 200 MHz | +0.387809 / +0.032648 ns | 0.717964 / 2.825040 mm² | 0 | internal fixed point `verified`; `evidence:single_linux_nangate45_backend_public` |
| `rv32ima_sv32_linux` / SRAM | 300 / 200 MHz | +0.720415 / +0.039090 ns | 0.198085 / 1.049500 mm² | 4 | P&R/timing `verified`, macro model `partial`; `evidence:single_linux_nangate45_backend_public` |
| `rv32im_ooo_4k` / registers or SRAM | — | — | — | — | backend `planned`; `nonclaim:ooo_ppa_timing_not_claimed` |

All four completed points report zero detailed-route DRC, antenna net/pin, and
unrouted-net counts. PrimeTime setup/hold TNS and violating-path counts are
also zero. SRAM standard-cell area excludes the four macros, so cross-memory
comparison must use the explicitly labeled core footprint while retaining the
macro organization. See the [backend evidence](evidence/backend_closure.en.md)
for role hashes, run identities, coverage, and caveats.

These results verify top-level physical implementation and internal extracted
setup/hold only. Max capacitance, external IO drive/delay, the analytical
OpenRAM model, `RC-004`, macro DRC/LVS/PEX, OCV/MMMC, DFT, formal LEC,
power/PI, foundry signoff, and silicon correlation remain open. Power and an
absolute CoreMark score remain `not_claimed`. See
[Verification](verification.en.md), [Limitations](limitations.en.md), and the
[Roadmap](roadmap.en.md).
