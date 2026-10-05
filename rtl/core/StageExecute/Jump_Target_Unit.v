`timescale 1ns / 1ps

module Jump_Target_Unit(
    Instruction_address_ID_EX,
    regfile_out_0_ID_EX,
    immediate_ID_EX,
    jump_target_mux_sel_ID_EX,
    jump_branch_destination
);

input [31:0] Instruction_address_ID_EX;
input [31:0] regfile_out_0_ID_EX;
input [31:0] immediate_ID_EX;
input jump_target_mux_sel_ID_EX;

output [31:0] jump_branch_destination;

wire [31:0] pc_relative_target;
wire [31:0] register_relative_target;

assign pc_relative_target = Instruction_address_ID_EX + immediate_ID_EX;
assign register_relative_target = (regfile_out_0_ID_EX + immediate_ID_EX) & 32'hfffffffe;

assign jump_branch_destination = jump_target_mux_sel_ID_EX ?
                                 register_relative_target :
                                 pc_relative_target;

endmodule
