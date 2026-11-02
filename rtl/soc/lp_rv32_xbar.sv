// lp_rv32_xbar: address decode and response mux between the core's I/D ports and the memories /
// APB bridge (docs/SPEC.md §4, docs/MICROARCH.md §5, docs/MEMORY_MAP.md).
//
// The I-port and D-port never compete: IMEM has separate ports (port 1 fetch, port 0 data) and the
// boot ROM has two read ports. So this is a decoder plus response muxes; no arbiter.
//  * I-port: BOOTROM and IMEM only; anything else -> ibus_err (instruction access fault).
//  * D-port: BOOTROM (read only), IMEM, DMEM, APB window (32-bit accesses only). A store to the ROM,
//    a byte/halfword APB access or an unmapped address gets an error response without a bus access
//    (load/store access fault).
// Responses: memories and errors answer in the next cycle; the APB bridge answers when it is done.
`default_nettype none
module lp_rv32_xbar #(
    parameter int IMEM_AW = 13,            // word-address bits (13 = 32 KB SIM, 8 = 1 KB GDS)
    parameter int DMEM_AW = 13,
    parameter int ROM_AW  = 6,             // 64 words = 256 B
    // Region bases (docs/MEMORY_MAP.md). Only the RISCOF testbench overrides IMEM_BASE (D-015).
    parameter logic [31:0] IMEM_BASE = 32'h1000_0000,
    parameter logic [31:0] DMEM_BASE = 32'h2000_0000
) (
    input  logic                clk,
    input  logic                rst_n,
    // core I-port
    input  logic [31:0]         ibus_addr,
    output logic [31:0]         ibus_rdata,
    output logic                ibus_err,
    // core D-port
    input  logic                dbus_req,
    input  logic                dbus_we,
    input  logic [31:0]         dbus_addr,
    input  logic [3:0]          dbus_be,
    input  logic [31:0]         dbus_wdata,
    output logic                dbus_rvalid,
    output logic [31:0]         dbus_rdata,
    output logic                dbus_err,
    // boot ROM (registered address inside the ROM)
    output logic [ROM_AW-1:0]   rom_iaddr,
    input  logic [31:0]         rom_idata,
    output logic [ROM_AW-1:0]   rom_daddr,
    output logic                rom_den,
    input  logic [31:0]         rom_ddata,
    // IMEM (1rw1r)
    output logic                imem_csb0,
    output logic                imem_web0,
    output logic [3:0]          imem_wmask0,
    output logic [IMEM_AW-1:0]  imem_addr0,
    output logic [31:0]         imem_din0,
    input  logic [31:0]         imem_dout0,
    output logic                imem_csb1,
    output logic [IMEM_AW-1:0]  imem_addr1,
    input  logic [31:0]         imem_dout1,
    // DMEM (port 0 only)
    output logic                dmem_csb0,
    output logic                dmem_web0,
    output logic [3:0]          dmem_wmask0,
    output logic [DMEM_AW-1:0]  dmem_addr0,
    output logic [31:0]         dmem_din0,
    input  logic [31:0]         dmem_dout0,
    // APB bridge request side
    output logic                br_req,
    output logic                br_we,
    output logic [15:0]         br_addr,
    output logic [31:0]         br_wdata,
    input  logic                br_rvalid,
    input  logic [31:0]         br_rdata,
    input  logic                br_err
);
    localparam logic [31:0] ROM_BASE  = 32'h0000_0000;
    localparam logic [31:0] APB_BASE  = 32'h4000_0000;

    // Region match: base bits above the region size must equal the base.
    function automatic logic in_region(input logic [31:0] a, input logic [31:0] base, input int bits);
        in_region = ((a ^ base) >> bits) == 32'd0;
    endfunction

    typedef enum logic [2:0] {S_NONE, S_ROM, S_IMEM, S_DMEM, S_APB} sel_e;

    // ---------------------------------------------------------------- I-port
    sel_e isel, isel_q;
    always_comb begin
        if (in_region(ibus_addr, ROM_BASE, ROM_AW + 2))        isel = S_ROM;
        else if (in_region(ibus_addr, IMEM_BASE, IMEM_AW + 2)) isel = S_IMEM;
        else                                                   isel = S_NONE;
    end
    assign rom_iaddr  = ibus_addr[ROM_AW+1:2];
    assign imem_csb1  = (isel != S_IMEM);
    assign imem_addr1 = ibus_addr[IMEM_AW+1:2];

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) isel_q <= S_NONE;
        else        isel_q <= isel;
    end
    assign ibus_rdata = (isel_q == S_ROM) ? rom_idata : imem_dout1;
    assign ibus_err   = (isel_q != S_ROM) && (isel_q != S_IMEM);

    // ---------------------------------------------------------------- D-port request
    sel_e dsel;
    always_comb begin
        if (in_region(dbus_addr, ROM_BASE, ROM_AW + 2))         dsel = dbus_we ? S_NONE : S_ROM;
        else if (in_region(dbus_addr, IMEM_BASE, IMEM_AW + 2))  dsel = S_IMEM;
        else if (in_region(dbus_addr, DMEM_BASE, DMEM_AW + 2))  dsel = S_DMEM;
        else if (in_region(dbus_addr, APB_BASE, 16))            dsel = (dbus_be == 4'hF) ? S_APB : S_NONE;
        else                                                    dsel = S_NONE;
    end

    assign rom_daddr   = dbus_addr[ROM_AW+1:2];
    assign rom_den     = dbus_req && dsel == S_ROM;

    assign imem_csb0   = !(dbus_req && dsel == S_IMEM);
    assign imem_web0   = !dbus_we;
    assign imem_wmask0 = dbus_be;
    assign imem_addr0  = dbus_addr[IMEM_AW+1:2];
    assign imem_din0   = dbus_wdata;

    assign dmem_csb0   = !(dbus_req && dsel == S_DMEM);
    assign dmem_web0   = !dbus_we;
    assign dmem_wmask0 = dbus_be;
    assign dmem_addr0  = dbus_addr[DMEM_AW+1:2];
    assign dmem_din0   = dbus_wdata;

    assign br_req   = dbus_req && dsel == S_APB;
    assign br_we    = dbus_we;
    assign br_addr  = dbus_addr[15:0];
    assign br_wdata = dbus_wdata;

    // ---------------------------------------------------------------- D-port response
    logic pend_q;
    sel_e psel_q;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pend_q <= 1'b0;
            psel_q <= S_NONE;
        end else begin
            if (dbus_req) begin
                pend_q <= 1'b1;
                psel_q <= dsel;
            end else if (dbus_rvalid) begin
                pend_q <= 1'b0;
            end
        end
    end

    always_comb begin
        dbus_rvalid = 1'b0;
        dbus_rdata  = 32'd0;
        dbus_err    = 1'b0;
        if (pend_q) begin
            case (psel_q)
                S_ROM:   begin dbus_rvalid = 1'b1; dbus_rdata = rom_ddata;  end
                S_IMEM:  begin dbus_rvalid = 1'b1; dbus_rdata = imem_dout0; end
                S_DMEM:  begin dbus_rvalid = 1'b1; dbus_rdata = dmem_dout0; end
                S_APB:   begin dbus_rvalid = br_rvalid; dbus_rdata = br_rdata; dbus_err = br_err; end
                default: begin dbus_rvalid = 1'b1; dbus_err = 1'b1; end
            endcase
        end
    end
endmodule
`default_nettype wire
