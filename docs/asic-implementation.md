# 双内存 ASIC 实现流程

[English](asic-implementation.en.md)

D7 为三个公开 Profile 提供同一条学术 Nangate45 实现路径：Design Compiler
映射、OpenROAD placement/CTS/route、OpenRCX SPEF 和 PrimeTime post-route
STA。`register-expanded` 模式将完整 4 KiB cache 映射为标准单元寄存器，
`macro_count=0`。D8 另为 Single 和 Linux Profile 提供四个 OpenRAM 宏的
`sram` 模式；OoO SRAM 仍因同步读 retiming 未完成而禁止。两种模式都不裁剪 cache 容量。

这条流程只约束内部寄存器路径。外部 memory、commit、reset 和集成 IO timing
没有虚构的输入/输出 delay。register 结果只能称为“Nangate45 academic
register-expanded implementation/closure point”；SRAM 结果必须同时披露 analytical
FreePDK45/OpenRAM 与 Nangate45 PVT 不一致。两者都不能称为最大频率、OCV/MMMC、
DFT、正式 LEC 或 foundry signoff。

## 配置与入口

```text
make rv32im_single_perf_asic_defconfig
make rv32im_single_perf_sram_asic_defconfig
make rv32ima_sv32_linux_asic_defconfig
make rv32ima_sv32_linux_sram_asic_defconfig
make rv32im_ooo_4k_asic_defconfig
make asic-config-check
make lc-macros-dry-run
make dc-matrix-dry-run
make pnr-dry-run NPC_ASIC_DC_RUN=<setup-closed-dc-run>
make sta-dry-run NPC_ASIC_PNR_RUN=<routed-pnr-run>
```

实际运行通过 ignored `flows/local/asic/` 配置库与工具。公共入口为：

```text
NPC_ASIC_LC_OUTPUT=build/asic/lc/20260729T120000Z make lc-macros
# Single 或 Linux 初始探索扫描
make dc-matrix
# Linux 当前 200 MHz 固定后端点的最终 DC handoff
ASIC_DC_ARGS="--timer-clock-hz 200000000" make dc-matrix
make pnr NPC_ASIC_DC_RUN=<setup-closed-dc-run>
make sta NPC_ASIC_PNR_RUN=<routed-pnr-run>
make asic-evidence-check NPC_ASIC_BUILD_ROOT=<run-root>
make implementation-check
```

`lc-macros` 只适用于 SRAM 配置，并要求调用者提供一个包含 UTC timestamp、尚不存在的
唯一输出目录；runner 拒绝覆盖已有 Library Compiler 结果。`lc-macros-dry-run` 在 SRAM
模式使用 ignored placeholder，在 register 模式明确返回 `not applicable`，且都不启动
`lc_shell`。所有真实 LC/DC/OpenROAD/PT 阶段都必须使用现有 heavy-stage lock 串行运行；
公开 CI 只检查合同和 dry-run。

DC 使用起始频点、最低频率边界和 10 MHz 网格进行 WNS 导航，每个实际执行点仍从
clean elaboration 独立运行。
若当前点仅 setup 失败，则按
`F_est = 1000 / (period_ns - WNS_ns)` 估算可达频率，再按
`F_next = floor(F_est / 10 MHz) * 10 MHz` 生成略低于估算值的新频点；中间更高的旧矩阵
锚点记为 skipped，不再机械执行。一旦有频点闭合，立即
停止向下扫描。若 elaboration、组合环/自动断弧、电气检查或工具证据失败，则停止扫描，
不得用降频掩盖。只有 `WNS>=0`、`TNS=0`、零 setup violation、零组合环/自动断弧、
零电气违反、预期 macro 数和零 blackbox 的最高实际执行频点可进入后端。Single registers、
Single SRAM、Linux registers 和 Linux SRAM 的 tracked P&R 默认值分别是已审计固定点
425、475、200 和 200 MHz；这些值优先于比例估算。只有 Profile/memory mode 没有 tracked
固定点且调用者也没有传入 `--frequency-mhz` 时，才回退到
`floor_to_25MHz(0.80 * F_dc_closed)`。该回退值不是新的 closure claim。
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

Linux 初次扫描可以使用 RTL 默认 timer clock；进入后端前必须在选定 `F_pnr_mhz` 下重新综合，
通过 `ASIC_DC_ARGS="--timer-clock-hz <F_pnr_mhz * 1000000>"` 显式传参；runner 随后定义
`NPC_TIMER_CLK_HZ`，timebase 保持 1 MHz。当前两条 Linux 路线的已审计固定点都是 200 MHz，
因此实际最终 DC 命令必须使用
`ASIC_DC_ARGS="--timer-clock-hz 200000000" make dc-matrix`。Linux dry-run 未传该参数时会
打印这条最终 handoff 要求，不会把使用 RTL 默认 timer 的探索扫描误称为后端输入。Linux 源锁是
`0fc3de40`：它在 E1 `bee5b918` 之上前移 DCache、trigger-enable、store-buffer
drain-valid、DTLB translated-address、memory-response 和顶层 control 声明，仅在
`NPC_ASIC` 下显式展开 CSR reset，并为 non-DPI statistic net 补全声明位宽，以兼容
DC O-2018；生产仿真路径不变。旧
`abf66cad` CoreMark 结果只保留为历史证据。

Linux SRAM 模式不覆盖上述生产 RTL。ASIC-only XPM compatibility leaf 仅在参数精确为
512x32 时，将两个 I-cache way 和两个 D-cache way绑定到已审计 OpenRAM 宏；任何其他
SRAM-mode XPM组织通过 unresolved sentinel fail closed。进入 DC 前必须通过 register
reference、OpenRAM model 和 XPM leaf 的逐拍 miter。

## 已审计结果

Single/Linux 的 register-expanded 与 SRAM-macro 四条路径已经通过 D11
source/config/tool/library identity 审计，不需要为发布重复执行 P&R/PT。固定频率、
area、setup/hold、route checks、same-run artifact hash 和分层成熟度见
[后端证据](evidence/backend_closure.md)。OoO 两种 memory mode 的后端仍是
`planned`，本页脚本存在不代表其综合或物理实现已经完成。

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
DC在写入 `run.ok` 前先生成独立 output manifest，冻结 mapped netlist/SDC、完整
source/config identity、compile recipe、macro/blackbox数量和标准单元库 identity；
P&R与postprocess recovery均在创建新输出前验证该记录。

`PNR_RCX_COMPLETED` 只表示 placement/CTS/route、route完整性门禁和 OpenRCX handoff
已经完成。它不表示 setup/hold 闭合；只有独立 PrimeTime summary 的 `sta_closed=true`
才构成该频点的 post-route timing closure。`timing_closed`/`sta_closed`与
`electrical_clean`分别记录：max-capacitance、max-fanout等例外保持可见，但不被
错误解释为 setup/hold 频率失败。

OpenROAD 非零退出也会保留 `summary.json`，但状态只能是 `PNR_RCX_PARTIAL`；该
summary用于区分可降频重跑的 setup/timing失败与不可伪装为频率问题的 DRC、antenna、
connectivity、hold或交接失败。

原始报告、mapped/routed netlist、SPEF、GDS和库文件只保留在 ignored `build/`。
公开仓库只保留脚本、配置、有限摘要、hash和限制说明。
