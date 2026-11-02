// lp_rv32_soc: LP-RV32 microcontroller top level (docs/SPEC.md §1, §4, §8, §9; MEMORY_MAP.md).
//
// Domains (SPEC §8.1, D-007 S-7):
//   AON  : PMU (vendor/pmu, P2), TIMER, SYSCTRL, UART-RX wake detector, reset synchroniser,
//          isolation clamps. Clock: clk (never gated).
//   CORE : core, boot ROM, crossbar, APB bridge, IRQC.   PMU domain 0 (CPU), clock pd_clk[0].
//   PERI : UART, GPIO.                                     PMU domain 2 (PERI), clock pd_clk[2].
//   MEM  : IMEM, DMEM. Always powered; clocked by the CORE clock.
//   PMU domain 1 (DSP) is unused: an always-accepting Q-Channel stub and a switch model.
// Every signal leaving CORE or PERI towards another domain or a pad passes an isolation clamp
// (vendor/pmu/rtl/cells/iso_wrap.sv) driven by that domain's iso_en.
//
// Memory configuration: SIM (default) uses mem_1rw1r_sim, 32 KB each (AW = 13). With LP_GDS
// defined, IMEM and DMEM are sky130_sram_1kbyte_1rw1r_32x256_8 macros (AW = 8).
`default_nettype none
module lp_rv32_soc #(
    parameter int SIM_AW = 13                // SIM configuration: 2^13 words = 32 KB per memory
) (
    input  logic       clk,
    input  logic       rst_n,                // pin, asynchronous assert
    input  logic       boot_sel,             // strap: 1 = memory preloaded (SPEC §7)
    input  logic       uart_rxd,
    output logic       uart_txd,
    input  logic [7:0] gpio_i,
    output logic [7:0] gpio_o,
    output logic [7:0] gpio_oe
);
`ifdef LP_GDS
    localparam int AW = 8;
