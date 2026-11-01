# lp-rv32-mcu top-level entry points (docs/BRIEF.md A7 "make all" is built up phase by phase).
# Run inside the iic-osic container, from the host:
#   docker exec -w /foss/projects/Single-Cycle-4-bit-RISC-Core-with-UART-Peripheral iic-osic bash -lc 'make <target>'

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

.PHONY: help env legacy-probe memmap memmap-check clean

help:
	@echo "make env           tool table -> results/env_check.txt (fails if anything is missing)"
	@echo "make legacy-probe  docs/AUDIT.md evidence -> results/legacy_probe.txt"
	@echo "make memmap        scripts/memmap.yaml -> docs/MEMORY_MAP.md, sw/include/lp_rv32.h, tb/memmap.py"
	@echo "make memmap-check  fail if those generated files are stale"
	@echo "make clean         remove sim_build/"

env:
	scripts/env_check.sh | tee results/env_check.txt

legacy-probe:
	scripts/legacy_probe.sh

memmap:
	python3 scripts/gen_memmap.py

memmap-check:
	python3 scripts/gen_memmap.py --check

clean:
	rm -rf sim_build
