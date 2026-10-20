`timescale 1ns / 1ps

// MEM stage. Besides the data memory access, it pushes custom-0 commands to the
// engine and performs READ_RESULT (plan Task 9, spec 6.3):
//   * LOAD_WEIGHT / LOAD_INPUT / COMPUTE (and the reserved funct3 values, pushed
//     as op ILLEGAL) are pushed here; rs1 arrives as alu_out_EX_MEM and rs2 as
//     datamem_wr_data_EX_MEM. A full FIFO (cmd_ready = 0) stalls the pipeline.
//   * READ_RESULT raises rd_req and waits for rd_ready (engine idle and FIFO
//     empty). rd_data is captured into MEM/WB and written back like a load.
// While the stage waits (mem_busy) MEM/WB loads a bubble so nothing retires twice.
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
    custom_ctl_EX_MEM,

    // engine command / result port (spec 7.1)
    cmd_valid,
    cmd_ready,
    cmd_op,
    cmd_addr,
    cmd_k,
    cmd_clr,
    rd_req,
    rd_idx,
    rd_ready,
    rd_data,

    // the MEM stage cannot complete this cycle
    mem_busy,

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
input [4:0] custom_ctl_EX_MEM;     // [4] custom-0, [3] clr (funct7[0]), [2:0] funct3

output cmd_valid;
input cmd_ready;
output [1:0] cmd_op;
output [31:0] cmd_addr;
output [31:0] cmd_k;
output cmd_clr;
output rd_req;
output [3:0] rd_idx;
input rd_ready;
input [31:0] rd_data;

output mem_busy;

output [31:0] Instruction_address_MEM_WB;
output [31:0] alu_out_MEM_WB;
output [31:0] datamem_out_MEM_WB;
output [1:0] writeback_mux_sel_MEM_WB;
output regfile_write_enable_MEM_WB;
output [4:0] regfile_write_address_MEM_WB;
output valid_MEM_WB;

wire [31:0] lsu_read_data;
wire [31:0] rd_data_MEM_WB;
wire rr_MEM_WB;

// ---- custom-0 ---------------------------------------------------------------
wire is_custom = valid_EX_MEM & custom_ctl_EX_MEM[4];
wire is_rr     = is_custom & (custom_ctl_EX_MEM[2:0] == 3'b011);
wire is_push   = is_custom & (custom_ctl_EX_MEM[2:0] != 3'b011);
wire is_mac    = (custom_ctl_EX_MEM[2:0] == 3'b010);

assign cmd_valid = is_push;
// funct3 100..111 (reserved) is pushed as op 3 (ILLEGAL); 000/001/010 map to 0/1/2
assign cmd_op   = custom_ctl_EX_MEM[2] ? 2'd3 : custom_ctl_EX_MEM[1:0];
// COMPUTE carries K in rs1 and has no address; the other commands carry rs1 = address, rs2 = K
assign cmd_addr = is_mac ? 32'b0 : alu_out_EX_MEM;
assign cmd_k    = is_mac ? alu_out_EX_MEM : datamem_wr_data_EX_MEM;
assign cmd_clr  = is_mac & custom_ctl_EX_MEM[3];

assign rd_req = is_rr;
assign rd_idx = alu_out_EX_MEM[3:0];     // upper bits of rs1 are ignored (spec 6.3)

assign mem_busy = (is_push & ~cmd_ready) | (is_rr & ~rd_ready);

// ---- data memory ------------------------------------------------------------
LSU LOAD_STORE_UNIT(
    .clk(clk),
    .reset(reset),
    .read_enable(datamem_read_enable_EX_MEM),
    .write_enable(datamem_write_enable_EX_MEM),
    .data_format(data_format_EX_MEM),
    .address(alu_out_EX_MEM[9:0]),
    .write_data(datamem_wr_data_EX_MEM),
    .read_data(lsu_read_data)
);

// READ_RESULT returns its data through the load-data path (writeback select 01)
assign datamem_out_MEM_WB = rr_MEM_WB ? rd_data_MEM_WB : lsu_read_data;

MEM_WB_Reg MEM_WB(
    .clk(clk),
    .reset(reset),

    .Instruction_address_EX_MEM(Instruction_address_EX_MEM),
    .alu_out_EX_MEM(alu_out_EX_MEM),
    .writeback_mux_sel_EX_MEM(writeback_mux_sel_EX_MEM),
    .regfile_write_enable_EX_MEM(regfile_write_enable_EX_MEM),
    .regfile_write_address_EX_MEM(regfile_write_address_EX_MEM),
    .valid_EX_MEM(valid_EX_MEM),
    .rr_EX_MEM(is_rr),
    .rd_data(rd_data),
    .bubble(mem_busy),

    .Instruction_address_MEM_WB(Instruction_address_MEM_WB),
    .alu_out_MEM_WB(alu_out_MEM_WB),
    .writeback_mux_sel_MEM_WB(writeback_mux_sel_MEM_WB),
    .regfile_write_enable_MEM_WB(regfile_write_enable_MEM_WB),
    .regfile_write_address_MEM_WB(regfile_write_address_MEM_WB),
    .valid_MEM_WB(valid_MEM_WB),
    .rr_MEM_WB(rr_MEM_WB),
    .rd_data_MEM_WB(rd_data_MEM_WB)
);

endmodule
