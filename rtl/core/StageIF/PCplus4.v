`timescale 1ns / 1ps

module PCplus4(fromPC, toPC);

input [31:0] fromPC;
output [31:0] toPC;

assign toPC = fromPC + 32'd4;

endmodule
