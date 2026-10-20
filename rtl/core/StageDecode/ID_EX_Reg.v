`timescale 1ns / 1ps

module ID_EX_Reg(
    clk,
    reset,
    stall,
    flush,

    // data from Decode
    Instruction_address_IF_ID,
    regfile_out_0,
    regfile_out_1,
    immediate,
    regfile_read_address_0,
    regfile_read_address_1,
    regfile_write_address,

    // control from Decode
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
    regfile_write_enable,
    writeback_mux_sel,
    csr_op,
    fence_i,
    valid,

    // data to Execute
    Instruction_address_ID_EX,
    regfile_out_0_ID_EX,
    regfile_out_1_ID_EX,
    immediate_ID_EX,
    regfile_read_address_0_ID_EX,
    regfile_read_address_1_ID_EX,
    regfile_write_address_ID_EX,

    // control to Execute
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
    valid_ID_EX
);

input clk, reset, stall, flush;

input [31:0] Instruction_address_IF_ID;
input [31:0] regfile_out_0;
input [31:0] regfile_out_1;
input [31:0] immediate;

input [4:0] regfile_read_address_0;
input [4:0] regfile_read_address_1;
input [4:0] regfile_write_address;

input jump_target_mux_sel;
input [1:0] alu_src_a_sel;
input mux_1_sel;
input [5:0] alu_operation;
input alu_branch;
input [2:0] alu_branch_control;
input jump_flag;
input [2:0] data_format;
input datamem_read_enable;
input datamem_write_enable;
input regfile_write_enable;
input [1:0] writeback_mux_sel;
input [2:0] csr_op;
input fence_i;
input valid;

output reg [31:0] Instruction_address_ID_EX;
output reg [31:0] regfile_out_0_ID_EX;
output reg [31:0] regfile_out_1_ID_EX;
output reg [31:0] immediate_ID_EX;

output reg [4:0] regfile_read_address_0_ID_EX;
output reg [4:0] regfile_read_address_1_ID_EX;
output reg [4:0] regfile_write_address_ID_EX;

output reg jump_target_mux_sel_ID_EX;
output reg [1:0] alu_src_a_sel_ID_EX;
output reg mux_1_sel_ID_EX;
output reg [5:0] alu_operation_ID_EX;
output reg alu_branch_ID_EX;
output reg [2:0] alu_branch_control_ID_EX;
output reg jump_flag_ID_EX;
output reg [2:0] data_format_ID_EX;
output reg datamem_read_enable_ID_EX;
output reg datamem_write_enable_ID_EX;
output reg regfile_write_enable_ID_EX;
output reg [1:0] writeback_mux_sel_ID_EX;
output reg [2:0] csr_op_ID_EX;
output reg fence_i_ID_EX;
output reg valid_ID_EX;

always @(posedge clk) begin
    if (reset) begin
        Instruction_address_ID_EX <= 32'b0;
        regfile_out_0_ID_EX       <= 32'b0;
        regfile_out_1_ID_EX       <= 32'b0;
        immediate_ID_EX           <= 32'b0;

        regfile_read_address_0_ID_EX <= 5'b0;
        regfile_read_address_1_ID_EX <= 5'b0;
        regfile_write_address_ID_EX  <= 5'b0;

        jump_target_mux_sel_ID_EX   <= 1'b0;
        alu_src_a_sel_ID_EX          <= 2'b00;
        mux_1_sel_ID_EX             <= 1'b0;
        alu_operation_ID_EX         <= 6'b000010;
        alu_branch_ID_EX            <= 1'b0;
        alu_branch_control_ID_EX    <= 3'b000;
        jump_flag_ID_EX             <= 1'b0;
        data_format_ID_EX            <= 3'b010;
        datamem_read_enable_ID_EX   <= 1'b0;
        datamem_write_enable_ID_EX  <= 1'b0;
        regfile_write_enable_ID_EX  <= 1'b0;
        writeback_mux_sel_ID_EX     <= 2'b00;
        csr_op_ID_EX                <= 3'b000;
        fence_i_ID_EX               <= 1'b0;
        valid_ID_EX                 <= 1'b0;
    end
    else if (flush) begin
        Instruction_address_ID_EX <= 32'b0;
        regfile_out_0_ID_EX       <= 32'b0;
        regfile_out_1_ID_EX       <= 32'b0;
        immediate_ID_EX           <= 32'b0;

        regfile_read_address_0_ID_EX <= 5'b0;
        regfile_read_address_1_ID_EX <= 5'b0;
        regfile_write_address_ID_EX  <= 5'b0;

        jump_target_mux_sel_ID_EX   <= 1'b0;
        alu_src_a_sel_ID_EX          <= 2'b00;
        mux_1_sel_ID_EX             <= 1'b0;
        alu_operation_ID_EX         <= 6'b000010;
        alu_branch_ID_EX            <= 1'b0;
        alu_branch_control_ID_EX    <= 3'b000;
        jump_flag_ID_EX             <= 1'b0;
        data_format_ID_EX            <= 3'b010;
        datamem_read_enable_ID_EX   <= 1'b0;
        datamem_write_enable_ID_EX  <= 1'b0;
        regfile_write_enable_ID_EX  <= 1'b0;
        writeback_mux_sel_ID_EX     <= 2'b00;
        csr_op_ID_EX                <= 3'b000;
        fence_i_ID_EX               <= 1'b0;
        valid_ID_EX                 <= 1'b0;
    end
    else if (!stall) begin
        Instruction_address_ID_EX <= Instruction_address_IF_ID;
        regfile_out_0_ID_EX       <= regfile_out_0;
        regfile_out_1_ID_EX       <= regfile_out_1;
        immediate_ID_EX           <= immediate;

        regfile_read_address_0_ID_EX <= regfile_read_address_0;
        regfile_read_address_1_ID_EX <= regfile_read_address_1;
        regfile_write_address_ID_EX  <= regfile_write_address;

        jump_target_mux_sel_ID_EX   <= jump_target_mux_sel;
        alu_src_a_sel_ID_EX          <= alu_src_a_sel;
        mux_1_sel_ID_EX             <= mux_1_sel;
        alu_operation_ID_EX         <= alu_operation;
        alu_branch_ID_EX            <= alu_branch;
        alu_branch_control_ID_EX    <= alu_branch_control;
        jump_flag_ID_EX             <= jump_flag;
        data_format_ID_EX            <= data_format;
        datamem_read_enable_ID_EX   <= datamem_read_enable;
        datamem_write_enable_ID_EX  <= datamem_write_enable;
        regfile_write_enable_ID_EX  <= regfile_write_enable;
        writeback_mux_sel_ID_EX     <= writeback_mux_sel;
        csr_op_ID_EX                <= csr_op;
        fence_i_ID_EX               <= fence_i;
        valid_ID_EX                 <= valid;
    end
end

endmodule
