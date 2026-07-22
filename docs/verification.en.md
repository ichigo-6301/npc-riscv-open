# Verification

[中文](verification.md)

Results remain isolated by Profile, source commit, image hash, and run
configuration. Process exit code zero is not sufficient: a test must also
observe its expected PASS marker, good trap/stop condition, instruction count,
and zero protocol errors.

## Validation layers

| Layer | Purpose | Current state |
| --- | --- | --- |
| Configuration and source closure | defconfig, manifest, filelist, defines, and source hashes agree | `verified` |
| Static checks | Verilator lint/elaboration for all Profiles | `verified` |
| Bounded smoke/regression | checked-in small programs pass on the headless runtime | `verified` |
| Local NEMU difftest | Profile-matched PC/instruction/GPR commit check | bounded PASS; overall `partial` |
| Complete OpenSBI/Linux | firmware, Sv32 page tables, interrupts, and devices | `not_claimed` |
| Performance benchmarks | public reproduction of fixed external CoreMark/workload inputs | `provisional` |
| ASIC/PPA | synthesis, P&R, STA, power, and signoff | `not_claimed` |

No functional coverage database is available; `coverage_status` is
`not_available`. A test-case count is not a coverage percentage.

## Standard gates

Run for every Profile:

```sh
make <profile>_defconfig
make showconfig
make config-check source-check docs-check public-hygiene
make verify-checksums
make verilator-lint
make smoke
make regression
```

Python unit tests for the runtime also check configuration selection, runner
commands, invalid inputs, and the Profile ABI. After building, Git status may
contain only correctly ignored `.config`, `build/`, and `flows/local/` output.

## Bounded test content

| Profile | Fixed image | Explicit coverage |
| --- | --- | --- |
| `rv32im_single_perf` | `smoke.hex` | RV32IM, x16-x31, RAW/WAW, branch, load/store, MUL/DIV, trap |
| `rv32ima_sv32_linux` | `smoke.hex` | RV32IM, upper GPRs, RAW/WAW, branch, load/store, MUL/DIV, trap |
| `rv32ima_sv32_linux` | `arch_smoke.hex` | RV32IMA, LR/SC, machine CSRs, trap |
| `rv32im_ooo_4k` | `smoke.hex` | RV32IM, upper GPRs, RAW/WAW, branch, load/store, MUL/DIV, recovery, dual-commit observation, trap |

The Linux Profile `arch_smoke.hex` is a bounded machine-mode test. It does not
cover complete S-mode delegation, translated Sv32 fetch/load/store, page
faults, OpenSBI startup, or a Linux kernel.

## Recorded deterministic results

| Profile / image | Cycles | Commit packets | Result |
| --- | ---: | ---: | --- |
| `rv32im_single_perf/smoke.hex` | 269 | 27 | `PUBLIC_SIM_PASS` |
| `rv32ima_sv32_linux/smoke.hex` | 162 | 27 | `PUBLIC_SIM_PASS` |
| `rv32ima_sv32_linux/arch_smoke.hex` | 80 | 15 | `PUBLIC_SIM_PASS` |
| `rv32im_ooo_4k/smoke.hex` | 107 | 26 (lane 0: 21 + lane 1: 5) | `PUBLIC_SIM_PASS` |

These cycle counts establish deterministic source-set, wrapper, DPI transport,
and runner behavior only. They are not CoreMark, Linux boot, CPI, frequency,
or area results.

## Local strict difftest

Using the three manifest-locked NEMU source trees and ignored local adapters,
all four bounded images passed with the same cycle and commit results. The
adapter checks:

- Profile ID, ABI, image, and reset vector;
- PC, instruction, and next PC for every commit;
- all 32 architectural GPRs;
- ordering and final architectural state for two commits in one OoO cycle.

The OoO debug shadow seeds untouched GPRs with an index sentinel. The adapter
ignores only untouched sentinels; every committed register write must still
match. Single-issue Profiles reset GPRs to zero and compare all entries.

The overall state remains `partial`: NEMU source and `.so` files are external
local artifacts, and the ABI does not compare devices, timer ticks, interrupt
timing, or arbitrary MMIO side effects.

## Fresh-clone requirements

For the target commit in a native-Linux temporary directory:

1. run `verify-checksums`, `docs-check`, source closure, and hygiene;
2. run lint, smoke, and regression for all three Profiles;
3. run bounded difftest when local NEMU is supplied;
4. check every source-set SHA256;
5. confirm that the worktree remains clean after testing.

Any image/config hash drift, fixed-test cycle or instruction-count change,
unexplained protocol error, or nondeterministic rerun must retain failure
evidence and stop performance/PPA conclusions.

See [Simulation](simulation.en.md),
[Performance and implementation data](performance.en.md), and
[Limitations](limitations.en.md).
