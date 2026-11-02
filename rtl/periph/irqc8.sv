// irqc8: 8-source interrupt controller, APB3 completer (docs/SPEC.md §9, MEMORY_MAP "IRQC").
// PENDING 0x00 (RO) = current source levels, ENABLE 0x04. meip = |(PENDING & ENABLE) -> mip.MEIP.
// Sources are levels and are cleared at their source. CORE domain.
`default_nettype none
module irqc8 (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [11:0] paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,
    input  logic [7:0]  src,
    output logic        meip
);
    logic [7:0] en;
    logic       acc;
    assign acc = psel && penable;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n)                                   en <= '0;
        else if (acc && pwrite && paddr == 12'h004)   en <= pwdata[7:0];
    end
    assign meip   = |(src & en);
    assign prdata = (paddr == 12'h000) ? {24'd0, src} : (paddr == 12'h004) ? {24'd0, en} : 32'd0;
    assign pready = 1'b1;
    assign pslverr = acc && ((paddr != 12'h000 && paddr != 12'h004) || (pwrite && paddr == 12'h000));

    logic unused_pwdata;
    assign unused_pwdata = ^pwdata[31:8];
endmodule
`default_nettype wire
