// mac_coverage.sv - functional coverage of mac_engine, the spec 10.5 groups (Phase 2 Task 16).
// Included by mac_env_pkg. cg_gate (D1 only) is added in Phase 3.
//
// Who samples what:
//   mac_predictor  cg_cmd, cg_operand, cg_acc, cg_err, cg_addr: at each command's CHECK (when the engine
//                  pops it) or CSR write, in the order the engine applies them, with values from npu_ref
//                  (the model's state before and after it)
//   run_phase      cg_fifo and cg_state: every clock edge, from the bound probe (FIFO count, FSM state)
//                  and the command interface (push attempts, READ while busy)

typedef enum int {ERR_EV_SET, ERR_EV_SET_WHILE_SET, ERR_EV_W1C_CLEAR} mac_err_ev_e;
typedef enum int {ACC_POS_TO_NEG, ACC_NEG_TO_POS} mac_acc_wrap_e;

class mac_coverage extends uvm_component;
    `uvm_component_utils(mac_coverage)

    virtual mac_cmd_if   cmd_vif;
    virtual mac_probe_if probe_vif;

    // op x K bins x K mod 4; MAC x clr x accumulator non-zero before the command.
    // The K bins are contiguous, so every K falls in exactly one (spec 10.5, D24).
    covergroup cg_cmd with function sample(npu_op_e op, bit [31:0] k, bit clr, bit acc_nz);
        cp_op: coverpoint op;
        cp_k: coverpoint k {
            bins k0        = {0};
            bins k1_7      = {[1:7]};
            bins k8_63     = {[8:63]};
            bins k64_kmax1 = {[64:KMAX - 1]};
            bins kmax      = {KMAX};
            bins over_kmax = {[KMAX + 1:32'hFFFF_FFFF]};
        }
        cp_kmod4: coverpoint k[1:0];
        x_op_k_mod: cross cp_op, cp_k, cp_kmod4 {
            // K = 0 and K = KMAX are multiples of 4: those crosses cannot occur. The cell k1_7 x (K mod 4 = 0)
            // is exactly K = 4, so the one-step case keeps a cross cell of its own.
            ignore_bins fixed = (binsof(cp_k.k0) || binsof(cp_k.kmax)) &&
                                binsof(cp_kmod4) intersect {[1:3]};
        }
        cp_mac_clr: coverpoint clr iff (op == OP_MAC);
        cp_mac_acc_nz: coverpoint acc_nz iff (op == OP_MAC);
        x_mac_clr_acc: cross cp_mac_clr, cp_mac_acc_nz;
    endgroup

    // every lane of every quad written into WBUF or IBUF
    covergroup cg_operand with function sample(bit is_ibuf, int unsigned lane, byte v);
        cp_buf:  coverpoint is_ibuf { bins wbuf = {0}; bins ibuf = {1}; }
        cp_lane: coverpoint lane { bins lane[] = {[0:15]}; }
        cp_val:  coverpoint v {
            bins m128  = {-128};
            bins m1    = {-1};
            bins zero  = {0};
            bins p1    = {1};
            bins p127  = {127};
            bins other = {[-127:-2], [2:126]};
        }
        x_buf_lane_val: cross cp_buf, cp_lane, cp_val;
    endgroup

    // FIFO occupancy when a push is attempted; a push attempted while full (the core stalls)
    covergroup cg_fifo with function sample(int unsigned occ, bit full);
        cp_occ: coverpoint occ {
            bins o0    = {0};
            bins o1    = {1};
            bins o2_n  = {[2:FIFO_DEPTH - 2]};
            bins o_n1  = {FIFO_DEPTH - 1};
            bins full  = {FIFO_DEPTH};
        }
        cp_push_while_full: coverpoint full { bins stall = {1}; }
    endgroup

    // FSM transitions; READ_RESULT requested while the engine is busy
    covergroup cg_state with function sample(bit [1:0] st, bit read_busy);
        cp_tr: coverpoint st {
            bins idle_check  = (0 => 1);
            bins check_load  = (1 => 2);
            bins check_mac   = (1 => 3);
            bins check_idle  = (1 => 0);
            bins load_idle   = (2 => 0);
            bins mac_idle    = (3 => 0);
        }
        cp_read_while_busy: coverpoint read_busy { bins read_busy = {1}; }
    endgroup

    covergroup cg_acc with function sample(mac_acc_wrap_e dir);
        cp_wrap: coverpoint dir;
    endgroup

    covergroup cg_err with function sample(int unsigned bit_pos, mac_err_ev_e ev);
        cp_bit: coverpoint bit_pos {
            bins err_k       = {ST_ERR_K};
            bins err_addr    = {ST_ERR_ADDR};
            bins err_illegal = {ST_ERR_ILLEGAL};
            bins err_align   = {ST_ERR_ALIGN};
        }
        cp_ev: coverpoint ev;
        x_bit_ev: cross cp_bit, cp_ev;
    endgroup

    covergroup cg_addr with function sample(bit first_quad, bit last_quad, bit past_end, bit [3:0] a_lo);
        cp_first: coverpoint first_quad { bins first_quad = {1}; }
        cp_last:  coverpoint last_quad  { bins last_quad  = {1}; }
        cp_past:  coverpoint past_end   { bins one_quad_past_end = {1}; }
        cp_alo:   coverpoint a_lo {
            bins a0    = {0};
            bins a4    = {4};
            bins a8    = {8};
            bins a12   = {12};
            bins other = {1, 2, 3, 5, 6, 7, 9, 10, 11, 13, 14, 15};
        }
    endgroup

    function new(string name, uvm_component parent);
        super.new(name, parent);
        cg_cmd     = new();
        cg_operand = new();
        cg_fifo    = new();
        cg_state   = new();
        cg_acc     = new();
        cg_err     = new();
        cg_addr    = new();
    endfunction

    function void build_phase(uvm_phase phase);
        super.build_phase(phase);
        if (!uvm_config_db #(virtual mac_cmd_if)::get(this, "", "cmd_vif", cmd_vif))
            `uvm_fatal("NOVIF", "mac_coverage: no cmd_vif")
        if (!uvm_config_db #(virtual mac_probe_if)::get(this, "", "probe_vif", probe_vif))
            `uvm_fatal("NOVIF", "mac_coverage: no probe_vif")
    endfunction

    task run_phase(uvm_phase phase);
        forever begin
            @(posedge cmd_vif.clk);
            if (probe_vif.rst_n !== 1'b1) continue;
            cg_state.sample(probe_vif.state, cmd_vif.rd_req === 1'b1 && cmd_vif.rd_ready !== 1'b1);
            if (cmd_vif.cmd_valid === 1'b1) cg_fifo.sample(probe_vif.fifo_count, probe_vif.fifo_full);
        end
    endtask

    // ---- called by mac_predictor ---------------------------------------------------------------
    function void sample_cmd(npu_op_e op, bit [31:0] k, bit clr, bit acc_nz);
        cg_cmd.sample(op, k, clr, acc_nz);
    endfunction

    function void sample_quad(bit is_ibuf, bit [PORT_B_W-1:0] quad);
        for (int unsigned lane = 0; lane < 16; lane++) cg_operand.sample(is_ibuf, lane, byte'(quad[8 * lane +: 8]));
    endfunction

    function void sample_acc_wrap(mac_acc_wrap_e dir);
        cg_acc.sample(dir);
    endfunction

    function void sample_err(int unsigned bit_pos, mac_err_ev_e ev);
        cg_err.sample(bit_pos, ev);
    endfunction

    // executes: the LOAD passed CHECK; err_addr: CHECK dropped it with err_addr (mac_cmd_fate)
    function void sample_addr(bit [31:0] addr, bit [31:0] k, bit executes, bit err_addr);
        longint unsigned last, dtcm_end;
        last     = longint'(addr) + 4 * longint'(k);           // one past the last byte
        dtcm_end = longint'(DTCM_BASE) + DTCM_BYTES;
        // first quad: a LOAD that executes and starts at DTCM_BASE; last quad: one that executes and ends
        // exactly at the end of the DTCM; one quad past the end: an err_addr LOAD that ends exactly 16 bytes
        // beyond (err_addr by the smallest margin). A LOAD dropped for K or alignment counts in none.
        cg_addr.sample(executes && addr == DTCM_BASE,
                       executes && last == dtcm_end,
                       err_addr && addr >= DTCM_BASE && last == dtcm_end + QUAD_BYTES,
                       addr[3:0]);
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("COV", $sformatf({"cg_cmd %0.1f%%  cg_operand %0.1f%%  cg_fifo %0.1f%%  cg_state %0.1f%%  ",
                                    "cg_acc %0.1f%%  cg_err %0.1f%%  cg_addr %0.1f%%"},
                                   cg_cmd.get_coverage(), cg_operand.get_coverage(), cg_fifo.get_coverage(),
                                   cg_state.get_coverage(), cg_acc.get_coverage(), cg_err.get_coverage(),
                                   cg_addr.get_coverage()), UVM_LOW)
    endfunction
endclass
