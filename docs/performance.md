# 性能与实现数据

[English](performance.en.md)

本页借鉴处理器项目常用的 Profile 对比形式，但严格区分仿真 CPI、
CoreMark/MHz、综合频率和面积。不同指标不能相互推导，也不能跨 Profile、
commit、binary 或 memory model 合并。

## 证据状态

- `verified`：本仓库的固定输入和配置可复现，并有公开 evidence ID。
- `provisional`：来自固定私有 commit 的历史记录，但尚未由当前公开流程独立
  复现全部输入和条件。
- `not_claimed`：当前明确不作结论。
- `—`：尚无满足对应栏位要求的数据。

## 当前公开复现

| Profile | CoreMark CPI | CoreMark/MHz | 七 workload weighted CPI | 闭合频率 | 面积 |
| --- | ---: | ---: | ---: | ---: | ---: |
| `rv32im_single_perf` | — | — | — | — | — |
| `rv32ima_sv32_linux` | — | — | — | — | — |
| `rv32im_ooo_4k` | — | — | — | — | — |

仓库内 bounded smoke 的周期数用于验证 wrapper 和运行时，不是 CoreMark 或
PPA 数据，因此不会填入此表。

## 历史 CoreMark CPI 参考

以下数据均为 `provisional`，不是当前公开 verified claim：

| Profile | Cycles | Retired/committed instructions | CoreMark CPI | 条件摘要 | Evidence / nonclaim |
| --- | ---: | ---: | ---: | --- | --- |
| `rv32im_single_perf` | 4,578,012 | 3,081,085 | 1.48 | RV32IM 单发射，项目内 Verilator/NEMU 记录；公开流程尚未复现 binary hash 和完整配置 | `single_public_cpi_not_yet_claimed` |
| `rv32ima_sv32_linux` | — | — | ≈1.72 | 后续优化的 Linux/System source snapshot `abf66cad`；S-mode Sv32、ITLB/DTLB、hit pipeline、2-entry store buffer、fast MUL、DCache load-hit 优化和 bridge-aware LSU load bypass；近似私有记录 | `linux_public_cpi_not_yet_claimed` |
| `rv32im_ooo_4k` | 2,718,684 | 3,081,080 | 0.882380204 | RV32IM，IF/LSU/memory=`2/3/2`，seed 1，Verilator + NEMU difftest | `ooo_coremark_cpi_not_yet_claimed` |

CoreMark CPI 是 `cycles / retired instructions`。它不是 CoreMark/MHz，不能在
缺少 CoreMark score、迭代数、编译选项和时钟实现数据时换算为后者。

### Linux Profile checkpoint 对照

公开 Profile 当前锁定后续优化 checkpoint `abf66cad0f9ad02efc8beb641d4005adeaeeae0b`，
因此历史主表使用约 `1.72`。较早的 `e3a1cc91c4c00040f7180eec5e385326d9964893`
约 `1.98` 仍保留为前一 checkpoint 对照；两者不是同一份 RTL，不能把旧数字
当作当前 source 的结果。

| Checkpoint | Source commit | Sv32 CoreMark CPI | 状态 |
| --- | --- | ---: | --- |
| 后续优化 checkpoint | `abf66cad0f9ad02efc8beb641d4005adeaeeae0b` | ≈1.72 | `linux_public_cpi_not_yet_claimed` |
| 前一冻结 checkpoint | `e3a1cc91c4c00040f7180eec5e385326d9964893` | ≈1.98 | `linux_prior_checkpoint_cpi_not_claimed` |

两行都属于 `provisional` 历史仿真记录，没有公开 binary hash、完整固定运行
摘要或独立 fresh-clone CoreMark 复现，因此不升级为 verified claim。CoreMark/MHz、
实现频率和面积继续保持 `—`/`not_claimed`。

## 历史多 workload 参考

| Profile | Workloads | Total cycles | Total retired instructions | Weighted CPI | Evidence / nonclaim |
| --- | --- | ---: | ---: | ---: | --- |
| `rv32im_ooo_4k` | CoreMark、matrix-mul、crc32、quick-sort、load-store、Dhrystone、microbench | 5,157,299 | 5,649,752 | 0.912836351 | `ooo_public_cpi_not_yet_claimed` |

该 weighted CPI 使用总周期除以总退休指令，仅描述这一组有限 workload。
其中 CoreMark CPI 是 `0.882380204`（`ooo_coremark_cpi_not_yet_claimed`），不能用
weighted CPI 替代；它也不表示所有程序 CPI 都小于 1。

## 历史综合参考

| Profile | Tool / target | Setup result | 频率描述 | Cell area | 状态与限制 |
| --- | --- | --- | --- | ---: | --- |
| `rv32im_single_perf` | Design Compiler，1.000 ns stress，Nangate45-family library setup | WNS ≈ -0.42 ns，TNS ≈ -4606.87 ns | 算术推算约 704 MHz；1 GHz 未闭合 | 184926.124968 library units | `provisional`; `single_700mhz_closure_not_claimed`; `single_dc_area_not_claimed` |
| `rv32ima_sv32_linux` | — | — | — | — | `not_claimed` |
| `rv32im_ooo_4k` | — | — | — | — | `not_claimed` |

约 704 MHz 来自 `1 / (1.000 ns + 0.42 ns)` 的历史估算（`single_700mhz_closure_not_claimed`），
不是闭合的最大频率。area 是该 DC run 的 library cell-area 数值
（`single_dc_area_not_claimed`），没有公开的 P&R、布线后寄生参数、SRAM signoff、
功耗、IO、OCV/MMMC 或硅后相关性。它也不能与另一个 memory binding 或工具设置的
面积直接比较。

## 后续填表条件

新增数据前必须记录：

1. Profile ID、source commit 和配置 hash；
2. benchmark binary/ELF hash、编译选项和退休指令定义；
3. simulator、reference model、latency、seed 和 trace/difftest 状态；
4. 对频率与面积记录技术库、PVT、memory binding、约束、WNS/TNS 和工具版本；
5. 可读的公开 evidence ID 与 fresh-clone 复现命令。

未满足这些条件的栏位继续保持 `—`。另见[证据规则](../evidence/README.md)
和[限制说明](limitations.md)。
