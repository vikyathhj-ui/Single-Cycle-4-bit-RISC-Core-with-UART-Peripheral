# lp-rv32-mcu top-level entry points (docs/BRIEF.md A7 "make all" is built up phase by phase).
# Run inside the iic-osic container, from the host:
#   docker exec -w /foss/projects/Single-Cycle-4-bit-RISC-Core-with-UART-Peripheral iic-osic bash -lc 'make <target>'

SHELL := /bin/bash
.SHELLFLAGS := -o pipefail -c

.PHONY: help env legacy-probe clean

help:
	@echo "make env           tool table -> results/env_check.txt (fails if anything is missing)"
	@echo "make legacy-probe  docs/AUDIT.md evidence -> results/legacy_probe.txt"
	@echo "make clean         remove sim_build/"

env:
	scripts/env_check.sh | tee results/env_check.txt

legacy-probe:
	scripts/legacy_probe.sh

clean:
	rm -rf sim_build
