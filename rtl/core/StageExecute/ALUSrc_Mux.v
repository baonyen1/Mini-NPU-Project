`timescale 1ns / 1ps

module ALUSrc_Mux(
    mux_1_sel_ID_EX,
    fw_mux_1_output,
    immediate_ID_EX,
    alu_input_b
);

input mux_1_sel_ID_EX;
input [31:0] fw_mux_1_output;
input [31:0] immediate_ID_EX;

output [31:0] alu_input_b;

assign alu_input_b = (mux_1_sel_ID_EX) ? immediate_ID_EX : fw_mux_1_output;

endmodule
