// ALU_4Bit.v (Verilog Version)
module ALU_4Bit (
    input wire [3:0] A, B,
    input wire [2:0] ALU_Op,
    output wire [3:0] Result
);
    reg [3:0] Result_r;

    always @(*) begin
        case (ALU_Op)
            3'b000: Result_r = A + B;     // ADD
            3'b001: Result_r = A - B;     // SUB
            3'b010: Result_r = A & B;     // AND
            3'b011: Result_r = A | B;     // OR
            default: Result_r = 4'b0000;
        endcase
    end
    assign Result = Result_r;
endmodule