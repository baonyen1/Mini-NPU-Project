// mac_predictor.sv - feeds every observed transaction to the golden model npu_ref in the order the
// engine applies it and turns READ_RESULT and CSR reads into comparisons for the scoreboard (Phase 2
// Task 16). Included by mac_env_pkg.
//
//   RESET   npu_ref_reset() clears the model's DTCM too, so the responder memory is mirrored back in;
//           the queued commands are dropped and the written-entry counts start again from 0.
//   PUSH    queued in `pending`, in program order (spec 6.3 rule 1): the RTL FIFO's contents.
//   POP     the engine pops the head in CHECK: npu_ref_cmd for the oldest pending command. The RTL sets
//           an error bit and starts a LOAD or MAC at that edge, so from then on npu_ref's error bits are
//           cycle-aligned with the RTL's. A W1C at the same edge comes first (monitor order, D23: the
//           set wins), so it does not clear that command's error.
//   CSR_WR  npu_ref_csr_write.
//   READ    compare rd_data with npu_ref_read(idx). READ_RESULT waits for the drain, so every command
//           has run by then.
//   CSR_RD  0x7C0, drained (rd_ready = 1): compare with npu_ref_status() (busy 0, fifo_empty 1).
//           0x7C0, not drained: compare the error and reserved bits with npu_ref; the RO bits are checked
//           against the ports of that cycle and the queue depth instead (STATUS_RO, check_status_ro).
//           0x7C1: X check only; the model keeps only the written value and spec 10.2 masks it
//           (mac_busy_cyc checks the count). Any other address must read 0 (D21).
//
// Spec 7.2: a COMPUTE must not read WBUF/IBUF entries that no LOAD wrote since reset. That is a test
// error, not a DUT error: UVM_ERROR UNWRITTEN_ENTRY (Review Focus 4). From then on the accumulators are
// unpredictable (the RTL reads X), so READ results are not compared until the next reset, and that
// COMPUTE and the later ones sample no coverage that depends on the accumulators.

typedef enum int {CMD_EXEC, CMD_K0, CMD_ILLEGAL, CMD_ERR_K, CMD_ERR_ALIGN, CMD_ERR_ADDR} mac_cmd_fate_e;

