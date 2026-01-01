// RegFile_4x4.v (Verilog Version)
module RegFile_4x4 (
    input wire CLK, RST,
    input wire WE,                  // Write Enable
    input wire [1:0] W_Addr,        // Write Address
    input wire [3:0] W_Data,        // Data to Write
    input wire [1:0] R1_Addr, R2_Addr, // Read Addresses
    output wire [3:0] R1_Data, R2_Data  // Data Read
);
    // 4 registers, 4 bits wide
    reg [3:0] Registers [0:3];

    // Asynchronous Read (Combinational)
    assign R1_Data = Registers[R1_Addr];
    assign R2_Data = Registers[R2_Addr];

    // Synchronous Write Logic
    always @(posedge CLK or posedge RST) begin
        if (RST) begin
            Registers[0] <= 4'b0;
            Registers[1] <= 4'b0;
            Registers[2] <= 4'b0;
            Registers[3] <= 4'b0;
        end else if (WE) begin
            Registers[W_Addr] <= W_Data;
        end
    end
endmodule