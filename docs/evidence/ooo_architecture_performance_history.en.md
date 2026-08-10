# OoO Architecture And Performance History

[中文](ooo_architecture_performance_history.md)

This page records the historical architecture evolution, CoreMark endpoints,
and later combinational-loop remediation of `rv32im_ooo_4k`. It does not merge
different source epochs into one implementation result. The machine-readable
sources are
[`ooo_coremark_history.json`](../../evidence/performance/ooo_coremark_history.json),
[`ooo_loop_remediation.json`](../../evidence/verification/ooo_loop_remediation.json),
and
[`source_lineage.json`](../../provenance/upstream/rv32im_ooo_4k/history/source_lineage.json).

## From Module Prototypes To A Dual-Width Elastic Pipeline

The OoO core first established precise-state and age semantics in module and
FSM prototypes, then advanced to an end-to-end pipeline:

1. Rename combines the RAT/RRAT, FreeList, and a 64-entry PRF. An 8-entry ROB
   preserves program order and commits precise state, while an 8-entry IQ
   selects ready entries by ROB age. ROB tags, generations, and recovery epochs
   reject stale completions that arrive after a flush.
2. The datapath progressively formed true IF2, Decode2/Rename2/Dispatch2,
   Issue2, Completion2/WB2, and Commit2. Explicit contracts cover slot 0/slot 1
   age, same-cycle RAW/WAW hazards, resource conflicts, and retained/replayed
   work; two same-cycle commits remain in program order.
3. ALU, BRU, LSU, and MDU units connect to the ROB through constrained
   dual-width issue and completion networks. Branch checkpoints, generations,
   and selective recovery invalidate only younger state. A load queue, precise
   store buffer, and store-to-load forwarding preserve memory and irreversible
   side-effect ordering.
4. S8 replaced whole-core FSM dependencies with ownership-bearing elastic
   stages. S9 then used lifecycle counters, lost-slot classification, and
   fixed-source A/B tests to attribute frontend, prediction/recovery,
   dispatch/issue, load/store, and completion/commit costs. A mechanism was
   retained only after functional, conservation, and directed-stress gates.

The corresponding public canonical RTL entrypoints are:

| Role | Code entrypoints | Reading focus |
| --- | --- | --- |
| Rename / PRF | [`ooo_rename_dispatch_recovery_2w.sv`](../../rtl/profiles/rv32im_ooo_4k/core/ooo_rename_dispatch_recovery_2w.sv), [`ooo_prf.sv`](../../rtl/profiles/rv32im_ooo_4k/core/ooo_prf.sv) | Dual rename, same-cycle dependencies, free-list management, and recovery snapshots |
| ROB / IQ | [`small_rob.sv`](../../rtl/profiles/rv32im_ooo_4k/core/small_rob.sv), [`alu_issue_queue_1w.sv`](../../rtl/profiles/rv32im_ooo_4k/core/alu_issue_queue_1w.sv) | In-order retirement, age selection, and completion-generation filtering |
| Issue / completion | [`ooo_issue_operand_elastic_2w.sv`](../../rtl/profiles/rv32im_ooo_4k/execute/ooo_issue_operand_elastic_2w.sv), [`ooo_pipeline_completion_fabric_2w.sv`](../../rtl/profiles/rv32im_ooo_4k/execute/ooo_pipeline_completion_fabric_2w.sv) | Retained/replay behavior, FU pairing, and dual completion |
| Recovery / LSU | [`ooo_branch_checkpoint_state_2w.sv`](../../rtl/profiles/rv32im_ooo_4k/core/ooo_branch_checkpoint_state_2w.sv), [`ooo_lsu_pipeline_1w.sv`](../../rtl/profiles/rv32im_ooo_4k/execute/ooo_lsu_pipeline_1w.sv), [`ooo_precise_store_buffer_4entry.sv`](../../rtl/profiles/rv32im_ooo_4k/execute/ooo_precise_store_buffer_4entry.sv) | Checkpoint/generation, LQ, STLF, and precise store ownership |

