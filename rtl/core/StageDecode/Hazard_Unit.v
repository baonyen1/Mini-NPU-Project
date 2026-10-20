`timescale 1ns / 1ps

// Central stall/flush logic (approach A of docs/core_stall.md).
//
//   stall_mem = mem_busy                  (MEM waits: FIFO full or READ_RESULT not ready)
//   stall_ex  = stall_mem | div_busy      (the EX stage cannot advance)
//   stall_id  = stall_ex | load_use       (the ID stage cannot advance)
//   redirect  = taken branch/jump in EX and EX not held
//   hold IF/ID = stall_id, hold ID/EX = stall_ex, hold EX/MEM = stall_mem
//   bubble into EX/MEM = div_busy & !stall_mem, bubble into MEM/WB = stall_mem
//   bubble into ID/EX = load_use & !stall_ex
// A younger stage must never bubble over an instruction that an older stall is
// holding, hence the "& !stall_<older stage>" terms.
module Hazard_Unit(
    pipeline_flush_signal,
    opcode_IF_ID,
    funct3_IF_ID,
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

    div_busy,
    mem_busy,

    pc_write,
    if_id_stall,
    if_id_flush,
    id_ex_stall,
    id_ex_flush,
    ex_mem_stall,
    ex_mem_bubble,
    mem_wb_bubble,
    fw_mux_0_sel,
    fw_mux_1_sel,
    load_use_stall
);

input pipeline_flush_signal;
input [6:0] opcode_IF_ID;
input [2:0] funct3_IF_ID;
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

input div_busy;      // a divide/remainder is in EX and its result is not ready
input mem_busy;      // the instruction in MEM waits for the engine (cmd_ready / rd_ready)

output pc_write;
output if_id_stall;
output if_id_flush;
output id_ex_stall;
output id_ex_flush;
output ex_mem_stall;
output ex_mem_bubble;
output mem_wb_bubble;
output [2:0] fw_mux_0_sel;
output [2:0] fw_mux_1_sel;
output load_use_stall;

wire uses_rs1_IF_ID;
wire uses_rs2_IF_ID;
wire stall_mem;
wire stall_ex;
wire stall_id;
wire redirect;

assign uses_rs1_IF_ID = (opcode_IF_ID == 7'b0110011) ||
                        (opcode_IF_ID == 7'b0010011) ||
                        (opcode_IF_ID == 7'b0000011) ||
                        (opcode_IF_ID == 7'b0100011) ||
                        (opcode_IF_ID == 7'b1100011) ||
                        (opcode_IF_ID == 7'b1100111) ||
                        // CSRRW/CSRRS/CSRRC read rs1; the immediate forms carry a zimm there
                        ((opcode_IF_ID == 7'b1110011) && !funct3_IF_ID[2] && (funct3_IF_ID[1:0] != 2'b00)) ||
                        (opcode_IF_ID == 7'b0001011);

assign uses_rs2_IF_ID = (opcode_IF_ID == 7'b0110011) ||
                        (opcode_IF_ID == 7'b0100011) ||
                        (opcode_IF_ID == 7'b1100011) ||
                        // custom-0: COMPUTE (010) and READ_RESULT (011) leave the rs2 field unused
                        ((opcode_IF_ID == 7'b0001011) && (funct3_IF_ID != 3'b010) && (funct3_IF_ID != 3'b011));

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

assign stall_mem = mem_busy;
assign stall_ex  = stall_mem | div_busy;
assign stall_id = stall_ex | load_use_stall;
// A branch or jump that is held in EX must not redirect yet.
assign redirect = pipeline_flush_signal & ~stall_ex;

assign pc_write      = ~stall_id | redirect;
assign if_id_stall   = stall_id;
assign if_id_flush   = redirect;
assign id_ex_stall   = stall_ex;
assign id_ex_flush   = redirect | (load_use_stall & ~stall_ex);
assign ex_mem_stall   = stall_mem;
assign ex_mem_bubble  = div_busy & ~stall_mem;
assign mem_wb_bubble  = stall_mem;

endmodule
