# NPC RISC-V Open 文档

[English](README.en.md)

本项目包含三套相互独立的处理器 RTL source set，以及共享的纯 Verilator
运行环境。Profile manifest 是 ISA、top、wrapper、filelist、源 commit 和默认
运行条件的唯一事实来源。

## Profile

| Profile | 架构定位 | 当前公开验证状态 |
| --- | --- | --- |
| `rv32im_single_perf` | RV32IM 五级顺序单发射 | source closure、回归与 hash-locked CoreMark+difftest 已验证 |
| `rv32ima_sv32_linux` | RV32IMA M/S + Sv32 五级顺序单发射 | bounded 架构测试与 hash-locked CoreMark+difftest 已验证；完整 Linux 未声明 |
| `rv32im_ooo_4k` | RV32IM 双发射、双退休 OoO | source closure、双宽回归已验证；CoreMark 因双退休 MMIO difftest 边界为 provisional |

三套 RTL 不是同一套参数化实现。构建系统每次只编译一个 source set，公共
wrapper 只统一 commit、halt 和 debug 观测接口。

## 技术文档

- [架构说明](architecture.md)：流水线、预测器、cache/TLB、OoO 资源和接口。
- [性能与实现数据](performance.md)：公开复现表、历史参考值和证据状态。
- [SoC 集成](soc-integration.md)：DPI、ACLINT、AXI 参考外设和地址空间。
- [仿真指南](simulation.md)：Profile 选择、镜像、trace 和可选 difftest。
- [验证说明](verification.md)：测试范围、现有结果和未覆盖边界。
- [限制说明](limitations.md)：尚未建立的功能、PPA 和系统级结论。

机器可读的 source lock、Profile 配置、claims、nonclaims 与证据索引位于
`delivery/`、`provenance/` 和 `evidence/`。不同 Profile、commit、binary 或
memory model 的数字不得混合比较。
