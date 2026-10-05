`timescale 1ns / 1ps

module LSU(
    clk,
    reset,
    read_enable,
    write_enable,
    data_format,
    address,
    write_data,
    read_data
);

input clk, reset;
input read_enable, write_enable;
input [2:0] data_format;
input [9:0] address;
input [31:0] write_data;

output [31:0] read_data;

Data_Memory DATA_MEMORY(
    .clk(clk),
    .reset(reset),
    .read_enable(read_enable),
    .write_enable(write_enable),
    .data_format(data_format),
    .address(address),
    .write_data(write_data),
    .read_data(read_data)
);

endmodule
