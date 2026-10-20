`timescale 1ns / 1ps

// Zbb (RV32 subset of spec 5), combinational, in EX.
// op encoding (the same numbers are used by Control.v and listed in docs/core_isa.md):
//   0 ANDN   1 ORN    2 XNOR   3 CLZ    4 CTZ     5 CPOP
//   6 MAX    7 MAXU   8 MIN    9 MINU  10 SEXT.B 11 SEXT.H
//  12 ZEXT.H 13 ROL   14 ROR   15 ORC.B 16 REV8
// RORI uses ROR with b = the immediate; rotate amounts use b[4:0]. Unary
// operations ignore b.
module BitManip(
    a,
    b,
    op,
    result
);

input [31:0] a;
input [31:0] b;
input [4:0] op;

output reg [31:0] result;

localparam BB_ANDN   = 5'd0;
localparam BB_ORN    = 5'd1;
localparam BB_XNOR   = 5'd2;
localparam BB_CLZ    = 5'd3;
localparam BB_CTZ    = 5'd4;
localparam BB_CPOP   = 5'd5;
localparam BB_MAX    = 5'd6;
localparam BB_MAXU   = 5'd7;
localparam BB_MIN    = 5'd8;
localparam BB_MINU   = 5'd9;
localparam BB_SEXT_B = 5'd10;
localparam BB_SEXT_H = 5'd11;
localparam BB_ZEXT_H = 5'd12;
localparam BB_ROL    = 5'd13;
localparam BB_ROR    = 5'd14;
localparam BB_ORC_B  = 5'd15;
localparam BB_REV8   = 5'd16;

wire [4:0] shamt = b[4:0];
// {a, a} shifted: the half that holds the rotated value is used, the other half is dropped
/* verilator lint_off UNUSEDSIGNAL */
wire [63:0] rol64 = {a, a} << shamt;
wire [63:0] ror64 = {a, a} >> shamt;
/* verilator lint_on UNUSEDSIGNAL */
wire a_lt_b_s = ($signed(a) < $signed(b));
wire a_lt_b_u = (a < b);

integer i;
reg [5:0] count;

always @(*) begin
    count  = 6'd0;
    result = 32'b0;
    case (op)
        BB_ANDN:   result = a & ~b;
        BB_ORN:    result = a | ~b;
        BB_XNOR:   result = ~(a ^ b);
        BB_CLZ: begin
            count = 6'd32;
            for (i = 0; i < 32; i = i + 1)
                if (a[i]) count = 6'd31 - i[5:0];  // the highest set bit is assigned last
            result = {26'b0, count};
        end
        BB_CTZ: begin
            count = 6'd32;
            for (i = 31; i >= 0; i = i - 1)
                if (a[i]) count = i[5:0];          // the lowest set bit is assigned last
            result = {26'b0, count};
        end
        BB_CPOP: begin
            for (i = 0; i < 32; i = i + 1)
                count = count + {5'b0, a[i]};
            result = {26'b0, count};
        end
        BB_MAX:    result = a_lt_b_s ? b : a;
        BB_MAXU:   result = a_lt_b_u ? b : a;
        BB_MIN:    result = a_lt_b_s ? a : b;
        BB_MINU:   result = a_lt_b_u ? a : b;
        BB_SEXT_B: result = {{24{a[7]}}, a[7:0]};
        BB_SEXT_H: result = {{16{a[15]}}, a[15:0]};
        BB_ZEXT_H: result = {16'b0, a[15:0]};
        BB_ROL:    result = rol64[63:32];
        BB_ROR:    result = ror64[31:0];
        BB_ORC_B:  result = {{8{|a[31:24]}}, {8{|a[23:16]}}, {8{|a[15:8]}}, {8{|a[7:0]}}};
        BB_REV8:   result = {a[7:0], a[15:8], a[23:16], a[31:24]};
        default:   result = 32'b0;
    endcase
end

endmodule
