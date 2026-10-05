`timescale 1ns / 1ps

module WriteBack_Mux(
    writeback_mux_sel_MEM_WB,
    alu_out_MEM_WB,
    datamem_out_MEM_WB,
    pc_plus4_MEM_WB,
    regfile_write_data
);

input [1:0] writeback_mux_sel_MEM_WB;
input [31:0] alu_out_MEM_WB;
input [31:0] datamem_out_MEM_WB;
input [31:0] pc_plus4_MEM_WB;

output reg [31:0] regfile_write_data;

always @(*) begin
    case (writeback_mux_sel_MEM_WB)
        2'b00: regfile_write_data = alu_out_MEM_WB;
        2'b01: regfile_write_data = datamem_out_MEM_WB;
        2'b10: regfile_write_data = pc_plus4_MEM_WB;
        default: regfile_write_data = alu_out_MEM_WB;
    endcase
end

endmodule
