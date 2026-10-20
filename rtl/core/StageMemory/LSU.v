`timescale 1ns / 1ps

// Load/store unit of the core (plan Task 8). The data memory is outside the core: the LSU
// drives the data bus (dmem_*) and formats what comes back, so the byte-lane handling stays
// in the core as the spec asks.
//   Stores: sb replicates the byte, sh the half-word, sw drives the word; dmem_we carries the
//           byte enables of the lane addressed. A half-word store ignores address bit 0 and a
//           word store ignores address bits 1:0 (misaligned accesses are not detected, W2-1).
//   Loads : dmem_re requests a whole word; the memory answers one cycle later on dmem_rdata
//           and the LSU picks and extends the lane with the format and offset that were
//           registered together with the request.
module LSU(
    clk,
    reset,
    read_enable,
    write_enable,
    data_format,
    address,
    write_data,
    read_data,

    dmem_re,
    dmem_we,
    dmem_addr,
    dmem_wdata,
    dmem_rdata
);

input clk, reset;
input read_enable, write_enable;
input [2:0] data_format;
input [31:0] address;
input [31:0] write_data;

output reg [31:0] read_data;

output dmem_re;
output [3:0] dmem_we;
output [31:0] dmem_addr;
output [31:0] dmem_wdata;
input [31:0] dmem_rdata;

reg [2:0] read_format_q;
reg [1:0] read_offset_q;

assign dmem_re   = read_enable;
assign dmem_addr = address;

assign dmem_we =
    (!write_enable) ? 4'b0000 :
    (data_format == 3'b000) ? (4'b0001 << address[1:0]) :
    (data_format == 3'b001) ? (address[1] ? 4'b1100 : 4'b0011) :
    (data_format == 3'b010) ? 4'b1111 :
    4'b0000;

assign dmem_wdata =
    (data_format == 3'b000) ? {4{write_data[7:0]}} :
    (data_format == 3'b001) ? {2{write_data[15:0]}} :
    write_data;

always @(posedge clk) begin
    if (reset) begin
        read_format_q <= 3'b010;
        read_offset_q <= 2'b00;
    end
    else if (read_enable) begin
        read_format_q <= data_format;
        read_offset_q <= address[1:0];
    end
end

always @(*) begin
    case (read_format_q)
        3'b000: begin // LB
            case (read_offset_q)
                2'b00: read_data = {{24{dmem_rdata[7]}}, dmem_rdata[7:0]};
                2'b01: read_data = {{24{dmem_rdata[15]}}, dmem_rdata[15:8]};
                2'b10: read_data = {{24{dmem_rdata[23]}}, dmem_rdata[23:16]};
                default: read_data = {{24{dmem_rdata[31]}}, dmem_rdata[31:24]};
            endcase
        end

        3'b001: begin // LH
            if (read_offset_q[1] == 1'b0)
                read_data = {{16{dmem_rdata[15]}}, dmem_rdata[15:0]};
            else
                read_data = {{16{dmem_rdata[31]}}, dmem_rdata[31:16]};
        end

        3'b010: read_data = dmem_rdata; // LW

        3'b100: begin // LBU
            case (read_offset_q)
                2'b00: read_data = {24'b0, dmem_rdata[7:0]};
                2'b01: read_data = {24'b0, dmem_rdata[15:8]};
                2'b10: read_data = {24'b0, dmem_rdata[23:16]};
                default: read_data = {24'b0, dmem_rdata[31:24]};
            endcase
        end

        3'b101: begin // LHU
            if (read_offset_q[1] == 1'b0)
                read_data = {16'b0, dmem_rdata[15:0]};
            else
                read_data = {16'b0, dmem_rdata[31:16]};
        end

        default: read_data = 32'b0;
    endcase
end

endmodule
