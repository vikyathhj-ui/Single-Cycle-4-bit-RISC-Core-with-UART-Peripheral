// core_decode: combinational instruction decoder (docs/SPEC.md §2, docs/MICROARCH.md §2).
//
// Decodes RV32I [U §2], Zicsr [U §6], Zbb [U §29.4.2] and the M-mode SYSTEM instructions
// [P §3.3]. Encodings with no defined instruction give legal = 0 (illegal instruction, SPEC §2.1).
// CSR address legality is checked by core_csr, not here.
`default_nettype none
module core_decode (
    input  logic [31:0] insn,
    output logic        legal,
    output logic [4:0]  rs1,
    output logic [4:0]  rs2,
    output logic [4:0]  rd,
    output logic        uses_rs1,
    output logic        uses_rs2,
    output logic        rd_we,       // writes rd (rd may still be x0)
    output logic [31:0] imm,
    output logic [4:0]  alu_op,      // alu_pkg encoding
    output logic [1:0]  alu_a_sel,   // 0 rs1, 1 pc, 2 zero
    output logic        alu_b_imm,   // 1: b = imm, 0: b = rs2
    output logic [1:0]  wb_sel,      // 0 ALU, 1 pc+4, 2 CSR, 3 load
    output logic        is_branch,
    output logic        is_jal,
    output logic        is_jalr,
    output logic        is_load,
    output logic        is_store,
    output logic [2:0]  funct3,
    output logic        is_csr,
    output logic        is_ecall,
    output logic        is_ebreak,
    output logic        is_mret,
    output logic        is_wfi
);
    import alu_pkg::*;

    localparam logic [6:0] OPC_LUI    = 7'b0110111;
    localparam logic [6:0] OPC_AUIPC  = 7'b0010111;
    localparam logic [6:0] OPC_JAL    = 7'b1101111;
    localparam logic [6:0] OPC_JALR   = 7'b1100111;
    localparam logic [6:0] OPC_BRANCH = 7'b1100011;
    localparam logic [6:0] OPC_LOAD   = 7'b0000011;
    localparam logic [6:0] OPC_STORE  = 7'b0100011;
    localparam logic [6:0] OPC_OPIMM  = 7'b0010011;
    localparam logic [6:0] OPC_OP     = 7'b0110011;
    localparam logic [6:0] OPC_MISC   = 7'b0001111;
    localparam logic [6:0] OPC_SYSTEM = 7'b1110011;

    logic [6:0] opcode, funct7;
    logic [11:0] funct12;
    assign opcode  = insn[6:0];
    assign funct3  = insn[14:12];
    assign funct7  = insn[31:25];
    assign funct12 = insn[31:20];
    assign rs1     = insn[19:15];
    assign rs2     = insn[24:20];
    assign rd      = insn[11:7];

    logic [31:0] imm_i, imm_s, imm_b, imm_u, imm_j;
    assign imm_i = {{20{insn[31]}}, insn[31:20]};
    assign imm_s = {{20{insn[31]}}, insn[31:25], insn[11:7]};
    assign imm_b = {{19{insn[31]}}, insn[31], insn[7], insn[30:25], insn[11:8], 1'b0};
    assign imm_u = {insn[31:12], 12'd0};
    assign imm_j = {{11{insn[31]}}, insn[31], insn[19:12], insn[20], insn[30:21], 1'b0};

    always_comb begin
        legal     = 1'b0;
        uses_rs1  = 1'b0;
        uses_rs2  = 1'b0;
        rd_we     = 1'b0;
        imm       = imm_i;
        alu_op    = OP_ADD;
        alu_a_sel = 2'd0;
        alu_b_imm = 1'b0;
        wb_sel    = 2'd0;
        is_branch = 1'b0;
        is_jal    = 1'b0;
        is_jalr   = 1'b0;
        is_load   = 1'b0;
        is_store  = 1'b0;
        is_csr    = 1'b0;
        is_ecall  = 1'b0;
        is_ebreak = 1'b0;
        is_mret   = 1'b0;
        is_wfi    = 1'b0;

        case (opcode)
            OPC_LUI: begin                                   // [U §2.4.1]
                legal = 1'b1; rd_we = 1'b1; imm = imm_u;
                alu_a_sel = 2'd2; alu_b_imm = 1'b1;
            end
            OPC_AUIPC: begin                                 // [U §2.4.1]
                legal = 1'b1; rd_we = 1'b1; imm = imm_u;
                alu_a_sel = 2'd1; alu_b_imm = 1'b1;
            end
            OPC_JAL: begin                                   // [U §2.5.1]
                legal = 1'b1; rd_we = 1'b1; imm = imm_j; is_jal = 1'b1; wb_sel = 2'd1;
            end
            OPC_JALR: begin                                  // [U §2.5.1]
                legal = (funct3 == 3'b000);
                uses_rs1 = 1'b1; rd_we = 1'b1; imm = imm_i; is_jalr = 1'b1; wb_sel = 2'd1;
                alu_b_imm = 1'b1;                            // target = rs1 + imm via the ALU adder
            end
            OPC_BRANCH: begin                                // [U §2.5.2]
                legal = (funct3 != 3'b010) && (funct3 != 3'b011);
                uses_rs1 = 1'b1; uses_rs2 = 1'b1; imm = imm_b; is_branch = 1'b1;
                alu_op = funct3[1] ? OP_SLTU : OP_SLT;       // BLT/BGE: SLT, BLTU/BGEU: SLTU
            end
            OPC_LOAD: begin                                  // [U §2.6]
                legal = (funct3 == 3'b000) || (funct3 == 3'b001) || (funct3 == 3'b010) ||
                        (funct3 == 3'b100) || (funct3 == 3'b101);
                uses_rs1 = 1'b1; rd_we = 1'b1; imm = imm_i; is_load = 1'b1; wb_sel = 2'd3;
                alu_b_imm = 1'b1;
            end
            OPC_STORE: begin                                 // [U §2.6]
                legal = (funct3 == 3'b000) || (funct3 == 3'b001) || (funct3 == 3'b010);
                uses_rs1 = 1'b1; uses_rs2 = 1'b1; imm = imm_s; is_store = 1'b1;
                alu_b_imm = 1'b1;
            end
            OPC_OPIMM: begin                                 // [U §2.4.1], Zbb [U §29.4.2]
                uses_rs1 = 1'b1; rd_we = 1'b1; imm = imm_i; alu_b_imm = 1'b1;
                case (funct3)
                    3'b000: begin legal = 1'b1; alu_op = OP_ADD;  end
                    3'b010: begin legal = 1'b1; alu_op = OP_SLT;  end
                    3'b011: begin legal = 1'b1; alu_op = OP_SLTU; end
                    3'b100: begin legal = 1'b1; alu_op = OP_XOR;  end
                    3'b110: begin legal = 1'b1; alu_op = OP_OR;   end
                    3'b111: begin legal = 1'b1; alu_op = OP_AND;  end
                    3'b001: begin
                        if (funct7 == 7'b0000000) begin
                            legal = 1'b1; alu_op = OP_SLL;                 // SLLI
                        end else if (funct7 == 7'b0110000) begin
                            case (rs2)                                     // unary Zbb ops
                                5'b00000: begin legal = 1'b1; alu_op = OP_CLZ;    end
                                5'b00001: begin legal = 1'b1; alu_op = OP_CTZ;    end
                                5'b00010: begin legal = 1'b1; alu_op = OP_CPOP;   end
                                5'b00100: begin legal = 1'b1; alu_op = OP_SEXT_B; end
                                5'b00101: begin legal = 1'b1; alu_op = OP_SEXT_H; end
                                default:  legal = 1'b0;
                            endcase
                        end
                    end
                    3'b101: begin
                        if (funct7 == 7'b0000000) begin
                            legal = 1'b1; alu_op = OP_SRL;                 // SRLI
                        end else if (funct7 == 7'b0100000) begin
                            legal = 1'b1; alu_op = OP_SRA;                 // SRAI
                        end else if (funct7 == 7'b0110000) begin
                            legal = 1'b1; alu_op = OP_ROR;                 // RORI
                        end else if (funct12 == 12'b001010000111) begin
                            legal = 1'b1; alu_op = OP_ORC_B;               // ORC.B
                        end else if (funct12 == 12'b011010011000) begin
                            legal = 1'b1; alu_op = OP_REV8;                // REV8 (RV32)
                        end
                    end
                    default: legal = 1'b0;
                endcase
            end
            OPC_OP: begin                                    // [U §2.4.2], Zbb [U §29.4.2]
                uses_rs1 = 1'b1; uses_rs2 = 1'b1; rd_we = 1'b1;
                case ({funct7, funct3})
                    {7'b0000000, 3'b000}: begin legal = 1'b1; alu_op = OP_ADD;  end
                    {7'b0100000, 3'b000}: begin legal = 1'b1; alu_op = OP_SUB;  end
                    {7'b0000000, 3'b001}: begin legal = 1'b1; alu_op = OP_SLL;  end
                    {7'b0000000, 3'b010}: begin legal = 1'b1; alu_op = OP_SLT;  end
                    {7'b0000000, 3'b011}: begin legal = 1'b1; alu_op = OP_SLTU; end
                    {7'b0000000, 3'b100}: begin legal = 1'b1; alu_op = OP_XOR;  end
                    {7'b0000000, 3'b101}: begin legal = 1'b1; alu_op = OP_SRL;  end
                    {7'b0100000, 3'b101}: begin legal = 1'b1; alu_op = OP_SRA;  end
                    {7'b0000000, 3'b110}: begin legal = 1'b1; alu_op = OP_OR;   end
                    {7'b0000000, 3'b111}: begin legal = 1'b1; alu_op = OP_AND;  end
                    {7'b0100000, 3'b111}: begin legal = 1'b1; alu_op = OP_ANDN; end
                    {7'b0100000, 3'b110}: begin legal = 1'b1; alu_op = OP_ORN;  end
                    {7'b0100000, 3'b100}: begin legal = 1'b1; alu_op = OP_XNOR; end
                    {7'b0000101, 3'b100}: begin legal = 1'b1; alu_op = OP_MIN;  end
                    {7'b0000101, 3'b101}: begin legal = 1'b1; alu_op = OP_MINU; end
                    {7'b0000101, 3'b110}: begin legal = 1'b1; alu_op = OP_MAX;  end
                    {7'b0000101, 3'b111}: begin legal = 1'b1; alu_op = OP_MAXU; end
                    {7'b0110000, 3'b001}: begin legal = 1'b1; alu_op = OP_ROL;  end
                    {7'b0110000, 3'b101}: begin legal = 1'b1; alu_op = OP_ROR;  end
                    {7'b0000100, 3'b100}: begin                    // ZEXT.H (RV32): rs2 field = 0
                        legal = (rs2 == 5'd0); uses_rs2 = 1'b0; alu_op = OP_ZEXT_H;
                    end
                    default: legal = 1'b0;
                endcase
            end
            OPC_MISC: begin                                  // FENCE [U §2.7]; FENCE.I not implemented
                legal = (funct3 == 3'b000);                  // executes as a no-op (SPEC §2.1)
            end
            OPC_SYSTEM: begin
                if (funct3 == 3'b000) begin                  // [P §3.3]
                    if (insn == 32'h0000_0073) begin legal = 1'b1; is_ecall  = 1'b1; end
                    if (insn == 32'h0010_0073) begin legal = 1'b1; is_ebreak = 1'b1; end
                    if (insn == 32'h3020_0073) begin legal = 1'b1; is_mret   = 1'b1; end
                    if (insn == 32'h1050_0073) begin legal = 1'b1; is_wfi    = 1'b1; end
                end else if (funct3 != 3'b100) begin         // Zicsr [U §6.1]
                    legal = 1'b1; is_csr = 1'b1; rd_we = 1'b1; wb_sel = 2'd2;
                    uses_rs1 = ~funct3[2];                   // register forms read rs1
                end
            end
            default: legal = 1'b0;
        endcase
        if (insn[1:0] != 2'b11) legal = 1'b0;                // only 32-bit encodings (no C)
    end
endmodule
`default_nettype wire
