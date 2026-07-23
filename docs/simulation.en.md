# Simulation

[中文](simulation.md)

## Requirements

- Linux;
- Python 3.8 or newer;
- GNU Make and a C++ compiler;
- PyYAML;
- Verilator 5.x.

Install the Python dependency and generate a Profile configuration:

```sh
python3 -m pip install --user PyYAML
make defconfig
make showconfig
```

`showconfig` should report `project_id=npc-riscv-open`, the current
`snapshot_id`, and one `profile_id`. Older `.config` files do not contain the
new project/snapshot fields; run a defconfig target again after updating.

## Select a Profile

```sh
make rv32im_single_perf_defconfig
make rv32ima_sv32_linux_defconfig
make rv32im_ooo_4k_defconfig
```

`make defconfig` selects `rv32im_ooo_4k`. The Profile manifest fixes ISA,
width, cache/TLB, and OoO mechanisms. Command-line inputs are limited to the
program image, watchdog, seed, tracing, and similar run controls.

## Standard flow

```sh
make config-check source-check docs-check public-hygiene
make verify-checksums
make sim-dry-run
make verilator-lint
make smoke
make regression
```

`sim-dry-run` reports the effective top, filelist, defines, latencies, and
runner command without starting a long simulation. `smoke` uses the selected
Profile's checked-in bounded image; `regression` runs only the explicit cases
in that Profile manifest.

## User program images

```sh
NPC_OPEN_IMAGE=/path/to/program.bin make sim
```

The runtime accepts raw binaries and word-oriented text images ending in
`.hex` or `.mem`. Sparse PMEM defaults to `0x80000000..0x8FFFFFFF`; a text
image may use `@<hex_addr>` to change its load address. An invalid image or an
address outside PMEM fails the run.

Optional environment inputs include:

| Variable | Purpose |
| --- | --- |
| `NPC_OPEN_IMAGE` | override the image in `.config` |
| `NPC_PUBLIC_MEM_BASE/LIMIT` | change the sparse PMEM range |
| `NPC_PUBLIC_TOHOST` | set a 32-bit tohost address; disabled by default |
| `VERILATOR` | select the Verilator executable |

These inputs do not change the ISA or microarchitecture identity.

## Default latencies

| Profile | IF latency | LSU latency | Memory latency |
| --- | ---: | ---: | ---: |
| `rv32im_single_perf` | 2 | 2 | 2 |
| `rv32ima_sv32_linux` | 0 | 0 | 0 |
| `rv32im_ooo_4k` | 2 | 3 | 2 |

These are public DPI transport settings, not ASIC SRAM timing or a direct
cache-hit latency. A configured value of zero still follows the clocked
ready/valid simulation protocol and must not be described as combinational
memory.

## Tracing and watchdog

All defconfigs disable VCD and itrace by default and use a 20,000,000-cycle
watchdog. Debug runs may explicitly enable:

- `CONFIG_NPC_VCD`, default path `build/waves/sim.vcd`;
- `CONFIG_NPC_ITRACE`, default path `build/traces/itrace.log`.

Tracing creates large files and reduces host simulation throughput, so it
should remain off for performance measurements. mtrace, ftrace, pmemtrace,
SDB, disassembly, and NVBoard are not part of the public runtime.

## Optional NEMU difftest

Default simulation does not need NEMU. A strict local check builds the
reference matching the selected Profile:

```sh
make rv32im_ooo_4k_defconfig
make difftest-prepare NPC_NEMU_SOURCE_REPO=/path/to/ysyx-workbench
make difftest
```

`difftest-prepare` extracts the matching NEMU tree from the workbench commit
locked by the manifest, builds a raw reference and MIT ABI adapter below
`flows/local/nemu/<profile>/`, and records their hashes. The directory is
ignored by Git.

Building NEMU also needs GNU Make, a C compiler, `libdl`, and the readline
development library. `make difftest` checks sidecar hashes, Profile, reset
vector, and image. Passing a raw NEMU `.so` directly fails closed.

The current adapter checks PC, instruction, and GPR state on every commit,
including two commits in an OoO cycle. It does not validate complete Linux
device/MMIO/interrupt equivalence; see [SoC integration](soc-integration.en.md).

## CoreMark

CoreMark uses a hash-locked manifest and requires both a binary and an ELF:

```sh
make rv32im_single_perf_defconfig
NPC_OPEN_COREMARK_IMAGE=/path/to/coremark.bin \
NPC_OPEN_COREMARK_ELF=/path/to/coremark.elf \
make coremark-difftest
```

`make coremark` leaves difftest off; `make coremark-difftest` uses the selected
Profile's local adapter. The runner validates input hashes and start/stop
markers, then reports timed, whole, pre/post, and CoreMark/MHz JSON counters.
OoO currently uses `make coremark` because reference ordering for a dual-retire
MMIO packet remains ambiguous. See
[CoreMark measurement evidence](evidence/coremark_reproduction.en.md).

## Output and Git cleanliness

Builds, traces, local NEMU files, and user outputs should stay in ignored
paths. After a run, check:

```sh
git status --short
```

A controlled fresh-clone test must not leave untracked files except correctly
ignored `.config`, `build/`, and `flows/local/` content.
