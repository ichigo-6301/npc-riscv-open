# NPC RISC-V Three-Profile Processors

[![Public profile CI](https://github.com/ichigo-6301/npc-riscv-open/actions/workflows/public-ci.yml/badge.svg?branch=main)](https://github.com/ichigo-6301/npc-riscv-open/actions/workflows/public-ci.yml) ![RTL](https://img.shields.io/badge/RTL-Verilog%20%2F%20SystemVerilog-2f6f9f) [![License](https://img.shields.io/github/license/ichigo-6301/npc-riscv-open)](LICENSE)

[中文](README.md) · [Architecture](docs/architecture.en.md) · [Performance](docs/performance.en.md) · [Verification](docs/verification.en.md) · [ASIC](docs/asic-implementation.en.md) · [Limitations](docs/limitations.en.md) · [Roadmap](docs/roadmap.en.md)

**A multi-profile RV32 CPU project spanning bare-metal performance, Sv32/Linux system capability, and dual-width out-of-order research, with auditable simulation contracts and Nangate45 academic ASIC backend evidence.**

The three Profiles are independent source locks, not one parameterized RTL design. The actively optimized `rv32im_ooo_4k` remains the default flagship and quickstart; backend-audited results cover the single-issue `rv32im_single_perf` and Linux/Sv32 `rv32ima_sv32_linux` Profiles. The default public entrypoint is [`npc_public_sim_top`](rtl/wrappers/rv32im_ooo_4k_sim_top.sv) with [`filelists/rv32im_ooo_4k.f`](filelists/rv32im_ooo_4k.f); `make defconfig && make smoke` produces a bounded `SMOKE_PASS`.

![NPC RISC-V three-Profile portfolio and backend maturity](docs/assets/profile_portfolio.svg)

## Key Results And Evidence

<!-- showcase:key-results:start -->
<!-- claim:single_public_coremark_timed_cpi maturity:verified -->
<!-- claim:single_public_coremark_per_mhz maturity:verified -->
<!-- claim:single_public_coremark_whole_cpi maturity:verified -->
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
<!-- evidence:coremark_public_current -->
<!-- evidence:linux_coremark_history_public -->
<!-- evidence:linux_boot_history_public -->
<!-- evidence:ooo_historical_optimization_public -->
<!-- evidence:single_xc7z100_history_public -->
<!-- evidence:single_linux_nangate45_backend_public -->
<!-- nonclaim:ooo_public_coremark_runtime_provisional -->
<!-- nonclaim:ooo_ppa_timing_not_claimed -->

| Result | Auditable summary | Maturity and time boundary | Direct evidence |
| --- | --- | --- | --- |
| Single CoreMark | Fixed public configuration timed CPI `1.4849` | `current / verified` | [Guide](docs/evidence/coremark_reproduction.en.md) · [JSON](evidence/performance/coremark.json) |
| Linux performance evolution | Historical whole-program CPI `8.587→1.726`, approximately `4.98x` in the same benchmark family | Optimized endpoint `historical_verified`; A/B comparison `partial`; current source `not_reverified` | [Guide](docs/evidence/performance_history.en.md) · [JSON](evidence/performance/linux_coremark_ab.json) |
| Linux system boot | DTB→OpenSBI→S-mode→Linux `6.6.141`→initramfs shell | `historical_verified`; current source `not_reverified` | [Guide](docs/evidence/system_fpga_history.en.md) · [JSON](evidence/system/linux_boot.json) |
| Historical OoO optimization | frontend-empty `53.76%→23.29%`; redirects/control completion `59.38%→17.73%` | `historical_verified` in `pre-loop-remediation`; current performance `provisional` | [Guide](docs/evidence/performance_history.en.md) · [JSON](evidence/performance/ooo_frontend_branch_ab.json) |
| Historical XC7Z100 implementation | Three historical snapshots complete `200 MHz` routed timing; the early snapshot has UART/ILA observation | implementation/timing `historical_verified`; board/workload binding `partial`; current source `not_claimed` | [Guide](docs/evidence/system_fpga_history.en.md) · [JSON](evidence/fpga/single_xc7z100_history.json) |
| ASIC fixed closure points | Single/Linux × register-expanded/4-macro SRAM, post-route `200–475 MHz` | implementation/internal STA `verified`; SRAM electrical/signoff `partial` | [Guide](docs/evidence/backend_closure.en.md) · [JSON](evidence/implementation/nangate45_fixed_points.json) |
<!-- showcase:key-results:end -->

ASIC values are fixed-frequency Nangate45 academic closure points, not Fmax, complete IO/electrical closure, OCV/MMMC, foundry signoff, or silicon results. The linked documents retain the SRAM macro-model and macro DRC/LVS/PEX boundaries.

## 60-Second Status Matrix

| Profile | Architecture focus | Current public status | Historical/backend boundary |
| --- | --- | --- | --- |
| `rv32im_single_perf` | RV32IM, five-stage single issue, I/D Cache, forwarding, BTB/PHT | Simulation and fixed-source CoreMark `verified` | Layered historical FPGA evidence; register/SRAM fixed points `verified` |
| `rv32ima_sv32_linux` | RV32IMA, M/S, Sv32, precise trap, TLB/PTW | Current bounded regression `verified` | Historical Linux shell verified, current source not deep-rerun; register/SRAM fixed points `verified` |
| `rv32im_ooo_4k` | Dual dispatch/issue/complete/commit, Rename/PRF/ROB/IQ | Default quickstart; performance `provisional` | Historical optimization does not transfer to current RTL; backend `planned / TODO` |

## 10-Minute Code Reading Path

| Reading stage | Entry points | What to inspect |
| --- | --- | --- |
| Three canonical tops | [Single `cpu_top`](rtl/profiles/rv32im_single_perf/cpu_top.v) · [Linux `cpu_top`](rtl/profiles/rv32ima_sv32_linux/top/cpu_top.v) · [OoO `ooo_npc_top`](rtl/profiles/rv32im_ooo_4k/top/ooo_npc_top.sv) | Start with each independent source lock's top-level clock/reset and external-bus boundaries; these are not parameter variants of one core. |
| Single frontend and dependencies | [`if_stage.v`](rtl/profiles/rv32im_single_perf/cpu_top/if_stage.v) · [`id_stage.v`](rtl/profiles/rv32im_single_perf/cpu_top/id_stage.v) | Inspect the 128-entry BTB/PHT, fetch queue, RAW/load-use detection, and cross-stage forwarding. |
| Single caches | [`ICache.v`](rtl/profiles/rv32im_single_perf/cache/ICache.v) · [`DCache.v`](rtl/profiles/rv32im_single_perf/cache/DCache.v) | Inspect each 4 KiB, two-way cache's miss/refill, write path, and pipeline backpressure. |
| Linux privilege and traps | [`PrivCsrRegs.v`](rtl/profiles/rv32ima_sv32_linux/csr/PrivCsrRegs.v) · [`TrapCtrl.v`](rtl/profiles/rv32ima_sv32_linux/csr/TrapCtrl.v) | Inspect M/S CSRs, delegation, precise trap/return, and satp transitions. |
| Linux MMU/PTW/LSU | [`Sv32FrontendPipe.v`](rtl/profiles/rv32ima_sv32_linux/frontend/Sv32FrontendPipe.v) · [`Sv32Tlb.v`](rtl/profiles/rv32ima_sv32_linux/mmu/Sv32Tlb.v) · [`Sv32DCacheBridge.v`](rtl/profiles/rv32ima_sv32_linux/lsu/Sv32DCacheBridge.v) · [`Sv32LSUPipe.v`](rtl/profiles/rv32ima_sv32_linux/lsu/Sv32LSUPipe.v) | Inspect ITLB/DTLB lookup, two-level PTW/replay, permission/page-fault handling, store buffering, and load-hit paths. |
| OoO rename/schedule/retire | [`ooo_rename_dispatch_recovery_2w.sv`](rtl/profiles/rv32im_ooo_4k/core/ooo_rename_dispatch_recovery_2w.sv) · [`ooo_prf.sv`](rtl/profiles/rv32im_ooo_4k/core/ooo_prf.sv) · [`small_rob.sv`](rtl/profiles/rv32im_ooo_4k/core/small_rob.sv) · [`alu_issue_queue_1w.sv`](rtl/profiles/rv32im_ooo_4k/core/alu_issue_queue_1w.sv) | Inspect tags, readiness, age, and precise-state boundaries across dual dispatch/issue/complete/commit. |
| OoO recovery and LSU ownership | [`ooo_branch_checkpoint_state_2w.sv`](rtl/profiles/rv32im_ooo_4k/core/ooo_branch_checkpoint_state_2w.sv) · [`ooo_lsu_atomic_mem_arbiter_2e.sv`](rtl/profiles/rv32im_ooo_4k/execute/ooo_lsu_atomic_mem_arbiter_2e.sv) · [`ooo_precise_store_buffer_4entry.sv`](rtl/profiles/rv32im_ooo_4k/execute/ooo_precise_store_buffer_4entry.sv) | Inspect checkpoint/generation recovery and causal ownership across Issue/WB/Commit and the LSU. |
| Public ABI and verification loop | [Single wrapper](rtl/wrappers/rv32im_single_perf_sim_top.sv) · [Linux wrapper](rtl/wrappers/rv32ima_sv32_linux_sim_top.sv) · [OoO wrapper](rtl/wrappers/rv32im_ooo_4k_sim_top.sv) · [`profile_abi.hpp`](sim/include/profile_abi.hpp) · [`nemu_public_adapter.cpp`](sim/adapters/nemu_public_adapter.cpp) · [`verilator_runner.py`](sim/common/verilator_runner.py) · [`verilator_main.cpp`](sim/common/verilator_main.cpp) · [bounded smoke](tests/sources/rv32im_core_smoke.S) | Inspect the shared commit packet, profile-specific NEMU state mapping, watchdog/PASS marker, and bounded self-check. |

## Quick Checks Without Commercial EDA

Python 3.8+, GNU Make, PyYAML, and Verilator 5.x are required. The default quickstart keeps OoO selected and produces a visible `SMOKE_PASS`:

```bash
python3 -m pip install --user PyYAML
make defconfig
make showconfig config-check source-check
make verilator-lint smoke regression
```

Run the same contract across all three Profiles:

```bash
for profile in rv32im_single_perf rv32ima_sv32_linux rv32im_ooo_4k; do
  make "${profile}_defconfig"
  make showconfig config-check source-check sim-dry-run verilator-lint smoke regression
done
make runtime-tests docs-check evidence-check showcase-check implementation-check
make verify-checksums public-hygiene
```

Validate the four public Single/Linux ASIC configurations as contracts and dry-runs only:

```bash
for defconfig in rv32im_single_perf_asic_defconfig \
                 rv32im_single_perf_sram_asic_defconfig \
                 rv32ima_sv32_linux_asic_defconfig \
                 rv32ima_sv32_linux_sram_asic_defconfig; do
  make "${defconfig}"
  make asic-config-check lc-macros-dry-run dc-matrix-dry-run pnr-dry-run sta-dry-run
done
```

`evidence-check` and `showcase-check` validate published records only. ASIC `*-dry-run` targets validate configuration, identity, and command contracts; they neither invoke nor imitate real DC, OpenROAD, OpenRCX, or PrimeTime execution.

## Canonical Top And Filelist

Each build selects exactly one source set. All three wrappers expose a module named `npc_public_sim_top`, but each must be paired with the filelist on the same row.

| Profile | Native top | Public wrapper / filelist | Defconfig |
| --- | --- | --- | --- |
| Single | [`cpu_top`](rtl/profiles/rv32im_single_perf/cpu_top.v) | [`rv32im_single_perf_sim_top.sv`](rtl/wrappers/rv32im_single_perf_sim_top.sv) / [`rv32im_single_perf.f`](filelists/rv32im_single_perf.f) | `rv32im_single_perf_defconfig` |
| Linux/Sv32 | [`cpu_top`](rtl/profiles/rv32ima_sv32_linux/top/cpu_top.v) | [`rv32ima_sv32_linux_sim_top.sv`](rtl/wrappers/rv32ima_sv32_linux_sim_top.sv) / [`rv32ima_sv32_linux.f`](filelists/rv32ima_sv32_linux.f) | `rv32ima_sv32_linux_defconfig` |
| OoO (default) | [`ooo_npc_top`](rtl/profiles/rv32im_ooo_4k/top/ooo_npc_top.sv) | [`rv32im_ooo_4k_sim_top.sv`](rtl/wrappers/rv32im_ooo_4k_sim_top.sv) / [`rv32im_ooo_4k.f`](filelists/rv32im_ooo_4k.f) | `rv32im_ooo_4k_defconfig` |

See [SoC integration](docs/soc-integration.en.md) for interfaces, MMIO, commit packets, and wrapper selection.

## Documentation

[Three-Profile architecture](docs/architecture.en.md) · [Simulation and difftest](docs/simulation.en.md) · [Performance and implementation data](docs/performance.en.md) · [Historical performance evidence](docs/evidence/performance_history.en.md) · [System/FPGA evidence](docs/evidence/system_fpga_history.en.md) · [Verification matrix](docs/verification.en.md) · [ASIC flow contract](docs/asic-implementation.en.md) · [Backend evidence](docs/evidence/backend_closure.en.md) · [Complete limitations](docs/limitations.en.md) · [Roadmap](docs/roadmap.en.md) · [Documentation index](docs/README.en.md)

## Limitations And Roadmap

Historical Linux boot and XC7Z100 implementation/board observation are published by source snapshot. A deep boot on the current Linux source, a new board run of the current Single source, coverage closure, and silicon results remain `not_claimed`. Single/Linux work continues on source-matched system reruns, external IO, electrical exceptions, SRAM characterization, and macro signoff. OoO remains under loop-free RTL optimization; verified current performance and register/SRAM backend results remain `provisional` / `planned`.
