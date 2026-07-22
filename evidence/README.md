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

CoreMark CPI, CoreMark/MHz, multi-workload weighted CPI, clock frequency, cell
area, physical area, and power are distinct metrics. They must not be merged or
compared without matching workload, source, configuration, memory model, tool,
and implementation conditions.

The current performance page lists historical references only to make known
data and gaps visible. The public reproduction cells remain empty until this
directory contains the required evidence.
