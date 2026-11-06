// mac_predictor.sv - feeds every observed transaction to the golden model npu_ref in program order and
// turns READ_RESULT and CSR reads into comparisons for the scoreboard (Phase 2 Task 16). Included by
// mac_env_pkg.
//
//   RESET   npu_ref_reset() clears the model's DTCM too, so the responder memory is mirrored back in;
//           the written-entry counts start again from 0.
//   PUSH    npu_ref_cmd at the edge where the engine accepted it (program order, spec 6.3 rule 1).
//   CSR_WR  npu_ref_csr_write.
//   READ    compare rd_data with npu_ref_read(idx).
//   CSR_RD  0x7C0: compare with npu_ref_status(), but only when the engine was drained in that cycle: the
//           model is untimed (busy = 0, fifo_empty = 1), and an error raised by a queued command appears
//           in the RTL only after its CHECK (spec 6.3 rule 4, D23). 0x7C1: not compared, the model keeps
//           only the written value and spec 10.2 masks npu_busy_cyc. Any other address must read 0 (D21).
//
// Spec 7.2: a COMPUTE must not read WBUF/IBUF entries that no LOAD wrote since reset. That is a test
// error, not a DUT error: UVM_ERROR UNWRITTEN_ENTRY (Review Focus 4). From then on the accumulators are
// unpredictable (the RTL reads X), so READ results are not compared until the next reset.

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

    int unsigned w_written, i_written;      // WBUF/IBUF entries 0..n-1 written since reset
    bit          acc_unknown;               // a COMPUTE read unwritten entries (see above)
    int unsigned n_status_skipped;          // npu_status reads not compared (engine not drained)

    function new(string name, uvm_component parent);
        super.new(name, parent);
        check_ap = new("check_ap", this);
    endfunction

    function void send(string what, bit [31:0] exp, bit [31:0] act);
        mac_check c = mac_check::type_id::create("c");
        c.what = what;
        c.exp  = exp;
        c.act  = act;
        check_ap.write(c);
    endfunction

    function void write(mac_cmd_item t);
        case (t.kind)
            MAC_RESET: begin
                npu_ref_reset();
                for (int unsigned w = 0; w < DTCM_WORDS; w++) npu_ref_mem_write(w, dtcm.read_word(w));
                w_written   = 0;
                i_written   = 0;
                acc_unknown = 1'b0;
            end
            MAC_PUSH:   on_push(t);
            MAC_CSR_WR: on_csr_write(t);
            MAC_READ: begin
                if (!acc_unknown) send($sformatf("READ_RESULT acc[%0d]", t.idx), npu_ref_read(t.idx), t.rdata);
            end
            MAC_CSR_RD: begin
                if (t.csr_addr == CSR_NPU_STATUS) begin
                    if (t.drained) send("CSR npu_status", npu_ref_status(), t.rdata);
                    else           n_status_skipped++;
                end else if (t.csr_addr != CSR_NPU_BUSY_CYC) begin
                    send($sformatf("CSR 0x%03x (no such CSR)", t.csr_addr), 32'd0, t.rdata);
                end
            end
            default: ;
        endcase
    endfunction

    function void on_push(mac_cmd_item t);
        mac_cmd_fate_e fate;
        bit [31:0]     acc_before [16];
        bit [31:0]     st_before, st_after, acc_after;
        bit            acc_nz;
        int unsigned   steps, bit_pos;

        fate      = mac_cmd_fate(t.op, t.addr, t.k);
        steps     = t.k / 4;
        st_before = npu_ref_status();
        acc_nz    = 1'b0;
        for (int i = 0; i < 16; i++) begin
            acc_before[i] = npu_ref_read(i);
            if (acc_before[i] != 0) acc_nz = 1'b1;
        end

        if (fate == CMD_EXEC && t.op == OP_MAC && (steps > w_written || steps > i_written)) begin
            `uvm_error("UNWRITTEN_ENTRY", $sformatf({"COMPUTE K=%0d reads %0d entries, but only %0d WBUF and %0d IBUF ",
                       "entries were written since reset (spec 7.2): a test error"}, t.k, steps, w_written, i_written))
            acc_unknown = 1'b1;
        end

        if (cov != null) begin
            cov.sample_cmd(t.op, t.k, t.clr, acc_nz);
            if (t.op == OP_LDW || t.op == OP_LDI) cov.sample_addr(t.addr, t.k);
            if (fate == CMD_EXEC && t.op != OP_MAC)
                for (int unsigned s = 0; s < steps; s++)
                    cov.sample_quad(t.op == OP_LDI, dtcm.mem[((t.addr - DTCM_BASE) >> 4) + s]);
        end

        npu_ref_cmd(t.op, t.addr, t.k, t.clr);

        if (fate == CMD_EXEC && t.op == OP_LDW && steps > w_written) w_written = steps;
        if (fate == CMD_EXEC && t.op == OP_LDI && steps > i_written) i_written = steps;

        if (cov == null) return;
        // error bits: a new set, or the same error again while its bit is still set
        st_after = npu_ref_status();
        bit_pos = 0;
        case (fate)
            CMD_ILLEGAL:   bit_pos = ST_ERR_ILLEGAL;
            CMD_ERR_K:     bit_pos = ST_ERR_K;
            CMD_ERR_ALIGN: bit_pos = ST_ERR_ALIGN;
            CMD_ERR_ADDR:  bit_pos = ST_ERR_ADDR;
            default: ;
        endcase
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
        if (cov != null && t.csr_addr == CSR_NPU_STATUS)
            foreach (err_bits[b])
                if (st_before[err_bits[b]] && t.csr_wdata[err_bits[b]]) cov.sample_err(err_bits[b], ERR_EV_W1C_CLEAR);
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("PRED", $sformatf("npu_status reads not compared because the engine was busy: %0d", n_status_skipped), UVM_LOW)
    endfunction
endclass
