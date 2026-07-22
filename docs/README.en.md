# Documentation index

## Profiles

| Profile | Purpose | Public status at RC1 |
| --- | --- | --- |
| `rv32im_single_perf` | RV32IM single-issue performance study | source and smoke status are declared in `delivery/` |
| `rv32ima_sv32_linux` | RV32IMA single-issue Sv32/Linux bring-up | Linux synthesis is not claimed |
| `rv32im_ooo_4k` | RV32IM dual-issue out-of-order performance | release evidence remains profile-scoped |

The profile manifest is the source of truth for top modules, source commits,
filelists, wrappers, ISA, memory binding and maturity. The root Makefile is only
a stable operator interface and must not grow a second set of defaults.

## Reproduction and limitations

- [Reproduction](reproduction.md) explains a fresh-clone, headless Verilator run.
- [Limitations](limitations.md) lists unclaimed implementation and integration
  boundaries.
- [中文文档](README.md)。

Claims, nonclaims, source closure and evidence hashes are kept under the
machine-readable `delivery/` and `evidence/` trees. Do not combine numbers from
different profiles, source commits or memory models.