The public canonical source remains
`99fcc2be539eabb078c0d73b26a7ef2c00071391`. Historical code is not copied as
a second canonical RTL tree. Reversible patches and source-set digests rebuild
and verify P89 and D12 from that public snapshot. P89 is an ancestor of public
S9S; D12 is a historical fork snapshot, and no ancestry between P89 and D12 is
claimed:

- [P89 10-file reversible patch](../../provenance/upstream/rv32im_ooo_4k/history/p89_from_public_s9s.patch)
  and [P89 source-set SHA256](../../provenance/upstream/rv32im_ooo_4k/history/p89_source_set.sha256);
- [D12 27-file reversible patch](../../provenance/upstream/rv32im_ooo_4k/history/d12_from_public_s9s.patch)
  and [D12 source-set SHA256](../../provenance/upstream/rv32im_ooo_4k/history/d12_source_set.sha256);
- [D12 input-identity bundle](../../provenance/upstream/rv32im_ooo_4k/history/d12_input_bundle.json)
  binds the four parameter locks, 64 effective parameters, original filelist,
  and macro blackbox interface;
- [D12 functional-point inventory](../../provenance/upstream/rv32im_ooo_4k/history/d12_functional_identity_points.json)
  enumerates the 14 ideal/default points across seven workloads and states the
  missing per-point identity boundary.

## S9A-To-P89 CoreMark Endpoints

<!-- evidence:ooo_coremark_history_public -->
<!-- claim:ooo_historical_s9a_coremark_whole_cpi maturity:partial value:6.184799387499 epoch:pre_combinational_loop_remediation -->
<!-- claim:ooo_historical_p89_coremark_whole_cpi maturity:verified value:1.097794842231 epoch:pre_combinational_loop_remediation -->
<!-- claim:ooo_historical_coremark_approx_speedup maturity:partial value:5.633830352325 epoch:pre_combinational_loop_remediation -->

Both runs belong to the historical performance-first epoch before
combinational-loop remediation. They use the same `riscv32e-npc` CoreMark
workload family, an RV32E/Zicsr ILP32E binary, hardware `M_EXT=1`, default
`IF/LSU/memory=2/3/2`, seed 1, and difftest. The metric counts from reset
through program termination. It is whole-program CPI, not timed-region CPI or
ASIC implementation performance.

| Checkpoint | RTL source | Evidence ref | Cycles / retired instructions | Whole-program CPI | Maturity |
| --- | --- | --- | ---: | ---: | --- |
| S9A performance baseline | `7154e5a3d61fab18718a33f3fe2588891c1b291b` | `d7376dde` | 48,395,814 / 7,824,961 | 6.184799 | `partial` |
| P89 optimized endpoint | `0e1730b71b7c4ad699e919fc9404189a5e8729d6` | `3a947f18` | 8,590,215 / 7,824,973 | 1.097795 | `historical_verified` |

At equal clock, the same-workload-family whole-program cycle ratio is
`48,395,814 / 8,590,215 = 5.633830x`, summarized as `6.18 -> 1.10`
(`approximately 5.63x`). Because the endpoints differ by 12 retired
instructions, the CPI ratio differs by approximately `0.000009x`; the `5.63x`
figure is therefore explicitly derived from total cycles, not from the CPI
ratio. The comparison remains `partial` for three reasons: neither the original
S9A binary hash nor its configuration hash was retained, and the endpoints
differ by 12 retired instructions. The IF/LSU/memory latency, seed, and difftest
settings come from tracked historical documentation rather than a hash-locked
S9A configuration. This is therefore not a hash-identical binary/config A/B and
cannot be promoted to a strict current-source performance claim. The P89
endpoint itself retains its binary/config hashes, counters, and source identity,
so that endpoint is `historical_verified`. Enabled measurement Oracles only
produce observations; they do not drive production ready/valid, arbitration,
or state updates.

