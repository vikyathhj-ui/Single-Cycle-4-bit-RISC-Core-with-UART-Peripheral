// tb_probe.v -- audit probe for docs/AUDIT.md (added in the lp-rv32 rework; not part of the
// original design). It runs the legacy RISC_UART_TOP exactly like legacy/RISC_UART_TOP_tb.v
// (50 MHz clock, 100 ns reset, 1 ms run) but OBSERVES instead of only driving:
//   P1. the opcode each ROM word decodes to, using ControlUnit's own table;
//   P2. a per-cycle trace of the first instructions (PC, opcode, register file);
//   P3. the number of cycles TX_Start is high, and how many of those coincide with the
//       UART's one-cycle clk_enable (the only cycles where IDLE samples TX_Start);
//   P4. the number of UART start bits (falling edges on TX_PIN) seen in the 1 ms window.
// Run by scripts/legacy_probe.sh.
`timescale 1ns/1ps
module tb_probe;
    localparam CLK_PERIOD = 20;
    reg CLK = 1'b0, RST = 1'b1;
    wire TX_PIN;
    always #(CLK_PERIOD/2) CLK = ~CLK;

    RISC_UART_TOP UUT (.CLK(CLK), .RST(RST), .TX_PIN(TX_PIN));

    integer i, cyc = 0, tx_start_cycles = 0, tx_start_sampled = 0, start_bits = 0;
    reg prev_tx = 1'b1;

    function [8*6-1:0] opname(input [2:0] op);
        case (op)
            3'b000: opname = "LOADI";
            3'b001: opname = "ADD";
            3'b010: opname = "OUT";
            3'b011: opname = "JUMP";
            default: opname = "NOP";
        endcase
    endfunction

    initial begin
        #1;
        $display("PROBE P1 ROM decode (ControlUnit opcode = instr[7:5]):");
        for (i = 0; i < 8; i = i + 1)
            $display("PROBE P1 ROM[%0d] = 8'h%h -> opcode %b = %0s  rd/rs=[4:3]=%0d imm/addr=[4:0]=%0d",
                     i, UUT.ROM_Unit.ROM[i], UUT.ROM_Unit.ROM[i][7:5], opname(UUT.ROM_Unit.ROM[i][7:5]),
                     UUT.ROM_Unit.ROM[i][4:3], UUT.ROM_Unit.ROM[i][4:0]);
    end

    always @(posedge CLK) if (!RST) begin
        cyc = cyc + 1;
        if (cyc <= 12)
            $display("PROBE P2 cycle %0d: PC=%0d instr=8'h%h op=%0s R0=%h R1=%h R2=%h R3=%h TX_Start=%b",
                     cyc, UUT.pc_out, UUT.instruction, opname(UUT.instruction[7:5]),
                     UUT.RF_Unit.Registers[0], UUT.RF_Unit.Registers[1],
                     UUT.RF_Unit.Registers[2], UUT.RF_Unit.Registers[3], UUT.TX_Start);
        if (UUT.TX_Start === 1'b1) begin
            tx_start_cycles = tx_start_cycles + 1;
            if (UUT.TX_Unit.clk_enable === 1'b1 && UUT.TX_Unit.tx_state == 3'b000)
                tx_start_sampled = tx_start_sampled + 1;
        end
        if (prev_tx === 1'b1 && TX_PIN === 1'b0) start_bits = start_bits + 1;
        prev_tx = TX_PIN;
    end

    initial begin
        RST = 1'b1; #100; RST = 1'b0;
        #1000000;
        $display("PROBE P3 cycles after reset: %0d", cyc);
        $display("PROBE P3 cycles with TX_Start=1: %0d", tx_start_cycles);
        $display("PROBE P3 TX_Start=1 cycles that coincide with clk_enable in IDLE: %0d", tx_start_sampled);
        $display("PROBE P4 UART start bits on TX_PIN in 1 ms: %0d", start_bits);
        $display("PROBE P4 final registers: R0=%h R1=%h R2=%h R3=%h",
                 UUT.RF_Unit.Registers[0], UUT.RF_Unit.Registers[1],
                 UUT.RF_Unit.Registers[2], UUT.RF_Unit.Registers[3]);
        $finish;
    end
endmodule
