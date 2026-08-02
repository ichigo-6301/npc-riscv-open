# 历史架构与性能优化证据

[English](performance_history.en.md)

本页记录可审计的历史优化节点，不把旧结果重标为当前 source lock 的性能。
机器可读来源为
[`linux_coremark_ab.json`](../../evidence/performance/linux_coremark_ab.json)和
[`ooo_frontend_branch_ab.json`](../../evidence/performance/ooo_frontend_branch_ab.json)。

## Linux/Sv32 CoreMark 演进

<!-- evidence:linux_coremark_history_public -->
<!-- claim:linux_historical_no_tlb_whole_cpi maturity:partial -->
<!-- claim:linux_historical_optimized_whole_cpi maturity:verified -->
<!-- claim:linux_historical_approx_speedup maturity:partial -->

| 节点 | Source | Cycles / retired instructions | Whole-program CPI | 状态 |
| --- | --- | ---: | ---: | --- |
| Sv32 no-TLB | `4a4cbf5d` | 27,929,341 / 3,252,477 | 8.587098694 | `partial`：配置与计数已锁定，baseline binary hash 缺失 |
| 优化节点 | `abf66cad` | 5,613,603 / 3,252,481 | 1.725944902 | `verified` historical result |

同一 benchmark family 下的 whole-program CPI 比值为
`8.587098694 / 1.725944902 = 4.975302910`，简写为约 `4.98x`。该值保持
`partial`：两次运行相差 4 条退休指令，且基线 binary hash 未保留，因此不是
严格 hash-identical A/B。优化节点包含 16-entry ITLB/DTLB、2-entry Store
Buffer、Fast MUL、跨级旁路和 load-hit 路径。当前 `0fc3de40` 尚未按同一输入复跑。

## OoO 前端与分支预测

<!-- evidence:ooo_historical_optimization_public -->
<!-- claim:ooo_historical_frontend_empty_baseline_percent maturity:verified -->
<!-- claim:ooo_historical_frontend_empty_s9b_percent maturity:verified -->
<!-- claim:ooo_historical_redirect_direct_jal_percent maturity:verified -->
<!-- claim:ooo_historical_redirect_btfnt_percent maturity:verified -->
<!-- claim:ooo_historical_redirect_btb_bht_percent maturity:verified -->
<!-- claim:ooo_historical_redirect_jalr_ras_percent maturity:verified -->
<!-- nonclaim:ooo_historical_ab_not_current_no_loop -->

历史 seven-workload default-profile 仿真中，S9B 通过多请求取指、epoch-tagged
有序响应和流水化 pair-fetch service，将 frontend-empty lost slots 从
`53.76%` 降至 `23.29%`；分母固定为 total dispatch slots。

| 分支阶段 | Source | Redirects / control completions |
| --- | --- | ---: |
| Direct JAL | `62d40850` | 59.38% |
| BTFNT | `a247ac43` | 24.84% |
| 64-entry tagged BTB/BHT | `712b3633` | 22.66% |
| 64-entry indirect BTB + 8-entry RAS | `87a0bbc4` | 17.73% |

这些数据全部属于组合环整改前的历史仿真纪元。它们证明相应机制在当时固定套件
中的方向性收益，但不代表当前无环 RTL 的性能，也不是 FPGA、ASIC 或 silicon
结果。当前 OoO CoreMark 仍为 provisional，后端仍为 planned。

## 简历使用边界

- Linux 可写“约 8.59→1.73、同频约 4.98x”，同时保留 approximate/partial 边界。
- OoO 可写“历史仿真中前端空泡率 53.76%→23.29%、控制重定向率
  59.38%→17.73%”，并说明随后进行了组合环和 causal ownership 重构。
- 不把历史百分比与当前 provisional CoreMark CPI、ASIC 频率或面积混合。
