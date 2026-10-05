`timescale 1ns / 1ps

module RISC_V_Top(
    clk,
    reset,

    Instruction_IF_ID,
    Instruction_address_IF_ID,
    Instruction_address_ID_EX,
    Instruction_address_EX_MEM,
    Instruction_address_MEM_WB,
    alu_out_EX_MEM,
    regfile_write_data_WB,
    jump_branch_signal
);

input clk, reset;

output [31:0] Instruction_IF_ID;
output [31:0] Instruction_address_IF_ID;
output [31:0] Instruction_address_ID_EX;
output [31:0] Instruction_address_EX_MEM;
output [31:0] Instruction_address_MEM_WB;
output [31:0] alu_out_EX_MEM;
output [31:0] regfile_write_data_WB;
output jump_branch_signal;

wire [31:0] jump_branch_destination;

wire [31:0] regfile_out_0_ID_EX;
wire [31:0] regfile_out_1_ID_EX;
wire [31:0] immediate_ID_EX;
wire [4:0] regfile_read_address_0_ID_EX;
wire [4:0] regfile_read_address_1_ID_EX;
wire [4:0] regfile_write_address_ID_EX;
wire jump_target_mux_sel_ID_EX;
wire [1:0] alu_src_a_sel_ID_EX;
wire mux_1_sel_ID_EX;
wire [3:0] alu_operation_ID_EX;
wire alu_branch_ID_EX;
wire [2:0] alu_branch_control_ID_EX;
wire jump_flag_ID_EX;
wire [2:0] data_format_ID_EX;
wire datamem_read_enable_ID_EX;
wire datamem_write_enable_ID_EX;
wire regfile_write_enable_ID_EX;
wire [1:0] writeback_mux_sel_ID_EX;

wire [31:0] datamem_wr_data_EX_MEM;
wire [2:0] data_format_EX_MEM;
wire datamem_read_enable_EX_MEM;
wire datamem_write_enable_EX_MEM;
wire [1:0] writeback_mux_sel_EX_MEM;
wire regfile_write_enable_EX_MEM;
wire [4:0] regfile_write_address_EX_MEM;

wire [31:0] alu_out_MEM_WB;
wire [31:0] datamem_out_MEM_WB;
wire [1:0] writeback_mux_sel_MEM_WB;
wire regfile_write_enable_MEM_WB;
wire [4:0] regfile_write_address_MEM_WB;

wire regfile_write_enable_WB;
wire [4:0] regfile_write_address_WB;

wire load_use_stall;
wire pipeline_flush_signal;
wire hazard_pc_write;
wire hazard_if_id_stall;
wire hazard_if_id_flush;
wire hazard_id_ex_stall;
wire hazard_id_ex_flush;
wire [2:0] fw_mux_0_sel;
wire [2:0] fw_mux_1_sel;

Hazard_Unit HAZARD_UNIT(
    .pipeline_flush_signal(pipeline_flush_signal),
    .opcode_IF_ID(Instruction_IF_ID[6:0]),
    .regfile_read_address_0_IF_ID(Instruction_IF_ID[19:15]),
    .regfile_read_address_1_IF_ID(Instruction_IF_ID[24:20]),
    .datamem_read_enable_ID_EX(datamem_read_enable_ID_EX),
    .regfile_write_address_ID_EX(regfile_write_address_ID_EX),
    .regfile_read_address_0_ID_EX(regfile_read_address_0_ID_EX),
    .regfile_read_address_1_ID_EX(regfile_read_address_1_ID_EX),
    .regfile_write_address_EX_MEM(regfile_write_address_EX_MEM),
    .regfile_write_enable_EX_MEM(regfile_write_enable_EX_MEM),
    .writeback_mux_sel_EX_MEM(writeback_mux_sel_EX_MEM),
    .regfile_write_address_MEM_WB(regfile_write_address_MEM_WB),
    .regfile_write_enable_MEM_WB(regfile_write_enable_MEM_WB),
    .writeback_mux_sel_MEM_WB(writeback_mux_sel_MEM_WB),
    .pc_write(hazard_pc_write),
    .if_id_stall(hazard_if_id_stall),
    .if_id_flush(hazard_if_id_flush),
    .id_ex_stall(hazard_id_ex_stall),
    .id_ex_flush(hazard_id_ex_flush),
    .fw_mux_0_sel(fw_mux_0_sel),
    .fw_mux_1_sel(fw_mux_1_sel),
    .load_use_stall(load_use_stall)
);

StageIF_TOP IF_STAGE(
    .clk(clk),
    .reset(reset),
    .pc_write(hazard_pc_write),
    .stall(hazard_if_id_stall),
    .flush(hazard_if_id_flush),
    .jump_branch_signal(jump_branch_signal),
    .jump_branch_destination(jump_branch_destination),

    .Instruction_IF_ID(Instruction_IF_ID),
    .Instruction_address_IF_ID(Instruction_address_IF_ID)
);

StageDecode_Top DECODE_STAGE(
    .clk(clk),
    .reset(reset),
    .stall(hazard_id_ex_stall),
    .flush(hazard_id_ex_flush),

    .Instruction_IF_ID(Instruction_IF_ID),
    .Instruction_address_IF_ID(Instruction_address_IF_ID),

    .regfile_write_enable_MEM_WB(regfile_write_enable_WB),
    .regfile_write_address_MEM_WB(regfile_write_address_WB),
    .regfile_write_data(regfile_write_data_WB),

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
    .writeback_mux_sel_ID_EX(writeback_mux_sel_ID_EX)
);

StageExecute_Top EXECUTE_STAGE(
    .clk(clk),
    .reset(reset),

    .Instruction_address_ID_EX(Instruction_address_ID_EX),
    .regfile_out_0_ID_EX(regfile_out_0_ID_EX),
    .regfile_out_1_ID_EX(regfile_out_1_ID_EX),
    .immediate_ID_EX(immediate_ID_EX),
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

    .alu_out_MEM_WB(alu_out_MEM_WB),
    .datamem_out_MEM_WB(datamem_out_MEM_WB),
    .Instruction_address_MEM_WB(Instruction_address_MEM_WB),
    .fw_mux_0_sel(fw_mux_0_sel),
    .fw_mux_1_sel(fw_mux_1_sel),

    .jump_branch_signal(jump_branch_signal),
    .flush_signal(pipeline_flush_signal),
    .jump_branch_destination(jump_branch_destination),

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

StageMemory_Top MEMORY_STAGE(
    .clk(clk),
    .reset(reset),

    .Instruction_address_EX_MEM(Instruction_address_EX_MEM),
    .alu_out_EX_MEM(alu_out_EX_MEM),
    .datamem_wr_data_EX_MEM(datamem_wr_data_EX_MEM),
    .data_format_EX_MEM(data_format_EX_MEM),
    .datamem_read_enable_EX_MEM(datamem_read_enable_EX_MEM),
    .datamem_write_enable_EX_MEM(datamem_write_enable_EX_MEM),
    .writeback_mux_sel_EX_MEM(writeback_mux_sel_EX_MEM),
    .regfile_write_enable_EX_MEM(regfile_write_enable_EX_MEM),
    .regfile_write_address_EX_MEM(regfile_write_address_EX_MEM),

    .Instruction_address_MEM_WB(Instruction_address_MEM_WB),
    .alu_out_MEM_WB(alu_out_MEM_WB),
    .datamem_out_MEM_WB(datamem_out_MEM_WB),
    .writeback_mux_sel_MEM_WB(writeback_mux_sel_MEM_WB),
    .regfile_write_enable_MEM_WB(regfile_write_enable_MEM_WB),
    .regfile_write_address_MEM_WB(regfile_write_address_MEM_WB)
);

StageWriteBack_Top WRITEBACK_STAGE(
    .Instruction_address_MEM_WB(Instruction_address_MEM_WB),
    .alu_out_MEM_WB(alu_out_MEM_WB),
    .datamem_out_MEM_WB(datamem_out_MEM_WB),
    .writeback_mux_sel_MEM_WB(writeback_mux_sel_MEM_WB),
    .regfile_write_enable_MEM_WB(regfile_write_enable_MEM_WB),
    .regfile_write_address_MEM_WB(regfile_write_address_MEM_WB),

    .regfile_write_data(regfile_write_data_WB),
    .regfile_write_enable_WB(regfile_write_enable_WB),
    .regfile_write_address_WB(regfile_write_address_WB)
);

endmodule
