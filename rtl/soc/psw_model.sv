// psw_model: behavioural power-switch acknowledge for one domain (docs/SPEC.md §8.1). There are
// no switch cells in the layout (BRIEF A6, out of scope). Each ack follows its enable after DELAY
// cycles.
`default_nettype none
module psw_model #(
    parameter int DELAY = 4
) (
    input  logic clk,
    input  logic rst_n,
    input  logic trickle_en,
    input  logic main_en,
    output logic trickle_ack,
    output logic main_ack
);
    logic [DELAY-1:0] t, m;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t <= '0;
            m <= '0;
        end else begin
            t <= {t[DELAY-2:0], trickle_en};
            m <= {m[DELAY-2:0], main_en};
        end
    end
    assign trickle_ack = t[DELAY-1];
    assign main_ack    = m[DELAY-1];
endmodule
`default_nettype wire
