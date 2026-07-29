# Single / Linux Backend Evidence

[中文](backend_closure.md)

<!-- evidence:single_linux_nangate45_backend_public -->

## Audit Verdict

All four Single/Linux backend evidence chains passed the read-only D11 audit
with verdict `AUDIT_CONFIRMED_EXISTING_BACKEND_RESULTS`. The audit reviewed
source/config/tool/library identity, role-level artifact SHA256, DC integrity,
placement/CTS/detailed route, GDS, OpenRCX, and PrimeTime reports. It did not
repeat DC, P&R, OpenRCX, or PrimeTime.

The verdict supports fixed-frequency Nangate45 academic closure points only.
It does not support Fmax, complete IO/electrical closure, foundry signoff, or a
silicon result.

## Fixed Identity

| Dimension | Single | Linux/Sv32 |
| --- | --- | --- |
| Profile | `rv32im_single_perf` | `rv32ima_sv32_linux` |
| Source lock | `f76de57479b798aca7468f999c386bb4cb5fce02` | `0fc3de40c4e0b231c65945c9dc1711f084688c04` |
| Canonical top | `cpu_top` | `cpu_top` |
| Memory modes | register-expanded / four-macro SRAM | register-expanded / four-macro SRAM |

Single registers consumes the 33 source roles directly from `f76de574`. Single
SRAM replaces exactly three logical cache roles with the audited versions from
`176d4fd74da61ec681816630854501b233213982`. Lexical comparison found functional
`NPC_ASIC_SRAM` token differences, so these files are not recorded as
comment/whitespace-equivalent. The two modes lock source-set SHA256 values
`8124c7d9d41959d0827af3c4f54c4154b90a4a116e46074e197afe207c751f12` and
`d5296a9dbba4a47ef061b286d6fac90a49770b7a2d46f72f05a12dfbfc2bfccb`,
respectively. Both Linux modes lock the same exact 51-role source set from
`0fc3de40`.

All four paths share a fixed Nangate45 ORFS academic platform identity:

- Design Compiler / PrimeTime / Library Compiler: `O-2018.06-SP1`.
- OpenROAD / OpenRCX: `26Q3-463-gbde79242a0`; ORFS commit
  `bea7dcd7be7f26d1328f6058b01cf42bf4352aa2`, with the container digest fixed
  in the machine record.
- NangateOpenCellLibrary typical / 1.1 V / 25 C with a 1 ns Liberty time unit.
- RC is classified as `PDK_PROVIDED_ACADEMIC_RC` using fixed OpenRCX rules; it
  is not called foundry-calibrated RC.

SRAM paths additionally bind OpenRAM commit
`e16d9eb0b4495e8beee441ced3fcad68391155e6` and analytical FreePDK45 TT /
1.0 V / 25 C macro views. The standard-cell and macro timing-model PVT mismatch
is a public limitation and is not hidden by renaming or lowering the clock.

## Verified Results

<!-- claim:single_registers_nangate45_dc_frequency maturity:verified -->
<!-- claim:single_registers_nangate45_postroute_frequency maturity:verified -->
<!-- claim:single_registers_nangate45_standard_cell_area maturity:verified -->
<!-- claim:single_registers_nangate45_core_area maturity:verified -->
<!-- claim:single_sram_nangate45_dc_frequency maturity:verified -->
<!-- claim:single_sram_nangate45_postroute_frequency maturity:verified -->
<!-- claim:single_sram_nangate45_standard_cell_area maturity:verified -->
<!-- claim:single_sram_nangate45_core_area maturity:verified -->
<!-- claim:linux_registers_nangate45_dc_frequency maturity:verified -->
<!-- claim:linux_registers_nangate45_postroute_frequency maturity:verified -->
<!-- claim:linux_registers_nangate45_standard_cell_area maturity:verified -->
<!-- claim:linux_registers_nangate45_core_area maturity:verified -->
<!-- claim:linux_sram_nangate45_dc_frequency maturity:verified -->
<!-- claim:linux_sram_nangate45_postroute_frequency maturity:verified -->
<!-- claim:linux_sram_nangate45_standard_cell_area maturity:verified -->
<!-- claim:linux_sram_nangate45_core_area maturity:verified -->

