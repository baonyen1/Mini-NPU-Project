`timescale 1ns / 1ps

module Forwarding_Mux(
    select,
    regfile_data,
    alu_out_EX_MEM,
    alu_out_MEM_WB,
    datamem_out_MEM_WB,
    return_address_EX_MEM,
    return_address_MEM_WB,
    forwarded_data
);

input [2:0] select;
input [31:0] regfile_data;
input [31:0] alu_out_EX_MEM;
input [31:0] alu_out_MEM_WB;
input [31:0] datamem_out_MEM_WB;
input [31:0] return_address_EX_MEM;
input [31:0] return_address_MEM_WB;

output reg [31:0] forwarded_data;

localparam FW_REGFILE    = 3'b000;
localparam FW_EX_ALU     = 3'b001;
localparam FW_WB_ALU     = 3'b010;
localparam FW_WB_MEMDATA = 3'b011;
localparam FW_EX_RETURN  = 3'b100;
localparam FW_WB_RETURN  = 3'b101;

always @(*) begin
    case (select)
        FW_REGFILE:    forwarded_data = regfile_data;
        FW_EX_ALU:     forwarded_data = alu_out_EX_MEM;
        FW_WB_ALU:     forwarded_data = alu_out_MEM_WB;
        FW_WB_MEMDATA: forwarded_data = datamem_out_MEM_WB;
        FW_EX_RETURN:  forwarded_data = return_address_EX_MEM;
        FW_WB_RETURN:  forwarded_data = return_address_MEM_WB;
        default:       forwarded_data = regfile_data;
    endcase
end

endmodule
