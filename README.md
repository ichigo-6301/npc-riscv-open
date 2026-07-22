# NPC RISC-V 多 Profile 公开发行版

本仓库是 `npc-riscv-open-v0.1.0-rc1` 的三个 RISC-V CPU profile 纯
Verilator、无板级界面发行版。仓库只保留一个 `main` 分支；三个 profile 使用
各自独立的 RTL source set，并由声明式 manifest 选择，单次构建不会把三套 RTL
混在一起。

默认 profile 为 `rv32im_ooo_4k`。构建前先选择并检查生效配置：

```text
make defconfig
make showconfig
make config-check source-check public-hygiene
make sim-dry-run
make verilator-lint
```

三个 profile 分别是单发射性能、单发射 Sv32 Linux 和双发射乱序性能。它们
分别绑定 wrapper、filelist、源提交和证据；共享的部分仅包括公开流程控制、
Verilator 运行器和测试接口。

| 维度 | RC1 状态 |
| --- | --- |
| 三套 RTL source set、纯 headless wrapper | verified by source closure/lint |
| 三 profile bounded self-check | verified in a native-Linux fresh clone (seed 1) |
| Linux 完整启动/OpenSBI | planned/partial；外部 firmware，不是 RC1 完成声明 |
| Difftest | 可选的 profile 匹配 NEMU adapter；默认关闭 |
| ASIC PPA、时序、SRAM/PDK signoff | not_claimed |

公开边界不包含板级用户界面、专有 EDA 数据库、PDK、生成物或私有参考模型
源码。可选外部参考适配器只能在运行时通过
[公开 ABI](sim/include/profile_abi.hpp) 提供路径，不随仓库发布；只 `dlopen`
一个库不会被视为 difftest 通过。

NEMU 是外部 Mulan PSL-2.0 依赖，不进入 Git 发行包。严格测试前执行
`make difftest-prepare NPC_NEMU_SOURCE_REPO=/path/to/ysyx-workbench`，脚本会
按 profile 构建被 `.gitignore` 忽略的 raw reference 和 MIT adapter；随后执行
`make difftest`。发行版默认配置保持 difftest 关闭，因此没有 NEMU 的 fresh
clone 仍可正常仿真。当前 adapter 关闭 trace、mtrace/ftrace 和 device 文件
输出；完整 Linux 中断/MMIO difftest 不属于 RC1 的 bounded 合同。

性能、实现和时序结论始终按 profile 隔离。只有当 binary hash、配置、源提交
和可复现实验证据都登记在 `delivery/` 与 `evidence/` 后，结果才可标记为公开
verified claim。

本 RC1 的 fresh-clone 证据只覆盖仓库内 bounded images：单发射 smoke 为
269 cycles/27 commits，Linux profile 的两个 bounded images 为 162/27 和
80/15，乱序 smoke 为 107 cycles/21 commits/5 second-lane commits。CoreMark、
OoO fixed-tail workloads、完整 OpenSBI/Linux boot、外部 difftest 和私有
commit-trace equivalence 仍依赖未随仓库发布的外部 fixture，因此不构成公开
性能 claim。

详见 [docs/README.md](docs/README.md)、[docs/README.en.md](docs/README.en.md)、
[docs/reproduction.md](docs/reproduction.md) 和 [docs/limitations.md](docs/limitations.md)。

英文平行文档见 [README.en.md](README.en.md)。
