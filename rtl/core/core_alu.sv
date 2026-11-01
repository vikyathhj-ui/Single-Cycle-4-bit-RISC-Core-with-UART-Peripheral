// core_alu: combinational RV32I + Zbb ALU for the ID/EX stage (docs/SPEC.md §10, D-007 S-2).
//
// Built from P1's vendored units, unchanged (vendor/alu/rtl/, see vendor/VENDOR.md):
// the shared adder (ARCH = HC by default), the barrel shifter, clz and cpop. The result logic
// mirrors P1 alu_top's S1/S2 stages without its input/output registers, so it can sit in a
// single-cycle execute stage with forwarding. Opcodes are P1's alu_pkg encoding (0-26).
// Illegal opcodes cannot reach this unit (the decoder only produces legal ones); they give 0.
`default_nettype none
module core_alu #(
    parameter int ADDER = alu_pkg::ADDER_HC
) (
    input  logic [4:0]  op,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic [31:0] y
);
    import alu_pkg::*;

    function automatic logic [31:0] rev32(input logic [31:0] x);
        for (int i = 0; i < 32; i++) rev32[i] = x[31-i];
    endfunction

    // One-hot decode into named wires (same style as P1 alu_top, P1 D-021).
    logic d_add, d_sub, d_sll, d_slt, d_sltu, d_xor, d_srl, d_sra, d_or, d_and;
    logic d_min, d_max, d_minu, d_maxu, d_andn, d_orn, d_xnor, d_rol, d_ror;
    logic d_clz, d_ctz, d_cpop, d_sext_b, d_sext_h, d_zext_h, d_rev8, d_orc_b;

    assign d_add    = (op == OP_ADD);
    assign d_sub    = (op == OP_SUB);
    assign d_sll    = (op == OP_SLL);
    assign d_slt    = (op == OP_SLT);
    assign d_sltu   = (op == OP_SLTU);
    assign d_xor    = (op == OP_XOR);
    assign d_srl    = (op == OP_SRL);
    assign d_sra    = (op == OP_SRA);
    assign d_or     = (op == OP_OR);
    assign d_and    = (op == OP_AND);
    assign d_min    = (op == OP_MIN);
    assign d_max    = (op == OP_MAX);
    assign d_minu   = (op == OP_MINU);
    assign d_maxu   = (op == OP_MAXU);
    assign d_andn   = (op == OP_ANDN);
    assign d_orn    = (op == OP_ORN);
    assign d_xnor   = (op == OP_XNOR);
    assign d_rol    = (op == OP_ROL);
    assign d_ror    = (op == OP_ROR);
    assign d_clz    = (op == OP_CLZ);
    assign d_ctz    = (op == OP_CTZ);
    assign d_cpop   = (op == OP_CPOP);
    assign d_sext_b = (op == OP_SEXT_B);
    assign d_sext_h = (op == OP_SEXT_H);
    assign d_zext_h = (op == OP_ZEXT_H);
    assign d_rev8   = (op == OP_REV8);
    assign d_orc_b  = (op == OP_ORC_B);

    logic use_sub, inv_b, is_addgrp, is_shift;
    assign use_sub   = d_sub | d_slt | d_sltu | d_min | d_max | d_minu | d_maxu;
    assign inv_b     = use_sub | d_andn | d_orn | d_xnor;
    assign is_addgrp = d_add | use_sub;
    assign is_shift  = d_sll | d_srl | d_sra | d_rol | d_ror;

    logic [31:0] bx;
    assign bx = inv_b ? ~b : b;

    // Shared adder (P1 unit).
    logic [31:0] sum;
    logic        cout, ovf, lt_s, lt_u;
    adder #(.ARCH(ADDER), .W(32)) u_adder (.a(a), .b(bx), .cin(use_sub), .sum(sum), .cout(cout));
    assign ovf  = (a[31] == bx[31]) && (sum[31] != a[31]);
    assign lt_s = sum[31] ^ ovf;
    assign lt_u = ~cout;

    logic [31:0] r_add;
    assign r_add = ({32{d_add | d_sub}} & sum)
                 | ({32{d_slt}}         & {31'd0, lt_s})
                 | ({32{d_sltu}}        & {31'd0, lt_u})
                 | ({32{d_min}}         & (lt_s ? a : b))
                 | ({32{d_max}}         & (lt_s ? b : a))
                 | ({32{d_minu}}        & (lt_u ? a : b))
                 | ({32{d_maxu}}        & (lt_u ? b : a));

    // Shifter (P1 unit).
    logic        sh_left, sh_rotate;
    logic [31:0] r_shift;
    assign sh_left   = d_sll | d_rol;
    assign sh_rotate = d_rol | d_ror;
    shifter u_shifter (.a(a), .s(b[4:0]), .left(sh_left), .rotate(sh_rotate), .arith(d_sra), .y(r_shift));

    // Counts (P1 units). CTZ = CLZ of the bit-reversed operand.
    logic [31:0] clz_in;
    logic [5:0]  n_lz, n_pop;
    assign clz_in = d_ctz ? rev32(a) : a;
    clz  #(.W(32)) u_clz  (.x(clz_in), .cnt(n_lz));
    cpop #(.W(32)) u_cpop (.x(a), .cnt(n_pop));

    logic [31:0] orc;
    for (genvar k = 0; k < 4; k++) begin : g_orc
        assign orc[8*k +: 8] = {8{|a[8*k +: 8]}};
    end

    logic [31:0] r_misc;
    assign r_misc = ({32{d_and | d_andn}} & (a & bx))
                  | ({32{d_or  | d_orn}}  & (a | bx))
                  | ({32{d_xor | d_xnor}} & (a ^ bx))
                  | ({32{d_clz | d_ctz}}  & {26'd0, n_lz})
                  | ({32{d_cpop}}         & {26'd0, n_pop})
                  | ({32{d_sext_b}}       & {{24{a[7]}}, a[7:0]})
                  | ({32{d_sext_h}}       & {{16{a[15]}}, a[15:0]})
                  | ({32{d_zext_h}}       & {16'd0, a[15:0]})
                  | ({32{d_rev8}}         & {a[7:0], a[15:8], a[23:16], a[31:24]})
                  | ({32{d_orc_b}}        & orc);

    assign y = is_addgrp ? r_add : is_shift ? r_shift : r_misc;

    // Elaboration check: this wrapper decodes exactly P1's 27 opcodes (0-26). If a re-vendored
    // alu_pkg changes the encoding, elaboration fails here instead of mis-executing.
    if (OP_ILLEGAL_MIN != 5'd27 || OP_ORC_B != 5'd26) begin : g_bad_alu_pkg
        core_alu_expects_alu_pkg_opcodes_0_to_26 u_error ();
    end
endmodule
`default_nettype wire
