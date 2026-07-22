# 验证说明

[English](verification.en.md)

验证结果按 Profile、source commit、image hash 和运行配置隔离。进程返回 0
不是充分条件；测试还必须看到预期 PASS marker、good trap/stop 条件、正确
指令计数和零协议错误。

## 验证层次

| 层次 | 目标 | 当前状态 |
| --- | --- | --- |
| 配置与 source closure | defconfig、manifest、filelist、define 和源 hash 一致 | `verified` |
| 静态检查 | 三个 Profile 的 Verilator lint/elaboration | `verified` |
| Bounded smoke/regression | 仓库内固定小程序在纯 Verilator runtime 上通过 | `verified` |
| 本地 NEMU difftest | Profile 匹配的 PC/instruction/GPR commit check | bounded PASS；总体 `partial` |
| 完整 OpenSBI/Linux | firmware、Sv32 page table、interrupt 和设备路径 | `not_claimed` |
| 性能 benchmark | 固定外部 CoreMark/多 workload 的公开复现 | `provisional` |
| ASIC/PPA | synthesis、P&R、STA、power、signoff | `not_claimed` |

没有功能覆盖率数据库；`coverage_status` 为 `not_available`。测试条目数量不能
解释为覆盖率百分比。

## 标准门禁

每个 Profile 执行：

```sh
make <profile>_defconfig
make showconfig
make config-check source-check docs-check public-hygiene
make verify-checksums
make verilator-lint
make smoke
make regression
```

公共 runtime 的 Python 单元测试还检查配置选择、runner 命令、错误输入和
Profile ABI。构建后 Git 状态只允许被正确忽略的 `.config`、`build/` 与
`flows/local/` 输出。

## Bounded 测试内容

| Profile | 固定 image | 显式覆盖范围 |
| --- | --- | --- |
| `rv32im_single_perf` | `smoke.hex` | RV32IM、x16-x31、RAW/WAW、branch、load/store、MUL/DIV、trap |
| `rv32ima_sv32_linux` | `smoke.hex` | RV32IM、upper GPR、RAW/WAW、branch、load/store、MUL/DIV、trap |
| `rv32ima_sv32_linux` | `arch_smoke.hex` | RV32IMA、LR/SC、machine CSR、trap |
| `rv32im_ooo_4k` | `smoke.hex` | RV32IM、upper GPR、RAW/WAW、branch、load/store、MUL/DIV、recovery、双退休观测、trap |

Linux Profile 的 `arch_smoke.hex` 是 machine-mode bounded test。它没有覆盖
完整 S-mode trap delegation、Sv32 translated fetch/load/store、page fault、
OpenSBI 启动或 Linux kernel。

## 已记录的 deterministic 结果

| Profile / image | Cycles | Commit packets | 结果 |
| --- | ---: | ---: | --- |
| `rv32im_single_perf/smoke.hex` | 269 | 27 | `PUBLIC_SIM_PASS` |
| `rv32ima_sv32_linux/smoke.hex` | 162 | 27 | `PUBLIC_SIM_PASS` |
| `rv32ima_sv32_linux/arch_smoke.hex` | 80 | 15 | `PUBLIC_SIM_PASS` |
| `rv32im_ooo_4k/smoke.hex` | 107 | 26（lane0 21 + lane1 5） | `PUBLIC_SIM_PASS` |

这些周期数只确认 source set、wrapper、DPI transport 和 runner 的确定性。
它们不是 CoreMark、Linux boot、CPI、频率或面积结果。

## 本地 strict difftest

使用 manifest 锁定的三个 NEMU source tree 和被 Git 忽略的本地 adapter，
上述四个 bounded image 均在相同周期/commit 结果下通过。adapter 检查：

- Profile ID、ABI、image 和 reset vector；
- 每条 commit 的 PC、instruction 和 next PC；
- 32 个架构 GPR；
- OoO 同周期两条 commit 的顺序和最终架构状态。

OoO debug shadow 对尚未写过的 GPR 使用索引 sentinel；adapter 只忽略未触碰
sentinel，所有 committed register write 仍需一致。单发射 Profile 的 GPR
复位为零并逐项比较。

该结果仍标为 `partial`，因为 NEMU source/`.so` 是外部本地产物，且当前 ABI
不比较 device、timer tick、interrupt timing 或任意 MMIO side effect。

## Fresh-clone 要求

在原生 Linux 临时目录对目标 commit 执行：

1. `verify-checksums`、`docs-check`、source closure 和 hygiene；
2. 三 Profile lint、smoke 与 regression；
3. 若提供本地 NEMU，运行 bounded difftest；
4. 检查所有 source-set SHA256；
5. 确认运行后的 Git worktree 保持 clean。

任一 image/config hash 漂移、固定测试周期或指令数变化、不可解释的协议错误
或重复运行不一致，都必须保留失败证据并停止性能/PPA 结论。

另见[仿真指南](simulation.md)、[性能与实现数据](performance.md)和
[限制说明](limitations.md)。
