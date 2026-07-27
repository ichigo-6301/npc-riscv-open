# 无 SRAM ASIC 实现流程

D7 为三个公开 Profile 提供同一条学术 Nangate45 实现路径：Design Compiler
映射、OpenROAD placement/CTS/route、OpenRCX SPEF 和 PrimeTime post-route
STA。首轮固定为 `register-expanded`：完整 4 KiB cache 被映射为标准单元寄存器，
`macro_count=0`，不使用 OpenRAM/SRAM view，也不裁剪 OoO cache 容量。

这条流程只约束内部寄存器路径。外部 memory、commit、reset 和集成 IO timing
没有虚构的输入/输出 delay，因此结果必须称为“Nangate45 academic
register-expanded implementation/closure point”，不能称为最大频率、SRAM-aware
PPA、OCV/MMMC、DFT、正式 LEC 或 foundry signoff。

## 配置与入口

```text
make rv32im_single_perf_asic_defconfig
make rv32ima_sv32_linux_asic_defconfig
make rv32im_ooo_4k_asic_defconfig
make asic-config-check
make dc-matrix-dry-run
```

实际运行通过 ignored `flows/local/asic/` 配置库与工具。公共入口为：

```text
make dc-matrix
make pnr NPC_ASIC_DC_RUN=<setup-closed-dc-run>
make sta NPC_ASIC_PNR_RUN=<routed-pnr-run>
make asic-evidence-check NPC_ASIC_BUILD_ROOT=<run-root>
```

DC 使用起始频点、最低频率边界和 10 MHz 网格进行 WNS 导航，每个实际执行点仍从
clean elaboration 独立运行。
若当前点仅 setup 失败，则按
`F_est = 1000 / (period_ns - WNS_ns)` 估算可达频率，再按
`F_next = floor(F_est / 10 MHz) * 10 MHz` 生成略低于估算值的新频点；中间更高的旧矩阵
锚点记为 skipped，不再机械执行。一旦有频点闭合，立即
停止向下扫描。若 elaboration、组合环/自动断弧、电气检查或工具证据失败，则停止扫描，
不得用降频掩盖。只有 `WNS>=0`、`TNS=0`、零 setup violation、零组合环/自动断弧、
零电气违反、零 macro 和零 blackbox 的最高实际执行频点可进入后端。P&R 默认频率为
`floor_to_25MHz(0.80 * F_dc_closed)`。
每次矩阵将实际执行点、估算值、跳过点和停止原因写入 `scan_decisions.json`。

例如 Single Profile 在 700 MHz 的 `WNS=-0.396732 ns` 对应
`F_est=547.854 MHz`，因此 600 MHz 应直接跳过并运行 540 MHz。该估算只用于选择
下一次 DC 目标，不是闭合频率声明。

正式 DC 矩阵使用 `max_transition=0.20` 和 `max_fanout=32`；capacitance 使用
Nangate45 Liberty 原生限制，不额外施加全设计 `0.20` 的人为上限。所有 Liberty
capacitance violation仍由独立报告和零违反门禁检查。

当前 IC_EDA 使用 DC O-2018.06-SP1。该版本没有本流程所需的 `report_memory`
接口，因此 summary 中 `inferred_memory_bits=NA` 表示“工具无法直接报告”，不表示推断
memory bits 为零；register-expanded 和 `macro_count=0` 仍需由 elaboration、cell/reference
与 blackbox 检查共同证明。ASIC 专用控制器兼容远端 Python 3.6；公开通用控制面
`flowctl.py` 仍要求 Python 3.8 或更新版本。

Linux 初次扫描使用 RTL 默认 timer clock；进入后端前必须在选定 `F_pnr_mhz` 下重新综合，
显式传入 `NPC_TIMER_CLK_HZ=F_pnr_mhz * 1_000_000`，timebase保持 1 MHz。Linux 源锁是
`d3caf5fe`：它在 E1 `bee5b918` 之上前移 DCache 声明和 trigger-enable localparam，
并仅在 `NPC_ASIC` 下显式展开 CSR reset，以兼容 DC O-2018；生产仿真路径不变。旧
`abf66cad` CoreMark 结果只保留为历史证据。

## OoO A3 对照

公开 main 的 OoO source lock 是 `99fcc2be`。评估分支使用 `94ae2c6f`，并分别运行：

```text
ASIC_OOO_MODE=a3-split-off make dc-matrix
ASIC_OOO_MODE=a3 make dc-matrix
```

完整 A3 固定 `STABLE_ENTRY_IQ=1`、`ROB_INDEXED_SERVICE_LEVEL=1`、
`IQ_SPLIT_PAYLOAD_READ=1`。只有 timing graph 有效，同频最差数据路径改善至少 5%
或最高闭合频点提高至少 50 MHz，同时 TNS/path count不恶化、area/cell增长不超过
5%、CPI/周期/指令/commit trace保持一致时，才允许合并。

三次矩阵完成后使用 `make a3-dc-eval`。比较器以同一 A3 source set 的 split-off
矩阵作为主要实现基准，同时要求候选相对 public legacy 锚点也通过相同门禁；七 workload
的 ideal/default cycle、instruction与commit-trace identity summary是必需输入。任一 timing
graph包含组合环、自动断弧或缺失原生检查时，结果固定为
`A3_DC_INCONCLUSIVE_LOOP`，不得合并。

Tracked 14行 A3 performance CSV先通过
`flows/scripts/build_a3_cpi_identity.py` 转换为带 source commit与输入 SHA256的
bounded JSON。该转换还必须提供原始 A3 evidence manifest、实际使用的私有 OoO
NEMU `.so` 和对应 `.config`；生成结果绑定 Profile、NEMU commit、binary/config
SHA256以及 MMIO skip/resync policy。公开仓库为三个 Profile生成的 bounded NEMU
adapter各自用于本 Profile smoke，不能替代 OoO七 workload reference。
`a3-dc-eval` 不接受手工省略 workload、没有 commit/reference绑定的 CPI结论，或
使用 public bounded adapter生成的 OoO CPI结论。

## 后端交接

OpenROAD 必须通过 `SYNTH_NETLIST_FILES` 读取 DC mapped netlist，`VERILOG_FILES`
为空。runner逐字节验证该网表与 ORFS `1_2_yosys.v` 一致，防止 Yosys/ABC
重新映射。floorplan按 `DC_area * 1.25 / 0.30` 计算并 site-snap，placement density
固定为 0.55。route正常结束后才允许生成 OpenRCX SPEF和 PrimeTime输入。

PrimeTime必须读取同一次 run 的 routed netlist、sanitized routed SDC和SPEF，并断言
实际 clock period等于 `F_pnr`。DC→ORFS、route→RCX、route/RCX→PrimeTime均使用
逐角色 SHA256；任何缺失或不一致都以 `FAIL_HANDOFF_IDENTITY` 停止。

`PNR_RCX_COMPLETED` 只表示 placement/CTS/route、route完整性门禁和 OpenRCX handoff
已经完成。它不表示 setup/hold 闭合；只有独立 PrimeTime summary 的 `sta_closed=true`
才构成该频点的 post-route timing closure。

OpenROAD 非零退出也会保留 `summary.json`，但状态只能是 `PNR_RCX_PARTIAL`；该
summary用于区分可降频重跑的 setup/timing失败与不可伪装为频率问题的 DRC、antenna、
connectivity、hold或交接失败。

原始报告、mapped/routed netlist、SPEF、GDS和库文件只保留在 ignored `build/`。
公开仓库只保留脚本、配置、有限摘要、hash和限制说明。
