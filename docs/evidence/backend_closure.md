# Single / Linux 后端证据

[English](backend_closure.en.md)

<!-- evidence:single_linux_nangate45_backend_public -->

## 审计结论

四条 Single/Linux 后端证据链均已通过 D11 只读审计，结论为
`AUDIT_CONFIRMED_EXISTING_BACKEND_RESULTS`。审计复核了 source/config/tool/library
identity、逐角色 artifact SHA256、DC 完整性、placement/CTS/detail route、GDS、
OpenRCX 和 PrimeTime 报告；没有重复运行 DC、P&R、OpenRCX 或 PrimeTime。

该结论只支持固定频率的 Nangate45 academic closure point。它不支持 Fmax、完整
IO/电气闭合、foundry signoff 或 silicon result。

## 固定身份

| 维度 | Single | Linux/Sv32 |
| --- | --- | --- |
| Profile | `rv32im_single_perf` | `rv32ima_sv32_linux` |
| Source lock | `f76de57479b798aca7468f999c386bb4cb5fce02` | `0fc3de40c4e0b231c65945c9dc1711f084688c04` |
| Canonical top | `cpu_top` | `cpu_top` |
| Memory modes | register-expanded / four-macro SRAM | register-expanded / four-macro SRAM |

Single registers 直接使用 `f76de574` 的 33 个 source role；Single SRAM 仅将三个
cache role 替换为 `176d4fd74da61ec681816630854501b233213982` 的审计版本。词法
比较确认这些文件包含 `NPC_ASIC_SRAM` 功能 token 差异，因此不登记为注释/空白
等价。两种模式分别锁定 source-set SHA256
`8124c7d9d41959d0827af3c4f54c4154b90a4a116e46074e197afe207c751f12` 和
`d5296a9dbba4a47ef061b286d6fac90a49770b7a2d46f72f05a12dfbfc2bfccb`。Linux
两种模式均精确锁定 `0fc3de40` 的同一 51-role source set。

四条路线共用固定的 Nangate45 ORFS academic platform identity：

- Design Compiler / PrimeTime / Library Compiler：`O-2018.06-SP1`。
- OpenROAD / OpenRCX：`26Q3-463-gbde79242a0`；ORFS commit
  `bea7dcd7be7f26d1328f6058b01cf42bf4352aa2`，容器 digest 在机器证据中固定。
- NangateOpenCellLibrary typical / 1.1 V / 25 C，Liberty time unit 为 1 ns。
- RC 分类为 `PDK_PROVIDED_ACADEMIC_RC`，使用固定 OpenRCX rules；不称为
  foundry-calibrated RC。

SRAM 路线另外绑定 OpenRAM commit
`e16d9eb0b4495e8beee441ced3fcad68391155e6` 及 analytical FreePDK45 TT / 1.0 V /
25 C macro view。标准单元与 macro timing model 的 PVT 不一致是公开限制，不通过
重命名或降频隐藏。

## 已核验结果

<!-- claim:single_registers_nangate45_dc_frequency maturity:verified -->
<!-- claim:single_registers_nangate45_postroute_frequency maturity:verified -->
<!-- claim:single_registers_nangate45_standard_cell_area maturity:verified -->
<!-- claim:single_registers_nangate45_core_area maturity:verified -->
<!-- claim:single_sram_nangate45_dc_frequency maturity:verified -->
<!-- claim:single_sram_nangate45_postroute_frequency maturity:verified -->
<!-- claim:single_sram_nangate45_standard_cell_area maturity:verified -->
<!-- claim:single_sram_nangate45_core_area maturity:verified -->
<!-- claim:linux_registers_nangate45_dc_frequency maturity:verified -->
<!-- claim:linux_registers_nangate45_postroute_frequency maturity:verified -->
<!-- claim:linux_registers_nangate45_standard_cell_area maturity:verified -->
<!-- claim:linux_registers_nangate45_core_area maturity:verified -->
<!-- claim:linux_sram_nangate45_dc_frequency maturity:verified -->
<!-- claim:linux_sram_nangate45_postroute_frequency maturity:verified -->
<!-- claim:linux_sram_nangate45_standard_cell_area maturity:verified -->
<!-- claim:linux_sram_nangate45_core_area maturity:verified -->

