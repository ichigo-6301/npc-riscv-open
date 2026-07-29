# Roadmap

[中文](roadmap.md)

This page lists unfinished work only. The audited Single/Linux fixed-frequency
Nangate45 implementation points are recorded in
[Performance and implementation data](performance.en.md) and the
[backend evidence](evidence/backend_closure.en.md); they are not restated here
as future targets.

## `rv32im_single_perf`

- Add explicit external IO drive/load and input/output delay models while
  keeping internal timing separate from full-IO timing.
- Resolve or review max-capacitance and other electrical exceptions by exact
  object set; do not hide them by lowering the clock.
- Add characterized SRAM views, macro DRC/LVS/PEX, OCV/MMMC, DFT, formal LEC,
  and power-integrity evidence.

## `rv32ima_sv32_linux`

- Rerun the same hash-locked CoreMark input at source lock `0fc3de40` before
  promoting the historical `abf66cad` CPI to a current Profile claim.
- Extend bounded OpenSBI, S-mode, and Sv32 page-fault regressions. A complete
  Linux distribution boot still requires an external image, DTB, and audited
  board memory map.
- Continue the same backend work as Single: IO, electrical exceptions, macro
  signoff, OCV/MMMC, DFT, LEC, and power integrity.

## `rv32im_ooo_4k`

- Keep the current focus on RTL performance optimization, dual-retire MMIO
  difftest ordering, and the equivalence boundary of the synthesizable external
  memory contract.
- Register-expanded and SRAM-macro DC, P&R, OpenRCX, and PrimeTime are all
  `planned`; no projected frequency, area, or power is published.
- Promote a backend stage only after source/config freeze, actual tool output,
  same-run artifact identity, route checks, and external STA are all present.

## Promotion gate

Every future implementation result must bind its Profile, source set, memory
mode, SDC, tool, and library identity, with role-level SHA256 for the mapped
netlist, routed netlist, routed SDC, SPEF, and Liberty/DB views. Scripts, empty
directories, target clocks, or tool startup alone never promote maturity.
