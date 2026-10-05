`timescale 1ns / 1ps

module Forwarding_Unit(
    regfile_read_address_0_ID_EX,
    regfile_read_address_1_ID_EX,

    regfile_write_address_EX_MEM,
    regfile_write_enable_EX_MEM,
    writeback_mux_sel_EX_MEM,

    regfile_write_address_MEM_WB,
    regfile_write_enable_MEM_WB,
    writeback_mux_sel_MEM_WB,

    fw_mux_0_sel,
    fw_mux_1_sel
);

input [4:0] regfile_read_address_0_ID_EX;
input [4:0] regfile_read_address_1_ID_EX;

input [4:0] regfile_write_address_EX_MEM;
input regfile_write_enable_EX_MEM;
input [1:0] writeback_mux_sel_EX_MEM;

input [4:0] regfile_write_address_MEM_WB;
input regfile_write_enable_MEM_WB;
input [1:0] writeback_mux_sel_MEM_WB;

output reg [2:0] fw_mux_0_sel;
output reg [2:0] fw_mux_1_sel;

localparam FW_REGFILE    = 3'b000;
localparam FW_EX_ALU     = 3'b001;
localparam FW_WB_ALU     = 3'b010;
localparam FW_WB_MEMDATA = 3'b011;
localparam FW_EX_RETURN  = 3'b100;
localparam FW_WB_RETURN  = 3'b101;

function [2:0] select_ex_mem_source;
    input [1:0] wb_sel;
    begin
        case (wb_sel)
            2'b10: select_ex_mem_source = FW_EX_RETURN;
            default: select_ex_mem_source = FW_EX_ALU;
        endcase
    end
endfunction

function [2:0] select_mem_wb_source;
    input [1:0] wb_sel;
    begin
        case (wb_sel)
            2'b01: select_mem_wb_source = FW_WB_MEMDATA;
            2'b10: select_mem_wb_source = FW_WB_RETURN;
            default: select_mem_wb_source = FW_WB_ALU;
        endcase
    end
endfunction

always @(*) begin
    fw_mux_0_sel = FW_REGFILE;
    fw_mux_1_sel = FW_REGFILE;

    // A synchronous load result is not available from EX/MEM. A load-use
    // dependency is stalled and is forwarded from MEM/WB on the next cycle.
    if (regfile_write_enable_EX_MEM &&
        (writeback_mux_sel_EX_MEM != 2'b01) &&
        (regfile_write_address_EX_MEM != 5'b00000) &&
        (regfile_write_address_EX_MEM == regfile_read_address_0_ID_EX)) begin
        fw_mux_0_sel = select_ex_mem_source(writeback_mux_sel_EX_MEM);
    end
    else if (regfile_write_enable_MEM_WB &&
        (regfile_write_address_MEM_WB != 5'b00000) &&
        (regfile_write_address_MEM_WB == regfile_read_address_0_ID_EX)) begin
        fw_mux_0_sel = select_mem_wb_source(writeback_mux_sel_MEM_WB);
    end

    if (regfile_write_enable_EX_MEM &&
        (writeback_mux_sel_EX_MEM != 2'b01) &&
        (regfile_write_address_EX_MEM != 5'b00000) &&
        (regfile_write_address_EX_MEM == regfile_read_address_1_ID_EX)) begin
        fw_mux_1_sel = select_ex_mem_source(writeback_mux_sel_EX_MEM);
    end
    else if (regfile_write_enable_MEM_WB &&
        (regfile_write_address_MEM_WB != 5'b00000) &&
        (regfile_write_address_MEM_WB == regfile_read_address_1_ID_EX)) begin
        fw_mux_1_sel = select_mem_wb_source(writeback_mux_sel_MEM_WB);
    end
end

endmodule
