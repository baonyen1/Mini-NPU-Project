`timescale 1ns / 1ps

module MEM_WB_Reg(
    clk,
    reset,

    Instruction_address_EX_MEM,
    alu_out_EX_MEM,
    writeback_mux_sel_EX_MEM,
    regfile_write_enable_EX_MEM,
    regfile_write_address_EX_MEM,
    valid_EX_MEM,

    Instruction_address_MEM_WB,
    alu_out_MEM_WB,
    writeback_mux_sel_MEM_WB,
    regfile_write_enable_MEM_WB,
    regfile_write_address_MEM_WB,
    valid_MEM_WB
);

input clk, reset;

input [31:0] Instruction_address_EX_MEM;
input [31:0] alu_out_EX_MEM;
input [1:0] writeback_mux_sel_EX_MEM;
input regfile_write_enable_EX_MEM;
input [4:0] regfile_write_address_EX_MEM;
input valid_EX_MEM;

output reg [31:0] Instruction_address_MEM_WB;
output reg [31:0] alu_out_MEM_WB;
output reg [1:0] writeback_mux_sel_MEM_WB;
output reg regfile_write_enable_MEM_WB;
output reg [4:0] regfile_write_address_MEM_WB;
output reg valid_MEM_WB;

always @(posedge clk) begin
    if (reset) begin
        Instruction_address_MEM_WB <= 32'b0;
        alu_out_MEM_WB             <= 32'b0;
        writeback_mux_sel_MEM_WB   <= 2'b00;
        regfile_write_enable_MEM_WB <= 1'b0;
        regfile_write_address_MEM_WB <= 5'b0;
        valid_MEM_WB               <= 1'b0;
    end
    else begin
        Instruction_address_MEM_WB <= Instruction_address_EX_MEM;
        alu_out_MEM_WB             <= alu_out_EX_MEM;
        writeback_mux_sel_MEM_WB   <= writeback_mux_sel_EX_MEM;
        regfile_write_enable_MEM_WB <= regfile_write_enable_EX_MEM;
        regfile_write_address_MEM_WB <= regfile_write_address_EX_MEM;
        valid_MEM_WB               <= valid_EX_MEM;
    end
end

endmodule
