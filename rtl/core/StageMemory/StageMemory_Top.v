`timescale 1ns / 1ps

module StageMemory_Top(
    clk,
    reset,

    // input from EX/MEM
    Instruction_address_EX_MEM,
    alu_out_EX_MEM,
    datamem_wr_data_EX_MEM,
    data_format_EX_MEM,
    datamem_read_enable_EX_MEM,
    datamem_write_enable_EX_MEM,
    writeback_mux_sel_EX_MEM,
    regfile_write_enable_EX_MEM,
    regfile_write_address_EX_MEM,
    valid_EX_MEM,

    // output to MEM/WB
    Instruction_address_MEM_WB,
    alu_out_MEM_WB,
    datamem_out_MEM_WB,
    writeback_mux_sel_MEM_WB,
    regfile_write_enable_MEM_WB,
    regfile_write_address_MEM_WB,
    valid_MEM_WB
);

input clk, reset;

input [31:0] Instruction_address_EX_MEM;
input [31:0] alu_out_EX_MEM;
input [31:0] datamem_wr_data_EX_MEM;
input [2:0] data_format_EX_MEM;
input datamem_read_enable_EX_MEM;
input datamem_write_enable_EX_MEM;
input [1:0] writeback_mux_sel_EX_MEM;
input regfile_write_enable_EX_MEM;
input [4:0] regfile_write_address_EX_MEM;
input valid_EX_MEM;

output [31:0] Instruction_address_MEM_WB;
output [31:0] alu_out_MEM_WB;
output [31:0] datamem_out_MEM_WB;
output [1:0] writeback_mux_sel_MEM_WB;
output regfile_write_enable_MEM_WB;
output [4:0] regfile_write_address_MEM_WB;
output valid_MEM_WB;

LSU LOAD_STORE_UNIT(
    .clk(clk),
    .reset(reset),
    .read_enable(datamem_read_enable_EX_MEM),
    .write_enable(datamem_write_enable_EX_MEM),
    .data_format(data_format_EX_MEM),
    .address(alu_out_EX_MEM[9:0]),
    .write_data(datamem_wr_data_EX_MEM),
    .read_data(datamem_out_MEM_WB)
);

MEM_WB_Reg MEM_WB(
    .clk(clk),
    .reset(reset),

    .Instruction_address_EX_MEM(Instruction_address_EX_MEM),
    .alu_out_EX_MEM(alu_out_EX_MEM),
    .writeback_mux_sel_EX_MEM(writeback_mux_sel_EX_MEM),
    .regfile_write_enable_EX_MEM(regfile_write_enable_EX_MEM),
    .regfile_write_address_EX_MEM(regfile_write_address_EX_MEM),
    .valid_EX_MEM(valid_EX_MEM),

    .Instruction_address_MEM_WB(Instruction_address_MEM_WB),
    .alu_out_MEM_WB(alu_out_MEM_WB),
    .writeback_mux_sel_MEM_WB(writeback_mux_sel_MEM_WB),
    .regfile_write_enable_MEM_WB(regfile_write_enable_MEM_WB),
    .regfile_write_address_MEM_WB(regfile_write_address_MEM_WB),
    .valid_MEM_WB(valid_MEM_WB)
);

endmodule