| 路线 | DC / route+PT | PT setup / hold WNS | Standard-cell / core footprint | Macro |
| --- | ---: | ---: | ---: | ---: |
| Single / registers | 540 / 425 MHz | +0.025646 / +0.063219 ns | 0.679497 / 2.614530 mm² | 0 |
| Single / SRAM | 600 / 475 MHz | +0.013556 / +0.047904 ns | 0.149292 / 0.858801 mm² | 4 |
| Linux / registers | 280 / 200 MHz | +0.387809 / +0.032648 ns | 0.717964 / 2.825040 mm² | 0 |
| Linux / SRAM | 300 / 200 MHz | +0.720415 / +0.039090 ns | 0.198085 / 1.049500 mm² | 4 |

四条路线的 detail-route DRC、antenna net/pin 和 unrouted net 均为零。PrimeTime
setup/hold TNS 与 violating path count 均为零，constrained-path coverage 字段为
100%，unclocked synchronous endpoint 为零。`report_analysis_coverage` 另有以下
untested check 分类，不能被前述 100% 字段隐藏：

| 路线 | Total | Setup | Hold | Recovery | Removal | Min pulse width |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Single / registers | 19 | 2 | 2 | 5 | 5 | 5 |
| Single / SRAM | 0 | 0 | 0 | 0 | 0 | 0 |
| Linux / registers | 90 | 6 | 6 | 26 | 26 | 26 |
| Linux / SRAM | 2 | 1 | 1 | 0 | 0 | 0 |

这些计数按 D11 PrimeTime 报告原样保留；它们不是 unclocked synchronous endpoint，
也不改变已报告的 WNS/TNS，但会约束 claim 只能覆盖内部固定频率 timing point，不能
扩展为外部 IO timing、异步 recovery/removal 或完整 signoff closure。

## 角色级交接

每条路线都记录独立 DC、route 和 PrimeTime run ID，并对以下角色执行 SHA256
传递检查：

| 生产者 | 消费者 | 必须相等的角色 |
| --- | --- | --- |
| Design Compiler | P&R input / OpenROAD import | mapped netlist |
| OpenROAD route | PrimeTime | routed netlist、routed SDC |
| OpenROAD routed database | OpenRCX | routed database |
| OpenRCX | PrimeTime | SPEF |
| Platform / macro views | DC / P&R / PrimeTime | Liberty/DB 及适用的 macro view identity |

机器证据还保留 source SDC、DC mapped SDC、P&R input SDC、sanitized routed SDC、
routed DEF、GDS、tool setup 和主要报告的 SHA256。任何缺失或不相等都应失败为
handoff/evidence mismatch，而不是降低 claim 门槛。

完整角色值位于
[`evidence/implementation/nangate45_fixed_points.json`](../../evidence/implementation/nangate45_fixed_points.json)。
公开记录只保存 hash 和脱敏 run identity，不保存私有路径、账号或主机地址。

## DC 与阶段完整性

四条 DC 结果均满足 link、`check_design` 和 `check_timing`，组合 timing loop、自动
arc break、latch、unclocked synchronous endpoint 和 unresolved reference 均为零。
Register 路线 macro/blackbox 为 `0/0`；SRAM 路线 macro/blackbox 为 `4/0`。

四条物理路线均完成 placement、CTS、detail route、GDS 和 OpenRCX，并具备完整
PrimeTime setup、hold、coverage、constraint 和 parasitic annotation 报告。P&R
输入的 DC mapped netlist 与 OpenROAD import 逐字节一致，避免 Yosys/ABC 重新映射。

## 分层成熟度与限制

| 维度 | Register-expanded | SRAM-macro |
| --- | --- | --- |
| Physical implementation chain | `verified` | `verified` |
| Internal extracted setup/hold | `verified` | `verified` |
| Electrical / external IO | `partial` | `partial` |
| Macro model | `not_applicable` | `partial_analytical_characterization` |
| Macro DRC/LVS/PEX | `not_applicable` | `not_closed` |
| OCV/MMMC、DFT、LEC、power/PI | `not_claimed` | `not_claimed` |
| Foundry signoff / silicon | `not_claimed` | `not_claimed` |

PrimeTime 中保留的 max-capacitance、部分 fanout、外部 IO model 缺失和 SRAM RC-004
不是 setup 频率失败，不能通过盲目降频包装成完整电气闭合。SRAM standard-cell area
不包含 macro interior；register-expanded 与 SRAM 是不同 memory binding，面积和频率
比较必须保留 model boundary。

## 公开复核

以下命令不调用 EDA，只校验 evidence schema、四条结果、角色 hash 等式、claim/evidence
双向关系、双语数值和生成资产陈旧状态：

```bash
make implementation-check
make showcase-check
```
