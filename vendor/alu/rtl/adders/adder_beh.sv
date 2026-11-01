// adder_beh: behavioural adder. The synthesiser chooses the structure; this is
// the baseline the hand-built architectures are compared against.
module adder_beh #(
    parameter int W = 32
) (
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    input  logic         cin,
    output logic [W-1:0] sum,
    output logic         cout
);
    assign {cout, sum} = {1'b0, a} + {1'b0, b} + {{W{1'b0}}, cin};
endmodule
