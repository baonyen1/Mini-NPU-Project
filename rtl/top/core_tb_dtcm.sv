`timescale 1ns / 1ps

// Stand-in for Track B's dtcm_dp, port A only (plan Task 8). It lets the core be tested before
// dtcm_dp exists and is replaced by an instance of dtcm_dp in core_tb_top once Track B delivers
// it. 64 KB as 16384 words, 32-bit read/write with byte enables, 1-cycle read latency
// (spec 4.1). Backdoor load: +DTCM=<file> with $readmemh.
module core_tb_dtcm #(
    parameter int WORDS = 16384
) (
    input  logic        clk,
    input  logic        re,
    input  logic [3:0]  we,
    input  logic [13:0] addr,            // word index within the DTCM
    input  logic [31:0] wdata,
    output logic [31:0] rdata
);
    logic [31:0] mem [0:WORDS-1];
    logic [8*256-1:0] hex_file;

    initial begin
        for (int i = 0; i < WORDS; i++) mem[i] = 32'b0;
        rdata = 32'b0;
        if ($value$plusargs("DTCM=%s", hex_file)) $readmemh(hex_file, mem);
    end

    // Plain `always`, not `always_ff`: `mem` and `rdata` are also written by the `initial` block above
    // (backdoor load), which IEEE 1800 section 9.2.2.4 does not allow for an always_ff variable.
    always @(posedge clk) begin
        for (int b = 0; b < 4; b++)
            if (we[b]) mem[addr][8*b +: 8] <= wdata[8*b +: 8];
        if (re) rdata <= mem[addr];      // a read in the cycle of a write returns the old word
    end
endmodule