| Path | DC / route+PT | PT setup / hold WNS | Standard-cell / core footprint | Macros |
| --- | ---: | ---: | ---: | ---: |
| Single / registers | 540 / 425 MHz | +0.025646 / +0.063219 ns | 0.679497 / 2.614530 mm² | 0 |
| Single / SRAM | 600 / 475 MHz | +0.013556 / +0.047904 ns | 0.149292 / 0.858801 mm² | 4 |
| Linux / registers | 280 / 200 MHz | +0.387809 / +0.032648 ns | 0.717964 / 2.825040 mm² | 0 |
| Linux / SRAM | 300 / 200 MHz | +0.720415 / +0.039090 ns | 0.198085 / 1.049500 mm² | 4 |

Detail-route DRC, antenna net/pin, and unrouted-net counts are zero for all four
paths. PrimeTime setup/hold TNS and violating-path counts are zero, the
constrained-path coverage field is 100%, and the unclocked synchronous endpoint
count is zero. `report_analysis_coverage` separately records the following
untested check categories; the 100% field must not hide them:

| Path | Total | Setup | Hold | Recovery | Removal | Min pulse width |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Single / registers | 19 | 2 | 2 | 5 | 5 | 5 |
| Single / SRAM | 0 | 0 | 0 | 0 | 0 | 0 |
| Linux / registers | 90 | 6 | 6 | 26 | 26 | 26 |
| Linux / SRAM | 2 | 1 | 1 | 0 | 0 | 0 |

These D11 PrimeTime counts are retained verbatim. They are not unclocked
synchronous endpoints and do not change the reported WNS/TNS, but they bound
the claim to internal fixed-frequency timing points rather than external IO,
asynchronous recovery/removal, or complete signoff closure.

## Role-Level Handoff

Each path records separate DC, route, and PrimeTime run IDs and applies SHA256
handoff checks to these roles:

| Producer | Consumer | Roles that must match |
| --- | --- | --- |
| Design Compiler | P&R input / OpenROAD import | mapped netlist |
| OpenROAD route | PrimeTime | routed netlist and routed SDC |
| OpenROAD routed database | OpenRCX | routed database |
| OpenRCX | PrimeTime | SPEF |
| Platform / macro views | DC / P&R / PrimeTime | Liberty/DB and applicable macro-view identity |

The machine record also retains SHA256 for the source SDC, DC mapped SDC, P&R
input SDC, sanitized routed SDC, routed DEF, GDS, tool setup, and primary
reports. A missing or unequal role must fail as a handoff/evidence mismatch; it
must not lower the claim threshold.

Complete role values are in
[`evidence/implementation/nangate45_fixed_points.json`](../../evidence/implementation/nangate45_fixed_points.json).
The public record keeps hashes and sanitized run identities, not private paths,
accounts, or host addresses.

## DC And Stage Completeness

All four DC results pass link, `check_design`, and `check_timing`, with zero
combinational timing loops, automatic arc breaks, latches, unclocked synchronous
endpoints, and unresolved references. Register paths have macro/blackbox counts
of `0/0`; SRAM paths have `4/0`.

All four physical paths complete placement, CTS, detailed route, GDS, and
OpenRCX and provide complete PrimeTime setup, hold, coverage, constraint, and
parasitic-annotation reports. The DC mapped netlist at the P&R input is
byte-identical to the OpenROAD import, preventing Yosys/ABC remapping.

## Dimensioned Maturity And Limits

| Dimension | Register-expanded | SRAM-macro |
| --- | --- | --- |
| Physical implementation chain | `verified` | `verified` |
| Internal extracted setup/hold | `verified` | `verified` |
| Electrical / external IO | `partial` | `partial` |
| Macro model | `not_applicable` | `partial_analytical_characterization` |
| Macro DRC/LVS/PEX | `not_applicable` | `not_closed` |
| OCV/MMMC, DFT, LEC, power/PI | `not_claimed` | `not_claimed` |
| Foundry signoff / silicon | `not_claimed` | `not_claimed` |

Retained PrimeTime max-capacitance results, some fanout observations, missing
external IO models, and SRAM RC-004 are not setup-frequency failures. They
cannot be turned into complete electrical closure by blindly reducing the
clock. SRAM standard-cell area excludes macro interiors; register-expanded and
SRAM paths use different memory bindings, so frequency and area comparisons
must preserve the model boundary.

## Public Checks

These commands do not invoke EDA. They validate the evidence schema, all four
points, role-hash equality, bidirectional claim/evidence links, bilingual
values, and generated-asset freshness:

```bash
make implementation-check
make showcase-check
```
