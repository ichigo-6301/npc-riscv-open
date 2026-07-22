# Performance and implementation data

[中文](performance.md)

This page follows the common processor-project pattern of comparing Profiles,
while keeping simulation CPI, CoreMark/MHz, synthesis frequency, and area as
separate metrics. Values cannot be derived from each other or combined across
Profiles, commits, binaries, or memory models.

## Evidence states

- `verified`: reproducible from fixed public inputs and configuration, with a
  public evidence ID.
- `provisional`: a historical fixed-private-commit record not yet reproduced
  with all inputs and conditions by the current public flow.
- `not_claimed`: deliberately excluded from current conclusions.
- `—`: no data meeting the requirements of that column.

## Current public reproduction

These are current headless-runtime results using external CoreMark binaries that
are not bundled in the repository. Their state is
`provisional_external_input`, not an architecture-level verified claim. The
runner's `PUBLIC_SIM_PASS` counters are used directly: `commit` for Single/Linux
and `commit + commit2` for OoO.

| Profile | CoreMark CPI | CoreMark/MHz | Seven-workload weighted CPI | Closed frequency | Area | State/evidence |
| --- | ---: | ---: | ---: | ---: | ---: | --- |
| `rv32im_single_perf` | 1.486003063 | — | — | — | — | `evidence:coremark_public_runtime` / `nonclaim:single_public_coremark_runtime_provisional` |
| `rv32ima_sv32_linux` | 1.742774400 | — | — | — | — | `evidence:coremark_public_runtime` / `nonclaim:linux_public_coremark_runtime_provisional` |
| `rv32im_ooo_4k` | 0.882378295 | — | — | — | — | `evidence:coremark_public_runtime` / `nonclaim:ooo_public_coremark_runtime_provisional` |

Single/OoO use an M-mode binary and Linux uses an S-mode Sv32 binary. Binary
hashes, source commits, latency, complete commands, and stop output are recorded
in [CoreMark runtime evidence](evidence/coremark_reproduction.en.md). Since the
binary inputs are external, these rows remain provisional. CoreMark/MHz,
seven-workload weighted CPI, frequency, and area cannot be derived from these CPI
values and remain `—`.

## Historical CoreMark CPI references

Every value below is `provisional`, not a current public verified claim:

| Profile | Cycles | Retired/committed instructions | CoreMark CPI | Conditions | Evidence / nonclaim |
| --- | ---: | ---: | ---: | --- | --- |
| `rv32im_single_perf` | 4,578,012 | 3,081,085 | 1.48 | RV32IM single issue, project-local Verilator/NEMU record; the public runtime produced a close but different external-input row | `nonclaim:single_public_cpi_not_yet_claimed` |
| `rv32ima_sv32_linux` | 5,613,732 | 3,252,492 | 1.725978726 (≈1.72) | Later optimized source snapshot `abf66cad`; private fixed `NPC_DCACHE_WRITE_ALLOCATE=0`, S-mode Sv32, ITLB/DTLB, hit pipelines, a 2-entry store buffer, fast MUL, and LSU load bypass | `evidence:linux_checkpoint_rerun` / `nonclaim:linux_public_cpi_not_yet_claimed` |
| `rv32im_ooo_4k` | 2,718,684 | 3,081,080 | 0.882380204 | RV32IM, IF/LSU/memory=`2/3/2`, seed 1, Verilator + NEMU difftest | `ooo_coremark_cpi_not_yet_claimed` |

CoreMark CPI is `cycles / retired instructions`. It is not CoreMark/MHz and
cannot be converted without the CoreMark score, iteration count, compiler
options, and implemented clock information.

### Linux Profile checkpoint comparison

The public Profile now locks the later optimized checkpoint
`abf66cad0f9ad02efc8beb641d4005adeaee0b`, so the main historical table uses
the private rerun value `1.725978726` (approximately `1.72`). The earlier
`e3a1cc91c4c00040f7180eec5e385326d9964893` result of approximately `1.98` is
retained as a prior-checkpoint comparison. These are different RTL snapshots;
the older value must not be relabeled as a result of the current source.

| Checkpoint | Source commit | Sv32 CoreMark CPI | Status |
| --- | --- | ---: | --- |
| Later optimized checkpoint | `abf66cad0f9ad02efc8beb641d4005adeaee0b` | 1.725978726 (≈1.72) | `evidence:linux_checkpoint_rerun` / `nonclaim:linux_public_cpi_not_yet_claimed` |
| Earlier frozen checkpoint | `e3a1cc91c4c00040f7180eec5e385326d9964893` | ≈1.98 | `linux_prior_checkpoint_cpi_not_claimed` |

The later-checkpoint row now has private exact binary/config/log hashes, but its
binary and complete build tree are not in the public repository, so it remains
`provisional` rather than a verified claim. The current public Linux row uses
`WRITE_ALLOCATE=1`, hence CPI `1.742774400` is not the same configuration as the
historical `1.725978726`. CoreMark/MHz, implementation frequency, and area remain
`—`/`not_claimed`.

## Historical multi-workload reference

| Profile | Workloads | Total cycles | Total retired instructions | Weighted CPI | Evidence / nonclaim |
| --- | --- | ---: | ---: | ---: | --- |
| `rv32im_ooo_4k` | CoreMark, matrix-mul, crc32, quick-sort, load-store, Dhrystone, microbench | 5,157,299 | 5,649,752 | 0.912836351 | `ooo_public_cpi_not_yet_claimed` |

This weighted CPI divides aggregate cycles by aggregate retired instructions
for one finite workload set. CoreMark itself has CPI `0.882380204`
(`ooo_coremark_cpi_not_yet_claimed`); the two metrics are not interchangeable,
and neither proves that every program runs below CPI 1.

## Historical synthesis reference

| Profile | Tool / target | Setup result | Frequency description | Cell area | State and limitation |
| --- | --- | --- | --- | ---: | --- |
| `rv32im_single_perf` | Design Compiler, 1.000 ns stress, Nangate45-family library setup | WNS ≈ -0.42 ns, TNS ≈ -4606.87 ns | arithmetic estimate near 704 MHz; 1 GHz did not close | 184926.124968 library units | `provisional`; `single_700mhz_closure_not_claimed`; `single_dc_area_not_claimed` |
| `rv32ima_sv32_linux` | — | — | — | — | `not_claimed` |
| `rv32im_ooo_4k` | — | — | — | — | `not_claimed` |

The approximately 704 MHz value is the historical arithmetic estimate
`1 / (1.000 ns + 0.42 ns)` (`single_700mhz_closure_not_claimed`), not a closed
maximum frequency. The area is the library cell-area value from that DC run
(`single_dc_area_not_claimed`). There is no public P&R, post-route parasitic,
SRAM signoff, power, IO, OCV/MMMC, or silicon correlation, and the number is
not comparable to another memory binding or tool setup.

## Requirements for filling empty cells

New data must record:

1. Profile ID, source commit, and configuration hash;
2. benchmark binary/ELF hash, compiler options, and retirement definition;
3. simulator, reference model, latency, seed, and trace/difftest state;
4. for frequency and area, the technology library, PVT, memory binding,
   constraints, WNS/TNS, and tool version;
5. a readable public evidence ID and fresh-clone reproduction command.

Cells remain `—` until all requirements are met. See [CoreMark runtime evidence](evidence/coremark_reproduction.en.md),
the [evidence policy](../evidence/README.md), and [limitations](limitations.en.md).
