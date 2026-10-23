`timescale 1ns / 1ps

// Directed self-checking test of dtcm_dp (plan Task 8, Track B). No UVM: this block is
// small enough to prove with plain SystemVerilog before it is used by mac_env and npu_top.
// Verdict lines: "RESULT: PASS" or a $fatal with the first mismatch.
//
// Tests (names follow the plan): dtcm_last_word, dtcm_port_b_quad, plus byte enables, latency,
// read-before-write, no aliasing over all 16384 words, concurrent ports, and the backdoor load
// (+DTCM=<file>; without the plusarg the memory must read as zero).
// Waived for this testbench only: loop counters and helper arguments are plain ints, the DUT ports
// are 12/14 bits wide, so truncation and unused upper bits are deliberate.
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off WIDTHTRUNC */
module dtcm_dp_tb;
    import npu_pkg::*;

    localparam int unsigned WORDS = DTCM_BYTES / 4;

    logic                     clk = 1'b0;
    logic                     a_re = 1'b0;
    logic [3:0]               a_we = 4'b0;
    logic [WORD_ADDR_W-1:0]   a_addr = '0;
    logic [31:0]              a_wdata = 32'b0;
    logic [31:0]              a_rdata;
    logic                     b_req = 1'b0;
    logic [QUAD_ADDR_W-1:0]   b_addr = '0;
    logic [PORT_B_W-1:0]      b_rdata;

    dtcm_dp dut (.*);

    initial forever #5 clk = ~clk;

    int checks = 0;

    task automatic expect32(input string what, input logic [31:0] got, input logic [31:0] want);
        checks++;
        if (got !== want) $fatal(1, "FAIL %s: got %08x, expected %08x", what, got, want);
    endtask

    task automatic expect128(input string what, input logic [127:0] got, input logic [127:0] want);
        checks++;
        if (got !== want) $fatal(1, "FAIL %s: got %032x, expected %032x", what, got, want);
    endtask

    // All tasks drive just after a rising edge and sample just after the next one, so the data
    // seen is what the memory registered at that edge (1-cycle read latency).
    task automatic a_write(input int unsigned w, input logic [31:0] d, input logic [3:0] be = 4'hF);
        a_addr = w[WORD_ADDR_W-1:0]; a_wdata = d; a_we = be; a_re = 1'b0;
        @(posedge clk); #1;
        a_we = 4'b0;
    endtask

    task automatic a_read(input int unsigned w, output logic [31:0] d);
        a_addr = w[WORD_ADDR_W-1:0]; a_re = 1'b1;
        @(posedge clk); #1;
        a_re = 1'b0;
        d = a_rdata;
    endtask

    task automatic b_read(input int unsigned q, output logic [127:0] d);
        b_addr = q[QUAD_ADDR_W-1:0]; b_req = 1'b1;
        @(posedge clk); #1;
        b_req = 1'b0;
        d = b_rdata;
    endtask

    function automatic logic [31:0] pattern(input int unsigned w);
        return {w[15:0], ~w[15:0]} ^ 32'hA5C3_0F3C;      // unique per word index (w < 65536)
    endfunction

    logic [31:0]  r32;
    logic [127:0] r128, q0_before;

    initial begin
        // ---- zero-init, or the backdoor file ---------------------------------------------
        @(posedge clk); #1;
        if ($test$plusargs("DTCM")) begin
            // the Makefile writes: words 0..39 = 0x1000_0000 + w, word 16383 = 0xCAFE_F00D, rest 0
            for (int w = 0; w < 40; w++) begin
                a_read(w, r32);
                expect32($sformatf("backdoor word %0d via A", w), r32, 32'h1000_0000 + w);
                expect32($sformatf("backdoor word %0d via peek", w), dut.peek(w), 32'h1000_0000 + w);
            end
            a_read(WORDS - 1, r32);
            expect32("backdoor last word via A", r32, 32'hCAFE_F00D);
            b_read(1, r128);                         // quad 1 = words 4..7
            expect128("backdoor quad 1 via B", r128,
                      {32'h1000_0007, 32'h1000_0006, 32'h1000_0005, 32'h1000_0004});
            b_read(DTCM_QUADS - 1, r128);            // last quad = words 16380..16383
            expect128("backdoor last quad via B", r128, {32'hCAFE_F00D, 96'b0});
            a_read(40, r32);
            expect32("backdoor: first unloaded word is zero", r32, 32'b0);
        end else begin
            for (int w = 0; w < WORDS; w += 997) begin
                a_read(w, r32);
                expect32($sformatf("zero-init word %0d", w), r32, 32'b0);
            end
            b_read(0, r128);   expect128("zero-init quad 0", r128, 128'b0);
            b_read(DTCM_QUADS - 1, r128);
            expect128("zero-init last quad", r128, 128'b0);
        end

        // ---- dtcm_last_word: store and load at 0x0001_FFFC ---------------------------------
        a_write(WORDS - 1, 32'hDEAD_BEEF);
        a_read(WORDS - 1, r32);
        expect32("dtcm_last_word", r32, 32'hDEAD_BEEF);
        a_write(0, 32'h0BAD_F00D);
        a_read(0, r32);        expect32("word 0", r32, 32'h0BAD_F00D);
        a_read(WORDS - 1, r32);expect32("last word untouched by word 0", r32, 32'hDEAD_BEEF);

        // ---- dtcm_port_b_quad: stores to 0x0001_0010..0x0001_001C, read quad 1 on port B ----
        b_read(0, q0_before);                              // quad 0, whatever the backdoor loaded
        for (int i = 0; i < 4; i++) a_write(4 + i, 32'h1111_1111 * (i + 1));
        b_read(1, r128);
        expect128("dtcm_port_b_quad", r128,
                  {32'h4444_4444, 32'h3333_3333, 32'h2222_2222, 32'h1111_1111});   // bank 0 in [31:0]
        b_read(0, r128);
        expect128("quad 0 not disturbed by quad 1 stores", r128, q0_before);

        // ---- byte enables: every mask, each lane merged into the old word -------------------
        for (int be = 0; be < 16; be++) begin
            logic [31:0] old_w, new_w, want;
            old_w = 32'hA1B2_C3D4; new_w = 32'h0516_2738;
            a_write(100 + be, old_w);
            a_write(100 + be, new_w, be[3:0]);
            for (int b = 0; b < 4; b++) want[8*b +: 8] = be[b] ? new_w[8*b +: 8] : old_w[8*b +: 8];
            a_read(100 + be, r32);
            expect32($sformatf("byte enable %04b", be[3:0]), r32, want);
        end

        // ---- latency and hold ---------------------------------------------------------------
        a_write(200, 32'hAAAA_0001);
        a_write(201, 32'hAAAA_0002);
        a_read(201, r32);                                  // a_rdata now holds ...0002
        a_addr = 200; a_re = 1'b1;
        #1 expect32("port A: new data not visible in the request cycle", a_rdata, 32'hAAAA_0002);
        @(posedge clk); #1;
        expect32("port A: data one cycle after the request", a_rdata, 32'hAAAA_0001);
        a_re = 1'b0; a_addr = 201;
        @(posedge clk); #1;
        expect32("port A: rdata holds while a_re is low", a_rdata, 32'hAAAA_0001);

        b_read(0, r128);                                   // b_rdata now holds quad 0
        b_addr = 50; b_req = 1'b1;                         // quad 50 = words 200..203
        #1 expect128("port B: new data not visible in the request cycle", b_rdata, r128);
        @(posedge clk); #1;
        expect128("port B: data one cycle after the request", b_rdata,
                  {32'b0, 32'b0, 32'hAAAA_0002, 32'hAAAA_0001});
        b_req = 1'b0; b_addr = 0;
        @(posedge clk); #1;
        expect128("port B: rdata holds while b_req is low", b_rdata,
                  {32'b0, 32'b0, 32'hAAAA_0002, 32'hAAAA_0001});

        // ---- read-before-write: same word, same cycle, returns the old value ----------------
        a_write(300, 32'h0000_00AA);
        a_addr = 300; a_wdata = 32'h0000_00BB; a_we = 4'hF; a_re = 1'b1;
        @(posedge clk); #1;
        a_we = 4'b0; a_re = 1'b0;
        expect32("A read+write same cycle returns the old word", a_rdata, 32'h0000_00AA);
        a_read(300, r32);
        expect32("A write took effect", r32, 32'h0000_00BB);

        a_write(304, 32'h0000_00CC);                      // quad 76, word 0 of the quad
        a_addr = 304; a_wdata = 32'h0000_00DD; a_we = 4'hF; a_re = 1'b0;
        b_addr = 76; b_req = 1'b1;
        @(posedge clk); #1;
        a_we = 4'b0; b_req = 1'b0;
        expect128("B read concurrent with an A write returns the old quad", b_rdata, {96'b0, 32'h0000_00CC});
        b_read(76, r128);
        expect128("A write visible on B afterwards", r128, {96'b0, 32'h0000_00DD});

        // ---- ports used in the same cycle -----------------------------------------------------
        a_write(400, 32'hFEED_0400);
        a_write(2000, 32'hFEED_2000);                     // quad 500
        a_addr = 400; a_re = 1'b1; b_addr = 500; b_req = 1'b1;
        @(posedge clk); #1;
        a_re = 1'b0; b_req = 1'b0;
        expect32("concurrent: port A result", a_rdata, 32'hFEED_0400);
        expect128("concurrent: port B result", b_rdata, {96'b0, 32'hFEED_2000});

        // ---- no aliasing: unique value in every word, read back through both ports -----------
        for (int w = 0; w < WORDS; w++) a_write(w, pattern(w));
        for (int w = 0; w < WORDS; w++) begin
            a_read(w, r32);
            if (r32 !== pattern(w)) expect32($sformatf("alias check, word %0d via A", w), r32, pattern(w));
        end
        checks++;
        for (int q = 0; q < DTCM_QUADS; q++) begin
            b_read(q, r128);
            if (r128 !== {pattern(4*q + 3), pattern(4*q + 2), pattern(4*q + 1), pattern(4*q)})
                expect128($sformatf("alias check, quad %0d via B", q), r128,
                          {pattern(4*q + 3), pattern(4*q + 2), pattern(4*q + 1), pattern(4*q)});
        end
        checks++;
        for (int w = 0; w < WORDS; w += 311)
            expect32($sformatf("peek word %0d", w), dut.peek(w), pattern(w));

        $display("dtcm_dp_tb: %0d checks", checks);
        $display("RESULT: PASS");
        $finish;
    end

    // a stuck test must fail, not hang
    initial begin
        #(10 * 400000);
        $fatal(1, "FAIL timeout");
    end
endmodule
