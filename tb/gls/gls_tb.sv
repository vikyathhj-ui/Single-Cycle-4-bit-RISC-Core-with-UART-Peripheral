// gls_tb: testbench for the GDS-configuration power workload (sw/power_gds/power.S), used both for
// an RTL check (LP_GDS RTL + PDK SRAM model) and for the gate-level simulation of the final
// netlist (scripts/gls_power.py, D-032).
//   +imem=<hex>        preload u_imem (PDK SRAM model array `mem`, 256 words)
//   +period=<ns>       clock period (default 110, the implementation target)
//   +vcd=<file> +window=<n>   dump all signals only while gpio_o[n] = 1 (phase marker), then stop
// Prints the UART text (8 cycles per bit), the cycle at which each phase marker rose and fell,
// and "GLS_END" at the end.
`timescale 1ns/1ps
module gls_tb;
    reg clk = 1'b0, rst_n = 1'b0;
    real period = 110.0;
    wire uart_txd;
    wire [7:0] gpio_o, gpio_oe;
    lp_rv32_soc dut (.clk(clk), .rst_n(rst_n), .boot_sel(1'b1), .uart_rxd(1'b1), .uart_txd(uart_txd),
                     .gpio_i(8'h00), .gpio_o(gpio_o), .gpio_oe(gpio_oe));

    reg [8*256-1:0] f;
    integer win = -1, cyc = 0;
    initial begin
        if (!$value$plusargs("period=%f", period)) period = 110.0;
        if ($value$plusargs("imem=%s", f)) $readmemh(f, dut.u_imem.mem);
        if (!$value$plusargs("window=%d", win)) win = -1;
        #(10 * period) rst_n = 1'b1;
    end
    always #(period / 2.0) clk = ~clk;
    always @(posedge clk) cyc = cyc + 1;

    // phase markers and windowed dump
    reg [7:0] g_q = 8'h00;
    reg dumping = 1'b0;
    always @(posedge clk) begin
        if (gpio_o[0] != g_q[0]) $display("MARK active=%0d at cycle %0d", gpio_o[0], cyc);
        if (gpio_o[1] != g_q[1]) $display("MARK idle=%0d at cycle %0d", gpio_o[1], cyc);
        if (win >= 0 && !dumping && gpio_o[win] && !g_q[win] && $value$plusargs("vcd=%s", f)) begin
            $dumpfile(f);
            $dumpvars(0, dut);
            dumping = 1'b1;
            $display("DUMP start at cycle %0d", cyc);
        end
        if (dumping && !gpio_o[win]) begin
            $display("DUMP end at cycle %0d", cyc);
            $dumpflush;
            $display("GLS_END");
            $finish;
        end
        g_q <= gpio_o;
    end

    // UART decode (BAUD_DIV = 7 -> 8 cycles per bit)
    integer i;
    reg [7:0] ch;
    reg [8*64-1:0] text = 0;
    initial begin
        forever begin
            @(negedge uart_txd);
            repeat (4) @(posedge clk);
            for (i = 0; i < 8; i = i + 1) begin
                repeat (8) @(posedge clk);
                ch[i] = uart_txd;
            end
            repeat (8) @(posedge clk);
            $write("%c", ch);
            text = {text[8*63-1:0], ch};
            if (text[8*5-1:0] == "DONE\n") begin
                $display("UART DONE at cycle %0d", cyc);
                if (win < 0) begin $display("GLS_END"); $finish; end
            end
        end
    end

    initial begin
        #(400000.0 * period);
        $display("TIMEOUT at cycle %0d", cyc);
        $finish;
    end
endmodule
