`timescale 1ns / 1ps

module Flushing_Unit(
    alu_branch,
    alu_branch_response,
    jump_flag,
    jump_branch_signal,
    flush_signal
);

input alu_branch;
input alu_branch_response;
input jump_flag;

output jump_branch_signal;
output flush_signal;

wire branch_taken;

assign branch_taken = alu_branch & alu_branch_response;
assign jump_branch_signal = jump_flag | branch_taken;
assign flush_signal = jump_branch_signal;

endmodule
