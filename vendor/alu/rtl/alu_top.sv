// alu_top: RV32I + Zbb ALU (docs/SPEC.md).
//
// Pipeline (latency L = 2 for PIPE = 0, 3 for PIPE = 1; SPEC section 2, D-006):
//   S0   input registers: v0 (reset), op0/a0/b0 (load when in_valid)
//   S1   decode from the *registered* opcode; shared adder, shifter, counts,
//        logic and byte units -> three unit results + C/V + select
//   [P]  PIPE = 1 only: register after the adder/shifter stage (D-013)
//   S2   final mux, N/Z from that same y, illegal handling -> output registers
// Reset: rst_n is asynchronous assert; de-assertion must be synchronous to clk
// (the SoC's reset synchronizer provides it). Only valid bits are reset;
// data registers load only when their stage is valid and otherwise hold (D-010).
module alu_top #(
    parameter int ADDER = alu_pkg::ADDER_BEH,
    parameter int PIPE  = 0
) (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        in_valid,
    input  logic [4:0]  op,
    input  logic [31:0] a,
    input  logic [31:0] b,
    output logic        out_valid,
    output logic [31:0] y,
    output logic [3:0]  flags,      // {N, Z, C, V}
    output logic        illegal_op
);
    import alu_pkg::*;

    // Unit select for the final mux.
    localparam logic [1:0] SEL_ADD   = 2'd0;  // adder group: ADD SUB SLT SLTU MIN MAX MINU MAXU
    localparam logic [1:0] SEL_SHIFT = 2'd1;  // SLL SRL SRA ROL ROR
    localparam logic [1:0] SEL_MISC  = 2'd2;  // logic, counts, byte/extend
    localparam logic [1:0] SEL_ZERO  = 2'd3;  // illegal opcode -> y = 0

    function automatic logic [31:0] rev32(input logic [31:0] x);
        for (int i = 0; i < 32; i++) rev32[i] = x[31-i];
    endfunction

    // ------------------------------------------------------------------ S0
    logic        v0;
    logic [4:0]  op0;
    logic [31:0] a0, b0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) v0 <= 1'b0;
        else        v0 <= in_valid;
    end

    always_ff @(posedge clk) begin
        if (in_valid) begin
            op0 <= op;
            a0  <= a;
            b0  <= b;
        end
    end

    // ------------------------------------------------------------------ S1: decode
    // One-hot decode of the *registered* opcode into named wires (legacy bug A2).
    // Written as plain continuous assigns, with no logic inside port connections
    // and no multi-item case lists: Icarus 14.0-dev mis-evaluates those forms in
    // this module (DECISIONS D-021); this style simulates identically everywhere.
    logic d_add, d_sub, d_sll, d_slt, d_sltu, d_xor, d_srl, d_sra, d_or, d_and;
    logic d_min, d_max, d_minu, d_maxu, d_andn, d_orn, d_xnor, d_rol, d_ror;
    logic d_clz, d_ctz, d_cpop, d_sext_b, d_sext_h, d_zext_h, d_rev8, d_orc_b;

    assign d_add    = (op0 == OP_ADD);
    assign d_sub    = (op0 == OP_SUB);
    assign d_sll    = (op0 == OP_SLL);
    assign d_slt    = (op0 == OP_SLT);
    assign d_sltu   = (op0 == OP_SLTU);
    assign d_xor    = (op0 == OP_XOR);
    assign d_srl    = (op0 == OP_SRL);
    assign d_sra    = (op0 == OP_SRA);
    assign d_or     = (op0 == OP_OR);
    assign d_and    = (op0 == OP_AND);
    assign d_min    = (op0 == OP_MIN);
    assign d_max    = (op0 == OP_MAX);
    assign d_minu   = (op0 == OP_MINU);
    assign d_maxu   = (op0 == OP_MAXU);
    assign d_andn   = (op0 == OP_ANDN);
    assign d_orn    = (op0 == OP_ORN);
    assign d_xnor   = (op0 == OP_XNOR);
    assign d_rol    = (op0 == OP_ROL);
    assign d_ror    = (op0 == OP_ROR);
    assign d_clz    = (op0 == OP_CLZ);
    assign d_ctz    = (op0 == OP_CTZ);
    assign d_cpop   = (op0 == OP_CPOP);
    assign d_sext_b = (op0 == OP_SEXT_B);
    assign d_sext_h = (op0 == OP_SEXT_H);
    assign d_zext_h = (op0 == OP_ZEXT_H);
    assign d_rev8   = (op0 == OP_REV8);
    assign d_orc_b  = (op0 == OP_ORC_B);

    logic use_sub;    // adder computes a0 - b0
    logic inv_b;      // b0 is inverted (subtract, or ANDN/ORN/XNOR)
    logic is_addsub;  // C and V are architectural flags
    logic is_addgrp;  // result comes from the adder group
    logic is_shift;   // result comes from the shifter
    logic illegal;

    assign use_sub   = d_sub | d_slt | d_sltu | d_min | d_max | d_minu | d_maxu;
    assign inv_b     = use_sub | d_andn | d_orn | d_xnor;
    assign is_addsub = d_add | d_sub;
    assign is_addgrp = d_add | use_sub;
    assign is_shift  = d_sll | d_srl | d_sra | d_rol | d_ror;
    assign illegal   = (op0 >= OP_ILLEGAL_MIN);

    // One inverter on b serves the subtractor and the negated logic ops
    // (the Zbb implementation hint, D-014).
    logic [31:0] bx;
    assign bx = inv_b ? ~b0 : b0;

    // ------------------------------------------------------------------ S1: shared adder
    logic [31:0] sum;
    logic        cout;
    logic        ovf, lt_s, lt_u;

    adder #(.ARCH(ADDER), .W(32)) u_adder (
        .a(a0), .b(bx), .cin(use_sub), .sum(sum), .cout(cout)
    );

    // Signed overflow of a0 + bx (+cin): operands agree in sign, result does not.
    assign ovf  = (a0[31] == bx[31]) && (sum[31] != a0[31]);
    // Comparison by subtraction: signed a < b <=> N xor V; unsigned a < b <=> borrow.
    assign lt_s = sum[31] ^ ovf;
    assign lt_u = ~cout;

    // Adder-group result: one-hot AND-OR select (at most one d_* term is 1).
    logic [31:0] r_add;
    assign r_add = ({32{d_add | d_sub}} & sum)
                 | ({32{d_slt}}         & {31'd0, lt_s})
                 | ({32{d_sltu}}        & {31'd0, lt_u})
                 | ({32{d_min}}         & (lt_s ? a0 : b0))
                 | ({32{d_max}}         & (lt_s ? b0 : a0))
                 | ({32{d_minu}}        & (lt_u ? a0 : b0))
                 | ({32{d_maxu}}        & (lt_u ? b0 : a0));

    // ------------------------------------------------------------------ S1: shifter
    logic        sh_left, sh_rotate, sh_arith;
    logic [31:0] r_shift;

    assign sh_left   = d_sll | d_rol;
    assign sh_rotate = d_rol | d_ror;
    assign sh_arith  = d_sra;

    shifter u_shifter (
        .a(a0), .s(b0[4:0]), .left(sh_left), .rotate(sh_rotate), .arith(sh_arith), .y(r_shift)
    );

    // ------------------------------------------------------------------ S1: counts
    logic [31:0] clz_in;
    logic [5:0]  n_lz, n_pop;

    // CTZ = CLZ of the bit-reversed operand: one tree for both (D-015).
    assign clz_in = d_ctz ? rev32(a0) : a0;
    clz  #(.W(32)) u_clz  (.x(clz_in), .cnt(n_lz));
    cpop #(.W(32)) u_cpop (.x(a0), .cnt(n_pop));

    // ------------------------------------------------------------------ S1: logic + byte
    logic [31:0] orc;
    logic [31:0] r_misc;

    for (genvar k = 0; k < 4; k++) begin : g_orc
        assign orc[8*k +: 8] = {8{|a0[8*k +: 8]}};
    end

    assign r_misc = ({32{d_and | d_andn}}    & (a0 & bx))
                  | ({32{d_or  | d_orn}}     & (a0 | bx))
                  | ({32{d_xor | d_xnor}}    & (a0 ^ bx))
                  | ({32{d_clz | d_ctz}}     & {26'd0, n_lz})
                  | ({32{d_cpop}}            & {26'd0, n_pop})
                  | ({32{d_sext_b}}          & {{24{a0[7]}}, a0[7:0]})
                  | ({32{d_sext_h}}          & {{16{a0[15]}}, a0[15:0]})
                  | ({32{d_zext_h}}          & {16'd0, a0[15:0]})
                  | ({32{d_rev8}}            & {a0[7:0], a0[15:8], a0[23:16], a0[31:24]})
                  | ({32{d_orc_b}}           & orc);

    // ------------------------------------------------------------------ S1: result select, C/V
    logic [1:0] sel1;
    logic       c1, ovf1;

    assign sel1 = illegal   ? SEL_ZERO  :
                  is_addgrp ? SEL_ADD   :
                  is_shift  ? SEL_SHIFT : SEL_MISC;
    assign c1   = is_addsub & cout;
    assign ovf1 = is_addsub & ovf;

    // ------------------------------------------------------------------ optional PIPE register
    logic        v2;
    logic [31:0] r_add2, r_shift2, r_misc2;
    logic [1:0]  sel2;
    logic        c2, ovf2, illegal2;

    if (PIPE == 1) begin : g_pipe
        always_ff @(posedge clk or negedge rst_n) begin
            if (!rst_n) v2 <= 1'b0;
            else        v2 <= v0;
        end
        always_ff @(posedge clk) begin
            if (v0) begin
                r_add2   <= r_add;
                r_shift2 <= r_shift;
                r_misc2  <= r_misc;
                sel2     <= sel1;
                c2       <= c1;
                ovf2     <= ovf1;
                illegal2 <= illegal;
            end
        end
    end else if (PIPE == 0) begin : g_nopipe
        assign v2       = v0;
        assign r_add2   = r_add;
        assign r_shift2 = r_shift;
        assign r_misc2  = r_misc;
        assign sel2     = sel1;
        assign c2       = c1;
        assign ovf2     = ovf1;
        assign illegal2 = illegal;
    end else begin : g_bad_pipe
        alu_top_PIPE_must_be_0_or_1 u_error ();
    end

    // ------------------------------------------------------------------ S2: final mux, flags, outputs
    logic [31:0] y_next;

    assign y_next = (sel2 == SEL_ADD)   ? r_add2   :
                    (sel2 == SEL_SHIFT) ? r_shift2 :
                    (sel2 == SEL_MISC)  ? r_misc2  : 32'd0;  // SEL_ZERO: illegal opcode

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) out_valid <= 1'b0;
        else        out_valid <= v2;
    end

    // Flags are computed from the same y_next that is registered into y,
    // so they can never be a cycle stale (legacy bug A3).
    always_ff @(posedge clk) begin
        if (v2) begin
            y          <= y_next;
            flags      <= {y_next[31], (y_next == 32'd0), c2, ovf2};
            illegal_op <= illegal2;
        end
    end
endmodule
