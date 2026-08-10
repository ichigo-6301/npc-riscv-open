# OoO 架构与性能演进证据

[English](ooo_architecture_performance_history.en.md)

本页记录 `rv32im_ooo_4k` 的历史架构演进、CoreMark 性能端点和后续组合环整改。
它不把不同 source epoch 拼成同一个实现结果。机器可读来源为
[`ooo_coremark_history.json`](../../evidence/performance/ooo_coremark_history.json)、
[`ooo_loop_remediation.json`](../../evidence/verification/ooo_loop_remediation.json)和
[`source_lineage.json`](../../provenance/upstream/rv32im_ooo_4k/history/source_lineage.json)。

## 从模块原型到双宽弹性流水

OoO 核先以模块和 FSM 原型确定精确状态与年龄语义，再推进至端到端流水：

1. Rename 路径由 RAT/RRAT、FreeList 和 64-entry PRF 组成；8-entry ROB 保持程序
   顺序并提交精确状态，8-entry IQ 按 ROB 年龄选择可发射项。ROB tag、generation
   和 recovery epoch 用于拒绝 flush 后到达的陈旧 completion。
2. 数据通路逐步形成 true IF2、Decode2/Rename2/Dispatch2、Issue2、
   Completion2/WB2 和 Commit2。同周期 slot 0/slot 1 的年龄、RAW/WAW、资源冲突
   和 retained/replay 均由显式契约约束；双退休保持程序顺序。
3. ALU、BRU、LSU 和 MDU 经受约束的双宽 issue/completion 网络接入 ROB。
   Branch checkpoint、generation 和 selective recovery 仅撤销年轻状态；load queue、
   precise store buffer 与 store-to-load forwarding 保持访存和不可逆副作用顺序。
4. S8 将依赖 FSM 的整核控制拆成有 ownership 的弹性阶段；S9 再以生命周期计数、
   lost-slot 分类和 fixed-source A/B 对前端、预测/恢复、dispatch/issue、load/store、
   completion/commit 逐项归因。机制只有在功能、守恒和定向压力门禁通过后才保留。

公开 canonical RTL 的对应阅读入口为：

| 角色 | 代码入口 | 阅读重点 |
| --- | --- | --- |
| Rename / PRF | [`ooo_rename_dispatch_recovery_2w.sv`](../../rtl/profiles/rv32im_ooo_4k/core/ooo_rename_dispatch_recovery_2w.sv)、[`ooo_prf.sv`](../../rtl/profiles/rv32im_ooo_4k/core/ooo_prf.sv) | 双 rename、同周期依赖、free-list 和恢复快照 |
| ROB / IQ | [`small_rob.sv`](../../rtl/profiles/rv32im_ooo_4k/core/small_rob.sv)、[`alu_issue_queue_1w.sv`](../../rtl/profiles/rv32im_ooo_4k/core/alu_issue_queue_1w.sv) | 程序序退休、年龄选择、completion generation 过滤 |
| Issue / completion | [`ooo_issue_operand_elastic_2w.sv`](../../rtl/profiles/rv32im_ooo_4k/execute/ooo_issue_operand_elastic_2w.sv)、[`ooo_pipeline_completion_fabric_2w.sv`](../../rtl/profiles/rv32im_ooo_4k/execute/ooo_pipeline_completion_fabric_2w.sv) | retained/replay、FU 配对与双 completion |
| Recovery / LSU | [`ooo_branch_checkpoint_state_2w.sv`](../../rtl/profiles/rv32im_ooo_4k/core/ooo_branch_checkpoint_state_2w.sv)、[`ooo_lsu_pipeline_1w.sv`](../../rtl/profiles/rv32im_ooo_4k/execute/ooo_lsu_pipeline_1w.sv)、[`ooo_precise_store_buffer_4entry.sv`](../../rtl/profiles/rv32im_ooo_4k/execute/ooo_precise_store_buffer_4entry.sv) | checkpoint/generation、LQ、STLF 和精确 store ownership |

公开 canonical source 仍是 `99fcc2be539eabb078c0d73b26a7ef2c00071391`。
历史代码不复制成第二套 canonical RTL；可逆差分和 source-set 摘要用于从该公开快照
重建并核验 P89 与 D12。P89 是 public S9S 的祖先节点；D12 是独立分叉的历史
快照，不声明两者存在祖先关系：

- [P89 10-file 可逆差分](../../provenance/upstream/rv32im_ooo_4k/history/p89_from_public_s9s.patch)
  与 [P89 source-set SHA256](../../provenance/upstream/rv32im_ooo_4k/history/p89_source_set.sha256)；
- [D12 27-file 可逆差分](../../provenance/upstream/rv32im_ooo_4k/history/d12_from_public_s9s.patch)
  与 [D12 source-set SHA256](../../provenance/upstream/rv32im_ooo_4k/history/d12_source_set.sha256)。

## S9A 到 P89 的 CoreMark 性能端点

