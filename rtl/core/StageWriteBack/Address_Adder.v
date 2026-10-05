`timescale 1ns / 1ps

module Address_Adder(
    instruction_address_MEM_WB,
    return_address
);

input [31:0] instruction_address_MEM_WB;
output [31:0] return_address;

assign return_address = instruction_address_MEM_WB + 32'd4;

endmodule
