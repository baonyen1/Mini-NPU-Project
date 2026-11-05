`timescale 1ns / 1ps

// Behavioural DTCM port B for the mac_engine directed test (plan Task 11). Not RTL.
// Same layout as rtl/mem/dtcm_dp.sv: quad q = words 4q..4q+3, word 4q in bits [31:0], data valid the
// cycle after b_req (spec 7.1). Unlike dtcm_dp it does not hold the read data: in every cycle that does
// not follow a b_req, b_rdata is X, so an engine that samples port B at the wrong time reads X and the
// results mismatch (on a 4-state simulator; Verilator turns X into 0).
// The testbench writes the contents with write_word(), always together with npu_ref_mem_write().
module dtcm_model
  import npu_pkg::*;
(
    input  logic                    clk,
    input  logic                    b_req,
    input  logic [QUAD_ADDR_W-1:0]  b_addr,
    output logic [PORT_B_W-1:0]     b_rdata
);
    localparam int unsigned WORDS = DTCM_BYTES / 4;

    logic [31:0]         mem [WORDS];
    logic [PORT_B_W-1:0] rdata_q;
    logic                valid_q = 1'b0;
    int unsigned         n_reads = 0;               // port-B reads since the last clear()

    initial clear();

    task automatic clear();
        for (int w = 0; w < WORDS; w++) mem[w] = 32'd0;
        n_reads = 0;
    endtask

    task automatic write_word(input int unsigned word_idx, input logic [31:0] data);
        if (word_idx >= WORDS) $fatal(1, "dtcm_model.write_word: word %0d out of range", word_idx);
        mem[word_idx] = data;
    endtask

    always @(posedge clk) begin
        valid_q <= b_req;
        if (b_req) begin
            rdata_q <= {mem[4 * b_addr + 3], mem[4 * b_addr + 2], mem[4 * b_addr + 1], mem[4 * b_addr]};
            n_reads <= n_reads + 1;
        end
    end

    assign b_rdata = valid_q ? rdata_q : 'x;
endmodule
