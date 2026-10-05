`timescale 1ns / 1ps

module StageWriteBack_Top(
    Instruction_address_MEM_WB,
    alu_out_MEM_WB,
    datamem_out_MEM_WB,
    writeback_mux_sel_MEM_WB,
    regfile_write_enable_MEM_WB,
    regfile_write_address_MEM_WB,

    regfile_write_data,
    regfile_write_enable_WB,
    regfile_write_address_WB
);

input [31:0] Instruction_address_MEM_WB;
input [31:0] alu_out_MEM_WB;
input [31:0] datamem_out_MEM_WB;
input [1:0] writeback_mux_sel_MEM_WB;
input regfile_write_enable_MEM_WB;
input [4:0] regfile_write_address_MEM_WB;

output [31:0] regfile_write_data;
output regfile_write_enable_WB;
output [4:0] regfile_write_address_WB;

wire [31:0] return_address;

Address_Adder WB_RETURN_ADDRESS(
    .instruction_address_MEM_WB(Instruction_address_MEM_WB),
    .return_address(return_address)
);

assign regfile_write_enable_WB = regfile_write_enable_MEM_WB;
assign regfile_write_address_WB = regfile_write_address_MEM_WB;

WriteBack_Mux WB_MUX(
    .writeback_mux_sel_MEM_WB(writeback_mux_sel_MEM_WB),
    .alu_out_MEM_WB(alu_out_MEM_WB),
    .datamem_out_MEM_WB(datamem_out_MEM_WB),
    .pc_plus4_MEM_WB(return_address),
    .regfile_write_data(regfile_write_data)
);

endmodule
