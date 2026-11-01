// alu_pkg: opcode encoding for alu_top (docs/SPEC.md section 3, DECISIONS D-009).
//
// Codes 0-9 are RV32I, 10-26 are the Zbb subset grouped by the unit that
// executes them, and 27-31 are illegal. scripts/check_opcodes.py checks that
// these values match model/alu_ref.py, so the encoding is verified, not shared.

package alu_pkg;

    localparam int OPW = 5;

    // RV32I
    localparam logic [OPW-1:0] OP_ADD    = 5'd0;
    localparam logic [OPW-1:0] OP_SUB    = 5'd1;
    localparam logic [OPW-1:0] OP_SLL    = 5'd2;
    localparam logic [OPW-1:0] OP_SLT    = 5'd3;
    localparam logic [OPW-1:0] OP_SLTU   = 5'd4;
    localparam logic [OPW-1:0] OP_XOR    = 5'd5;
    localparam logic [OPW-1:0] OP_SRL    = 5'd6;
    localparam logic [OPW-1:0] OP_SRA    = 5'd7;
    localparam logic [OPW-1:0] OP_OR     = 5'd8;
    localparam logic [OPW-1:0] OP_AND    = 5'd9;
    // Zbb: compare/select (shared adder)
    localparam logic [OPW-1:0] OP_MIN    = 5'd10;
    localparam logic [OPW-1:0] OP_MAX    = 5'd11;
    localparam logic [OPW-1:0] OP_MINU   = 5'd12;
    localparam logic [OPW-1:0] OP_MAXU   = 5'd13;
    // Zbb: logic with negate
    localparam logic [OPW-1:0] OP_ANDN   = 5'd14;
    localparam logic [OPW-1:0] OP_ORN    = 5'd15;
    localparam logic [OPW-1:0] OP_XNOR   = 5'd16;
    // Zbb: rotates (shared shifter)
    localparam logic [OPW-1:0] OP_ROL    = 5'd17;
    localparam logic [OPW-1:0] OP_ROR    = 5'd18;
    // Zbb: counts
    localparam logic [OPW-1:0] OP_CLZ    = 5'd19;
    localparam logic [OPW-1:0] OP_CTZ    = 5'd20;
    localparam logic [OPW-1:0] OP_CPOP   = 5'd21;
    // Zbb: byte / extend
    localparam logic [OPW-1:0] OP_SEXT_B = 5'd22;
    localparam logic [OPW-1:0] OP_SEXT_H = 5'd23;
    localparam logic [OPW-1:0] OP_ZEXT_H = 5'd24;
    localparam logic [OPW-1:0] OP_REV8   = 5'd25;
    localparam logic [OPW-1:0] OP_ORC_B  = 5'd26;

    // Every opcode >= OP_ILLEGAL_MIN is illegal (one comparison, D-009).
    localparam logic [OPW-1:0] OP_ILLEGAL_MIN = 5'd27;

    // Adder architecture codes for alu_top/adder parameter ADDER (BRIEF A2 table).
    // Integer codes rather than strings because Icarus cannot pass a string
    // parameter from parent to child (DECISIONS D-012). Scripts use the names
    // via scripts/adders.py, which scripts/check_opcodes.py checks against this.
    localparam int ADDER_RCA  = 0;
    localparam int ADDER_CLA4 = 1;
    localparam int ADDER_CSLA = 2;
    localparam int ADDER_BK   = 3;
    localparam int ADDER_KS   = 4;
    localparam int ADDER_SK   = 5;
    localparam int ADDER_HC   = 6;
    localparam int ADDER_BEH  = 7;

endpackage
