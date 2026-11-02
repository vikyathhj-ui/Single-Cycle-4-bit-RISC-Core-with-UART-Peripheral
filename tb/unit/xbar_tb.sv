// xbar_tb: unit-test wrapper for lp_rv32_xbar + apb_bridge (BRIEF A5 "crossbar and APB bridge").
// The cocotb test (tb/unit/test_xbar.py) drives the core-side I and D ports.
//  * IMEM / DMEM: mem_1rw1r_sim with AW = 6 (256 B each), so addresses past the end of a region
//    are inside its 256 MB window but unmapped.
//  * ROM model: data = 32'hC0DE_0000 | word index, address registered (same contract as bootrom).
//  * APB slave model behind every present slot (SLOT_PRESENT = 16'h00FF; slots 8-15 absent):
//    16 words per slot, PREADY after `slv_wait` wait states, PSLVERR = `slv_err`; both are sampled
//    at the start of each transfer and driven by the test.
//  * APB protocol assertions (IHI 0024E §3, §4.1) on the bridge's master side.
`default_nettype none
module xbar_tb (
    input  logic        clk,
    input  logic        rst_n,
    input  logic [31:0] ibus_addr,
    output logic [31:0] ibus_rdata,
    output logic        ibus_err,
    input  logic        dbus_req,
    input  logic        dbus_we,
    input  logic [31:0] dbus_addr,
    input  logic [3:0]  dbus_be,
    input  logic [31:0] dbus_wdata,
    output logic        dbus_rvalid,
    output logic [31:0] dbus_rdata,
    output logic        dbus_err,
    input  logic [3:0]  slv_wait,
    input  logic        slv_err,
    output logic        apb_violation
);
    localparam int AW = 6;
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
        .clk(clk), .rst_n(rst_n),
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

    mem_1rw1r_sim #(.AW(AW)) u_imem (
        .clk0(clk), .csb0(i_csb0), .web0(i_web0), .wmask0(i_wmask0), .addr0(i_addr0), .din0(i_din0),
        .dout0(i_dout0), .clk1(clk), .csb1(i_csb1), .addr1(i_addr1), .dout1(i_dout1));
    mem_1rw1r_sim #(.AW(AW)) u_dmem (
        .clk0(clk), .csb0(d_csb0), .web0(d_web0), .wmask0(d_wmask0), .addr0(d_addr0), .din0(d_din0),
        .dout0(d_dout0), .clk1(clk), .csb1(1'b1), .addr1('0), .dout1(d_dout1));

    // ROM model
    logic [5:0] ria_q, rda_q;
    always_ff @(posedge clk) begin
        ria_q <= rom_iaddr;
        if (rom_den) rda_q <= rom_daddr;
    end
    assign rom_idata = 32'hC0DE_0000 | {26'd0, ria_q};
    assign rom_ddata = 32'hC0DE_0000 | {26'd0, rda_q};

    // APB bridge + slave model
    logic [15:0] psel, pready, pslverr;
    logic        penable, pwrite;
    logic [11:0] paddr;
    logic [31:0] pwdata;
    logic [31:0] prdata [16];

    apb_bridge #(.SLOT_PRESENT(16'h00FF)) u_br (
        .clk(clk), .rst_n(rst_n), .req(br_req), .we(br_we), .addr(br_addr), .wdata(br_wdata),
        .rvalid(br_rvalid), .rdata(br_rdata), .err(br_err),
        .psel(psel), .penable(penable), .pwrite(pwrite), .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr)
    );

    logic [31:0] slv_mem [16][16];
    logic [3:0]  wcnt, wtarget;
    logic        werr;
    logic [3:0]  sel_idx;
    always_comb begin
        sel_idx = 4'd0;
        for (int s = 0; s < 16; s++) if (psel[s]) sel_idx = s[3:0];
    end
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            wcnt <= '0; wtarget <= '0; werr <= 1'b0;
            for (int s = 0; s < 16; s++) for (int w = 0; w < 16; w++) slv_mem[s][w] <= 32'h5000_0000 | (s << 8) | w;
        end else if (|psel && !penable) begin                 // SETUP: sample this transfer's behaviour
            wcnt <= '0; wtarget <= slv_wait; werr <= slv_err;
        end else if (|psel && penable) begin
            if (wcnt == wtarget) begin
                if (pwrite && !werr) slv_mem[sel_idx][paddr[5:2]] <= pwdata;
            end else begin
                wcnt <= wcnt + 4'd1;
            end
        end
    end
    for (genvar s = 0; s < 16; s++) begin : g_slv
        assign prdata[s]  = (psel[s] && penable && wcnt == wtarget && !pwrite) ? slv_mem[s][paddr[5:2]] : 32'hX;
        assign pready[s]  = psel[s] && penable && wcnt == wtarget;
        assign pslverr[s] = psel[s] && penable && wcnt == wtarget && werr;
    end

    // APB protocol checks on the master side (sticky flag read by the test)
    logic        p_sel_q, p_en_q, p_wr_q, p_done_q;
    logic [11:0] p_addr_q;
    logic [31:0] p_wd_q;
    logic [15:0] p_psel_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            apb_violation <= 1'b0; p_sel_q <= 1'b0; p_en_q <= 1'b0; p_done_q <= 1'b0;
            p_wr_q <= 1'b0; p_addr_q <= '0; p_wd_q <= '0; p_psel_q <= '0;
        end else begin
            if ((psel & (psel - 16'd1)) != 16'd0) apb_violation <= 1'b1;              // one-hot
            if (penable && !(|psel)) apb_violation <= 1'b1;                           // PENABLE needs PSEL
            if (penable && !p_en_q && !p_sel_q) apb_violation <= 1'b1;                // ACCESS without SETUP
            if (|psel && !penable && p_en_q && !p_done_q) apb_violation <= 1'b1;      // access abandoned
            if (p_en_q && !p_done_q && (psel != p_psel_q || paddr != p_addr_q || pwrite != p_wr_q ||
                (pwrite && pwdata != p_wd_q)))
                apb_violation <= 1'b1;                                               // stable while waiting
            p_sel_q  <= |psel;
            p_en_q   <= penable;
            p_done_q <= penable && |(pready & psel);
            p_psel_q <= psel;
            p_addr_q <= paddr;
            p_wr_q   <= pwrite;
            p_wd_q   <= pwdata;
        end
    end

    logic unused_tb;
    assign unused_tb = ^{d_dout1, slv_mem[15][15]};
endmodule
`default_nettype wire
