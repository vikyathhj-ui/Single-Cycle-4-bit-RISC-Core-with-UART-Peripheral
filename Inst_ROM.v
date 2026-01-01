// Inst_ROM.v

module Inst_ROM (
    input wire [4:0] Address,    // 5-bit address from PC
    output wire [7:0] Instruction // 8-bit instruction output
);

    // Memory array: 32 locations, 8 bits wide
    reg [7:0] ROM [0:31]; 

    initial begin
        // Initialize memory with the test program
        ROM[0] = 8'h0D; // LOADI R1, 5
        ROM[1] = 8'h16; // LOADI R2, 6
        ROM[2] = 8'h5C; // ADD R1, R2
        ROM[3] = 8'h98; // OUT R1 (Start TX)
        ROM[4] = 8'hC3; // JUMP 3 (Loop)
        // Pad the rest of the memory with NOP (e.g., 0x00)
        ROM[5] = 8'h00; 
        ROM[6] = 8'h00; 
        // ... and so on up to ROM[31]
    end

    // Combinational Read Logic: The instruction is ready immediately based on the address
    assign Instruction = ROM[Address];

endmodule