The S9A counters come from
`d7376dde:npc/docs/perf/s9a_pipeline_performance_baseline.md`. P89 acceptance,
manifest, and summary records are fixed by `3a947f18`. The public JSON retains
only sanitized logical paths, identities, and hashes; raw private logs are not
published.

The reduction was not one parameter change. S9A counters first exposed
frontend starvation and branch-recovery cost. Fixed-input iterations then
retained continuous fetch, BTB/BHT/RAS, same-cycle dependency forwarding, and
dispatch/issue paths. Later attribution targeted load/store transaction
ownership, completion/wakeup, and empty second commit slots. P89 finally added
a guarded third tagged load-transaction owner while preserving store admission,
AMO exclusion, tag/generation/recovery-epoch matching, and response
backpressure.

## D12 Registered-Ownership Remediation

<!-- evidence:ooo_loop_remediation_public -->
<!-- claim:ooo_historical_comb_loop_zero maturity:verified value:0 epoch:d12_registered_causal_ownership -->
<!-- claim:ooo_historical_unoptflat_zero maturity:verified value:0 epoch:d12_registered_causal_ownership -->
<!-- claim:ooo_historical_pre_techmap_scc_zero maturity:verified value:0 epoch:d12_registered_causal_ownership -->
<!-- claim:ooo_historical_post_techmap_scc_zero maturity:verified value:0 epoch:d12_registered_causal_ownership -->
<!-- claim:ooo_historical_precise_retirement_preserved maturity:partial value:true epoch:d12_registered_causal_ownership -->

A passing performance-first simulation proves architectural behavior for that
simulation schedule; it does not prove that the combinational dependency graph
is acyclic. In the separate D12 source epoch
`a8f689cc00213859fb6893b31b65ef5cb3cbd7eb`, typed registered ownership
refactors the Issue/WB/Commit and LSU boundaries:

- typed ROB outcomes and retire owners freeze instruction class and retirement
  decisions;
- depth-3 memory request/response owners make accepted transactions durable and
  drain killed reads by token;
- typed completion owners and a registered dual-width service arbiter isolate
  FU permission from downstream ready;
- a persistent recovery token separates recovery, RAS preview, and irreversible
  side effects from live backpressure.

Identity-matched structural gates report SpyGlass CombLoop `0`, Verilator
UNOPTFLAT `0`, and Yosys pre/post-techmap SCC `0/0`; these four structural
results are `historical_verified`. The historical report also records 14/14
ideal/default points across seven workloads and zero protocol, lifecycle, and
conservation errors. Reachable Git evidence does not retain per-point
binary/config hashes, normalized trace digests, cycles, or retired
instructions, so precise-retirement preservation is only an aggregate-reported
`partial` result. D12 does not inherit P89's `1.097795` CPI and is not a rerun
of the public canonical source.

## Claim Boundary And Nonclaims

- Supported: historical same-workload-family CoreMark whole-program CPI of
  approximately `6.18 -> 1.10`, with an equal-clock whole-program cycle ratio
  of approximately `5.63x`; the comparison remains
  `partial` and the P89 endpoint marked `historical_verified`.
- Supported: a separate D12 source epoch completed registered Issue/WB/Commit
  and LSU ownership; all four loop/SCC counts across the three structural tools
  are zero. Precise retirement is an aggregate-reported 14/14 `partial` result,
  not a claim of independently replayable per-point identity.
- Not permitted: presenting P89 CPI as performance of the current acyclic RTL,
  public canonical source, FPGA, or ASIC implementation.
- Not permitted: claiming a D12 or current-OoO DC closure point, area, P&R, STA,
  Fmax, power, or signoff result. This evidence establishes none of them.

Independent historical frontend-empty and redirect measurements are documented
in [Historical Architecture And Performance Evidence](performance_history.en.md).
