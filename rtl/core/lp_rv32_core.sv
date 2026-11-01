// lp_rv32_core: RV32I + Zicsr + Zbb, machine mode only, 3-stage in-order pipeline
// (IF | ID/EX | MEM/WB). Spec: docs/SPEC.md. Implementation plan: docs/MICROARCH.md.
//
// Bus contract (MICROARCH §3, §5):
//  * I-port: the core drives ibus_addr every cycle; the memory registers it at the rising edge,
//    and ibus_rdata / ibus_err for that address are valid during the next cycle only (OpenRAM
//    timing). When ID/EX stalls, the same address is fetched again.
//  * D-port: dbus_req is a one-cycle request issued from ID/EX (address word-aligned, byte
//    enables in dbus_be). Exactly one response (dbus_rvalid, with dbus_rdata / dbus_err) comes
//    back in a later cycle, in order. At most one request is outstanding.
`default_nettype none
module lp_rv32_core #(
    parameter logic [31:0] RESET_VEC = 32'h0000_0000,
    parameter int          ADDER     = alu_pkg::ADDER_HC
) (
    input  logic        clk,
    input  logic        rst_n,
    // instruction port
    output logic [31:0] ibus_addr,
    input  logic [31:0] ibus_rdata,
    input  logic        ibus_err,
    // data port
    output logic        dbus_req,
    output logic        dbus_we,
    output logic [31:0] dbus_addr,
    output logic [3:0]  dbus_be,
    output logic [31:0] dbus_wdata,
    input  logic        dbus_rvalid,
    input  logic [31:0] dbus_rdata,
    input  logic        dbus_err,
    // interrupts (levels)
    input  logic        irq_msip,
    input  logic        irq_mtip,
    input  logic        irq_meip,
    // power interface (SPEC §8.2, MICROARCH §7): Q-Channel device for PMU PD0
    input  logic        qreq_n,
    output logic        qaccept_n,
    output logic        qdeny,
    output logic        qactive,
    output logic        core_idle,
    output logic        irq_wake
`ifdef RISCV_FORMAL
    ,
    output logic        rvfi_valid,
    output logic [63:0] rvfi_order,
    output logic [31:0] rvfi_insn,
    output logic        rvfi_trap,
    output logic        rvfi_halt,
    output logic        rvfi_intr,
    output logic [1:0]  rvfi_mode,
    output logic [1:0]  rvfi_ixl,
    output logic [4:0]  rvfi_rs1_addr,
    output logic [4:0]  rvfi_rs2_addr,
    output logic [31:0] rvfi_rs1_rdata,
    output logic [31:0] rvfi_rs2_rdata,
    output logic [4:0]  rvfi_rd_addr,
    output logic [31:0] rvfi_rd_wdata,
    output logic [31:0] rvfi_pc_rdata,
    output logic [31:0] rvfi_pc_wdata,
    output logic [31:0] rvfi_mem_addr,
    output logic [3:0]  rvfi_mem_rmask,
    output logic [3:0]  rvfi_mem_wmask,
    output logic [31:0] rvfi_mem_rdata,
    output logic [31:0] rvfi_mem_wdata,
    output logic [31:0] rvfi_csr_mscratch_rmask,
    output logic [31:0] rvfi_csr_mscratch_wmask,
    output logic [31:0] rvfi_csr_mscratch_rdata,
    output logic [31:0] rvfi_csr_mscratch_wdata,
    output logic [31:0] rvfi_csr_mtval_rmask,
    output logic [31:0] rvfi_csr_mtval_wmask,
    output logic [31:0] rvfi_csr_mtval_rdata,
    output logic [31:0] rvfi_csr_mtval_wdata,
    output logic [31:0] rvfi_csr_mcycle_rmask,
    output logic [31:0] rvfi_csr_mcycle_wmask,
    output logic [31:0] rvfi_csr_mcycle_rdata,
    output logic [31:0] rvfi_csr_mcycle_wdata,
    output logic [31:0] rvfi_csr_mcycleh_rmask,
    output logic [31:0] rvfi_csr_mcycleh_wmask,
    output logic [31:0] rvfi_csr_mcycleh_rdata,
    output logic [31:0] rvfi_csr_mcycleh_wdata,
    output logic [31:0] rvfi_csr_minstret_rmask,
    output logic [31:0] rvfi_csr_minstret_wmask,
    output logic [31:0] rvfi_csr_minstret_rdata,
    output logic [31:0] rvfi_csr_minstret_wdata,
    output logic [31:0] rvfi_csr_minstreth_rmask,
    output logic [31:0] rvfi_csr_minstreth_wmask,
    output logic [31:0] rvfi_csr_minstreth_rdata,
    output logic [31:0] rvfi_csr_minstreth_wdata
