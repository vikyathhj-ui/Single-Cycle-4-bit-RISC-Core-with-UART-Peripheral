// adder_cla4: hierarchical carry-lookahead adder built from 4-bit lookahead
// units (cla4_unit) with group lookahead (BRIEF A2).
//
// Level 0 holds the per-bit (g, p). Each level groups 4 elements of the level
// below into one (G, P) pair; the top level receives cin. Carries then flow back
// down: every unit turns its carry-in into the carries for its 3 upper inputs.
// For W = 32 that is 8 units -> 2 units -> 1 unit (3 levels, since 4^3 >= 32).
// Positions beyond an element count are padded with g = 0, p = 1: the identity
// of the (G, P) operator, so padding never changes a group's G or P.
module adder_cla4 #(
    parameter int W = 32
) (
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    input  logic         cin,
    output logic [W-1:0] sum,
    output logic         cout
);
    // Number of lookahead levels: smallest NL with 4^NL >= W.
    localparam int NL = ($clog2(W) + 1) / 2;

    // Element count at level l (ceil(W / 4^l)) and units at level l.
    function automatic int count_at(input int l);
        int n = W;
        for (int k = 0; k < l; k++) n = (n + 3) / 4;
        return n;
    endfunction

    // lg/lp[l][j]: generate/propagate of element j at level l.
    // lc[l][j]:    carry into element j at level l.
    // Arrays are W wide at every level; elements past count_at(l) are padding.
    logic [W-1:0] lg [0:NL];
    logic [W-1:0] lp [0:NL];
    logic [W-1:0] lc [0:NL];

    assign lg[0] = a & b;
    assign lp[0] = a ^ b;

    for (genvar l = 0; l < NL; l++) begin : g_lvl
        localparam int N  = count_at(l);
        localparam int NU = (N + 3) / 4;
        for (genvar u = 0; u < NU; u++) begin : g_unit
            logic [3:0] ug, up;
            for (genvar q = 0; q < 4; q++) begin : g_in
                if (4*u + q < N) begin : g_real
                    assign ug[q] = lg[l][4*u + q];
                    assign up[q] = lp[l][4*u + q];
                end else begin : g_pad
                    // Identity element: g = 0, p = 1. (p = 0 here would force
                    // the unit's group propagate gp = &p to 0 and break cout.)
                    assign ug[q] = 1'b0;
                    assign up[q] = 1'b1;
                end
            end
            logic [3:1] uc;
            cla4_unit u_cla (
                .g(ug), .p(up), .c0(lc[l+1][u]), .c(uc), .gg(lg[l+1][u]), .gp(lp[l+1][u])
            );
            assign lc[l][4*u] = lc[l+1][u];
            // Carries for padding inputs land in padding slots of lc and are
            // never read (synthesis removes them); real inputs get real carries.
            for (genvar q = 1; q < 4; q++) begin : g_out
                if (4*u + q < W) begin : g_slot
                    assign lc[l][4*u + q] = uc[q];
                end
            end
        end
        // Tie off unused padding positions at the level above.
        for (genvar j = NU; j < W; j++) begin : g_tie
            assign lg[l+1][j] = 1'b0;
            assign lp[l+1][j] = 1'b0;
        end
        // Slots of this level not covered by any unit (only exist for l >= 1).
        for (genvar j = 4*NU; j < W; j++) begin : g_tie_c
            assign lc[l][j] = 1'b0;
        end
    end

    assign lc[NL][0] = cin;
    for (genvar j = 1; j < W; j++) begin : g_tie_top
        assign lc[NL][j] = 1'b0;
    end

    assign sum  = lp[0] ^ lc[0];
    assign cout = lg[NL][0] | (lp[NL][0] & cin);
endmodule
