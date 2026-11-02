// qch_stub_dev: an always-accepting Q-Channel device (P2 SPEC §2.2 device rules) for PMU domains
// that have no quiescence logic of their own: PD1 (DSP, unused) and PD2 (PERI) (docs/SPEC.md §8.1,
// D-007 S-7). Reset: Q_STOPPED. QACCEPTn falls one cycle after QREQn falls and rises one cycle
// after QREQn rises; it never denies. Firmware makes PERI quiet before DEEP_SLEEP (it waits for
// UART STATUS.TX_EMPTY), SPEC §8.3.
`default_nettype none
module qch_stub_dev (
    input  logic clk,
    input  logic rst_n,
    input  logic qreq_n,
    output logic qaccept_n,
    output logic qdeny,
    output logic qactive
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) qaccept_n <= 1'b0;
        else        qaccept_n <= qreq_n;
    end
    assign qdeny   = 1'b0;
    assign qactive = 1'b0;
endmodule
`default_nettype wire
