`timescale 1ns / 1ps

module PCMux(pc_sel, PC_plus4, Branch_target, PC_out);

input pc_sel;
input [31:0] PC_plus4;
input [31:0] Branch_target;

output [31:0] PC_out;

assign PC_out = (pc_sel) ? Branch_target : PC_plus4;

endmodule
