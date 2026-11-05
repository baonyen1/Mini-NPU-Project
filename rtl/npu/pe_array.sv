`timescale 1ns / 1ps

// 4 x 4 array of dot4 PEs with their accumulators (spec 6.2, 6.3, 7.2; plan Task 11, build stage 4).
// Gated clock domain: clk is mac_engine's clk_mac (spec 7.3). The array never gates a clock itself;
// it updates only in cycles with step = 1 (flop enable), so it holds its value while clk_mac is gated.
//
// One step (one cycle, no pipelining in Senior Project 2, spec 7.2), for i, j in 0..3:
//   dot_ij = sum over t < 4 of sext8(w_quad.word_i.lane_t) * sext8(x_quad.word_j.lane_t)
//   acc_ij <= (load ? 0 : acc_ij) + dot_ij                                   (mod 2^32, spec D5)
// w_quad is WBUF[s] (word i = four weights of output row i), x_quad is IBUF[s] (word j = four inputs
// of image j). load is COMPUTE's clr on its first step, so the first step loads the dot product.
// |dot_ij| <= 4 * 128 * 128 = 65536, which fits 18 signed bits; it is sign-extended to 32 bits.
// acc[4*i + j] is READ_RESULT index idx = 4*i + j (spec 6.2), read combinationally by mac_engine.
// Reset (D18): asynchronous assert, all 16 accumulators to 0.
module pe_array
  import npu_pkg::*;
(
    input  logic                                   clk,
    input  logic                                   rst_n,
    input  logic                                   step,
    input  logic                                   load,
    input  logic [PORT_B_W-1:0]                    w_quad,
    input  logic [PORT_B_W-1:0]                    x_quad,
    output logic [PE_ROWS*PE_COLS-1:0][31:0]       acc
);
    localparam int unsigned DOT_W = 18;              // 4 products of at most 2^14 in magnitude, signed

    // sum over the 4 lanes of the product of two signed int8, exact in DOT_W bits
    function automatic logic signed [DOT_W-1:0] dot4(input logic [31:0] a, input logic [31:0] b);
        logic signed [DOT_W-1:0] sum;
        logic signed [15:0]      prod;
        sum = '0;
        for (int t = 0; t < K_DOT; t++) begin
            prod = 16'($signed(a[8 * t +: 8])) * 16'($signed(b[8 * t +: 8]));  // |prod| <= 16384
            sum  = sum + DOT_W'(prod);
        end
        return sum;
    endfunction

    for (genvar i = 0; i < PE_ROWS; i++) begin : g_row
        for (genvar j = 0; j < PE_COLS; j++) begin : g_col
            logic signed [DOT_W-1:0] dot;
            logic        [31:0]      acc_q;

            assign dot = dot4(w_quad[32 * i +: 32], x_quad[32 * j +: 32]);

            always_ff @(posedge clk or negedge rst_n) begin
                if (!rst_n)    acc_q <= '0;
                else if (step) acc_q <= (load ? 32'd0 : acc_q) + 32'(dot);   // sign-extends dot
            end

            assign acc[PE_COLS * i + j] = acc_q;
        end
    end
endmodule