// What CHECK does with a command (spec 6.3 error table, D16 order). Written from the spec, independently
// of the RTL and of npu_ref, for coverage and for the unwritten-entry rule.
function automatic mac_cmd_fate_e mac_cmd_fate(npu_op_e op, bit [31:0] addr, bit [31:0] k);
    longint unsigned last;
    if (op == OP_ILLEGAL)            return CMD_ILLEGAL;
    if (k == 0)                      return CMD_K0;
    if (k > KMAX || k[1:0] != 2'b00) return CMD_ERR_K;
    if (op == OP_MAC)                return CMD_EXEC;
    if (addr[3:0] != 4'h0)           return CMD_ERR_ALIGN;
    last = longint'(addr) + 4 * longint'(k);
    if (addr < DTCM_BASE || last > longint'(DTCM_BASE) + DTCM_BYTES) return CMD_ERR_ADDR;
    return CMD_EXEC;
endfunction

class mac_predictor extends uvm_subscriber #(mac_cmd_item);
    `uvm_component_utils(mac_predictor)

    uvm_analysis_port #(mac_check) check_ap;
    mac_dtcm_agent dtcm;                    // set by mac_env
    mac_coverage   cov;                     // set by mac_env; may be null

    mac_cmd_item pending [$];               // pushed, not yet popped: the RTL FIFO's contents
    int unsigned w_written, i_written;      // WBUF/IBUF entries 0..n-1 written since reset
    bit          acc_unknown;               // a COMPUTE read unwritten entries (see above)
    realtime     t_status_wr = -1.0;        // time of the last observed npu_status write ...
    bit [31:0]   status_wdata;              // ... and its value
    int unsigned n_status_busy;             // npu_status reads with the engine not drained
    int unsigned n_d23;                     // CHECKs that set an error bit W1C'd at the same edge (D23)

    localparam bit [31:0] ST_RO_MASK = (32'd1 << ST_BUSY) | (32'd1 << ST_FIFO_EMPTY) | (32'd1 << ST_FIFO_FULL);

    function new(string name, uvm_component parent);
        super.new(name, parent);
        check_ap = new("check_ap", this);
    endfunction

    function void send(string what, logic [31:0] exp, logic [31:0] act, string id = "MISMATCH",
                       string src = "npu_ref", bit cmp = 1'b1);
        mac_check c = mac_check::type_id::create("c");
        c.what = what;
        c.exp  = exp;
        c.act  = act;
        c.id   = id;
        c.src  = src;
        c.cmp  = cmp;
        check_ap.write(c);
    endfunction

    function void write(mac_cmd_item t);
        case (t.kind)
            MAC_RESET: begin
                npu_ref_reset();
                for (int unsigned w = 0; w < DTCM_WORDS; w++) npu_ref_mem_write(w, dtcm.read_word(w));
                pending.delete();
                w_written   = 0;
                i_written   = 0;
                acc_unknown = 1'b0;
                t_status_wr = -1.0;
            end
            MAC_PUSH:   pending.push_back(t);
            MAC_POP: begin
                if (pending.size() == 0)
                    `uvm_error("POP_EMPTY", "the engine entered CHECK with no command pushed and not yet popped")
                else
                    on_check(pending.pop_front());
            end
            MAC_CSR_WR: on_csr_write(t);
            MAC_READ: begin
                if (!acc_unknown) send($sformatf("READ_RESULT acc[%0d]", t.idx), npu_ref_read(t.idx), t.rdata);
            end
            MAC_CSR_RD: on_csr_read(t);
            default: ;
        endcase
    endfunction

    function void on_csr_read(mac_cmd_item t);
        if (t.csr_addr == CSR_NPU_STATUS) begin
            if (t.drained) begin
                send("CSR npu_status", npu_ref_status(), t.rdata);
            end else begin
                send("CSR npu_status error and reserved bits (engine not drained)",
                     npu_ref_status() & ~ST_RO_MASK, t.rdata & ~ST_RO_MASK);
                n_status_busy++;
            end
            check_status_ro(t);
        end else if (t.csr_addr == CSR_NPU_BUSY_CYC) begin
            send("CSR npu_busy_cyc", 'x, t.rdata, "MISMATCH", "", 1'b0);
        end else begin
            send($sformatf("CSR 0x%03x (no such CSR)", t.csr_addr), 32'd0, t.rdata);
        end
    endfunction

    // npu_status RO bits (spec 6.4) against what the testbench sees in the same cycle: cmd_ready is
    // !fifo_full and rd_ready is !busy && fifo_empty (spec 7.1), and `pending` holds as many commands as
    // the FIFO (pushes and pops of earlier edges only: the read is processed before this edge's).
    function void check_status_ro(mac_cmd_item t);
        int unsigned n = pending.size();
        send("npu_status.fifo_full vs !cmd_ready", 32'(!t.cmd_ready), 32'(t.rdata[ST_FIFO_FULL]),
             "STATUS_RO", "ports");
        send($sformatf("npu_status.fifo_full with %0d commands queued", n), 32'(n == FIFO_DEPTH),
             32'(t.rdata[ST_FIFO_FULL]), "STATUS_RO", "queue");
        send($sformatf("npu_status.fifo_empty with %0d commands queued", n), 32'(n == 0),
             32'(t.rdata[ST_FIFO_EMPTY]), "STATUS_RO", "queue");
        send("npu_status busy || !fifo_empty vs !rd_ready", 32'(!t.drained),
             32'(t.rdata[ST_BUSY] || !t.rdata[ST_FIFO_EMPTY]), "STATUS_RO", "ports");
    endfunction

    // The command popped at this edge: the model executes it now, as the RTL starts it now.
    function void on_check(mac_cmd_item t);
        mac_cmd_fate_e fate;
        bit [31:0]     acc_before [16];
        bit [31:0]     st_before, acc_after;
        bit            acc_nz, unwritten, is_load;
        int unsigned   steps, bit_pos;

        fate      = mac_cmd_fate(t.op, t.addr, t.k);
        steps     = t.k / 4;
        is_load   = (t.op == OP_LDW || t.op == OP_LDI);
        st_before = npu_ref_status();
        acc_nz    = 1'b0;
        for (int i = 0; i < 16; i++) begin
            acc_before[i] = npu_ref_read(i);
            if (acc_before[i] != 0) acc_nz = 1'b1;
        end

        unwritten = (fate == CMD_EXEC && t.op == OP_MAC && (steps > w_written || steps > i_written));
        if (unwritten) begin
            `uvm_error("UNWRITTEN_ENTRY", $sformatf({"COMPUTE K=%0d reads %0d entries, but only %0d WBUF and %0d IBUF ",
                       "entries were written since reset (spec 7.2): a test error"}, t.k, steps, w_written, i_written))
            acc_unknown = 1'b1;
        end

        bit_pos = 0;
        case (fate)
            CMD_ILLEGAL:   bit_pos = ST_ERR_ILLEGAL;
            CMD_ERR_K:     bit_pos = ST_ERR_K;
            CMD_ERR_ALIGN: bit_pos = ST_ERR_ALIGN;
            CMD_ERR_ADDR:  bit_pos = ST_ERR_ADDR;
            default: ;
        endcase
        if (bit_pos != 0 && t_status_wr == $realtime && status_wdata[bit_pos]) n_d23++;

        // Coverage (Review Focus 4): none for a COMPUTE that reads unwritten entries; while the
        // accumulators are unknown, no COMPUTE samples cg_cmd (acc-nonzero-before) or cg_acc.
        if (cov != null && !unwritten) begin
            if (!(t.op == OP_MAC && acc_unknown)) cov.sample_cmd(t.op, t.k, t.clr, acc_nz);
            if (is_load) cov.sample_addr(t.addr, t.k, fate == CMD_EXEC, fate == CMD_ERR_ADDR);
            if (fate == CMD_EXEC && is_load)
                for (int unsigned s = 0; s < steps; s++)
                    cov.sample_quad(t.op == OP_LDI, dtcm.mem[((t.addr - DTCM_BASE) >> 4) + s]);
        end

        npu_ref_cmd(t.op, t.addr, t.k, t.clr);

        if (fate == CMD_EXEC && t.op == OP_LDW && steps > w_written) w_written = steps;
        if (fate == CMD_EXEC && t.op == OP_LDI && steps > i_written) i_written = steps;

        if (cov == null || unwritten) return;
        // error bits: a new set, or the same error again while its bit is still set
        if (bit_pos != 0) cov.sample_err(bit_pos, st_before[bit_pos] ? ERR_EV_SET_WHILE_SET : ERR_EV_SET);
        // accumulator wrap: the signed result crosses 0 the wrong way for the sign of the added value
        // (|added value| <= 2^24 < 2^31, so the 32-bit difference has the sign of the value added)
        if (fate == CMD_EXEC && t.op == OP_MAC && !t.clr && !acc_unknown) begin
            for (int i = 0; i < 16; i++) begin
                bit [31:0] diff;
                acc_after = npu_ref_read(i);
                diff      = acc_after - acc_before[i];
                if (!acc_before[i][31] && acc_after[31] && !diff[31]) cov.sample_acc_wrap(ACC_POS_TO_NEG);
                if (acc_before[i][31] && !acc_after[31] && diff[31])  cov.sample_acc_wrap(ACC_NEG_TO_POS);
            end
        end
    endfunction

    function void on_csr_write(mac_cmd_item t);
        bit [31:0]   st_before;
        int unsigned err_bits [4] = '{ST_ERR_K, ST_ERR_ADDR, ST_ERR_ILLEGAL, ST_ERR_ALIGN};
        st_before = npu_ref_status();
        npu_ref_csr_write(t.csr_addr, t.csr_wdata);
        if (t.csr_addr == CSR_NPU_STATUS) begin
            t_status_wr  = $realtime;
            status_wdata = t.csr_wdata;
        end
        if (cov != null && t.csr_addr == CSR_NPU_STATUS)
            foreach (err_bits[b])
                if (st_before[err_bits[b]] && t.csr_wdata[err_bits[b]]) cov.sample_err(err_bits[b], ERR_EV_W1C_CLEAR);
    endfunction

    function void check_phase(uvm_phase phase);
        if (pending.size() != 0)
            `uvm_error("PENDING", $sformatf("%0d pushed command(s) never reached CHECK by the end of the test",
                       pending.size()))
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("PRED", $sformatf({"npu_status reads with the engine not drained (error bits vs npu_ref, RO bits ",
                  "vs ports): %0d; W1C of an error bit at the CHECK edge that sets it (D23): %0d"},
                  n_status_busy, n_d23), UVM_LOW)
    endfunction
endclass
