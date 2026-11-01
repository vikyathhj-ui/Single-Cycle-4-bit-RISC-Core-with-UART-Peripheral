#!/usr/bin/env bash
# Verilator -Wall lint of lp_rv32_core (BRIEF A5 "Verilator -Wall clean"), in the normal build
# and the RVFI build (-DRISCV_FORMAL). No waivers. Output: results/lint.txt; exit 1 on any warning.
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
} > "$OUT"
cat "$OUT"
exit $status
