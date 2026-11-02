// uart_wake: AON UART-RX start-bit detector (docs/SPEC.md §8.4). 2-flop synchroniser on the RX pin
// and a falling-edge detector, enabled by SYSCTRL.UART_WAKE_EN. Output: a one-cycle pulse, which
// goes to PMU wake_irq[1] (the PMU synchronises and edge-detects it). The byte itself is lost
// (S-9): the UART receiver is in PERI.
`default_nettype none
module uart_wake (
    input  logic clk,
    input  logic rst_n,
    input  logic en,
    input  logic rxd,
    output logic wake
);
    logic [2:0] s;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) s <= 3'b111;
        else        s <= {s[1:0], rxd};
    end
    assign wake = en && s[2] && !s[1];
endmodule
`default_nettype wire
