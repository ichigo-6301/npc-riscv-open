# Historical Architecture And Performance Evidence

[中文](performance_history.md)

This page records auditable historical optimization checkpoints without
relabeling them as performance of the current source locks. The machine-readable
sources are
[`linux_coremark_ab.json`](../../evidence/performance/linux_coremark_ab.json) and
[`ooo_frontend_branch_ab.json`](../../evidence/performance/ooo_frontend_branch_ab.json).

## Linux/Sv32 CoreMark Evolution

<!-- evidence:linux_coremark_history_public -->
<!-- claim:linux_historical_no_tlb_whole_cpi maturity:partial -->
<!-- claim:linux_historical_optimized_whole_cpi maturity:verified -->
<!-- claim:linux_historical_approx_speedup maturity:partial -->

| Checkpoint | Source | Cycles / retired instructions | Whole-program CPI | Status |
| --- | --- | ---: | ---: | --- |
| Sv32 without TLBs | `4a4cbf5d` | 27,929,341 / 3,252,477 | 8.587098694 | `partial`: configuration and counters are locked, but the baseline binary hash is unavailable |
| Optimized | `abf66cad` | 5,613,603 / 3,252,481 | 1.725944902 | `verified` historical result |

The same-benchmark-family whole-program ratio is
`8.587098694 / 1.725944902 = 4.975302910`, reported compactly as approximately
`4.98x`. It remains `partial`: the runs differ by four retired instructions and
the baseline binary hash was not retained, so this is not a strict
hash-identical A/B. The optimized checkpoint includes 16-entry ITLB/DTLBs, a
two-entry store buffer, fast MUL, cross-stage forwarding, and the load-hit path.
The current `0fc3de40` source has not repeated the exact-input run.

## OoO Frontend And Branch Prediction

<!-- evidence:ooo_historical_optimization_public -->
<!-- claim:ooo_historical_frontend_empty_baseline_percent maturity:verified -->
<!-- claim:ooo_historical_frontend_empty_s9b_percent maturity:verified -->
<!-- claim:ooo_historical_redirect_direct_jal_percent maturity:verified -->
<!-- claim:ooo_historical_redirect_btfnt_percent maturity:verified -->
<!-- claim:ooo_historical_redirect_btb_bht_percent maturity:verified -->
<!-- claim:ooo_historical_redirect_jalr_ras_percent maturity:verified -->
<!-- nonclaim:ooo_historical_ab_not_current_no_loop -->

In the historical seven-workload default-profile simulation, S9B used
multi-request fetch, epoch-tagged ordered responses, and a pipelined pair-fetch
service to reduce frontend-empty lost slots from `53.76%` to `23.29%`. The
denominator is total dispatch slots.

| Branch stage | Source | Redirects / control completions |
| --- | --- | ---: |
| Direct JAL | `62d40850` | 59.38% |
| BTFNT | `a247ac43` | 24.84% |
| 64-entry tagged BTB/BHT | `712b3633` | 22.66% |
| 64-entry indirect BTB + 8-entry RAS | `87a0bbc4` | 17.73% |

All values belong to the historical pre-combinational-loop-remediation epoch.
They demonstrate the directional effect of those mechanisms in the fixed
suite, but they are not current no-loop RTL, FPGA, ASIC, or silicon results.
Current OoO CoreMark remains provisional and its backend remains planned.

## Resume Boundary

- Linux may be summarized as approximately 8.59 to 1.73 CPI and approximately
  4.98x at equal frequency, with the approximate/partial boundary retained.
- OoO may cite the historical 53.76% to 23.29% frontend-empty and 59.38% to
  17.73% redirect reductions, followed by the loop and causal-ownership refactor.
- Historical ratios must not be combined with current provisional CoreMark CPI
  or with ASIC frequency and area.
