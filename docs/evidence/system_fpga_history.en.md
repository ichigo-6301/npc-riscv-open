# Historical Linux-System And XC7Z100 Evidence

[中文](system_fpga_history.md)

This page reports system boot, FPGA implementation, bitstream generation,
board observation, and workload validation as separate dimensions. The
machine-readable sources are
[`linux_boot.json`](../../evidence/system/linux_boot.json) and
[`single_xc7z100_history.json`](../../evidence/fpga/single_xc7z100_history.json).

## OpenSBI To Linux Shell

<!-- evidence:linux_boot_history_public -->
<!-- claim:linux_historical_boot_to_initramfs_shell maturity:verified -->
<!-- nonclaim:linux_current_source_deep_boot_not_reverified -->

The historical `e3a1cc91` source log records DTB loading, OpenSBI
`v1.8.1-85-gf36acaeb`, `Domain0 Next Mode: S-mode`, Linux `6.6.141`,
`Run /init`, `=== initramfs entered ===`, and `=== shell ready ===`. This
verifies DTB argument handoff, the M-mode to S-mode transition, and the
initramfs shell milestone for that source snapshot.

The raw log is not public; only its SHA256 and bounded marker summary are
published. `e3a1cc91` is an ancestor of `abf66cad`, which is an ancestor of the
current `0fc3de40` source. The current source lock has not repeated this deep
boot, so the historical log is not relabeled as a current-source rerun.

## Three Historical XC7Z100 Snapshots

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

All three results use Vivado 2022.2, `xc7z100ffg900-2`, and the internal
`clk_fpga_0=200 MHz` clock.

| Historical snapshot | Architecture scope | Setup WNS / Hold WHS | Route / DRC | Bitstream / board |
| --- | --- | ---: | --- | --- |
| 2026-05-07 | Five-stage core before forwarding and prediction | +0.083 / +0.044 ns | 0 routing errors; 4 warnings | bitstream `verified`; UART/ILA board observation `partial` |
| 2026-05-12 | Cross-stage forwarding added | +0.010 / +0.040 ns | 0 routing errors; 6 warnings | `not_claimed` |
| 2026-05-15 | Forwarding plus 128-entry BTB/PHT | +0.010 / +0.045 ns | 0 routing errors; 6 warnings | `not_claimed` |

The XSA files in the two later directories have exactly the same SHA256 as the
May 7 file and predate their routed runs. The checker explicitly prevents them
from upgrading the May 12/15 bitstream or board status. Routed timing is
verified for all three snapshots, but routed DRC has warnings and is not called
DRC-clean.

## Board Workload Boundary

The May 7 UART capture contains a CoreMark PASS marker. All 49/49 valid ILA
commit instructions match the saved binary at their captured PCs. The workload
uses `rv32em_zicsr` / `ilp32e`, so it does not validate x16-x31 use. No Hardware
Manager programmed-image transcript was retained; board smoke and workload
validation therefore remain `partial`.

<!-- nonclaim:single_current_source_fpga_board_not_claimed -->
<!-- nonclaim:single_forward_predict_board_not_claimed -->
<!-- nonclaim:single_fpga_exact_programmed_image_not_claimed -->
<!-- nonclaim:single_fpga_standard_coremark_score_not_claimed -->

The current `f76de574` source is not claimed as revalidated on the board,
forwarding/BTB-PHT board execution is not claimed, and the project-specific UART
Marks field is not presented as a standardized absolute CoreMark score.
