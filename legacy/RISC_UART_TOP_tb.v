// RISC_UART_TOP_tb.v

module RISC_UART_TOP_tb;

    // --- Simulation Parameters ---
    localparam CLK_PERIOD = 20;  // 50 MHz clock period (20ns)

    // --- Testbench Signals ---
    reg  CLK = 1'b0;
    reg  RST = 1'b1; // Start in reset
    wire TX_PIN;

    // 1. Clock Generation
    always #((CLK_PERIOD)/2) CLK = ~CLK;

    // 2. Instantiate the Unit Under Test (UUT)
    // The instance name MUST match the top-level module name: RISC_UART_TOP
    RISC_UART_TOP UUT (
        .CLK(CLK),
        .RST(RST),
        .TX_PIN(TX_PIN)
    );

    // 3. Stimulus (Reset Release and Program Run)
    initial begin
        // Apply reset for 100 ns
        RST = 1'b1;
        #100;

        // Release reset to start program execution
        RST = 1'b0;
        
        // Let the program run for a sufficient time (e.g., 5 instructions + UART time)
        // Since one bit takes ~5208 clock cycles, 5 bits take 26040 cycles
        // 5 instructions take much longer. Let's run for 1ms (1,000,000 ns)
        #1000000; 

        // Stop simulation
        $stop;
    end

endmodule