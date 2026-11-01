// adder_ks: Kogge-Stone parallel-prefix adder.
// log2(W) levels. At level k every position i >= 2^k combines with i - 2^k,
// so each node drives at most 2 cells (minimum fan-out, minimum depth) at the
// cost of the most cells and the longest wires (spans up to W/2).
// Group (G, P) arrays: G[k][i] covers bits [max(0, i-2^k+1) .. i]; cin is
// folded into bit 0 so G[k][i] is the carry out of bit i once its group
// reaches bit 0.
module adder_ks #(
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
            if (i < (1 << k)) begin : g_pass
                // Group already reaches bit 0.
                assign G[k+1][i] = G[k][i];
                assign P[k+1][i] = P[k][i];
            end else if (i < (2 << k)) begin : g_gray
                // Result reaches bit 0: only G is needed from here on.
                pg_gray u_cell (.gh(G[k][i]), .ph(P[k][i]), .gl(G[k][i-(1<<k)]), .g(G[k+1][i]));
                assign P[k+1][i] = 1'b0;  // never read
            end else begin : g_black
                pg_black u_cell (.gh(G[k][i]), .ph(P[k][i]), .gl(G[k][i-(1<<k)]),
                                 .pl(P[k][i-(1<<k)]), .g(G[k+1][i]), .p(P[k+1][i]));
            end
        end
    end

    assign sum  = pb ^ {G[L][W-2:0], cin};
    assign cout = G[L][W-1];
endmodule
