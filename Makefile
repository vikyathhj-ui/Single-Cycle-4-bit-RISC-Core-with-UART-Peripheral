# lp-rv32-mcu top-level entry points (docs/BRIEF.md A7 "make all" is built up phase by phase).
# Run inside the iic-osic container, from the host:
#   docker exec -w /foss/projects/Single-Cycle-4-bit-RISC-Core-with-UART-Peripheral iic-osic bash -lc 'make <target>'

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

.PHONY: help env legacy-probe memmap memmap-check lint formal formal-quick tb-arch tb-arch-trace riscof unit bootrom clean

help:
	@echo "make env           tool table -> results/env_check.txt (fails if anything is missing)"
	@echo "make legacy-probe  docs/AUDIT.md evidence -> results/legacy_probe.txt"
	@echo "make memmap        scripts/memmap.yaml -> docs/MEMORY_MAP.md, sw/include/lp_rv32.h, tb/memmap.py"
	@echo "make memmap-check  fail if those generated files are stale"
	@echo "make lint          verilator -Wall, normal + RVFI build -> results/lint.txt"
	@echo "make formal        riscv-formal, full depths -> results/formal/summary.json"
	@echo "make formal-quick  riscv-formal, depths capped at 10 (CI) -> results/formal/summary_quick.json"
	@echo "make tb-arch       build the RISCOF DUT testbench (Verilator) -> sim_build/tb_arch/tb_arch"
	@echo "make riscof        riscv-arch-test 3.10.0 via RISCOF, Spike reference -> results/riscof/"
	@echo "make unit          cocotb unit tests (uart, timer, gpio, xbar+bridge, soc smoke) -> results/unit/summary.json"
	@echo "make bootrom       rtl/soc/bootrom_image.svh from sw/boot (scripts/gen_bootrom.py)"
	@echo "make clean         remove sim_build/"

env:
	scripts/env_check.sh | tee results/env_check.txt

legacy-probe:
	scripts/legacy_probe.sh

memmap:
	python3 scripts/gen_memmap.py

memmap-check:
	python3 scripts/gen_memmap.py --check

lint:
	scripts/lint.sh

formal:
	python3 scripts/run_formal.py

formal-quick:
	python3 scripts/run_formal.py --quick

CORE_FILES := $(shell grep -v '^\s*//' rtl/core/core.f | grep -v '^\s*$$')
SOC_SIM_FILES := rtl/soc/mem_1rw1r_sim.sv rtl/soc/lp_rv32_xbar.sv rtl/soc/apb_bridge.sv

tb-arch:
	verilator --binary --timing -O2 -Wall -Wno-fatal --top-module tb_arch -Mdir sim_build/tb_arch -o tb_arch \
	  $(CORE_FILES) $(SOC_SIM_FILES) tb/arch/tb_arch.sv

tb-arch-trace:
	verilator --binary --timing -O2 -DRISCV_FORMAL -Wno-fatal --top-module tb_arch -Mdir sim_build/tb_arch_trace -o tb_arch \
	  $(CORE_FILES) $(SOC_SIM_FILES) tb/arch/tb_arch.sv

riscof: tb-arch
	python3 scripts/run_riscof.py

.venv/bin/python:
	python3 -m venv --system-site-packages .venv && .venv/bin/pip install cocotb-coverage==2.0

unit: .venv/bin/python
	.venv/bin/python scripts/run_unit.py

bootrom:
	python3 scripts/gen_bootrom.py

clean:
	rm -rf sim_build
