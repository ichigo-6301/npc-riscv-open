# Release limitations and nonclaims

This document is deliberately conservative. An item listed here may become a
claim only after a profile-specific source reference, configuration, raw log,
hash and fresh-clone reproduction are recorded.

The Linux profile's RC1 public wrapper is a CPU-only headless boundary. It does
not bundle OpenSBI, a Linux kernel, a DTB, NEMU, or a board/MMIO integration.
`opensbi-smoke` therefore requires an external firmware image and remains an
optional bounded gate. The checked-in Linux regression image covers RV32IMA
machine-mode LR/SC and CSR behavior; it must not be read as proof of full Sv32
translation or Linux boot.

The public DPI service models deterministic sparse PMEM, RTC/UART hooks,
tohost, pair fetch, and tagged responses with profile-selected IF/LSU/memory
latencies. It is a release runtime contract, not a silicon memory model.

- The three profiles are not promised to be RTL-compatible internally. Their
  native top modules and source sets are selected independently.
- No ASIC synthesis, place-and-route, extracted timing, silicon frequency,
  PPA, SRAM macro signoff or foundry result is established by the public flow.
- Historical register-expanded and macro experiments remain provenance only;
  they do not automatically establish a release Fmax or a closed timing point.
- The Linux profile provides a bounded Sv32/firmware integration entrypoint.
  Full kernel distribution, boot-time services and a particular board platform
  are outside the RC1 acceptance boundary.
- External reference adapters, firmware, benchmark binaries and toolchains are
  not redistributed. Their exact version and hash must be recorded by each run.
- The upstream OoO release manifest is exported as a config-only provenance
  view. Its mechanism list, disabled Oracles, capacities and source identity are
  retained, while private performance, verification evidence and claims are
  removed. Public claims are governed only by `delivery/claims`.
- Tracing and waveform options are debug aids, not performance measurements.
  Default release runs keep heavyweight file-producing traces disabled.
- The public source tree is headless and does not provide board peripherals or
  a graphical board harness. Memory and MMIO behavior must be supplied by the
  selected profile adapter.
- The frozen profile RTL is exported byte-for-byte from its locked Git blobs.
  A few inherited upstream files contain trailing whitespace; the exporter
  preserves those bytes so the recorded SHA256 source lock remains valid.
  Formatting checks therefore apply to the public control plane separately and
  do not silently rewrite locked RTL.
- A generic-secret inventory scan may flag identifiers such as
  `mem_req_token`/`mem_rsp_token` in the OoO RTL. These are typed transaction
  protocol fields, contain no credentials, and are retained by the source lock;
  the public hygiene gate separately confirms that no secret-like value exists.
- A process exit code alone is not evidence of architectural correctness;
  smoke markers, trap status, instruction counts and conservation checks must
  be retained in the evidence record.

The `delivery/claims` and `delivery/nonclaims` manifests are authoritative when
they are more restrictive than this prose.
