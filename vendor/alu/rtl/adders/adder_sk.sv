// adder_sk: Sklansky (divide-and-conquer) parallel-prefix adder.
// log2(W) levels like Kogge-Stone but far fewer cells: at level k each position
// with bit k set combines with the top of the lower half of its 2^(k+1) block,
// ((i >> k) << k) - 1. That one node drives 2^k cells, so fan-out grows to W/2:
// minimum depth, few cells, but high fan-out.
module adder_sk #(
    parameter int W = 32
) (
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    input  logic         cin,
    output logic [W-1:0] sum,
    output logic         cout
);
    localparam int L = $clog2(W);

    logic [W-1:0] pb;  // per-bit propagate a ^ b (P is the group propagate)
    logic [W-1:0] G [0:L];
    logic [W-1:0] P [0:L];

    assign pb   = a ^ b;
    assign G[0] = (a & b) | {{(W-1){1'b0}}, pb[0] & cin};
    assign P[0] = pb;

    for (genvar k = 0; k < L; k++) begin : g_lvl
        for (genvar i = 0; i < W; i++) begin : g_bit
            localparam int J = ((i >> k) << k) - 1;  // partner (top of lower half)
            if (((i >> k) & 1) == 0) begin : g_pass
                assign G[k+1][i] = G[k][i];
                assign P[k+1][i] = P[k][i];
            end else if (i < (2 << k)) begin : g_gray
                pg_gray u_cell (.gh(G[k][i]), .ph(P[k][i]), .gl(G[k][J]), .g(G[k+1][i]));
                assign P[k+1][i] = 1'b0;  // never read
            end else begin : g_black
                pg_black u_cell (.gh(G[k][i]), .ph(P[k][i]), .gl(G[k][J]), .pl(P[k][J]),
                                 .g(G[k+1][i]), .p(P[k+1][i]));
            end
        end
    end

    assign sum  = pb ^ {G[L][W-2:0], cin};
    assign cout = G[L][W-1];
endmodule
