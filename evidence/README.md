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
