// mac_scoreboard.sv - compares what mac_engine returned with what npu_ref predicts (Phase 2 Task 16).
// Included by mac_env_pkg. mac_predictor sends one mac_check per comparison: each observed READ_RESULT
// and CSR read, and the npu_status RO-bit checks against the ports (STATUS_RO).
// An X or Z in a returned value is an error of its own (XVALUE), never a silent 0: the observed values
// are 4-state from the monitor on. A check with cmp = 0 is that X check only (npu_busy_cyc, whose value
// npu_ref does not model).
// A test with no comparison at all is an error (NO_CHECKS): a silent environment must not pass.

class mac_check extends uvm_object;
    string       what;
    string       id  = "MISMATCH";               // the UVM_ERROR ID of a difference
    string       src = "npu_ref";                // where exp comes from, for the message
    bit          cmp = 1'b1;                     // 0: X check only
    logic [31:0] exp;
    logic [31:0] act;

    `uvm_object_utils(mac_check)

    function new(string name = "mac_check");
        super.new(name);
    endfunction
endclass

class mac_scoreboard extends uvm_component;
    `uvm_component_utils(mac_scoreboard)

    uvm_analysis_imp #(mac_check, mac_scoreboard) imp;
    int unsigned n_checks;
    int unsigned n_mismatch;

    function new(string name, uvm_component parent);
        super.new(name, parent);
        imp = new("imp", this);
    endfunction

    function void write(mac_check c);
        n_checks++;
        if ($isunknown(c.act)) begin
            n_mismatch++;
            `uvm_error("XVALUE", $sformatf("%s: DUT returned %08x (X or Z bits)", c.what, c.act))
        end else if (c.cmp && c.act !== c.exp) begin
            n_mismatch++;
            `uvm_error(c.id, $sformatf("%s: DUT %08x, %s %08x", c.what, c.act, c.src, c.exp))
        end
    endfunction

    function void check_phase(uvm_phase phase);
        if (n_checks == 0) `uvm_error("NO_CHECKS", "the scoreboard compared nothing in this test")
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCB", $sformatf("%0d comparisons, %0d mismatches", n_checks, n_mismatch), UVM_LOW)
    endfunction
endclass
