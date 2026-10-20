`timescale 1ns / 1ps

module Controller(
    Instruction_IF_ID,
    regfile_read_address_0,
    regfile_read_address_1,
    immediate,
    jump_target_mux_sel,
    alu_src_a_sel,
    mux_1_sel,
    alu_operation,
    alu_branch,
    alu_branch_control,
    jump_flag,
    data_format,
    datamem_read_enable,
    datamem_write_enable,
    writeback_mux_sel,
    regfile_write_enable,
    regfile_write_address,
    csr_op
);

input [31:0] Instruction_IF_ID;

output [4:0] regfile_read_address_0;
output [4:0] regfile_read_address_1;
output [31:0] immediate;
output jump_target_mux_sel;
output [1:0] alu_src_a_sel;
output mux_1_sel;
output [5:0] alu_operation;
output alu_branch;
output [2:0] alu_branch_control;
output jump_flag;
output [2:0] data_format;
output datamem_read_enable;
output datamem_write_enable;
output [1:0] writeback_mux_sel;
output regfile_write_enable;
output [4:0] regfile_write_address;
output [2:0] csr_op;

wire [6:0] opcode;
wire [2:0] fun3;
wire [6:0] fun7;

Instruction_Decoder DECODER(
    .instruction(Instruction_IF_ID),
    .Opcode(opcode),
    .Rd(regfile_write_address),
    .fun3(fun3),
    .fun7(fun7),
    .Rs1(regfile_read_address_0),
    .Rs2(regfile_read_address_1)
);

Control_Unit CONTROL_LOGIC(
    .Opcode(opcode),
    .fun3(fun3),
    .fun7(fun7),
    .Branch(alu_branch),
    .Memread(datamem_read_enable),
    .alu_operation(alu_operation),
    .alu_branch_control(alu_branch_control),
    .Memwrite(datamem_write_enable),
    .ALUSrc(mux_1_sel),
    .ALUSrcA(alu_src_a_sel),
    .reg_write(regfile_write_enable),
    .Jump(jump_flag),
    .JumpTargetSel(jump_target_mux_sel),
    .DataFormat(data_format),
    .WB_sel(writeback_mux_sel),
    .csr_op(csr_op)
);

ImmGenerator IMMEDIATE_GENERATOR(
    .instruction(Instruction_IF_ID),
    .Imm_out(immediate)
);

endmodule
