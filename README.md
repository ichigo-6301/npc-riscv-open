# NPC RISC-V 多 Profile 处理器

[English](README.en.md)

NPC RISC-V Open 提供三套用途不同的 RISC-V 处理器 RTL，以及一套共享的纯
Verilator 仿真基础设施。默认配置是 `rv32im_ooo_4k`。仓库不依赖 NVBoard，
也不包含显示、键盘或其他板级界面。

三套 RTL 来自独立且固定的源提交。它们共享配置入口、headless wrapper、
仿真运行时和 commit packet ABI，但不是同一套参数化 RTL；一次构建只选择
一个 Profile 的 filelist。

## 主要特性

- RV32IM 五级顺序单发射核心，面向通用裸机与性能实验。
- RV32IMA、M/S 特权级和 Sv32 的五级顺序核心，带 TLB、store buffer 和
  ACLINT timer。
- RV32IM 双发射、双退休乱序核心，带 64-entry PRF、ROB8、IQ8 和两项分支
  checkpoint。
- 三个 Profile 共用纯 Verilator 命令行运行时；difftest 可按 Profile 接入
  本地 NEMU，默认关闭。
- 源文件、配置、测试和历史测量均绑定 Profile 与固定 commit，禁止跨
  Profile 混用数字。

## Profile 对比

| Profile | ISA / 特权级 | 微架构 | 指令与数据结构 | 主要用途 |
| --- | --- | --- | --- | --- |
| `rv32im_single_perf` | RV32IM / M | 5-stage，单发射、单退休 | 4 KiB 两路 I-cache + 4 KiB 两路 D-cache；128-entry BTB/PHT | 裸机、CoreMark 和顺序流水线研究 |
| `rv32ima_sv32_linux` | RV32IMA / M+S，Sv32 | 5-stage，单发射、单退休 | 4 KiB 两路 I/D cache；16-entry ITLB/DTLB；2-entry store buffer；ACLINT | OpenSBI、Sv32 和操作系统集成研究 |
| `rv32im_ooo_4k` | RV32IM / M | 双 dispatch/issue/complete/commit 的 OoO 核心 | 4 KiB instruction-pair storage；4 KiB physically tagged word cache | 双宽乱序吞吐与性能研究 |

`rv32im_ooo_4k` 的 instruction-pair storage 是按 64-bit 指令对组织的前端
存储，不等同于传统 set-associative I-cache。三套结构的详细差异见
[架构说明](docs/architecture.md)。

## 快速开始

需要 Python 3.8+、GNU Make、PyYAML 和 Verilator 5.x：

```sh
python3 -m pip install --user PyYAML
make defconfig
make showconfig
make config-check source-check docs-check public-hygiene
make verilator-lint
make smoke
```

切换 Profile 时重新生成 `.config`：

```sh
make rv32im_single_perf_defconfig
make rv32ima_sv32_linux_defconfig
make rv32im_ooo_4k_defconfig
```

运行自备程序镜像：

```sh
NPC_OPEN_IMAGE=/path/to/program.bin make sim
```

默认配置无需 NEMU。严格测试可在本地准备与 Profile 匹配的参考模型：

```sh
make difftest-prepare NPC_NEMU_SOURCE_REPO=/path/to/ysyx-workbench
make difftest
```

生成的参考 `.so`、日志、波形和构建目录均被 Git 忽略。完整流程见
[仿真指南](docs/simulation.md)和[验证说明](docs/verification.md)。

## 架构、性能与 SoC 集成

- [架构说明](docs/architecture.md)：三套流水线、预测器、存储结构和接口。
- [性能与实现数据](docs/performance.md)：公开复现表和严格标注的历史参考值。
- [SoC 集成](docs/soc-integration.md)：DPI runtime、Linux RTL timer 与
  NEMU/AM 参考外设的边界。

当前公开流程已覆盖 source closure、Verilator lint、bounded smoke 和回归；
外部 CoreMark binary 也可由 headless runner 得到 cycles/commit/CPI。由于
binary 未随仓库提供且 profile-matched difftest 尚未全部接受，这些性能行仍标为
`provisional`，不能解释为最大频率、物理实现或硅后结果。

## 项目边界

本仓库不携带 NEMU、AM、OpenSBI、Linux、PDK、Liberty、SRAM macro、EDA
数据库或板级工程。MIT 许可证仅覆盖仓库中明确列出的自有 RTL、wrapper、
脚本和文档。第三方组件由使用者按各自许可证另行取得。

更多信息见[文档索引](docs/README.md)、[限制说明](docs/limitations.md)、
[证据规则](evidence/README.md)和 [NOTICE](NOTICE)。
