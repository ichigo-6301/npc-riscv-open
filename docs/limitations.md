# 限制与不作结论事项

[English](limitations.en.md)

本页采用保守边界。只有 Profile、source commit、配置、输入 hash、原始结果和
fresh-clone 复现全部匹配，某项结果才可能从 `provisional` 或 `not_claimed`
升级为 `verified`。

## RTL 与 Profile

- 三个 Profile 是独立冻结的 RTL source set，不保证内部 module、macro、
  interface 或时序行为兼容。
- 公共 wrapper 只统一 commit、halt 和 GPR/PC debug 观测，不统一内部 memory
  protocol、exception ownership 或 pipeline signal。
- 一次构建只能选择一个 Profile；将多个 filelist 混合编译属于无效配置。
- 为保持 source lock，导出的原生 RTL 不作格式化或去重。同名 module 只能
  在各自 source set 中使用。
- Linux Profile 的公开 source snapshot 是后续结构化 RTL 布局；目录重排不应被
  误解为三个 Profile 共用一套参数化 RTL，也不改变公开 wrapper 的功能契约。

## 系统与软件

- 工程是 CPU + headless Verilator runtime，不是完整可综合 SoC。
- NVBoard、VGA、PS2、keyboard、GPIO、FPGA project 和板级 top 均不包含；
  这不否定外部历史 Vivado 工程的分层证据，只表示该工程不可由本仓库直接复现。
- AXI UARTLite 和 AXI Timer 有 deterministic Verilator `runtime-only` 模型，
  但不是可综合 RTL 外设；AXI INTC 仍为 NEMU/AM `reference-only`。
- Linux Profile 内部包含 `AclintTimer`，但仓库不携带 OpenSBI、Linux kernel、
  DTB、rootfs 或完整板级 memory map。
- 当前 bounded Linux image 只覆盖 machine-mode RV32IMA/LRSC/CSR/trap，不能
  单独证明 S-mode delegation、Sv32 page fault 或 Linux boot。`e3a1cc91` 历史
  日志已证明 DTB/OpenSBI/Linux 6.6.141/initramfs shell 链，但当前 `0fc3de40`
  尚未深跑复验。
- OpenSBI、Linux、AM、NEMU、编译器和用户程序均为外部依赖，使用者负责取得
  正确版本和遵守各自许可证。

## 仿真与 difftest

- 公共 DPI sparse PMEM、legacy RTC、serial TX、AXI Timer、UARTLite 和 tohost
  是 simulation-only 服务，不是硅上 memory 或 peripheral 模型。
- latency 参数描述时钟化仿真 transport，不是 SRAM access time、AXI QoS 或
  cache hit timing。
- 默认 difftest 关闭。本地 adapter 只做 bounded PC/instruction/GPR commit
  check，不覆盖完整 device、timer、interrupt 和 MMIO side-effect 等价。
- 不同 timer 模型不声明 cycle-exact 等价；wall-clock、simulation tick 和
  RTL `mtime` 不能直接混作一个时间基准。
- VCD/itrace 仅用于 debug，开启后会降低宿主吞吐；它们不应参与性能 A/B。
- process exit code 不是单独的 PASS 证据，仍需检查 trap/stop marker、commit
  count、watchdog 和 protocol error。

## 性能、频率与面积

- Single/Linux 的 hash-locked CoreMark marker 计量、self-check 和 NEMU difftest
  已通过；verified 范围仅限固定 binary、config 和仿真条件，不包含绝对
  CoreMark score、频率或硅后性能。
- OoO CoreMark self-check 和 marker 计数通过，但双退休 MMIO packet 的 reference
  顺序有歧义；其 timed CPI `0.879973757` 仍为 provisional
  （`ooo_public_coremark_runtime_provisional`）。
- Linux 私有/公开 timed 区间已精确同步为 CPI `1.725375105`。`WRITE_ALLOCATE=1`
  的 whole CPI `1.742798498` 主要由 start marker 前开销造成，不能表述为
  CoreMark 主循环约 1% 的差异（`linux_write_allocate_coremark_speedup_not_claimed`）。
