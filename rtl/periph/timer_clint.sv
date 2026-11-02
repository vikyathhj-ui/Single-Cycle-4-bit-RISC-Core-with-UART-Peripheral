// timer_clint: CLINT-style machine timer and software interrupt, APB3 completer (docs/SPEC.md §9,
// docs/MEMORY_MAP.md "TIMER", [P §3.2.1]). AON domain (runs on the ungated clock).
// MSIP 0x00, MTIMECMP_LO 0x08, MTIMECMP_HI 0x0C, MTIME_LO 0x10, MTIME_HI 0x14, PRESCALE 0x18.
// mtime increments every PRESCALE+1 cycles. mtip = (mtime >= mtimecmp), unsigned 64-bit.
// A write to MTIME takes effect on the next cycle (that cycle's increment is replaced).
`default_nettype none
module timer_clint (
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
    output logic        msip,
    output logic        mtip
);
    logic [63:0] mtime, mtimecmp;
    logic [15:0] presc, pcnt;
    logic        wr, acc, tick;
    assign acc  = psel && penable;
    assign wr   = acc && pwrite;
    assign tick = (pcnt == presc);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mtime <= '0; mtimecmp <= '1; presc <= '0; pcnt <= '0; msip <= 1'b0;
        end else begin
            pcnt <= tick ? 16'd0 : pcnt + 16'd1;
            if (wr && paddr == 12'h010)      mtime[31:0]  <= pwdata;
            else if (wr && paddr == 12'h014) mtime[63:32] <= pwdata;
            else if (tick)                   mtime        <= mtime + 64'd1;
            if (wr) begin
                case (paddr)
                    12'h000: msip            <= pwdata[0];
                    12'h008: mtimecmp[31:0]  <= pwdata;
                    12'h00C: mtimecmp[63:32] <= pwdata;
                    12'h018: begin presc <= pwdata[15:0]; pcnt <= 16'd0; end
                    default: ;
                endcase
            end
        end
    end
    assign mtip = (mtime >= mtimecmp);

    logic valid;
    always_comb begin
        valid = 1'b1; prdata = 32'd0;
        case (paddr)
            12'h000: prdata = {31'd0, msip};
            12'h008: prdata = mtimecmp[31:0];
            12'h00C: prdata = mtimecmp[63:32];
            12'h010: prdata = mtime[31:0];
            12'h014: prdata = mtime[63:32];
            12'h018: prdata = {16'd0, presc};
            default: valid = 1'b0;
        endcase
    end
    assign pready  = 1'b1;
    assign pslverr = acc && !valid;
endmodule
`default_nettype wire
