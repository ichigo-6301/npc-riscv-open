# NPC RISC-V Three-Profile Processors

[![Public profile CI](https://github.com/ichigo-6301/npc-riscv-open/actions/workflows/public-ci.yml/badge.svg?branch=main)](https://github.com/ichigo-6301/npc-riscv-open/actions/workflows/public-ci.yml) ![RTL](https://img.shields.io/badge/RTL-Verilog%20%2F%20SystemVerilog-2f6f9f) [![License](https://img.shields.io/github/license/ichigo-6301/npc-riscv-open)](LICENSE)

[中文](README.md) · [Architecture](docs/architecture.en.md) · [Performance](docs/performance.en.md) · [Verification](docs/verification.en.md) · [ASIC](docs/asic-implementation.en.md) · [Limitations](docs/limitations.en.md) · [Roadmap](docs/roadmap.en.md)

**A multi-profile RV32 CPU project spanning bare-metal performance, Sv32/Linux system capability, and dual-width out-of-order research, with auditable simulation contracts and Nangate45 academic ASIC backend evidence.**

The three Profiles are independent source locks, not one parameterized RTL design. The actively optimized `rv32im_ooo_4k` remains the default flagship and quickstart; backend-audited results currently cover the single-issue `rv32im_single_perf` and Linux/Sv32 `rv32ima_sv32_linux` Profiles. The default public simulation entrypoint is [`npc_public_sim_top`](rtl/wrappers/rv32im_ooo_4k_sim_top.sv) with [`filelists/rv32im_ooo_4k.f`](filelists/rv32im_ooo_4k.f); `make defconfig && make smoke` produces a bounded PASS result.

![NPC RISC-V three-Profile portfolio and backend maturity](docs/assets/profile_portfolio.svg)

## 60-Second Status Matrix

<!-- evidence:single_linux_nangate45_backend_public -->
<!-- nonclaim:ooo_ppa_timing_not_claimed -->

| Profile | ISA / microarchitecture | Public RTL and runtime | Register-expanded backend | SRAM-macro backend |
| --- | --- | --- | --- | --- |
| `rv32im_single_perf` | RV32IM, five-stage single-issue in order | Source closure, lint, smoke/regression, and fixed CoreMark/NEMU path verified | `verified` fixed point | `verified` fixed point |
| `rv32ima_sv32_linux` | RV32IMA, M/S + Sv32, single issue | Source closure and bounded architecture regression verified; an external-image OpenSBI entrypoint is provided, while payload-bound execution remains `partial` and complete Linux boot is not claimed | `verified` fixed point | `verified` fixed point |
| `rv32im_ooo_4k` | RV32IM, dual dispatch/issue/complete/commit OoO | Default flagship; RTL and public runtime execute, while performance claims remain `provisional` | `planned / TODO` | `planned / TODO` |

Here, `verified` means only a fixed-frequency Nangate45 academic physical implementation with internal extracted setup/hold STA. It does not mean Fmax, complete IO/electrical closure, foundry signoff, or a silicon result.

## Verified Results

### Nangate45 Fixed-Frequency Closure Points

![Single and Linux Nangate45 fixed-frequency closure points](docs/assets/nangate45_closure_points.svg)

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
<!-- evidence:single_linux_nangate45_backend_public -->

| Path | DC / route+PT | PT setup / hold WNS | Standard-cell / core footprint | Macros |
| --- | ---: | ---: | ---: | ---: |
| Single / registers | 540 / 425 MHz | +0.025646 / +0.063219 ns | 0.679497 / 2.614530 mm² | 0 |
| Single / SRAM | 600 / 475 MHz | +0.013556 / +0.047904 ns | 0.149292 / 0.858801 mm² | 4 |
| Linux / registers | 280 / 200 MHz | +0.387809 / +0.032648 ns | 0.717964 / 2.825040 mm² | 0 |
| Linux / SRAM | 300 / 200 MHz | +0.720415 / +0.039090 ns | 0.198085 / 1.049500 mm² | 4 |

All four paths complete placement, CTS, detailed route, GDS, OpenRCX, and PrimeTime, with detail-route DRC / antenna / unrouted counts of `0 / 0 / 0`. Role-level SHA256 and same-run identity for the mapped netlist, P&R import, routed netlist/SDC, SPEF, and Liberty/DB are in the [backend evidence guide](docs/evidence/backend_closure.en.md) and [machine-readable evidence](evidence/implementation/nangate45_fixed_points.json).

The SRAM rows use analytical OpenRAM FreePDK45 TT / 1.0 V / 25 C macro views with Nangate45 typical / 1.1 V / 25 C standard-cell views and retain RC-004. Macro DRC/LVS/PEX, OCV/MMMC, DFT, LEC, power, and PI are not closed. Register and SRAM rows represent different memory bindings, so their area delta is not a complete-chip PPA improvement claim.

### Simulation Performance

<!-- claim:single_public_coremark_timed_cpi maturity:verified -->
<!-- claim:single_public_coremark_per_mhz maturity:verified -->
<!-- claim:single_public_coremark_whole_cpi maturity:verified -->
<!-- evidence:coremark_public_current -->
<!-- nonclaim:ooo_public_coremark_runtime_provisional -->

| Profile | CoreMark timed CPI | CoreMark/MHz | Whole-program CPI | Boundary |
| --- | ---: | ---: | ---: | --- |
| `rv32im_single_perf` | 1.484920431 | 2.201416876 | 1.485861312 | `verified`, fixed binary/config, NEMU difftest PASS |
| `rv32ima_sv32_linux` | 1.725375105 | 1.894598197 | 1.725944902 | `historical_verified` at `abf66cad`; the `0fc3de40` source lock awaits an exact-input rerun |
| `rv32im_ooo_4k` | 0.879973757 | 3.714802709 | 0.882383851 | `provisional`, self-check PASS; dual-retire MMIO difftest ordering remains ambiguous |

`CoreMark/MHz` is iterations per million simulated cycles within the fixed marker interval. It is neither an absolute CoreMark score nor an implemented-clock assumption. Complete counters, binary/config hashes, and reproduction contracts are in [Performance](docs/performance.en.md) and the [CoreMark evidence](docs/evidence/coremark_reproduction.en.md).

## Canonical Top And Filelist

Each build selects exactly one source set. All three wrappers expose a module named `npc_public_sim_top`, but each must be paired with the filelist on the same row.

| Profile | Native top | Public wrapper / filelist | Defconfig |
| --- | --- | --- | --- |
| Single | [`cpu_top`](rtl/profiles/rv32im_single_perf/cpu_top.v) | [`rv32im_single_perf_sim_top.sv`](rtl/wrappers/rv32im_single_perf_sim_top.sv) / [`rv32im_single_perf.f`](filelists/rv32im_single_perf.f) | `rv32im_single_perf_defconfig` |
| Linux/Sv32 | [`cpu_top`](rtl/profiles/rv32ima_sv32_linux/top/cpu_top.v) | [`rv32ima_sv32_linux_sim_top.sv`](rtl/wrappers/rv32ima_sv32_linux_sim_top.sv) / [`rv32ima_sv32_linux.f`](filelists/rv32ima_sv32_linux.f) | `rv32ima_sv32_linux_defconfig` |
| OoO (default) | [`ooo_npc_top`](rtl/profiles/rv32im_ooo_4k/top/ooo_npc_top.sv) | [`rv32im_ooo_4k_sim_top.sv`](rtl/wrappers/rv32im_ooo_4k_sim_top.sv) / [`rv32im_ooo_4k.f`](filelists/rv32im_ooo_4k.f) | `rv32im_ooo_4k_defconfig` |

See [SoC integration](docs/soc-integration.en.md) for interface, MMIO, commit-packet, and wrapper-selection details.

## Quick Start

Python 3.8+, GNU Make, PyYAML, and Verilator 5.x are required. This keeps OoO as the default Profile and produces a visible `SMOKE_PASS`:

```bash
python3 -m pip install --user PyYAML
make defconfig
make showconfig
make config-check source-check showcase-check public-hygiene
make verilator-lint
make smoke
```

Regenerate `.config` when switching Profiles:

```bash
make rv32im_single_perf_defconfig
make rv32ima_sv32_linux_defconfig
make rv32im_ooo_4k_defconfig
```

The four public ASIC contracts can be checked without commercial EDA. Dry runs print validated stage commands and do not pretend to execute tools:

```bash
make rv32im_single_perf_sram_asic_defconfig
make asic-config-check
make lc-macros-dry-run
make dc-matrix-dry-run
make pnr-dry-run
make sta-dry-run
```

Real EDA runs require user-supplied tools, PDK/library/macro views, and ignored local configuration. The public repository excludes raw reports, mapped/routed netlists, SPEF, GDS, Liberty/DB/LEF, licenses, and private host details.

## Documentation

[Three-Profile architecture](docs/architecture.en.md) · [Simulation and difftest](docs/simulation.en.md) · [Performance and implementation data](docs/performance.en.md) · [Verification matrix](docs/verification.en.md) · [ASIC flow contract](docs/asic-implementation.en.md) · [Backend evidence](docs/evidence/backend_closure.en.md) · [Complete limitations](docs/limitations.en.md) · [Roadmap](docs/roadmap.en.md) · [Documentation index](docs/README.en.md)

## Limitations And Roadmap

A complete Linux distribution boot, FPGA/board validation, coverage closure, and silicon results are not claimed. Single/Linux follow-up work focuses on external IO, electrical exceptions, SRAM characterization, and macro signoff. OoO remains under RTL optimization, with register/SRAM synthesis and backend stages marked `planned/TODO`. A future result advances only after source/config, tool/library, and same-run artifact identity all close.
