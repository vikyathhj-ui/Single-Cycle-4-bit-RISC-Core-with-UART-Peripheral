// core_regfile: 31 x 32-bit integer registers, x0 hard-wired to 0 [U §2.1].
// Two asynchronous read ports (ID/EX), one synchronous write port (end of MEM/WB).
// No reset: register contents are UNSPECIFIED after reset [P §3.4]. In simulation they start
// as X, so a read before a write shows up.
`default_nettype none
module core_regfile (
    input  logic        clk,
    input  logic [4:0]  ra1,
    input  logic [4:0]  ra2,
    output logic [31:0] rd1,
    output logic [31:0] rd2,
    input  logic        we,
    input  logic [4:0]  wa,
    input  logic [31:0] wd
);
    logic [31:0] regs [1:31];

    always_ff @(posedge clk) begin
        if (we && wa != 5'd0) regs[wa] <= wd;
    end

    assign rd1 = (ra1 == 5'd0) ? 32'd0 : regs[ra1];
    assign rd2 = (ra2 == 5'd0) ? 32'd0 : regs[ra2];
endmodule
`default_nettype wire
