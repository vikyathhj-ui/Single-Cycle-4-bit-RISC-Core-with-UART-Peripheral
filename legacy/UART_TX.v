// UART_TX.v

module UART_TX (
    // System Signals
    input wire CLK,              // 50 MHz FPGA Clock
    input wire RST,              // System Reset
    // CPU Interface
    input wire [3:0] TX_Data_In, // 4-bit data from RISC core
    input wire TX_Start,         // Signal from CPU Control Unit to begin transmission
    // Serial Output
    output reg TX_Pin            // Serial Transmit Line (Idle = High)
);

    // --- State Machine Definition ---
    localparam [2:0] 
        IDLE  = 3'b000,
        START = 3'b001,
        DATA  = 3'b010,
        STOP  = 3'b011;
        
    reg [2:0] tx_state = IDLE;
    
    // --- Baud Rate Counter ---
    // Counter size: 13 bits (2^12 = 4096, 2^13 = 8192) needed for 5208 cycles
    localparam BAUD_DIVIDER = 13'd5207; // Counts from 0 to 5207 (5208 total cycles)
    reg [12:0] clk_count = 0;
    reg clk_enable = 0; // Clock enable pulse for one bit period
    
    // --- Data Management Registers ---
    reg [3:0] data_buffer = 4'b0; // Holds data during transmission
    reg [2:0] bit_count = 0;      // Counts through the 4 data bits (and start/stop)

    // 1. Baud Rate Clock Divider (Generates clk_enable)
    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            clk_count <= 0;
            clk_enable <= 0;
        end else begin
            if (clk_count == BAUD_DIVIDER) begin
                clk_count <= 0;
                clk_enable <= 1; // Pulse high for one clock cycle
            end else begin
                clk_count <= clk_count + 1;
                clk_enable <= 0;
            end
        end
    end
    
    // 2. Transmitter Finite State Machine (FSM)
    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            tx_state <= IDLE;
            TX_Pin <= 1'b1; // Default to high (Idle state)
            bit_count <= 0;
        end else if (clk_enable) begin // Only update state on the slow clock pulse
            case (tx_state)
                IDLE: begin
                    TX_Pin <= 1'b1; // Keep line high
                    if (TX_Start) begin // Check if CPU wants to send
                        data_buffer <= TX_Data_In; // Load data
                        bit_count <= 0;
                        tx_state <= START;
                    end
                end
                
                START: begin
                    TX_Pin <= 1'b0; // Start bit is logic low
                    tx_state <= DATA;
                end
                
                DATA: begin
                    // Send the current data bit (LSB first)
                    TX_Pin <= data_buffer[bit_count];
                    
                    if (bit_count == 3) begin // Sent 4 data bits (0, 1, 2, 3)
                        tx_state <= STOP;
                    end else begin
                        bit_count <= bit_count + 1;
                    end
                end
                
                STOP: begin
                    TX_Pin <= 1'b1; // Stop bit is logic high
                    tx_state <= IDLE; // Return to idle
                end
                
                default: tx_state <= IDLE;
            endcase
        end
    end

endmodule