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
ASICCTL := $(PYTHON) "$(ROOT)/flows/scripts/asicctl.py" --root "$(ROOT)" --config "$(CONFIG)"
ASIC_OOO_MODE ?= auto
ASIC_MEMORY_MODE ?= auto
ASIC_LC_ARGS ?=

-include $(CONFIG)

.DEFAULT_GOAL := help
.PHONY: help defconfig rv32im_single_perf_defconfig rv32ima_sv32_linux_defconfig \
        rv32im_ooo_4k_defconfig rv32im_single_perf_asic_defconfig \
        rv32im_single_perf_sram_asic_defconfig \
        rv32ima_sv32_linux_asic_defconfig rv32ima_sv32_linux_sram_asic_defconfig \
        rv32im_ooo_4k_asic_defconfig \
        menuconfig showconfig config-check source-check \
        public-hygiene sim-dry-run verilator-lint sim smoke regression difftest difftest-prepare \
        coremark coremark-difftest performance-check ooo-history-check evidence-check opensbi-smoke runtime-tests docs-check \
        implementation-check showcase-check verify-checksums \
        asic-config-check lc-macros lc-macros-dry-run dc-matrix dc-matrix-dry-run \
        pnr pnr-dry-run sta sta-dry-run \
        asic-evidence-check a3-dc-eval ci

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
	  '  make coremark / coremark-difftest         Run hash-locked external CoreMark inputs' \
	  '  make performance-check                    Validate tracked performance evidence' \
	  '  make ooo-history-check                    Validate bounded OoO history and source reconstruction' \
	  '  make evidence-check                       Validate performance, system, FPGA, and ASIC evidence' \
	  '  make <profile>_asic_defconfig             Select a register-expanded ASIC Profile' \
	  '  make asic-config-check                    Validate ASIC source/config closure' \
	  '  make lc-macros[-dry-run]                  Compile audited OpenRAM Liberty views to DB' \
	  '  make dc-matrix[-dry-run]                  Run/show the WNS-guided DC frequency scan' \
	  '  make pnr[-dry-run]                        Run/show mapped-netlist OpenROAD/OpenRCX' \
	  '  make sta[-dry-run]                        Run/show same-run PrimeTime STA' \
	  '  make a3-dc-eval                           Evaluate three-way OoO A3 DC evidence' \
	  '  make runtime-tests                       Run dependency-free control-plane tests' \
	  '  make docs-check                           Validate bilingual docs and metric references' \
	  '  make implementation-check                 Validate four bounded ASIC evidence chains' \
	  '  make showcase-check                       Validate evidence, claims, and generated assets' \
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

rv32im_single_perf_asic_defconfig:
	@$(FLOWCTL) defconfig --source "$(ROOT)/configs/rv32im_single_perf_asic_defconfig"

rv32im_single_perf_sram_asic_defconfig:
	@$(FLOWCTL) defconfig --source "$(ROOT)/configs/rv32im_single_perf_sram_asic_defconfig"

rv32ima_sv32_linux_asic_defconfig:
	@$(FLOWCTL) defconfig --source "$(ROOT)/configs/rv32ima_sv32_linux_asic_defconfig"

rv32ima_sv32_linux_sram_asic_defconfig:
	@$(FLOWCTL) defconfig --source "$(ROOT)/configs/rv32ima_sv32_linux_sram_asic_defconfig"

rv32im_ooo_4k_asic_defconfig:
	@$(FLOWCTL) defconfig --source "$(ROOT)/configs/rv32im_ooo_4k_asic_defconfig"

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

coremark:
	@$(FLOWCTL) coremark

coremark-difftest:
	@$(FLOWCTL) coremark-difftest

performance-check:
	@$(PYTHON) "$(ROOT)/flows/scripts/check_performance.py" --root "$(ROOT)"

ooo-history-check:
	@$(PYTHON) "$(ROOT)/flows/scripts/check_ooo_history.py" --root "$(ROOT)"

evidence-check: performance-check ooo-history-check implementation-check
	@$(PYTHON) "$(ROOT)/flows/scripts/check_historical_evidence.py" --root "$(ROOT)"

