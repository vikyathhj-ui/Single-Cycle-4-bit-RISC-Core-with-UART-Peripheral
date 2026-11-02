// sysctrl: boot / wake reason, scratch and boot strap, APB3 completer (docs/SPEC.md §7, §9,
// MEMORY_MAP "SYSCTRL"). AON domain; reset only by the cold reset.
// ID 0x00 (RO), RESET_CAUSE 0x04 (W1C), WAKE_SRC 0x08 (W1C), SCRATCH 0x0C, BOOT 0x10 (RO),
// UART_WAKE_EN 0x14.
// RESET_CAUSE.COLD resets to 1. RESET_CAUSE.WARM is set when the CPU domain is powered up
// (core_pwr_up = PMU main-switch acknowledge of PD0 rises) for any time after the first one
// following a cold reset, i.e. after a DEEP_SLEEP power-up (SPEC §8.3). The main switch comes on
// before the PMU releases the core reset, so WARM is valid when the core starts. (The core reset
// net itself is not sampled: it is an asynchronous reset, D-018.)
// WAKE_SRC[i] is set on a rising edge of wake[i].
`default_nettype none
module sysctrl (
    input  logic        clk,
    input  logic        rst_n,          // cold reset (synchronised pin)
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [11:0] paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,
    input  logic        boot_sel,       // strap pin, sampled on the first clock after cold reset
    input  logic        core_pwr_up,    // PMU psw_main_ack[CPU]
    input  logic [2:0]  wake,           // PMU wake_irq[2:0] sources
    output logic        uart_wake_en
);
    logic       cold, warm, booted, pwr_q, boot_q, sampled;
    logic [2:0] wsrc, wake_q;
    logic [31:0] scratch;
    logic       acc, wr;
    assign acc = psel && penable;
    assign wr  = acc && pwrite;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cold <= 1'b1; warm <= 1'b0; booted <= 1'b0; pwr_q <= 1'b0; boot_q <= 1'b0; sampled <= 1'b0;
            wsrc <= '0; wake_q <= '0; scratch <= '0; uart_wake_en <= 1'b0;
        end else begin
            pwr_q <= core_pwr_up;
            if (!sampled) begin boot_q <= boot_sel; sampled <= 1'b1; end   // first clock after cold reset
            wake_q     <= wake;
            if (core_pwr_up && !pwr_q) booted <= 1'b1;
            if (core_pwr_up && !pwr_q && booted)          warm <= 1'b1;
            else if (wr && paddr == 12'h004 && pwdata[1])     warm <= 1'b0;
            if (wr && paddr == 12'h004 && pwdata[0])          cold <= 1'b0;
            wsrc <= (wsrc & ~((wr && paddr == 12'h008) ? pwdata[2:0] : 3'b000)) | (wake & ~wake_q);
            if (wr && paddr == 12'h00C) scratch <= pwdata;
            if (wr && paddr == 12'h014) uart_wake_en <= pwdata[0];
        end
    end

    logic valid;
    always_comb begin
        valid = 1'b1; prdata = 32'd0;
        case (paddr)
            12'h000: prdata = 32'h4C50_3332;          // "LP32"
            12'h004: prdata = {30'd0, warm, cold};
            12'h008: prdata = {29'd0, wsrc};
            12'h00C: prdata = scratch;
            12'h010: prdata = {31'd0, boot_q};
            12'h014: prdata = {31'd0, uart_wake_en};
            default: valid = 1'b0;
        endcase
    end
    assign pready  = 1'b1;
    assign pslverr = acc && (!valid || (pwrite && (paddr == 12'h000 || paddr == 12'h010)));
endmodule
`default_nettype wire
