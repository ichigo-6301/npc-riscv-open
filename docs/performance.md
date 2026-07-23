# 性能与实现数据

[English](performance.en.md)

本页把 CoreMark 定时区间、完整程序 CPI、CoreMark/MHz、有限 workload 聚合和
物理实现指标分开。所有当前数字来自
[`evidence/performance/coremark.json`](../evidence/performance/coremark.json)；
`make performance-check` 会校验公式、输入 hash、claim 和中英文页面的一致性。

## 指标定义

```text
timed CPI       = stop_commit_cycle - start_commit_cycle
                  ---------------------------------------
                  stop_commit_ordinal - start_commit_ordinal

whole CPI       = reset-to-ebreak cycles / retired instructions

CoreMark/MHz    = iterations * 1,000,000 / timed cycles  # evidence:coremark_public_current
```

本轮固定 `ITERATIONS=10`、单 context。CoreMark/MHz 是每百万仿真周期完成的
iteration 数；它不是 host 输出的 `Marks`，也不是有真实工作频率后的绝对
CoreMark score。后者目前为 `—`。

## 当前 CoreMark 结果

| Profile | Timed cycles / instructions | Timed CPI | CoreMark/MHz | Whole cycles / instructions | Whole CPI | 状态 |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `rv32im_single_perf` | 4,542,529 / 3,059,106 | 1.484920431 | 2.201416876 | 4,578,065 / 3,081,085 | 1.485861312 | `verified`，difftest PASS；`evidence:coremark_public_current` |
| `rv32ima_sv32_linux` | 5,278,164 / 3,059,140 | 1.725375105 | 1.894598197 | 5,613,603 / 3,252,481 | 1.725944902 | `verified`，difftest PASS；`evidence:coremark_public_current` |
| `rv32im_ooo_4k` | 2,691,933 / 3,059,106 | 0.879973757 | 3.714802709 | 2,718,727 / 3,081,116 | 0.882383851 | `provisional`，self-check PASS、双退休 MMIO difftest 歧义；`evidence:coremark_public_current` / `nonclaim:ooo_public_coremark_runtime_provisional` |

Single/OoO 使用同一 hash-locked M-mode binary，Linux 使用 hash-locked Sv32
S-mode binary。三行均完成 CoreMark self-check、marker 闭合、good trap 和
watchdog；Single/Linux 还通过 Profile 匹配的 NEMU difftest。OoO 没有把歧义
的双退休 MMIO packet 强行 skip，因此仍是 provisional。

| Profile | Binary SHA256 | Config SHA256 | IF/LSU/memory latency | Evidence |
| --- | --- | --- | --- | --- |
| `rv32im_single_perf` | `601f942b5a32d071dd0170425107875fdc287bb86549c6489622656ea7ff1742` | `f397f1899ed896023c81f2a16e9eb9523eb2599a5539b923c7132ae69881528e` | `2/2/2` | `evidence:coremark_public_current` |
| `rv32ima_sv32_linux` | `50840465ecda9da48a69a4361b1a479c42428b5331b114dc694658c6928be6c5` | `82a3448b6c29355e3249a1123f9f15f51b60b02a327a8f2950f000093eb169ea` | `0/0/0` | `evidence:coremark_public_current` |
| `rv32im_ooo_4k` | `601f942b5a32d071dd0170425107875fdc287bb86549c6489622656ea7ff1742` | `b72d4c86e1c7e12bc110d15d298748942b08f8502c7563b491f187f1397ae24f` | `2/3/2` | `evidence:coremark_public_current` |

## Linux 私有/公开同步

公开 Profile 与私有历史都锁定 RTL commit
`abf66cad0f9ad02efc8beb641d4005adeaeeae0b`，并统一
`NPC_DCACHE_WRITE_ALLOCATE=0`。同一 canonical Sv32 binary 在两套 harness 中的
CoreMark marker 区间完全一致：

| Harness | Pre cycles / instructions | Timed cycles / instructions | Post cycles / instructions | Whole cycles / instructions | Evidence |
| --- | ---: | ---: | ---: | ---: | --- |
| 私有 NPC + measurement-only observer | 313,889 / 184,284 | 5,278,164 / 3,059,140 | 21,426 / 9,025 | 5,613,479 / 3,252,449 | `evidence:coremark_public_current` |
| 公开 headless runtime | 313,878 / 184,284 | 5,278,164 / 3,059,140 | 21,561 / 9,057 | 5,613,603 / 3,252,481 | `evidence:coremark_public_current` |

两边 timed CPI 都是 1.725375105（`evidence:coremark_public_current`）。Whole-program
差异由旧 harness 的 reset/计数索引和结束 UART/terminal 边界解释，不是 RTL 或
CoreMark 主循环差异。因此当前公开 Linux 数字已经与性能较好的 checkpoint 同步。

### WRITE_ALLOCATE 诊断

| 设置 | Pre cycles | Timed cycles | Timed CPI | Whole cycles | Whole CPI | Evidence |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `WRITE_ALLOCATE=0` | 313,878 | 5,278,164 | 1.725375105 | 5,613,603 | 1.725944902 | `evidence:coremark_public_current` |
| `WRITE_ALLOCATE=1` | 368,877 | 5,277,919 | 1.725295018 | 5,668,419 | 1.742798498 | `evidence:coremark_public_current` / `nonclaim:linux_write_allocate_coremark_speedup_not_claimed` |

开启 write allocation 使 whole-program 增加 54,816 cycles（`evidence:coremark_public_current`），其中 start marker 前
增加 54,999 cycles；timed 区间反而少 245 cycles（`evidence:coremark_public_current`）
（`evidence:coremark_public_current`）。所以旧 `1.7428` 对 `1.7259` 的差异主要是
启动边界，不代表 CoreMark 主体获得约 1% 加速。

## 七项工作负载指令加权聚合 CPI

历史 OoO 套件包含 CoreMark、matrix-mul、crc32、quick-sort、load-store、
Dhrystone、microbench：

```text
instruction-weighted aggregate CPI = 5,157,299 / 5,649,752 = 0.912836351  # evidence:coremark_public_current
```

定义是所有 workload 的总 cycles 除以总 retired instructions，不是七个 CPI 的
算术平均，也不是 CoreMark score。精确外部 workload 集尚未由当前公开入口完整
复跑，因此保持 `provisional`（`nonclaim:ooo_public_cpi_not_yet_claimed`）。

Linux 较早 checkpoint `e3a1cc91c4c00040f7180eec5e385326d9964893` 只有约
CoreMark CPI 1.98 的历史记录（`nonclaim:linux_prior_checkpoint_cpi_not_claimed`）；
它不是当前 `abf66cad` Profile 的结果。

## 实现数据

| Profile | 绝对 CoreMark score | 闭合频率 | 面积 | 功耗 | 状态 |
| --- | ---: | ---: | ---: | ---: | --- |
| `rv32im_single_perf` | — | — | — | — | `not_claimed` |
| `rv32ima_sv32_linux` | — | — | — | — | `not_claimed` |
| `rv32im_ooo_4k` | — | — | — | — | `not_claimed` |

仿真 CPI 或 CoreMark/MHz 不能推出闭合频率、面积或功耗。历史 DC stress 数据仍
保留在 machine-readable nonclaims 中，但不填入当前实现结果表。另见
[CoreMark 证据](evidence/coremark_reproduction.md)、[验证说明](verification.md)和
[限制说明](limitations.md)。
