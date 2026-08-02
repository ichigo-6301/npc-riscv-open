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
| OpenSBI/Linux 系统启动 | DTB、M→S、Linux 6.6.141、`/init`、initramfs shell | `e3a1cc91` 历史快照 `verified`；当前 `0fc3de40` 未深跑复验 |
| XC7Z100 FPGA | synthesis、routed implementation、timing、bitstream、板级观测、workload | 三个历史快照分层记录；当前 `f76de574` 上板 `not_claimed` |
| 性能 benchmark | hash-locked CoreMark marker 计量与 difftest | Single 当前 source lock `verified`；Linux `abf66cad` 历史证据；OoO `provisional` |
| ASIC implementation | DC、P&R、OpenRCX、internal PrimeTime | Single/Linux 四条 fixed point `verified`；OoO `planned` |
| Electrical / signoff | IO、electrical、macro signoff、OCV/MMMC、power、silicon | `partial` / `not_claimed` |

没有功能覆盖率数据库；`coverage_status` 为 `not_available`。测试条目数量不能
解释为覆盖率百分比。

## 标准门禁

每个 Profile 执行：

```sh
make <profile>_defconfig
make showconfig
make config-check source-check docs-check evidence-check showcase-check public-hygiene
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
OpenSBI 启动或 Linux kernel；这描述的是当前公开 bounded image 的覆盖范围，
不否定 `e3a1cc91` 历史快照已经记录的完整启动链。

`make opensbi-smoke` 提供显式外部固件入口，但公开仓库未锁定 DTB、参考模型
或 shutdown 终止协议，因此该入口本身不构成一次已验证的 OpenSBI 执行 claim。

## 历史系统与 FPGA 快照

Linux 历史日志在 `e3a1cc91` 记录了 DTB 载入、OpenSBI、M→S 交接、Linux
`6.6.141`、`/init` 与 initramfs shell marker。原始日志不公开，只发布 hash 和
bounded marker 摘要；当前 ASIC source lock `0fc3de40` 尚未重新执行约一小时的
完整启动，因此不得把该结论改写为 current-source verification。

Single 的 XC7Z100 证据按八个成熟度维度拆分。2026-05-07 原始五级核具备
200 MHz routed timing、bitstream 与 UART/ILA 板级观测，但板级镜像绑定为
`partial`；2026-05-12 forwarding 和 2026-05-15 forwarding+BTB/PHT 快照只验证
200 MHz synthesis/implementation/timing。后两目录中的 XSA 是 5 月 7 日旧文件，
不能升级其 bitstream 或板级状态。详见[系统与 FPGA 历史证据](evidence/system_fpga_history.md)。

## 已记录的 deterministic 结果

| Profile / image | Cycles | Commit packets | 结果 |
| --- | ---: | ---: | --- |
| `rv32im_single_perf/smoke.hex` | 269 | 27 | `PUBLIC_SIM_PASS` |
| `rv32ima_sv32_linux/smoke.hex` | 150 | 27 | `PUBLIC_SIM_PASS` |
| `rv32ima_sv32_linux/arch_smoke.hex` | 77 | 15 | `PUBLIC_SIM_PASS` |
| `rv32im_ooo_4k/smoke.hex` | 107 | 26（lane0 21 + lane1 5） | `PUBLIC_SIM_PASS` |

这些周期数只确认 source set、wrapper、DPI transport 和 runner 的确定性。
它们不是 CoreMark、Linux boot、CPI、频率或面积结果。

## Hash-locked CoreMark 结果

公开 runner 会在结束时输出 `PUBLIC_SIM_PASS cycles=... commit=... commit2=...`。
证据绑定的三个 source ref 均记录了 CoreMark self-check、start/stop marker 闭合、
good trap 和 watchdog。公开 runtime 已提供 deterministic AXI Timer/UARTLite。
Single 在当前 source lock 上通过 Profile 匹配的 NEMU difftest，因此其 timed CPI、
whole CPI 和 CoreMark/MHz 标为 `verified`。Linux 数值仅在 `abf66cad` 上为
`historical_verified`；当前 `0fc3de40` source lock 尚待相同 binary/config 的精确复测。
OoO self-check 和计数通过，但双退休 MMIO packet 无法使用单退休 skip-and-sync 而不引入
顺序歧义，因此保持 `provisional`。精确 binary/config hash、计数分区和协议边界见
[CoreMark 计量证据](evidence/coremark_reproduction.md)。

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
不比较 device cycle-exact 状态、timer tick、interrupt timing 或任意 MMIO side
effect。Single/Linux CoreMark 仅对精确匹配的已知 Timer/UART MMIO 使用
deterministic skip-and-sync；未知地址和副作用直接失败。

## 后端证据门禁

Single/Linux 的 register-expanded 与 SRAM-macro 流程分别锁定 DC、P&R 和 PT
period。四条路线必须同时满足：DC link 正常、无 combinational loop/automatic
arc break/latch/unclocked endpoint、macro/blackbox 数符合配置；placement、CTS、
detail route、GDS 与 OpenRCX 报告完整；mapped/routed netlist、routed SDC、SPEF 和
Liberty/DB 的角色 hash 一致；PrimeTime 内部 setup/hold TNS 与 violating path 为
0。公开 checker 会从 bounded JSON 复核这些字段，而不是读取或分发 raw artifacts。

SRAM 的 P&R 与内部 extracted timing 可以是 `verified`，同时 macro model 为
`partial_analytical_characterization`、macro physical signoff 为 `not_closed`，
overall profile 仍为 `partial`。详细 scope 见
[后端证据](evidence/backend_closure.md)。

## Fresh-clone 要求

在原生 Linux 临时目录对目标 commit 执行：

1. `verify-checksums`、`docs-check`、`evidence-check`、`showcase-check`、
   source closure 和 hygiene；
2. 三 Profile lint、smoke 与 regression；
3. 若提供本地 NEMU，运行 bounded difftest；若同时提供 hash-locked CoreMark
   输入，运行 Single/Linux `coremark-difftest` 和 OoO `coremark`；
4. 对四个 Single/Linux ASIC defconfig 运行 config-check 与 LC/DC/P&R/PT
   dry-run，不启动商业 EDA；
5. 检查所有 source-set SHA256；
6. 确认运行后的 Git worktree 保持 clean。

任一 image/config hash 漂移、固定测试周期或指令数变化、不可解释的协议错误
或重复运行不一致，都必须保留失败证据并停止性能/PPA 结论。

另见[仿真指南](simulation.md)、[性能与实现数据](performance.md)和
[限制说明](limitations.md)。
