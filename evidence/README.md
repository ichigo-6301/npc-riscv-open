# Evidence policy

This directory is reserved for small, reviewable, Profile-scoped evidence.
Unreviewed benchmark logs, private workbench paths, PDKs, libraries, SRAM
views, and generated EDA databases do not belong here.

A measured value needs all of the following before it can be marked
`verified`:

- Profile ID and exact source commit;
- benchmark or implementation task and complete configuration;
- input binary, configuration, and result hashes where applicable;
- tool and version information;
- a readable result summary and reproduction command;
- a public evidence ID linked from the corresponding claim.

Values derived from private notes, remembered results, incomplete logs, or a
different host flow remain `provisional`. Future targets are `planned`; metrics
that the project intentionally does not assert are `not_claimed`.

CoreMark timed CPI, whole-program CPI, CoreMark/MHz, instruction-weighted
multi-workload aggregate CPI, clock frequency, cell area, physical area, and
power are distinct metrics. They must not be merged or compared without
matching workload, source, configuration, memory model, tool, and
implementation conditions.

`performance/coremark.json` is the bounded numeric source for the current
CoreMark table and Linux parity result. Single/Linux records are verified under
their fixed external-input contracts; the OoO record carries its own
provisional difftest boundary. Frequency, area, power, and absolute CoreMark
score remain empty until separate evidence satisfies this policy.

Historical, snapshot-scoped evidence is intentionally separate:

- `performance/linux_coremark_ab.json` records the approximate/partial Linux
  no-TLB-to-optimized comparison and current-source rerun boundary;
- `performance/ooo_coremark_history.json` records the historical S9A-to-P89
  CoreMark whole-program endpoints. The P89 endpoint is historical verified;
  the derived same-workload-family comparison remains partial because the S9A
  binary/config hashes are unavailable and the retired counts differ by 12;
- `performance/ooo_frontend_branch_ab.json` records pre-loop-remediation OoO
  frontend and branch-prediction experiments with explicit denominators;
- `verification/ooo_loop_remediation.json` records the separate D12 typed
  registered-ownership epoch. Yosys pre/post-techmap SCC `0/0` is historical
  verified because source-set `e5782d80dde8aceef10516f5cdaeab3fda8f21b5e4df051de39939da5002da12`
  is exactly recomputed from the public filelist and reconstruction. SpyGlass
  CombLoop `0` is report-only historical partial because its staged relative
  path context is unavailable; Verilator UNOPTFLAT `0` is log-only historical
  partial because no source-set binding was retained. Precise retirement is
  also partial aggregate reporting: the workload/profile enumeration and 14/14
  count are preserved, but per-point binary/config/trace/counter identity is
  not. It does not inherit P89 performance;
- `system/linux_boot.json` records bounded Linux 6.6.141 boot markers and
  source lineage without publishing the raw log;
- `fpga/single_xc7z100_history.json` records three Vivado snapshots across all
  eight FPGA maturity dimensions and rejects old-XSA promotion.

The corresponding OoO source lineage is recorded in
[`source_lineage.json`](../provenance/upstream/rv32im_ooo_4k/history/source_lineage.json).
The adjacent `p89_from_public_s9s.patch` and `d12_from_public_s9s.patch` files
rebuild the historical snapshots from the public S9S source; the two
`*_source_set.sha256` files bind the reconstructed role sets. See the bilingual
[OoO architecture and performance history](../docs/evidence/ooo_architecture_performance_history.en.md)
for the technical narrative and nonclaim boundary.

`implementation/nangate45_fixed_points.json` remains the bounded source for
the four Single/Linux academic fixed-frequency ASIC points. `make evidence-check`
validates all current, historical, FPGA, system, and implementation identities.
