`timescale 1ns / 1ps

// Directed DPI testbench of mac_engine (plan Task 11, Step 1). No UVM.
//
// Every command the testbench pushes is mirrored into the golden model npu_ref (through npu_dpi_pkg)
// at the edge where the engine accepts it, so the model runs in program order. compare() waits until
// the engine has drained (rd_ready, the READ_RESULT condition), then checks npu_status and all 16
// READ_RESULT values against the model. Many tests also check hand-computed values, so a bug the
// model shares with the RTL is still caught. DTCM contents go to dtcm_model and to npu_ref together,
// and only while the engine is drained (the WAR rule, spec 6.3 rule 5).
//
// Mismatches are counted per test in three classes, so a stage of the build can be judged before the
// later stages exist: status (npu_status, csr_rdata), value (READ_RESULT data) and other (handshake,
// timing, X on an output, a hang). The run ends with one line per test, then "RESULT: PASS" or
// "RESULT: FAIL" and a $fatal.
//
//   +TEST=<name>   run only that test (default: all, in the order of TESTS below)
//
// Conventions: inputs change 1 ns after a rising edge (tick()); combinational outputs are read 1 ns
// after the inputs they depend on change. The engine samples at the next rising edge.
// Waived for this testbench only: helper arguments are plain ints narrowed to port widths (WIDTH*),
// some DUT outputs are only read in some tests (UNUSEDSIGNAL), and the negedge monitors count
// mismatches with blocking updates of testbench variables, which is not sequential logic (BLKSEQ).
/* verilator lint_off UNUSEDSIGNAL */
/* verilator lint_off WIDTHTRUNC */
/* verilator lint_off WIDTHEXPAND */
/* verilator lint_off BLKSEQ */
module mac_engine_tb;
    import npu_pkg::*;
    import npu_dpi_pkg::*;

    // ---- DUT and port-B memory -----------------------------------------------------------------
    logic                    clk = 1'b0;
    logic                    rst_n = 1'b0;
    logic                    cmd_valid = 1'b0;
    logic                    cmd_ready;
    logic [1:0]              cmd_op = 2'd0;
    logic [31:0]             cmd_addr = 32'd0;
    logic [31:0]             cmd_k = 32'd0;
    logic                    cmd_clr = 1'b0;
    logic                    rd_req = 1'b0;
    logic [RD_IDX_W-1:0]     rd_idx = '0;
    logic                    rd_ready;
    logic [31:0]             rd_data;
    logic                    csr_we = 1'b0;
    logic [11:0]             csr_addr = CSR_NPU_STATUS;
    logic [31:0]             csr_wdata = 32'd0;
    logic [31:0]             csr_rdata;
    logic                    b_req;
    logic [QUAD_ADDR_W-1:0]  b_addr;
    logic [PORT_B_W-1:0]     b_rdata;

    mac_engine dut (.*);

    dtcm_model u_dtcm (
        .clk     (clk),
        .b_req   (b_req),
        .b_addr  (b_addr),
        .b_rdata (b_rdata)
    );

    initial forever #5 clk = ~clk;

    // ---- constants -----------------------------------------------------------------------------
    localparam logic [31:0] W0    = 32'h0001_0000;     // hand case, as in Task 10 test_npu_ref.c
    localparam logic [31:0] I0    = 32'h0001_0010;
    localparam logic [31:0] BIG_W = 32'h0001_0000;     // K = KMAX operands, 4 KB each
    localparam logic [31:0] BIG_I = 32'h0001_1000;
    localparam int          DRAIN_LIMIT = 20000;       // cycles; the longest drain here is 10 x K=1024
    localparam logic [31:0] ERR_K_B   = 32'd1 << ST_ERR_K;
    localparam logic [31:0] ERR_ADDR_B = 32'd1 << ST_ERR_ADDR;
    localparam logic [31:0] ERR_ILL_B = 32'd1 << ST_ERR_ILLEGAL;
    localparam logic [31:0] ERR_ALN_B = 32'd1 << ST_ERR_ALIGN;

    // HAND[4*i + j] = dot(row i, image j) of the hand case (Task 10 hand_4x4_k4)
    int hand_acc [16] = '{10, 1, -1280, -4, -10, -1, 1280, 4, 127, 127, -16256, 254, -128, 0, 16384, 256};

    // ---- bookkeeping ---------------------------------------------------------------------------
    string cur = "(none)";
    int    n_status, n_value, n_other;                 // mismatches in the current test
    int    n_failed = 0;
    string results [$];
    int unsigned exp_reads = 0;                        // port-B reads expected so far (see load_quads)

    function automatic void report(input int kind, input string msg);
        string cls;
        case (kind)
            0:       begin n_status++; cls = "status"; end
            1:       begin n_value++;  cls = "value";  end
            default: begin n_other++;  cls = "other";  end
        endcase
        if (n_status + n_value + n_other <= 6) $display("  FAIL [%s] %s: %s", cur, cls, msg);
    endfunction

    task automatic tick();
        @(posedge clk);
        #1;
    endtask

    // ---- stimulus helpers ----------------------------------------------------------------------
    task automatic reset_all();
        cmd_valid = 1'b0;
        rd_req    = 1'b0;
        csr_we    = 1'b0;
        csr_addr  = CSR_NPU_STATUS;
        rst_n     = 1'b0;
        npu_ref_reset();
        u_dtcm.clear();
        exp_reads = 0;
        repeat (2) tick();
        rst_n = 1'b1;                                  // released just after an edge (npu_top synchronises it)
        tick();
    endtask

    task automatic mem_write(input logic [31:0] byte_addr, input logic [31:0] data);
        int unsigned w;
        w = (byte_addr - DTCM_BASE) >> 2;
        if (rd_ready !== 1'b1) report(2, "testbench wrote DTCM while the engine was busy (WAR rule)");
        u_dtcm.write_word(w, data);
        npu_ref_mem_write(w, data);
    endtask

    int last_push_wait;                                // cycles the last push() waited for cmd_ready

    // Port-B reads the engine must make: K/4 for a LOAD that passes every check, 0 for anything else.
    // Written here from spec 6.3 independently of the RTL and of npu_ref; compare() checks the count
    // that dtcm_model saw, so a LOAD that reads one quad too many or too few is caught. (exp_reads is
    // declared with the bookkeeping above.)

    function automatic int unsigned load_quads(input logic [1:0] op, input logic [31:0] addr, input logic [31:0] k);
        longint unsigned last_byte;
        if (op != OP_LDW && op != OP_LDI) return 0;
        if (k == 0 || k > KMAX || k[1:0] != 2'b00) return 0;
        if (addr[3:0] != 4'h0) return 0;
        last_byte = longint'(addr) + 4 * longint'(k);
        if (addr < DTCM_BASE || last_byte > longint'(DTCM_BASE) + DTCM_BYTES) return 0;
        return k / 4;
    endfunction

    // Present one command and hold it until the engine accepts it. Consecutive calls are back to back.
    task automatic push(input logic [1:0] op, input logic [31:0] addr, input logic [31:0] k, input logic clr);
        int waited;
        waited = 0;
        cmd_op = op; cmd_addr = addr; cmd_k = k; cmd_clr = clr; cmd_valid = 1'b1;
        while (cmd_ready !== 1'b1) begin
            tick();
            waited++;
            if (waited > DRAIN_LIMIT) begin
                report(2, "cmd_ready stuck at 0");
                cmd_valid = 1'b0;
                last_push_wait = waited;
                return;
            end
        end
        @(posedge clk);                                // accepted at this edge
        npu_ref_cmd(op, addr, k, clr);
        exp_reads += load_quads(op, addr, k);
        #1 cmd_valid = 1'b0;
        last_push_wait = waited;
    endtask

    task automatic drain();
        int n;
        n = 0;
        while (rd_ready !== 1'b1) begin
            tick();
            n++;
            if (n > DRAIN_LIMIT) begin
                report(2, "the engine never drained (rd_ready stuck at 0)");
                return;
            end
        end
    endtask

    task automatic csr_read(input logic [11:0] a, output logic [31:0] d);
        csr_addr = a;
        #1 d = csr_rdata;
    endtask

    // One CSR write. D21: csr_rdata in the cycle of the write must still show the old value.
    task automatic csr_write(input logic [11:0] a, input logic [31:0] d, input bit mirror = 1'b1);
        logic [31:0] rd_old, rd_during;
        csr_addr = a;
        #1 rd_old = csr_rdata;
        csr_wdata = d;
        csr_we    = 1'b1;
        #1 rd_during = csr_rdata;
        if (rd_during !== rd_old)
            report(0, $sformatf("D21: csr_rdata of 0x%03x changed in the cycle of the write: %08x -> %08x", a, rd_old, rd_during));
        @(posedge clk);
        if (mirror) npu_ref_csr_write(a, d);
        #1 csr_we = 1'b0;
    endtask

    task automatic compare(input string where);
        logic [31:0] st;
        drain();
        csr_read(CSR_NPU_STATUS, st);
        if (st !== npu_ref_status())
            report(0, $sformatf("%s: npu_status %08x, npu_ref %08x", where, st, npu_ref_status()));
        if (u_dtcm.n_reads !== exp_reads)
            report(2, $sformatf("%s: %0d port-B reads, expected %0d", where, u_dtcm.n_reads, exp_reads));
        for (int idx = 0; idx < 16; idx++) begin
            rd_idx = idx;
            rd_req = 1'b1;
            #1;
            if (rd_ready !== 1'b1) report(2, $sformatf("%s: rd_ready = %b while drained", where, rd_ready));
            if (rd_data !== npu_ref_read(idx))
                report(1, $sformatf("%s: acc[%0d] = %08x, npu_ref %08x", where, idx, rd_data, npu_ref_read(idx)));
        end
        rd_req = 1'b0;
        tick();
    endtask

    task automatic expect_errs(input string where, input logic [31:0] want);
        logic [31:0] st;
        drain();
        csr_read(CSR_NPU_STATUS, st);
        if ((st & ST_ERR_MASK) !== want)
            report(0, $sformatf("%s: error bits %08x, expected %08x", where, st & ST_ERR_MASK, want));
    endtask

    task automatic expect_acc(input string where, input int unsigned idx, input logic [31:0] want);
        drain();
        rd_idx = idx;
        rd_req = 1'b1;
        #1;
        if (rd_data !== want) report(1, $sformatf("%s: acc[%0d] = %08x, expected %08x", where, idx, rd_data, want));
        rd_req = 1'b0;
    endtask

    task automatic expect_all_acc(input string where, input logic [31:0] want);
        for (int idx = 0; idx < 16; idx++) expect_acc(where, idx, want);
    endtask

    // ---- data helpers --------------------------------------------------------------------------
    function automatic logic [31:0] pack4(input int l0, input int l1, input int l2, input int l3);
        return {l3[7:0], l2[7:0], l1[7:0], l0[7:0]};
    endfunction

    function automatic int unsigned xorshift32(input int unsigned x);
        x ^= x << 13;
        x ^= x >> 17;
        x ^= x << 5;
        return x;
    endfunction

    int unsigned rng;

    task automatic fill_random(input logic [31:0] byte_addr, input int unsigned nwords);
        for (int unsigned n = 0; n < nwords; n++) begin
            rng = xorshift32(rng);
            mem_write(byte_addr + 4 * n, rng);
        end
    endtask

    task automatic fill(input logic [31:0] byte_addr, input int unsigned nwords, input logic [31:0] w);
        for (int unsigned n = 0; n < nwords; n++) mem_write(byte_addr + 4 * n, w);
    endtask

    task automatic hand_setup();
        mem_write(W0 +  0, pack4(1, 2, 3, 4));
        mem_write(W0 +  4, pack4(-1, -2, -3, -4));
        mem_write(W0 +  8, pack4(127, 0, 0, 0));
        mem_write(W0 + 12, pack4(0, 0, 0, -128));
        mem_write(I0 +  0, pack4(1, 1, 1, 1));
        mem_write(I0 +  4, pack4(1, 0, 0, 0));
        mem_write(I0 +  8, pack4(-128, -128, -128, -128));
        mem_write(I0 + 12, pack4(2, -2, 2, -2));
    endtask

    task automatic hand_run();
        push(OP_LDW, W0, 4, 1'b0);
        push(OP_LDI, I0, 4, 1'b0);
        push(OP_MAC, 32'd0, 4, 1'b1);
    endtask

    task automatic check_hand(input string where);
        for (int idx = 0; idx < 16; idx++) expect_acc(where, idx, hand_acc[idx]);
    endtask

    // Task 10's expect_dropped: run the hand case, overwrite its DTCM data with zeros, issue one
    // command, check exactly `want` error bits, then show that the buffers and accumulators are
    // unchanged (a dropped LOAD that wrongly ran would have pulled in the zeros).
    task automatic expect_dropped(input logic [1:0] op, input logic [31:0] addr, input logic [31:0] k,
                                  input logic clr, input logic [31:0] want);
        string where;
        where = $sformatf("op %0d addr %08x k %0d clr %0d", op, addr, k, clr);
        reset_all();
        hand_setup();
        hand_run();
        drain();
        fill(W0, 4, 32'd0);
        fill(I0, 4, 32'd0);
        push(op, addr, k, clr);
        compare(where);
        expect_errs(where, want);
        check_hand({where, ", state kept"});
        push(OP_MAC, 32'd0, 4, 1'b1);                  // recompute from the buffers
        compare({where, ", recompute"});
        check_hand({where, ", recompute"});
    endtask

    task automatic big_setup(input logic [31:0] w);
        reset_all();
        fill(BIG_W, 1024, w);
        fill(BIG_I, 1024, w);
        push(OP_LDW, BIG_W, 1024, 1'b0);
        push(OP_LDI, BIG_I, 1024, 1'b0);
    endtask

    task automatic big_random_setup(input int unsigned seed);
        reset_all();
        rng = seed;
        fill_random(BIG_W, 1024);
        fill_random(BIG_I, 1024);
        push(OP_LDW, BIG_W, 1024, 1'b0);
        push(OP_LDI, BIG_I, 1024, 1'b0);
    endtask

    task automatic set_all_errors();
        push(OP_MAC, 32'd0, 6, 1'b0);                  // err_k
        push(OP_LDW, 32'h0001_FFF0, 8, 1'b0);          // err_addr
        push(OP_ILLEGAL, W0, 4, 1'b0);                 // err_illegal
        push(OP_LDI, 32'h0001_0004, 4, 1'b0);          // err_align
        compare("set all errors");
        expect_errs("set all errors", ST_ERR_MASK);
    endtask

    // Returns in the cycle in which npu_status.busy is 1, 2 ns after the edge. With a single
    // ILLEGAL or dropped command in flight that is its CHECK cycle.
    task automatic wait_busy(input string where);
        logic [31:0] st;
        for (int n = 0; n < 20; n++) begin
            csr_read(CSR_NPU_STATUS, st);
            if (st[ST_BUSY]) return;
            @(posedge clk);
            #1;
        end
        report(2, {where, ": npu_status.busy never became 1"});
    endtask

    // ---- monitors ------------------------------------------------------------------------------
    // No X or Z on an output once reset is released (QuestaSim is 4-state).
    always @(negedge clk) begin
        if (rst_n) begin
            if ($isunknown({cmd_ready, rd_ready, b_req, csr_rdata}))
                report(2, $sformatf("X/Z on an output: cmd_ready %b rd_ready %b b_req %b csr_rdata %08x",
                                    cmd_ready, rd_ready, b_req, csr_rdata));
            if (b_req && $isunknown(b_addr)) report(2, "X/Z on b_addr while b_req");
            if (rd_ready && $isunknown(rd_data)) report(2, "X/Z on rd_data while rd_ready");
        end
    end

    // Counts busy cycles from outside: npu_status.busy, sampled in the middle of each cycle while the
    // testbench holds csr_addr at npu_status.
    bit count_busy = 1'b0;
    int n_busy_seen = 0;
    always @(negedge clk) begin
        if (count_busy && csr_addr == CSR_NPU_STATUS && csr_rdata[ST_BUSY]) n_busy_seen++;
    end

    // ---- tests ---------------------------------------------------------------------------------
    task automatic t_single_k4();
        reset_all();
        hand_setup();
        hand_run();
        compare("hand");
        check_hand("hand");
        expect_errs("hand", 32'd0);
    endtask

    // Task 10 test_hand_k8_accumulate: random words, an oracle written here from the word arrays.
    task automatic t_k8_layout();
        logic [31:0] wm [8], im [8], want [16];
        int unsigned s;
        logic [31:0] WA, IA;
        WA = 32'h0001_0000;
        IA = 32'h0001_0100;
        s = 12345;
        for (int n = 0; n < 8; n++) begin
            s = s * 1664525 + 1013904223; wm[n] = s;
            s = s * 1664525 + 1013904223; im[n] = s;
        end
        for (int i = 0; i < 4; i++)
            for (int j = 0; j < 4; j++) begin
                int sum;
                sum = 0;
                for (int q = 0; q < 2; q++)
                    for (int t = 0; t < 4; t++) begin
                        int a, b;
                        a = $signed(wm[4 * q + i][8 * t +: 8]);
                        b = $signed(im[4 * q + j][8 * t +: 8]);
                        sum += a * b;
                    end
                want[4 * i + j] = sum;
            end
        // (a) one COMPUTE with K = 8
        reset_all();
        for (int n = 0; n < 8; n++) begin mem_write(WA + 4 * n, wm[n]); mem_write(IA + 4 * n, im[n]); end
        push(OP_LDW, WA, 8, 1'b0);
        push(OP_LDI, IA, 8, 1'b0);
        push(OP_MAC, 32'd0, 8, 1'b1);
        compare("K=8");
        for (int idx = 0; idx < 16; idx++) expect_acc("K=8", idx, want[idx]);
        // (b) two COMPUTEs with K = 4, the second accumulating
        reset_all();
        for (int n = 0; n < 8; n++) begin mem_write(WA + 4 * n, wm[n]); mem_write(IA + 4 * n, im[n]); end
        push(OP_LDW, WA, 4, 1'b0);
        push(OP_LDI, IA, 4, 1'b0);
        push(OP_MAC, 32'd0, 4, 1'b1);
        push(OP_LDW, WA + 16, 4, 1'b0);
        push(OP_LDI, IA + 16, 4, 1'b0);
        push(OP_MAC, 32'd0, 4, 1'b0);
        compare("2 x K=4");
        for (int idx = 0; idx < 16; idx++) expect_acc("2 x K=4", idx, want[idx]);
        expect_errs("2 x K=4", 32'd0);
    endtask

    task automatic t_k_kmax();
        big_random_setup(32'hC0FF_EE01);
        push(OP_MAC, 32'd0, 1024, 1'b1);
        compare("K=1024 random");
        expect_errs("K=1024 random", 32'd0);
        big_setup(32'h8080_8080);                      // every lane -128
        push(OP_MAC, 32'd0, 1024, 1'b1);
        compare("K=1024 all -128");
        expect_all_acc("K=1024 all -128", 32'd16777216);   // 1024 * (-128)^2
    endtask

    task automatic t_k0();
        logic [1:0] ops [3] = '{OP_LDW, OP_LDI, OP_MAC};
        foreach (ops[o])
            for (int clr = 0; clr < 2; clr++)
                expect_dropped(ops[o], 32'hFFFF_FFFF, 0, clr, 32'd0);  // the address must not even be checked
    endtask

    task automatic t_k_too_big();
        logic [1:0]  ops [3] = '{OP_LDW, OP_LDI, OP_MAC};
        logic [31:0] ks  [5] = '{1028, 2048, 32'h0001_0000, 32'h8000_0400, 32'hFFFF_FFFC};
        foreach (ops[o]) foreach (ks[n]) expect_dropped(ops[o], W0, ks[n], 1'b1, ERR_K_B);
    endtask

    task automatic t_k_mod4();
        logic [1:0]  ops [3] = '{OP_LDW, OP_LDI, OP_MAC};
        logic [31:0] ks  [6] = '{1, 2, 3, 6, 1022, 32'hFFFF_FFFF};
        foreach (ops[o]) foreach (ks[n]) expect_dropped(ops[o], W0, ks[n], 1'b1, ERR_K_B);
    endtask

    task automatic t_addr_oob();
        logic [1:0] loads [2] = '{OP_LDW, OP_LDI};
        foreach (loads[o]) begin
            expect_dropped(loads[o], 32'h0000_FFF0, 4, 1'b0, ERR_ADDR_B);     // just below the DTCM
            expect_dropped(loads[o], 32'h0000_0000, 4, 1'b0, ERR_ADDR_B);     // ITCM
            expect_dropped(loads[o], 32'h0001_FFF0, 8, 1'b0, ERR_ADDR_B);     // runs past the end
            expect_dropped(loads[o], 32'h0002_0000, 4, 1'b0, ERR_ADDR_B);     // starts at the end
            expect_dropped(loads[o], 32'h0001_F010, 1024, 1'b0, ERR_ADDR_B);  // K=KMAX, 16 bytes too far
            // legal edge cases: no error
            reset_all();
            push(loads[o], 32'h0001_FFF0, 4, 1'b0);                           // the last quad
            push(loads[o], 32'h0001_F000, 1024, 1'b0);                        // ends exactly at the end
            push(loads[o], DTCM_BASE, 1024, 1'b0);
            compare("legal edge loads");
            expect_errs("legal edge loads", 32'd0);
        end
    endtask

    task automatic t_addr_misaligned();
        logic [1:0] loads [2] = '{OP_LDW, OP_LDI};
        foreach (loads[o]) begin
            expect_dropped(loads[o], 32'h0001_0004, 4, 1'b0, ERR_ALN_B);
            expect_dropped(loads[o], 32'h0001_0001, 4, 1'b0, ERR_ALN_B);
            expect_dropped(loads[o], 32'h0001_000F, 4, 1'b0, ERR_ALN_B);
            expect_dropped(loads[o], 32'h0001_FFF4, 8, 1'b0, ERR_ALN_B);      // also out of range: align first
            // K is checked before alignment and range (D16 order)
            expect_dropped(loads[o], 32'h0001_0004, 6,    1'b0, ERR_K_B);
            expect_dropped(loads[o], 32'h0001_0004, 1028, 1'b0, ERR_K_B);
            expect_dropped(loads[o], 32'hFFFF_FFF0, 6,    1'b0, ERR_K_B);
            expect_dropped(loads[o], 32'hFFFF_FFF0, 1028, 1'b0, ERR_K_B);
        end
        expect_dropped(OP_MAC, 32'h0000_0003, 4, 1'b1, 32'd0);                // COMPUTE ignores the address
    endtask

    task automatic load_addr_wraps_32bit();
        logic [1:0] loads [2] = '{OP_LDW, OP_LDI};
        foreach (loads[o]) begin
            expect_dropped(loads[o], 32'hFFFF_FFF0, 8,    1'b0, ERR_ADDR_B);  // a + 4K wraps to 0x10
            expect_dropped(loads[o], 32'hFFFF_FFF0, 4,    1'b0, ERR_ADDR_B);  // a + 4K wraps to exactly 0
            expect_dropped(loads[o], 32'hFFFF_FF00, 1024, 1'b0, ERR_ADDR_B);  // wraps into the ITCM range
        end
    endtask

    task automatic compute_k0_clr_keeps_acc();
        reset_all();
        hand_setup();
        hand_run();
        push(OP_MAC, 32'd0, 0, 1'b1);
        compare("COMPUTE K=0 clr=1");
        check_hand("COMPUTE K=0 clr=1");
        expect_errs("COMPUTE K=0 clr=1", 32'd0);
    endtask

    task automatic t_illegal();
        logic [31:0] addrs [4] = '{W0, 32'h0001_0004, 32'hFFFF_FFF0, 32'h0000_0000};
        logic [31:0] ks    [4] = '{0, 4, 6, 1028};
        foreach (addrs[a]) foreach (ks[n])
            for (int clr = 0; clr < 2; clr++)
                expect_dropped(OP_ILLEGAL, addrs[a], ks[n], clr, ERR_ILL_B);
    endtask

    task automatic t_clr_vs_acc();
        reset_all();
        hand_setup();
        hand_run();
        push(OP_MAC, 32'd0, 4, 1'b0);                  // accumulate: every value doubles
        compare("accumulate");
        for (int idx = 0; idx < 16; idx++) expect_acc("accumulate", idx, 2 * hand_acc[idx]);
        push(OP_MAC, 32'd0, 4, 1'b1);                  // clr: back to one copy
        compare("clr");
        check_hand("clr");
    endtask

    // Task 10 test_stale_quads_survive_short_load: buffers keep old quads (spec 7.2).
    task automatic t_stale_quads();
        logic [31:0] WA, IA;
        WA = 32'h0001_0000;
        IA = 32'h0001_0100;
        reset_all();
        mem_write(WA +  0, pack4(1, 1, 1, 1));
        mem_write(WA + 16, pack4(2, 2, 2, 2));
        mem_write(IA +  0, pack4(1, 1, 1, 1));
        mem_write(IA + 16, pack4(1, 1, 1, 1));
        push(OP_LDW, WA, 8, 1'b0);
        push(OP_LDI, IA, 8, 1'b0);
        drain();
        mem_write(WA, pack4(3, 3, 3, 3));
        mem_write(WA + 16, pack4(5, 5, 5, 5));         // a K=4 LOAD that also read quad 1 would load this
        push(OP_LDW, WA, 4, 1'b0);                     // K=4: WBUF quad 1 must stay
        push(OP_MAC, 32'd0, 8, 1'b1);
        compare("stale quad 1");
        expect_acc("stale quad 1", 0, 3 * 4 + 2 * 4);
    endtask

    // Task 10 test_wrap: 257 x 2^24 passes 2^31 and 2^32.
    task automatic t_wrap();
        big_setup(32'h8080_8080);
        push(OP_MAC, 32'd0, 1024, 1'b1);
        for (int n = 1; n < 128; n++) push(OP_MAC, 32'd0, 1024, 1'b0);
        compare("128 x 2^24");
        expect_all_acc("128 x 2^24", 32'h8000_0000);
        for (int n = 128; n < 256; n++) push(OP_MAC, 32'd0, 1024, 1'b0);
        compare("256 x 2^24");
        expect_all_acc("256 x 2^24", 32'h0000_0000);
        push(OP_MAC, 32'd0, 1024, 1'b0);
        compare("257 x 2^24");
        expect_all_acc("257 x 2^24", 32'h0100_0000);
        expect_errs("wrap", 32'd0);
    endtask

    // 10 back-to-back pushes of long commands. The first is popped at once, the next 8 fill the FIFO,
    // so pushes 1..9 are accepted in 9 consecutive cycles and push 10 must wait. Every cycle,
    // cmd_ready must equal !npu_status.fifo_full. No command may be lost: the final result depends
    // on all ten.
    bit mon_ready = 1'b0;
    int n_full_seen = 0;
    always @(negedge clk) begin
        if (mon_ready && csr_addr == CSR_NPU_STATUS) begin
            if (cmd_ready !== !csr_rdata[ST_FIFO_FULL])
                report(2, $sformatf("cmd_ready %b but npu_status.fifo_full %b", cmd_ready, csr_rdata[ST_FIFO_FULL]));
            if (csr_rdata[ST_FIFO_FULL]) n_full_seen++;
        end
    end

    task automatic t_fifo_full();
        int waits [10];
        rng = 32'h0F1F_0001;
        reset_all();
        fill_random(BIG_W, 1024);
        fill_random(BIG_I, 1024);
        csr_addr    = CSR_NPU_STATUS;
        n_full_seen = 0;
        mon_ready   = 1'b1;
        push(OP_LDW, BIG_W, 1024, 1'b0);  waits[0] = last_push_wait;
        push(OP_LDI, BIG_I, 1024, 1'b0);  waits[1] = last_push_wait;
        push(OP_MAC, 32'd0, 1024, 1'b1);  waits[2] = last_push_wait;
        for (int n = 3; n < 10; n++) begin
            push(OP_MAC, 32'd0, 1024, 1'b0);
            waits[n] = last_push_wait;
        end
        drain();
        mon_ready = 1'b0;
        for (int n = 0; n < 9; n++)
            if (waits[n] != 0) report(2, $sformatf("push %0d waited %0d cycles, expected 0", n + 1, waits[n]));
        if (waits[9] == 0) report(2, "push 10 was accepted at once: the FIFO never filled");
        if (n_full_seen == 0) report(2, "npu_status.fifo_full was never seen");
        compare("10 pushes");
        expect_errs("10 pushes", 32'd0);
    endtask

    // While commands are queued or running, rd_ready must be 0; it must equal
    // npu_status.fifo_empty && !npu_status.busy in every cycle (A-MAC-2), then the data must match.
    task automatic t_read_while_busy();
        logic [31:0] st;
        int waited;
        big_random_setup(32'h5EED_0002);
        push(OP_MAC, 32'd0, 1024, 1'b1);
        rd_idx = 5;
        rd_req = 1'b1;
        waited = 0;
        forever begin
            csr_read(CSR_NPU_STATUS, st);
            if (rd_ready !== (st[ST_FIFO_EMPTY] && !st[ST_BUSY]))
                report(2, $sformatf("rd_ready %b, npu_status %08x", rd_ready, st));
            if (rd_ready === 1'b1) break;
            tick();
            waited++;
            if (waited > DRAIN_LIMIT) begin report(2, "rd_ready never became 1"); break; end
        end
        // three commands of 256 quads each, one quad per cycle at best (spec 7.2)
        if (waited < 3 * 256) report(2, $sformatf("rd_ready came after %0d cycles, at least 768 expected", waited));
        if (rd_data !== npu_ref_read(5)) report(1, $sformatf("acc[5] = %08x, npu_ref %08x", rd_data, npu_ref_read(5)));
        rd_req = 1'b0;
        tick();
        compare("after the read");
    endtask

    task automatic t_w1c();
        logic [31:0] st;
        logic [31:0] bits [4] = '{ERR_K_B, ERR_ADDR_B, ERR_ILL_B, ERR_ALN_B};
        logic [31:0] left;
        reset_all();
        set_all_errors();
        csr_write(CSR_NPU_STATUS, 32'd0);              // writing 0 clears nothing
        compare("write 0");
        expect_errs("write 0", ST_ERR_MASK);
        csr_write(CSR_NPU_STATUS, 32'h0000_0007);      // RO bits: no effect
        compare("write RO bits");
        left = ST_ERR_MASK;
        foreach (bits[b]) begin                        // one bit at a time
            csr_write(CSR_NPU_STATUS, bits[b]);
            left &= ~bits[b];
            compare($sformatf("clear bit %0d", b));
            expect_errs($sformatf("clear bit %0d", b), left);
        end
        set_all_errors();
        csr_write(CSR_NPU_STATUS, 32'hFFFF_FFFF);
        compare("write all ones");
        expect_errs("write all ones", 32'd0);

        // D23: CHECK sets err_illegal in the same cycle as a W1C of err_illegal and err_k.
        push(OP_MAC, 32'd0, 6, 1'b0);                  // err_k
        expect_errs("D23 setup", ERR_K_B);
        push(OP_ILLEGAL, W0, 4, 1'b0);
        wait_busy("D23");                              // the ILLEGAL's CHECK cycle
        csr_read(CSR_NPU_STATUS, st);
        if (st[ST_ERR_ILLEGAL] !== 1'b0) report(0, "D23: err_illegal already 1 before its CHECK edge");
        csr_wdata = ERR_ILL_B | ERR_K_B;
        csr_we    = 1'b1;
        @(posedge clk);
        #1 csr_we = 1'b0;
        npu_ref_csr_write(CSR_NPU_STATUS, ERR_K_B);    // the model has no same-cycle case: apply set-wins
        csr_read(CSR_NPU_STATUS, st);
        if ((st & ST_ERR_MASK) !== ERR_ILL_B)
            report(0, $sformatf("D23: error bits %08x after set + clear in one cycle, expected %08x (set wins, err_k cleared)",
                                st & ST_ERR_MASK, ERR_ILL_B));
        compare("D23");
    endtask

    task automatic t_csr_write_semantics();
        logic [31:0] st, bc, v, rd0, rd1;
        logic [11:0] aliases [$];
        logic [11:0] csrs [2] = '{CSR_NPU_STATUS, CSR_NPU_BUSY_CYC};
        // every address one bit away from 0x7C0 or 0x7C1 (bit 0 of 0x7C1 gives 0x7C0, a real CSR, so
        // the flips start at bit 1), plus two far ones: a decoder that ignores any address bit fails
        aliases = '{12'h000, 12'hB00};
        for (int b = 1; b < 12; b++) begin
            aliases.push_back(CSR_NPU_STATUS ^ (12'd1 << b));
            aliases.push_back(CSR_NPU_BUSY_CYC ^ (12'd1 << b));
        end
        reset_all();
        csr_read(CSR_NPU_BUSY_CYC, bc);
        if (bc !== 32'd0) report(0, $sformatf("npu_busy_cyc after reset = %0d", bc));

        // npu_busy_cyc counts exactly the cycles with npu_status.busy = 1
        csr_addr    = CSR_NPU_STATUS;
        n_busy_seen = 0;
        count_busy  = 1'b1;
        push(OP_ILLEGAL, W0, 4, 1'b0);
        drain();
        count_busy = 1'b0;
        csr_read(CSR_NPU_BUSY_CYC, bc);
        if (n_busy_seen != 1) report(2, $sformatf("an ILLEGAL command kept the engine busy %0d cycles, expected 1 (CHECK)", n_busy_seen));
        if (bc !== n_busy_seen) report(0, $sformatf("npu_busy_cyc %0d, busy cycles seen %0d", bc, n_busy_seen));
        csr_addr    = CSR_NPU_STATUS;
        n_busy_seen = 0;
        count_busy  = 1'b1;
        push(OP_MAC, 32'd0, 6, 1'b0);
        push(OP_LDW, W0, 4, 1'b0);
        push(OP_MAC, 32'd0, 0, 1'b1);
        push(OP_LDI, I0, 8, 1'b0);
        push(OP_MAC, 32'd0, 4, 1'b1);
        push(OP_LDW, 32'h0001_0004, 4, 1'b0);
        drain();
        count_busy = 1'b0;
        csr_read(CSR_NPU_BUSY_CYC, v);
        if (v - bc !== n_busy_seen) report(0, $sformatf("npu_busy_cyc grew by %0d, busy cycles seen %0d", v - bc, n_busy_seen));

        // W1C writes (D17)
        reset_all();
        set_all_errors();
        csr_write(CSR_NPU_STATUS, 32'h0000_0100);      // clears err_k only
        compare("write 0x100");
        expect_errs("write 0x100", ST_ERR_MASK & ~ERR_K_B);
        csr_write(CSR_NPU_STATUS, 32'd0);              // changes nothing
        compare("write 0");
        expect_errs("write 0", ST_ERR_MASK & ~ERR_K_B);

        // a write to npu_busy_cyc in a busy cycle wins over the increment
        v = 32'h1234_5678;
        push(OP_ILLEGAL, W0, 4, 1'b0);
        wait_busy("busy_cyc write");
        csr_addr  = CSR_NPU_BUSY_CYC;
        csr_wdata = v;
        csr_we    = 1'b1;
        @(posedge clk);
        npu_ref_csr_write(CSR_NPU_BUSY_CYC, v);
        #1 csr_we = 1'b0;
        csr_read(CSR_NPU_BUSY_CYC, bc);
        if (bc !== v) report(0, $sformatf("npu_busy_cyc %08x after a write of %08x in a busy cycle", bc, v));
        compare("busy_cyc write");

        // other addresses read 0 and ignore writes, while error bits are set and npu_busy_cyc != 0
        set_all_errors();
        csr_write(CSR_NPU_BUSY_CYC, v);
        foreach (aliases[a]) begin
            csr_read(aliases[a], st);
            if (st !== 32'd0) report(0, $sformatf("CSR 0x%03x reads %08x, expected 0", aliases[a], st));
            csr_write(aliases[a], 32'hFFFF_FFFF);
            compare($sformatf("write to 0x%03x", aliases[a]));
            expect_errs($sformatf("write to 0x%03x", aliases[a]), ST_ERR_MASK);
            csr_read(CSR_NPU_BUSY_CYC, bc);
            if (bc !== v) report(0, $sformatf("npu_busy_cyc %08x after a write to 0x%03x", bc, aliases[a]));
        end

        // D21: no combinational path from the other inputs either. Inside one cycle, raise cmd_valid
        // (dropped again before the edge, so nothing is pushed), rd_req and rd_idx: csr_rdata must not move.
        foreach (csrs[c]) begin
            tick();
            csr_addr = csrs[c];
            #0.5 rd0 = csr_rdata;
            cmd_op = OP_ILLEGAL; cmd_addr = 32'hFFFF_FFF0; cmd_k = 6; cmd_clr = 1'b1; cmd_valid = 1'b1;
            rd_req = 1'b1; rd_idx = 4'hF;
            #0.5 rd1 = csr_rdata;
            cmd_valid = 1'b0;
            rd_req    = 1'b0;
            if (rd1 !== rd0)
                report(0, $sformatf("D21: CSR 0x%03x moved from %08x to %08x with cmd_valid/rd_req/rd_idx", csrs[c], rd0, rd1));
        end
        compare("after the D21 input sweep");
    endtask

    // D18: an asynchronous reset in the middle of a cycle, with error bits set, non-zero accumulators,
    // a non-zero npu_busy_cyc, commands queued and one running. Buffers are not checked (spec 7.2).
    task automatic t_reset_state();
        logic [31:0] st, bc;
        reset_all();
        hand_setup();
        hand_run();
        push(OP_MAC, 32'd0, 6, 1'b0);
        push(OP_ILLEGAL, W0, 4, 1'b0);
        compare("before reset");
        expect_errs("before reset", ERR_K_B | ERR_ILL_B);
        push(OP_LDW, BIG_W, 1024, 1'b0);
        for (int n = 0; n < 4; n++) push(OP_MAC, 32'd0, 1024, 1'b0);
        // We are 1 ns after an edge. Assert reset now and read everything in 0.2 ns steps, so all phase-0
        // reads (about 4 ns) happen before the next edge: only asynchronous-reset flops pass them (D18).
        rst_n = 1'b0;
        for (int phase = 0; phase < 2; phase++) begin  // 0: at once, before any edge; 1: after release
            string when;
            when = phase == 0 ? "during reset, before an edge" : "after release";
            csr_addr = CSR_NPU_STATUS;
            #0.2 st = csr_rdata;
            if (st !== (32'd1 << ST_FIFO_EMPTY)) report(0, $sformatf("%s: npu_status %08x, expected %08x", when, st, 32'd1 << ST_FIFO_EMPTY));
            csr_addr = CSR_NPU_BUSY_CYC;
            #0.2 bc = csr_rdata;
            if (bc !== 32'd0) report(0, $sformatf("%s: npu_busy_cyc %0d", when, bc));
            if (cmd_ready !== 1'b1) report(2, $sformatf("%s: cmd_ready %b", when, cmd_ready));
            if (rd_ready !== 1'b1)  report(2, $sformatf("%s: rd_ready %b", when, rd_ready));
            if (b_req !== 1'b0)     report(2, $sformatf("%s: b_req %b", when, b_req));
            rd_req = 1'b1;
            for (int idx = 0; idx < 16; idx++) begin
                rd_idx = idx;
                #0.2;
                if (rd_data !== 32'd0) report(1, $sformatf("%s: acc[%0d] = %08x", when, idx, rd_data));
            end
            rd_req = 1'b0;
            if (phase == 0) begin
                tick();
                tick();
                rst_n = 1'b1;
                tick();
            end
        end
        npu_ref_reset();                               // resynchronise the model (its DTCM too)
        u_dtcm.clear();
        exp_reads = 0;
        compare("after reset");
    endtask

    // ---- runner --------------------------------------------------------------------------------
    string TESTS [$] = '{
        "t_single_k4", "t_k8_layout", "t_k_kmax", "t_k0", "t_k_too_big", "t_k_mod4", "t_addr_oob",
        "t_addr_misaligned", "load_addr_wraps_32bit", "compute_k0_clr_keeps_acc", "t_illegal",
        "t_clr_vs_acc", "t_stale_quads", "t_wrap", "t_fifo_full", "t_read_while_busy", "t_w1c",
        "t_csr_write_semantics", "t_reset_state"
    };

    task automatic run_one(input string name);
        cur = name;
        n_status = 0; n_value = 0; n_other = 0;
        case (name)
            "t_single_k4":              t_single_k4();
            "t_k8_layout":              t_k8_layout();
            "t_k_kmax":                 t_k_kmax();
            "t_k0":                     t_k0();
            "t_k_too_big":              t_k_too_big();
            "t_k_mod4":                 t_k_mod4();
            "t_addr_oob":               t_addr_oob();
            "t_addr_misaligned":        t_addr_misaligned();
            "load_addr_wraps_32bit":    load_addr_wraps_32bit();
            "compute_k0_clr_keeps_acc": compute_k0_clr_keeps_acc();
            "t_illegal":                t_illegal();
            "t_clr_vs_acc":             t_clr_vs_acc();
            "t_stale_quads":            t_stale_quads();
            "t_wrap":                   t_wrap();
            "t_fifo_full":              t_fifo_full();
            "t_read_while_busy":        t_read_while_busy();
            "t_w1c":                    t_w1c();
            "t_csr_write_semantics":    t_csr_write_semantics();
            "t_reset_state":            t_reset_state();
            default: begin
                $display("unknown test %s", name);
                n_other++;
            end
        endcase
        if (n_status + n_value + n_other == 0) results.push_back($sformatf("PASS  %s", name));
        else begin
            n_failed++;
            results.push_back($sformatf("FAIL  %s status %0d  value %0d  other %0d", name, n_status, n_value, n_other));
        end
    endtask

    initial begin
        string only;
        int    ran;
        bit    have_only;
        have_only = $value$plusargs("TEST=%s", only);
        ran = 0;
        foreach (TESTS[n]) begin
            if (!have_only || TESTS[n] == only) begin
                run_one(TESTS[n]);
                ran++;
            end
        end
        if (ran == 0) begin
            $display("no test named %s", only);
            n_failed++;
        end
        $display("---- mac_engine_tb summary ----");
        foreach (results[n]) $display("%s", results[n]);
        if (n_failed == 0) begin
            $display("RESULT: PASS");
            $finish;
        end else begin
            $display("RESULT: FAIL (%0d of %0d tests)", n_failed, ran);
            $fatal(1, "mac_engine_tb failed");
        end
    end

    // a stuck run must fail, not hang
    initial begin
        #(10 * 4_000_000);
        $fatal(1, "FAIL global timeout in test %s", cur);
    end
endmodule