<!-- evidence:ooo_coremark_history_public -->
<!-- claim:ooo_historical_s9a_coremark_whole_cpi maturity:partial -->
<!-- claim:ooo_historical_p89_coremark_whole_cpi maturity:verified -->
<!-- claim:ooo_historical_coremark_approx_speedup maturity:partial -->

两次运行均属于历史 performance-first、组合环整改前的 epoch，使用同一
`riscv32e-npc` CoreMark workload family、RV32E/Zicsr ILP32E binary、硬件
`M_EXT=1`、default `IF/LSU/memory=2/3/2`、seed 1 和 difftest。指标是从 reset 后
开始计数到程序结束的 whole-program CPI，不是 timed-region CPI，也不是 ASIC
实现性能。

| 节点 | RTL source | Evidence ref | Cycles / retired instructions | Whole-program CPI | 成熟度 |
| --- | --- | --- | ---: | ---: | --- |
| S9A 性能基线 | `7154e5a3d61fab18718a33f3fe2588891c1b291b` | `d7376dde` | 48,395,814 / 7,824,961 | 6.184799 | `partial` |
| P89 优化端点 | `0e1730b71b7c4ad699e919fc9404189a5e8729d6` | `3a947f18` | 8,590,215 / 7,824,973 | 1.097795 | `historical_verified` |

同 workload family 的 CPI 比值对应同频执行效率约 `5.6338x`，简写为
`6.18 -> 1.10（约 5.63x）`。
它保持 `partial`，原因有两个：S9A 原始 binary hash 未保留；两端退休指令相差 12
条。因此这不是 hash-identical binary A/B，不能升级为当前 source 的严格性能 claim。
P89 端点本身保留了 binary/config hash、计数和 source identity，故端点可标为
`historical_verified`。配置中启用的 measurement Oracle 只生成观测量，不驱动生产
ready/valid、仲裁或状态更新。

S9A 计数来自 `d7376dde:npc/docs/perf/s9a_pipeline_performance_baseline.md`；
P89 的验收状态、manifest 和 summary 由 `3a947f18` 固定。公开 JSON 只保留脱敏
logical path、identity 和 hash，不发布原始私有日志。

这段下降不是一次参数调整。S9A 的计数器首先暴露前端断供和分支恢复成本，随后按
固定输入逐步保留持续取指、BTB/BHT/RAS、同周期依赖旁路和 dispatch/issue 路径；
再针对 load/store transaction ownership、completion/wakeup 与双退休空槽继续归因。
P89 最终增加受保护的第三项 tagged load transaction owner，保持 store admission、
AMO exclusion、tag/generation/recovery-epoch 匹配和响应反压契约。

## D12 的寄存化 ownership 整改

<!-- evidence:ooo_loop_remediation_public -->
<!-- claim:ooo_historical_comb_loop_zero maturity:verified -->
<!-- claim:ooo_historical_unoptflat_zero maturity:verified -->
<!-- claim:ooo_historical_pre_techmap_scc_zero maturity:verified -->
<!-- claim:ooo_historical_post_techmap_scc_zero maturity:verified -->
<!-- claim:ooo_historical_precise_retirement_preserved maturity:verified -->

performance-first RTL 的仿真 PASS 只证明时序仿真下的架构行为，不证明组合依赖图
无环。D12 在另一个 source epoch `a8f689cc00213859fb6893b31b65ef5cb3cbd7eb`
中，以 typed registered ownership 重构 Issue/WB/Commit 与 LSU 边界：

- typed ROB outcome 与 retire owner 固化指令类别和退休决定；
- depth-3 memory request/response owner 使已接收事务持久化，并按 token 排空被取消读；
- typed completion owner 与寄存化双宽 service arbiter 隔离 FU 许可和下游 ready；
- persistent recovery token 将恢复、RAS preview 和不可逆副作用从实时反压中分离。

该快照在身份匹配的结构门禁中得到 SpyGlass CombLoop `0`、Verilator UNOPTFLAT
`0`、Yosys pre/post-techmap SCC `0/0`；定向与集成检查保持精确退休，协议、生命周期
和守恒错误为 `0`。这些结果是 `historical_verified` 的结构证据，不继承 P89 的
`1.097795` CPI，也不代表公开 canonical source 的当前复跑。

## Claim 边界与非声明项

- 本证据支持：历史同族 CoreMark whole-program CPI 约
  `6.18 -> 1.10（约 5.63x）`，comparison 为 `partial`，P89 端点为
  `historical_verified`。
- 本证据支持：另一个 D12 source epoch 完成 Issue/WB/Commit/LSU 寄存化
  ownership 重构，三个结构门禁均为零并保持精确退休。
- 不可写：把 P89 CPI 称为当前无环 RTL、公开 canonical source、FPGA 或 ASIC 性能。
- 不可写：D12 或当前 OoO 的 DC 固定频点、面积、P&R、STA、Fmax、功耗或 signoff；
  本证据未给出这些结论。

前端空泡和分支重定向的独立历史指标见
[历史架构与性能优化证据](performance_history.md)。
