`timescale 1ns / 1ps

module Hazard_Unit(
    cpu_en,
    pipeline_flush_signal,
    opcode_IF_ID,
    regfile_read_address_0_IF_ID,
    regfile_read_address_1_IF_ID,

    datamem_read_enable_ID_EX,
    regfile_write_address_ID_EX,
    regfile_read_address_0_ID_EX,
    regfile_read_address_1_ID_EX,

    regfile_write_address_EX_MEM,
    regfile_write_enable_EX_MEM,
    writeback_mux_sel_EX_MEM,

    regfile_write_address_MEM_WB,
    regfile_write_enable_MEM_WB,
    writeback_mux_sel_MEM_WB,

    pc_write,
    if_id_stall,
    if_id_flush,
    id_ex_stall,
    id_ex_flush,
    fw_mux_0_sel,
    fw_mux_1_sel,
    load_use_stall
);

input cpu_en;
input pipeline_flush_signal;
input [6:0] opcode_IF_ID;
input [4:0] regfile_read_address_0_IF_ID;
input [4:0] regfile_read_address_1_IF_ID;

input datamem_read_enable_ID_EX;
input [4:0] regfile_write_address_ID_EX;
input [4:0] regfile_read_address_0_ID_EX;
input [4:0] regfile_read_address_1_ID_EX;

input [4:0] regfile_write_address_EX_MEM;
input regfile_write_enable_EX_MEM;
input [1:0] writeback_mux_sel_EX_MEM;

input [4:0] regfile_write_address_MEM_WB;
input regfile_write_enable_MEM_WB;
input [1:0] writeback_mux_sel_MEM_WB;

output pc_write;
output if_id_stall;
output if_id_flush;
output id_ex_stall;
output id_ex_flush;
output [2:0] fw_mux_0_sel;
output [2:0] fw_mux_1_sel;
output load_use_stall;

wire uses_rs1_IF_ID;
wire uses_rs2_IF_ID;
wire hazard_bubble;

assign uses_rs1_IF_ID = (opcode_IF_ID == 7'b0110011) ||
                        (opcode_IF_ID == 7'b0010011) ||
                        (opcode_IF_ID == 7'b0000011) ||
                        (opcode_IF_ID == 7'b0100011) ||
                        (opcode_IF_ID == 7'b1100011) ||
                        (opcode_IF_ID == 7'b1100111);

assign uses_rs2_IF_ID = (opcode_IF_ID == 7'b0110011) ||
                        (opcode_IF_ID == 7'b0100011) ||
                        (opcode_IF_ID == 7'b1100011);

Hazard_Detection_Unit LOAD_USE_DETECTOR(
    .datamem_read_enable_ID_EX(datamem_read_enable_ID_EX),
    .regfile_write_address_ID_EX(regfile_write_address_ID_EX),
    .regfile_read_address_0_IF_ID(regfile_read_address_0_IF_ID),
    .regfile_read_address_1_IF_ID(regfile_read_address_1_IF_ID),
    .uses_rs1_IF_ID(uses_rs1_IF_ID),
    .uses_rs2_IF_ID(uses_rs2_IF_ID),
    .load_use_stall(load_use_stall)
);

Forwarding_Unit FORWARDING_CONTROL(
    .regfile_read_address_0_ID_EX(regfile_read_address_0_ID_EX),
    .regfile_read_address_1_ID_EX(regfile_read_address_1_ID_EX),
    .regfile_write_address_EX_MEM(regfile_write_address_EX_MEM),
    .regfile_write_enable_EX_MEM(regfile_write_enable_EX_MEM),
    .writeback_mux_sel_EX_MEM(writeback_mux_sel_EX_MEM),
    .regfile_write_address_MEM_WB(regfile_write_address_MEM_WB),
    .regfile_write_enable_MEM_WB(regfile_write_enable_MEM_WB),
    .writeback_mux_sel_MEM_WB(writeback_mux_sel_MEM_WB),
    .fw_mux_0_sel(fw_mux_0_sel),
    .fw_mux_1_sel(fw_mux_1_sel)
);

assign hazard_bubble = cpu_en & load_use_stall;

// Branch/jump redirection has priority over a simultaneous load-use stall.
assign pc_write = cpu_en & ((~load_use_stall) | pipeline_flush_signal);
assign if_id_stall = (~cpu_en) | hazard_bubble;
assign if_id_flush = pipeline_flush_signal;
assign id_ex_stall = ~cpu_en;
assign id_ex_flush = pipeline_flush_signal | hazard_bubble;

endmodule
