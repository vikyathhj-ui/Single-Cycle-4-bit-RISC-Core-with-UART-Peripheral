// mem_1rw1r_sim: behavioural memory with the port list of sky130_sram_1kbyte_1rw1r_32x256_8
// (docs/SPEC.md §4 SIM configuration, D-007 S-4). Used for the SIM memory configuration
// (32 KB each by default) and by the RISCOF testbench.
//
// Timing contract, the same as the macro's (MICROARCH §3): inputs are registered at the rising
// edge, read data is valid during the following cycle. A port-0 write updates the array at that
// edge, so a read of the same word in a later cycle returns the new data. The macro's falling-edge
// detail is not modelled (functionally identical for this synchronous design).
`default_nettype none
module mem_1rw1r_sim #(
    parameter int AW = 13                  // word-address bits: 13 -> 8192 words = 32 KB
) (
    // port 0: read/write
    input  logic          clk0,
    input  logic          csb0,            // active-low chip select
    input  logic          web0,            // active-low write enable
    input  logic [3:0]    wmask0,
    input  logic [AW-1:0] addr0,
    input  logic [31:0]   din0,
    output logic [31:0]   dout0,
    // port 1: read only
    input  logic          clk1,
    input  logic          csb1,
    input  logic [AW-1:0] addr1,
    output logic [31:0]   dout1
);
    logic [31:0]   mem [0:(1<<AW)-1];
    logic [AW-1:0] a0_q, a1_q;

    always_ff @(posedge clk0) begin
        if (!csb0) begin
            a0_q <= addr0;
            if (!web0) begin
                for (int b = 0; b < 4; b++)
                    if (wmask0[b]) mem[addr0][8*b +: 8] <= din0[8*b +: 8];
            end
        end
    end

    always_ff @(posedge clk1) begin
        if (!csb1) a1_q <= addr1;
    end

    assign dout0 = mem[a0_q];
    assign dout1 = mem[a1_q];
endmodule
`default_nettype wire
