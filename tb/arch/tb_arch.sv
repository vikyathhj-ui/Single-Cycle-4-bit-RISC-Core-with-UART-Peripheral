// tb_arch: RISCOF DUT testbench (SIM memory configuration: IMEM 32 KB + DMEM 32 KB, D-007 S-4).
//
// lp_rv32_core + lp_rv32_xbar + two mem_1rw1r_sim + apb_bridge with no peripherals (every APB
// access faults). Reset vector = IMEM base (the arch tests link there; no boot ROM needed).
// IMEM sits at 0x8000_0000 here, not at the SoC's 0x1000_0000: Spike, the reference model, has a
// built-in UART at 0x1000_0000, and both must use the same addresses (D-015). Core RTL unchanged.
// +trace (RVFI build only, -DRISCV_FORMAL) prints every retired instruction.
// Plusargs (written by riscof/lp_rv32/riscof_lp_rv32.py):
//   +imem=<hex> +dmem=<hex>   word-per-line images from IMEM / DMEM base
//   +tohost=<hex addr>        a store to this address ends the test
//   +sig_begin=<hex> +sig_end=<hex> +sig=<file>   signature range and output file
//   +timeout=<cycles>         fail if tohost is not written in time (default 2,000,000)
// Exit: $finish after writing the signature; $fatal on timeout.
`default_nettype none
module tb_arch;
    localparam int AW = 13;
    localparam logic [31:0] IMEM_BASE = 32'h8000_0000;
    localparam logic [31:0] DMEM_BASE = 32'h2000_0000;

    logic clk = 1'b0;
    logic rst_n = 1'b0;
    always #5 clk = ~clk;

    // core <-> xbar
    logic [31:0] ibus_addr, ibus_rdata, dbus_addr, dbus_wdata, dbus_rdata;
    logic        ibus_err, dbus_req, dbus_we, dbus_rvalid, dbus_err;
    logic [3:0]  dbus_be;
    logic        qaccept_n, qdeny, qactive, core_idle, irq_wake;

    lp_rv32_core #(.RESET_VEC(IMEM_BASE)) u_core (
        .clk(clk), .rst_n(rst_n),
        .ibus_addr(ibus_addr), .ibus_rdata(ibus_rdata), .ibus_err(ibus_err),
        .dbus_req(dbus_req), .dbus_we(dbus_we), .dbus_addr(dbus_addr), .dbus_be(dbus_be),
        .dbus_wdata(dbus_wdata), .dbus_rvalid(dbus_rvalid), .dbus_rdata(dbus_rdata), .dbus_err(dbus_err),
        .irq_msip(1'b0), .irq_mtip(1'b0), .irq_meip(1'b0),
        .qreq_n(1'b1), .qaccept_n(qaccept_n), .qdeny(qdeny), .qactive(qactive),
        .core_idle(core_idle), .irq_wake(irq_wake)
    );

    // xbar <-> memories / bridge
    logic [5:0]    rom_iaddr, rom_daddr;
    logic          rom_den;
    logic          i_csb0, i_web0, i_csb1, d_csb0, d_web0;
    logic [3:0]    i_wmask0, d_wmask0;
    logic [AW-1:0] i_addr0, i_addr1, d_addr0;
    logic [31:0]   i_din0, i_dout0, i_dout1, d_din0, d_dout0;
    logic          br_req, br_we, br_rvalid, br_err;
    logic [15:0]   br_addr;
    logic [31:0]   br_wdata, br_rdata;

    lp_rv32_xbar #(.IMEM_AW(AW), .DMEM_AW(AW), .IMEM_BASE(IMEM_BASE), .DMEM_BASE(DMEM_BASE)) u_xbar (
        .clk(clk), .rst_n(rst_n),
        .ibus_addr(ibus_addr), .ibus_rdata(ibus_rdata), .ibus_err(ibus_err),
        .dbus_req(dbus_req), .dbus_we(dbus_we), .dbus_addr(dbus_addr), .dbus_be(dbus_be),
        .dbus_wdata(dbus_wdata), .dbus_rvalid(dbus_rvalid), .dbus_rdata(dbus_rdata), .dbus_err(dbus_err),
        .rom_iaddr(rom_iaddr), .rom_idata(32'd0), .rom_daddr(rom_daddr), .rom_den(rom_den), .rom_ddata(32'd0),
        .imem_csb0(i_csb0), .imem_web0(i_web0), .imem_wmask0(i_wmask0), .imem_addr0(i_addr0),
        .imem_din0(i_din0), .imem_dout0(i_dout0), .imem_csb1(i_csb1), .imem_addr1(i_addr1), .imem_dout1(i_dout1),
        .dmem_csb0(d_csb0), .dmem_web0(d_web0), .dmem_wmask0(d_wmask0), .dmem_addr0(d_addr0),
        .dmem_din0(d_din0), .dmem_dout0(d_dout0),
        .br_req(br_req), .br_we(br_we), .br_addr(br_addr), .br_wdata(br_wdata),
        .br_rvalid(br_rvalid), .br_rdata(br_rdata), .br_err(br_err)
    );

    mem_1rw1r_sim #(.AW(AW)) u_imem (
        .clk0(clk), .csb0(i_csb0), .web0(i_web0), .wmask0(i_wmask0), .addr0(i_addr0), .din0(i_din0), .dout0(i_dout0),
        .clk1(clk), .csb1(i_csb1), .addr1(i_addr1), .dout1(i_dout1)
    );
    logic [31:0] d_dout1_unused;
    mem_1rw1r_sim #(.AW(AW)) u_dmem (
        .clk0(clk), .csb0(d_csb0), .web0(d_web0), .wmask0(d_wmask0), .addr0(d_addr0), .din0(d_din0), .dout0(d_dout0),
        .clk1(clk), .csb1(1'b1), .addr1('0), .dout1(d_dout1_unused)
    );

    logic [15:0] psel, pready, pslverr;
    logic        penable, pwrite;
    logic [11:0] paddr;
    logic [31:0] pwdata;
    logic [31:0] prdata [16];
    assign pready  = '1;
    assign pslverr = '1;
    for (genvar s = 0; s < 16; s++) begin : g_prd
        assign prdata[s] = 32'd0;
    end
    apb_bridge #(.SLOT_PRESENT(16'h0000)) u_br (
        .clk(clk), .rst_n(rst_n), .req(br_req), .we(br_we), .addr(br_addr), .wdata(br_wdata),
        .rvalid(br_rvalid), .rdata(br_rdata), .err(br_err),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr)
    );

    // ---------------------------------------------------------------- test control
    string       imem_f, dmem_f, sig_f;
    logic [31:0] tohost, sig_begin, sig_end;
    longint      timeout, cycles;
    int          fd;

    function automatic logic [31:0] rd_word(input logic [31:0] a);
        if (((a ^ IMEM_BASE) >> (AW + 2)) == 0) return u_imem.mem[a[AW+1:2]];
        if (((a ^ DMEM_BASE) >> (AW + 2)) == 0) return u_dmem.mem[a[AW+1:2]];
        return 32'hDEAD_BEEF;
    endfunction

    initial begin
        if (!$value$plusargs("imem=%s", imem_f)) $fatal(1, "+imem missing");
        if (!$value$plusargs("dmem=%s", dmem_f)) $fatal(1, "+dmem missing");
        if (!$value$plusargs("sig=%s", sig_f)) $fatal(1, "+sig missing");
        if (!$value$plusargs("tohost=%h", tohost)) $fatal(1, "+tohost missing");
        if (!$value$plusargs("sig_begin=%h", sig_begin)) $fatal(1, "+sig_begin missing");
        if (!$value$plusargs("sig_end=%h", sig_end)) $fatal(1, "+sig_end missing");
        if (!$value$plusargs("timeout=%d", timeout)) timeout = 2000000;
        for (int i = 0; i < (1 << AW); i++) begin
            u_imem.mem[i] = 32'd0;
            u_dmem.mem[i] = 32'd0;
        end
        $readmemh(imem_f, u_imem.mem);
        $readmemh(dmem_f, u_dmem.mem);
        repeat (3) @(posedge clk);
        rst_n = 1'b1;
    end

    always @(posedge clk) begin
        if (rst_n) begin
            cycles = cycles + 1;
            if (dbus_req && dbus_we && dbus_addr == {tohost[31:2], 2'b00}) begin
                fd = $fopen(sig_f, "w");
                for (logic [31:0] a = sig_begin; a < sig_end; a += 4)
                    $fwrite(fd, "%08x\n", rd_word(a));
                $fclose(fd);
                $display("tb_arch: tohost written after %0d cycles, signature %08x..%08x -> %s",
                         cycles, sig_begin, sig_end, sig_f);
                $finish;
            end
            if (cycles >= timeout) $fatal(1, "tb_arch: timeout after %0d cycles", cycles);
        end else begin
            cycles = 0;
        end
    end

`ifdef RISCV_FORMAL
    bit trace;
    initial trace = $test$plusargs("trace");
    always @(posedge clk) begin
        if (trace && u_core.rvfi_valid)
            $display("retire %0d pc=%08x insn=%08x trap=%0d intr=%0d rd=x%0d=%08x mem=%08x r%0h w%0h",
                     u_core.rvfi_order, u_core.rvfi_pc_rdata, u_core.rvfi_insn, u_core.rvfi_trap,
                     u_core.rvfi_intr, u_core.rvfi_rd_addr, u_core.rvfi_rd_wdata, u_core.rvfi_mem_addr,
                     u_core.rvfi_mem_rmask, u_core.rvfi_mem_wmask);
    end
`endif
endmodule
`default_nettype wire