`else
    localparam int AW = SIM_AW;
`endif

    // ================================================================ reset (AON)
    logic rst_aon_n;
    rst_sync u_rst (.clk(clk), .rst_n_in(rst_n), .rst_n(rst_aon_n));

    // ================================================================ PMU (AON)
    localparam int NPD = 3;
    logic [NPD-1:0] qreq_n, qaccept_n, qdeny, qactive;
    logic [NPD-1:0] clk_en, pd_clk, iso_en, ret_save, ret_restore, pd_rst_n;
    logic [NPD-1:0] psw_trickle_en, psw_main_en, psw_trickle_ack, psw_main_ack;
    logic [7:0]     wake_irq;
    logic           pmu_irq;
    logic [7*NPD:0] pmu_state;

    logic        pmu_psel, ap_penable, ap_pwrite;    // ap_*: APB signals after CORE isolation
    logic [11:0] ap_paddr;
    logic [31:0] ap_pwdata, pmu_prdata;
    logic        pmu_pready, pmu_pslverr;

    pmu_top #(.N_PD(NPD), .HAS_RET(3'b000)) u_pmu (
        .PCLK(clk), .PRESETn(rst_aon_n),
        .PSEL(pmu_psel), .PENABLE(ap_penable), .PWRITE(ap_pwrite), .PADDR(ap_paddr),
        .PWDATA(ap_pwdata), .PRDATA(pmu_prdata), .PREADY(pmu_pready), .PSLVERR(pmu_pslverr),
        .QREQn(qreq_n), .QACCEPTn(qaccept_n), .QDENY(qdeny), .QACTIVE(qactive),
        .clk_en(clk_en), .pd_clk(pd_clk), .iso_en(iso_en), .ret_save(ret_save),
        .ret_restore(ret_restore), .rst_n(pd_rst_n),
        .psw_trickle_en(psw_trickle_en), .psw_main_en(psw_main_en),
        .psw_trickle_ack(psw_trickle_ack), .psw_main_ack(psw_main_ack),
        .wake_irq(wake_irq), .irq(pmu_irq), .pmu_state(pmu_state)
    );

    for (genvar d = 0; d < NPD; d++) begin : g_psw
        psw_model u_psw (.clk(clk), .rst_n(rst_aon_n), .trickle_en(psw_trickle_en[d]),
                         .main_en(psw_main_en[d]), .trickle_ack(psw_trickle_ack[d]),
                         .main_ack(psw_main_ack[d]));
    end

    logic clk_core, clk_peri, rst_core_n, rst_peri_n;
    assign clk_core   = pd_clk[0];
    assign clk_peri   = pd_clk[2];
    assign rst_core_n = pd_rst_n[0];
    assign rst_peri_n = pd_rst_n[2];

    qch_stub_dev u_q_dsp  (.clk(clk), .rst_n(pd_rst_n[1]), .qreq_n(qreq_n[1]),
                           .qaccept_n(qaccept_n[1]), .qdeny(qdeny[1]), .qactive(qactive[1]));
    qch_stub_dev u_q_peri (.clk(clk_peri), .rst_n(rst_peri_n), .qreq_n(qreq_n[2]),
                           .qaccept_n(qaccept_n[2]), .qdeny(qdeny[2]), .qactive(qactive[2]));

    // ================================================================ core (CORE)
    logic [31:0] ibus_addr, ibus_rdata, dbus_addr, dbus_wdata, dbus_rdata;
    logic        ibus_err, dbus_req, dbus_we, dbus_rvalid, dbus_err;
    logic [3:0]  dbus_be;
    logic        msip, mtip, meip, core_idle, irq_wake;

    lp_rv32_core #(.RESET_VEC(32'h0000_0000)) u_core (
        .clk(clk_core), .rst_n(rst_core_n),
        .ibus_addr(ibus_addr), .ibus_rdata(ibus_rdata), .ibus_err(ibus_err),
        .dbus_req(dbus_req), .dbus_we(dbus_we), .dbus_addr(dbus_addr), .dbus_be(dbus_be),
        .dbus_wdata(dbus_wdata), .dbus_rvalid(dbus_rvalid), .dbus_rdata(dbus_rdata), .dbus_err(dbus_err),
        .irq_msip(msip), .irq_mtip(mtip), .irq_meip(meip),
        .qreq_n(qreq_n[0]), .qaccept_n(qaccept_n[0]), .qdeny(qdeny[0]), .qactive(qactive[0]),
        .core_idle(core_idle), .irq_wake(irq_wake)
    );

    // ================================================================ crossbar + memories (CORE / MEM)
    logic [5:0]    rom_iaddr, rom_daddr;
    logic          rom_den;
    logic [31:0]   rom_idata, rom_ddata;
    logic          i_csb0, i_web0, i_csb1, d_csb0, d_web0;
    logic [3:0]    i_wmask0, d_wmask0;
    logic [AW-1:0] i_addr0, i_addr1, d_addr0;
    logic [31:0]   i_din0, i_dout0, i_dout1, d_din0, d_dout0, d_dout1;
    logic          br_req, br_we, br_rvalid, br_err;
    logic [15:0]   br_addr;
    logic [31:0]   br_wdata, br_rdata;

    lp_rv32_xbar #(.IMEM_AW(AW), .DMEM_AW(AW)) u_xbar (
        .clk(clk_core), .rst_n(rst_core_n),
        .ibus_addr(ibus_addr), .ibus_rdata(ibus_rdata), .ibus_err(ibus_err),
        .dbus_req(dbus_req), .dbus_we(dbus_we), .dbus_addr(dbus_addr), .dbus_be(dbus_be),
        .dbus_wdata(dbus_wdata), .dbus_rvalid(dbus_rvalid), .dbus_rdata(dbus_rdata), .dbus_err(dbus_err),
        .rom_iaddr(rom_iaddr), .rom_idata(rom_idata), .rom_daddr(rom_daddr), .rom_den(rom_den),
        .rom_ddata(rom_ddata),
        .imem_csb0(i_csb0), .imem_web0(i_web0), .imem_wmask0(i_wmask0), .imem_addr0(i_addr0),
        .imem_din0(i_din0), .imem_dout0(i_dout0), .imem_csb1(i_csb1), .imem_addr1(i_addr1),
        .imem_dout1(i_dout1),
        .dmem_csb0(d_csb0), .dmem_web0(d_web0), .dmem_wmask0(d_wmask0), .dmem_addr0(d_addr0),
        .dmem_din0(d_din0), .dmem_dout0(d_dout0),
        .br_req(br_req), .br_we(br_we), .br_addr(br_addr), .br_wdata(br_wdata),
        .br_rvalid(br_rvalid), .br_rdata(br_rdata), .br_err(br_err)
    );

    bootrom u_rom (.clk(clk_core), .iaddr(rom_iaddr), .idata(rom_idata),
                   .daddr(rom_daddr), .den(rom_den), .ddata(rom_ddata));

