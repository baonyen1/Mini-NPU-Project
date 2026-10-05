`timescale 1ns / 1ps

module Instruction_Decoder(
    instruction,
    Opcode,
    Rd,
    fun3,
    fun7,
    Rs1,
    Rs2
);

input [31:0] instruction;

output [6:0] Opcode;
output [4:0] Rd;
output [2:0] fun3;
output [6:0] fun7;
output [4:0] Rs1;
output [4:0] Rs2;

assign Opcode = instruction[6:0];
assign Rd = instruction[11:7];
assign fun3 = instruction[14:12];
assign fun7 = instruction[31:25];
assign Rs1 = instruction[19:15];
assign Rs2 = instruction[24:20];

endmodule

