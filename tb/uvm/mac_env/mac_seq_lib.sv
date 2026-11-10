// mac_seq_lib.sv - sequences of mac_env (Phase 2 Task 16: Step 1, the directed tests of spec 10.3;
// Step 6, mac_rand_seq at the end of the file). Included by mac_test_pkg.
//
// mac_base_seq holds the helpers. Every READ_RESULT and every npu_status read it issues is also compared
// with npu_ref by the scoreboard; the explicit expectations below (hand-computed values, error bits,
// wait cycles) are a second, model-independent check. DTCM writes go through dtcm_agent.write_word, which
// mirrors them into npu_ref, and are only made after drain() (the WAR rule, spec 6.3 rule 5).

class mac_base_seq extends uvm_sequence #(mac_cmd_item);
    `uvm_object_utils(mac_base_seq)

    mac_env env;                                       // set by the test before start()
    int unsigned last_wait;                            // wait_cycles of the last push() or read()
    bit [31:0]   rng = 32'h1234_5678;

    localparam bit [31:0] W0    = 32'h0001_0000;       // hand case, as in Task 10 test_npu_ref.c
    localparam bit [31:0] I0    = 32'h0001_0010;
    localparam bit [31:0] BIG_W = 32'h0001_0000;       // K = KMAX operands, 4 KB each
    localparam bit [31:0] BIG_I = 32'h0001_1000;

    // hand case results, acc[4*i + j] = dot(row i, image j)
    int hand_acc [16] = '{10, 1, -1280, -4, -10, -1, 1280, 4, 127, 127, -16256, 254, -128, 0, 16384, 256};

    function new(string name = "mac_base_seq");
        super.new(name);
    endfunction

    // ---- transactions --------------------------------------------------------------------------
    task push(npu_op_e op, bit [31:0] addr, bit [31:0] k, bit clr = 1'b0, int unsigned gap = 0);
        mac_cmd_item it = mac_cmd_item::type_id::create("push");
        start_item(it);
        it.kind = MAC_PUSH; it.op = op; it.addr = addr; it.k = k; it.clr = clr; it.gap = gap;
        finish_item(it);
        last_wait = it.wait_cycles;
    endtask

    task read(bit [3:0] idx, output bit [31:0] data, input int unsigned gap = 0);
        mac_cmd_item it = mac_cmd_item::type_id::create("read");
        start_item(it);
        it.kind = MAC_READ; it.idx = idx; it.gap = gap;
        finish_item(it);
        data      = it.rdata;
        last_wait = it.wait_cycles;
    endtask

    task csr_rd(bit [11:0] a, output bit [31:0] data, input int unsigned gap = 0);
        mac_cmd_item it = mac_cmd_item::type_id::create("csr_rd");
        start_item(it);
        it.kind = MAC_CSR_RD; it.csr_addr = a; it.gap = gap;
        finish_item(it);
        data = it.rdata;
    endtask

    task csr_wr(bit [11:0] a, bit [31:0] d, int unsigned gap = 0);
        mac_cmd_item it = mac_cmd_item::type_id::create("csr_wr");
        start_item(it);
        it.kind = MAC_CSR_WR; it.csr_addr = a; it.csr_wdata = d; it.gap = gap;
        finish_item(it);
    endtask

    // READ_RESULT waits until the engine is idle with an empty FIFO (spec 6.3 rule 4)
    task drain();
        bit [31:0] d;
        read(0, d);
    endtask

    // all 16 results and npu_status, each compared with npu_ref by the scoreboard
    task check_all();
        bit [31:0] d;
        for (int i = 0; i < 16; i++) read(i, d);
        csr_rd(CSR_NPU_STATUS, d);
    endtask

    task clear_errors();
        csr_wr(CSR_NPU_STATUS, ST_ERR_MASK);
    endtask

    task expect_errs(string where, bit [31:0] want);
        bit [31:0] st;
        drain();
        csr_rd(CSR_NPU_STATUS, st);
        if ((st & ST_ERR_MASK) != want)
            `uvm_error("ERRBITS", $sformatf("%s: error bits %08x, expected %08x", where, st & ST_ERR_MASK, want))
    endtask

    task expect_acc(string where, int unsigned idx, bit [31:0] want);
        bit [31:0] d;
        read(idx, d);
        if (d != want) `uvm_error("EXPECTED", $sformatf("%s: acc[%0d] = %08x, expected %08x", where, idx, d, want))
    endtask

    task expect_all_acc(string where, bit [31:0] want);
        for (int i = 0; i < 16; i++) expect_acc(where, i, want);
    endtask

    // ---- data ----------------------------------------------------------------------------------
    function void mem_write(bit [31:0] byte_addr, bit [31:0] data);
        env.dtcm_agent.write_byte_addr(byte_addr, data);
    endfunction

    function bit [31:0] pack4(int l0, int l1, int l2, int l3);
        return {l3[7:0], l2[7:0], l1[7:0], l0[7:0]};
    endfunction

    function bit [31:0] next_rand();
        rng ^= rng << 13;
        rng ^= rng >> 17;
        rng ^= rng << 5;
        return rng;
    endfunction

    function void fill(bit [31:0] byte_addr, int unsigned nwords, bit [31:0] w);
        for (int unsigned n = 0; n < nwords; n++) mem_write(byte_addr + 4 * n, w);
    endfunction

    function void fill_random(bit [31:0] byte_addr, int unsigned nwords);
        for (int unsigned n = 0; n < nwords; n++) mem_write(byte_addr + 4 * n, next_rand());
    endfunction

    function void hand_setup();
        mem_write(W0 +  0, pack4(1, 2, 3, 4));
        mem_write(W0 +  4, pack4(-1, -2, -3, -4));
        mem_write(W0 +  8, pack4(127, 0, 0, 0));
        mem_write(W0 + 12, pack4(0, 0, 0, -128));
        mem_write(I0 +  0, pack4(1, 1, 1, 1));
        mem_write(I0 +  4, pack4(1, 0, 0, 0));
        mem_write(I0 +  8, pack4(-128, -128, -128, -128));
        mem_write(I0 + 12, pack4(2, -2, 2, -2));
    endfunction

    task hand_run();
        push(OP_LDW, W0, 4);
        push(OP_LDI, I0, 4);
        push(OP_MAC, 0, 4, 1'b1);
    endtask

    task check_hand(string where);
        for (int i = 0; i < 16; i++) expect_acc(where, i, hand_acc[i]);
    endtask

    // Task 10's expect_dropped: run the hand case, overwrite its DTCM data with zeros, issue one
    // command, check exactly `want` error bits, then show that buffers and accumulators are unchanged
    // (a dropped LOAD that wrongly ran would have pulled in the zeros).
    task expect_dropped(npu_op_e op, bit [31:0] addr, bit [31:0] k, bit clr, bit [31:0] want);
        string where = $sformatf("%s addr %08x K %0d clr %0d", op.name(), addr, k, clr);
        drain();
        clear_errors();
        hand_setup();
        hand_run();
        drain();
        fill(W0, 4, 0);
        fill(I0, 4, 0);
        push(op, addr, k, clr);
        check_all();
        expect_errs(where, want);
        check_hand({where, ", state kept"});
        push(OP_MAC, 0, 4, 1'b1);                      // recompute from the buffers
        check_hand({where, ", recompute"});
    endtask

    task big_setup(bit [31:0] w);
        drain();
        fill(BIG_W, 1024, w);
        fill(BIG_I, 1024, w);
        push(OP_LDW, BIG_W, 1024);
        push(OP_LDI, BIG_I, 1024);
    endtask

    task big_random_setup();
        drain();
        fill_random(BIG_W, 1024);
        fill_random(BIG_I, 1024);
        push(OP_LDW, BIG_W, 1024);
        push(OP_LDI, BIG_I, 1024);
    endtask
endclass

// End of every test: all results and npu_status once more after the last command.
class mac_final_seq extends mac_base_seq;
    `uvm_object_utils(mac_final_seq)
    function new(string name = "mac_final_seq"); super.new(name); endfunction
    task body(); check_all(); endtask
