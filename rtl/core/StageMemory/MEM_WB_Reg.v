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
    rr_EX_MEM,
    rd_data,
    bubble,
    insn_EX_MEM,
    mem_addr_EX_MEM,
    mem_wdata_EX_MEM,
    mem_wmask_EX_MEM,

    Instruction_address_MEM_WB,
    alu_out_MEM_WB,
    writeback_mux_sel_MEM_WB,
    regfile_write_enable_MEM_WB,
    regfile_write_address_MEM_WB,
    valid_MEM_WB,
    rr_MEM_WB,
    rd_data_MEM_WB,
    insn_MEM_WB,
    mem_addr_MEM_WB,
    mem_wdata_MEM_WB,
    mem_wmask_MEM_WB
);

input clk, reset;

input [31:0] Instruction_address_EX_MEM;
input [31:0] alu_out_EX_MEM;
input [1:0] writeback_mux_sel_EX_MEM;
input regfile_write_enable_EX_MEM;
input [4:0] regfile_write_address_EX_MEM;
input valid_EX_MEM;
input rr_EX_MEM;          // the instruction is a READ_RESULT whose data is rd_data
input [31:0] rd_data;
input bubble;             // the MEM stage is waiting: load a NOP
input [31:0] insn_EX_MEM;       // the fields below only feed the RVVI retire trace
input [31:0] mem_addr_EX_MEM;
input [31:0] mem_wdata_EX_MEM;
input [3:0] mem_wmask_EX_MEM;

output reg [31:0] Instruction_address_MEM_WB;
output reg [31:0] alu_out_MEM_WB;
output reg [1:0] writeback_mux_sel_MEM_WB;
output reg regfile_write_enable_MEM_WB;
output reg [4:0] regfile_write_address_MEM_WB;
output reg valid_MEM_WB;
output reg rr_MEM_WB;
output reg [31:0] rd_data_MEM_WB;
output reg [31:0] insn_MEM_WB;
output reg [31:0] mem_addr_MEM_WB;
output reg [31:0] mem_wdata_MEM_WB;
output reg [3:0] mem_wmask_MEM_WB;

always @(posedge clk) begin
    if (reset) begin
        Instruction_address_MEM_WB <= 32'b0;
        alu_out_MEM_WB             <= 32'b0;
        writeback_mux_sel_MEM_WB   <= 2'b00;
        regfile_write_enable_MEM_WB <= 1'b0;
        regfile_write_address_MEM_WB <= 5'b0;
        valid_MEM_WB               <= 1'b0;
        rr_MEM_WB                  <= 1'b0;
        rd_data_MEM_WB             <= 32'b0;
        insn_MEM_WB                <= 32'h00000013;
        mem_addr_MEM_WB            <= 32'b0;
        mem_wdata_MEM_WB           <= 32'b0;
        mem_wmask_MEM_WB           <= 4'b0;
    end
    else if (bubble) begin
        Instruction_address_MEM_WB <= 32'b0;
        alu_out_MEM_WB             <= 32'b0;
        writeback_mux_sel_MEM_WB   <= 2'b00;
        regfile_write_enable_MEM_WB <= 1'b0;
        regfile_write_address_MEM_WB <= 5'b0;
        valid_MEM_WB               <= 1'b0;
        rr_MEM_WB                  <= 1'b0;
        rd_data_MEM_WB             <= 32'b0;
        insn_MEM_WB                <= 32'h00000013;
        mem_addr_MEM_WB            <= 32'b0;
        mem_wdata_MEM_WB           <= 32'b0;
        mem_wmask_MEM_WB           <= 4'b0;
    end
    else begin
        Instruction_address_MEM_WB <= Instruction_address_EX_MEM;
        alu_out_MEM_WB             <= alu_out_EX_MEM;
        writeback_mux_sel_MEM_WB   <= writeback_mux_sel_EX_MEM;
        regfile_write_enable_MEM_WB <= regfile_write_enable_EX_MEM;
        regfile_write_address_MEM_WB <= regfile_write_address_EX_MEM;
        valid_MEM_WB               <= valid_EX_MEM;
        rr_MEM_WB                  <= rr_EX_MEM;
        rd_data_MEM_WB             <= rd_data;
        insn_MEM_WB                <= insn_EX_MEM;
        mem_addr_MEM_WB            <= mem_addr_EX_MEM;
        mem_wdata_MEM_WB           <= mem_wdata_EX_MEM;
        mem_wmask_MEM_WB           <= mem_wmask_EX_MEM;
    end
end

endmodule
