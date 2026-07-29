# NPC RISC-V 三 Profile 处理器

[![Public profile CI](https://github.com/ichigo-6301/npc-riscv-open/actions/workflows/public-ci.yml/badge.svg?branch=main)](https://github.com/ichigo-6301/npc-riscv-open/actions/workflows/public-ci.yml) ![RTL](https://img.shields.io/badge/RTL-Verilog%20%2F%20SystemVerilog-2f6f9f) [![License](https://img.shields.io/github/license/ichigo-6301/npc-riscv-open)](LICENSE)

[English](README.en.md) · [架构](docs/architecture.md) · [性能](docs/performance.md) · [验证](docs/verification.md) · [ASIC](docs/asic-implementation.md) · [限制](docs/limitations.md) · [Roadmap](docs/roadmap.md)

**一个覆盖裸机性能、Sv32/Linux 系统能力与双宽乱序研究的多 Profile RV32 CPU 项目，并公开可复查的仿真合同与 Nangate45 academic ASIC 后端证据。**

三套 Profile 是独立 source lock，不是同一份参数化 RTL。默认旗舰与 quickstart 仍是正在优化的 `rv32im_ooo_4k`；已完成后端审计的是单发射 `rv32im_single_perf` 和 Linux/Sv32 `rv32ima_sv32_linux`。默认公开仿真入口为 [`npc_public_sim_top`](rtl/wrappers/rv32im_ooo_4k_sim_top.sv) + [`filelists/rv32im_ooo_4k.f`](filelists/rv32im_ooo_4k.f)，运行 `make defconfig && make smoke` 可得到有界 PASS 结果。

![NPC RISC-V 三 Profile 与后端成熟度](docs/assets/profile_portfolio.svg)

## 60 秒状态矩阵

<!-- evidence:single_linux_nangate45_backend_public -->
<!-- nonclaim:ooo_ppa_timing_not_claimed -->

| Profile | ISA / 微架构 | 公开 RTL 与 runtime | Register-expanded 后端 | SRAM-macro 后端 |
| --- | --- | --- | --- | --- |
| `rv32im_single_perf` | RV32IM，5 级单发射顺序流水线 | source closure、lint、smoke/regression 与固定 CoreMark/NEMU 路径已验证 | `verified` fixed point | `verified` fixed point |
| `rv32ima_sv32_linux` | RV32IMA，M/S + Sv32，单发射 | source closure 与 bounded 体系结构回归已验证；提供外部镜像驱动的 OpenSBI 入口，payload-bound execution 仍为 `partial`，完整 Linux boot 不声明 | `verified` fixed point | `verified` fixed point |
| `rv32im_ooo_4k` | RV32IM，双 dispatch/issue/complete/commit OoO | 默认旗舰；RTL 与公开 runtime 可运行，性能 claim 仍为 `provisional` | `planned / TODO` | `planned / TODO` |

`verified` 在这里仅表示固定频率的 Nangate45 academic physical implementation 与 internal extracted setup/hold STA。它不表示 Fmax、完整 IO/电气闭合、foundry signoff 或 silicon result。

## 已验证结果

### Nangate45 固定频率闭合点

![Single 与 Linux 的 Nangate45 固定频率闭合点](docs/assets/nangate45_closure_points.svg)

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

| 路线 | DC / route+PT | PT setup / hold WNS | Standard-cell / core footprint | Macro |
| --- | ---: | ---: | ---: | ---: |
| Single / registers | 540 / 425 MHz | +0.025646 / +0.063219 ns | 0.679497 / 2.614530 mm² | 0 |
| Single / SRAM | 600 / 475 MHz | +0.013556 / +0.047904 ns | 0.149292 / 0.858801 mm² | 4 |
| Linux / registers | 280 / 200 MHz | +0.387809 / +0.032648 ns | 0.717964 / 2.825040 mm² | 0 |
| Linux / SRAM | 300 / 200 MHz | +0.720415 / +0.039090 ns | 0.198085 / 1.049500 mm² | 4 |

四条路线均完成 placement、CTS、detail route、GDS、OpenRCX 和 PrimeTime，detail-route DRC / antenna / unrouted 均为 `0 / 0 / 0`。mapped netlist、P&R import、routed netlist/SDC、SPEF 与 Liberty/DB 的角色级 SHA256 和 same-run identity 见[后端证据说明](docs/evidence/backend_closure.md)与[机器可读证据](evidence/implementation/nangate45_fixed_points.json)。

SRAM 行使用 OpenRAM analytical FreePDK45 TT / 1.0 V / 25 C macro view 与 Nangate45 typical / 1.1 V / 25 C standard-cell view，保留 RC-004；macro DRC/LVS/PEX、OCV/MMMC、DFT、LEC、power/PI 尚未闭合。寄存器与 SRAM 行代表不同 memory binding，不能把面积差直接解释为完整芯片 PPA 改善。

### 仿真性能

<!-- claim:single_public_coremark_timed_cpi maturity:verified -->
<!-- claim:single_public_coremark_per_mhz maturity:verified -->
<!-- claim:single_public_coremark_whole_cpi maturity:verified -->
<!-- evidence:coremark_public_current -->
<!-- nonclaim:ooo_public_coremark_runtime_provisional -->

| Profile | CoreMark timed CPI | CoreMark/MHz | Whole-program CPI | 边界 |
| --- | ---: | ---: | ---: | --- |
| `rv32im_single_perf` | 1.484920431 | 2.201416876 | 1.485861312 | `verified`，固定 binary/config，NEMU difftest PASS |
| `rv32ima_sv32_linux` | 1.725375105 | 1.894598197 | 1.725944902 | `historical_verified` 于 `abf66cad`；`0fc3de40` source lock 尚待同输入复测 |
| `rv32im_ooo_4k` | 0.879973757 | 3.714802709 | 0.882383851 | `provisional`，self-check PASS；双退休 MMIO difftest 顺序仍未消歧 |

`CoreMark/MHz` 是固定 marker 区间内每百万仿真周期完成的 iteration 数，不是绝对 CoreMark score，也不假设已实现时钟。完整计数、binary/config hash 与复现合同见[性能页](docs/performance.md)和[CoreMark 证据](docs/evidence/coremark_reproduction.md)。

## Canonical top 与 filelist

每次构建只选择一套 source set。三个 wrapper 都提供相同名称的 `npc_public_sim_top`，但只能与同一行的 filelist 配对。

| Profile | Native top | Public wrapper / filelist | Defconfig |
| --- | --- | --- | --- |
| Single | [`cpu_top`](rtl/profiles/rv32im_single_perf/cpu_top.v) | [`rv32im_single_perf_sim_top.sv`](rtl/wrappers/rv32im_single_perf_sim_top.sv) / [`rv32im_single_perf.f`](filelists/rv32im_single_perf.f) | `rv32im_single_perf_defconfig` |
| Linux/Sv32 | [`cpu_top`](rtl/profiles/rv32ima_sv32_linux/top/cpu_top.v) | [`rv32ima_sv32_linux_sim_top.sv`](rtl/wrappers/rv32ima_sv32_linux_sim_top.sv) / [`rv32ima_sv32_linux.f`](filelists/rv32ima_sv32_linux.f) | `rv32ima_sv32_linux_defconfig` |
| OoO（默认） | [`ooo_npc_top`](rtl/profiles/rv32im_ooo_4k/top/ooo_npc_top.sv) | [`rv32im_ooo_4k_sim_top.sv`](rtl/wrappers/rv32im_ooo_4k_sim_top.sv) / [`rv32im_ooo_4k.f`](filelists/rv32im_ooo_4k.f) | `rv32im_ooo_4k_defconfig` |

SoC 接口、MMIO、commit packet 与 wrapper 选择见[集成说明](docs/soc-integration.md)。

## 快速开始

依赖为 Python 3.8+、GNU Make、PyYAML 和 Verilator 5.x。下面保持 OoO 为默认 Profile，并产生可见的 `SMOKE_PASS`：

```bash
python3 -m pip install --user PyYAML
make defconfig
make showconfig
make config-check source-check showcase-check public-hygiene
make verilator-lint
make smoke
```

切换 Profile 后重新生成 `.config`：

```bash
make rv32im_single_perf_defconfig
make rv32ima_sv32_linux_defconfig
make rv32im_ooo_4k_defconfig
```

不安装商业 EDA 也可以检查四个公开 ASIC 合同；dry-run 只打印经过校验的阶段命令，不伪装工具执行：

```bash
make rv32im_single_perf_sram_asic_defconfig
make asic-config-check
make lc-macros-dry-run
make dc-matrix-dry-run
make pnr-dry-run
make sta-dry-run
```

真实 EDA 运行需要用户自备工具、PDK/library/macro views 和 ignored 本地配置。公开仓库不包含 raw report、mapped/routed netlist、SPEF、GDS、Liberty/DB/LEF、license 或私有主机信息。

## 文档导航

[三 Profile 架构](docs/architecture.md) · [仿真与 difftest](docs/simulation.md) · [性能与实现数据](docs/performance.md) · [验证矩阵](docs/verification.md) · [ASIC 流程合同](docs/asic-implementation.md) · [后端证据](docs/evidence/backend_closure.md) · [完整限制](docs/limitations.md) · [后续路线](docs/roadmap.md) · [文档索引](docs/README.md)

## 限制与后续

完整 Linux distribution boot、FPGA/board、coverage closure 和 silicon 结果均不声明。Single/Linux 后续工作集中在外部 IO、电气例外、SRAM characterization 与 macro signoff；OoO 当前继续做 RTL 优化，其 register/SRAM 综合与后端流程保持 `planned/TODO`。新增结果只有在 source/config、工具/库和 same-run artifact identity 全部闭合后才会提升成熟度。
