# 架构说明

[English](architecture.en.md)

## 设计组织

本仓库采用“一个工程、三个独立 RTL source set”的组织方式。每个 Profile
锁定自己的原生 top、filelist、宏和源 commit；公共 wrapper 只把不同核心的
退休、停止和寄存器观测归一为最多两条 commit packet。共享基础设施不表示
三套微架构可以通过一个参数互相转换。

## Profile 总览

| 特性 | `rv32im_single_perf` | `rv32ima_sv32_linux` | `rv32im_ooo_4k` |
| --- | --- | --- | --- |
| ISA | RV32IM | RV32IMA | RV32IM |
| ABI | ilp32 | ilp32 | ilp32 |
| 特权级 | M | M、S | M |
| 地址转换 | 无 | Sv32；16-entry ITLB + 16-entry DTLB | 无 |
| 执行模型 | 5-stage in-order | 5-stage in-order | out-of-order |
| dispatch / issue / commit | 1 / 1 / 1 | 1 / 1 / 1 | 2 / 2 / 2 |
| 架构/物理寄存器 | 32 / 不适用 | 32 / 不适用 | 32 / 64 |
| ROB / IQ | 不适用 | 不适用 | 8 / 8 |
| 分支恢复 | 流水线 flush | 精确 trap/redirect + 流水线 flush | 2-entry branch checkpoint + tag/generation recovery |
| 分支预测 | 128-entry BTB/PHT | 128-entry BTB + 128-entry BHT | 256-entry correlated conditional predictor、BTB/RAS、target storage |
| 指令侧 | 4 KiB、两路、64 B line I-cache | 4 KiB、两路、64 B line I-cache | 512 × 64-bit、单路 instruction-pair storage，共 4 KiB payload |
| 数据侧 | 4 KiB、两路、64 B line D-cache | 4 KiB、两路、64 B line D-cache | 1024 × 32-bit、单路 physically tagged word cache，共 4 KiB payload |
| 原子扩展 | 无 | LR/SC/AMO，RV32A | 无 |
| timer | 公共 DPI legacy RTC | RTL `AclintTimer`、MTIP 和 CSR time 视图 | 公共 DPI legacy RTC |
| 公共仿真 memory binding | DPI behavioral | DPI behavioral | tagged/pair DPI behavioral |

这里的 cache 容量是数据 payload 容量，不包含 tag、valid、dirty、LRU 或控制
状态。OoO Profile 的两个 4 KiB 结构与顺序核的 64-byte-line cache 组织不同，
不能只按容量名称视为等价结构。

## `rv32im_single_perf`

该 Profile 是五级顺序流水线：

```text
Fetch -> Decode -> Execute -> Memory -> Writeback/Commit
```

- 每周期最多发射和退休一条指令。
- 32 个架构整数寄存器，支持 RV32M 的乘除法路径。
- I/D cache 均为 64 条、每条 64 B、两路组相联，即 32 sets、4 KiB payload。
- 前端使用 128-entry BTB，并为条件分支保存 128 个两位方向计数器。
- 原生 RTL 保留 AXI 端口，但公开 headless 配置选择内部 DPI memory bridge，
  wrapper 将未使用的 AXI 输入固定为静态值。

源身份：`f76de57479b798aca7468f999c386bb4cb5fce02`。

## `rv32ima_sv32_linux`

该 Profile 在五级顺序核心上增加特权、地址转换和系统路径：

```text
Fetch/ITLB -> Decode -> Execute -> Memory/DTLB -> Writeback/Commit
                  \-> trap, CSR and redirect control
```

- 支持 M/S mode、Sv32、RV32A，以及 machine timer interrupt。
- 16-entry ITLB、16-entry DTLB；I/D cache 仍为 4 KiB、两路、64 B line。
- 数据路径启用两项 store buffer、load bypass、hit pipeline 和两周期 fast MUL。
- 分支预测使用 128-entry BTB、128-entry BHT 和 8-bit history 配置；当前
  source-set 没有启用 gshare 宏。
- RTL `AclintTimer` 提供 memory-mapped `mtime/mtimecmp`、MTIP 和 CSR
  `time/timeh` 的时间源。
- OpenSBI、Linux image、DTB 与 NEMU 均为外部输入，不包含在 CPU source set。

源身份：`abf66cad0f9ad02efc8beb641d4005adeaeeae0b`。

该 source snapshot 采用后续的结构化 RTL 布局，将 CSR、frontend、LSU、MMU、
pipeline、statistic 和 top glue 分到独立目录。它是保持 wrapper ABI 和架构
行为边界不变的源码重构；公开仓库仍只编译该 Profile 的独立 filelist。

## `rv32im_ooo_4k`

该 Profile 使用乱序后端，概念数据流为：

```text
FetchDelivery -> Decode -> Rename/Dispatch -> IQ/Issue
              -> Execute/Raw -> Complete/Final -> ROB Commit
```

这些名称表示 ownership 边界，并不保证每个框固定为单周期。核心能力包括：

- 每周期最多双 dispatch、双 issue、双 completion 和双 commit。
- 64-entry PRF、8-entry ROB、8-entry IQ 和两项 branch checkpoint。
- 多个 FU 共用受约束的双宽 issue/complete 通道；“宽度为 2”不表示任意两条
  指令都可以配对。
- ROB tag、generation 和恢复 epoch 用于抑制 flush 后的陈旧 completion。
- 512 项 64-bit instruction-pair storage 服务双指令前端；它是单路、
  pair-oriented 的 tagged storage，不是传统 I-cache。
- 1024 项 32-bit physically tagged word cache 服务数据 hit 路径；它不使用
  64 B cache line 组织。
- correlated conditional predictor、BTB/RAS、两项 checkpoint 和 selective
  recovery 共同处理控制流。
- 公共 wrapper 固定启用 47 项已验收机制，17 项 measurement Oracle 全部关闭。

源身份：`99fcc2be539eabb078c0d73b26a7ef2c00071391`。

## 公共 wrapper ABI

三个 wrapper 都导出：

- lane 0 与 lane 1 的 `valid/pc/instr/nextpc` commit packet；
- halt 原因与位置；
- 架构 PC 和按索引读取的 32 个 GPR。

单发射 Profile 将 lane 1 固定为无效。OoO Profile 保持同周期两条退休指令的
程序顺序。这个 ABI 用于 runner 和可选 difftest adapter，不承诺三套核心的
内部流水信号兼容。

另见 [SoC 集成](soc-integration.md)、[仿真指南](simulation.md)和
[限制说明](limitations.md)。