`ifdef LP_GDS
    sky130_sram_1kbyte_1rw1r_32x256_8 u_imem (
        .clk0(clk_core), .csb0(i_csb0), .web0(i_web0), .wmask0(i_wmask0), .addr0(i_addr0),
        .din0(i_din0), .dout0(i_dout0), .clk1(clk_core), .csb1(i_csb1), .addr1(i_addr1), .dout1(i_dout1));
    sky130_sram_1kbyte_1rw1r_32x256_8 u_dmem (
        .clk0(clk_core), .csb0(d_csb0), .web0(d_web0), .wmask0(d_wmask0), .addr0(d_addr0),
        .din0(d_din0), .dout0(d_dout0), .clk1(clk_core), .csb1(1'b1), .addr1('0), .dout1(d_dout1));
`else
    mem_1rw1r_sim #(.AW(AW)) u_imem (
        .clk0(clk_core), .csb0(i_csb0), .web0(i_web0), .wmask0(i_wmask0), .addr0(i_addr0),
        .din0(i_din0), .dout0(i_dout0), .clk1(clk_core), .csb1(i_csb1), .addr1(i_addr1), .dout1(i_dout1));
    mem_1rw1r_sim #(.AW(AW)) u_dmem (
        .clk0(clk_core), .csb0(d_csb0), .web0(d_web0), .wmask0(d_wmask0), .addr0(d_addr0),
        .din0(d_din0), .dout0(d_dout0), .clk1(clk_core), .csb1(1'b1), .addr1('0), .dout1(d_dout1));
