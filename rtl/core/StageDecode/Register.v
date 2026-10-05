`timescale 1ns / 1ps

module Register_File(clk, reset, Rs1, Rs2, Rd, write_data, read_data1, read_data2, reg_write);

input clk, reset, reg_write;
input [4:0] Rs1, Rs2, Rd;
input [31:0] write_data;

output [31:0] read_data1, read_data2;

integer i;
reg [31:0] regs [0:31];

always @(posedge clk) begin
    if (reset) begin
        for (i = 0; i < 32; i = i + 1) begin
            regs[i] <= 32'b0;
        end
    end
    else if (reg_write && (Rd != 5'b00000)) begin
        regs[Rd] <= write_data;
    end
end

assign read_data1 = (Rs1 == 5'b00000) ? 32'b0 :
                    (reg_write && (Rd == Rs1) && (Rd != 5'b00000)) ? write_data :
                    regs[Rs1];

assign read_data2 = (Rs2 == 5'b00000) ? 32'b0 :
                    (reg_write && (Rd == Rs2) && (Rd != 5'b00000)) ? write_data :
                    regs[Rs2];

endmodule
