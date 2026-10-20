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
    jump_branch_signal,

    // instruction memory (ITCM): combinational read
    imem_addr,
    imem_rdata,

    // data memory bus: the memory answers a dmem_re one cycle later on dmem_rdata
    dmem_re,
    dmem_we,
    dmem_addr,
    dmem_wdata,
    dmem_rdata,

    // engine CSR port (spec 7.1)
    csr_we,
    csr_addr,
    csr_wdata,
    csr_rdata,

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
    rd_data

`ifdef RVVI_TRACE
    // retire trace (spec 5): one record per retired instruction, verification only
    ,
    rvvi_valid,
    rvvi_order,
    rvvi_pc,
    rvvi_insn,
    rvvi_rd,
    rvvi_rd_wdata,
    rvvi_mem_addr,
    rvvi_mem_wdata,
    rvvi_mem_wmask,
    rvvi_trap
`endif
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

output [31:0] imem_addr;
input [31:0] imem_rdata;

output dmem_re;
output [3:0] dmem_we;
output [31:0] dmem_addr;
output [31:0] dmem_wdata;
input [31:0] dmem_rdata;

output csr_we;
output [11:0] csr_addr;
output [31:0] csr_wdata;
input [31:0] csr_rdata;

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

`ifdef RVVI_TRACE
output rvvi_valid;
output [63:0] rvvi_order;
output [31:0] rvvi_pc;
output [31:0] rvvi_insn;
output [4:0] rvvi_rd;
output [31:0] rvvi_rd_wdata;
output [31:0] rvvi_mem_addr;
output [31:0] rvvi_mem_wdata;
output [3:0] rvvi_mem_wmask;
output rvvi_trap;
`endif

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
wire [5:0] alu_operation_ID_EX;
wire alu_branch_ID_EX;
wire [2:0] alu_branch_control_ID_EX;
wire jump_flag_ID_EX;
wire [2:0] data_format_ID_EX;
wire datamem_read_enable_ID_EX;
wire datamem_write_enable_ID_EX;
wire regfile_write_enable_ID_EX;
wire [1:0] writeback_mux_sel_ID_EX;
wire [2:0] csr_op_ID_EX;
wire fence_i_ID_EX;
wire [4:0] custom_ctl_ID_EX, custom_ctl_EX_MEM;
wire mem_busy;
wire hazard_ex_mem_stall;
wire hazard_mem_wb_bubble;
wire load_like_ID_EX;
wire valid_IF_ID, valid_ID_EX, valid_EX_MEM, valid_MEM_WB;
wire [31:0] insn_ID_EX, insn_EX_MEM, insn_MEM_WB;
wire [31:0] mem_addr_MEM_WB, mem_wdata_MEM_WB;
wire [3:0] mem_wmask_MEM_WB;

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
wire hazard_ex_mem_bubble;
wire div_busy;
wire [31:0] operand_0_ex, operand_1_ex;
wire [2:0] fw_mux_0_sel;
wire [2:0] fw_mux_1_sel;

Hazard_Unit HAZARD_UNIT(
    .pipeline_flush_signal(pipeline_flush_signal),
    .opcode_IF_ID(Instruction_IF_ID[6:0]),
    .funct3_IF_ID(Instruction_IF_ID[14:12]),
    .regfile_read_address_0_IF_ID(Instruction_IF_ID[19:15]),
    .regfile_read_address_1_IF_ID(Instruction_IF_ID[24:20]),
    .datamem_read_enable_ID_EX(load_like_ID_EX),
    .regfile_write_address_ID_EX(regfile_write_address_ID_EX),
    .regfile_read_address_0_ID_EX(regfile_read_address_0_ID_EX),
    .regfile_read_address_1_ID_EX(regfile_read_address_1_ID_EX),
    .regfile_write_address_EX_MEM(regfile_write_address_EX_MEM),
    .regfile_write_enable_EX_MEM(regfile_write_enable_EX_MEM),
    .writeback_mux_sel_EX_MEM(writeback_mux_sel_EX_MEM),
    .regfile_write_address_MEM_WB(regfile_write_address_MEM_WB),
    .regfile_write_enable_MEM_WB(regfile_write_enable_MEM_WB),
    .writeback_mux_sel_MEM_WB(writeback_mux_sel_MEM_WB),
    .div_busy(div_busy),
    .mem_busy(mem_busy),
    .pc_write(hazard_pc_write),
    .if_id_stall(hazard_if_id_stall),
    .if_id_flush(hazard_if_id_flush),
    .id_ex_stall(hazard_id_ex_stall),
    .id_ex_flush(hazard_id_ex_flush),
    .ex_mem_stall(hazard_ex_mem_stall),
    .ex_mem_bubble(hazard_ex_mem_bubble),
    .mem_wb_bubble(hazard_mem_wb_bubble),
    .fw_mux_0_sel(fw_mux_0_sel),
    .fw_mux_1_sel(fw_mux_1_sel),
    .load_use_stall(load_use_stall)
);

