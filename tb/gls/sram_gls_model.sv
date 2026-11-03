// Behavioural model of sky130_sram_1kbyte_1rw1r_32x256_8 for the gate-level power simulation
// (scripts/gls_power.py, D-032). The PDK model ($PDK_ROOT/.../verilog/...32x256_8.v) does not
// elaborate in Icarus: it uses `mem` in a $display before declaring it ("Scope index expression is
// not constant"). This model has the same module name and ports and the same function as
// rtl/soc/mem_1rw1r_sim.sv (inputs registered at the rising edge, data in the next cycle). It
// differs from the macro only in WHEN dout changes inside the cycle (after the rising edge here,
// after the falling edge in the macro). That does not change per-cycle toggle counts in a
// zero-delay functional simulation. The array is named `mem` like the PDK model's, so
// tb/gls/gls_tb.sv preloads both the same way.
`timescale 1ns/1ps
module sky130_sram_1kbyte_1rw1r_32x256_8 (
    input         clk0,
    input         csb0,
    input         web0,
    input  [3:0]  wmask0,
    input  [7:0]  addr0,
    input  [31:0] din0,
    output [31:0] dout0,
    input         clk1,
    input         csb1,
    input  [7:0]  addr1,
    output [31:0] dout1
);
    reg [31:0] mem [0:255];
    reg [7:0]  a0_q, a1_q;
    integer b;
    always @(posedge clk0) begin
        if (!csb0) begin
            a0_q <= addr0;
            if (!web0)
                for (b = 0; b < 4; b = b + 1)
                    if (wmask0[b]) mem[addr0][8*b +: 8] <= din0[8*b +: 8];
        end
    end
    always @(posedge clk1) if (!csb1) a1_q <= addr1;
    assign dout0 = mem[a0_q];
    assign dout1 = mem[a1_q];
endmodule
