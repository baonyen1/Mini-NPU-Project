// mac_seq_lib.sv - sequences of mac_env (Phase 2 Task 16, Step 1: the directed tests of spec 10.3).
// Included by mac_test_pkg.
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

    task read(bit [3:0] idx, output bit [31:0] data);
        mac_cmd_item it = mac_cmd_item::type_id::create("read");
        start_item(it);
        it.kind = MAC_READ; it.idx = idx; it.gap = 0;
        finish_item(it);
        data      = it.rdata;
        last_wait = it.wait_cycles;
    endtask

    task csr_rd(bit [11:0] a, output bit [31:0] data);
        mac_cmd_item it = mac_cmd_item::type_id::create("csr_rd");
        start_item(it);
        it.kind = MAC_CSR_RD; it.csr_addr = a; it.gap = 0;
        finish_item(it);
        data = it.rdata;
    endtask

    task csr_wr(bit [11:0] a, bit [31:0] d);
        mac_cmd_item it = mac_cmd_item::type_id::create("csr_wr");
        start_item(it);
        it.kind = MAC_CSR_WR; it.csr_addr = a; it.csr_wdata = d; it.gap = 0;
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

// 257 COMPUTEs of 2^24 each pass 2^31 (positive to negative) and 2^32 (back to 0), spec D5
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
    endtask
endclass

// 10 back-to-back pushes of long commands: the first is popped at once, the next 8 fill the FIFO, so
// pushes 1..9 go in on consecutive cycles and push 10 waits (cmd_ready = 0). The final values depend
// on all ten, so a lost command shows up as a mismatch.
class mac_fifo_full_seq extends mac_base_seq;
    `uvm_object_utils(mac_fifo_full_seq)
    function new(string name = "mac_fifo_full_seq"); super.new(name); endfunction
    task body();
        int unsigned waits [10];
        rng = 32'h0F1F_0001;
        drain();
        fill_random(BIG_W, 1024);
        fill_random(BIG_I, 1024);
        push(OP_LDW, BIG_W, KMAX);           waits[0] = last_wait;
        push(OP_LDI, BIG_I, KMAX);           waits[1] = last_wait;
        push(OP_MAC, 0, KMAX, 1'b1);         waits[2] = last_wait;
        for (int n = 3; n < 10; n++) begin
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
    task set_all_errors();
        push(OP_MAC, 0, 6);                            // err_k
        push(OP_LDW, 32'h0001_FFF0, 8);                // err_addr
        push(OP_ILLEGAL, W0, 4);                       // err_illegal
        push(OP_LDI, 32'h0001_0004, 4);                // err_align
        expect_errs("all four set", ST_ERR_MASK);
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
        push(OP_MAC, 0, 6);                            // set while already set: stays set
        expect_errs("set while set", ST_ERR_MASK);
        csr_wr(CSR_NPU_STATUS, 32'hFFFF_FFFF);
        expect_errs("write all ones", 0);
        check_all();
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
