// ControlUnit.v

module ControlUnit (
    // Input: Instruction from Inst_ROM
    input wire [7:0] Instruction,
    
    // Outputs: Control Signals
    output reg Reg_WE,          // Register File Write Enable
    output reg [2:0] ALU_Op,    // ALU Operation Selector
    output reg TX_Start,        // UART Transmit Start Pulse
    output reg PC_Load          // Program Counter Load Enable (for Jumps)
);

    // Decode the 3-bit OpCode
    wire [2:0] OpCode = Instruction[7:5];
    
    // ------------------------------------------------------------------
    // OpCode Definitions (from our ISA)
    // '000': LOADI (Load Immediate) -> Writes to RegFile
    // '001': ADD     -> Uses ALU, Writes to RegFile
    // '010': OUT     -> Triggers UART TX
    // '011': JUMP    -> Loads PC with new address
    // ------------------------------------------------------------------
    
    // Combinational logic to generate control signals based on OpCode
    always @(*) begin
        // Default (Safety) settings: No operations
        Reg_WE   = 1'b0;
        ALU_Op   = 3'b000; // Default to ADD or NOP depending on ALU design
        TX_Start = 1'b0;
        PC_Load  = 1'b0;
        
        case (OpCode)
            // 000: LOADI Rd, Imm
            3'b000: begin
                Reg_WE = 1'b1; // We write to a register
                // ALU is unused in this instruction
            end
            
            // 001: ADD Rd, Rs
            3'b001: begin
                Reg_WE = 1'b1; // We write the ALU result to a register
                ALU_Op = 3'b000; // Select ADD operation (from ALU_4Bit design)
            end
            
            // 010: OUT Rs
            3'b010: begin
                TX_Start = 1'b1; // Tell the UART to start transmitting
                // ALU and RegFile are read-only (not written)
            end
            
            // 011: JUMP Address
            3'b011: begin
                PC_Load = 1'b1; // Load the PC with the jump address
            end
            
            // Default case (NOP or Halt)
            default: begin
                // All defaults are already set to 0 (No Operation)
            end
        endcase
    end

endmodule