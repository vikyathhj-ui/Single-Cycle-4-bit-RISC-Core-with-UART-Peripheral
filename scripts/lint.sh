#!/usr/bin/env bash
# Verilator -Wall lint (BRIEF A5 "Verilator -Wall clean"), no waivers:
#   lp_rv32_core, normal build and RVFI build (-DRISCV_FORMAL);
#   lp_rv32_soc (core + SoC + peripherals + vendored PMU), SIM memory configuration.
# Output: results/lint.txt; exit 1 on any warning.
# Run inside the iic-osic container (or CI) from the repo root.
set -uo pipefail
cd "$(dirname "$0")/.."
FILES=$(grep -v '^\s*//' rtl/core/core.f | grep -v '^\s*$')
OUT=results/lint.txt
status=0
{
echo "# verilator lint ($(verilator --version))"
for defs in "" "-DRISCV_FORMAL"; do
    echo "## lp_rv32_core ${defs:-(normal build)}"
    if verilator --lint-only -Wall $defs --top-module lp_rv32_core $FILES 2>&1 | grep -E '%(Warning|Error)'; then
        status=1
    else
        echo "clean"
    fi
done
SOC=$(grep -v '^\s*//' rtl/soc/soc.f | grep -v '^\s*$')
echo "## lp_rv32_soc (SIM memory configuration)"
if verilator --lint-only -Wall -Irtl/soc --top-module lp_rv32_soc $FILES $SOC 2>&1 | grep -E '%(Warning|Error)'; then
    status=1
else
    echo "clean"
fi
} > "$OUT"
cat "$OUT"
exit $status
