# NPC RISC-V public multi-profile release

This repository is the `npc-riscv-open-v0.1.0-rc1` headless Verilator release
of three RISC-V CPU profiles. One `main` branch contains three independent RTL source
sets selected by declarative profile manifests; a run never compiles all three
sets together.

The default profile is `rv32im_ooo_4k`. Select a profile and inspect the exact
effective configuration before building:

```text
make defconfig
make showconfig
make config-check source-check public-hygiene
make sim-dry-run
make verilator-lint
```

The single-issue performance profile, single-issue Sv32 Linux profile and
dual-issue out-of-order profile have separate wrappers, filelists, source
references and evidence. Shared files are limited to the public flow control,
Verilator runner and test interfaces.

## Release status

| Dimension | RC1 status |
| --- | --- |
| Three isolated RTL sets and headless wrappers | verified by source closure/lint |
| Three-profile bounded self-check | verified in a native-Linux fresh clone (seed 1) |
| Full Linux/OpenSBI boot | planned/partial; external firmware and not an RC1 completion claim |
| Difftest | planned; only the documented adapter ABI is accepted, not a raw NEMU `.so` |
| ASIC PPA, timing, SRAM/PDK signoff | not_claimed |

## Public boundary

The release contains no board-specific user-interface integration, proprietary
EDA databases, PDK files, generated build output or private reference-model
source. An optional external reference adapter can be supplied by path at run
time using [the public ABI](sim/include/profile_abi.hpp); loading a shared object
without the required init/step/fini symbols is an explicit failure.

Performance, implementation and timing statements are profile-scoped. A value
is not a public verified claim until its binary hash, configuration, source
commit and reproducible evidence are listed in `delivery/` and `evidence/`.

The RC1 fresh-clone evidence covers only the checked-in bounded images: the
single-issue smoke completed in 269 cycles/27 commits, the Linux-profile images
in 162/27 and 80/15, and the OoO smoke in 107 cycles/21 commits with 5
second-lane commits. CoreMark, OoO fixed-tail workloads, full OpenSBI/Linux
boot, external difftest, and private commit-trace equivalence still require
external fixtures and are not public performance claims.

See [docs/README.en.md](docs/README.en.md), [docs/README.md](docs/README.md),
[docs/reproduction.md](docs/reproduction.md) and [docs/limitations.md](docs/limitations.md).

中文默认文档见 [README.md](README.md)。
