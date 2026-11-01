// adder_csla: carry-select adder with 8-bit blocks (BRIEF A2).
// Block 0 is a plain ripple adder. Every other block computes its sum twice in
// parallel, once assuming carry-in 0 and once assuming 1, and the real carry
// from the block below selects the right copy. The carry path is one mux per
// block instead of 8 full-adder stages.
module adder_csla #(
    parameter int W = 32,
    parameter int B = 8
) (
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    input  logic         cin,
    output logic [W-1:0] sum,
    output logic         cout
);
    localparam int NB = W / B;

    logic [NB:0] c;  // c[k] = carry into block k
    assign c[0] = cin;

    for (genvar k = 0; k < NB; k++) begin : g_blk
        if (k == 0) begin : g_first
            adder_rca #(.W(B)) u_rca (
                .a(a[B-1:0]), .b(b[B-1:0]), .cin(c[0]), .sum(sum[B-1:0]), .cout(c[1])
            );
        end else begin : g_sel
            logic [B-1:0] s0, s1;
            logic         c0, c1;
            adder_rca #(.W(B)) u_rca0 (
                .a(a[k*B +: B]), .b(b[k*B +: B]), .cin(1'b0), .sum(s0), .cout(c0)
            );
            adder_rca #(.W(B)) u_rca1 (
                .a(a[k*B +: B]), .b(b[k*B +: B]), .cin(1'b1), .sum(s1), .cout(c1)
            );
            assign sum[k*B +: B] = c[k] ? s1 : s0;
            assign c[k+1]        = c[k] ? c1 : c0;
        end
    end
    assign cout = c[NB];

    // Elaboration-time check: W must be a whole number of blocks.
    if (W % B != 0) begin : g_bad_width
        adder_csla_requires_W_multiple_of_B u_error ();
    end
endmodule
