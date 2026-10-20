`timescale 1ns / 1ps

module ALU_Unit(
    A,
    B,
    Control_in,
    alu_branch_control,
    ALU_result,
    alu_branch_response
);

input [31:0] A, B;
input [5:0] Control_in;
input [2:0] alu_branch_control;

output reg [31:0] ALU_result;
output alu_branch_response;

localparam ALU_AND = 6'b000000;
localparam ALU_OR  = 6'b000001;
localparam ALU_ADD = 6'b000010;
localparam ALU_XOR = 6'b000011;
localparam ALU_SLL = 6'b000100;
localparam ALU_SRL = 6'b000101;
localparam ALU_SUB = 6'b000110;
localparam ALU_SLT  = 6'b000111; // set if A <  B, signed   (slt, slti)
localparam ALU_SLTU = 6'b001000; // set if A <  B, unsigned (sltu, sltiu)
localparam ALU_SRA  = 6'b001001; // arithmetic right shift  (sra, srai)

always @(*) begin
    case (Control_in)
        ALU_AND: ALU_result = A & B;
        ALU_OR:  ALU_result = A | B;
        ALU_ADD: ALU_result = A + B;
        ALU_XOR: ALU_result = A ^ B;
        ALU_SLL: ALU_result = A << B[4:0];
        ALU_SRL: ALU_result = A >> B[4:0];
        ALU_SUB: ALU_result = A - B;
        ALU_SLT:  ALU_result = {31'b0, ($signed(A) < $signed(B))};
        ALU_SLTU: ALU_result = {31'b0, (A < B)};
        ALU_SRA:  ALU_result = $signed(A) >>> B[4:0];
        default: ALU_result = 32'b0;
    endcase
end

Branch_Comparator BRANCH_COMPARE(
    .regfile_out_0(A),
    .regfile_out_1(B),
    .alu_branch_control(alu_branch_control),
    .alu_branch_response(alu_branch_response)
);

endmodule
