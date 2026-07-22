# NPC RISC-V multi-profile processors

[中文](README.md)

NPC RISC-V Open contains three purpose-built RISC-V RTL source sets and one
shared, headless Verilator environment. The default configuration is
`rv32im_ooo_4k`. No NVBoard, display, keyboard, or other board user interface
is required.

Each RTL set is locked to an independent source commit. They share the
configuration entry points, headless wrappers, simulation runtime, and commit
packet ABI, but they are not one parameterized RTL implementation. Each build
selects exactly one Profile filelist.

## Highlights

- A five-stage, single-issue RV32IM core for bare-metal and performance work.
- A five-stage RV32IMA M/S-mode and Sv32 core with TLBs, a store buffer, and an
  ACLINT timer.
- A dual-issue, dual-commit RV32IM out-of-order core with a 64-entry PRF,
  ROB8, IQ8, and two branch checkpoints.
- A shared command-line Verilator runtime. Profile-matched local NEMU difftest
  is optional and disabled by default.
- Source, configuration, test, and historical measurement identities remain
  Profile-scoped and commit-locked.

## Profile comparison

| Profile | ISA / privilege | Microarchitecture | Instruction and data structures | Primary use |
| --- | --- | --- | --- | --- |
| `rv32im_single_perf` | RV32IM / M | 5-stage, single issue and commit | 4 KiB 2-way I-cache + 4 KiB 2-way D-cache; 128-entry BTB/PHT | Bare-metal, CoreMark, and in-order pipeline study |
| `rv32ima_sv32_linux` | RV32IMA / M+S, Sv32 | 5-stage, single issue and commit | 4 KiB 2-way I/D caches; 16-entry ITLB/DTLB; 2-entry store buffer; ACLINT | OpenSBI, Sv32, and operating-system integration |
| `rv32im_ooo_4k` | RV32IM / M | Dual dispatch/issue/complete/commit OoO core | 4 KiB instruction-pair storage; 4 KiB physically tagged word cache | Dual-width out-of-order throughput study |

The `rv32im_ooo_4k` instruction-pair storage is a 64-bit pair-oriented
frontend structure, not a conventional set-associative I-cache. See
[Architecture](docs/architecture.en.md) for the full comparison.

## Quick start

Python 3.8+, GNU Make, PyYAML, and Verilator 5.x are required:

```sh
python3 -m pip install --user PyYAML
make defconfig
make showconfig
make config-check source-check docs-check public-hygiene
make verilator-lint
make smoke
```

Regenerate `.config` when selecting another Profile:

```sh
make rv32im_single_perf_defconfig
make rv32ima_sv32_linux_defconfig
make rv32im_ooo_4k_defconfig
```

Run a user-supplied image with:

```sh
NPC_OPEN_IMAGE=/path/to/program.bin make sim
```

The default configuration does not need NEMU. A strict local run can prepare
the reference model matching the selected Profile:

```sh
make difftest-prepare NPC_NEMU_SOURCE_REPO=/path/to/ysyx-workbench
make difftest
```

Generated reference libraries, logs, waves, and build directories are ignored
by Git. See [Simulation](docs/simulation.en.md) and
[Verification](docs/verification.en.md) for details.

## Architecture, performance, and SoC integration

- [Architecture](docs/architecture.en.md): pipelines, predictors, memory
  structures, and interfaces for all three Profiles.
- [Performance and implementation data](docs/performance.en.md): a public
  reproduction table and explicitly provisional historical references.
- [SoC integration](docs/soc-integration.en.md): boundaries between the public
  DPI runtime, Linux RTL timer, and NEMU/AM reference devices.

The current public flow covers source closure, Verilator lint, bounded smoke,
and regression. CoreMark, frequency, and area values that have not been
independently reproduced by this repository remain `provisional`; they are not
maximum-frequency, physical-implementation, or silicon claims.

## Project boundary

NEMU, AM, OpenSBI, Linux, PDKs, Liberty files, SRAM macros, EDA databases, and
board projects are not bundled. The MIT license covers only the self-owned RTL,
wrappers, scripts, and documentation explicitly present here. Users obtain
third-party components separately under their respective licenses.

See the [documentation index](docs/README.en.md),
[limitations](docs/limitations.en.md), [evidence policy](evidence/README.md),
and [NOTICE](NOTICE).
