`timescale 1ns / 1ps

module Hazard_Detection_Unit(
    datamem_read_enable_ID_EX,
    regfile_write_address_ID_EX,
    regfile_read_address_0_IF_ID,
    regfile_read_address_1_IF_ID,
    uses_rs1_IF_ID,
    uses_rs2_IF_ID,
    load_use_stall
);

input datamem_read_enable_ID_EX;
input [4:0] regfile_write_address_ID_EX;
input [4:0] regfile_read_address_0_IF_ID;
input [4:0] regfile_read_address_1_IF_ID;
input uses_rs1_IF_ID;
input uses_rs2_IF_ID;

output load_use_stall;

assign load_use_stall =
    datamem_read_enable_ID_EX &&
    (regfile_write_address_ID_EX != 5'b00000) &&
    ((uses_rs1_IF_ID && (regfile_write_address_ID_EX == regfile_read_address_0_IF_ID)) ||
     (uses_rs2_IF_ID && (regfile_write_address_ID_EX == regfile_read_address_1_IF_ID)));

endmodule
