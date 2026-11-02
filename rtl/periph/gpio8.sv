// gpio8: 8-bit GPIO, APB3 completer (docs/SPEC.md §9, docs/MEMORY_MAP.md "GPIO"). PERI domain.
// IN 0x00 (RO, after a 2-flop synchroniser), OUT 0x04, DIR 0x08 (1 = output), RISE_EN 0x0C,
// FALL_EN 0x10, IRQ_STATUS 0x14 (W1C). Edges are detected on the synchronised value, so an output
// pin also sees its own edges (it reads back through the pad). irq = |IRQ_STATUS.
`default_nettype none
module gpio8 (
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
    input  logic [7:0]  gpio_i,
    output logic [7:0]  gpio_o,
    output logic [7:0]  gpio_oe,
    output logic        irq
);
    logic [7:0] s1, s2, prev, rise_en, fall_en, pend;
    logic       wr, acc;
    assign acc = psel && penable;
    assign wr  = acc && pwrite;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            s1 <= '0; s2 <= '0; prev <= '0;
            gpio_o <= '0; gpio_oe <= '0; rise_en <= '0; fall_en <= '0; pend <= '0;
        end else begin
            s1   <= gpio_i;
            s2   <= s1;
            prev <= s2;
            if (wr) begin
                case (paddr)
                    12'h004: gpio_o  <= pwdata[7:0];
                    12'h008: gpio_oe <= pwdata[7:0];
                    12'h00C: rise_en <= pwdata[7:0];
                    12'h010: fall_en <= pwdata[7:0];
                    default: ;
                endcase
            end
            // set has priority over a simultaneous W1C
            pend <= (pend & ~((wr && paddr == 12'h014) ? pwdata[7:0] : 8'h00))
                  | (rise_en & s2 & ~prev) | (fall_en & ~s2 & prev);
        end
    end
    assign irq = |pend;

    logic valid;
    always_comb begin
        valid = 1'b1; prdata = 32'd0;
        case (paddr)
            12'h000: prdata = {24'd0, s2};
            12'h004: prdata = {24'd0, gpio_o};
            12'h008: prdata = {24'd0, gpio_oe};
            12'h00C: prdata = {24'd0, rise_en};
            12'h010: prdata = {24'd0, fall_en};
            12'h014: prdata = {24'd0, pend};
            default: valid = 1'b0;
        endcase
    end
    assign pready  = 1'b1;
    assign pslverr = acc && (!valid || (pwrite && paddr == 12'h000));

    logic unused_pwdata;
    assign unused_pwdata = ^pwdata[31:8];
endmodule
`default_nettype wire
