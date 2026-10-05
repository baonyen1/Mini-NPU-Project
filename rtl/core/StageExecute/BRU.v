`timescale 1ns / 1ps

module BRU(
    Instruction_address_ID_EX,
    regfile_out_0_ID_EX,
    immediate_ID_EX,
    jump_target_mux_sel_ID_EX,
    alu_branch_ID_EX,
    alu_branch_response,
    jump_flag_ID_EX,
    jump_branch_signal,
    flush_signal,
    jump_branch_destination
);

input [31:0] Instruction_address_ID_EX;
input [31:0] regfile_out_0_ID_EX;
input [31:0] immediate_ID_EX;
input jump_target_mux_sel_ID_EX;
input alu_branch_ID_EX;
input alu_branch_response;
input jump_flag_ID_EX;

output jump_branch_signal;
output flush_signal;
output [31:0] jump_branch_destination;

Jump_Target_Unit TARGET_GENERATOR(
    .Instruction_address_ID_EX(Instruction_address_ID_EX),
    .regfile_out_0_ID_EX(regfile_out_0_ID_EX),
    .immediate_ID_EX(immediate_ID_EX),
    .jump_target_mux_sel_ID_EX(jump_target_mux_sel_ID_EX),
    .jump_branch_destination(jump_branch_destination)
);

Flushing_Unit CONTROL_REDIRECT(
    .alu_branch(alu_branch_ID_EX),
    .alu_branch_response(alu_branch_response),
    .jump_flag(jump_flag_ID_EX),
    .jump_branch_signal(jump_branch_signal),
    .flush_signal(flush_signal)
);

endmodule
