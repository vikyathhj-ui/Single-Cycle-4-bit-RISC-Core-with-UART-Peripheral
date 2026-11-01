// adder_rca: ripple-carry adder. Each bit's carry-out feeds the next bit, so
// delay grows linearly with W (W full-adder carry stages).
module adder_rca #(
    parameter int W = 32
) (
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    input  logic         cin,
    output logic [W-1:0] sum,
    output logic         cout
);
    logic [W:0] c;

    assign c[0] = cin;
    for (genvar i = 0; i < W; i++) begin : g_fa
        assign sum[i]  = a[i] ^ b[i] ^ c[i];
        assign c[i+1]  = (a[i] & b[i]) | ((a[i] ^ b[i]) & c[i]);
    end
    assign cout = c[W];
endmodule
