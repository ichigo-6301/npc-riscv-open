# NPC RISC-V 三 Profile 处理器

[![Public profile CI](https://github.com/ichigo-6301/npc-riscv-open/actions/workflows/public-ci.yml/badge.svg?branch=main)](https://github.com/ichigo-6301/npc-riscv-open/actions/workflows/public-ci.yml) ![RTL](https://img.shields.io/badge/RTL-Verilog%20%2F%20SystemVerilog-2f6f9f) [![License](https://img.shields.io/github/license/ichigo-6301/npc-riscv-open)](LICENSE)

[English](README.en.md) · [架构](docs/architecture.md) · [性能](docs/performance.md) · [验证](docs/verification.md) · [ASIC](docs/asic-implementation.md) · [限制](docs/limitations.md) · [Roadmap](docs/roadmap.md)

**一个覆盖裸机性能、Sv32/Linux 系统能力与双宽乱序研究的多 Profile RV32 CPU 项目，并公开可复查的仿真合同与 Nangate45 academic ASIC 后端证据。**

三套 Profile 是独立 source lock，不是同一份参数化 RTL。默认旗舰与 quickstart 仍是正在优化的 `rv32im_ooo_4k`；已完成后端审计的是单发射 `rv32im_single_perf` 和 Linux/Sv32 `rv32ima_sv32_linux`。默认公开仿真入口为 [`npc_public_sim_top`](rtl/wrappers/rv32im_ooo_4k_sim_top.sv) + [`filelists/rv32im_ooo_4k.f`](filelists/rv32im_ooo_4k.f)，运行 `make defconfig && make smoke` 可得到有界 `SMOKE_PASS`。

![NPC RISC-V 三 Profile 与后端成熟度](docs/assets/profile_portfolio.svg)

## 关键结果与证据入口

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

| 结果 | 可核验摘要 | 成熟度与时间边界 | 直接证据 |
| --- | --- | --- | --- |
| Single CoreMark | 固定公开配置 timed CPI `1.4849` | `current / verified` | [说明](docs/evidence/coremark_reproduction.md) · [JSON](evidence/performance/coremark.json) |
| Linux 性能演进 | historical whole-program CPI `8.587→1.726`，同 benchmark family 约 `4.98x` | 优化端点 `historical_verified`；A/B comparison `partial`；当前 source `not_reverified` | [说明](docs/evidence/performance_history.md) · [JSON](evidence/performance/linux_coremark_ab.json) |
| Linux 系统启动 | DTB→OpenSBI→S-mode→Linux `6.6.141`→initramfs shell | `historical_verified`；当前 source `not_reverified` | [说明](docs/evidence/system_fpga_history.md) · [JSON](evidence/system/linux_boot.json) |
| OoO 历史优化 | frontend-empty `53.76%→23.29%`；redirect/control completion `59.38%→17.73%` | `historical_verified` 于 `pre-loop-remediation`；当前性能 `provisional` | [说明](docs/evidence/performance_history.md) · [JSON](evidence/performance/ooo_frontend_branch_ab.json) |
| XC7Z100 历史实现 | 三个历史快照完成 `200 MHz` routed timing；早期快照有 UART/ILA 观测 | implementation/timing `historical_verified`；board/workload binding `partial`；当前 source `not_claimed` | [说明](docs/evidence/system_fpga_history.md) · [JSON](evidence/fpga/single_xc7z100_history.json) |
| ASIC 固定闭合点 | Single/Linux × register-expanded/4-macro SRAM，post-route `200–475 MHz` | implementation/internal STA `verified`；SRAM electrical/signoff `partial` | [说明](docs/evidence/backend_closure.md) · [JSON](evidence/implementation/nangate45_fixed_points.json) |
<!-- showcase:key-results:end -->

ASIC 数值仅是固定频率的 Nangate45 academic closure point，不是 Fmax、完整 IO/电气闭合、OCV/MMMC、foundry signoff 或 silicon result。SRAM 行的 macro model 与 macro DRC/LVS/PEX 边界见链接文档。

## 60 秒状态矩阵

| Profile | 架构重点 | 当前公开状态 | 历史/后端边界 |
| --- | --- | --- | --- |
| `rv32im_single_perf` | RV32IM，5 级单发射，I/D Cache、forwarding、BTB/PHT | 仿真与 fixed-source CoreMark `verified` | 历史 FPGA 分层披露；register/SRAM fixed point `verified` |
| `rv32ima_sv32_linux` | RV32IMA，M/S、Sv32、精确 trap、TLB/PTW | 当前 bounded 回归 `verified` | 历史 Linux shell `verified`、当前未深跑；register/SRAM fixed point `verified` |
| `rv32im_ooo_4k` | 双 dispatch/issue/complete/commit，Rename/PRF/ROB/IQ | 默认 quickstart；性能 `provisional` | 历史优化不继承到当前；后端 `planned / TODO` |

## 10 分钟代码阅读路径

| 阅读阶段 | 入口 | 阅读重点 |
| --- | --- | --- |
| 三个 canonical top | [Single `cpu_top`](rtl/profiles/rv32im_single_perf/cpu_top.v) · [Linux `cpu_top`](rtl/profiles/rv32ima_sv32_linux/top/cpu_top.v) · [OoO `ooo_npc_top`](rtl/profiles/rv32im_ooo_4k/top/ooo_npc_top.sv) | 先看三套独立 source lock 的顶层边界、时钟复位和外部总线，而不是把它们当作参数化同核。 |
| Single 前端与相关性 | [`if_stage.v`](rtl/profiles/rv32im_single_perf/cpu_top/if_stage.v) · [`id_stage.v`](rtl/profiles/rv32im_single_perf/cpu_top/id_stage.v) | 关注 128-entry BTB/PHT、取指队列、RAW/load-use 检测与跨级 forwarding。 |
| Single Cache | [`ICache.v`](rtl/profiles/rv32im_single_perf/cache/ICache.v) · [`DCache.v`](rtl/profiles/rv32im_single_perf/cache/DCache.v) | 关注各 4 KiB、2-way cache 的 miss/refill、写路径和流水线 backpressure。 |
| Linux 特权与 trap | [`PrivCsrRegs.v`](rtl/profiles/rv32ima_sv32_linux/csr/PrivCsrRegs.v) · [`TrapCtrl.v`](rtl/profiles/rv32ima_sv32_linux/csr/TrapCtrl.v) | 关注 M/S CSR、委托、精确 trap/return 与 satp 切换。 |
| Linux MMU/PTW/LSU | [`Sv32FrontendPipe.v`](rtl/profiles/rv32ima_sv32_linux/frontend/Sv32FrontendPipe.v) · [`Sv32Tlb.v`](rtl/profiles/rv32ima_sv32_linux/mmu/Sv32Tlb.v) · [`Sv32DCacheBridge.v`](rtl/profiles/rv32ima_sv32_linux/lsu/Sv32DCacheBridge.v) · [`Sv32LSUPipe.v`](rtl/profiles/rv32ima_sv32_linux/lsu/Sv32LSUPipe.v) | 关注 ITLB/DTLB、两级 PTW/replay、权限/页故障、store buffer 与 load-hit 路径。 |
| OoO Rename/调度/退休 | [`ooo_rename_dispatch_recovery_2w.sv`](rtl/profiles/rv32im_ooo_4k/core/ooo_rename_dispatch_recovery_2w.sv) · [`ooo_prf.sv`](rtl/profiles/rv32im_ooo_4k/core/ooo_prf.sv) · [`small_rob.sv`](rtl/profiles/rv32im_ooo_4k/core/small_rob.sv) · [`alu_issue_queue_1w.sv`](rtl/profiles/rv32im_ooo_4k/core/alu_issue_queue_1w.sv) | 关注双 dispatch/issue/complete/commit 的 tag、ready、年龄与精确状态边界。 |
| OoO 恢复与 LSU ownership | [`ooo_branch_checkpoint_state_2w.sv`](rtl/profiles/rv32im_ooo_4k/core/ooo_branch_checkpoint_state_2w.sv) · [`ooo_lsu_atomic_mem_arbiter_2e.sv`](rtl/profiles/rv32im_ooo_4k/execute/ooo_lsu_atomic_mem_arbiter_2e.sv) · [`ooo_precise_store_buffer_4entry.sv`](rtl/profiles/rv32im_ooo_4k/execute/ooo_precise_store_buffer_4entry.sv) | 关注 checkpoint/generation 恢复以及 Issue/WB/Commit 与 LSU 的 causal ownership。 |
| 公共 ABI 与验证闭环 | [Single wrapper](rtl/wrappers/rv32im_single_perf_sim_top.sv) · [Linux wrapper](rtl/wrappers/rv32ima_sv32_linux_sim_top.sv) · [OoO wrapper](rtl/wrappers/rv32im_ooo_4k_sim_top.sv) · [`profile_abi.hpp`](sim/include/profile_abi.hpp) · [`nemu_public_adapter.cpp`](sim/adapters/nemu_public_adapter.cpp) · [`verilator_runner.py`](sim/common/verilator_runner.py) · [`verilator_main.cpp`](sim/common/verilator_main.cpp) · [bounded smoke](tests/sources/rv32im_core_smoke.S) | 关注统一 commit packet、profile-specific NEMU 状态映射、watchdog/PASS marker 与有界自检。 |

## 快速检查（不依赖商业 EDA）

依赖为 Python 3.8+、GNU Make、PyYAML 和 Verilator 5.x。默认 quickstart 保持 OoO，并产生可见的 `SMOKE_PASS`：

```bash
python3 -m pip install --user PyYAML
make defconfig
make showconfig config-check source-check
make verilator-lint smoke regression
```

三 Profile 可按同一合同检查：

```bash
for profile in rv32im_single_perf rv32ima_sv32_linux rv32im_ooo_4k; do
  make "${profile}_defconfig"
  make showconfig config-check source-check sim-dry-run verilator-lint smoke regression
done
make runtime-tests docs-check evidence-check showcase-check implementation-check
make verify-checksums public-hygiene
```

四个 Single/Linux ASIC 配置只做公开合同与 dry-run 验证：

```bash
for defconfig in rv32im_single_perf_asic_defconfig \
                 rv32im_single_perf_sram_asic_defconfig \
                 rv32ima_sv32_linux_asic_defconfig \
                 rv32ima_sv32_linux_sram_asic_defconfig; do
  make "${defconfig}"
  make asic-config-check lc-macros-dry-run dc-matrix-dry-run pnr-dry-run sta-dry-run
done
```

`evidence-check`/`showcase-check` 只验证已公开记录，ASIC `*-dry-run` 只验证配置、身份与命令合同；它们不会调用或伪装 DC、OpenROAD、OpenRCX、PrimeTime 等真实 EDA 执行。

## Canonical top 与 filelist

每次构建只选择一套 source set。三个 wrapper 都提供相同名称的 `npc_public_sim_top`，但只能与同一行的 filelist 配对。

| Profile | Native top | Public wrapper / filelist | Defconfig |
| --- | --- | --- | --- |
| Single | [`cpu_top`](rtl/profiles/rv32im_single_perf/cpu_top.v) | [`rv32im_single_perf_sim_top.sv`](rtl/wrappers/rv32im_single_perf_sim_top.sv) / [`rv32im_single_perf.f`](filelists/rv32im_single_perf.f) | `rv32im_single_perf_defconfig` |
| Linux/Sv32 | [`cpu_top`](rtl/profiles/rv32ima_sv32_linux/top/cpu_top.v) | [`rv32ima_sv32_linux_sim_top.sv`](rtl/wrappers/rv32ima_sv32_linux_sim_top.sv) / [`rv32ima_sv32_linux.f`](filelists/rv32ima_sv32_linux.f) | `rv32ima_sv32_linux_defconfig` |
| OoO（默认） | [`ooo_npc_top`](rtl/profiles/rv32im_ooo_4k/top/ooo_npc_top.sv) | [`rv32im_ooo_4k_sim_top.sv`](rtl/wrappers/rv32im_ooo_4k_sim_top.sv) / [`rv32im_ooo_4k.f`](filelists/rv32im_ooo_4k.f) | `rv32im_ooo_4k_defconfig` |

SoC 接口、MMIO、commit packet 与 wrapper 选择见[集成说明](docs/soc-integration.md)。

## 文档导航

[三 Profile 架构](docs/architecture.md) · [仿真与 difftest](docs/simulation.md) · [性能与实现数据](docs/performance.md) · [历史性能证据](docs/evidence/performance_history.md) · [系统/FPGA 证据](docs/evidence/system_fpga_history.md) · [验证矩阵](docs/verification.md) · [ASIC 流程合同](docs/asic-implementation.md) · [后端证据](docs/evidence/backend_closure.md) · [完整限制](docs/limitations.md) · [后续路线](docs/roadmap.md) · [文档索引](docs/README.md)

## 限制与 Roadmap

历史 Linux boot 和 XC7Z100 implementation/board observation 已按 source snapshot 分层公开；当前 Linux source 的深跑复验、当前 Single source 的重新上板、coverage closure 和 silicon 结果仍为 `not_claimed`。Single/Linux 后续工作集中在 source-matched 系统复验、外部 IO、电气例外、SRAM characterization 与 macro signoff；OoO 当前继续做无环 RTL 优化，其 verified performance 与 register/SRAM 后端保持 `provisional` / `planned`。