`endif
);
    // mcause codes ([P §3.1.15] Table 14)
    localparam logic [31:0] C_IADDR_MIS = 32'd0;
    localparam logic [31:0] C_IACC      = 32'd1;
    localparam logic [31:0] C_ILL       = 32'd2;
    localparam logic [31:0] C_BREAK     = 32'd3;
    localparam logic [31:0] C_LADDR_MIS = 32'd4;
    localparam logic [31:0] C_LACC      = 32'd5;
    localparam logic [31:0] C_SADDR_MIS = 32'd6;
    localparam logic [31:0] C_SACC      = 32'd7;
    localparam logic [31:0] C_ECALL_M   = 32'd11;
    localparam logic [31:0] C_INT_MSI   = 32'h8000_0003;
    localparam logic [31:0] C_INT_MTI   = 32'h8000_0007;
    localparam logic [31:0] C_INT_MEI   = 32'h8000_000B;

    // ================================================================ Q-Channel device
    // States {QACCEPTn, QDENY}: 10 RUN, 00 STOPPED, 11 DENIED. Reset: STOPPED (P2 SPEC §2.2).
    logic q_run;
    logic stopped_q;   // device in Q_STOPPED (pipeline frozen)

    // ================================================================ pipeline state
    // IF / ID
    logic        id_valid;
    logic [31:0] id_pc;
    // registered redirect (taken branch / jump / trap / MRET): one bubble (MICROARCH H4, H5)
    logic        rd_q;
    logic [31:0] rd_pc_q;
    // MEM/WB
    logic        mw_valid;
    logic        mw_exc;        // exception decided in ID/EX: retires as a trap, no effects
    logic [31:0] mw_pc;
    logic [4:0]  mw_rd;
    logic        mw_wen;        // writes rd (rd != 0)
    logic [31:0] mw_result;     // ALU / pc+4 / CSR value
    logic        mw_load;
    logic        mw_store;
    logic [2:0]  mw_funct3;
    logic [1:0]  mw_boff;
    logic [31:0] mw_addr;       // effective (byte) address of a load/store
    logic        mw_no_instret; // CSR write to minstret: no increment for this instruction

    // ================================================================ decode (ID/EX)
    logic [31:0] insn;
    assign insn = ibus_rdata;

    logic        d_legal, d_uses_rs1, d_uses_rs2, d_rd_we, d_alu_b_imm;
    logic        d_branch, d_jal, d_jalr, d_load, d_store, d_csr, d_ecall, d_ebreak, d_mret, d_wfi;
    logic [4:0]  d_rs1, d_rs2, d_rd, d_alu_op;
    logic [1:0]  d_alu_a_sel, d_wb_sel;
    logic [2:0]  d_funct3;
    logic [31:0] d_imm;

    core_decode u_dec (
        .insn(insn), .legal(d_legal), .rs1(d_rs1), .rs2(d_rs2), .rd(d_rd),
        .uses_rs1(d_uses_rs1), .uses_rs2(d_uses_rs2), .rd_we(d_rd_we), .imm(d_imm),
        .alu_op(d_alu_op), .alu_a_sel(d_alu_a_sel), .alu_b_imm(d_alu_b_imm), .wb_sel(d_wb_sel),
        .is_branch(d_branch), .is_jal(d_jal), .is_jalr(d_jalr), .is_load(d_load),
        .is_store(d_store), .funct3(d_funct3), .is_csr(d_csr), .is_ecall(d_ecall),
        .is_ebreak(d_ebreak), .is_mret(d_mret), .is_wfi(d_wfi)
    );

    // Effective register addresses: 0 when the instruction does not read the register.
    logic [4:0] ra1, ra2;
    assign ra1 = d_uses_rs1 ? d_rs1 : 5'd0;
    assign ra2 = d_uses_rs2 ? d_rs2 : 5'd0;

    // ================================================================ register file + forwarding
    logic [31:0] rf_rd1, rf_rd2, wb_data;
    logic        rf_we;

    core_regfile u_rf (
        .clk(clk), .ra1(ra1), .ra2(ra2), .rd1(rf_rd1), .rd2(rf_rd2),
        .we(rf_we), .wa(mw_rd), .wd(wb_data)
    );

    // H1: forward the MEM/WB result (non-load) into ID/EX.
    logic fwd_ok;
    assign fwd_ok = mw_valid && mw_wen && !mw_load;
    logic [31:0] rs1v, rs2v;
    assign rs1v = (fwd_ok && ra1 != 5'd0 && ra1 == mw_rd) ? mw_result : rf_rd1;
    assign rs2v = (fwd_ok && ra2 != 5'd0 && ra2 == mw_rd) ? mw_result : rf_rd2;

    // ================================================================ execute
    logic [31:0] alu_a, alu_b, alu_y;
    assign alu_a = (d_alu_a_sel == 2'd1) ? id_pc : (d_alu_a_sel == 2'd2) ? 32'd0 : rs1v;
    assign alu_b = d_alu_b_imm ? d_imm : rs2v;

    core_alu #(.ADDER(ADDER)) u_alu (.op(d_alu_op), .a(alu_a), .b(alu_b), .y(alu_y));

    logic [31:0] pc4, br_target, jalr_target, ctl_target;
    assign pc4         = id_pc + 32'd4;
    assign br_target   = id_pc + d_imm;                       // branches and JAL
    assign jalr_target = {alu_y[31:1], 1'b0};                 // [U §2.5.1]
    assign ctl_target  = d_jalr ? jalr_target : br_target;

    logic br_eq, br_cond, taken;
    assign br_eq = (rs1v == rs2v);
    always_comb begin
        case (d_funct3)
            3'b000:  br_cond = br_eq;            // BEQ
            3'b001:  br_cond = !br_eq;           // BNE
            3'b100,
            3'b110:  br_cond = alu_y[0];         // BLT / BLTU (ALU SLT / SLTU)
            default: br_cond = !alu_y[0];        // BGE / BGEU
        endcase
    end
    assign taken = d_jal || d_jalr || (d_branch && br_cond);

    // Load / store (SPEC §2.1: misaligned accesses trap, S-1)
    logic [31:0] ls_addr;
    logic [1:0]  ls_boff;
    logic        ls_misaligned;
    logic [3:0]  ls_be;
    logic [31:0] st_data;
    assign ls_addr = alu_y;
    assign ls_boff = ls_addr[1:0];
    always_comb begin
        case (d_funct3[1:0])
            2'b00:   begin ls_misaligned = 1'b0;            ls_be = 4'b0001 << ls_boff; end
            2'b01:   begin ls_misaligned = ls_boff[0];      ls_be = ls_boff[1] ? 4'b1100 : 4'b0011; end
            default: begin ls_misaligned = (ls_boff != 0);  ls_be = 4'b1111; end
        endcase
    end
    assign st_data = (d_funct3[1:0] == 2'b00) ? {4{rs2v[7:0]}} :
                     (d_funct3[1:0] == 2'b01) ? {2{rs2v[15:0]}} : rs2v;

    // CSR access
    logic        csr_wr, csr_legal, csr_we;
    logic [31:0] csr_operand, csr_rdata, csr_wdata;
    logic        mstatus_mie;
    logic [31:0] mtvec, mepc, mip, mie;
    logic [63:0] mcycle_rd, mcycle_wr, minstret_rd, minstret_wr;
    logic        trap_en, mret_en, instret_inc;
    logic [31:0] trap_cause, trap_epc, trap_tval;

    assign csr_operand = d_funct3[2] ? {27'd0, d_rs1} : rs1v;
    assign csr_wr      = (d_funct3[1:0] == 2'b01) || (d_rs1 != 5'd0);   // [U §6.1]

    core_csr u_csr (
        .clk(clk), .rst_n(rst_n),
        .addr(insn[31:20]), .op(d_funct3[1:0]), .operand(csr_operand), .wr(csr_wr), .we(csr_we),
        .rdata(csr_rdata), .wdata(csr_wdata), .legal(csr_legal),
        .instret_inc(instret_inc),
        .trap_en(trap_en), .trap_cause(trap_cause), .trap_epc(trap_epc), .trap_tval(trap_tval),
        .mret_en(mret_en),
        .irq_msip(irq_msip), .irq_mtip(irq_mtip), .irq_meip(irq_meip),
        .mstatus_mie(mstatus_mie), .mtvec(mtvec), .mepc(mepc), .mip(mip), .mie(mie),
        .mcycle_rd(mcycle_rd), .mcycle_wr(mcycle_wr), .minstret_rd(minstret_rd), .minstret_wr(minstret_wr)
    );

    // ================================================================ hazards and control
    logic ex_v;                 // a real instruction is in ID/EX
    assign ex_v = id_valid && !rd_q && q_run;

    // MEM/WB waiting for its bus response; MEM/WB access fault (MICROARCH H6, §6)
    logic mw_mem, mw_wait, mw_fault;
    assign mw_mem   = mw_valid && !mw_exc && (mw_load || mw_store);
    assign mw_wait  = mw_mem && !dbus_rvalid;
    assign mw_fault = mw_mem && dbus_rvalid && dbus_err;

    // Interrupts (SPEC §5.4): MEI > MSI > MTI [P §3.1.9]. WFI itself is never interrupted:
    // it retires and the next instruction takes the trap, so mepc = pc(WFI) + 4 [P §3.3.3].
    logic [31:0] irq_pend;
    assign irq_pend = mip & mie;
    assign irq_wake = |irq_pend;
    logic take_irq;
    assign take_irq = ex_v && mstatus_mie && irq_wake && !d_wfi;
    logic [31:0] irq_cause;
    assign irq_cause = irq_pend[11] ? C_INT_MEI : irq_pend[3] ? C_INT_MSI : C_INT_MTI;

    // Synchronous exceptions in ID/EX, in priority order (SPEC §5.2).
    logic        exc;
    logic [31:0] exc_cause, exc_tval;
    always_comb begin
        exc = 1'b1; exc_cause = C_ILL; exc_tval = 32'd0;
        if (ibus_err) begin
            exc_cause = C_IACC; exc_tval = id_pc;
        end else if (!d_legal || (d_csr && !csr_legal)) begin
            exc_cause = C_ILL; exc_tval = insn;
        end else if (taken && ctl_target[1]) begin
            exc_cause = C_IADDR_MIS; exc_tval = ctl_target;
        end else if (d_ecall) begin
            exc_cause = C_ECALL_M; exc_tval = 32'd0;
        end else if (d_ebreak) begin
            exc_cause = C_BREAK; exc_tval = id_pc;
        end else if ((d_load || d_store) && ls_misaligned) begin
            exc_cause = d_store ? C_SADDR_MIS : C_LADDR_MIS; exc_tval = ls_addr;
        end else begin
            exc = 1'b0;
        end
    end

    // H3 load-use, H10 WFI
    logic load_use, wfi_wait;
    assign load_use = mw_valid && mw_load && mw_wen &&
                      ((ra1 != 5'd0 && ra1 == mw_rd) || (ra2 != 5'd0 && ra2 == mw_rd));
    assign wfi_wait = d_wfi && !irq_wake;

    // ID/EX completes this cycle
    logic adv_ex, ex_trap, ex_normal;
    // An interrupt needs no operands, so it may be taken during a load-use stall. A synchronous
    // exception may depend on operands (misaligned address, jump target), so it waits like any
    // other instruction (formal bug 01, docs/DECISIONS.md "Bugs found by formal").
    assign adv_ex    = ex_v && !mw_wait && !mw_fault &&
                       (take_irq || (!load_use && (exc || !wfi_wait)));
    assign ex_trap   = adv_ex && (take_irq || exc);
    assign ex_normal = adv_ex && !take_irq && !exc;

    assign csr_we  = ex_normal && d_csr;
    assign mret_en = ex_normal && d_mret;

    // Retire in MEM/WB this cycle
    logic retire;
    assign retire      = mw_valid && !mw_wait;
    assign instret_inc = retire && !mw_exc && !mw_fault && !mw_no_instret;

    // Trap entry: MEM/WB access fault has priority (it is older); it squashes ID/EX.
    assign trap_en    = mw_fault || ex_trap;
    assign trap_cause = mw_fault ? (mw_store ? C_SACC : C_LACC) : take_irq ? irq_cause : exc_cause;
    assign trap_epc   = mw_fault ? mw_pc : id_pc;
    assign trap_tval  = mw_fault ? mw_addr : take_irq ? 32'd0 : exc_tval;

    // Redirect (registered): trap -> mtvec, MRET -> mepc, taken control transfer -> target
    logic        redirect;
    logic [31:0] redirect_pc;
    assign redirect    = trap_en || mret_en || (ex_normal && taken);
    assign redirect_pc = trap_en ? mtvec : mret_en ? mepc : ctl_target;

    // ================================================================ fetch
    logic if_hold;
    assign if_hold = mw_wait || (ex_v && !adv_ex) || (id_valid && !q_run);
    assign ibus_addr = rd_q ? rd_pc_q : if_hold ? id_pc : id_pc + 32'd4;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            id_valid <= 1'b0;
            id_pc    <= RESET_VEC - 32'd4;
            rd_q     <= 1'b0;
            rd_pc_q  <= 32'd0;
        end else if (!q_run && !id_valid) begin
            // Q_STOPPED out of reset: no fetch yet (ibus_addr = id_pc + 4 = RESET_VEC is fetched
            // every cycle and discarded until Q_RUN).
        end else begin
            if (rd_q && !mw_wait) begin
                id_pc    <= rd_pc_q;
                id_valid <= 1'b1;
                rd_q     <= 1'b0;
            end else if (!if_hold) begin
                id_pc    <= id_pc + 32'd4;
                id_valid <= 1'b1;
            end
            if (redirect) begin
                rd_q    <= 1'b1;
                rd_pc_q <= redirect_pc;
            end
        end
    end

    // ================================================================ D-port request
    assign dbus_req   = ex_normal && (d_load || d_store);
    assign dbus_we    = d_store;
    assign dbus_addr  = {ls_addr[31:2], 2'b00};
    assign dbus_be    = ls_be;
    assign dbus_wdata = st_data;

    // ================================================================ MEM/WB register
    logic [31:0] ex_result;
    assign ex_result = (d_wb_sel == 2'd1) ? pc4 : (d_wb_sel == 2'd2) ? csr_rdata : alu_y;

    logic mw_next_valid;
    assign mw_next_valid = adv_ex && !take_irq;   // normal instruction or exception record

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mw_valid <= 1'b0;
        end else if (!mw_wait) begin
            mw_valid <= mw_next_valid;
        end
    end

    always_ff @(posedge clk) begin
        if (!mw_wait) begin
            mw_exc        <= exc;
            mw_pc         <= id_pc;
            mw_rd         <= d_rd;
            mw_wen        <= !exc && d_rd_we && (d_rd != 5'd0);
            mw_result     <= ex_result;
            mw_load       <= d_load;
            mw_store      <= d_store;
            mw_funct3     <= d_funct3;
            mw_boff       <= ls_boff;
            mw_addr       <= ls_addr;
            mw_no_instret <= d_csr && csr_wr && (insn[31:20] == 12'hB02 || insn[31:20] == 12'hB82);
        end
    end

    // Load data alignment and extension
    logic [31:0] ld_shift, ld_data;
    assign ld_shift = dbus_rdata >> {mw_boff, 3'b000};
    always_comb begin
        case (mw_funct3)
            3'b000:  ld_data = {{24{ld_shift[7]}}, ld_shift[7:0]};    // LB
            3'b001:  ld_data = {{16{ld_shift[15]}}, ld_shift[15:0]};  // LH
            3'b100:  ld_data = {24'd0, ld_shift[7:0]};                // LBU
            3'b101:  ld_data = {16'd0, ld_shift[15:0]};               // LHU
            default: ld_data = ld_shift;                              // LW
        endcase
    end
    assign wb_data = mw_load ? ld_data : mw_result;
    assign rf_we   = retire && mw_wen && !mw_fault;

    // ================================================================ Q-Channel device FSM
    // P2 SPEC §2.2 device rules: QACCEPTn falls only with QREQn=0 and QDENY=0; rises only with
    // QREQn=1 and QDENY=0. QDENY rises only with QREQn=0 and QACCEPTn=1; falls only with QREQn=1.
    assign core_idle = id_valid && !rd_q && !ibus_err && d_wfi && wfi_wait && !mw_valid;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            qaccept_n <= 1'b0;   // Q_STOPPED at reset
            qdeny     <= 1'b0;
        end else if (qaccept_n && !qdeny) begin            // Q_RUN / Q_REQUEST
            if (!qreq_n) begin
                if (irq_wake)       qdeny     <= 1'b1;      // -> Q_DENIED
                else if (core_idle) qaccept_n <= 1'b0;      // -> Q_STOPPED
            end
        end else if (!qaccept_n) begin                     // Q_STOPPED
            if (qreq_n) qaccept_n <= 1'b1;                  // Q_EXIT -> Q_RUN
        end else begin                                      // Q_DENIED
            if (qreq_n) qdeny <= 1'b0;                      // Q_CONTINUE -> Q_RUN
        end
    end
    assign stopped_q = !qaccept_n;
    assign q_run     = !stopped_q;
    assign qactive   = !core_idle;

`ifdef RISCV_FORMAL
    // ================================================================ RVFI (MEM/WB retire)
    // Fields that are only known in ID/EX are captured with the instruction.
    logic [4:0]  mw_rs1a, mw_rs2a;
    logic [31:0] mw_rs1v, mw_rs2v, mw_wdata;
    logic [3:0]  mw_be;
    logic        mw_intr, intr_pending;
    logic        mw_csr_ms, mw_csr_mt, mw_csr_cy, mw_csr_ir, mw_csr_rd, mw_csr_wr;
    logic [31:0] mw_csr_rv, mw_csr_wv;
    logic [63:0] mw_cy_rd, mw_cy_wr, mw_ir_rd, mw_ir_wr;
    logic [31:0] mw_pc_next, mw_insn;

    always_ff @(posedge clk) begin
        if (!mw_wait) begin
            mw_pc_next <= exc ? mtvec : d_mret ? mepc : taken ? ctl_target : pc4;
            mw_insn  <= insn;
            mw_rs1a  <= ra1;
            mw_rs2a  <= ra2;
            mw_rs1v  <= rs1v;
            mw_rs2v  <= rs2v;
            mw_wdata <= st_data;
            mw_be    <= ls_be;
            mw_intr  <= intr_pending;
            mw_csr_ms <= d_csr && insn[31:20] == 12'h340;
            mw_csr_mt <= d_csr && insn[31:20] == 12'h343;
            mw_csr_cy <= d_csr && (insn[31:20] == 12'hB00 || insn[31:20] == 12'hB80);
            mw_csr_ir <= d_csr && (insn[31:20] == 12'hB02 || insn[31:20] == 12'hB82);
            mw_csr_rd <= d_csr && d_rd != 5'd0;
            mw_csr_wr <= d_csr && csr_wr;
            mw_csr_rv <= csr_rdata;
            mw_csr_wv <= csr_wdata;
            mw_cy_rd  <= mcycle_rd;
            mw_cy_wr  <= mcycle_wr;
            mw_ir_rd  <= minstret_rd;
            mw_ir_wr  <= minstret_wr;
        end
    end

    // The first instruction of a trap handler has rvfi_intr = 1.
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                  intr_pending <= 1'b0;
        else if (trap_en)            intr_pending <= 1'b1;
        else if (mw_next_valid && !mw_wait) intr_pending <= 1'b0;
    end

    logic [63:0] order_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)      order_q <= 64'd0;
        else if (retire) order_q <= order_q + 64'd1;
    end

    logic r_trap;
    assign r_trap = mw_exc || mw_fault;

    assign rvfi_valid     = retire;
    assign rvfi_order     = order_q;
    assign rvfi_insn      = mw_insn;
    assign rvfi_trap      = r_trap;
    assign rvfi_halt      = 1'b0;
    assign rvfi_intr      = mw_intr;
    assign rvfi_mode      = 2'd3;
    assign rvfi_ixl       = 2'd1;
    assign rvfi_rs1_addr  = mw_rs1a;
    assign rvfi_rs2_addr  = mw_rs2a;
    assign rvfi_rs1_rdata = mw_rs1v;
    assign rvfi_rs2_rdata = mw_rs2v;
    assign rvfi_rd_addr   = (mw_wen && !r_trap) ? mw_rd : 5'd0;
    assign rvfi_rd_wdata  = (mw_wen && !r_trap) ? wb_data : 32'd0;
    assign rvfi_pc_rdata  = mw_pc;
    assign rvfi_pc_wdata  = mw_fault ? mtvec : mw_pc_next;
    assign rvfi_mem_addr  = {mw_addr[31:2], 2'b00};
    assign rvfi_mem_rmask = (mw_load && !r_trap) ? mw_be : 4'd0;
    assign rvfi_mem_wmask = (mw_store && !r_trap) ? mw_be : 4'd0;
    assign rvfi_mem_rdata = dbus_rdata;
    assign rvfi_mem_wdata = mw_wdata;

    logic csr_ok;
    assign csr_ok = !r_trap;
    assign rvfi_csr_mscratch_rmask = (csr_ok && mw_csr_ms && mw_csr_rd) ? 32'hFFFF_FFFF : 32'd0;
    assign rvfi_csr_mscratch_wmask = (csr_ok && mw_csr_ms && mw_csr_wr) ? 32'hFFFF_FFFF : 32'd0;
    assign rvfi_csr_mscratch_rdata = mw_csr_rv;
    assign rvfi_csr_mscratch_wdata = mw_csr_wv;
    assign rvfi_csr_mtval_rmask    = (csr_ok && mw_csr_mt && mw_csr_rd) ? 32'hFFFF_FFFF : 32'd0;
    assign rvfi_csr_mtval_wmask    = (csr_ok && mw_csr_mt && mw_csr_wr) ? 32'hFFFF_FFFF : 32'd0;
    assign rvfi_csr_mtval_rdata    = mw_csr_rv;
    assign rvfi_csr_mtval_wdata    = mw_csr_wv;
    // Counters are reported as 64-bit values for every instruction (riscv-formal csrs.rst),
    // split into low/high 32-bit ports as RVFI_CONN32 expects.
    logic [63:0] cy_rmask, cy_wmask, ir_rmask, ir_wmask;
    assign cy_rmask = csr_ok ? 64'hFFFF_FFFF_FFFF_FFFF : 64'd0;
    assign cy_wmask = (csr_ok && mw_csr_cy && mw_csr_wr) ? 64'hFFFF_FFFF_FFFF_FFFF : 64'd0;
    assign ir_rmask = csr_ok ? 64'hFFFF_FFFF_FFFF_FFFF : 64'd0;
    assign ir_wmask = (csr_ok && mw_csr_ir && mw_csr_wr) ? 64'hFFFF_FFFF_FFFF_FFFF : 64'd0;
    assign {rvfi_csr_mcycleh_rmask,   rvfi_csr_mcycle_rmask}   = cy_rmask;
    assign {rvfi_csr_mcycleh_wmask,   rvfi_csr_mcycle_wmask}   = cy_wmask;
    assign {rvfi_csr_mcycleh_rdata,   rvfi_csr_mcycle_rdata}   = mw_cy_rd;
    assign {rvfi_csr_mcycleh_wdata,   rvfi_csr_mcycle_wdata}   = mw_cy_wr;
    assign {rvfi_csr_minstreth_rmask, rvfi_csr_minstret_rmask} = ir_rmask;
    assign {rvfi_csr_minstreth_wmask, rvfi_csr_minstret_wmask} = ir_wmask;
    assign {rvfi_csr_minstreth_rdata, rvfi_csr_minstret_rdata} = mw_ir_rd;
    assign {rvfi_csr_minstreth_wdata, rvfi_csr_minstret_wdata} = mw_ir_wr;
`else
    // Values that only the RVFI port uses.
    logic unused_rvfi;
    assign unused_rvfi = ^{csr_wdata, mcycle_rd, mcycle_wr, minstret_rd, minstret_wr};
`endif
endmodule
`default_nettype wire