endclass

// ---- directed sequences, one per spec 10.3 mac row -------------------------------------------------

class mac_single_k4_seq extends mac_base_seq;
    `uvm_object_utils(mac_single_k4_seq)
    function new(string name = "mac_single_k4_seq"); super.new(name); endfunction
    task body();
        hand_setup();
        hand_run();
        check_all();
        check_hand("hand case");
        expect_errs("hand case", 0);
    endtask
endclass

class mac_k_kmax_seq extends mac_base_seq;
    `uvm_object_utils(mac_k_kmax_seq)
    function new(string name = "mac_k_kmax_seq"); super.new(name); endfunction
    task body();
        rng = 32'hC0FF_EE01;
        big_random_setup();
        push(OP_MAC, 0, KMAX, 1'b1);
        check_all();
        big_setup(32'h8080_8080);                      // every lane -128
        push(OP_MAC, 0, KMAX, 1'b1);
        check_all();
        expect_all_acc("K=KMAX, all -128", 32'd16777216);   // 1024 * (-128)^2
        expect_errs("K=KMAX", 0);
    endtask
endclass

class mac_k0_seq extends mac_base_seq;
    `uvm_object_utils(mac_k0_seq)
    function new(string name = "mac_k0_seq"); super.new(name); endfunction
    task body();
        npu_op_e ops [3] = '{OP_LDW, OP_LDI, OP_MAC};
        foreach (ops[o])
            for (int clr = 0; clr < 2; clr++)
                expect_dropped(ops[o], 32'hFFFF_FFFF, 0, clr, 0);    // the address must not even be checked
    endtask
endclass

class mac_k_too_big_seq extends mac_base_seq;
    `uvm_object_utils(mac_k_too_big_seq)
    function new(string name = "mac_k_too_big_seq"); super.new(name); endfunction
    task body();
        npu_op_e   ops [3] = '{OP_LDW, OP_LDI, OP_MAC};
        bit [31:0] ks  [4] = '{KMAX + 4, 2048, 32'h8000_0400, 32'hFFFF_FFFC};
        foreach (ops[o]) foreach (ks[n]) expect_dropped(ops[o], W0, ks[n], 1'b1, 32'd1 << ST_ERR_K);
    endtask
endclass

class mac_k_mod4_seq extends mac_base_seq;
    `uvm_object_utils(mac_k_mod4_seq)
    function new(string name = "mac_k_mod4_seq"); super.new(name); endfunction
    task body();
        npu_op_e   ops [3] = '{OP_LDW, OP_LDI, OP_MAC};
        bit [31:0] ks  [5] = '{6, 1, 2, 3, 1022};
        foreach (ops[o]) foreach (ks[n]) expect_dropped(ops[o], W0, ks[n], 1'b1, 32'd1 << ST_ERR_K);
    endtask
endclass

class mac_misaligned_seq extends mac_base_seq;
    `uvm_object_utils(mac_misaligned_seq)
    function new(string name = "mac_misaligned_seq"); super.new(name); endfunction
    task body();
        npu_op_e loads [2] = '{OP_LDW, OP_LDI};
        foreach (loads[o]) begin
            expect_dropped(loads[o], 32'h0001_0004, 4, 1'b0, 32'd1 << ST_ERR_ALIGN);   // a[3:0] = 4
            expect_dropped(loads[o], 32'h0001_0001, 4, 1'b0, 32'd1 << ST_ERR_ALIGN);
            expect_dropped(loads[o], 32'h0001_FFF4, 8, 1'b0, 32'd1 << ST_ERR_ALIGN);   // also out of range: align first
            expect_dropped(loads[o], 32'h0001_0004, 6, 1'b0, 32'd1 << ST_ERR_K);       // K before alignment (D16)
        end
        expect_dropped(OP_MAC, 32'h0000_0003, 4, 1'b1, 0);                             // COMPUTE ignores the address
    endtask
endclass

class mac_addr_oob_seq extends mac_base_seq;
    `uvm_object_utils(mac_addr_oob_seq)
    function new(string name = "mac_addr_oob_seq"); super.new(name); endfunction
    task body();
        npu_op_e loads [2] = '{OP_LDW, OP_LDI};
        foreach (loads[o]) begin
            expect_dropped(loads[o], 32'h0000_FFF0, 4,    1'b0, 32'd1 << ST_ERR_ADDR);  // just below the DTCM
            expect_dropped(loads[o], 32'h0000_0000, 4,    1'b0, 32'd1 << ST_ERR_ADDR);  // ITCM
            expect_dropped(loads[o], 32'h0001_FFF0, 8,    1'b0, 32'd1 << ST_ERR_ADDR);  // one quad past the end
            expect_dropped(loads[o], 32'h0002_0000, 4,    1'b0, 32'd1 << ST_ERR_ADDR);  // starts at the end
            expect_dropped(loads[o], 32'h0001_F010, KMAX, 1'b0, 32'd1 << ST_ERR_ADDR);
            // legal edges, random data over the whole DTCM so every quad-index bit matters
            drain();
            clear_errors();                                    // err_addr of the cases above
            rng = 32'hA11C_E5E0 + o;
            fill_random(DTCM_BASE, DTCM_BYTES / 4);
            push(loads[o], DTCM_BASE, KMAX);                   // first quad
            push(loads[o], 32'h0001_F000, KMAX);               // ends exactly at the end
            push(loads[o], 32'h0001_8000, 64);
            push(loads[o], 32'h0001_FFF0, 4);                  // the last quad
            push(OP_MAC, 0, 4, 1'b1);
            check_all();
            expect_errs("legal edge loads", 0);
        end
    endtask
endclass

class mac_addr_wraps_32bit_seq extends mac_base_seq;
    `uvm_object_utils(mac_addr_wraps_32bit_seq)
    function new(string name = "mac_addr_wraps_32bit_seq"); super.new(name); endfunction
    task body();
        npu_op_e loads [2] = '{OP_LDW, OP_LDI};
        foreach (loads[o]) begin
            expect_dropped(loads[o], 32'hFFFF_FFF0, 8,    1'b0, 32'd1 << ST_ERR_ADDR);  // a + 4K wraps to 0x10
            expect_dropped(loads[o], 32'hFFFF_FFF0, 4,    1'b0, 32'd1 << ST_ERR_ADDR);  // wraps to exactly 0
            expect_dropped(loads[o], 32'hFFFF_FF00, KMAX, 1'b0, 32'd1 << ST_ERR_ADDR);
        end
    endtask
endclass

class mac_illegal_seq extends mac_base_seq;
    `uvm_object_utils(mac_illegal_seq)
    function new(string name = "mac_illegal_seq"); super.new(name); endfunction
    task body();
        bit [31:0] addrs [3] = '{W0, 32'h0001_0004, 32'hFFFF_FFF0};
        bit [31:0] ks    [4] = '{0, 4, 6, KMAX + 4};
        foreach (addrs[a]) foreach (ks[n])
            for (int clr = 0; clr < 2; clr++)
                expect_dropped(OP_ILLEGAL, addrs[a], ks[n], clr, 32'd1 << ST_ERR_ILLEGAL);   // D16: only err_illegal
    endtask
endclass

class mac_clr_vs_accum_seq extends mac_base_seq;
    `uvm_object_utils(mac_clr_vs_accum_seq)
    function new(string name = "mac_clr_vs_accum_seq"); super.new(name); endfunction
    task body();
        hand_setup();
        hand_run();
        push(OP_MAC, 0, 4, 1'b0);                      // accumulate: every value doubles
        check_all();
        for (int i = 0; i < 16; i++) expect_acc("accumulate", i, 2 * hand_acc[i]);
        push(OP_MAC, 0, 4, 1'b1);                      // clr: back to one copy
        check_all();
        check_hand("clr");
        push(OP_MAC, 0, 0, 1'b1);                      // K = 0 with clr is a no-op: acc kept (spec 6.3)
        check_hand("COMPUTE K=0 clr=1");
        // clr over several steps, with non-zero accumulators: only the first step loads, the later steps
        // add (a K=4 COMPUTE has one step and cannot tell "clr on step 0" from "clr on every step")
        drain();
        rng = 32'h00C1_7A11;
        fill_random(32'h0001_0100, 16);                // 4 weight quads
        fill_random(32'h0001_0200, 16);                // 4 input quads
        push(OP_LDW, 32'h0001_0100, 16);
        push(OP_LDI, 32'h0001_0200, 16);
        push(OP_MAC, 0, 16, 1'b0);                     // accumulate onto the hand results
        check_all();
        push(OP_MAC, 0, 16, 1'b1);                     // clr, 4 steps
        check_all();
        push(OP_MAC, 0, 16, 1'b0);                     // and accumulate once more: twice the clr result
        check_all();
    endtask
endclass

// 257 COMPUTEs of 2^24 each pass 2^31 (positive to negative) and 2^32 (back to 0), spec D5. Then
// +127 x -128 in every lane: each COMPUTE adds 1024 * -16256 = -0xFE_0000, so 129 of them give
// -0x7FFE_0000 = 0x8002_0000 and the 130th passes -2^31: -0x80FC_0000 = 0x7F04_0000 (negative to positive).
class mac_forced_wrap_seq extends mac_base_seq;
    `uvm_object_utils(mac_forced_wrap_seq)
    function new(string name = "mac_forced_wrap_seq"); super.new(name); endfunction
    task body();
        big_setup(32'h8080_8080);
        push(OP_MAC, 0, KMAX, 1'b1);
        for (int n = 1; n < 128; n++) push(OP_MAC, 0, KMAX, 1'b0);
        check_all();
        expect_all_acc("128 x 2^24", 32'h8000_0000);
        for (int n = 128; n < 256; n++) push(OP_MAC, 0, KMAX, 1'b0);
        check_all();
        expect_all_acc("256 x 2^24", 32'h0000_0000);
        push(OP_MAC, 0, KMAX, 1'b0);
        check_all();
        expect_all_acc("257 x 2^24", 32'h0100_0000);
        drain();
        fill(BIG_W, 1024, 32'h7F7F_7F7F);              // every weight lane +127
        fill(BIG_I, 1024, 32'h8080_8080);              // every input lane -128
        push(OP_LDW, BIG_W, KMAX);
        push(OP_LDI, BIG_I, KMAX);
        push(OP_MAC, 0, KMAX, 1'b1);
        for (int n = 1; n < 129; n++) push(OP_MAC, 0, KMAX, 1'b0);
        check_all();
        expect_all_acc("129 x -0xFE0000", 32'h8002_0000);
        push(OP_MAC, 0, KMAX, 1'b0);
        check_all();
        expect_all_acc("130 x -0xFE0000", 32'h7F04_0000);
    endtask
endclass

// 10 back-to-back pushes of long commands: the first is popped at once, the next 8 fill the FIFO, so
// pushes 1..9 go in on consecutive cycles and push 10 waits (cmd_ready = 0). npu_status is read between
// pushes 9 and 10, with the FIFO full. The final values depend on all ten, so a lost command shows up as
// a mismatch.
class mac_fifo_full_seq extends mac_base_seq;
    `uvm_object_utils(mac_fifo_full_seq)
    function new(string name = "mac_fifo_full_seq"); super.new(name); endfunction
    task body();
        int unsigned waits [10];
        bit [31:0]   st;
        rng = 32'h0F1F_0001;
        drain();
        fill_random(BIG_W, 1024);
        fill_random(BIG_I, 1024);
        push(OP_LDW, BIG_W, KMAX);           waits[0] = last_wait;
        push(OP_LDI, BIG_I, KMAX);           waits[1] = last_wait;
        push(OP_MAC, 0, KMAX, 1'b1);         waits[2] = last_wait;
        for (int n = 3; n < 10; n++) begin
            if (n == 9) begin
                csr_rd(CSR_NPU_STATUS, st);
                if (!st[ST_FIFO_FULL] || st[ST_FIFO_EMPTY] || !st[ST_BUSY])
                    `uvm_error("FIFO_FULL", $sformatf("npu_status %08x with the FIFO full: expected busy, fifo_full, not fifo_empty", st))
            end
            push(OP_MAC, 0, KMAX, 1'b0);
            waits[n] = last_wait;
        end
        for (int n = 0; n < 9; n++)
            if (waits[n] != 0) `uvm_error("FIFO_FULL", $sformatf("push %0d waited %0d cycles, expected 0", n + 1, waits[n]))
        if (waits[9] == 0) `uvm_error("FIFO_FULL", "push 10 was accepted at once: cmd_ready never dropped")
        else `uvm_info("FIFO_FULL", $sformatf("push 10 waited %0d cycles with cmd_ready = 0", waits[9]), UVM_LOW)
        check_all();
    endtask
endclass

// READ_RESULT right after three K=KMAX commands: rd_ready stays 0 until they are done (at least one
// quad per cycle each, so >= 768 cycles), then the data match npu_ref (scoreboard).
class mac_read_while_busy_seq extends mac_base_seq;
    `uvm_object_utils(mac_read_while_busy_seq)
    function new(string name = "mac_read_while_busy_seq"); super.new(name); endfunction
    task body();
        bit [31:0] d;
        rng = 32'h5EED_0002;
        big_random_setup();
        push(OP_MAC, 0, KMAX, 1'b1);
        read(5, d);
        if (last_wait < 3 * (KMAX / 4))
            `uvm_error("READ_BUSY", $sformatf("READ_RESULT returned after %0d cycles, at least %0d expected", last_wait, 3 * (KMAX / 4)))
        else `uvm_info("READ_BUSY", $sformatf("READ_RESULT waited %0d cycles with rd_ready = 0", last_wait), UVM_LOW)
        check_all();
    endtask
endclass

class mac_w1c_seq extends mac_base_seq;
    `uvm_object_utils(mac_w1c_seq)
    function new(string name = "mac_w1c_seq"); super.new(name); endfunction
    task set_all_errors(string where = "all four set");
        push(OP_MAC, 0, 6);                            // err_k
        push(OP_LDW, 32'h0001_FFF0, 8);                // err_addr
        push(OP_ILLEGAL, W0, 4);                       // err_illegal
        push(OP_LDI, 32'h0001_0004, 4);                // err_align
        expect_errs(where, ST_ERR_MASK);
    endtask
    task body();
        bit [31:0] bits [4] = '{32'd1 << ST_ERR_K, 32'd1 << ST_ERR_ADDR, 32'd1 << ST_ERR_ILLEGAL, 32'd1 << ST_ERR_ALIGN};
        bit [31:0] left;
        set_all_errors();
        csr_wr(CSR_NPU_STATUS, 0);                     // writing 0 clears nothing
        expect_errs("write 0", ST_ERR_MASK);
        csr_wr(CSR_NPU_STATUS, 32'h0000_0007);         // RO bits: no effect
        expect_errs("write RO bits", ST_ERR_MASK);
        left = ST_ERR_MASK;
        foreach (bits[b]) begin                        // one bit at a time
            csr_wr(CSR_NPU_STATUS, bits[b]);
            left &= ~bits[b];
            expect_errs($sformatf("clear bit %0d", b), left);
        end
        set_all_errors();
        set_all_errors("set while set");               // each of the four again: stays set (cg_err)
        csr_wr(CSR_NPU_STATUS, 32'hFFFF_FFFF);
        expect_errs("write all ones", 0);
        check_all();
    endtask
endclass

// A W1C issued while an erroneous command is still queued does not clear its error: the engine raises
// it later, in CHECK (spec 6.3 rule 4, D23). The predictor must apply each command at its CHECK.
class mac_w1c_inflight_seq extends mac_base_seq;
    `uvm_object_utils(mac_w1c_inflight_seq)
    function new(string name = "mac_w1c_inflight_seq"); super.new(name); endfunction
    task body();
        push(OP_MAC, 0, 6);                            // err_k, raised in CHECK two edges later
        csr_wr(CSR_NPU_STATUS, ST_ERR_MASK);           // W1C in the next cycle, before that CHECK
        expect_errs("W1C before CHECK", 32'd1 << ST_ERR_K);
        clear_errors();
        // the same behind a long LOAD: both erroneous commands are still in the FIFO at the W1C
        push(OP_LDW, BIG_W, KMAX);
        push(OP_ILLEGAL, W0, 4);                       // err_illegal
        push(OP_LDI, 32'h0001_0004, 4);                // err_align
        csr_wr(CSR_NPU_STATUS, ST_ERR_MASK);
        expect_errs("W1C while queued", (32'd1 << ST_ERR_ILLEGAL) | (32'd1 << ST_ERR_ALIGN));
    endtask
endclass

// D23: a W1C in the CHECK cycle of a command that sets the same bit; the set wins, the W1C still clears
// every other bit it names. The CHECK cycle is found as in Task 11's t_w1c: npu_status is read every
// cycle after a push until busy; the test then repeats the push and writes in that cycle instead.
class mac_d23_seq extends mac_base_seq;
    `uvm_object_utils(mac_d23_seq)
    function new(string name = "mac_d23_seq"); super.new(name); endfunction
    task body();
        bit [31:0]   st;
        int unsigned d;
        // calibration: d = cycles after the push before the CHECK cycle
        push(OP_MAC, 0, 6);
        d = 0;
        csr_rd(CSR_NPU_STATUS, st);
        while (!st[ST_BUSY] && d < 20) begin
            d++;
            csr_rd(CSR_NPU_STATUS, st);
        end
        if (!st[ST_BUSY]) `uvm_error("D23", "npu_status.busy never became 1 after a push")
        `uvm_info("D23", $sformatf("CHECK cycle: %0d cycle(s) after the push", d), UVM_LOW)
        drain();
        clear_errors();
        push(OP_ILLEGAL, W0, 4);                       // err_illegal and err_align, to be cleared by the W1C
        push(OP_LDI, 32'h0001_0004, 4);
        expect_errs("D23 setup", (32'd1 << ST_ERR_ILLEGAL) | (32'd1 << ST_ERR_ALIGN));
        push(OP_MAC, 0, 6);                            // err_k, set at the end of its CHECK cycle
        repeat (d) begin
            csr_rd(CSR_NPU_STATUS, st);
            if (st[ST_BUSY]) `uvm_error("D23", "the engine became busy earlier than in the calibration run")
        end
        csr_wr(CSR_NPU_STATUS, ST_ERR_MASK);           // in that CHECK cycle: set err_k and W1C all four
        expect_errs("D23: set wins", 32'd1 << ST_ERR_K);
        // the monitor saw the W1C and the pop at the same edge, so the case was really hit
        if (env.predictor.n_d23 != 1)
            `uvm_error("D23", $sformatf("W1C at the CHECK edge of the command seen %0d times, expected 1", env.predictor.n_d23))
    endtask
endclass

// D17, spec 6.4: npu_busy_cyc counts the cycles with npu_status.busy = 1 and wraps mod 2^32; a written
// value holds while idle; a write in a busy cycle wins over that cycle's increment. The busy cycles are
// counted through npu_status, one read per cycle, not taken from docs/mac_engine.md.
class mac_busy_cyc_seq extends mac_base_seq;
    `uvm_object_utils(mac_busy_cyc_seq)
    function new(string name = "mac_busy_cyc_seq"); super.new(name); endfunction

    // npu_status every cycle until the engine is idle with an empty FIFO; n = cycles with busy = 1
    task count_busy(string where, output int unsigned n);
        bit [31:0] st;
        n = 0;
        for (int c = 0; c < 4 * KMAX; c++) begin
            csr_rd(CSR_NPU_STATUS, st);
            if (st[ST_BUSY])            n++;
            else if (st[ST_FIFO_EMPTY]) return;
        end
        `uvm_error("BUSY_CYC", $sformatf("%s: the engine did not drain within %0d cycles", where, 4 * KMAX))
    endtask

    task expect_busy_cyc(string where, bit [31:0] want, int unsigned gap = 0);
        bit [31:0] v;
        csr_rd(CSR_NPU_BUSY_CYC, v, gap);
        if (v != want) `uvm_error("BUSY_CYC", $sformatf("%s: npu_busy_cyc = %08x, expected %08x", where, v, want))
    endtask

    localparam bit [31:0] V0 = 32'hFFFF_FF80;          // the COMPUTE below wraps it past 2^32
    localparam bit [31:0] V1 = 32'h1234_5678;

    task body();
        bit [31:0]   st;
        int unsigned n, n_after;
        rng = 32'hB05C_0001;
        big_random_setup();
        drain();
        csr_wr(CSR_NPU_BUSY_CYC, V0);
        expect_busy_cyc("written while idle", V0);
        expect_busy_cyc("20 idle cycles later", V0, 20);
        // one COMPUTE: the counter grows by exactly the busy cycles seen
        push(OP_MAC, 0, KMAX, 1'b1);
        count_busy("COMPUTE K=KMAX", n);
        `uvm_info("BUSY_CYC", $sformatf("COMPUTE K=%0d: %0d busy cycles seen through npu_status", KMAX, n), UVM_LOW)
        if (n == 0) `uvm_error("BUSY_CYC", "COMPUTE K=KMAX: npu_status.busy was never 1")
        expect_busy_cyc("after COMPUTE K=KMAX", V0 + n);
        // a write in a busy cycle: busy in cycle c (read), write in c+1, read back in c+2. The engine runs
        // one command, so its busy cycles are contiguous: a busy cycle after c+2 proves c+1 and c+2 busy.
        push(OP_MAC, 0, KMAX, 1'b0);
        n = 0;
        csr_rd(CSR_NPU_STATUS, st);
        while (!st[ST_BUSY] && n < 20) begin
            n++;
            csr_rd(CSR_NPU_STATUS, st);
        end
        if (!st[ST_BUSY]) `uvm_error("BUSY_CYC", "npu_status.busy never became 1 after a push")
        csr_wr(CSR_NPU_BUSY_CYC, V1);
        expect_busy_cyc("written in a busy cycle", V1);        // neither V1 + 1 nor the old value + 1
        count_busy("rest of the COMPUTE", n_after);
        if (n_after == 0) `uvm_error("BUSY_CYC", "the COMPUTE ended too early: the write cycle is not shown to be busy")
        expect_busy_cyc("after the write in a busy cycle", V1 + 1 + n_after);
    endtask
endclass

// Self-check of cg_addr (review finding F9a): first_quad counts only a LOAD that executes from DTCM_BASE.
// A LOAD at DTCM_BASE that CHECK drops (K = 6, err_k) must leave the bin empty; a legal one must fill it.
// cp_first has the single bin first_quad, so its coverage is 0 or 100.
class mac_addr_cov_dropped_seq extends mac_base_seq;
    `uvm_object_utils(mac_addr_cov_dropped_seq)
    function new(string name = "mac_addr_cov_dropped_seq"); super.new(name); endfunction
    task body();
        real c;
        hand_setup();
        push(OP_LDW, DTCM_BASE, 6);
        expect_errs("LDW at DTCM_BASE, K = 6", 32'd1 << ST_ERR_K);
        c = env.coverage.cg_addr.cp_first.get_coverage();
        if (c != 0.0) `uvm_error("COV_ADDR", $sformatf("dropped LOAD at DTCM_BASE hit first_quad (cp_first %0.1f%%)", c))
        push(OP_LDW, DTCM_BASE, 4);
        drain();
        c = env.coverage.cg_addr.cp_first.get_coverage();
        if (c != 100.0) `uvm_error("COV_ADDR", $sformatf("legal LOAD at DTCM_BASE missed first_quad (cp_first %0.1f%%)", c))
    endtask
endclass

// Review Focus 2: a DTCM-wide workload; the mirror check itself runs in mac_env.check_phase of every test.
class mac_mem_mirror_check_seq extends mac_base_seq;
    `uvm_object_utils(mac_mem_mirror_check_seq)
    function new(string name = "mac_mem_mirror_check_seq"); super.new(name); endfunction
    task body();
        rng = 32'h3141_5926;
        drain();
        fill_random(DTCM_BASE, DTCM_BYTES / 4);
        push(OP_LDW, 32'h0001_C000, KMAX);
        push(OP_LDI, 32'h0001_4000, KMAX);
        push(OP_MAC, 0, KMAX, 1'b1);
        check_all();
        drain();
        for (int n = 0; n < 64; n++) mem_write(DTCM_BASE + 4 * (next_rand() % (DTCM_BYTES / 4)), next_rand());
        push(OP_LDW, 32'h0001_0000, KMAX);
        push(OP_MAC, 0, KMAX, 1'b0);
        check_all();
    endtask
endclass

// Self-test of the mirror check (expected to fail with MEM_MIRROR only): one responder word is changed
// without npu_ref after the last LOAD, so only the end-of-test hash comparison can see it.
class mac_mem_mirror_inject_seq extends mac_mem_mirror_check_seq;
    `uvm_object_utils(mac_mem_mirror_inject_seq)
    function new(string name = "mac_mem_mirror_inject_seq"); super.new(name); endfunction
    task body();
        super.body();
        drain();
        env.dtcm_agent.corrupt_word(12345, ~env.dtcm_agent.read_word(12345));
    endtask
endclass

// Self-test of the WAR check (expected to fail with WAR_RULE only): a DTCM write while a LOAD is queued
// or running breaks spec 6.3 rule 5. The word is outside every LOAD of the test, so no result changes.
class mac_war_inject_seq extends mac_base_seq;
    `uvm_object_utils(mac_war_inject_seq)
    function new(string name = "mac_war_inject_seq"); super.new(name); endfunction
    task body();
        drain();
        push(OP_LDW, BIG_W, KMAX);
        mem_write(DTCM_BASE + 32'h8000, 32'hDEAD_BEEF);
        drain();
    endtask
endclass

// Review Focus 4 (expected to fail with UNWRITTEN_ENTRY only): COMPUTE K=8 after reset with one quad
// loaded into each buffer reads WBUF[1]/IBUF[1], which no LOAD wrote (spec 7.2).
class mac_unwritten_entry_flagged_seq extends mac_base_seq;
    `uvm_object_utils(mac_unwritten_entry_flagged_seq)
    function new(string name = "mac_unwritten_entry_flagged_seq"); super.new(name); endfunction
    task body();
        hand_setup();
        push(OP_LDW, W0, 4);
        push(OP_LDI, I0, 4);
        push(OP_MAC, 0, 8, 1'b1);
        drain();
    endtask
endclass

// Task 19: every cell of cg_cmd's op x K bin x K mod 4 cross (spec 10.5, D24), deterministically. For each
// op, K runs over both edges of every K bin in each residue mod 4: 0; 1..7; 8..11 and 60..63; 64..67 and
// KMAX-4..KMAX-1; KMAX; KMAX+1..KMAX+4 and 0xFFFF_FFFC..0xFFFF_FFFF. The random mix reaches OP_ILLEGAL
// with an illegal K only a few times in 200 seeds, so these cells are closed here. Each command runs
// alone and its error bits are checked against the spec 6.3 table (D16: ILLEGAL sets err_illegal only,
// whatever its K); the scoreboard also compares every result and npu_status with npu_ref.
class mac_k_cross_seq extends mac_base_seq;
    `uvm_object_utils(mac_k_cross_seq)
    function new(string name = "mac_k_cross_seq"); super.new(name); endfunction
    task body();
        npu_op_e   ops [4] = '{OP_LDW, OP_LDI, OP_MAC, OP_ILLEGAL};
        bit [31:0] ks [$];
        bit [31:0] want, addr;
        ks.push_back(0);
        for (int unsigned k = 1; k <= 7; k++) ks.push_back(k);
        for (int unsigned m = 0; m < 4; m++) begin
            ks.push_back(8 + m);
            ks.push_back(60 + m);
            ks.push_back(64 + m);
            ks.push_back(KMAX - 4 + m);
            ks.push_back(KMAX + 1 + m);
            ks.push_back(32'hFFFF_FFFC + m);
        end
        ks.push_back(KMAX);
        rng = 32'h0C0F_FEE5;
        big_random_setup();                            // all WBUF/IBUF entries written: no COMPUTE reads unwritten ones
        foreach (ops[o]) begin
            foreach (ks[n]) begin
                // a LOAD at DTCM_BASE is in range for every legal K (4 * KMAX bytes); COMPUTE and ILLEGAL
                // ignore the address (spec 6.3)
                addr = (ops[o] inside {OP_LDW, OP_LDI}) ? DTCM_BASE : W0;
                if (ops[o] == OP_ILLEGAL)                          want = 32'd1 << ST_ERR_ILLEGAL;
                else if (ks[n] > KMAX || ks[n][1:0] != 2'b00)      want = 32'd1 << ST_ERR_K;
                else                                               want = 0;
                push(ops[o], addr, ks[n], 1'(n % 2));
                expect_errs($sformatf("%s K %0d", ops[o].name(), ks[n]), want);
                if (want != 0) clear_errors();
            end
            check_all();
        end
    endtask
endclass

// Task 19 (deferred review minor F9b): a reset in the middle of a LOAD must not leave cg_state with a
// transition from the state before the reset to IDLE after it (it would hit load_idle although no LOAD
// finished). After the reset only idle_check and check_load (2 of the 6 cp_tr bins) may be covered;
// a LOAD that does finish afterwards must then hit load_idle (3 of 6), so the check is not vacuous. The
// test drives rst_n itself, 1 ns after an edge as mac_tb_top does; it also exercises the predictor's
// RESET path (npu_ref_reset and the memory mirror) in the middle of a test.
class mac_reset_midrun_seq extends mac_base_seq;
    `uvm_object_utils(mac_reset_midrun_seq)
    function new(string name = "mac_reset_midrun_seq"); super.new(name); endfunction

    task expect_tr_cov(string where, real want);
        real c = env.coverage.cg_state.cp_tr.get_coverage();
        if (c < want - 0.1 || c > want + 0.1)
            `uvm_error("COV_STATE", $sformatf("%s: cg_state.cp_tr %0.2f%%, expected %0.2f%%", where, c, want))
    endtask

    task body();
        virtual mac_cmd_if vif = env.cmd_agent.drv.vif;
        bit [31:0] st;
        hand_setup();
        push(OP_LDW, BIG_W, KMAX);                     // IDLE -> CHECK -> LOAD of 256 quads
        repeat (8) csr_rd(CSR_NPU_STATUS, st);         // a few cycles into the LOAD
        if (!st[ST_BUSY]) `uvm_error("RESET_MIDRUN", "the LOAD is not running when the reset is applied")
        expect_tr_cov("before the reset", 100.0 * 2 / 6);
        #1 vif.rst_n = 1'b0;
        repeat (3) @(posedge vif.clk);
        #1 vif.rst_n = 1'b1;
        repeat (4) csr_rd(CSR_NPU_STATUS, st);         // idle cycles after the reset: IDLE is sampled
        expect_tr_cov("after a reset in LOAD", 100.0 * 2 / 6);
        push(OP_LDW, W0, 4);                           // a LOAD that finishes: load_idle
        drain();
        expect_tr_cov("after a complete LOAD", 100.0 * 3 / 6);
    endtask
endclass

// ==== Step 6: random stimulus (spec 10.3 mac_rand_seq) ===============================================
//
// mac_rand_cmd is one random step of mac_rand_seq: a command push, a READ_RESULT or a CSR access. All of
// its choices are SystemVerilog constraints solved by randomize(), and the operand data come from
// $urandom, so -sv_seed alone reproduces a run (run.py --seeds N passes -sv_seed 1..N).
//
//   kind     LDW 30 / LDI 30 / MAC 30 / ILLEGAL 2 / READ 8 (spec 10.3, plan Task 16 Step 6), plus CSR
//            reads 3 and CSR writes 2 on top, so a W1C in flight and D23 get random coverage too; the
//            ratios between the five command kinds are those of the plan for the ordinary steps. Task 19
//            adds two targeted steps, D23 2 and BUSY_WR 2 (about 7 of each per 400-step seed); each D23
//            step pushes one more command (a quarter of them ILLEGAL), which the summary line does not
//            count in its pushes, K bins or illegal-K %:
//            D23      drain (a READ), push one erroneous command, and W1C npu_status in exactly its CHECK
//                     cycle (cycles counted from the push as measured at the start, as mac_d23 does), then
//                     read npu_status in the next cycle: the bit the command sets must be 1 (the set wins,
//                     D23) and every other named error bit cleared (scoreboard). Which error (err_k with
//                     LDW/LDI/MAC, err_addr, err_illegal, err_align), its K/address and the other W1C bits
//                     are random. The step fails if the W1C missed that edge (predictor n_d23).
//            BUSY_WR  write a random value to npu_busy_cyc at a random point (the engine is busy in most
//                     cycles of this mix) and read it in the next cycle: exactly the written value (D17:
//                     the write wins over that cycle's increment); npu_ref keeps no count (spec 10.2)
//   K        k_ok 95 % (legal: 0 or a multiple of 4 up to KMAX), 5 % illegal; then a bin of cg_cmd
//            (spec 10.5, D24): legal K: {0} 5, [1:7] (that is K = 4) 15, [8:63] 30, [64:KMAX-1] 35,
//            {KMAX} 15; illegal K: [1:7], [8:63], [64:KMAX-1] (not a multiple of 4) and > KMAX, 1 each.
//            The same K mix is used for every op, ILLEGAL included (D16: it ignores K).
//   COMPUTE  K/4 never exceeds the entries written since reset in both WBUF and IBUF (spec 7.2): the
//            sequence passes that count in as max_steps. The predictor's UNWRITTEN_ENTRY check stays
//            as the safety net; a random run that raises it is a sequence bug.
//   address  LOADs: 90 % aligned and in range (70 anywhere, 10 at the first quad, 10 ending exactly at
//            the end of the DTCM), 10 % not (4 misaligned, 2 below DTCM_BASE, 2 past the end, 1 one
//            quad past the end, 1 at the top of the 32-bit space). COMPUTE and ILLEGAL ignore the
//            address (spec 6.3), so it is any 32-bit value.
//   gap      0..20 idle cycles before the step: 0 40 %, 1..3 30 %, 4..20 30 %
//   READ     random idx; 25 % of them are followed by all 16 results and npu_status (check_all), and
//            30 % by a rewrite of a DTCM block (see mac_rand_seq)
//   CSR      reads: 0x7C0 70, 0x7C1 15, any other address 15 (reads 0, D21); writes: 0x7C0 80 (W1C
//            of random bits, or of all four error bits in 25 % of them), 0x7C1 10, other 10 (ignored).
//            50 % of the writes to 0x7C0 are followed by a gap-0 read of 0x7C0: without that read a
//            later set of the same sticky bit hides a wrong W1C result (D23, a W1C in flight)
typedef enum {RND_LDW, RND_LDI, RND_MAC, RND_ILLEGAL, RND_READ, RND_CSR_RD, RND_CSR_WR, RND_D23,
              RND_BUSY_WR} mac_rand_kind_e;
typedef enum {D23_ERR_K, D23_ERR_ADDR, D23_ERR_ILLEGAL, D23_ERR_ALIGN} mac_rand_d23_e;
typedef enum {RK_0, RK_1_7, RK_8_63, RK_64_KMAX1, RK_KMAX, RK_OVER} mac_rand_kbin_e;
typedef enum {RA_IN, RA_FIRST, RA_LAST, RA_MISALIGNED, RA_BELOW, RA_PAST, RA_ONE_PAST, RA_TOP} mac_rand_acls_e;

class mac_rand_cmd extends uvm_object;
    `uvm_object_utils(mac_rand_cmd)

    localparam bit [31:0] DTCM_END = DTCM_BASE + DTCM_BYTES;    // one past the last byte

    rand mac_rand_kind_e kind;
    rand bit             k_ok;          // K is legal: 0, or a multiple of 4 up to KMAX
    rand mac_rand_kbin_e k_bin;
    rand bit [31:0]      k;
    rand mac_rand_acls_e a_cls;
    rand bit [31:0]      addr;
    rand bit             clr;
    rand int unsigned    gap;
    rand bit [3:0]       idx;
    rand bit             read_all;      // READ: check_all() after it
    rand bit             refresh;       // READ: rewrite a DTCM block after it (the engine is drained)
    rand bit [11:0]      csr_addr;
    rand bit             w1c_all;       // CSR write to npu_status: all four error bits
    rand bit [31:0]      csr_wdata;
    rand bit             rd_after_w1c;  // CSR write to npu_status: read npu_status right after it
    rand mac_rand_d23_e  d23_err;       // D23 step: the error its command raises
    rand bit [1:0]       d23_op;        // D23 step, err_k: 0 LDW, 1 LDI, 2/3 MAC; err_addr/err_align: [0] LDW/LDI

    int unsigned max_steps;             // input: min(WBUF, IBUF) entries written since reset

    constraint c_kind {
        kind dist {RND_LDW := 30, RND_LDI := 30, RND_MAC := 30, RND_ILLEGAL := 2, RND_READ := 8,
                   RND_CSR_RD := 3, RND_CSR_WR := 2, RND_D23 := 2, RND_BUSY_WR := 2};
    }

    // K: legal or not first, then the cg_cmd bin, then the value (the solve order keeps the weights).
    // A D23 step picks its error before k_ok, so the four errors are equally likely.
    constraint c_k_order {
        solve kind before d23_err; solve d23_err before k_ok; solve k_ok before k_bin; solve k_bin before k;
    }

    // D23 step: K and address of a command that CHECK drops with exactly the chosen error (spec 6.3 table,
    // D16 order K, alignment, range); every sum stays below 2^32 (k <= KMAX, addr < 2^31)
    constraint c_d23 {
        if (kind == RND_D23) {
            (d23_err == D23_ERR_K)              -> !k_ok;
            (d23_err inside {D23_ERR_ADDR, D23_ERR_ALIGN}) -> (k_ok && k != 0);
            (d23_err == D23_ERR_ADDR)           -> (addr[3:0] == 4'h0 &&
                                                    (addr < DTCM_BASE || (addr < 32'h8000_0000 && addr + 4 * k > DTCM_END)));
            (d23_err == D23_ERR_ALIGN)          -> (addr[3:0] != 4'h0);
        }
    }
    constraint c_k_ok    { k_ok dist {1 := 95, 0 := 5}; }
    constraint c_k_bin {
        if (k_ok) k_bin dist {RK_0 := 5, RK_1_7 := 15, RK_8_63 := 30, RK_64_KMAX1 := 35, RK_KMAX := 15};
        else      k_bin dist {RK_1_7 := 1, RK_8_63 := 1, RK_64_KMAX1 := 1, RK_OVER := 1};
    }
    constraint c_k {
        k_ok == (k <= KMAX && k[1:0] == 2'b00);
        (k_bin == RK_0)        -> (k == 0);
        (k_bin == RK_1_7)      -> (k inside {[1:7]});
        (k_bin == RK_8_63)     -> (k inside {[8:63]});
        (k_bin == RK_64_KMAX1) -> (k inside {[64:KMAX - 1]});
        (k_bin == RK_KMAX)     -> (k == KMAX);
        (k_bin == RK_OVER)     -> (k > KMAX);
        if (k_bin == RK_OVER)
            k dist {[KMAX + 1:KMAX + 4] :/ 1, [KMAX + 5:4 * KMAX] :/ 1, [4 * KMAX + 1:32'hFFFF_FFFF] :/ 1};
    }
    // spec 7.2: no COMPUTE reads a WBUF/IBUF entry not written since reset (K = 0 and a dropped K read none)
    constraint c_written { (kind == RND_MAC && k_ok && k != 0) -> (k <= 4 * max_steps); }

    // LOAD addresses; with an illegal K or K = 0 the "last" and "one past" cases use the last quad and
    // DTCM_END. Every sum below stays far from 2^32 (k <= KMAX where it is used, addr < 2^31).
    constraint c_a_cls {
        a_cls dist {RA_IN := 70, RA_FIRST := 10, RA_LAST := 10, RA_MISALIGNED := 4, RA_BELOW := 2,
                    RA_PAST := 2, RA_ONE_PAST := 1, RA_TOP := 1};
    }
    constraint c_addr {
        if (kind inside {RND_LDW, RND_LDI}) {
            (a_cls inside {RA_IN, RA_FIRST, RA_LAST}) -> (addr[3:0] == 4'h0 && addr >= DTCM_BASE && addr < DTCM_END);
            (a_cls == RA_IN && k_ok)                    -> (addr + 4 * k <= DTCM_END);
            (a_cls == RA_FIRST)                         -> (addr == DTCM_BASE);
            (a_cls == RA_LAST && k_ok && k != 0)        -> (addr == DTCM_END - 4 * k);
            (a_cls == RA_LAST && !(k_ok && k != 0))     -> (addr == DTCM_END - QUAD_BYTES);
            (a_cls == RA_MISALIGNED)                    -> (addr[3:0] != 4'h0 && addr >= DTCM_BASE && addr < DTCM_END);
            (a_cls == RA_BELOW)                         -> (addr[3:0] == 4'h0 && addr < DTCM_BASE);
            (a_cls == RA_PAST)                          -> (addr[3:0] == 4'h0 && addr >= DTCM_BASE && addr < 32'h8000_0000);
            (a_cls == RA_PAST && k_ok && k != 0)        -> (addr + 4 * k > DTCM_END + QUAD_BYTES);
            (a_cls == RA_PAST && !(k_ok && k != 0))     -> (addr >= DTCM_END);
            (a_cls == RA_ONE_PAST && k_ok && k != 0)    -> (addr == DTCM_END + QUAD_BYTES - 4 * k);
            (a_cls == RA_ONE_PAST && !(k_ok && k != 0)) -> (addr == DTCM_END);
            (a_cls == RA_TOP)                           -> (addr[3:0] == 4'h0 && addr >= 32'hFFFF_F000);
        }
    }

    constraint c_gap  { gap dist {0 := 40, [1:3] :/ 30, [4:20] :/ 30}; }
    constraint c_read { read_all dist {1 := 25, 0 := 75}; refresh dist {1 := 30, 0 := 70}; }
    constraint c_csr {
        if (kind == RND_CSR_WR)
            csr_addr dist {CSR_NPU_STATUS := 80, CSR_NPU_BUSY_CYC := 10,
                           [0:CSR_NPU_STATUS - 1] :/ 5, [CSR_NPU_BUSY_CYC + 1:12'hFFF] :/ 5};
        else
            csr_addr dist {CSR_NPU_STATUS := 70, CSR_NPU_BUSY_CYC := 15,
                           [0:CSR_NPU_STATUS - 1] :/ 8, [CSR_NPU_BUSY_CYC + 1:12'hFFF] :/ 7};
        w1c_all dist {1 := 25, 0 := 75};
        (csr_addr == CSR_NPU_STATUS && w1c_all) -> (csr_wdata == ST_ERR_MASK);
        rd_after_w1c dist {1 := 50, 0 := 50};
    }

    function new(string name = "mac_rand_cmd");
        super.new(name);
    endfunction
endclass

// mac_rand_seq: n_items random steps (+MAC_RAND_N=<n>, default 400) on a DTCM filled with random data.
//
// Data. The whole DTCM is filled at the start; after 30 % of the READs (READ_RESULT drains the engine,
// so every queued LOAD has run: the WAR rule, spec 6.3 rule 5) a random block of 1..256 quads is
// rewritten. Every operand byte is one of {-128, -1, 0, 1, 127} with probability 20 % (each 4 %), else
// uniform over the other 251 values. A rewritten block is all zero in 10 % of the cases (so a COMPUTE
// with clr can leave every accumulator 0: cg_cmd acc-nonzero-before = 0) and one corner value in every
// lane in another 10 %.
//
// Written entries. The sequence counts, in program order, the WBUF and IBUF entries written since reset
// (an executing LOAD of K writes 0..K/4-1; mac_cmd_fate, as in the predictor) and constrains COMPUTE with
// the smaller count (spec 7.2). The engine executes in program order, so the count at the push is the
// count at its CHECK.
//
// Checks come from the env: every READ and every npu_status read against npu_ref, the SVA, the WAR
// check in write_word and the end-of-test DTCM mirror. The summary line gives the mix actually drawn and
// a signature of the whole stimulus stream (the same seed gives the same signature).
class mac_rand_seq extends mac_base_seq;
    `uvm_object_utils(mac_rand_seq)

    int unsigned n_items = 400;
    int unsigned w_written, i_written;          // WBUF/IBUF entries 0..n-1 written since reset
    int unsigned n_kind  [RND_BUSY_WR + 1];     // draws per enum value, indexed by the enum
    int unsigned n_kbin  [RK_OVER + 1];
    int unsigned n_acls  [RA_TOP + 1];
    int unsigned n_d23err [D23_ERR_ALIGN + 1];
    int unsigned n_k_bad, n_push, n_refresh, n_rd_w1c;
    int unsigned check_delay;                   // cycles from a push into the drained engine to its CHECK
    bit [31:0]   sig = 32'h811C_9DC5;           // FNV-1a over the stimulus stream

    localparam bit [7:0] CORNERS [5] = '{8'h80, 8'hFF, 8'h00, 8'h01, 8'h7F};

    function new(string name = "mac_rand_seq"); super.new(name); endfunction

    // one operand byte: a corner value with probability 20 %, else one of the 251 others
    function bit [7:0] rand_lane();
        int unsigned n;
        if ($urandom_range(99) < 20) return CORNERS[$urandom_range(4)];
        n = $urandom_range(250);
        return (n < 125) ? 8'(n + 2) : 8'(n - 125 + 32'h81);    // 0x02..0x7E, then 0x81..0xFE
    endfunction

    // pattern 0: biased random lanes; 1: all zero; 2: one corner value in every lane
    function void fill_quads(int unsigned q0, int unsigned nq, int unsigned pattern);
        bit [7:0]  c = CORNERS[$urandom_range(4)];
        bit [31:0] d;
        for (int unsigned q = q0; q < q0 + nq && q < DTCM_QUADS; q++)
            for (int unsigned w = 0; w < 4; w++) begin
                case (pattern)
                    0:       d = {rand_lane(), rand_lane(), rand_lane(), rand_lane()};
                    1:       d = '0;
                    default: d = {4{c}};
                endcase
                mem_write(DTCM_BASE + QUAD_BYTES * q + 4 * w, d);
            end
    endfunction

    function void refresh_block();
        int unsigned p = $urandom_range(99);
        fill_quads($urandom_range(DTCM_QUADS - 1), $urandom_range(256, 1), (p < 80) ? 0 : (p < 90) ? 1 : 2);
        n_refresh++;
    endfunction

    function void note(bit [31:0] v);
        sig = mac_env::fnv1a(sig, v);
    endfunction

    // check_delay = cycles after a push into the drained engine before that command's CHECK cycle, seen as
    // the first npu_status read with busy = 1 (as in mac_d23). COMPUTE K = 0 passes CHECK and changes nothing.
    task measure_check_delay();
        bit [31:0] st;
        drain();
        push(OP_MAC, 0, 0, 1'b0);
        check_delay = 0;
        csr_rd(CSR_NPU_STATUS, st);
        while (!st[ST_BUSY] && check_delay < 20) begin
            check_delay++;
            csr_rd(CSR_NPU_STATUS, st);
        end
        if (!st[ST_BUSY]) `uvm_fatal("D23", "npu_status.busy never became 1 after a push into the drained engine")
        `uvm_info("D23", $sformatf("CHECK cycle: %0d cycle(s) after a push into the drained engine", check_delay), UVM_LOW)
    endtask

    // the D23 step (see the header): the W1C lands in the CHECK cycle of an erroneous command
    task d23_step(mac_rand_cmd c);
        npu_op_e       op;
        mac_cmd_fate_e fate;
        bit [31:0]     st, w1c;
        int unsigned   bit_pos, n0;
        case (c.d23_err)
            D23_ERR_ILLEGAL: op = OP_ILLEGAL;
            D23_ERR_K:       op = (c.d23_op == 0) ? OP_LDW : (c.d23_op == 1) ? OP_LDI : OP_MAC;
            default:         op = c.d23_op[0] ? OP_LDI : OP_LDW;
        endcase
        fate = mac_cmd_fate(op, c.addr, c.k);
        case (fate)
            CMD_ILLEGAL:   bit_pos = ST_ERR_ILLEGAL;
            CMD_ERR_K:     bit_pos = ST_ERR_K;
            CMD_ERR_ALIGN: bit_pos = ST_ERR_ALIGN;
            CMD_ERR_ADDR:  bit_pos = ST_ERR_ADDR;
            default: `uvm_fatal("D23", $sformatf("D23 step: %s addr %08x K %0d raises no error (sequence bug)",
                                                 op.name(), c.addr, c.k))
        endcase
        w1c = c.csr_wdata | (32'd1 << bit_pos);         // the bit being set, plus random others
        note(op); note(c.addr); note(c.k); note(c.clr); note(w1c);
        n_d23err[c.d23_err]++;
        read(c.idx, st, c.gap);                         // drain: the cycle count below starts from idle
        n0 = env.predictor.n_d23;
        push(op, c.addr, c.k, c.clr, 0);
        repeat (check_delay) begin
            csr_rd(CSR_NPU_STATUS, st, 0);
            if (st[ST_BUSY]) `uvm_error("D23", "the engine became busy earlier than measured at the start")
        end
        csr_wr(CSR_NPU_STATUS, w1c, 0);                 // in the CHECK cycle: the set and the W1C meet
        csr_rd(CSR_NPU_STATUS, st, 0);                  // the next cycle, before anything can set the bit again
        if (!st[bit_pos])
            `uvm_error("D23", $sformatf("%s addr %08x K %0d with W1C %08x in its CHECK cycle: npu_status %08x, bit %0d clear (the set must win)",
                       op.name(), c.addr, c.k, w1c, st, bit_pos))
        if (env.predictor.n_d23 != n0 + 1)
            `uvm_error("D23", $sformatf("the W1C did not meet the command's CHECK edge (predictor n_d23 %0d -> %0d)",
                       n0, env.predictor.n_d23))
    endtask

    task body();
        mac_rand_cmd c = mac_rand_cmd::type_id::create("c");
        bit [31:0]   d;
        npu_op_e     op;
        void'($value$plusargs("MAC_RAND_N=%d", n_items));
        measure_check_delay();
        drain();
        fill_quads(0, DTCM_QUADS, 0);
        for (int unsigned n = 0; n < n_items; n++) begin
            c.max_steps = (w_written < i_written) ? w_written : i_written;
            if (!c.randomize()) `uvm_fatal("RAND", $sformatf("mac_rand_cmd randomize() failed at step %0d", n))
            n_kind[c.kind]++;
            note(c.kind); note(c.gap);
            case (c.kind)
                RND_LDW, RND_LDI, RND_MAC, RND_ILLEGAL: begin
                    op = (c.kind == RND_LDW) ? OP_LDW : (c.kind == RND_LDI) ? OP_LDI :
                         (c.kind == RND_MAC) ? OP_MAC : OP_ILLEGAL;
                    n_push++;
                    n_kbin[c.k_bin]++;
                    if (!c.k_ok) n_k_bad++;
                    if (op inside {OP_LDW, OP_LDI}) n_acls[c.a_cls]++;
                    note(c.addr); note(c.k); note(c.clr);
                    push(op, c.addr, c.k, c.clr, c.gap);
                    if (mac_cmd_fate(op, c.addr, c.k) == CMD_EXEC) begin
                        if (op == OP_LDW && c.k / 4 > w_written) w_written = c.k / 4;
                        if (op == OP_LDI && c.k / 4 > i_written) i_written = c.k / 4;
                    end
                end
                RND_READ: begin
                    note(c.idx); note(c.read_all); note(c.refresh);
                    read(c.idx, d, c.gap);
                    if (c.read_all) check_all();
                    if (c.refresh) refresh_block();             // drained by the READ above
                end
                RND_CSR_RD: begin
                    note(c.csr_addr);
                    csr_rd(c.csr_addr, d, c.gap);
                end
                RND_CSR_WR: begin
                    note(c.csr_addr); note(c.csr_wdata);
                    csr_wr(c.csr_addr, c.csr_wdata, c.gap);
                    if (c.csr_addr == CSR_NPU_STATUS) begin
                        note(c.rd_after_w1c);
                        if (c.rd_after_w1c) begin               // in the next cycle: the W1C result
                            csr_rd(CSR_NPU_STATUS, d, 0);       // before another set can hide it
                            n_rd_w1c++;
                        end
                    end
                end
                RND_D23: d23_step(c);
                RND_BUSY_WR: begin
                    note(c.csr_wdata);
                    csr_wr(CSR_NPU_BUSY_CYC, c.csr_wdata, c.gap);
                    csr_rd(CSR_NPU_BUSY_CYC, d, 0);             // the next cycle: the written value, no increment
                    if (d !== c.csr_wdata)
                        `uvm_error("BUSY_CYC", $sformatf("npu_busy_cyc written %08x, read %08x in the next cycle (D17: the write wins)",
                                   c.csr_wdata, d))
                end
                default: `uvm_fatal("RAND", $sformatf("mac_rand_cmd kind %s not handled", c.kind.name()))
            endcase
        end
        drain();
        `uvm_info("MAC_RAND", $sformatf({"D23 steps %0d (err_k %0d, err_addr %0d, err_illegal %0d, err_align %0d); ",
                  "npu_busy_cyc write-and-read steps %0d"}, n_kind[RND_D23], n_d23err[D23_ERR_K], n_d23err[D23_ERR_ADDR],
                  n_d23err[D23_ERR_ILLEGAL], n_d23err[D23_ERR_ALIGN], n_kind[RND_BUSY_WR]), UVM_LOW)
        `uvm_info("MAC_RAND", $sformatf({"%0d steps: LDW %0d, LDI %0d, MAC %0d, ILLEGAL %0d, READ %0d, CSR_RD %0d, ",
                  "CSR_WR %0d (%0d npu_status reads right after a W1C); %0d pushes, illegal K %0d (%0.1f%%); ",
                  "K bins 0:%0d 1-7:%0d 8-63:%0d 64-KMAX-1:%0d ",
                  "KMAX:%0d >KMAX:%0d; LOAD address in/first/last %0d/%0d/%0d, misaligned %0d, below %0d, ",
                  "past %0d, one past %0d, top %0d; %0d DTCM blocks rewritten; entries written WBUF %0d IBUF %0d; ",
                  "stimulus signature %08x"},
                  n_items, n_kind[RND_LDW], n_kind[RND_LDI], n_kind[RND_MAC], n_kind[RND_ILLEGAL],
                  n_kind[RND_READ], n_kind[RND_CSR_RD], n_kind[RND_CSR_WR], n_rd_w1c, n_push, n_k_bad,
                  (n_push == 0) ? 0.0 : 100.0 * n_k_bad / n_push,
                  n_kbin[RK_0], n_kbin[RK_1_7], n_kbin[RK_8_63], n_kbin[RK_64_KMAX1], n_kbin[RK_KMAX], n_kbin[RK_OVER],
                  n_acls[RA_IN], n_acls[RA_FIRST], n_acls[RA_LAST], n_acls[RA_MISALIGNED], n_acls[RA_BELOW],
                  n_acls[RA_PAST], n_acls[RA_ONE_PAST], n_acls[RA_TOP], n_refresh, w_written, i_written, sig),
                  UVM_LOW)
    endtask
endclass
