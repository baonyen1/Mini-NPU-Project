`timescale 1ns / 1ps

module StageExecute_Top(
    clk,
    reset,

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
    csr_op_ID_EX,
    fence_i_ID_EX,
    custom_ctl_ID_EX,
    insn_ID_EX,
    regfile_read_address_0_ID_EX,
    valid_ID_EX,

    // stall interface (Hazard_Unit, docs/core_stall.md)
    ex_stall,
    ex_mem_stall,
    ex_mem_bubble,
    div_busy,
    operand_0_ex,
    operand_1_ex,

    // engine CSR port (spec 7.1)
    csr_we,
    csr_addr,
    csr_wdata,
    csr_rdata,

    // retire information for minstret
    valid_MEM_WB,

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
    regfile_write_address_EX_MEM,
    valid_EX_MEM,
    custom_ctl_EX_MEM,
    insn_EX_MEM
);

input clk, reset;

input [31:0] Instruction_address_ID_EX;
input [31:0] regfile_out_0_ID_EX;
input [31:0] regfile_out_1_ID_EX;
input [31:0] immediate_ID_EX;
input [4:0] regfile_write_address_ID_EX;
input jump_target_mux_sel_ID_EX;
input [1:0] alu_src_a_sel_ID_EX;
input mux_1_sel_ID_EX;
input [5:0] alu_operation_ID_EX;
input alu_branch_ID_EX;
input [2:0] alu_branch_control_ID_EX;
input jump_flag_ID_EX;
input [2:0] data_format_ID_EX;
input datamem_read_enable_ID_EX;
input datamem_write_enable_ID_EX;
input regfile_write_enable_ID_EX;
input [1:0] writeback_mux_sel_ID_EX;
input [2:0] csr_op_ID_EX;
input fence_i_ID_EX;
input [4:0] custom_ctl_ID_EX;
input [31:0] insn_ID_EX;
input [4:0] regfile_read_address_0_ID_EX;
input valid_ID_EX;

input [31:0] csr_rdata;
input valid_MEM_WB;

input ex_stall;        // EX cannot advance this cycle
input ex_mem_stall;    // hold EX/MEM
input ex_mem_bubble;   // load a NOP into EX/MEM

input [31:0] alu_out_MEM_WB;
input [31:0] datamem_out_MEM_WB;
input [31:0] Instruction_address_MEM_WB;
input [2:0] fw_mux_0_sel;
input [2:0] fw_mux_1_sel;

output div_busy;       // a divide/remainder is in EX and its result is not ready
output [31:0] operand_0_ex;   // rs1 / rs2 values as EX sees them (after forwarding)
output [31:0] operand_1_ex;
output csr_we;
output [11:0] csr_addr;
output [31:0] csr_wdata;

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
output valid_EX_MEM;
output [4:0] custom_ctl_EX_MEM;
output [31:0] insn_EX_MEM;

wire [31:0] fw_mux_0_output;
wire [31:0] fw_mux_1_output;
wire [31:0] alu_input_a;

assign operand_0_ex = fw_mux_0_output;
assign operand_1_ex = fw_mux_1_output;
wire [31:0] mux_1_output;
wire [31:0] alu_output;
wire [31:0] ex_result;
wire [31:0] bb_result;
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

// ---- RV32M --------------------------------------------------------------
// alu_operation_ID_EX[5:4] = 01 selects the M unit and [2:0] is the funct3:
// [2] = 0 multiply (combinational), [2] = 1 divide/remainder (iterative).
wire is_m_op   = (alu_operation_ID_EX[5:4] == 2'b01);
wire is_mul_op = is_m_op & ~alu_operation_ID_EX[2];
wire is_div_op = is_m_op &  alu_operation_ID_EX[2];

wire [31:0] mul_result;
wire [31:0] div_result;
wire div_done;

Multiplier MULTIPLIER(
    .a(alu_input_a),
    .b(mux_1_output),
    .op(alu_operation_ID_EX[1:0]),
    .result(mul_result)
);

// The divider starts once per instruction. div_started marks "start already
// issued for the instruction now in EX"; it clears when that instruction
// leaves EX. The divider samples its operands at start, so the forwarding
// sources disappearing afterwards does not matter.
reg div_started;
wire div_start = is_div_op & ~div_started;

Divider DIVIDER(
    .clk(clk),
    .reset(reset),
    .start(div_start),
    .is_signed(~alu_operation_ID_EX[0]),
    .is_rem(alu_operation_ID_EX[1]),
    .a(alu_input_a),
    .b(mux_1_output),
    .busy(),
    .done(div_done),
    .result(div_result)
);

assign div_busy = is_div_op & ~(div_started & div_done);

always @(posedge clk) begin
    if (reset)
        div_started <= 1'b0;
    else if (div_start)
        div_started <= 1'b1;
    else if (~ex_stall)
        div_started <= 1'b0;
end

// ---- Zicsr --------------------------------------------------------------
wire csr_is_op = (csr_op_ID_EX[1:0] != 2'b00);
wire [31:0] csr_operand = csr_op_ID_EX[2] ? {27'b0, regfile_read_address_0_ID_EX} : fw_mux_0_output;
wire [31:0] csr_value;
wire [1:0] older_in_flight = valid_EX_MEM + valid_MEM_WB;   // valid instructions in MEM and WB

CSR_Unit CSR(
    .clk(clk),
    .reset(reset),
    .csr_op(csr_op_ID_EX),
    .csr_addr(immediate_ID_EX[11:0]),
    .wdata(csr_operand),
    .rs1_nonzero(regfile_read_address_0_ID_EX != 5'b00000),
    .ex_advance(~ex_stall),
    .rdata(csr_value),
    .retire(valid_MEM_WB),
    .older_in_flight(older_in_flight),
    .npu_csr_we(csr_we),
    .npu_csr_addr(csr_addr),
    .npu_csr_wdata(csr_wdata),
    .npu_csr_rdata(csr_rdata)
);

// ---- Zbb: alu_operation[5] = 1, operation in [4:0] -----------------------
wire is_bb_op = alu_operation_ID_EX[5];

BitManip BITMANIP(
    .a(alu_input_a),
    .b(mux_1_output),
    .op(alu_operation_ID_EX[4:0]),
    .result(bb_result)
);

assign ex_result = csr_is_op ? csr_value :
                   is_bb_op  ? bb_result :
                   is_mul_op ? mul_result :
                   is_div_op ? div_result :
                   alu_output;

// fence.i is a jump to PC+4: it flushes the younger instructions and refetches
// them (there is no I-cache; spec 5). It reuses the PC-relative jump path with
// the immediate forced to 4.
wire [31:0] bru_immediate = fence_i_ID_EX ? 32'd4 : immediate_ID_EX;
wire bru_jump_flag = jump_flag_ID_EX | fence_i_ID_EX;

BRU BRANCH_RESOLUTION_UNIT(
    .Instruction_address_ID_EX(Instruction_address_ID_EX),
    .regfile_out_0_ID_EX(fw_mux_0_output),
    .immediate_ID_EX(bru_immediate),
    .jump_target_mux_sel_ID_EX(jump_target_mux_sel_ID_EX),
    .alu_branch_ID_EX(alu_branch_ID_EX),
    .alu_branch_response(alu_branch_response),
    .jump_flag_ID_EX(bru_jump_flag),
    .jump_branch_signal(jump_branch_signal),
    .flush_signal(flush_signal),
    .jump_branch_destination(jump_branch_destination)
);

EX_MEM_Reg EX_MEM(
    .clk(clk),
    .reset(reset),
    .stall(ex_mem_stall),
    .bubble(ex_mem_bubble),

    .Instruction_address_ID_EX(Instruction_address_ID_EX),
    .alu_output(ex_result),
    .datamem_wr_data(fw_mux_1_output),
    .data_format_ID_EX(data_format_ID_EX),
    .datamem_read_enable_ID_EX(datamem_read_enable_ID_EX),
    .datamem_write_enable_ID_EX(datamem_write_enable_ID_EX),
    .writeback_mux_sel_ID_EX(writeback_mux_sel_ID_EX),
    .regfile_write_enable_ID_EX(regfile_write_enable_ID_EX),
    .regfile_write_address_ID_EX(regfile_write_address_ID_EX),
    .valid_ID_EX(valid_ID_EX),
    .custom_ctl_ID_EX(custom_ctl_ID_EX),
    .insn_ID_EX(insn_ID_EX),

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

endmodule
