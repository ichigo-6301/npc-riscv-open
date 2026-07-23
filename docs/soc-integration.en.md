# SoC integration

[中文](soc-integration.md)

The repository currently provides CPU RTL, Profile wrappers, and a headless
Verilator runtime, not a complete synthesizable SoC. This document separates
four commonly confused layers:

1. **CPU RTL**: modules instantiated inside a processor Profile;
2. **public DPI runtime**: C++ memory/MMIO services used only by headless
   simulation;
3. **NEMU/AM reference platform**: device models used for software and
   reference-model alignment;
4. **future synthesizable SoC**: interconnect, peripherals, and top-level
   integration that require separate implementation and validation.

## State definitions

| State | Meaning |
| --- | --- |
| `RTL-integrated` | the device or function is instantiated in the Profile RTL |
| `runtime-only` | handled only by the public Verilator C++ runtime, not synthesizable RTL |
| `reference-only` | present only in the NEMU/AM reference environment |
| `not integrated` | absent from the current Profile |
| `not tested` | an entry point exists, but public validation does not cover its full behavior |

## Current component matrix

| Component | `rv32im_single_perf` | `rv32ima_sv32_linux` | `rv32im_ooo_4k` | Notes |
| --- | --- | --- | --- | --- |
| CPU core | `RTL-integrated` | `RTL-integrated` | `RTL-integrated` | three independent source sets |
| Sparse PMEM / image loader | `runtime-only` | `runtime-only` | `runtime-only` | public DPI runtime |
| Legacy serial TX | `runtime-only` | `runtime-only` | `runtime-only` | write `0xA00003F8` to print a byte |
| Legacy RTC | `runtime-only` | `runtime-only` | `runtime-only` | `0xA0000048/4C` returns simulation ticks |
| ACLINT `mtime/mtimecmp` + MTIP | `not integrated` | `RTL-integrated` | `not integrated` | Linux Profile `AclintTimer` |
| AXI Timer | `runtime-only` | `runtime-only` | `runtime-only` | deterministic C++ model; NEMU/AM also has a reference model |
| AXI UARTLite | `runtime-only` | `runtime-only` | `runtime-only` | deterministic C++ TX/status; NEMU/AM also has a reference model |
| AXI INTC | `reference-only` | `reference-only` | `reference-only` | NEMU device; currently one UART interrupt input |
| tohost stop/pass | `runtime-only` | `runtime-only` | `runtime-only` | active only when a runtime address is configured |
| Board display, keyboard, GPIO | `not integrated` | `not integrated` | `not integrated` | NVBoard and board tops are absent |

`runtime-only` does not mean that the CPU wrapper instantiates synthesizable AXI
IP. The public Timer/UARTLite implementation provides only deterministic
simulation semantics needed by CoreMark and bounded software. NEMU/AM retains
separate `reference-only` device models; cycle-exact equivalence is not claimed.

## Address map

| Address range | Name | Key registers | Current owner |
| --- | --- | --- | --- |
| `0xA0000000..0xA000001F` | AXI Timer | TCSR0 `+0x00`, TLR0 `+0x04`, TCR0 `+0x08`, TCSR1 `+0x10`, TLR1 `+0x14`, TCR1 `+0x18` | public DPI `runtime-only`; NEMU/AM `reference-only` |
| `0xA0000048..0xA000004F` | Legacy RTC | low `+0x0`, high `+0x4` | public DPI `runtime-only` |
| `0xA00003F8` | Legacy serial TX | low byte | public DPI `runtime-only` |
| `0xA0010000..0xA001000F` | AXI UARTLite | RX `+0x0`, TX `+0x4`, status `+0x8`, control `+0xC` | public DPI `runtime-only`; NEMU `reference-only` |
| `0xA0020000..0xA0020007` | ACLINT `mtime` | 64-bit low/high words | Linux RTL; NEMU also has a reference model |
| `0xA0030000..0xA0030007` | ACLINT `mtimecmp` | 64-bit low/high words | Linux RTL; NEMU also has a reference model |
| `0xA0040000..0xA0040FFF` | AXI INTC | ISR/IPR/IER/IAR/SIE/CIE/IVR/MER at `+0x00..0x1C` | NEMU `reference-only` |

AXI Timer and Legacy RTC occupy different offsets in the same
`0xA0000000`-based platform region and have different register semantics.
Software must use the AM header, DTB, and device model matching its target; the
two timers are not interchangeable.

## ACLINT, CSRs, and counters

The clock block that appears both peripheral-like and CSR-visible in the Linux
Profile has this boundary:

- `mtime` and `mtimecmp` are memory-mapped 64-bit registers;
- `AclintTimer` advances `mtime` according to `CLK_HZ/TIMEBASE_HZ`;
- `mtime >= mtimecmp` asserts the machine timer interrupt pending condition;
- CSR `time` (`0xC01`) and `timeh` (`0xC81`) observe `mtime`;
- CSR `cycle/cycleh` and `instret/instreth` are independent counters, not
  aliases of `mtime/mtimecmp`.

ACLINT is therefore an MMIO timer peripheral in RTL, while the CSR file
provides a time view and separate execution/retirement counters.

## CPU memory-interface boundary

- The native tops of both in-order Profiles expose separate instruction and
  data AXI master ports. The public filelists select `NPC_USE_DPI`, so the
  headless wrappers tie AXI response inputs static and use the internal DPI
  bridges for memory traffic.
- The public OoO configuration uses pair-fetch and tagged-data DPI transports;
  it currently has no standard AXI SoC wrapper.
- The public commit ABI is a verification interface, not a bus protocol. It
  does not replace memory-ordering, interrupt, or DMA validation.

A synthesizable SoC needs a Profile-specific adapter with explicit clock and
reset, AXI outstanding behavior, cacheable/uncached regions, interrupt routing,
timer frequency, DTB, and software headers, followed by system-level tests.
The C++ DPI service must not be treated as synthesizable, and a NEMU device
model must not be described as an RTL peripheral.

## Difftest boundary

The current local NEMU adapter is a bounded GPR/PC/commit checker. Single-retire
Profiles use deterministic skip-and-sync for exact Legacy RTC, AXI Timer, and
UARTLite loads/stores; unknown MMIO, PMEM side effects, or dual-retire ambiguity
fail. It does not check cycle-exact device equivalence, ACLINT ticks, AXI INTC,
complete interrupt timing, or arbitrary MMIO side effects.

See [Architecture](architecture.en.md),
[Verification](verification.en.md), and [Limitations](limitations.en.md).
