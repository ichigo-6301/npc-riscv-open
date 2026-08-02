# Limitations and nonclaims

[中文](limitations.md)

This page is intentionally conservative. A result can move from `provisional`
or `not_claimed` to `verified` only when Profile, source commit, configuration,
input hashes, raw result, and fresh-clone reproduction all agree.

## RTL and Profiles

- The three Profiles are independently frozen RTL source sets. Internal module,
  macro, interface, and timing compatibility is not promised.
- Public wrappers normalize only commit, halt, and GPR/PC debug observation,
  not internal memory protocols, exception ownership, or pipeline signals.
- One build selects one Profile. Combining several filelists is invalid.
- Native RTL is neither reformatted nor deduplicated, preserving its source
  lock. Duplicate module names are legal only inside separate source sets.
- The public Linux Profile uses a later structured RTL snapshot. The directory
  refactor does not turn the three Profiles into one parameterized RTL or change
  the public wrapper's functional contract.

## Systems and software

- The project is a CPU plus a headless Verilator runtime, not a complete
  synthesizable SoC.
- NVBoard, VGA, PS2, keyboard, GPIO, FPGA projects, and board tops are absent.
  This does not erase layered evidence from external historical Vivado
  projects; it means those projects are not directly reproducible here.
- AXI UARTLite and AXI Timer have deterministic Verilator `runtime-only`
  models but are not synthesizable RTL peripherals; AXI INTC remains NEMU/AM
  `reference-only`.
- The Linux Profile contains RTL `AclintTimer`, but OpenSBI, a Linux kernel,
  DTB, root filesystem, and complete board memory map are not bundled.
- The bounded Linux image covers machine-mode RV32IMA/LRSC/CSR/trap behavior;
  by itself it does not prove S-mode delegation, Sv32 page faults, or Linux
  boot. A historical `e3a1cc91` log verifies the DTB/OpenSBI/Linux 6.6.141/
  initramfs-shell chain, but current `0fc3de40` has not been deeply rerun.
- OpenSBI, Linux, AM, NEMU, compilers, and user programs are external. Users
  obtain matching versions and comply with their licenses.

## Simulation and difftest

- Public DPI sparse PMEM, legacy RTC, serial TX, AXI Timer, UARTLite, and tohost
  are simulation-only services, not silicon memory or peripheral models.
- Latency settings describe clocked simulation transport, not SRAM access
  time, AXI QoS, or cache-hit timing.
- Difftest is off by default. The local adapter is a bounded
  PC/instruction/GPR commit checker, not complete device, timer, interrupt, or
  MMIO-side-effect equivalence.
- Timer models do not claim cycle-exact equivalence. Wall clock, simulation
  ticks, and RTL `mtime` are distinct time bases.
- VCD and itrace are debug aids that reduce host throughput and should not be
  enabled in performance A/B runs.
- Process exit code alone is not PASS evidence; trap/stop markers, commit
  counts, watchdog, and protocol errors must also be checked.

## Performance, frequency, and area

- Single/Linux hash-locked CoreMark marker accounting, self-check, and NEMU
  difftest pass. The verified scope is only the fixed binary, configuration,
  and simulation conditions; it excludes absolute CoreMark score, frequency,
  and silicon performance.
- OoO CoreMark self-check and marker accounting pass, but reference ordering for
  a dual-retire MMIO packet is ambiguous. Its timed CPI `0.879973757` remains
  provisional (`ooo_public_coremark_runtime_provisional`).
- Linux private/public timed intervals now match exactly at CPI `1.725375105`.
  The `WRITE_ALLOCATE=1` whole CPI `1.742798498` is dominated by pre-marker
  overhead and is not an approximately one-percent CoreMark-loop difference
  (`linux_write_allocate_coremark_speedup_not_claimed`).
- Linux whole CPI `8.587098694` to `1.725944902`, approximately `4.9753x`, is
  a `partial` same-benchmark-family A/B. The baseline binary hash is missing
  and retired counts differ by four, so it is not a strict same-binary result.
- OoO frontend-empty and control-redirect improvements belong to the
  historical pre-loop-remediation seven-workload simulation epoch. They do not
  transfer to current loop-free RTL or ASIC results.
- OoO `0.912836351` is an instruction-weighted aggregate CPI for seven finite
  workloads, not a universal CPI guarantee and not a replacement for current
  timed CoreMark CPI.
- The Single approximately 704 MHz value is arithmetic inference from a
  negative-WNS 1 ns DC stress run, not 700 MHz closure or maximum frequency;
  it does not replace the source-matched fixed-frequency results below.
- Single/Linux register-expanded and SRAM-macro modes have four Nangate45
  academic fixed-frequency points. Their verified scope is top-level
  placement, CTS, detailed route, route-tool DRC/antenna/connectivity,
  OpenRCX, and matching PrimeTime internal setup/hold;
  `evidence:single_linux_nangate45_backend_public`.
- These points are not Fmax. DC and physical clocks are separate
  configurations; the higher DC clock is not post-route closure.
- P&R standard-cell area, macro count, and core footprint are reported
  separately. SRAM standard-cell area excludes the four macros and cannot be
  compared alone against register-expanded area.
- Register-expanded modes retain max-capacitance and external IO drive/delay
  boundaries. Those electrical/IO caveats are not hidden by lowering the clock
  and do not invalidate the reported internal setup/hold fixed point.
- SRAM timing uses OpenRAM analytical FreePDK45 TT/1.0 V/25 C while standard
  cells use Nangate45 typical/1.1 V/25 C. `RC-004`, macro characterization,
  macro DRC/LVS/PEX, OCV/MMMC, DFT, formal LEC, and power/PI remain open.
- OoO register/SRAM backend work remains `planned`, with no published
  frequency, area, or power result.
- Historical FPGA results are layered per source snapshot. The original
  five-stage core has only `partial` UART/ILA board binding; forwarding and
  predictor snapshots verify 200 MHz routed timing only. Current `f76de574`
  reboarding and later-snapshot bitstream/board/workload results are not claimed.
- All three FPGA routes have zero routing errors but 4/6/6 DRC warnings, so
  none is called DRC-clean. The copied older XSA in the two later directories
  is not bitstream or board evidence for those snapshots.
- No Profile claims foundry signoff, full IO/electrical closure, silicon
  correlation, or an absolute CoreMark score.
- The OoO public performance path uses internal tagged DPI memory. Its external
  memory synthesis contract excludes some DPI-only precise-store/forwarding
  behavior, so complete synthesis equivalence is not claimed.

## Evidence and security

- Private benchmark binaries, full logs, host absolute paths, PDKs,
  Liberty/DB, LEF, mapped/routed netlists, SPEF, GDS, SRAM views, EDA work
  databases, and credentials are excluded. Only bounded summaries, path-free
  run identities, and SHA256 values are public.
- Historical values retain an exact `historical_verified`, `partial`, or
  `provisional` snapshot boundary until public inputs and current-source
  conditions are reproduced; they never auto-promote to current-source claims.
- Source inventory may flag protocol fields such as `mem_req_token` as generic
  secrets. They are typed transaction identifiers; real credentials or
  secret-like values must still fail closed.
- Machine-readable claims/nonclaims take precedence when they are more
  restrictive than this prose.

See [Performance and implementation data](performance.en.md) for evidence
requirements, [SoC integration](soc-integration.en.md) for system boundaries,
and [Verification](verification.en.md) for test scope.
