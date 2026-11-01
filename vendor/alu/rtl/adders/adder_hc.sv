// adder_hc: Han-Carlson parallel-prefix adder.
// Level 0 pairs each odd bit with the even bit below it. Levels 1 .. log2(W)-1
// run Kogge-Stone on the odd positions only (half the cells and wires of KS).
// A final level fixes each even position from the odd neighbour below.
// log2(W)+1 levels (6 for W = 32): one level deeper than KS, about half its cells.
module adder_hc #(
    parameter int W = 32
) (
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    input  logic         cin,
    output logic [W-1:0] sum,
    output logic         cout
);
    localparam int L  = $clog2(W);
    localparam int NS = L + 1;

    logic [W-1:0] pb;  // per-bit propagate a ^ b (P is the group propagate)
    logic [W-1:0] G [0:NS];
    logic [W-1:0] P [0:NS];

    assign pb   = a ^ b;
    assign G[0] = (a & b) | {{(W-1){1'b0}}, pb[0] & cin};
    assign P[0] = pb;

    // Level 0: odd i combines with i - 1.
    for (genvar i = 0; i < W; i++) begin : g_l0
        if ((i % 2) == 0) begin : g_pass
            assign G[1][i] = G[0][i];
            assign P[1][i] = P[0][i];
        end else if (i == 1) begin : g_gray
            pg_gray u_cell (.gh(G[0][i]), .ph(P[0][i]), .gl(G[0][i-1]), .g(G[1][i]));
            assign P[1][i] = 1'b0;  // never read
        end else begin : g_black
            pg_black u_cell (.gh(G[0][i]), .ph(P[0][i]), .gl(G[0][i-1]), .pl(P[0][i-1]),
                             .g(G[1][i]), .p(P[1][i]));
        end
    end

    // Levels 1 .. L-1: Kogge-Stone on odd positions with span 2^k.
    for (genvar k = 1; k < L; k++) begin : g_lvl
        for (genvar i = 0; i < W; i++) begin : g_bit
            if (((i % 2) == 0) || (i < (1 << k) + 1)) begin : g_pass
                assign G[k+1][i] = G[k][i];
                assign P[k+1][i] = P[k][i];
            end else if (i < (2 << k)) begin : g_gray
                pg_gray u_cell (.gh(G[k][i]), .ph(P[k][i]), .gl(G[k][i-(1<<k)]), .g(G[k+1][i]));
                assign P[k+1][i] = 1'b0;  // never read
            end else begin : g_black
                pg_black u_cell (.gh(G[k][i]), .ph(P[k][i]), .gl(G[k][i-(1<<k)]),
                                 .pl(P[k][i-(1<<k)]), .g(G[k+1][i]), .p(P[k+1][i]));
            end
        end
    end

    // Final level: even i >= 2 combines with the (complete) odd position i - 1.
    for (genvar i = 0; i < W; i++) begin : g_fix
        if (((i % 2) == 0) && (i >= 2)) begin : g_gray
            pg_gray u_cell (.gh(G[L][i]), .ph(P[L][i]), .gl(G[L][i-1]), .g(G[NS][i]));
            assign P[NS][i] = 1'b0;  // never read
        end else begin : g_pass
            assign G[NS][i] = G[L][i];
            assign P[NS][i] = P[L][i];
        end
    end

    assign sum  = pb ^ {G[NS][W-2:0], cin};
    assign cout = G[NS][W-1];
endmodule
