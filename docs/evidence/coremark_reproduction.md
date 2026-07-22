# CoreMark 公开运行证据

本记录只描述可审计的 headless Verilator 运行，不把结果升级为
`verified` claim。CoreMark 输入和编译树是仓库外部文件，未随项目快照提交；
因此状态为 `provisional_external_input`。

## 固定条件

- public source snapshot：`25cce067d41b37151c45acd8a3069c445dbcb7b5`；文档更新不改变
  三个 RTL source-set 的 hash。
- Profile source commits：Single `f76de57479b798aca7468f999c386bb4cb5fce02`，
  Linux `abf66cad0f9ad02efc8beb641d4005adeaeeae0b`，OoO
  `99fcc2be539eabb078c0d73b26a7ef2c00071391`。
- runner：`sim/common/verilator_runner.py`；Verilator `5.008`；seed `1`；
  watchdog `10000000`；VCD、itrace、mtrace、ftrace 和 pmemtrace 均关闭。
- CoreMark/AM source commit：`034e6c6b5902709546fa74ad70e3a3238ecee576`；
  `core_portme.h` 的测量配置将 `ITERATIONS` 设为 `10`，文件 hash 为
  `beaafe65699ef47191d6153fa9d6913ab5928a5b98e6c6f8949a31aad892335e`；
  compiler 为 `riscv64-linux-gnu-gcc 11.4.0`。
- retired instruction 定义：Single/Linux 为 `commit`；OoO 为
  `commit + commit2`，对应 wrapper 的有效 commit packet。

## 当前 public headless runtime

输入 binary 不在仓库内，以下 hash 用于重新取得和核对输入：

从项目根目录执行的命令（将 `external/...` 替换为已核对 hash 的本地输入）：

```sh
python3 sim/common/verilator_runner.py --profile rv32im_single_perf \
  --filelist filelists/rv32im_single_perf.f --build-dir build/coremark-public \
  --image external/coremark-riscv32-M-npc.bin --watchdog 10000000

python3 sim/common/verilator_runner.py --profile rv32ima_sv32_linux \
  --filelist filelists/rv32ima_sv32_linux.f --build-dir build/coremark-public \
  --image external/coremark-riscv32s-M-fpga.bin --watchdog 10000000 \
  --ifetch-latency 0 --lsu-latency 0 --memory-latency 0

python3 sim/common/verilator_runner.py --profile rv32im_ooo_4k \
  --filelist filelists/rv32im_ooo_4k.f --build-dir build/coremark-public \
  --image external/coremark-riscv32-M-npc.bin --watchdog 10000000
```

| Profile | Binary / ELF SHA256 | Runtime latency | Cycles | Retired instructions | CPI | CoreMark stop |
| --- | --- | ---: | ---: | ---: | ---: | --- |
| `rv32im_single_perf` | `coremark-riscv32-M-npc.bin` / `46c58bd81c055444cac483d7f83038774d9afd0c9c2f2c62ac4916f720e3a1bd` (ELF)；binary `ea230c1a3766d7ea5726d8ff53f0a615bfa2cd7f7d2c98a69d0c829c432a663d` | `2/3/2` (IF/LSU/memory) | `4578475` | `3081067` | `1.486003063` | `CoreMark PASS`, ebreak |
| `rv32ima_sv32_linux` | `coremark-riscv32s-M-fpga.bin` / `8d6a55b2766fe039267ea3bc8b8457d296689872d45dccccb39861de960cc774` (ELF)；binary `814002f10fb0f2e4338fb07d8b421dc7c3c4bb4f06e633d1426f867133f39cdb` | `0/0/0`; public filelist uses `NPC_DCACHE_WRITE_ALLOCATE=1` | `5668250` | `3252429` | `1.742774400` | ebreak at `_trm_init`; CoreMark marker unavailable |
| `rv32im_ooo_4k` | `coremark-riscv32-M-npc.bin` / ELF `46c58bd81c055444cac483d7f83038774d9afd0c9c2f2c62ac4916f720e3a1bd`；binary `ea230c1a3766d7ea5726d8ff53f0a615bfa2cd7f7d2c98a69d0c829c432a663d` | `2/3/2` (IF/LSU/memory) | `2718694` | `3081098` (`2040454 + 1040644`) | `0.882378295` | `CoreMark PASS`, ebreak |

对应的 `PUBLIC_SIM_PASS` 行为为：

```text
single: PUBLIC_SIM_PASS cycles=4578475 commit=3081067 commit2=0
linux:  PUBLIC_SIM_PASS cycles=5668250 commit=3252429 commit2=0
ooo:    PUBLIC_SIM_PASS cycles=2718694 commit=2040454 commit2=1040644
```

OoO 使用 M-mode binary；将 Linux/Sv32 binary 放到 OoO 会在 Sv32 trap handler
停止，不能把该结果当作 OoO CoreMark。

这些运行没有启用 difftest。尝试开启 profile-matched adapter 的结果如下：

- Single：在 legacy RTC `0xa0000048` 访问处被当前 `device=false` NEMU 合同拒绝；
- Linux：在 AXI timer `0xa0000000` 访问处被同一合同拒绝；
- OoO：第 11 条 commit 出现 `x8` 参考值 `0`、DUT 值 `0xb` 的确定性 mismatch。

因此 Single/OoO 是“CoreMark PASS、runtime PASS、difftest 未接受”，Linux 是
“CoreMark image 到达正常 ebreak、marker 不可见、difftest 未接受”。三行都只是
provisional 数据，不能标为架构 verified claim。Linux 的 marker 缺失来自公开
runtime 未实现 AXI UARTLite/AXI Timer；私有同一 binary 家族的重跑仍有明确 PASS。
DPI runtime 的 host 毫秒和 Marks 只作停机 sanity check；没有实现时钟，不能换算
CoreMark/MHz。

## Linux 后续优化 checkpoint 私有重跑

为确认历史 `≈1.72`，在 source commit
`abf66cad0f9ad02efc8beb641d4005adeaeeae0b` 上使用同一 S-mode binary 和
`NPC_DCACHE_WRITE_ALLOCATE=0` 的私有配置重跑：

```text
cycles=5613732
committed=3252492
CPI=1.7259787264657377
```

CoreMark PASS、GOOD TRAP、CPI attribution mismatch `0`、unknown `0`。
私有运行日志 hash 为 `25b995dd6e12d9e77284f5552667d149d7c77986f3bcb722e7e2aa62449b4451`，
build log hash 为 `13e01b226d40c4e633246e1cc08244d3a16ae3f976c4ed39425ef0a19839984d`，
CoreMark build log hash 为 `3a7ac0ed58723aa0d233ea2305daeb6e31fa1d82347488f9416191c706c24ba8`。
这解释了历史 `≈1.72`，也说明它与当前公开 Linux filelist 的
`WRITE_ALLOCATE=1`、CPI `1.742774400` 不是同一配置；两者不能混为一个结果。

历史重跑仍是 `provisional`：binary、完整私有构建树和 NEMU/AM 依赖没有进入
公开仓库。公开表保留精确 CPI 及其条件，频率、面积、CoreMark/MHz 和七 workload
weighted CPI 继续留空。
