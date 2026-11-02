// uart_lite: 16550-lite UART, APB3 completer (docs/SPEC.md §9, docs/MEMORY_MAP.md "UART").
// 8N1 only, programmable bit period (BAUD_DIV+1 clock cycles), 16-byte TX and RX FIFOs,
// RX / TX / framing-error / overflow interrupts. Lives in the PERI domain.
//
// Registers (offsets): DATA 0x00, STATUS 0x04 (RO), CTRL 0x08, BAUD_DIV 0x0C, IRQ_EN 0x10,
// IRQ_STATUS 0x14 (W1C for the sticky error bits). PREADY is always 1. PSLVERR: write to STATUS,
// or an address not listed.
// RX: the start bit is confirmed at its middle ((DIV+1)/2 cycles after the falling edge); data and
// stop bits are sampled every DIV+1 cycles after that. Stop bit 0 -> FRAME_ERR, byte dropped.
`default_nettype none
module uart_lite (
    input  logic        clk,
    input  logic        rst_n,
    // APB3
    input  logic        psel,
    input  logic        penable,
    input  logic        pwrite,
    input  logic [11:0] paddr,
    input  logic [31:0] pwdata,
    output logic [31:0] prdata,
    output logic        pready,
    output logic        pslverr,
    // serial
    input  logic        rxd,
    output logic        txd,
    output logic        irq
);
    localparam int DEPTH = 16;

    // ---------------------------------------------------------------- registers
    logic        tx_en, rx_en;
    logic [3:0]  rx_thresh;
    logic [15:0] div;
    logic [4:0]  irq_en;
    logic        st_frame, st_rxovf, st_txovf;

    // ---------------------------------------------------------------- FIFOs
    logic [7:0] txf [DEPTH];
    logic [7:0] rxf [DEPTH];
    logic [3:0] tx_rd, tx_wr, rx_rd, rx_wr;
    logic [4:0] tx_cnt, rx_cnt;

    logic acc, wr, rd;
    assign acc = psel && penable;
    assign wr  = acc && pwrite;
    assign rd  = acc && !pwrite;

    logic tx_push, tx_pop, rx_push, rx_pop, tx_flush, rx_flush;
    logic [7:0] rx_byte;
    assign tx_push  = wr && paddr == 12'h000 && tx_cnt != DEPTH[4:0];
    assign rx_pop   = rd && paddr == 12'h000 && rx_cnt != 5'd0;
    assign tx_flush = wr && paddr == 12'h008 && pwdata[2];
    assign rx_flush = wr && paddr == 12'h008 && pwdata[3];

    // ---------------------------------------------------------------- transmitter
    typedef enum logic [1:0] {T_IDLE, T_START, T_DATA, T_STOP} tst_e;
    tst_e        tst;
    logic [15:0] tcnt;
    logic [2:0]  tbit;
    logic [7:0]  tsh;
    assign tx_pop = (tst == T_IDLE) && tx_en && tx_cnt != 5'd0;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tst <= T_IDLE; tcnt <= '0; tbit <= '0; tsh <= '0; txd <= 1'b1;
        end else begin
            case (tst)
                T_IDLE: begin
                    txd <= 1'b1;
                    if (tx_pop) begin
                        tsh  <= txf[tx_rd];
                        tst  <= T_START;
                        tcnt <= div;
                        txd  <= 1'b0;
                    end
                end
                T_START, T_DATA, T_STOP: begin
                    if (tcnt != 16'd0) begin
                        tcnt <= tcnt - 16'd1;
                    end else begin
                        tcnt <= div;
                        case (tst)
                            T_START: begin tst <= T_DATA; tbit <= 3'd0; txd <= tsh[0]; end
                            T_DATA: begin
                                if (tbit == 3'd7) begin
                                    tst <= T_STOP; txd <= 1'b1;
                                end else begin
                                    tbit <= tbit + 3'd1;
                                    txd  <= tsh[tbit + 3'd1];
                                end
                            end
                            default: begin tst <= T_IDLE; txd <= 1'b1; end   // stop bit done
                        endcase
                    end
                end
                default: tst <= T_IDLE;
            endcase
        end
    end

    // ---------------------------------------------------------------- receiver
    logic [1:0] rx_sync;
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) rx_sync <= 2'b11;
        else        rx_sync <= {rx_sync[0], rxd};
    end
    logic rxs;
    assign rxs = rx_sync[1];

    typedef enum logic [1:0] {R_IDLE, R_START, R_DATA, R_STOP} rst_e;
    rst_e        rst_q;
    logic [15:0] rcnt;
    logic [2:0]  rbit;
    logic [7:0]  rsh;
    logic        rx_done, rx_ferr;

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            rst_q <= R_IDLE; rcnt <= '0; rbit <= '0; rsh <= '0; rx_done <= 1'b0; rx_ferr <= 1'b0;
        end else begin
            rx_done <= 1'b0;
            rx_ferr <= 1'b0;
            case (rst_q)
                R_IDLE: if (rx_en && !rxs) begin
                    rst_q <= R_START;
                    rcnt  <= {1'b0, div[15:1]};          // half a bit period: (DIV+1)/2 - 1 cycles
                end
                R_START: begin
                    if (rcnt != 16'd0) rcnt <= rcnt - 16'd1;
                    else if (rxs)      rst_q <= R_IDLE;  // glitch: not a start bit
                    else begin rst_q <= R_DATA; rcnt <= div; rbit <= 3'd0; end
                end
                R_DATA: begin
                    if (rcnt != 16'd0) rcnt <= rcnt - 16'd1;
                    else begin
                        rsh  <= {rxs, rsh[7:1]};
                        rcnt <= div;
                        if (rbit == 3'd7) rst_q <= R_STOP;
                        else              rbit  <= rbit + 3'd1;
                    end
                end
                R_STOP: begin
                    if (rcnt != 16'd0) rcnt <= rcnt - 16'd1;
                    else begin
                        rst_q <= R_IDLE;
                        if (rxs) rx_done <= 1'b1;
                        else     rx_ferr <= 1'b1;
                    end
                end
                default: rst_q <= R_IDLE;
            endcase
        end
    end
    assign rx_byte = rsh;
    assign rx_push = rx_done && rx_cnt != DEPTH[4:0];

    // ---------------------------------------------------------------- FIFO pointers
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_rd <= '0; tx_wr <= '0; tx_cnt <= '0;
            rx_rd <= '0; rx_wr <= '0; rx_cnt <= '0;
        end else begin
            if (tx_flush) begin
                tx_rd <= '0; tx_wr <= '0; tx_cnt <= '0;
            end else begin
                if (tx_push) begin txf[tx_wr] <= pwdata[7:0]; tx_wr <= tx_wr + 4'd1; end
                if (tx_pop)  tx_rd <= tx_rd + 4'd1;
                tx_cnt <= tx_cnt + {4'd0, tx_push} - {4'd0, tx_pop};
            end
            if (rx_flush) begin
                rx_rd <= '0; rx_wr <= '0; rx_cnt <= '0;
            end else begin
                if (rx_push) begin rxf[rx_wr] <= rx_byte; rx_wr <= rx_wr + 4'd1; end
                if (rx_pop)  rx_rd <= rx_rd + 4'd1;
                rx_cnt <= rx_cnt + {4'd0, rx_push} - {4'd0, rx_pop};
            end
        end
    end

    // ---------------------------------------------------------------- control registers
    logic st_rx, st_tx;
    assign st_rx = {1'b0, rx_cnt} > {2'b00, rx_thresh};
    assign st_tx = (tx_cnt == 5'd0);

    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tx_en <= 1'b0; rx_en <= 1'b0; rx_thresh <= 4'd0; div <= 16'h01B1; irq_en <= 5'd0;
            st_frame <= 1'b0; st_rxovf <= 1'b0; st_txovf <= 1'b0;
        end else begin
            if (wr) begin
                case (paddr)
                    12'h008: begin tx_en <= pwdata[0]; rx_en <= pwdata[1]; rx_thresh <= pwdata[11:8]; end
                    12'h00C: div <= pwdata[15:0];
                    12'h010: irq_en <= pwdata[4:0];
                    default: ;
                endcase
            end
            // sticky status: set has priority over a simultaneous W1C
            if (rx_ferr)                                           st_frame <= 1'b1;
            else if (wr && paddr == 12'h014 && pwdata[2])          st_frame <= 1'b0;
            if (rx_done && rx_cnt == DEPTH[4:0])                   st_rxovf <= 1'b1;
            else if (wr && paddr == 12'h014 && pwdata[3])          st_rxovf <= 1'b0;
            if (wr && paddr == 12'h000 && tx_cnt == DEPTH[4:0])    st_txovf <= 1'b1;
            else if (wr && paddr == 12'h014 && pwdata[4])          st_txovf <= 1'b0;
        end
    end

    logic [4:0] irq_status;
    assign irq_status = {st_txovf, st_rxovf, st_frame, st_tx, st_rx};
    assign irq = |(irq_status & irq_en);

    // ---------------------------------------------------------------- APB read / response
    logic valid_addr;
    always_comb begin
        valid_addr = 1'b1;
        prdata     = 32'd0;
        case (paddr)
            12'h000: prdata = {24'd0, rx_cnt != 5'd0 ? rxf[rx_rd] : 8'd0};
            12'h004: prdata = {11'd0, rx_cnt, 3'd0, tx_cnt, 4'd0,
                               rx_cnt == DEPTH[4:0], rx_cnt == 5'd0, tx_cnt == DEPTH[4:0],
                               (tx_cnt == 5'd0) && (tst == T_IDLE)};
            12'h008: prdata = {20'd0, rx_thresh, 6'd0, rx_en, tx_en};
            12'h00C: prdata = {16'd0, div};
            12'h010: prdata = {27'd0, irq_en};
            12'h014: prdata = {27'd0, irq_status};
            default: valid_addr = 1'b0;
        endcase
    end
    assign pready  = 1'b1;
    assign pslverr = acc && (!valid_addr || (pwrite && paddr == 12'h004));

    logic unused_pwdata;
    assign unused_pwdata = ^pwdata[31:16];
endmodule
`default_nettype wire