- Linux no-TLB 到优化版的 whole CPI `8.587098694→1.725944902`、约 `4.9753x`
  仅是同 benchmark-family 的 `partial` A/B；基线 binary hash 缺失且退休数相差
  4 条，不能称严格同 binary 对比。
- OoO 的前端空泡率和控制重定向率改善来自组合环整改前的历史 seven-workload
  仿真纪元；不得继承为当前无环 RTL 性能或 ASIC 结果。
- OoO 的 `0.912836351` 是有限七项工作负载的 instruction-weighted aggregate
  CPI，不是通用 CPI 保证，也不能替代当前 CoreMark timed CPI。
- Single 的约 704 MHz 是 1 ns DC stress 出现负 WNS 后的算术推算，不是
  700 MHz closure 或最大频率；它不替代本次 source-matched 固定频率结果。
- Single/Linux 的 register-expanded 与 SRAM-macro 路线已有四个 Nangate45
  academic fixed-frequency points。其 verified 范围是 top-level placement、CTS、
  detail route、route-tool DRC/antenna/connectivity、OpenRCX 和 matching
  PrimeTime 内部 setup/hold；`evidence:single_linux_nangate45_backend_public`。
- 这些结果不是 Fmax。DC 与 physical clock 是两个独立配置，DC 较高频率不能
  表述成 post-route closure。
- P&R standard-cell area、macro count 和 core footprint 分开报告。SRAM 行的
  standard-cell area 不包含四个 macro，不能单独与 register-expanded area 比较。
- register-expanded 路线仍有 max-capacitance 与外部 IO drive/delay 边界；这些
  电气/IO caveat 不通过降频掩盖，也不否定已报告的内部 setup/hold fixed point。
- SRAM timing 使用 OpenRAM analytical FreePDK45 TT/1.0 V/25 C，而标准单元是
  Nangate45 typical/1.1 V/25 C。`RC-004`、macro characterization、macro
  DRC/LVS/PEX、OCV/MMMC、DFT、formal LEC、power/PI 均未闭合。
- OoO register/SRAM 后端仍为 `planned`，没有公开频率、面积或功耗数据。
- FPGA 历史结果按 source snapshot 分层：原始五级核仅有 `partial` 板级
  UART/ILA 绑定；forwarding 与 predictor 快照只验证 200 MHz routed timing。
  当前 `f76de574` 重新上板、后两快照 bitstream/board/workload 均不声明。
- 三条 FPGA route 均有 0 routing error，但有 4/6/6 条 DRC warning，不能称
  DRC-clean；后两目录中的旧 XSA 不能作为后续 bitstream 或上板证据。
- 三个 Profile 均不声明 foundry signoff、完整 IO/electrical closure、silicon
  correlation 或绝对 CoreMark score。
- OoO 的公开性能路径使用 internal tagged DPI memory；外部 memory synthesis
  contract 不包含所有 DPI-only precise-store/forwarding 行为，因此不声明
  两者完整综合等价。

## 证据与安全

- 私有 benchmark binary、完整日志、主机绝对路径、PDK、Liberty/DB、LEF、
  mapped/routed netlist、SPEF、GDS、SRAM view、EDA work database 和 credential
  不进入工程。公开面只保留 bounded summary、无路径 run identity 和 SHA256。
- 历史数字即使来自私有已验证记录，在公开输入未复现前仍只能标
  `provisional` 或保持精确的 `historical_verified`/`partial` snapshot 边界；
  不能自动升级为当前 source claim。
- source inventory 可能把 `mem_req_token` 等协议字段误报为 secret；这些是
  typed transaction identifiers。真正的 credential 或 secret-like value
  仍必须 fail closed。
- 机器可读 claims/nonclaims 比本文更保守时，以机器可读约束为准。

已知空白和后续数据要求见[性能与实现数据](performance.md)，系统边界见
[SoC 集成](soc-integration.md)，测试范围见[验证说明](verification.md)。
