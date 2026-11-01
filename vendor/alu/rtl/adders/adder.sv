// adder: selects one adder architecture (BRIEF A2 "parameter ADDER").
// ARCH takes the alu_pkg::ADDER_* codes (integers, DECISIONS D-012).
// Every architecture has the same interface and must give identical results;
// formal equivalence against a + b + cin is proven per architecture (Phase 3).
module adder #(
    parameter int ARCH = alu_pkg::ADDER_BEH,
    parameter int W    = 32
) (
    input  logic [W-1:0] a,
    input  logic [W-1:0] b,
    input  logic         cin,
    output logic [W-1:0] sum,
    output logic         cout
);
    import alu_pkg::*;

    if (ARCH == ADDER_RCA) begin : g_rca
        adder_rca  #(.W(W)) u_add (.a, .b, .cin, .sum, .cout);
    end else if (ARCH == ADDER_CLA4) begin : g_cla4
        adder_cla4 #(.W(W)) u_add (.a, .b, .cin, .sum, .cout);
    end else if (ARCH == ADDER_CSLA) begin : g_csla
        adder_csla #(.W(W)) u_add (.a, .b, .cin, .sum, .cout);
    end else if (ARCH == ADDER_BK) begin : g_bk
        adder_bk   #(.W(W)) u_add (.a, .b, .cin, .sum, .cout);
    end else if (ARCH == ADDER_KS) begin : g_ks
        adder_ks   #(.W(W)) u_add (.a, .b, .cin, .sum, .cout);
    end else if (ARCH == ADDER_SK) begin : g_sk
        adder_sk   #(.W(W)) u_add (.a, .b, .cin, .sum, .cout);
    end else if (ARCH == ADDER_HC) begin : g_hc
        adder_hc   #(.W(W)) u_add (.a, .b, .cin, .sum, .cout);
    end else if (ARCH == ADDER_BEH) begin : g_beh
        adder_beh  #(.W(W)) u_add (.a, .b, .cin, .sum, .cout);
    end else begin : g_bad_arch
        // Unknown code: instantiate a module that does not exist so every tool
        // stops at elaboration with this name in the error message.
        adder_unknown_ARCH_parameter u_error ();
    end
endmodule
