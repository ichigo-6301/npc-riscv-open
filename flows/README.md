# Public flow control

`flows/scripts/flowctl.py` is the stable public dispatcher. It reads one checked-in
defconfig, validates the matching delivery profile and source set, and invokes the
shared Verilator runner. It does not select architecture parameters itself.

Host-specific program images and external reference adapters are supplied at run
time. Generated files stay below `build/`; local proprietary tool setup is not part
of this release.
