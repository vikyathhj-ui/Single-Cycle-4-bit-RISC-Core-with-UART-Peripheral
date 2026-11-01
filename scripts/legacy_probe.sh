#!/usr/bin/env bash
# Evidence for docs/AUDIT.md. Runs the legacy testbench as shipped and the audit probe
# (legacy/tb_probe.v), and extracts the facts the audit quotes from the legacy source.
# Run inside the iic-osic container from the repo root:
#   docker exec -w /foss/projects/Single-Cycle-4-bit-RISC-Core-with-UART-Peripheral iic-osic \
#     bash -lc 'scripts/legacy_probe.sh'
# Output: results/legacy_probe.txt
set -euo pipefail
cd "$(dirname "$0")/.."
OUT=results/legacy_probe.txt
B=sim_build/legacy
mkdir -p "$B"
L=legacy
SRC="$L/RISC_UART_TOP.v $L/PC_5Bit.v $L/Inst_ROM.v $L/ControlUnit.v $L/RegFile_4x4.v $L/ALU_4Bit.v $L/UART_TX.v"
{
echo "# Legacy probe ($(date -u +%Y-%m-%dT%H:%MZ)), $(iverilog -V 2>&1 | head -n1)"
echo
echo "## L1. Legacy testbench as shipped (legacy/RISC_UART_TOP_tb.v)"
echo "Lines that check or print anything (\$display/\$monitor/\$error/if/assert/===/!==): \
$(grep -cE '\$display|\$monitor|\$error|\$fatal|\bif\b|assert|===|!==' "$L/RISC_UART_TOP_tb.v" || true)"
echo "Stimulus statements:"
grep -nE 'RST *=|#[0-9(]|\$stop|always' "$L/RISC_UART_TOP_tb.v"
iverilog -g2005 -o "$B/legacy_tb" "$L/RISC_UART_TOP_tb.v" $SRC
echo "Simulator output of the shipped testbench (everything it prints):"
(cd "$B" && timeout 120 vvp -n legacy_tb 2>&1) | sed 's/^/  | /'
echo
echo "## L2. Program in the ROM: comments vs the ControlUnit decode table"
echo "ControlUnit opcode table:"
grep -nE "^\s*3'b[01]{3}:" "$L/ControlUnit.v"
echo "ROM initialisation (with the original comments):"
grep -nE "ROM\[[0-9]+\] *=" "$L/Inst_ROM.v"
echo "ROM entries initialised: $(grep -cE 'ROM\[[0-9]+\] *=' "$L/Inst_ROM.v") of 32 (array 'reg [7:0] ROM [0:31]')"
echo
echo "## L3. Audit probe (legacy/tb_probe.v), same clock/reset/run length as the shipped testbench"
iverilog -g2005 -o "$B/probe" "$L/tb_probe.v" $SRC
(cd "$B" && timeout 120 vvp -n probe) | grep PROBE
echo
echo "## L4. UART framing and baud constants (legacy/UART_TX.v)"
grep -nE "BAUD_DIVIDER *=|TX_Data_In|bit_count == |else if \(clk_enable\)|if \(TX_Start\)" "$L/UART_TX.v"
div=$(grep -oE "BAUD_DIVIDER = 13'd[0-9]+" "$L/UART_TX.v" | grep -oE '[0-9]+$')
python3 -c "d=$div+1; print(f'bit period = {d} cycles; at the 50 MHz clock in legacy/RISC_UART_TOP_tb.v (CLK_PERIOD=20 ns): {50e6/d:.1f} baud')"
echo
echo "## L5. Target device of the Quartus project (legacy/uuart.qsf)"
grep -nE "FAMILY|DEVICE |TOP_LEVEL_ENTITY" "$L/uuart.qsf"
} > "$OUT" 2>&1
echo "-> $OUT"
