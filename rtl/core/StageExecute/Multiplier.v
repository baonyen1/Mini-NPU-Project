`timescale 1ns / 1ps

// RV32M multiplier, combinational (1 cycle in EX, simulation only; spec 5).
// op = funct3[1:0]: 00 MUL, 01 MULH, 10 MULHSU, 11 MULHU.
// Both operands are widened to 33 bits so one signed 33x33 product covers all
// four cases: the extension bit is the sign bit when the operand is signed for
// that op, and 0 when it is unsigned.
module Multiplier(
    a,
    b,
    op,
    result
);

input [31:0] a;
input [31:0] b;
input [1:0] op;

output [31:0] result;

wire a_signed = (op != 2'b11);   // MUL (low word is sign-agnostic), MULH, MULHSU
wire b_signed = (op == 2'b01);   // only MULH treats rs2 as signed

wire signed [32:0] a_ext = {a_signed & a[31], a};
wire signed [32:0] b_ext = {b_signed & b[31], b};
wire signed [65:0] product = a_ext * b_ext;

assign result = (op == 2'b00) ? product[31:0] : product[63:32];

endmodule
