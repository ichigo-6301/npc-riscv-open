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
| OpenSBI/Linux system boot | DTB, M-to-S handoff, Linux 6.6.141, `/init`, and initramfs shell | historical snapshot `e3a1cc91` `verified`; current `0fc3de40` not deeply rerun |
| XC7Z100 FPGA | synthesis, routed implementation, timing, bitstream, board observation, and workload | three historical snapshots reported by layer; current `f76de574` board run `not_claimed` |
| Performance benchmarks | hash-locked CoreMark marker accounting and difftest | Single current source lock `verified`; Linux historical evidence at `abf66cad`; OoO `provisional` |
| ASIC implementation | DC, P&R, OpenRCX, and internal PrimeTime | four Single/Linux fixed points `verified`; OoO `planned` |
| Electrical / signoff | IO, electrical, macro signoff, OCV/MMMC, power, and silicon | `partial` / `not_claimed` |

No functional coverage database is available; `coverage_status` is
`not_available`. A test-case count is not a coverage percentage.

## Standard gates

Run for every Profile:

```sh
make <profile>_defconfig
make showconfig
make config-check source-check docs-check evidence-check showcase-check public-hygiene
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
This describes the current checked-in bounded image, not the complete boot
chain historically recorded at `e3a1cc91`.

`make opensbi-smoke` provides an explicit external-firmware entrypoint, but
the public repository does not lock a DTB, reference model, or shutdown
termination protocol. The entrypoint alone is therefore not a verified
OpenSBI-execution claim.

## Historical system and FPGA snapshots

The Linux log at `e3a1cc91` records DTB loading, OpenSBI, the M-to-S handoff,
Linux `6.6.141`, `/init`, and initramfs-shell markers. The raw log remains
private; only its hash and bounded marker summary are published. The current
ASIC source lock `0fc3de40` has not repeated the approximately one-hour deep
boot, so this evidence is not current-source verification.

Single XC7Z100 evidence is split across all eight maturity dimensions. The
2026-05-07 original five-stage snapshot has 200 MHz routed timing, a bitstream,
and UART/ILA board observations, with board-image binding marked `partial`.
The 2026-05-12 forwarding and 2026-05-15 forwarding+BTB/PHT snapshots verify
only 200 MHz synthesis, implementation, and timing. Their XSA files are copies
from May 7 and cannot promote bitstream or board status. See
[System and FPGA history](evidence/system_fpga_history.en.md).

## Recorded deterministic results

| Profile / image | Cycles | Commit packets | Result |
| --- | ---: | ---: | --- |
| `rv32im_single_perf/smoke.hex` | 269 | 27 | `PUBLIC_SIM_PASS` |
| `rv32ima_sv32_linux/smoke.hex` | 150 | 27 | `PUBLIC_SIM_PASS` |
| `rv32ima_sv32_linux/arch_smoke.hex` | 77 | 15 | `PUBLIC_SIM_PASS` |
| `rv32im_ooo_4k/smoke.hex` | 107 | 26 (lane 0: 21 + lane 1: 5) | `PUBLIC_SIM_PASS` |

These cycle counts establish deterministic source-set, wrapper, DPI transport,
and runner behavior only. They are not CoreMark, Linux boot, CPI, frequency,
or area results.

## Hash-locked CoreMark results

The public runner emits `PUBLIC_SIM_PASS cycles=... commit=... commit2=...` at
termination. The evidence-bound source refs for all three Profiles record a
passing CoreMark self-check, a closed start/stop marker interval, a good trap,
and a satisfied watchdog. The public runtime provides deterministic AXI
Timer/UARTLite behavior. Single passes Profile-matched NEMU difftest at its
current source lock, so its timed CPI, whole CPI, and CoreMark/MHz are
`verified`. The Linux values are `historical_verified` only at `abf66cad`; the
current `0fc3de40` source lock still needs an exact-input rerun. OoO self-check
and accounting pass, but a dual-retire MMIO packet cannot use the single-retire
skip-and-sync rule without ordering ambiguity, so it remains `provisional`.
Exact input/config hashes, counter partitions, and protocol boundaries are in
[CoreMark measurement evidence](evidence/coremark_reproduction.en.md).

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
local artifacts, and the ABI does not compare cycle-exact device state, timer
ticks, interrupt timing, or arbitrary MMIO side effects. Single/Linux CoreMark
uses deterministic skip-and-sync only for exact known Timer/UART MMIO; unknown
addresses and side effects fail.

## Backend evidence gates

Single/Linux register-expanded and SRAM-macro flows lock independent DC, P&R,
and PT periods. Each of the four paths must have a clean DC link, no
combinational loop, automatic arc break, latch, or unclocked endpoint, and the
configured macro/blackbox count. Placement, CTS, detailed route, GDS, and
OpenRCX reports must be complete. Role hashes for mapped/routed netlists,
routed SDC, SPEF, and Liberty/DB must agree, and PrimeTime internal setup/hold
TNS and violating-path counts must be zero. The public checker validates these
fields from bounded JSON; it neither reads nor distributes raw artifacts.

An SRAM path can have `verified` P&R and internal extracted timing while its
macro model is `partial_analytical_characterization`, macro physical signoff is
`not_closed`, and overall profile maturity remains `partial`. See the
[backend evidence](evidence/backend_closure.en.md) for the exact scope.

## Fresh-clone requirements

For the target commit in a native-Linux temporary directory:

1. run `verify-checksums`, `docs-check`, `evidence-check`,
   `showcase-check`, source closure, and hygiene;
2. run lint, smoke, and regression for all three Profiles;
3. run bounded difftest when local NEMU is supplied; when hash-locked CoreMark
   inputs are also supplied, run Single/Linux `coremark-difftest` and OoO
   `coremark`;
4. run config-check and LC/DC/P&R/PT dry-run contracts for all four
   Single/Linux ASIC defconfigs without launching commercial EDA;
5. check every source-set SHA256;
6. confirm that the worktree remains clean after testing.

Any image/config hash drift, fixed-test cycle or instruction-count change,
unexplained protocol error, or nondeterministic rerun must retain failure
evidence and stop performance/PPA conclusions.

See [Simulation](simulation.en.md),
[Performance and implementation data](performance.en.md), and
[Limitations](limitations.en.md).
