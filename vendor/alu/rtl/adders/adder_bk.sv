// adder_bk: Brent-Kung parallel-prefix adder.
// An up-sweep (spans 1, 2, 4, ... W/2) builds groups at positions 2^(k+1)-1
// multiples; a down-sweep (spans W/4 ... 1) fills in the rest. 2*log2(W)-1
// levels (9 for W = 32): roughly twice the depth of Kogge-Stone, but about
// 2W cells, fan-out <= 2 and short wiring. Requires W to be a power of 2.
module adder_bk #(
    parameter int W = 32
) (
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    input  logic         cin,
    output logic [W-1:0] sum,
    output logic         cout
);
    localparam int L  = $clog2(W);
    localparam int NS = 2 * L - 1;  // number of prefix levels

    logic [W-1:0] pb;  // per-bit propagate a ^ b (P is the group propagate)
    logic [W-1:0] G [0:NS];
    logic [W-1:0] P [0:NS];

    assign pb   = a ^ b;
    assign G[0] = (a & b) | {{(W-1){1'b0}}, pb[0] & cin};
    assign P[0] = pb;

    // Up-sweep: level k combines i with i - 2^k where (i + 1) is a multiple of 2^(k+1).
    for (genvar k = 0; k < L; k++) begin : g_up
        for (genvar i = 0; i < W; i++) begin : g_bit
            if (((i + 1) % (2 << k)) != 0) begin : g_pass
                assign G[k+1][i] = G[k][i];
                assign P[k+1][i] = P[k][i];
            end else if (i == (2 << k) - 1) begin : g_gray
                pg_gray u_cell (.gh(G[k][i]), .ph(P[k][i]), .gl(G[k][i-(1<<k)]), .g(G[k+1][i]));
                assign P[k+1][i] = 1'b0;  // never read
            end else begin : g_black
                pg_black u_cell (.gh(G[k][i]), .ph(P[k][i]), .gl(G[k][i-(1<<k)]),
                                 .pl(P[k][i-(1<<k)]), .g(G[k+1][i]), .p(P[k+1][i]));
            end
        end
    end

    // Down-sweep: span 2^k for k = L-2 .. 0. Position i with (i + 1) mod 2^(k+1) == 2^k
    // (and past the first block) combines with i - 2^k, which is already complete.
    for (genvar d = 0; d < L - 1; d++) begin : g_down
        localparam int K = L - 2 - d;
        localparam int S = L + d;  // input level index
        for (genvar i = 0; i < W; i++) begin : g_bit
            if ((((i + 1) % (2 << K)) == (1 << K)) && (i >= (2 << K) + (1 << K) - 1)) begin : g_gray
                pg_gray u_cell (.gh(G[S][i]), .ph(P[S][i]), .gl(G[S][i-(1<<K)]), .g(G[S+1][i]));
                assign P[S+1][i] = 1'b0;  // never read
            end else begin : g_pass
                assign G[S+1][i] = G[S][i];
                assign P[S+1][i] = P[S][i];
            end
        end
    end

    assign sum  = pb ^ {G[NS][W-2:0], cin};
    assign cout = G[NS][W-1];

    if ((1 << L) != W) begin : g_bad_width
        adder_bk_requires_power_of_two_W u_error ();
    end
endmodule
