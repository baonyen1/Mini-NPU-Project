`timescale 1ns / 1ps

module Data_Memory(
    clk,
    reset,
    cpu_en,
    read_enable,
    write_enable,
    data_format,
    address,
    write_data,
    read_data
);

input clk, reset, cpu_en;
input read_enable, write_enable;
input [2:0] data_format;
input [9:0] address;
input [31:0] write_data;

output reg [31:0] read_data;

integer i;
(* ram_style = "block" *) reg [31:0] memory [0:255];
reg [31:0] read_word;
reg [2:0] read_format_q;
reg [1:0] read_offset_q;

wire [7:0] word_addr;
wire [3:0] byte_write_enable;
wire [31:0] aligned_write_data;

assign word_addr = address[9:2];

assign byte_write_enable =
    (!write_enable) ? 4'b0000 :
    (data_format == 3'b000) ? (4'b0001 << address[1:0]) :
    (data_format == 3'b001) ? (address[1] ? 4'b1100 : 4'b0011) :
    (data_format == 3'b010) ? 4'b1111 :
    4'b0000;

assign aligned_write_data =
    (data_format == 3'b000) ? {4{write_data[7:0]}} :
    (data_format == 3'b001) ? {2{write_data[15:0]}} :
    write_data;

initial begin
    for (i = 0; i < 256; i = i + 1) begin
        memory[i] = 32'b0;
    end
end

always @(posedge clk) begin
    if (reset) begin
        read_word <= 32'b0;
        read_format_q <= 3'b010;
        read_offset_q <= 2'b00;
    end
    else if (cpu_en) begin
        if (byte_write_enable[0]) begin
            memory[word_addr][7:0] <= aligned_write_data[7:0];
        end
        if (byte_write_enable[1]) begin
            memory[word_addr][15:8] <= aligned_write_data[15:8];
        end
        if (byte_write_enable[2]) begin
            memory[word_addr][23:16] <= aligned_write_data[23:16];
        end
        if (byte_write_enable[3]) begin
            memory[word_addr][31:24] <= aligned_write_data[31:24];
        end

        if (read_enable) begin
            read_word <= memory[word_addr];
            read_format_q <= data_format;
            read_offset_q <= address[1:0];
        end
    end
end

always @(*) begin
    case (read_format_q)
        3'b000: begin // LB
            case (read_offset_q)
                2'b00: read_data = {{24{read_word[7]}}, read_word[7:0]};
                2'b01: read_data = {{24{read_word[15]}}, read_word[15:8]};
                2'b10: read_data = {{24{read_word[23]}}, read_word[23:16]};
                default: read_data = {{24{read_word[31]}}, read_word[31:24]};
            endcase
        end

        3'b001: begin // LH
            if (read_offset_q[1] == 1'b0)
                read_data = {{16{read_word[15]}}, read_word[15:0]};
            else
                read_data = {{16{read_word[31]}}, read_word[31:16]};
        end

        3'b010: read_data = read_word; // LW

        3'b100: begin // LBU
            case (read_offset_q)
                2'b00: read_data = {24'b0, read_word[7:0]};
                2'b01: read_data = {24'b0, read_word[15:8]};
                2'b10: read_data = {24'b0, read_word[23:16]};
                default: read_data = {24'b0, read_word[31:24]};
            endcase
        end

        3'b101: begin // LHU
            if (read_offset_q[1] == 1'b0)
                read_data = {16'b0, read_word[15:0]};
            else
                read_data = {16'b0, read_word[31:16]};
        end

        default: read_data = 32'b0;
    endcase
end

endmodule
