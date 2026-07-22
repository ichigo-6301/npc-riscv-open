# Profile-matched NEMU difftest

The public repository does not bundle NEMU source or shared objects.  The
profile table in `nemu_profiles.json` locks the workbench commit and NEMU tree
used for each reference:

```text
make difftest-prepare NPC_NEMU_SOURCE_REPO=/path/to/ysyx-workbench
make <profile>_defconfig
make difftest
```

The preparation command extracts only the `nemu` subtree into the ignored
`flows/local/nemu/<profile>/` directory, builds a trace-free `SHARE=1`
interpreter, and places a small MIT adapter beside it.  The adapter checks the
profile, image, reset vector, instruction bytes, GPRs and PC at every bounded
commit.  `make difftest` verifies the local sidecar hashes before loading it;
passing a raw NEMU `.so` directly is intentionally rejected by the public ABI.

The generated references use zero-initialized static PMEM, RV32, and no device
or trace/file service.  Linux device, timer-interrupt, and full MMIO equivalence
remain a separate future contract.  All generated sources, configs, logs and
libraries are ignored and must not be copied into a public commit.  Building
the historical NEMU SDB objects also requires the host `readline` development
library (and `libdl`); the preparation script supplies those link flags
explicitly.
