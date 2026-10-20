`timescale 1ns / 1ps

module EX_MEM_Reg(
    clk,
    reset,
    stall,
    bubble,

    Instruction_address_ID_EX,
    alu_output,
    datamem_wr_data,
    data_format_ID_EX,
    datamem_read_enable_ID_EX,
    datamem_write_enable_ID_EX,
    writeback_mux_sel_ID_EX,
    regfile_write_enable_ID_EX,
    regfile_write_address_ID_EX,
    valid_ID_EX,
    custom_ctl_ID_EX,

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
    custom_ctl_EX_MEM
);

input clk, reset;
input stall;    // hold the instruction in MEM (an older-stage stall, not used before Task 9)
input bubble;   // load a NOP: the instruction in EX is not ready to leave (divider busy)

input [31:0] Instruction_address_ID_EX;
input [31:0] alu_output;
input [31:0] datamem_wr_data;
input [2:0] data_format_ID_EX;
input datamem_read_enable_ID_EX;
input datamem_write_enable_ID_EX;
input [1:0] writeback_mux_sel_ID_EX;
input regfile_write_enable_ID_EX;
input [4:0] regfile_write_address_ID_EX;
input valid_ID_EX;
input [4:0] custom_ctl_ID_EX;

output reg [31:0] Instruction_address_EX_MEM;
output reg [31:0] alu_out_EX_MEM;
output reg [31:0] datamem_wr_data_EX_MEM;
output reg [2:0] data_format_EX_MEM;
output reg datamem_read_enable_EX_MEM;
output reg datamem_write_enable_EX_MEM;
output reg [1:0] writeback_mux_sel_EX_MEM;
output reg regfile_write_enable_EX_MEM;
output reg [4:0] regfile_write_address_EX_MEM;
output reg valid_EX_MEM;
output reg [4:0] custom_ctl_EX_MEM;

always @(posedge clk) begin
    if (reset) begin
        Instruction_address_EX_MEM <= 32'b0;
        alu_out_EX_MEM             <= 32'b0;
        datamem_wr_data_EX_MEM     <= 32'b0;
        data_format_EX_MEM         <= 3'b010;
        datamem_read_enable_EX_MEM <= 1'b0;
        datamem_write_enable_EX_MEM <= 1'b0;
        writeback_mux_sel_EX_MEM   <= 2'b00;
        regfile_write_enable_EX_MEM <= 1'b0;
        regfile_write_address_EX_MEM <= 5'b0;
        valid_EX_MEM               <= 1'b0;
        custom_ctl_EX_MEM          <= 5'b00000;
    end
    else if (stall) begin
        // hold
    end
    else if (bubble) begin
        Instruction_address_EX_MEM <= 32'b0;
        alu_out_EX_MEM             <= 32'b0;
        datamem_wr_data_EX_MEM     <= 32'b0;
        data_format_EX_MEM         <= 3'b010;
        datamem_read_enable_EX_MEM <= 1'b0;
        datamem_write_enable_EX_MEM <= 1'b0;
        writeback_mux_sel_EX_MEM   <= 2'b00;
        regfile_write_enable_EX_MEM <= 1'b0;
        regfile_write_address_EX_MEM <= 5'b0;
        valid_EX_MEM               <= 1'b0;
        custom_ctl_EX_MEM          <= 5'b00000;
    end
    else begin
        Instruction_address_EX_MEM <= Instruction_address_ID_EX;
        alu_out_EX_MEM             <= alu_output;
        datamem_wr_data_EX_MEM     <= datamem_wr_data;
        data_format_EX_MEM         <= data_format_ID_EX;
        datamem_read_enable_EX_MEM <= datamem_read_enable_ID_EX;
        datamem_write_enable_EX_MEM <= datamem_write_enable_ID_EX;
        writeback_mux_sel_EX_MEM   <= writeback_mux_sel_ID_EX;
        regfile_write_enable_EX_MEM <= regfile_write_enable_ID_EX;
        regfile_write_address_EX_MEM <= regfile_write_address_ID_EX;
        valid_EX_MEM               <= valid_ID_EX;
        custom_ctl_EX_MEM          <= custom_ctl_ID_EX;
    end
end

endmodule
