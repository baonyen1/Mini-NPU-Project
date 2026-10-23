`timescale 1ns / 1ps

// Data tightly-coupled memory, dual port (spec 4.1, plan Task 8): 64 KB at 0x0001_0000,
// organised as 4 banks x 32 bit. Word address w (a 14-bit index inside the DTCM) lives in
// bank w[1:0] at row w[13:2]. A 128-bit "quad" is the four words of one row, one from each bank.
//
//   port A  core LSU      32-bit read/write, byte enables, 1-cycle read latency
//   port B  MAC engine    128-bit read-only (spec 7.1), 1-cycle read latency:
//                         b_rdata = {bank3[b_addr], bank2[b_addr], bank1[b_addr], bank0[b_addr]}
//                         (bank 0 in bits [31:0]), valid the cycle after b_req
//
// Read-before-write: a read and a write to the same word in the same cycle return the OLD word,
// on either port. Software never relies on it (WAR rule, spec 6.3 rule 5, assertion A-SOC-1).
// The read data registers hold their value while re / b_req is low.
//
// Backdoor load (decision D7): +DTCM=<file> reads one 32-bit hex word per line, word 0 first,
// with $readmemh before reset is released. Every word not loaded is 0. Address decode (is this
// access for the DTCM at all) is the job of the SoC top, so a_addr and b_addr cannot go out of range.
module dtcm_dp
  import npu_pkg::*;
(
    input  logic                       clk,

    // port A: core LSU
    input  logic                       a_re,
    input  logic [3:0]                 a_we,
    input  logic [WORD_ADDR_W-1:0]     a_addr,    // word index within the DTCM
    input  logic [31:0]                a_wdata,
    output logic [31:0]                a_rdata,

    // port B: engine, read-only (spec 7.1)
    input  logic                       b_req,
    input  logic [QUAD_ADDR_W-1:0]     b_addr,    // quad index within the DTCM
    output logic [PORT_B_W-1:0]        b_rdata
);
    localparam int unsigned WORDS = DTCM_BYTES / 4;     // 16384
    localparam int unsigned BANKS = 4;

    // One array per bank, so a quad is one row of all four (and maps to four RAMs).
    logic [31:0] bank0 [0:DTCM_QUADS-1];
    logic [31:0] bank1 [0:DTCM_QUADS-1];
    logic [31:0] bank2 [0:DTCM_QUADS-1];
    logic [31:0] bank3 [0:DTCM_QUADS-1];

    logic [31:0] a_rdata_q = 32'b0;
    logic [PORT_B_W-1:0] b_rdata_q = '0;
    assign a_rdata = a_rdata_q;
    assign b_rdata = b_rdata_q;

    wire [QUAD_ADDR_W-1:0] a_row  = a_addr[WORD_ADDR_W-1:2];
    wire [1:0]             a_bank = a_addr[1:0];

    // ---- backdoor load ----------------------------------------------------------------------
    logic [31:0]      load_buf [0:WORDS-1];
    logic [8*256-1:0] hex_file;

    initial begin
        for (int w = 0; w < WORDS; w++) load_buf[w] = 32'b0;
        if ($value$plusargs("DTCM=%s", hex_file)) $readmemh(hex_file, load_buf);
        for (int r = 0; r < DTCM_QUADS; r++) begin
            bank0[r] = load_buf[BANKS * r + 0];
            bank1[r] = load_buf[BANKS * r + 1];
            bank2[r] = load_buf[BANKS * r + 2];
            bank3[r] = load_buf[BANKS * r + 3];
        end
    end

    // ---- port A write (plain `always`: the banks are also written by the initial block above,
    //      which IEEE 1800 section 9.2.2.4 does not allow for an always_ff variable) ------------
    always @(posedge clk) begin
        for (int b = 0; b < 4; b++) begin
            if (a_we[b]) begin
                case (a_bank)
                    2'd0: bank0[a_row][8*b +: 8] <= a_wdata[8*b +: 8];
                    2'd1: bank1[a_row][8*b +: 8] <= a_wdata[8*b +: 8];
                    2'd2: bank2[a_row][8*b +: 8] <= a_wdata[8*b +: 8];
                    default: bank3[a_row][8*b +: 8] <= a_wdata[8*b +: 8];
                endcase
            end
        end
    end

    // ---- reads: registered, so the data appears one cycle after the request ------------------
    always_ff @(posedge clk) begin
        if (a_re) begin
            case (a_bank)
                2'd0:    a_rdata_q <= bank0[a_row];
                2'd1:    a_rdata_q <= bank1[a_row];
                2'd2:    a_rdata_q <= bank2[a_row];
                default: a_rdata_q <= bank3[a_row];
            endcase
        end
    end

    always_ff @(posedge clk) begin
        if (b_req) b_rdata_q <= {bank3[b_addr], bank2[b_addr], bank1[b_addr], bank0[b_addr]};
    end

    // ---- simulation backdoor read (hierarchical call from testbenches and the harness) ------
    function automatic logic [31:0] peek(input logic [WORD_ADDR_W-1:0] word_idx);
        case (word_idx[1:0])
            2'd0:    return bank0[word_idx[WORD_ADDR_W-1:2]];
            2'd1:    return bank1[word_idx[WORD_ADDR_W-1:2]];
            2'd2:    return bank2[word_idx[WORD_ADDR_W-1:2]];
            default: return bank3[word_idx[WORD_ADDR_W-1:2]];
        endcase
    endfunction
endmodule
