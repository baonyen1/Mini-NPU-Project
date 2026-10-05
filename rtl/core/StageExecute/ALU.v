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
input [3:0] Control_in;
input [2:0] alu_branch_control;

output reg [31:0] ALU_result;
output alu_branch_response;

localparam ALU_AND = 4'b0000;
localparam ALU_OR  = 4'b0001;
localparam ALU_ADD = 4'b0010;
localparam ALU_XOR = 4'b0011;
localparam ALU_SLL = 4'b0100;
localparam ALU_SRL = 4'b0101;
localparam ALU_SUB = 4'b0110;

always @(*) begin
    case (Control_in)
        ALU_AND: ALU_result = A & B;
        ALU_OR:  ALU_result = A | B;
        ALU_ADD: ALU_result = A + B;
        ALU_XOR: ALU_result = A ^ B;
        ALU_SLL: ALU_result = A << B[4:0];
        ALU_SRL: ALU_result = A >> B[4:0];
        ALU_SUB: ALU_result = A - B;
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
