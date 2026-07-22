# RC1 validation record

This record describes the bounded validation scope of
`npc-riscv-open-v0.1.0-rc1`. It is intentionally separate from performance
claims and does not include private benchmark evidence.

## Exact checks

From a fresh native-Linux clone, the following were run for each profile:

```text
make <profile>_defconfig
make showconfig config-check source-check public-hygiene
make verilator-lint smoke regression
```

The run also verified `SHA256SUMS`, the runtime unit tests (4 tests), and a
clean Git status after the ignored `.config` and `build/` outputs were created.
The normal release matrix keeps difftest disabled. A strict local matrix may
first run `make difftest-prepare` against the exact workbench source repository;
the resulting NEMU source, raw `.so`, adapter, and logs remain under ignored
`flows/local/` and are never part of the public commit.

## Bounded results

| Profile | Images | Observed result |
| --- | --- | --- |
| `rv32im_single_perf` | `smoke.hex` | `PUBLIC_SIM_PASS`, 269 cycles, 27 commits |
| `rv32ima_sv32_linux` | `smoke.hex`, `arch_smoke.hex` | `PUBLIC_SIM_PASS`, 162/27 and 80/15 |
| `rv32im_ooo_4k` | `smoke.hex` | `PUBLIC_SIM_PASS`, 107 cycles, 21 lane-0 commits, 5 lane-1 commits |

## Local strict difftest record

Using the profile-locked NEMU trees in
`delivery/difftest/nemu_profiles.json`, the ignored local adapters reproduced
all bounded results with difftest enabled:

| Profile | Image | Difftest result |
| --- | --- | --- |
| `rv32im_single_perf` | `smoke.hex` | PASS, 269 cycles / 27 commits |
| `rv32ima_sv32_linux` | `smoke.hex` | PASS, 162 cycles / 27 commits |
| `rv32ima_sv32_linux` | `arch_smoke.hex` | PASS, 80 cycles / 15 commits |
| `rv32im_ooo_4k` | `smoke.hex` | PASS, 107 cycles / 21 lane-0 + 5 lane-1 commits |

The frozen OoO debug shadow seeds untouched GPRs with their register index as
a bring-up sentinel.  The adapter therefore compares every committed register
write plus PC/instruction flow, while ignoring only untouched debug sentinel
values.  The single-issue profiles expose architectural zero reset values and
compare all 32 GPRs on every valid snapshot.

The locked RTL source hashes and profile manifests are the authoritative
identity checks. The upstream OoO release manifest in this repository is a
config-only sanitized view; private performance tables and claims are not
exported.

## Deliberately incomplete gates

CoreMark and OoO fixed-tail binaries are external AM-derived fixtures and are
not redistributed. The Linux/OpenSBI image is also external and no repository-
owned S-mode payload is included in RC1. Architectural commit-trace identity,
ASIC synthesis, PPA, timing, and physical signoff remain unclaimed until their
inputs and evidence are independently published. The local adapter is a
bounded GPR/PC checker; Linux device, timer-interrupt, and full MMIO equivalence
require a future profile-specific extension.
