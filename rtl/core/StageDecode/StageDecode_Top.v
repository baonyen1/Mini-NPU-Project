`timescale 1ns / 1ps

module StageDecode_Top(
    clk,
    reset,
    stall,
    flush,

    // input from IF/ID
    Instruction_IF_ID,
    Instruction_address_IF_ID,
    valid_IF_ID,

    // writeback input from MEM/WB stage
    regfile_write_enable_MEM_WB,
    regfile_write_address_MEM_WB,
    regfile_write_data,

    // output to ID/EX
    Instruction_address_ID_EX,
    regfile_out_0_ID_EX,
    regfile_out_1_ID_EX,
    immediate_ID_EX,
    regfile_read_address_0_ID_EX,
    regfile_read_address_1_ID_EX,
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
    csr_op_ID_EX,
    valid_ID_EX
);

input clk, reset, stall, flush;

input [31:0] Instruction_IF_ID;
input [31:0] Instruction_address_IF_ID;
input valid_IF_ID;

input regfile_write_enable_MEM_WB;
input [4:0] regfile_write_address_MEM_WB;
input [31:0] regfile_write_data;

output [31:0] Instruction_address_ID_EX;
output [31:0] regfile_out_0_ID_EX;
output [31:0] regfile_out_1_ID_EX;
output [31:0] immediate_ID_EX;

output [4:0] regfile_read_address_0_ID_EX;
output [4:0] regfile_read_address_1_ID_EX;
output [4:0] regfile_write_address_ID_EX;

output jump_target_mux_sel_ID_EX;
output [1:0] alu_src_a_sel_ID_EX;
output mux_1_sel_ID_EX;
output [5:0] alu_operation_ID_EX;
output alu_branch_ID_EX;
output [2:0] alu_branch_control_ID_EX;
output jump_flag_ID_EX;
output [2:0] data_format_ID_EX;
output datamem_read_enable_ID_EX;
output datamem_write_enable_ID_EX;
output regfile_write_enable_ID_EX;
output [1:0] writeback_mux_sel_ID_EX;
output [2:0] csr_op_ID_EX;
output valid_ID_EX;

wire [4:0] regfile_write_address;
wire [4:0] regfile_read_address_0;
wire [4:0] regfile_read_address_1;

wire alu_branch;
wire [2:0] alu_branch_control;
wire datamem_read_enable;
wire datamem_write_enable;
wire jump_target_mux_sel;
wire [1:0] alu_src_a_sel;
wire mux_1_sel;
wire regfile_write_enable;
wire jump_flag;
wire [2:0] data_format;
wire [5:0] alu_operation;
wire [1:0] writeback_mux_sel;
wire [2:0] csr_op;

wire [31:0] regfile_out_0;
wire [31:0] regfile_out_1;
wire [31:0] immediate;

Controller CONTROLLER(
    .Instruction_IF_ID(Instruction_IF_ID),
    .regfile_read_address_0(regfile_read_address_0),
    .regfile_read_address_1(regfile_read_address_1),
    .immediate(immediate),
    .jump_target_mux_sel(jump_target_mux_sel),
    .alu_src_a_sel(alu_src_a_sel),
    .mux_1_sel(mux_1_sel),
    .alu_operation(alu_operation),
    .alu_branch(alu_branch),
    .alu_branch_control(alu_branch_control),
    .jump_flag(jump_flag),
    .data_format(data_format),
    .datamem_read_enable(datamem_read_enable),
    .datamem_write_enable(datamem_write_enable),
    .writeback_mux_sel(writeback_mux_sel),
    .regfile_write_enable(regfile_write_enable),
    .regfile_write_address(regfile_write_address),
    .csr_op(csr_op)
);

Register_File REGFILE(
    .clk(clk),
    .reset(reset),
    .Rs1(regfile_read_address_0),
    .Rs2(regfile_read_address_1),
    .Rd(regfile_write_address_MEM_WB),
    .write_data(regfile_write_data),
    .read_data1(regfile_out_0),
    .read_data2(regfile_out_1),
    .reg_write(regfile_write_enable_MEM_WB)
);

ID_EX_Reg ID_EX(
    .clk(clk),
    .reset(reset),
    .stall(stall),
    .flush(flush),

    .Instruction_address_IF_ID(Instruction_address_IF_ID),
    .regfile_out_0(regfile_out_0),
    .regfile_out_1(regfile_out_1),
    .immediate(immediate),
    .regfile_read_address_0(regfile_read_address_0),
    .regfile_read_address_1(regfile_read_address_1),
    .regfile_write_address(regfile_write_address),

    .jump_target_mux_sel(jump_target_mux_sel),
    .alu_src_a_sel(alu_src_a_sel),
    .mux_1_sel(mux_1_sel),
    .alu_operation(alu_operation),
    .alu_branch(alu_branch),
    .alu_branch_control(alu_branch_control),
    .jump_flag(jump_flag),
    .data_format(data_format),
    .datamem_read_enable(datamem_read_enable),
    .datamem_write_enable(datamem_write_enable),
    .regfile_write_enable(regfile_write_enable),
    .writeback_mux_sel(writeback_mux_sel),
    .csr_op(csr_op),
    .valid(valid_IF_ID),

    .Instruction_address_ID_EX(Instruction_address_ID_EX),
    .regfile_out_0_ID_EX(regfile_out_0_ID_EX),
    .regfile_out_1_ID_EX(regfile_out_1_ID_EX),
    .immediate_ID_EX(immediate_ID_EX),
    .regfile_read_address_0_ID_EX(regfile_read_address_0_ID_EX),
    .regfile_read_address_1_ID_EX(regfile_read_address_1_ID_EX),
    .regfile_write_address_ID_EX(regfile_write_address_ID_EX),

    .jump_target_mux_sel_ID_EX(jump_target_mux_sel_ID_EX),
    .alu_src_a_sel_ID_EX(alu_src_a_sel_ID_EX),
    .mux_1_sel_ID_EX(mux_1_sel_ID_EX),
    .alu_operation_ID_EX(alu_operation_ID_EX),
    .alu_branch_ID_EX(alu_branch_ID_EX),
    .alu_branch_control_ID_EX(alu_branch_control_ID_EX),
    .jump_flag_ID_EX(jump_flag_ID_EX),
    .data_format_ID_EX(data_format_ID_EX),
    .datamem_read_enable_ID_EX(datamem_read_enable_ID_EX),
    .datamem_write_enable_ID_EX(datamem_write_enable_ID_EX),
    .regfile_write_enable_ID_EX(regfile_write_enable_ID_EX),
    .writeback_mux_sel_ID_EX(writeback_mux_sel_ID_EX),
    .csr_op_ID_EX(csr_op_ID_EX),
    .valid_ID_EX(valid_ID_EX)
);

endmodule
