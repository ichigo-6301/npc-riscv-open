# Flow control

`flows/scripts/flowctl.py` is the stable dispatcher shared by the three
Profiles. It reads one checked-in defconfig, validates the matching Profile and
source-set contracts, and invokes the headless Verilator runner. Architecture
parameters are fixed by the selected Profile; the dispatcher does not invent
or silently override them.

Common entry points are:

```sh
make <profile>_defconfig
make showconfig
make config-check source-check docs-check public-hygiene
make sim-dry-run
make verilator-lint
make smoke
make regression
```

Program images, watchdog limits, random seeds, tracing, and optional external
reference adapters are run inputs. Generated files stay below ignored
directories such as `build/` and `flows/local/`.

The checked-in configuration keeps difftest and file-producing traces off.
`make difftest-prepare` builds a local, Profile-matched NEMU adapter when the
operator supplies the corresponding workbench source. That local dependency is
not copied into the repository.

Commercial EDA setup, PDKs, libraries, memory macros, credentials, and host
absolute paths are outside this control plane.
