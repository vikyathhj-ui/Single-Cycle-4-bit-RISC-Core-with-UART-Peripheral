// cpop: population count with a log-depth adder tree (BRIEF A2).
// Recursively counts each half and adds the two counts, so a W = 32 input
// becomes 16 2-bit sums, 8 3-bit, 4 4-bit, 2 5-bit and finally one 6-bit sum.
// W must be a power of 2.
module cpop #(
    parameter int W = 32
) (
    input  logic [W-1:0]        x,
    output logic [$clog2(W):0]  cnt
);
    if (W == 1) begin : g_leaf
        assign cnt = x;
    end else begin : g_node
        localparam int H = W / 2;
        logic [$clog2(H):0] ch, cl;
        cpop #(.W(H)) u_hi (.x(x[W-1:H]), .cnt(ch));
        cpop #(.W(H)) u_lo (.x(x[H-1:0]), .cnt(cl));
        assign cnt = {1'b0, ch} + {1'b0, cl};
    end

    if ((1 << $clog2(W)) != W) begin : g_bad_width
        cpop_requires_power_of_two_W u_error ();
    end
endmodule
