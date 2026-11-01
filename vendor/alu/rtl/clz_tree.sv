// clz_tree: recursive leading-zero tree used by clz.
// v = "some bit of x is 1"; c = number of leading zeros (valid when v = 1).
// Each node splits x into halves: if the high half has a 1, its count is the
// answer; otherwise the answer is W/2 plus the low half's count. That is a
// single mux per level, so depth is log2(W) (5 levels for W = 32).
// W must be a power of 2, >= 2.
module clz_tree #(
    parameter int W = 32
) (
    input  logic [W-1:0]          x,
    output logic                  v,
    output logic [$clog2(W)-1:0]  c
);
    if (W == 2) begin : g_leaf
        assign v = x[1] | x[0];
        assign c = ~x[1];  // 0 leading zeros if x[1] = 1, else 1
    end else begin : g_node
        localparam int H = W / 2;
        logic                 vh, vl;
        logic [$clog2(H)-1:0] ch, cl;
        clz_tree #(.W(H)) u_hi (.x(x[W-1:H]), .v(vh), .c(ch));
        clz_tree #(.W(H)) u_lo (.x(x[H-1:0]), .v(vl), .c(cl));
        assign v = vh | vl;
        assign c = vh ? {1'b0, ch} : {1'b1, cl};
    end

    if ((1 << $clog2(W)) != W || W < 2) begin : g_bad_width
        clz_tree_requires_power_of_two_W u_error ();
    end
endmodule
