# 后续路线

[English](roadmap.en.md)

本页只列尚未完成的工作。已经审计确认的 Single/Linux Nangate45 固定频率
实现点记录在[性能与实现数据](performance.md)和
[后端证据](evidence/backend_closure.md)中，不在这里重复包装为目标。

## `rv32im_single_perf`

- 复核外部 IO drive/load 与 input/output delay，并把内部时序和完整 IO 时序分开。
- 对 max-capacitance 等电气例外建立对象级修复或审阅记录；不通过降频掩盖。
- 为 SRAM macro 补充实际 characterization、macro DRC/LVS/PEX、OCV/MMMC、DFT、
  formal LEC 和 power-integrity 证据。

## `rv32ima_sv32_linux`

- 在 `0fc3de40` source lock 上复跑相同 hash 的 CoreMark 输入，决定历史
  `abf66cad` CPI 是否可以提升为当前 Profile claim。
- 扩展 OpenSBI/S-mode/Sv32 page-fault 的 bounded regression；完整 Linux
  distribution boot 仍需外部 image、DTB 和可审计的板级 memory map。
- 后端后续项与 Single 相同：IO、电气例外、macro signoff、OCV/MMMC、DFT、LEC
  和 power integrity。

## `rv32im_ooo_4k`

- 当前优先级是继续完成 RTL 性能优化、双退休 MMIO difftest 顺序和可综合外部
  memory contract 的等价边界。
- register-expanded 与 SRAM-macro 的 DC、P&R、OpenRCX 和 PrimeTime 均为
  `planned`；当前不发布预测频率、面积或功耗。
- 只有 source/config freeze、实际工具输出、same-run artifact identity、route
  checks 和 external STA 同时齐全时，才能把后端状态从 `planned` 提升。

## 状态升级门禁

任何新增实现结果都必须绑定 Profile、source set、memory mode、SDC、工具和库
identity，并保留 mapped netlist、routed netlist、routed SDC、SPEF 与 Liberty/DB
的角色级 SHA256。脚本、空目录、目标频率或一次工具启动均不能单独升级状态。
