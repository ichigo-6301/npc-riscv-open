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
- AXI UARTLite, AXI Timer, and AXI INTC currently exist only as NEMU/AM
  reference-platform device models, not RTL peripherals in the public wrapper.
- The Linux Profile contains RTL `AclintTimer`, but OpenSBI, a Linux kernel,
  DTB, root filesystem, and complete board memory map are not bundled.
- The bounded Linux image covers machine-mode RV32IMA/LRSC/CSR/trap behavior;
  it does not prove complete S-mode delegation, Sv32 page faults, or Linux boot.
- OpenSBI, Linux, AM, NEMU, compilers, and user programs are external. Users
  obtain matching versions and comply with their licenses.

## Simulation and difftest

- Public DPI sparse PMEM, legacy RTC, serial TX, and tohost are
  simulation-only services, not silicon memory or peripheral models.
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

- The public headless runtime has now completed profile-matched CoreMark runs for
  all three Profiles using external, unbundled binaries, with cycles/commit/CPI
  recorded. These rows remain `provisional_external_input`, not verified claims.
- Profile-matched CoreMark difftest is not fully accepted: Single/Linux MMIO
  accesses exceed the `device=false` contract, and OoO has an early GPR mismatch.
  A runtime PASS therefore does not replace an architecture-level difftest PASS.
- The private rerun of the later Linux checkpoint is CPI `1.725978726`
  (approximately `1.72`), while the current public filelist with
  `WRITE_ALLOCATE=1` is `1.742774400`; these are different configurations and
  must not be combined.
- OoO `0.912836351` is a weighted CPI for seven finite workloads, not a
  universal CPI guarantee and not a replacement for CoreMark CPI
  `0.882380204`.
- The Single approximately 704 MHz value is arithmetic inference from a
  negative-WNS 1 ns DC stress run, not 700 MHz closure, maximum frequency,
  P&R, or silicon performance.
- Single `184926.124968` is a library-area value under that historical DC
  setup, not physical die/core area and not directly comparable across memory
  bindings.
- The Linux and OoO Profiles have no public frequency, area, or power values.
- No Profile establishes public P&R, post-route extraction/STA, CDC/RDC, DFT,
  LEC, power, SRAM macro DRC/LVS/PEX, IO, OCV/MMMC, foundry signoff, or silicon
  correlation.
- The OoO public performance path uses internal tagged DPI memory. Its external
  memory synthesis contract excludes some DPI-only precise-store/forwarding
  behavior, so complete synthesis equivalence is not claimed.

## Evidence and security

- Private benchmark binaries, full logs, host absolute paths, PDKs,
  Liberty/DB, LEF, GDS, SRAM views, EDA work databases, and credentials are
  excluded.
- A historical value remains `provisional` even if privately verified until
  its public inputs and conditions are reproduced.
- Source inventory may flag protocol fields such as `mem_req_token` as generic
  secrets. They are typed transaction identifiers; real credentials or
  secret-like values must still fail closed.
- Machine-readable claims/nonclaims take precedence when they are more
  restrictive than this prose.

See [Performance and implementation data](performance.en.md) for evidence
requirements, [SoC integration](soc-integration.en.md) for system boundaries,
and [Verification](verification.en.md) for test scope.
