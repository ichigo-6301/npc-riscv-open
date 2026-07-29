# NPC RISC-V Open documentation

[中文](README.md)

The project contains three independent processor RTL source sets and one
shared, headless Verilator environment. Profile manifests are the source of
truth for ISA, top module, wrapper, filelist, source commit, and default run
conditions.

## Profiles

| Profile | Architecture | Current public validation state |
| --- | --- | --- |
| `rv32im_single_perf` | Five-stage, single-issue RV32IM | source closure, regression, and hash-locked CoreMark+difftest verified |
| `rv32ima_sv32_linux` | Five-stage, single-issue RV32IMA M/S + Sv32 | source closure and bounded architecture regression are verified; the OpenSBI entrypoint remains `partial`; the `abf66cad` CoreMark+difftest row is historical; complete Linux is not claimed |
| `rv32im_ooo_4k` | Dual-issue, dual-commit RV32IM OoO | source closure and dual-width regression verified; CoreMark provisional at the dual-retire MMIO difftest boundary |

The three RTL sets are not one parameterized implementation. One build compiles
one source set, while the public wrappers normalize only commit, halt, and
debug observation.

## Technical documents

- [Architecture](architecture.en.md): pipelines, predictors, caches/TLBs, OoO
  resources, and interfaces.
- [Performance and implementation data](performance.en.md): public
  reproduction tables, historical references, and evidence states.
- [SoC integration](soc-integration.en.md): DPI, ACLINT, AXI reference devices,
  and the address map.
- [Simulation](simulation.en.md): Profile selection, images, tracing, and
  optional difftest.
- [Verification](verification.en.md): test scope, current results, and gaps.
- [Dual-memory ASIC implementation](asic-implementation.en.md): LC, DC,
  OpenROAD/OpenRCX, PrimeTime, and evidence gates.
- [Backend closure evidence](evidence/backend_closure.en.md): bounded evidence
  for the four Single/Linux fixed-frequency implementation points.
- [Limitations](limitations.en.md): unestablished feature, PPA, and system-level
  conclusions.
- [Roadmap](roadmap.en.md): unfinished work and maturity promotion gates by
  Profile.

Machine-readable source locks, Profile configurations, claims, nonclaims, and
evidence indexes live under `delivery/`, `provenance/`, and `evidence/`. Never
combine values from different Profiles, commits, binaries, or memory models.
