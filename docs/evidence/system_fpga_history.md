# Linux 系统启动与 XC7Z100 历史证据

[English](system_fpga_history.en.md)

本页把系统启动、FPGA implementation、bitstream、板级观测和 workload
validation 分开报告。机器可读来源为
[`linux_boot.json`](../../evidence/system/linux_boot.json)和
[`single_xc7z100_history.json`](../../evidence/fpga/single_xc7z100_history.json)。

## OpenSBI 至 Linux shell

<!-- evidence:linux_boot_history_public -->
<!-- claim:linux_historical_boot_to_initramfs_shell maturity:verified -->
<!-- nonclaim:linux_current_source_deep_boot_not_reverified -->

`e3a1cc91` 历史 source snapshot 的日志依次记录：DTB 载入、OpenSBI
`v1.8.1-85-gf36acaeb`、`Domain0 Next Mode: S-mode`、Linux `6.6.141`、
`Run /init`、`=== initramfs entered ===` 和 `=== shell ready ===`。该链路验证
DTB 参数传递、M-mode 至 S-mode 交接以及 initramfs shell 启动。

原始日志不公开，只公开 SHA256 和 bounded marker 摘要。`e3a1cc91` 是
`abf66cad` 的祖先，`abf66cad` 又是当前 `0fc3de40` 的祖先；但当前 source lock
没有重新执行这次深启动，因此不能把历史日志标成当前 source 的复跑结果。

## XC7Z100 三条历史快照

<!-- evidence:single_xc7z100_history_public -->
<!-- claim:single_fpga_original_routed_frequency maturity:verified -->
<!-- claim:single_fpga_original_setup_wns maturity:verified -->
<!-- claim:single_fpga_original_hold_whs maturity:verified -->
<!-- claim:single_fpga_historical_board_observation maturity:partial -->
<!-- claim:single_fpga_forward_routed_frequency maturity:verified -->
<!-- claim:single_fpga_forward_setup_wns maturity:verified -->
<!-- claim:single_fpga_forward_hold_whs maturity:verified -->
<!-- claim:single_fpga_predict_routed_frequency maturity:verified -->
<!-- claim:single_fpga_predict_setup_wns maturity:verified -->
<!-- claim:single_fpga_predict_hold_whs maturity:verified -->

三条结果均使用 Vivado 2022.2、`xc7z100ffg900-2` 和内部 `clk_fpga_0=200 MHz`。

| 历史快照 | 架构范围 | Setup WNS / Hold WHS | Route / DRC | Bitstream / board |
| --- | --- | ---: | --- | --- |
| 2026-05-07 | forwarding 与预测前的五级核 | +0.083 / +0.044 ns | routing errors 0；4 warnings | bitstream `verified`；UART/ILA board observation `partial` |
| 2026-05-12 | 加入跨级 Forwarding | +0.010 / +0.040 ns | routing errors 0；6 warnings | `not_claimed` |
| 2026-05-15 | Forwarding + 128-entry BTB/PHT | +0.010 / +0.045 ns | routing errors 0；6 warnings | `not_claimed` |

后两个目录中的 XSA 与 5 月 7 日文件 SHA256 完全相同，且早于相应 routed run；
checker 明确禁止用它升级 5 月 12/15 日的 bitstream 或 board 状态。三条 routed
timing 均 verified，但 routed DRC 含 warning，因此不称 DRC-clean。

## 板级 workload 边界

5 月 7 日 UART 包含 CoreMark PASS marker；ILA 中 49/49 条有效 commit instruction
与保存的 binary 在对应 PC 完全匹配。workload 为 `rv32em_zicsr` / `ilp32e`，
不能验证 x16-x31 使用。未保存 Hardware Manager programmed-image transcript，
所以 board smoke 和 workload validation 均为 `partial`。

<!-- nonclaim:single_current_source_fpga_board_not_claimed -->
<!-- nonclaim:single_forward_predict_board_not_claimed -->
<!-- nonclaim:single_fpga_exact_programmed_image_not_claimed -->
<!-- nonclaim:single_fpga_standard_coremark_score_not_claimed -->

不声明当前 `f76de574` 已重新上板，不声明 Forwarding/BTB-PHT 快照已在板上运行，
也不把 UART 中项目自定义的 Marks 字段解释为标准绝对 CoreMark score。
