`timescale 1ns / 1ps

// RV32M iterative restoring divider, radix 2, one quotient bit per cycle
// (about 32 cycles; spec 5, plan Task 5).
//
// Handshake: pulse `start` for one cycle; a and b are sampled in that cycle
// (the caller must not rely on them afterwards, because forwarding sources
// disappear while the instruction waits in EX). `busy` is high while the loop
// runs. `done` is high while `result` is valid and stays high until the next
// `start`. A new `start` is accepted while idle or done.
//
// Spec corner cases are handled without running the loop:
//   x / 0         : quotient = all ones, remainder = dividend
//   -2^31 / -1    : quotient = -2^31,    remainder = 0
module Divider(
    clk,
    reset,
    start,
    is_signed,
    is_rem,
    a,
    b,
    busy,
    done,
    result
);

input clk, reset;
input start;
input is_signed;     // 1: div/rem, 0: divu/remu
input is_rem;        // 1: result is the remainder, 0: the quotient
input [31:0] a;      // dividend
input [31:0] b;      // divisor

output busy;
output done;
output [31:0] result;

localparam S_IDLE = 2'd0;
localparam S_RUN  = 2'd1;
localparam S_DONE = 2'd2;

reg [1:0] state;
reg [5:0] count;          // iterations left
reg [31:0] dividend_q;    // dividend bits not consumed yet (shifts out MSB first)
reg [31:0] quotient_q;
reg [31:0] remainder_q;
reg [31:0] divisor_q;     // |divisor|
reg neg_quotient_q;
reg neg_remainder_q;
reg is_rem_q;
reg special_q;            // divide by zero or signed overflow: result is fixed
reg [31:0] special_result_q;

wire a_neg = is_signed & a[31];
wire b_neg = is_signed & b[31];
wire [31:0] a_abs = a_neg ? (~a + 32'd1) : a;
wire [31:0] b_abs = b_neg ? (~b + 32'd1) : b;
wire div_by_zero = (b == 32'd0);
wire overflow    = is_signed & (a == 32'h80000000) & (b == 32'hFFFFFFFF);

// One restoring step: shift the next dividend bit into the partial remainder
// (33 bits: 2*remainder + bit < 2^33) and subtract the divisor when it fits.
wire [32:0] shifted = {remainder_q, dividend_q[31]};
wire fits = (shifted >= {1'b0, divisor_q});
wire [32:0] difference = shifted - {1'b0, divisor_q};

wire [31:0] quotient_final  = neg_quotient_q  ? (~quotient_q  + 32'd1) : quotient_q;
wire [31:0] remainder_final = neg_remainder_q ? (~remainder_q + 32'd1) : remainder_q;

assign busy = (state == S_RUN);
assign done = (state == S_DONE);
assign result = special_q ? special_result_q :
                is_rem_q  ? remainder_final  : quotient_final;

always @(posedge clk) begin
    if (reset) begin
        state            <= S_IDLE;
        count            <= 6'd0;
        dividend_q       <= 32'b0;
        quotient_q       <= 32'b0;
        remainder_q      <= 32'b0;
        divisor_q        <= 32'b0;
        neg_quotient_q   <= 1'b0;
        neg_remainder_q  <= 1'b0;
        is_rem_q         <= 1'b0;
        special_q        <= 1'b0;
        special_result_q <= 32'b0;
    end
    else if (start && (state != S_RUN)) begin
        is_rem_q <= is_rem;
        if (div_by_zero || overflow) begin
            special_q        <= 1'b1;
            special_result_q <= div_by_zero ? (is_rem ? a : 32'hFFFFFFFF)
                                            : (is_rem ? 32'd0 : 32'h80000000);
            state            <= S_DONE;
        end
        else begin
            special_q       <= 1'b0;
            dividend_q      <= a_abs;
            divisor_q       <= b_abs;
            quotient_q      <= 32'b0;
            remainder_q     <= 32'b0;
            neg_quotient_q  <= a_neg ^ b_neg;
            neg_remainder_q <= a_neg;
            count           <= 6'd32;
            state           <= S_RUN;
        end
    end
    else if (state == S_RUN) begin
        dividend_q  <= {dividend_q[30:0], 1'b0};
        quotient_q  <= {quotient_q[30:0], fits};
        remainder_q <= fits ? difference[31:0] : shifted[31:0];
        count       <= count - 6'd1;
        if (count == 6'd1) state <= S_DONE;
    end
end

endmodule
