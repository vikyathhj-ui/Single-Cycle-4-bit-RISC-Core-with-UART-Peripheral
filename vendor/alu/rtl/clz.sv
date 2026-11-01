// clz: count leading zeros of a W-bit value with a log-depth tree (BRIEF A2).
// Returns W when x == 0 (zb#insns-clz). CTZ uses the same module fed with the
// bit-reversed operand (alu_top), so there is one tree for both (D-015).
module clz #(
    parameter int W = 32
) (
    input  logic [W-1:0]         x,
    output logic [$clog2(W):0]   cnt
);
    logic                  v;
    logic [$clog2(W)-1:0]  c;

    clz_tree #(.W(W)) u_tree (.x, .v, .c);

    // v = 0 means x was all zeros: the count is W = {1, 0...0}.
    assign cnt = v ? {1'b0, c} : {1'b1, {$clog2(W){1'b0}}};
endmodule
