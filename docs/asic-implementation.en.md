# No-SRAM ASIC Implementation Flow

D7 gives all three public Profiles one academic Nangate45 path: Design Compiler
mapping, OpenROAD placement/CTS/route, OpenRCX SPEF, and PrimeTime post-route
STA. The first pass is strictly `register-expanded`: the complete 4 KiB caches
map to standard-cell registers, `macro_count=0`, no OpenRAM/SRAM view is used,
and the OoO cache capacities are not reduced.

Only internal register-to-register timing is constrained. External memory,
commit, reset, and integration IO timing have no invented delays. Results must
therefore be described as a "Nangate45 academic register-expanded
implementation/closure point", not maximum frequency, SRAM-aware PPA,
OCV/MMMC, DFT, formal LEC, or foundry signoff.

## Configuration And Entry Points

```text
make rv32im_single_perf_asic_defconfig
make rv32ima_sv32_linux_asic_defconfig
make rv32im_ooo_4k_asic_defconfig
make asic-config-check
make dc-matrix-dry-run
```

Real runs use ignored setup under `flows/local/asic/`. Public entry points are:

```text
make dc-matrix
make pnr NPC_ASIC_DC_RUN=<setup-closed-dc-run>
make sta NPC_ASIC_PNR_RUN=<routed-pnr-run>
make asic-evidence-check NPC_ASIC_BUILD_ROOT=<run-root>
```

DC uses a starting point, a lower frequency bound, and a 10 MHz grid for
WNS-guided navigation. Every point that is actually run still starts from a
clean elaboration. When setup is the only failed gate, it estimates
`F_est = 1000 / (period_ns - WNS_ns)` and generates the next point as
`F_next = floor(F_est / 10 MHz) * 10 MHz`; higher legacy matrix anchors are
recorded as skipped instead of being run mechanically. The scan stops at the
first closed point. Elaboration, combinational-loop or automatic-arc-break,
electrical-check, and tool-evidence failures stop the scan and cannot be hidden
by lowering the frequency. Only the highest executed point with `WNS>=0`,
`TNS=0`, no setup violations, no combinational loop or automatic arc break, no
electrical violation, no macro, and no blackbox may enter P&R. The default
physical frequency is `floor_to_25MHz(0.80 * F_dc_closed)`.
Each matrix records executed points, estimates, skipped points, and the stop
reason in `scan_decisions.json`.

For example, the Single Profile result at 700 MHz with
`WNS=-0.396732 ns` gives `F_est=547.854 MHz`, so the declared 600 MHz point is
skipped and 540 MHz is run next. The estimate selects the next DC target; it is
not a frequency-closure claim.

The formal DC matrix uses `max_transition=0.20` and `max_fanout=32`.
Capacitance keeps the native Nangate45 Liberty limits instead of imposing an
extra design-wide `0.20` cap. Separate reports and the zero-violation gate
still enforce every Liberty capacitance limit.

IC_EDA currently runs DC O-2018.06-SP1. That tool version does not provide the
`report_memory` interface required by this flow, so
`inferred_memory_bits=NA` means that the tool cannot report the value directly;
it does not mean zero inferred memory bits. Register expansion and
`macro_count=0` remain subject to elaboration, cell/reference, and blackbox
checks. The ASIC-specific controller supports Python 3.6 on the remote host;
the general public `flowctl.py` control plane still requires Python 3.8 or
newer.

The first Linux scan uses the RTL timer default. Before physical handoff it must
be resynthesized at the chosen `F_pnr_mhz` with
`NPC_TIMER_CLK_HZ=F_pnr_mhz * 1_000_000` and a 1 MHz
timebase. Linux is locked to `34f13ec4`, which only moves DCache declarations
and the trigger-enable localparam ahead of task references for DC O-2018
compatibility on top of E1 `bee5b918`. The old `abf66cad`
CoreMark row stays historical until an exact rerun.

## OoO A3 Comparison

Public main keeps OoO source `99fcc2be`. The evaluation branch uses `94ae2c6f`
and runs both modes:

```text
ASIC_OOO_MODE=a3-split-off make dc-matrix
ASIC_OOO_MODE=a3 make dc-matrix
```

Full A3 fixes `STABLE_ENTRY_IQ=1`, `ROB_INDEXED_SERVICE_LEVEL=1`, and
`IQ_SPLIT_PAYLOAD_READ=1`. Merge requires a valid timing graph, at least 5%
same-frequency worst-data-path improvement or a 50 MHz higher closed point, no
worse TNS/path count, no more than 5% area/cell growth, and unchanged
CPI/cycles/instructions/commit trace.

After all three matrices complete, `make a3-dc-eval` uses split-off from the
same A3 source set as the primary implementation reference and also requires
the candidate to pass the same guards against the public legacy anchor. A
seven-workload ideal/default cycle, instruction, and commit-trace identity
summary is mandatory. Any combinational loop, automatic arc break, or missing
native timing-graph check yields `A3_DC_INCONCLUSIVE_LOOP` and forbids merge.

The tracked 14-row A3 performance CSV is first converted by
`flows/scripts/build_a3_cpi_identity.py` into bounded JSON carrying the source
commit and input SHA256. The conversion also requires the original A3 evidence
manifest, the private OoO NEMU `.so` actually used, and its matching `.config`;
the result binds the Profile, NEMU commit, binary/config SHA256, and MMIO
skip/resynchronization policy. The public bounded adapters generated separately
for the three Profiles remain Profile smoke references and cannot replace the
OoO seven-workload reference. `a3-dc-eval` rejects a manually shortened
workload set, CPI evidence without commit/reference binding, or OoO CPI evidence
produced with the public bounded adapter.

## Physical Handoff

OpenROAD consumes the DC netlist through `SYNTH_NETLIST_FILES` with an empty
`VERILOG_FILES`. The runner byte-checks it against ORFS `1_2_yosys.v`, preventing
Yosys/ABC remapping. The floorplan uses `DC_area * 1.25 / 0.30`, site snapping,
and placement density 0.55. OpenRCX and PrimeTime are allowed only after normal
detailed-route completion.

PrimeTime reads the same-run routed netlist, sanitized routed SDC, and SPEF and
asserts that the real clock period equals `F_pnr`. Role-by-role SHA256 binds the
DC-to-ORFS, route-to-RCX, and route/RCX-to-PrimeTime handoffs. Missing or unequal
roles fail as `FAIL_HANDOFF_IDENTITY`.

`PNR_RCX_COMPLETED` means only that placement/CTS/route, route-integrity gates,
and the OpenRCX handoff completed. It does not establish setup or hold closure;
only `sta_closed=true` in the independent PrimeTime summary closes post-route
timing at that frequency.

A non-zero OpenROAD exit still leaves a `summary.json`, but its status can only
be `PNR_RCX_PARTIAL`. That summary separates setup/timing failures eligible for
a lower-frequency rerun from DRC, antenna, connectivity, hold, or handoff
failures that must not be disguised as frequency problems.

Raw reports, mapped/routed netlists, SPEF, GDS, and libraries stay under ignored
`build/`. Only recipes, bounded summaries, hashes, and caveats are public.
