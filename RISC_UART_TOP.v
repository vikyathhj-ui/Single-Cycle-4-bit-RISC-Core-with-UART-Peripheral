// RISC_UART_TOP.v

module RISC_UART_TOP (
    // Physical I/O Pins
    input wire CLK,              // System Clock (e.g., 50 MHz from FPGA board)
    input wire RST,              // System Reset (e.g., from a pushbutton)
    output wire TX_PIN           // Serial Output to PC/FTDI chip
);

    // ------------------------------------------------------------------
    // INTERNAL WIRES & REGISTERS
    // ------------------------------------------------------------------

    // Control Unit Output Wires
    wire Reg_WE;
    wire [2:0] ALU_Op;
    wire TX_Start;
    wire PC_Load;

    // Data Path Wires
    wire [4:0] pc_out;            // Address from PC to ROM
    wire [7:0] instruction;       // Instruction from ROM to Control Unit
    
    // Register File Connections
    wire [3:0] r1_data, r2_data;  // Read Data from Register File
    wire [1:0] w_addr;            // Write Address (Destination Register)
    wire [3:0] reg_w_data;        // Data to be written back to RegFile (ALU Result)
    wire [1:0] r1_addr, r2_addr;  // Read Addresses (Source Registers)
    
    // ALU Connections
    wire [3:0] alu_result;
    
    // UART Connections
    wire [3:0] tx_data_in;        // Data from RegFile to UART

    // ------------------------------------------------------------------
    // INSTRUCTION DECODING (Extract Addresses and Immediate Values)
    // Based on 8-bit instruction: [OPCODE(7:5)] [OPERANDS/ADDRESS(4:0)]
    // ------------------------------------------------------------------

    // Extract Write Address (Rd) for LOADI, ADD from bits 4:3
    assign w_addr = instruction[4:3]; 
    
    // Extract Read Address 1 (R1_Addr/Rd for ADD) from bits 4:3
    assign r1_addr = instruction[4:3]; 
    
    // Extract Read Address 2 (Rs) for ADD from bits 2:1
    assign r2_addr = instruction[2:1]; 
    
    // Extract Immediate Value for LOADI from bits 2:0
    wire [3:0] load_immediate = {1'b0, instruction[2:0]}; // Zero-extend to 4 bits
    
    // Extract Jump Address for JUMP from bits 4:0
    wire [4:0] jump_addr = instruction[4:0]; 
    
    // ------------------------------------------------------------------
    // INSTRUCTION/DATA SELECTION (Multiplexing)
    // ------------------------------------------------------------------

    // Determine the data source for the Register File write port (reg_w_data)
    // Only two instructions write back: LOADI and ADD
    // If LOADI is active, write the immediate value; otherwise, write the ALU result.
    assign reg_w_data = (instruction[7:5] == 3'b000) ? load_immediate : alu_result;
    
    // Determine the data source for the UART (tx_data_in)
    // The source register for OUT is R1_Addr (bits 4:3)
    assign tx_data_in = r1_data; 
    
    // ------------------------------------------------------------------
    // MODULE INSTANTIATIONS
    // ------------------------------------------------------------------

    // 1. Program Counter
    PC_5Bit PC_Unit (
        .CLK(CLK),
        .RST(RST),
        .PC_Load(PC_Load),
        .PC_Next_Addr(jump_addr), // Jump address from instruction
        .PC_Address(pc_out)
    );

    // 2. Instruction ROM
    Inst_ROM ROM_Unit (
        .Address(pc_out),
        .Instruction(instruction)
    );
    
    // 3. Control Unit (Generates all control signals)
    ControlUnit Control_Unit (
        .Instruction(instruction),
        .Reg_WE(Reg_WE),
        .ALU_Op(ALU_Op),
        .TX_Start(TX_Start),
        .PC_Load(PC_Load)
    );

    // 4. Register File
    RegFile_4x4 RF_Unit (
        .CLK(CLK),
        .RST(RST),
        .WE(Reg_WE),
        .W_Addr(w_addr),
        .W_Data(reg_w_data), // Either Immediate or ALU result
        .R1_Addr(r1_addr),
        .R2_Addr(r2_addr),
        .R1_Data(r1_data),
        .R2_Data(r2_data)
    );
    
    // 5. ALU
    ALU_4Bit ALU_Unit (
        .A(r1_data), // Read data 1 (Rd)
        .B(r2_data), // Read data 2 (Rs)
        .ALU_Op(ALU_Op),
        .Result(alu_result)
    );
    
    // 6. UART Transmitter
    UART_TX TX_Unit (
        .CLK(CLK),
        .RST(RST),
        .TX_Data_In(tx_data_in), // Data to send (from R1)
        .TX_Start(TX_Start),     // Trigger from Control Unit
        .TX_Pin(TX_PIN)
    );

endmodule