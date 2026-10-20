`timescale 1ns / 1ps

// Instruction tightly-coupled memory: 16 KB at 0x0000_0000 (spec 4.1), combinational read.
// Backdoor load: +ITCM=<file> reads a hex file (one 32-bit word per line, word 0 first) with
// $readmemh before reset is released (decision D7). Every word not loaded is a NOP, and a
// fetch outside the ITCM returns a NOP too (decision W2-1 is still open).
module itcm #(
    parameter int WORDS = 4096                       // 16 KB
) (
    input  logic [31:2] addr,                        // word address of the instruction (the PC without bits 1:0)
    output logic [31:0] rdata
);
    localparam logic [31:0] NOP = 32'h0000_0013;     // addi x0, x0, 0

    logic [31:0] mem [0:WORDS-1];
    logic [8*256-1:0] hex_file;

    initial begin
        for (int i = 0; i < WORDS; i++) mem[i] = NOP;
        if ($value$plusargs("ITCM=%s", hex_file)) $readmemh(hex_file, mem);
    end

    logic in_range;
    assign in_range = (addr[31:14] == 18'd0);
    assign rdata    = in_range ? mem[addr[13:2]] : NOP;
endmodule
