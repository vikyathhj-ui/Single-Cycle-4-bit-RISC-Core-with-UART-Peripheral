// apb_bridge: simple-bus to APB3 master bridge (docs/SPEC.md §9, ARM IHI 0024E).
//
// Request side: a one-cycle request (req, we, addr[15:0], wdata) from the crossbar; at most one
// outstanding. Response: rvalid for one cycle with rdata / err, registered (one cycle after the
// APB access phase completes).
// APB side: 16 slots of 4 KB, PSEL[addr[15:12]]; PADDR = addr[11:0]. IHI 0024E §4.1: IDLE ->
// SETUP (PSEL=1, PENABLE=0) -> ACCESS (PENABLE=1, held until PREADY). Slots not set in
// SLOT_PRESENT answer with an error and no APB transfer (SPEC §4: access fault).
`default_nettype none
module apb_bridge #(
    parameter logic [15:0] SLOT_PRESENT = 16'h003F     // UART, GPIO, TIMER, IRQC, SYSCTRL, PMU
) (
    input  logic        clk,
    input  logic        rst_n,
    // request side
    input  logic        req,
    input  logic        we,
    input  logic [15:0] addr,
    input  logic [31:0] wdata,
    output logic        rvalid,
    output logic [31:0] rdata,
    output logic        err,
    // APB3 master
    output logic [15:0] psel,
    output logic        penable,
    output logic        pwrite,
    output logic [11:0] paddr,
    output logic [31:0] pwdata,
    input  logic [31:0] prdata  [16],
    input  logic [15:0] pready,
    input  logic [15:0] pslverr
);
    typedef enum logic [1:0] {IDLE, SETUP, ACCESS, RESP} state_e;
    state_e      state;
    logic [3:0]  slot;
    logic [31:0] rdata_q;
    logic        err_q;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state   <= IDLE;
            slot    <= 4'd0;
            pwrite  <= 1'b0;
            paddr   <= 12'd0;
            pwdata  <= 32'd0;
            rdata_q <= 32'd0;
            err_q   <= 1'b0;
        end else begin
            if ((state == IDLE || state == RESP) && req) begin
                // A new request may arrive in the same cycle as the previous response.
                slot   <= addr[15:12];
                pwrite <= we;
                paddr  <= addr[11:0];
                pwdata <= wdata;
                if (SLOT_PRESENT[addr[15:12]]) begin
                    err_q <= 1'b0;
                    state <= SETUP;
                end else begin
                    rdata_q <= 32'd0;
                    err_q   <= 1'b1;
                    state   <= RESP;
                end
            end else begin
                case (state)
                    SETUP:  state <= ACCESS;
                    ACCESS: if (pready[slot]) begin
                        rdata_q <= pwrite ? 32'd0 : prdata[slot];
                        err_q   <= pslverr[slot];
                        state   <= RESP;
                    end
                    RESP: begin
                        err_q <= 1'b0;
                        state <= IDLE;
                    end
                    default: state <= IDLE;
                endcase
            end
        end
    end

    assign psel    = (state == SETUP || state == ACCESS) ? (16'd1 << slot) : 16'd0;
    assign penable = (state == ACCESS);
    assign rvalid  = (state == RESP);
    assign rdata   = rdata_q;
    assign err     = err_q;
endmodule
`default_nettype wire
