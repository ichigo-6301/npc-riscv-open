# SoC 集成

[English](soc-integration.en.md)

本仓库当前提供 CPU RTL、Profile wrapper 和纯 Verilator runtime，不提供一个
完整可综合 SoC。本文将四个容易混淆的层次分开：

1. **CPU RTL**：处理器内部已经实例化的模块；
2. **公开 DPI runtime**：仅用于 headless 仿真的 C++ memory/MMIO 服务；
3. **NEMU/AM reference platform**：用于软件和 reference model 对齐的设备模型；
4. **未来可综合 SoC**：需要另行实现和验证的 interconnect、peripheral 与顶层。

## 状态定义

| 状态 | 含义 |
| --- | --- |
| `RTL-integrated` | 外设或功能已经实例化在对应 Profile 的 RTL 中 |
| `runtime-only` | 仅由公开 Verilator C++ runtime 处理，不是可综合 RTL |
| `reference-only` | 只存在于 NEMU/AM 参考环境，不在公开 CPU wrapper 中 |
| `not integrated` | 当前 Profile 没有该功能 |
| `not tested` | 存在入口，但当前公开验证尚未覆盖其完整行为 |

## 当前组件矩阵

| 组件 | `rv32im_single_perf` | `rv32ima_sv32_linux` | `rv32im_ooo_4k` | 说明 |
| --- | --- | --- | --- | --- |
| CPU core | `RTL-integrated` | `RTL-integrated` | `RTL-integrated` | 三个独立 source set |
| Sparse PMEM / image loader | `runtime-only` | `runtime-only` | `runtime-only` | 公共 DPI runtime |
| Legacy serial TX | `runtime-only` | `runtime-only` | `runtime-only` | 写 `0xA00003F8` 输出字符 |
| Legacy RTC | `runtime-only` | `runtime-only` | `runtime-only` | `0xA0000048/4C` 返回仿真 tick |
| ACLINT `mtime/mtimecmp` + MTIP | `not integrated` | `RTL-integrated` | `not integrated` | Linux Profile 的 `AclintTimer` |
| AXI Timer | `reference-only` | `reference-only` | `reference-only` | NEMU/AM FPGA-compatible layout |
| AXI UARTLite | `reference-only` | `reference-only` | `reference-only` | NEMU/AM FPGA-compatible layout |
| AXI INTC | `reference-only` | `reference-only` | `reference-only` | NEMU reference device，当前一条 UART interrupt input |
| tohost stop/pass | `runtime-only` | `runtime-only` | `runtime-only` | 仅在运行时显式配置地址后生效 |
| 板级显示、键盘、GPIO | `not integrated` | `not integrated` | `not integrated` | NVBoard 和板级 top 不在工程中 |

`reference-only` 表示有可参考的软件/模型地址布局，不表示 CPU wrapper 已经
实例化了该 AXI IP，也不表示通过了 RTL 级中断或驱动验证。

## 地址空间

| 地址范围 | 名称 | 关键寄存器 | 当前归属 |
| --- | --- | --- | --- |
| `0xA0000000..0xA000001F` | AXI Timer | TCSR0 `+0x00`、TLR0 `+0x04`、TCR0 `+0x08`、TCSR1 `+0x10`、TLR1 `+0x14`、TCR1 `+0x18` | NEMU/AM `reference-only` |
| `0xA0000048..0xA000004F` | Legacy RTC | low `+0x0`、high `+0x4` | 公共 DPI `runtime-only` |
| `0xA00003F8` | Legacy serial TX | low byte | 公共 DPI `runtime-only` |
| `0xA0010000..0xA001000F` | AXI UARTLite | RX `+0x0`、TX `+0x4`、status `+0x8`、control `+0xC` | NEMU/AM `reference-only` |
| `0xA0020000..0xA0020007` | ACLINT `mtime` | 64-bit low/high word | Linux RTL；NEMU 也有 reference model |
| `0xA0030000..0xA0030007` | ACLINT `mtimecmp` | 64-bit low/high word | Linux RTL；NEMU 也有 reference model |
| `0xA0040000..0xA0040FFF` | AXI INTC | ISR/IPR/IER/IAR/SIE/CIE/IVR/MER 位于 `+0x00..0x1C` | NEMU `reference-only` |

AXI Timer 与 Legacy RTC 的地址属于同一 `0xA0000000` 区域的两种软件平台
约定，但寄存器语义不同。软件必须选择与目标平台一致的 AM header、DTB 和
设备模型，不能把二者视为同一个 timer。

## ACLINT、CSR 与计数器

用户所说“既像 CSR 又像外设的时钟”在当前 Linux Profile 中由以下边界组成：

- `mtime` 和 `mtimecmp` 是 memory-mapped 64-bit 寄存器；
- `AclintTimer` 按 `CLK_HZ/TIMEBASE_HZ` 分频更新 `mtime`；
- 当 `mtime >= mtimecmp` 时，RTL 置位 machine timer interrupt pending；
- CSR `time` (`0xC01`) 和 `timeh` (`0xC81`) 读取 `mtime` 的可见值；
- CSR `cycle/cycleh` 与 `instret/instreth` 是独立计数器，不是
  `mtime/mtimecmp` 的别名。

因此 ACLINT 是 RTL 中的 MMIO timer 外设，而 CSR 文件只提供时间视图和独立
的执行/退休计数。

## CPU memory 接口边界

- 两个顺序 Profile 的原生 top 暴露独立 instruction/data AXI master 端口。
  公开 filelist 选择 `NPC_USE_DPI`，因此 headless wrapper 中 AXI response
  输入被固定，实际访存由内部 DPI bridge 完成。
- OoO Profile 的公开配置使用 pair-fetch 与 tagged data DPI transport；当前
  没有提供标准 AXI SoC wrapper。
- 公共 commit ABI 是验证接口，不是总线协议，也不能代替 memory ordering、
  interrupt 或 DMA 接口验证。

要构建可综合 SoC，应为选定 Profile 新增独立 adapter，明确 clock/reset、
AXI outstanding、cacheable/uncached 区域、interrupt routing、timer frequency、
DTB 和软件 header，并重新运行系统级验证。不要把 DPI C++ 服务综合化，也
不要把 NEMU device model 当作 RTL 外设。

## Difftest 边界

当前本地 NEMU adapter 是 bounded GPR/PC/commit checker。它不验证 UART、
AXI Timer、ACLINT tick 的 cycle-exact 等价、AXI INTC、完整 interrupt timing
或任意 MMIO side effect。不同 timer 模型也不声明 cycle-exact 等价。

另见[架构说明](architecture.md)、[验证说明](verification.md)和
[限制说明](limitations.md)。
