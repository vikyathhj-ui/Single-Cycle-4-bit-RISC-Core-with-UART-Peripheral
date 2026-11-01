// shifter: the ALU's single shared logarithmic barrel shifter (BRIEF A2).
// Serves SLL, SRL, SRA, ROL and ROR.
//
// Core: a 63->32 funnel right shifter. The 32-bit value `lo` is extended on
// the left with 31 fill bits `hi`, and the concatenation is shifted right by
// s = b[4:0] in five log stages (16, 8, 4, 2, 1). Each stage keeps only the
// bits a later stage can still use, so the widths shrink 63->47->39->35->33->32.
//   SRL: hi = 0            SRA: hi = copies of a[31]       ROR: hi = a[30:0]
// Left operations reuse the same right shifter via bit reversal (D-016):
//   SLL(a, s) = rev(SRL(rev(a), s)),  ROL(a, s) = rev(ROR(rev(a), s)).
module shifter (
    input  logic [31:0] a,
    input  logic [4:0]  s,
    input  logic        left,    // SLL, ROL
    input  logic        rotate,  // ROL, ROR
    input  logic        arith,   // SRA
    output logic [31:0] y
);
    function automatic logic [31:0] rev32(input logic [31:0] x);
        for (int i = 0; i < 32; i++) rev32[i] = x[31-i];
    endfunction

    logic [31:0] lo;
    logic [30:0] hi;
    logic [62:0] x0;
    logic [46:0] x1;
    logic [38:0] x2;
    logic [34:0] x3;
    logic [32:0] x4;
    logic [31:0] r;

    assign lo = left ? rev32(a) : a;
    assign hi = rotate ? lo[30:0] : {31{arith & a[31]}};
    assign x0 = {hi, lo};

    assign x1 = s[4] ? x0[62:16] : x0[46:0];
    assign x2 = s[3] ? x1[46:8]  : x1[38:0];
    assign x3 = s[2] ? x2[38:4]  : x2[34:0];
    assign x4 = s[1] ? x3[34:2]  : x3[32:0];
    assign r  = s[0] ? x4[32:1]  : x4[31:0];

    assign y = left ? rev32(r) : r;
endmodule
