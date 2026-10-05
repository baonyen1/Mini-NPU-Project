`timescale 1ns / 1ps

module StageExecute_Top(
    clk,
    reset,
    cpu_en,

    // input from ID/EX
    Instruction_address_ID_EX,
    regfile_out_0_ID_EX,
    regfile_out_1_ID_EX,
    immediate_ID_EX,
    regfile_write_address_ID_EX,
    jump_target_mux_sel_ID_EX,
    alu_src_a_sel_ID_EX,
    mux_1_sel_ID_EX,
    alu_operation_ID_EX,
    alu_branch_ID_EX,
    alu_branch_control_ID_EX,
    jump_flag_ID_EX,
    data_format_ID_EX,
    datamem_read_enable_ID_EX,
    datamem_write_enable_ID_EX,
    regfile_write_enable_ID_EX,
    writeback_mux_sel_ID_EX,

    // forwarding sources from MEM and MEM/WB
    alu_out_MEM_WB,
    datamem_out_MEM_WB,
    Instruction_address_MEM_WB,
    fw_mux_0_sel,
    fw_mux_1_sel,

    // branch/jump feedback to IF
    jump_branch_signal,
    flush_signal,
    jump_branch_destination,

    // output to EX/MEM
    Instruction_address_EX_MEM,
    alu_out_EX_MEM,
    datamem_wr_data_EX_MEM,
    data_format_EX_MEM,
    datamem_read_enable_EX_MEM,
    datamem_write_enable_EX_MEM,
    writeback_mux_sel_EX_MEM,
    regfile_write_enable_EX_MEM,
    regfile_write_address_EX_MEM
);

input clk, reset, cpu_en;

input [31:0] Instruction_address_ID_EX;
input [31:0] regfile_out_0_ID_EX;
input [31:0] regfile_out_1_ID_EX;
input [31:0] immediate_ID_EX;
input [4:0] regfile_write_address_ID_EX;
input jump_target_mux_sel_ID_EX;
input [1:0] alu_src_a_sel_ID_EX;
input mux_1_sel_ID_EX;
input [3:0] alu_operation_ID_EX;
input alu_branch_ID_EX;
input [2:0] alu_branch_control_ID_EX;
input jump_flag_ID_EX;
input [2:0] data_format_ID_EX;
input datamem_read_enable_ID_EX;
input datamem_write_enable_ID_EX;
input regfile_write_enable_ID_EX;
input [1:0] writeback_mux_sel_ID_EX;

input [31:0] alu_out_MEM_WB;
input [31:0] datamem_out_MEM_WB;
input [31:0] Instruction_address_MEM_WB;
input [2:0] fw_mux_0_sel;
input [2:0] fw_mux_1_sel;

output jump_branch_signal;
output flush_signal;
output [31:0] jump_branch_destination;

output [31:0] Instruction_address_EX_MEM;
output [31:0] alu_out_EX_MEM;
output [31:0] datamem_wr_data_EX_MEM;
output [2:0] data_format_EX_MEM;
output datamem_read_enable_EX_MEM;
output datamem_write_enable_EX_MEM;
output [1:0] writeback_mux_sel_EX_MEM;
output regfile_write_enable_EX_MEM;
output [4:0] regfile_write_address_EX_MEM;

wire [31:0] fw_mux_0_output;
wire [31:0] fw_mux_1_output;
wire [31:0] alu_input_a;
wire [31:0] mux_1_output;
wire [31:0] alu_output;
wire alu_branch_response;
wire [31:0] return_address_EX_MEM;
wire [31:0] return_address_MEM_WB;

assign return_address_EX_MEM = Instruction_address_EX_MEM + 32'd4;
assign return_address_MEM_WB = Instruction_address_MEM_WB + 32'd4;

assign alu_input_a = (alu_src_a_sel_ID_EX == 2'b01) ? 32'b0 :
                     (alu_src_a_sel_ID_EX == 2'b10) ? Instruction_address_ID_EX :
                     fw_mux_0_output;

Forwarding_Mux FW_MUX_0(
    .select(fw_mux_0_sel),
    .regfile_data(regfile_out_0_ID_EX),
    .alu_out_EX_MEM(alu_out_EX_MEM),
    .alu_out_MEM_WB(alu_out_MEM_WB),
    .datamem_out_MEM_WB(datamem_out_MEM_WB),
    .return_address_EX_MEM(return_address_EX_MEM),
    .return_address_MEM_WB(return_address_MEM_WB),
    .forwarded_data(fw_mux_0_output)
);

Forwarding_Mux FW_MUX_1(
    .select(fw_mux_1_sel),
    .regfile_data(regfile_out_1_ID_EX),
    .alu_out_EX_MEM(alu_out_EX_MEM),
    .alu_out_MEM_WB(alu_out_MEM_WB),
    .datamem_out_MEM_WB(datamem_out_MEM_WB),
    .return_address_EX_MEM(return_address_EX_MEM),
    .return_address_MEM_WB(return_address_MEM_WB),
    .forwarded_data(fw_mux_1_output)
);

ALUSrc_Mux MUX_1(
    .mux_1_sel_ID_EX(mux_1_sel_ID_EX),
    .fw_mux_1_output(fw_mux_1_output),
    .immediate_ID_EX(immediate_ID_EX),
    .alu_input_b(mux_1_output)
);

ALU_Unit ALU(
    .A(alu_input_a),
    .B(mux_1_output),
    .Control_in(alu_operation_ID_EX),
    .alu_branch_control(alu_branch_control_ID_EX),
    .ALU_result(alu_output),
    .alu_branch_response(alu_branch_response)
);

BRU BRANCH_RESOLUTION_UNIT(
    .cpu_en(cpu_en),
    .Instruction_address_ID_EX(Instruction_address_ID_EX),
    .regfile_out_0_ID_EX(fw_mux_0_output),
    .immediate_ID_EX(immediate_ID_EX),
    .jump_target_mux_sel_ID_EX(jump_target_mux_sel_ID_EX),
    .alu_branch_ID_EX(alu_branch_ID_EX),
    .alu_branch_response(alu_branch_response),
    .jump_flag_ID_EX(jump_flag_ID_EX),
    .jump_branch_signal(jump_branch_signal),
    .flush_signal(flush_signal),
    .jump_branch_destination(jump_branch_destination)
);

EX_MEM_Reg EX_MEM(
    .clk(clk),
    .reset(reset),
    .cpu_en(cpu_en),

    .Instruction_address_ID_EX(Instruction_address_ID_EX),
    .alu_output(alu_output),
    .datamem_wr_data(fw_mux_1_output),
    .data_format_ID_EX(data_format_ID_EX),
    .datamem_read_enable_ID_EX(datamem_read_enable_ID_EX),
    .datamem_write_enable_ID_EX(datamem_write_enable_ID_EX),
    .writeback_mux_sel_ID_EX(writeback_mux_sel_ID_EX),
    .regfile_write_enable_ID_EX(regfile_write_enable_ID_EX),
    .regfile_write_address_ID_EX(regfile_write_address_ID_EX),

    .Instruction_address_EX_MEM(Instruction_address_EX_MEM),
    .alu_out_EX_MEM(alu_out_EX_MEM),
    .datamem_wr_data_EX_MEM(datamem_wr_data_EX_MEM),
    .data_format_EX_MEM(data_format_EX_MEM),
    .datamem_read_enable_EX_MEM(datamem_read_enable_EX_MEM),
    .datamem_write_enable_EX_MEM(datamem_write_enable_EX_MEM),
    .writeback_mux_sel_EX_MEM(writeback_mux_sel_EX_MEM),
    .regfile_write_enable_EX_MEM(regfile_write_enable_EX_MEM),
    .regfile_write_address_EX_MEM(regfile_write_address_EX_MEM)
);

endmodule
