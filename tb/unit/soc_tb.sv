// soc_tb: wrapper for SoC-level cocotb tests (tb/unit/test_soc.py). Instantiates lp_rv32_soc in the
// SIM memory configuration and preloads IMEM / DMEM from +imem=<hex> / +dmem=<hex> (one 32-bit word
// per line) before reset is released.
`default_nettype none
module soc_tb (
    input  logic       clk,
    input  logic       rst_n,
    input  logic       boot_sel,
    input  logic       uart_rxd,
    output logic       uart_txd,
    input  logic [7:0] gpio_i,
    output logic [7:0] gpio_o,
    output logic [7:0] gpio_oe
);
    lp_rv32_soc u_soc (.clk(clk), .rst_n(rst_n), .boot_sel(boot_sel), .uart_rxd(uart_rxd),
                       .uart_txd(uart_txd), .gpio_i(gpio_i), .gpio_o(gpio_o), .gpio_oe(gpio_oe));
    string f;
    initial begin
        if ($value$plusargs("imem=%s", f)) $readmemh(f, u_soc.u_imem.mem);
        if ($value$plusargs("dmem=%s", f)) $readmemh(f, u_soc.u_dmem.mem);
    end
endmodule
`default_nettype wire
