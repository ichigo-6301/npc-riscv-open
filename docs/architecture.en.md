# Architecture

[中文](architecture.md)

## Design organization

The repository uses one project with three independent RTL source sets. Each
Profile locks its native top, filelist, macros, and source commit. Public
wrappers normalize only retirement, halt, and register observation into at
most two commit packets. Shared infrastructure does not make the three
microarchitectures interchangeable through one parameter.

## Profile overview

| Feature | `rv32im_single_perf` | `rv32ima_sv32_linux` | `rv32im_ooo_4k` |
| --- | --- | --- | --- |
| ISA | RV32IM | RV32IMA | RV32IM |
| ABI | ilp32 | ilp32 | ilp32 |
| Privilege | M | M and S | M |
| Translation | none | Sv32; 16-entry ITLB + 16-entry DTLB | none |
| Execution model | 5-stage in-order | 5-stage in-order | out-of-order |
| Dispatch / issue / commit | 1 / 1 / 1 | 1 / 1 / 1 | 2 / 2 / 2 |
| Architectural / physical registers | 32 / not applicable | 32 / not applicable | 32 / 64 |
| ROB / IQ | not applicable | not applicable | 8 / 8 |
| Branch recovery | pipeline flush | precise trap/redirect + pipeline flush | 2-entry branch checkpoint + tag/generation recovery |
| Branch prediction | 128-entry BTB/PHT | 128-entry BTB + 128-entry BHT | 256-entry correlated conditional predictor, BTB/RAS, target storage |
| Instruction side | 4 KiB, 2-way, 64 B-line I-cache | 4 KiB, 2-way, 64 B-line I-cache | 512 × 64-bit, 1-way instruction-pair storage; 4 KiB payload |
| Data side | 4 KiB, 2-way, 64 B-line D-cache | 4 KiB, 2-way, 64 B-line D-cache | 1024 × 32-bit, 1-way physically tagged word cache; 4 KiB payload |
| Atomic extension | none | LR/SC/AMO, RV32A | none |
| Timer | public DPI legacy RTC | RTL `AclintTimer`, MTIP, and CSR time view | public DPI legacy RTC |
| Public simulation memory binding | behavioral DPI | behavioral DPI | tagged/pair behavioral DPI |

Cache sizes above count data payload only; tags, valid/dirty/LRU bits, and
control state are excluded. The two 4 KiB OoO structures do not have the same
organization as the 64-byte-line caches in the in-order cores.

## `rv32im_single_perf`

The Profile is a five-stage in-order pipeline:

```text
Fetch -> Decode -> Execute -> Memory -> Writeback/Commit
```

- At most one instruction is issued and committed per cycle.
- Thirty-two architectural integer registers and RV32M multiply/divide paths.
- Each I/D cache has 64 lines of 64 B, 2 ways, 32 sets, and 4 KiB payload.
- The frontend has a 128-entry BTB and 128 two-bit conditional counters.
- The native RTL retains AXI ports, while the public headless configuration
  selects its internal DPI memory bridge and ties unused AXI inputs static.

Source identity: `f76de57479b798aca7468f999c386bb4cb5fce02`.

## `rv32ima_sv32_linux`

This Profile adds privilege, translation, and system paths to the five-stage
in-order core:

```text
Fetch/ITLB -> Decode -> Execute -> Memory/DTLB -> Writeback/Commit
                  \-> trap, CSR, and redirect control
```

- M/S modes, Sv32, RV32A, and machine timer interrupts.
- 16-entry ITLB and DTLB; 4 KiB, 2-way, 64 B-line I/D caches.
- A two-entry store buffer, load bypass, hit pipelines, and a two-cycle fast
  multiplier are enabled.
- Branch prediction uses a 128-entry BTB, a 128-entry BHT, and an 8-bit
  history configuration; the selected source set does not enable gshare.
- RTL `AclintTimer` provides memory-mapped `mtime/mtimecmp`, MTIP, and the time
  source observed through CSR `time/timeh`.
- OpenSBI, Linux images, DTBs, and NEMU remain external inputs.

Source identity: `abf66cad0f9ad02efc8beb641d4005adeaeeae0b`.

This snapshot uses the later structured RTL layout, with CSR, frontend, LSU,
MMU, pipeline, statistic, and top-glue directories separated explicitly. It
is a source refactor that preserves the wrapper ABI and architectural boundary;
the public build still compiles only this Profile's isolated filelist.

## `rv32im_ooo_4k`

The Profile uses an out-of-order backend with this conceptual data flow:

```text
FetchDelivery -> Decode -> Rename/Dispatch -> IQ/Issue
              -> Execute/Raw -> Complete/Final -> ROB Commit
```

These names are ownership boundaries, not a promise that every box is exactly
one cycle. Key properties are:

- Up to two dispatches, issues, completions, and commits per cycle.
- A 64-entry PRF, 8-entry ROB, 8-entry IQ, and two branch checkpoints.
- Several FUs share constrained dual-width issue and completion channels;
  width two does not make every pair legal.
- ROB tags, generations, and recovery epochs reject stale completions after a
  flush.
- The 512-entry, 64-bit instruction-pair structure is 1-way, pair-oriented
  tagged storage rather than a conventional I-cache.
- The 1024-entry, 32-bit physically tagged word cache serves data-hit paths
  without a 64 B cache-line organization.
- A correlated conditional predictor, BTB/RAS, two checkpoints, and selective
  recovery cooperate on control flow.
- The public wrapper fixes 47 accepted mechanisms on and all 17 measurement
  Oracles off.

Source identity: `99fcc2be539eabb078c0d73b26a7ef2c00071391`.

## Public wrapper ABI

All wrappers export:

- lane 0 and lane 1 `valid/pc/instr/nextpc` commit packets;
- halt reason and location;
- architectural PC and indexed access to all 32 GPRs.

Single-issue Profiles tie lane 1 invalid. The OoO Profile preserves program
order for two commits in the same cycle. This ABI serves the runner and
optional difftest adapter; it does not imply internal pipeline compatibility.

See also [SoC integration](soc-integration.en.md),
[Simulation](simulation.en.md), and [Limitations](limitations.en.md).
