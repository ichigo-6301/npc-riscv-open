# Reproduction guide

The commands below are intentionally bounded and work from a fresh Linux clone.
Use Python 3.8 or newer, GNU Make and Verilator 5.x. PyYAML is required for
reading the delivery manifests:

```sh
python3 -m pip install --user PyYAML
make rv32im_ooo_4k_defconfig
make showconfig
make config-check
make source-check
make public-hygiene
```

The source and wrapper checks run before any simulator build. `make smoke` uses
the checked-in `tests/<profile>/smoke.hex`; `make regression` uses the explicit
profile `regression.json` list. A different program image is an
external input and should be supplied without committing it:

```sh
make smoke
NPC_OPEN_IMAGE=/path/to/program.bin make sim
make sim-dry-run
```

The profile-specific commands are:

```sh
make rv32im_single_perf_defconfig
make rv32ima_sv32_linux_defconfig
make rv32im_ooo_4k_defconfig
```

Differential testing is disabled by every checked-in defconfig and requires an
explicit local preparation step.  The preparation script takes the exact NEMU
tree recorded for the selected profile from a workbench checkout, builds a
`SHARE=1` interpreter, and writes both the raw reference and a MIT adapter under
the ignored `flows/local/nemu/<profile>/` directory:

```sh
make difftest-prepare NPC_NEMU_SOURCE_REPO=/path/to/ysyx-workbench
make rv32im_ooo_4k_defconfig
make difftest
```

`make difftest` verifies the sidecar hashes and automatically selects the
profile-matched adapter.  To use a separately built adapter, set
`NPC_OPEN_REFERENCE_SO=/path/to/npc-public-nemu-adapter.so`.  The adapter must
export `npc_public_difftest_init_v2`, `npc_public_difftest_step`, and
`npc_public_difftest_fini` with the signatures in
`sim/include/profile_abi.hpp`; a raw NEMU library fails closed.  NEMU source,
raw `.so` files, adapters, and generated configs are local ignored artifacts,
not release files.  The bundled reference is configured with tracing,
mtrace/ftrace, and device file output disabled; full Linux interrupt/MMIO
difftest remains outside this bounded RC1 contract.

The local preparation host also needs a C compiler, GNU Make, and the
`readline` development library because the frozen NEMU source retains its SDB
objects in the `SHARE=1` link.

A bounded Linux firmware smoke uses
`NPC_OPEN_OPENSBI_IMAGE=/path/to/firmware.bin make opensbi-smoke`.

Build output, traces and waveforms are ignored under `build/`; after a smoke
run a fresh clone must remain clean apart from those ignored files. Record the
profile, source commit, image hash, command line and result hash in the
corresponding evidence entry before making a public performance statement.

## CI-equivalent checks

```sh
make config-check source-check public-hygiene
make verilator-lint
make sim-dry-run
```

`make smoke` and `make regression` require the profile's public test images.
They fail closed when a required image or manifest is absent; they do not
silently substitute a different profile or private worktree.

## RC1 bounded fresh-clone record

The release candidate was checked from a native-Linux clone with Python 3.10,
GNU Make, Verilator 5.008, seed 1, and no file-producing trace. The bounded
results were deterministic: `rv32im_single_perf` smoke 269 cycles/27 commits;
`rv32ima_sv32_linux` smoke 162 cycles/27 commits and architecture smoke 80
cycles/15 commits; `rv32im_ooo_4k` smoke 107 cycles/21 commits with 5 second-lane
commits. These numbers validate the public wrappers and runtime only. They are
not CoreMark, Linux-boot, PPA, timing, or public CPI claims.
