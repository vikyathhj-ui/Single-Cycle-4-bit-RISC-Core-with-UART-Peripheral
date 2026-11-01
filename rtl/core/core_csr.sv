// core_csr: machine-mode CSRs, trap entry and MRET (docs/SPEC.md §3, §5; MICROARCH.md §8).
//
// One CSR instruction is executed per cycle in ID/EX. The core supplies the address, the
// operation and the operand. This block returns the old value and the legality, and commits
// the new value at the clock edge when `we` is set. Trap entry and MRET commit the same way.
// At most one of we / trap_en / mret_en is set in a cycle (the core guarantees it).
`default_nettype none
module core_csr (
    input  logic        clk,
    input  logic        rst_n,
    // CSR instruction (ID/EX)
    input  logic [11:0] addr,
    input  logic [1:0]  op,          // funct3[1:0]: 01 RW, 10 RS, 11 RC
    input  logic [31:0] operand,     // rs1 value or zero-extended uimm
    input  logic        wr,          // the instruction writes the CSR (SPEC §2.2)
    input  logic        we,          // commit the write at this edge
    output logic [31:0] rdata,       // old value
    output logic [31:0] wdata,       // value the CSR holds after the write (WARL applied)
    output logic        legal,
    // retire of an older instruction in MEM/WB this cycle (minstret, MICROARCH H8)
    input  logic        instret_inc,
    // trap entry / return
    input  logic        trap_en,
    input  logic [31:0] trap_cause,
    input  logic [31:0] trap_epc,
    input  logic [31:0] trap_tval,
    input  logic        mret_en,
    // interrupt lines (levels)
    input  logic        irq_msip,
    input  logic        irq_mtip,
    input  logic        irq_meip,
    // state used by the pipeline
    output logic        mstatus_mie,
    output logic [31:0] mtvec,
    output logic [31:0] mepc,
    output logic [31:0] mip,
    output logic [31:0] mie,
    // 64-bit counters for RVFI: value read by this instruction, and after its write
    output logic [63:0] mcycle_rd,
    output logic [63:0] mcycle_wr,
    output logic [63:0] minstret_rd,
    output logic [63:0] minstret_wr
);
    localparam logic [31:0] MISA = 32'h4000_0100;   // MXL = 1, I (SPEC §3, S-3)

    // ---------------------------------------------------------------- state
    logic        st_mie, st_mpie;
    logic [2:0]  st_ie;          // {MEIE, MTIE, MSIE}
    logic [29:0] st_mtvec;
    logic [31:0] st_mscratch;
    logic [29:0] st_mepc;
    logic        st_cause_int;
    logic [3:0]  st_cause_code;
    logic [31:0] st_mtval;
    logic [63:0] st_mcycle, st_minstret;

    assign mstatus_mie = st_mie;
    assign mtvec       = {st_mtvec, 2'b00};
    assign mepc        = {st_mepc, 2'b00};
    assign mip         = {20'd0, irq_meip, 3'd0, irq_mtip, 3'd0, irq_msip, 3'd0};
    assign mie         = {20'd0, st_ie[2], 3'd0, st_ie[1], 3'd0, st_ie[0], 3'd0};

    logic [63:0] instret_cur;
    assign instret_cur = st_minstret + {63'd0, instret_inc};

    // ---------------------------------------------------------------- read
    logic implemented;
    always_comb begin
        implemented = 1'b1;
        rdata       = 32'd0;
        case (addr)
            12'hF11, 12'hF12, 12'hF13, 12'hF14, 12'hF15: rdata = 32'd0;   // RO-0 IDs
            12'h300: rdata = {19'd0, 2'b11, 3'd0, st_mpie, 3'd0, st_mie, 3'd0};
            12'h301: rdata = MISA;
            12'h304: rdata = mie;
            12'h305: rdata = mtvec;
            12'h310: rdata = 32'd0;                                         // mstatush
            12'h340: rdata = st_mscratch;
            12'h341: rdata = mepc;
            12'h342: rdata = {st_cause_int, 27'd0, st_cause_code};
            12'h343: rdata = st_mtval;
            12'h344: rdata = mip;
            12'hB00: rdata = st_mcycle[31:0];
            12'hB80: rdata = st_mcycle[63:32];
            12'hB02: rdata = instret_cur[31:0];
            12'hB82: rdata = instret_cur[63:32];
            default: begin
                // mhpmcounter3-31(h) and mhpmevent3-31: RO-0 [P §3.1.10]
                if ((addr >= 12'hB03 && addr <= 12'hB1F) || (addr >= 12'hB83 && addr <= 12'hB9F) ||
                    (addr >= 12'h323 && addr <= 12'h33F))
                    rdata = 32'd0;
                else
                    implemented = 1'b0;
            end
        endcase
    end

    // Read-only CSR addresses (bits [11:10] = 11) trap on a write [P §2.1].
    assign legal = implemented && !(wr && addr[11:10] == 2'b11);

    // ---------------------------------------------------------------- new value
    logic [31:0] nv;
    always_comb begin
        case (op)
            2'b01:   nv = operand;
            2'b10:   nv = rdata | operand;
            2'b11:   nv = rdata & ~operand;
            default: nv = rdata;
        endcase
    end

    // Value after the write, with WARL masks applied (what the CSR will read back).
    always_comb begin
        wdata = rdata;
        if (wr) begin
            case (addr)
                12'h300: wdata = {19'd0, 2'b11, 3'd0, nv[7], 3'd0, nv[3], 3'd0};
                12'h304: wdata = {20'd0, nv[11], 3'd0, nv[7], 3'd0, nv[3], 3'd0};
                12'h305: wdata = {nv[31:2], 2'b00};
                12'h340: wdata = nv;
                12'h341: wdata = {nv[31:2], 2'b00};
                12'h342: wdata = {nv[31], 27'd0, nv[3:0]};
                12'h343: wdata = nv;
                12'hB00, 12'hB80, 12'hB02, 12'hB82: wdata = nv;
                default: wdata = rdata;                                      // read-only views
            endcase
        end
    end

    logic w;
    assign w = we && wr;

    // mcause keeps only the Interrupt bit and a 4-bit code (WLRL); mepc bits 1:0 are zero.
    logic unused_trap_bits;
    assign unused_trap_bits = ^{trap_cause[30:4], trap_epc[1:0]};

    // Counters: what this instruction reads, and the value after it (RVFI, MICROARCH H8).
    assign mcycle_rd   = st_mcycle;
    assign mcycle_wr   = (w && addr == 12'hB00) ? {st_mcycle[63:32], nv} :
                         (w && addr == 12'hB80) ? {nv, st_mcycle[31:0]} : st_mcycle;
    assign minstret_rd = instret_cur;
    assign minstret_wr = (w && addr == 12'hB02) ? {instret_cur[63:32], nv} :
                         (w && addr == 12'hB82) ? {nv, instret_cur[31:0]} : instret_cur;

    // ---------------------------------------------------------------- update
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st_mie        <= 1'b0;
            st_mpie       <= 1'b0;
            st_ie         <= 3'd0;
            st_mtvec      <= 30'd0;
            st_mscratch   <= 32'd0;
            st_mepc       <= 30'd0;
            st_cause_int  <= 1'b0;
            st_cause_code <= 4'd0;
            st_mtval      <= 32'd0;
            st_mcycle     <= 64'd0;
            st_minstret   <= 64'd0;
        end else begin
            // Counters (a write overrides the increment, SPEC §3).
            if (w && (addr == 12'hB00 || addr == 12'hB80)) st_mcycle <= mcycle_wr;
            else                                           st_mcycle <= st_mcycle + 64'd1;
            st_minstret <= minstret_wr;

            if (trap_en) begin                                  // [P §3.1.6.1], SPEC §5.3
                st_mpie       <= st_mie;
                st_mie        <= 1'b0;
                st_mepc       <= trap_epc[31:2];
                st_cause_int  <= trap_cause[31];
                st_cause_code <= trap_cause[3:0];
                st_mtval      <= trap_tval;
            end else if (mret_en) begin                         // [P §3.3.2]
                st_mie  <= st_mpie;
                st_mpie <= 1'b1;
            end else if (w) begin
                case (addr)
                    12'h300: begin st_mie <= nv[3]; st_mpie <= nv[7]; end
                    12'h304: st_ie <= {nv[11], nv[7], nv[3]};
                    12'h305: st_mtvec <= nv[31:2];
                    12'h340: st_mscratch <= nv;
                    12'h341: st_mepc <= nv[31:2];
                    12'h342: begin st_cause_int <= nv[31]; st_cause_code <= nv[3:0]; end
                    12'h343: st_mtval <= nv;
                    default: ;
                endcase
            end
        end
    end
endmodule
`default_nettype wire
