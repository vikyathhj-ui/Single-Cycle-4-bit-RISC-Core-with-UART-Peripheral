// PC_5Bit.v

module PC_5Bit (
    // System Signals
    input wire CLK,
    input wire RST,
    // Control Signals
    input wire PC_Load,          // High when a JUMP instruction is active
    // Inputs for Jump/Branch
    input wire [4:0] PC_Next_Addr, // 5-bit target address for JUMP
    // Output
    output reg [4:0] PC_Address    // Current 5-bit instruction address
);

    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            // Reset PC to address 0 to start program execution
            PC_Address <= 5'b0;
        end else begin
            if (PC_Load) begin
                // Load a new address (JUMP or BRANCH)
                PC_Address <= PC_Next_Addr;
            end else begin
                // Sequential execution: PC = PC + 1
                PC_Address <= PC_Address + 5'b1;
            end
        end
    end

endmodule