// READ_RESULT returns its data in WB like a load, so it joins the load-use detector
assign load_like_ID_EX = datamem_read_enable_ID_EX |
                         (custom_ctl_ID_EX[4] & (custom_ctl_ID_EX[2:0] == 3'b011));

StageIF_TOP IF_STAGE(
    .clk(clk),
    .reset(reset),
    .pc_write(hazard_pc_write),
    .stall(hazard_if_id_stall),
    .flush(hazard_if_id_flush),
    .jump_branch_signal(jump_branch_signal),
    .jump_branch_destination(jump_branch_destination),

    .Instruction_IF_ID(Instruction_IF_ID),
    .Instruction_address_IF_ID(Instruction_address_IF_ID),
    .valid_IF_ID(valid_IF_ID),
    .imem_addr(imem_addr),
    .imem_rdata(imem_rdata)
);

StageDecode_Top DECODE_STAGE(
    .clk(clk),
    .reset(reset),
    .stall(hazard_id_ex_stall),
    .flush(hazard_id_ex_flush),
    .held_operand_0(operand_0_ex),
    .held_operand_1(operand_1_ex),

    .Instruction_IF_ID(Instruction_IF_ID),
    .Instruction_address_IF_ID(Instruction_address_IF_ID),
    .valid_IF_ID(valid_IF_ID),

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
    .writeback_mux_sel_ID_EX(writeback_mux_sel_ID_EX),
    .csr_op_ID_EX(csr_op_ID_EX),
    .fence_i_ID_EX(fence_i_ID_EX),
    .custom_ctl_ID_EX(custom_ctl_ID_EX),
    .valid_ID_EX(valid_ID_EX),
    .insn_ID_EX(insn_ID_EX)
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
    .csr_op_ID_EX(csr_op_ID_EX),
    .fence_i_ID_EX(fence_i_ID_EX),
    .custom_ctl_ID_EX(custom_ctl_ID_EX),
    .insn_ID_EX(insn_ID_EX),
    .regfile_read_address_0_ID_EX(regfile_read_address_0_ID_EX),
    .valid_ID_EX(valid_ID_EX),

    .csr_we(csr_we),
    .csr_addr(csr_addr),
    .csr_wdata(csr_wdata),
    .csr_rdata(csr_rdata),
    .valid_MEM_WB(valid_MEM_WB),

    .operand_0_ex(operand_0_ex),
    .operand_1_ex(operand_1_ex),
    .ex_stall(hazard_id_ex_stall),
    .ex_mem_stall(hazard_ex_mem_stall),
    .ex_mem_bubble(hazard_ex_mem_bubble),
    .div_busy(div_busy),

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
    .regfile_write_address_EX_MEM(regfile_write_address_EX_MEM),
    .valid_EX_MEM(valid_EX_MEM),
    .custom_ctl_EX_MEM(custom_ctl_EX_MEM),
    .insn_EX_MEM(insn_EX_MEM)
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
    .valid_EX_MEM(valid_EX_MEM),
    .custom_ctl_EX_MEM(custom_ctl_EX_MEM),
    .insn_EX_MEM(insn_EX_MEM),

    .dmem_re(dmem_re),
    .dmem_we(dmem_we),
    .dmem_addr(dmem_addr),
    .dmem_wdata(dmem_wdata),
    .dmem_rdata(dmem_rdata),

    .cmd_valid(cmd_valid),
    .cmd_ready(cmd_ready),
    .cmd_op(cmd_op),
    .cmd_addr(cmd_addr),
    .cmd_k(cmd_k),
    .cmd_clr(cmd_clr),
    .rd_req(rd_req),
    .rd_idx(rd_idx),
    .rd_ready(rd_ready),
    .rd_data(rd_data),
    .mem_busy(mem_busy),

    .Instruction_address_MEM_WB(Instruction_address_MEM_WB),
    .alu_out_MEM_WB(alu_out_MEM_WB),
    .datamem_out_MEM_WB(datamem_out_MEM_WB),
    .writeback_mux_sel_MEM_WB(writeback_mux_sel_MEM_WB),
    .regfile_write_enable_MEM_WB(regfile_write_enable_MEM_WB),
    .regfile_write_address_MEM_WB(regfile_write_address_MEM_WB),
    .valid_MEM_WB(valid_MEM_WB),
    .insn_MEM_WB(insn_MEM_WB),
    .mem_addr_MEM_WB(mem_addr_MEM_WB),
    .mem_wdata_MEM_WB(mem_wdata_MEM_WB),
    .mem_wmask_MEM_WB(mem_wmask_MEM_WB)
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

`ifdef RVVI_TRACE
// ---- RVVI retire trace --------------------------------------------------------------------
// One record per instruction leaving WB (valid_MEM_WB), so stalls and flushes never repeat or
// skip a record. `order` counts retired instructions from reset.
reg [63:0] rvvi_order_q;
always @(posedge clk) begin
    if (reset)              rvvi_order_q <= 64'b0;
    else if (valid_MEM_WB)  rvvi_order_q <= rvvi_order_q + 64'd1;
end

wire rvvi_writes_rd = regfile_write_enable_WB && (regfile_write_address_WB != 5'b00000);

assign rvvi_valid     = valid_MEM_WB;
assign rvvi_order     = rvvi_order_q;
assign rvvi_pc        = Instruction_address_MEM_WB;
assign rvvi_insn      = insn_MEM_WB;
assign rvvi_rd        = rvvi_writes_rd ? regfile_write_address_WB : 5'b00000;
assign rvvi_rd_wdata  = rvvi_writes_rd ? regfile_write_data_WB : 32'b0;
assign rvvi_mem_addr  = mem_addr_MEM_WB;
assign rvvi_mem_wdata = mem_wdata_MEM_WB;
assign rvvi_mem_wmask = mem_wmask_MEM_WB;
assign rvvi_trap      = 1'b0;                 // no traps until decision W2-1 is recorded
`endif

endmodule
