# CoreMark 计量与复现证据

[English](coremark_reproduction.en.md)

本页说明当前 headless Verilator CoreMark 的输入身份、定时边界、结果状态与复现
方法。机器可读的唯一数字源是
[`evidence/performance/coremark.json`](../../evidence/performance/coremark.json)，
输入合同是
[`delivery/benchmarks/coremark.json`](../../delivery/benchmarks/coremark.json)。

## 固定输入

- AM/CoreMark commit：`034e6c6b5902709546fa74ad70e3a3238ecee576`。
- `ITERATIONS=10`，单 context；patch SHA256：
  `586abb219713ac368b5e2d79289ce67a133af334346908328628f69d8e86279d`。
- compiler：`riscv64-linux-gnu-gcc 11.4.0`；完整 flags 记录在 benchmark manifest。
- benchmark manifest SHA256：
  `d03f12046d34af83a2487db8594d62ad8b762c256bb6de38d66c0bab4e6f53d0`。
- seed `1`；watchdog `20,000,000` cycles；VCD、itrace、mtrace、ftrace、
  pmemtrace 均关闭。

| Variant | Profiles | BIN SHA256 | ELF SHA256 | Start marker | Stop marker |
| --- | --- | --- | --- | --- | --- |
| `rv32im_m` | Single、OoO | `601f942b5a32d071dd0170425107875fdc287bb86549c6489622656ea7ff1742` | `0dec53590bd873d2fb4b0055e7f62bfc041eefad686b843e2eb2f867f8a615e3` | PC `0x800015dc`, instr `0x38a7a223` | PC `0x80001618`, instr `0x34a7a623` |
| `rv32ima_sv32` | Linux/Sv32 | `50840465ecda9da48a69a4361b1a479c42428b5331b114dc694658c6928be6c5` | `6aee51c5ea8084fde549169fc3f4360f2e5705057356fc824a2c55943d36bab2` | PC `0x80001788`, instr `0x7ca7a023` | PC `0x800017c4`, instr `0x78a7a423` |

runner 会同时核对 BIN、ELF 和 marker 处的指令编码。hash 不匹配、marker 重复、
乱序、缺失或未闭合都会直接失败。多个完整 episode 出现时选择最后一个并保留
全部 episode 计数。

## 计量边界

start/stop 指令退休时记录 cycle 与全局 commit ordinal：

```text
timed_cycles       = stop_commit_cycle - start_commit_cycle
timed_instructions = stop_commit_ordinal - start_commit_ordinal
timed_cpi          = timed_cycles / timed_instructions
coremark_per_mhz   = 10 * 1,000,000 / timed_cycles
```

`whole` 从 reset 后运行到 ebreak；`pre`、`timed`、`post` 在 cycles 和 retired
instructions 两个维度都必须守恒。host wall-clock 毫秒和项目自定义 `Marks` 只用
于 sanity check，不进入性能数字。

## 当前结果

| Profile | Pre cycles/instr | Timed cycles/instr | Post cycles/instr | Timed CPI | CoreMark/MHz | Whole CPI | Difftest | 状态 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | --- | --- |
| `rv32im_single_perf` | 21,270 / 14,176 | 4,542,529 / 3,059,106 | 14,266 / 7,803 | 1.484920431 | 2.201416876 | 1.485861312 | PASS，466 MMIO skips | `verified` |
| `rv32ima_sv32_linux` | 313,878 / 184,284 | 5,278,164 / 3,059,140 | 21,561 / 9,057 | 1.725375105 | 1.894598197 | 1.725944902 | PASS，932 MMIO skips | `verified` |
| `rv32im_ooo_4k` | 15,254 / 14,176 | 2,691,933 / 3,059,106 | 11,540 / 7,834 | 0.879973757 | 3.714802709 | 0.882383851 | 未运行：双退休 MMIO 歧义 | `provisional` |

Single/Linux adapter 在 REF 执行前解码已知 Timer/UART MMIO，执行确定性的
skip-and-sync，随后继续比较 PC/instruction/GPR。未知 MMIO 或 PMEM 副作用会失败。
OoO 同周期可能退休两个 packet；当其中包含 MMIO 时，当前 ABI 无法无歧义地确定
reference 执行/跳过顺序。本轮没有放宽协议，所以 OoO 只作为 self-check 与计数
通过的 provisional 结果。

## 复现

外部 BIN/ELF 不进入 Git。取得与 manifest 完全匹配的本地文件后：

```sh
make rv32im_single_perf_defconfig
NPC_OPEN_COREMARK_IMAGE=/path/to/coremark-riscv32-M-npc.bin \
NPC_OPEN_COREMARK_ELF=/path/to/coremark-riscv32-M-npc.elf \
make coremark-difftest

make rv32ima_sv32_linux_defconfig
NPC_OPEN_COREMARK_IMAGE=/path/to/coremark-riscv32s-M-fpga.bin \
NPC_OPEN_COREMARK_ELF=/path/to/coremark-riscv32s-M-fpga.elf \
make coremark-difftest

make rv32im_ooo_4k_defconfig
NPC_OPEN_COREMARK_IMAGE=/path/to/coremark-riscv32-M-npc.bin \
NPC_OPEN_COREMARK_ELF=/path/to/coremark-riscv32-M-npc.elf \
make coremark

make performance-check
```

`coremark-difftest` 需要先按[仿真指南](../simulation.md)准备本地 NEMU adapter。
每次运行输出 `PUBLIC_SIM_PASS`、`PUBLIC_BENCHMARK_EPISODE`、
`PUBLIC_BENCHMARK`，并在 `build/performance/<profile>/` 写一次性 JSON。

## Linux parity 与配置解释

私有 `abf66cad` RTL 加 measurement-only observer 与公开 wrapper 使用同一 Sv32
binary、`WRITE_ALLOCATE=0`：二者均得到 `5,278,164` timed cycles、`3,059,140`
timed instructions、CPI `1.725375105`。observer patch SHA256 为
`d3bd6c500dac32403eb6fa7f1fd92933cc4269e844231992f9cd98fdd5515623`。

私有/公开 whole-program 分别为 `5,613,479 / 3,252,449` 与
`5,613,603 / 3,252,481`；差值来自 reset/计数索引和结束 UART/terminal 边界。
`WRITE_ALLOCATE=1` 诊断得到 whole `5,668,419` cycles，但 timed 仅
`5,277,919` cycles。相对默认配置，多出的 `54,816` whole cycles 几乎全部是
start marker 前的 `54,999` cycles，不能解释为 CoreMark 主循环约 1% 的性能差。

另见[性能页](../performance.md)、[验证说明](../verification.md)和
[限制说明](../limitations.md)。
