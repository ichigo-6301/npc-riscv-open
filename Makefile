SELF_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
# In the private workbench this file lives in npc/open/control; the exporter
# places the same file at the public repository root.  Resolve both layouts
# without relying on the caller's working directory.
ifeq ($(wildcard $(SELF_DIR)/configs),)
ROOT := $(abspath $(SELF_DIR)/..)
KCONFIG_FILE := $(SELF_DIR)/Kconfig
else
ROOT := $(SELF_DIR)
KCONFIG_FILE := $(ROOT)/Kconfig
endif
CONFIG ?= $(ROOT)/.config
DEFCONFIG ?= configs/rv32im_ooo_4k_defconfig
PYTHON ?= python3
FLOWCTL := $(PYTHON) "$(ROOT)/flows/scripts/flowctl.py" --root "$(ROOT)" --config "$(CONFIG)"

-include $(CONFIG)

.DEFAULT_GOAL := help
.PHONY: help defconfig rv32im_single_perf_defconfig rv32ima_sv32_linux_defconfig \
        rv32im_ooo_4k_defconfig menuconfig showconfig config-check source-check \
        public-hygiene sim-dry-run verilator-lint sim smoke regression difftest difftest-prepare \
        opensbi-smoke runtime-tests docs-check verify-checksums ci

help:
	@printf '%s\n' \
	  'NPC RISC-V public multi-profile project' \
	  '' \
	  '  make defconfig                         Select the dual-issue default' \
	  '  make <profile>_defconfig               Select one declared profile' \
	  '  make showconfig                         Print stable effective values' \
	  '  make config-check source-check         Validate profile and source closure' \
	  '  make public-hygiene                     Scan the public tree' \
	  '  make sim-dry-run / verilator-lint       Inspect or lint the selected profile' \
	  '  make smoke / regression                 Run bounded public tests' \
	  '  make difftest-prepare                   Build ignored profile-matched NEMU adapters' \
	  '  make difftest                            Run strict difftest using the local adapter' \
	  '  make runtime-tests                       Run dependency-free control-plane tests' \
	  '  make docs-check                           Validate bilingual docs and metric references' \
	  '  make verify-checksums                     Verify the exported SHA256 manifest' \
	  '' \
	  'Only profile manifests select RTL, ISA, and memory topology.'

defconfig:
	@$(FLOWCTL) defconfig --source "$(ROOT)/$(DEFCONFIG)"

rv32im_single_perf_defconfig:
	@$(FLOWCTL) defconfig --source "$(ROOT)/configs/rv32im_single_perf_defconfig"

rv32ima_sv32_linux_defconfig:
	@$(FLOWCTL) defconfig --source "$(ROOT)/configs/rv32ima_sv32_linux_defconfig"

rv32im_ooo_4k_defconfig:
	@$(FLOWCTL) defconfig --source "$(ROOT)/configs/rv32im_ooo_4k_defconfig"

menuconfig:
	@test -f "$(CONFIG)" || $(MAKE) defconfig
	@command -v "$${KCONFIG_MCONF:-mconf}" >/dev/null 2>&1 || { \
	  echo 'Kconfig frontend not found; use a checked-in defconfig or set KCONFIG_MCONF.'; exit 2; \
	}
	@KCONFIG_CONFIG="$(CONFIG)" "$${KCONFIG_MCONF:-mconf}" "$(KCONFIG_FILE)"

showconfig:
	@$(FLOWCTL) show-config

config-check:
	@$(FLOWCTL) config-check

source-check:
	@$(FLOWCTL) source-check

public-hygiene:
	@$(FLOWCTL) hygiene

sim-dry-run:
	@$(FLOWCTL) sim --dry-run

verilator-lint:
	@$(FLOWCTL) lint

sim:
	@$(FLOWCTL) sim

smoke:
	@$(FLOWCTL) smoke

regression:
	@$(FLOWCTL) regression

difftest:
	@$(FLOWCTL) difftest

difftest-prepare:
	@$(FLOWCTL) difftest-prepare $(DIFFTEST_PREPARE_ARGS)

opensbi-smoke:
	@$(FLOWCTL) opensbi-smoke

runtime-tests:
	@$(PYTHON) -m unittest discover -s "$(ROOT)/tests" -p 'test_*.py'

docs-check:
	@$(PYTHON) "$(ROOT)/flows/scripts/check_docs.py" --root "$(ROOT)"

verify-checksums:
	@cd "$(ROOT)" && sha256sum --check SHA256SUMS

ci: verify-checksums docs-check runtime-tests config-check source-check public-hygiene verilator-lint smoke regression