`endif

    // ================================================================ APB bridge (CORE)
    logic [15:0] psel;
    logic        penable, pwrite;
    logic [11:0] paddr;
    logic [31:0] pwdata;
    logic [31:0] prdata [16];
    logic [15:0] pready, pslverr;

    apb_bridge #(.SLOT_PRESENT(16'h003F)) u_br (
        .clk(clk_core), .rst_n(rst_core_n), .req(br_req), .we(br_we), .addr(br_addr), .wdata(br_wdata),
        .rvalid(br_rvalid), .rdata(br_rdata), .err(br_err),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr)
    );

    // CORE -> AON / PERI: APB request signals clamped to 0 while CORE is isolated.
    logic [15:0] ap_psel;
    for (genvar i = 0; i < 16; i++) begin : g_iso_psel
        iso_wrap #(.CLAMP(1'b0)) u_iso (.d(psel[i]), .iso_en(iso_en[0]), .q(ap_psel[i]));
    end
    iso_wrap #(.CLAMP(1'b0)) u_iso_pen (.d(penable), .iso_en(iso_en[0]), .q(ap_penable));
    iso_wrap #(.CLAMP(1'b0)) u_iso_pwr (.d(pwrite),  .iso_en(iso_en[0]), .q(ap_pwrite));
    for (genvar i = 0; i < 12; i++) begin : g_iso_paddr
        iso_wrap #(.CLAMP(1'b0)) u_iso (.d(paddr[i]), .iso_en(iso_en[0]), .q(ap_paddr[i]));
    end
    for (genvar i = 0; i < 32; i++) begin : g_iso_pwdata
        iso_wrap #(.CLAMP(1'b0)) u_iso (.d(pwdata[i]), .iso_en(iso_en[0]), .q(ap_pwdata[i]));
    end
    assign pmu_psel = ap_psel[5];

    // ================================================================ PERI: UART, GPIO
    logic [31:0] uart_prdata, gpio_prdata;
    logic        uart_pready, uart_pslverr, gpio_pready, gpio_pslverr, uart_irq, gpio_irq, uart_txd_p;
    logic [7:0]  gpio_o_p, gpio_oe_p;

    uart_lite u_uart (
        .clk(clk_peri), .rst_n(rst_peri_n),
        .psel(ap_psel[0]), .penable(ap_penable), .pwrite(ap_pwrite), .paddr(ap_paddr), .pwdata(ap_pwdata),
        .prdata(uart_prdata), .pready(uart_pready), .pslverr(uart_pslverr),
        .rxd(uart_rxd), .txd(uart_txd_p), .irq(uart_irq)
    );
    gpio8 u_gpio (
        .clk(clk_peri), .rst_n(rst_peri_n),
        .psel(ap_psel[1]), .penable(ap_penable), .pwrite(ap_pwrite), .paddr(ap_paddr), .pwdata(ap_pwdata),
        .prdata(gpio_prdata), .pready(gpio_pready), .pslverr(gpio_pslverr),
        .gpio_i(gpio_i), .gpio_o(gpio_o_p), .gpio_oe(gpio_oe_p), .irq(gpio_irq)
    );

    // PERI -> outside: clamp while PERI is isolated. APB response clamps to an error (PREADY=1,
    // PSLVERR=1, PRDATA=0) so an access to a powered-off peripheral cannot hang the bridge.
    logic [31:0] uart_prdata_i, gpio_prdata_i;
    logic        uart_pready_i, uart_pslverr_i, gpio_pready_i, gpio_pslverr_i, uart_irq_i, gpio_irq_i;
    for (genvar i = 0; i < 32; i++) begin : g_iso_prdata
        iso_wrap #(.CLAMP(1'b0)) u_iso_u (.d(uart_prdata[i]), .iso_en(iso_en[2]), .q(uart_prdata_i[i]));
        iso_wrap #(.CLAMP(1'b0)) u_iso_g (.d(gpio_prdata[i]), .iso_en(iso_en[2]), .q(gpio_prdata_i[i]));
    end
    iso_wrap #(.CLAMP(1'b1)) u_iso_urdy (.d(uart_pready),  .iso_en(iso_en[2]), .q(uart_pready_i));
    iso_wrap #(.CLAMP(1'b1)) u_iso_uerr (.d(uart_pslverr), .iso_en(iso_en[2]), .q(uart_pslverr_i));
    iso_wrap #(.CLAMP(1'b1)) u_iso_grdy (.d(gpio_pready),  .iso_en(iso_en[2]), .q(gpio_pready_i));
    iso_wrap #(.CLAMP(1'b1)) u_iso_gerr (.d(gpio_pslverr), .iso_en(iso_en[2]), .q(gpio_pslverr_i));
    iso_wrap #(.CLAMP(1'b0)) u_iso_uirq (.d(uart_irq),     .iso_en(iso_en[2]), .q(uart_irq_i));
    iso_wrap #(.CLAMP(1'b0)) u_iso_girq (.d(gpio_irq),     .iso_en(iso_en[2]), .q(gpio_irq_i));
    iso_wrap #(.CLAMP(1'b1)) u_iso_txd  (.d(uart_txd_p),   .iso_en(iso_en[2]), .q(uart_txd));   // line idles high
    for (genvar i = 0; i < 8; i++) begin : g_iso_gpio
        iso_wrap #(.CLAMP(1'b0)) u_iso_o  (.d(gpio_o_p[i]),  .iso_en(iso_en[2]), .q(gpio_o[i]));
        iso_wrap #(.CLAMP(1'b0)) u_iso_oe (.d(gpio_oe_p[i]), .iso_en(iso_en[2]), .q(gpio_oe[i]));
    end

    // ================================================================ AON: TIMER, SYSCTRL, wake detector
    logic [31:0] tmr_prdata, sys_prdata;
    logic        tmr_pready, tmr_pslverr, sys_pready, sys_pslverr, uart_wake_en, uart_wake;

    timer_clint u_timer (
        .clk(clk), .rst_n(rst_aon_n),
        .psel(ap_psel[2]), .penable(ap_penable), .pwrite(ap_pwrite), .paddr(ap_paddr), .pwdata(ap_pwdata),
        .prdata(tmr_prdata), .pready(tmr_pready), .pslverr(tmr_pslverr), .msip(msip), .mtip(mtip)
    );
    sysctrl u_sys (
        .clk(clk), .rst_n(rst_aon_n),
        .psel(ap_psel[4]), .penable(ap_penable), .pwrite(ap_pwrite), .paddr(ap_paddr), .pwdata(ap_pwdata),
        .prdata(sys_prdata), .pready(sys_pready), .pslverr(sys_pslverr),
        .boot_sel(boot_sel), .core_pwr_up(psw_main_ack[0]), .wake(wake_irq[2:0]), .uart_wake_en(uart_wake_en)
    );
    uart_wake u_uwake (.clk(clk), .rst_n(rst_aon_n), .en(uart_wake_en), .rxd(uart_rxd), .wake(uart_wake));

    // CORE -> AON: the core's wake request is clamped while CORE is isolated.
    logic irq_wake_i;
    iso_wrap #(.CLAMP(1'b0)) u_iso_wake (.d(irq_wake), .iso_en(iso_en[0]), .q(irq_wake_i));
    assign wake_irq = {5'd0, mtip, uart_wake, irq_wake_i};       // SPEC §8.2-8.4, MEMORY_MAP WAKE_SRC

    // ================================================================ IRQC (CORE)
    logic [31:0] irqc_prdata;
    logic        irqc_pready, irqc_pslverr;
    irqc8 u_irqc (
        .clk(clk_core), .rst_n(rst_core_n),
        .psel(psel[3]), .penable(penable), .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata),
        .prdata(irqc_prdata), .pready(irqc_pready), .pslverr(irqc_pslverr),
        .src({5'd0, pmu_irq, gpio_irq_i, uart_irq_i}), .meip(meip)
    );

    // ================================================================ APB response mux inputs
    always_comb begin
        for (int s = 0; s < 16; s++) prdata[s] = 32'd0;
        prdata[0] = uart_prdata_i;
        prdata[1] = gpio_prdata_i;
        prdata[2] = tmr_prdata;
        prdata[3] = irqc_prdata;
        prdata[4] = sys_prdata;
        prdata[5] = pmu_prdata;
    end
    assign pready  = {10'h3FF, pmu_pready, sys_pready, irqc_pready, tmr_pready, gpio_pready_i, uart_pready_i};
    assign pslverr = {10'h3FF, pmu_pslverr, sys_pslverr, irqc_pslverr, tmr_pslverr, gpio_pslverr_i, uart_pslverr_i};

    // Outputs not used in this SoC (debug bus, retention: HAS_RET = 0, core_idle is internal to the
    // Q-Channel handshake, D-port of DMEM port 1).
    logic unused_soc;
    assign unused_soc = ^{pmu_state, ret_save, ret_restore, clk_en, core_idle, d_dout1, pd_clk[1],
                          iso_en[1], ap_psel[15:6], ap_psel[3]};   // IRQC (CORE) uses psel[3] directly
endmodule
`default_nettype wire