opensbi-smoke:
	@$(FLOWCTL) opensbi-smoke

asic-config-check:
	@$(ASICCTL) config-check --ooo-mode "$(ASIC_OOO_MODE)" --memory-mode "$(ASIC_MEMORY_MODE)"

lc-macros:
	@$(ASICCTL) lc-macros --ooo-mode "$(ASIC_OOO_MODE)" --memory-mode "$(ASIC_MEMORY_MODE)" $(ASIC_LC_ARGS)

lc-macros-dry-run:
	@$(ASICCTL) lc-macros --dry-run --ooo-mode "$(ASIC_OOO_MODE)" --memory-mode "$(ASIC_MEMORY_MODE)" $(ASIC_LC_ARGS)

dc-matrix:
	@$(ASICCTL) dc-matrix --ooo-mode "$(ASIC_OOO_MODE)" --memory-mode "$(ASIC_MEMORY_MODE)" $(ASIC_DC_ARGS)

dc-matrix-dry-run:
	@$(ASICCTL) dc-matrix --dry-run --ooo-mode "$(ASIC_OOO_MODE)" --memory-mode "$(ASIC_MEMORY_MODE)" $(ASIC_DC_ARGS)

pnr:
	@$(ASICCTL) pnr --ooo-mode "$(ASIC_OOO_MODE)" --memory-mode "$(ASIC_MEMORY_MODE)" --dc-run "$(NPC_ASIC_DC_RUN)" $(ASIC_PNR_ARGS)

pnr-dry-run:
	@$(ASICCTL) pnr --dry-run --ooo-mode "$(ASIC_OOO_MODE)" --memory-mode "$(ASIC_MEMORY_MODE)" --dc-run "$(NPC_ASIC_DC_RUN)" $(ASIC_PNR_ARGS)

sta:
	@$(ASICCTL) sta --ooo-mode "$(ASIC_OOO_MODE)" --memory-mode "$(ASIC_MEMORY_MODE)" --pnr-run "$(NPC_ASIC_PNR_RUN)" $(ASIC_STA_ARGS)

sta-dry-run:
	@$(ASICCTL) sta --dry-run --ooo-mode "$(ASIC_OOO_MODE)" --memory-mode "$(ASIC_MEMORY_MODE)" --pnr-run "$(NPC_ASIC_PNR_RUN)" $(ASIC_STA_ARGS)

asic-evidence-check:
	@$(ASICCTL) evidence-check --build-root "$(NPC_ASIC_BUILD_ROOT)"

a3-dc-eval:
	@$(ASICCTL) a3-dc-eval \
	  --legacy "$(NPC_ASIC_A3_LEGACY_RUN)" \
	  --split-off "$(NPC_ASIC_A3_SPLIT_OFF_RUN)" \
	  --a3 "$(NPC_ASIC_A3_RUN)" \
	  --cpi-summary "$(NPC_ASIC_A3_CPI_SUMMARY)" \
	  --output "$(NPC_ASIC_A3_EVAL_OUTPUT)"

runtime-tests:
	@$(PYTHON) -m unittest discover -s "$(ROOT)/tests" -p 'test_*.py'

docs-check:
	@$(PYTHON) "$(ROOT)/flows/scripts/check_docs.py" --root "$(ROOT)"
	@$(PYTHON) "$(ROOT)/flows/scripts/check_performance.py" --root "$(ROOT)"
	@$(PYTHON) "$(ROOT)/flows/scripts/check_historical_evidence.py" --root "$(ROOT)"

implementation-check:
	@$(PYTHON) "$(ROOT)/flows/scripts/check_implementation.py" --root "$(ROOT)"

showcase-check: evidence-check
	@$(PYTHON) "$(ROOT)/flows/scripts/generate_showcase_assets.py" --root "$(ROOT)" --check

verify-checksums:
	@cd "$(ROOT)" && sha256sum --check SHA256SUMS

ci: verify-checksums docs-check showcase-check runtime-tests config-check source-check public-hygiene verilator-lint smoke regression
