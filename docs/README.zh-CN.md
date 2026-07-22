# 文档索引

## Profile

| Profile | 用途 | RC1 公开状态 |
| --- | --- | --- |
| `rv32im_single_perf` | RV32IM 单发射性能研究 | source 与 smoke 状态以 `delivery/` 为准 |
| `rv32ima_sv32_linux` | RV32IMA 单发射 Sv32/Linux 启动 | 不声明 Linux 综合结果 |
| `rv32im_ooo_4k` | RV32IM 双发射乱序性能 | 证据始终按 profile 隔离 |

Profile manifest 是 top module、源提交、filelist、wrapper、ISA、memory binding
和成熟度的唯一来源。根目录 Makefile 只是稳定的操作入口，不应再维护第二套默认值。

## 复现与限制

- [复现说明](reproduction.md) 描述 fresh clone 上的纯 Verilator 流程。
- [限制说明](limitations.md) 列出尚未声明的实现和集成边界。

claims、nonclaims、source closure 和证据 hash 保存在机器可读的 `delivery/`
与 `evidence/` 中。不同 profile、源提交或 memory model 的数字不能混合比较。
