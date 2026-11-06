// mac_scoreboard.sv - compares what mac_engine returned with what npu_ref predicts (Phase 2 Task 16).
// Included by mac_env_pkg. mac_predictor sends one mac_check per observed READ_RESULT or CSR read.
// A test with no comparison at all is an error (NO_CHECKS): a silent environment must not pass.

class mac_check extends uvm_object;
    string     what;
    bit [31:0] exp;
    bit [31:0] act;

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
        if (c.act !== c.exp) begin
            n_mismatch++;
            `uvm_error("MISMATCH", $sformatf("%s: DUT %08x, npu_ref %08x", c.what, c.act, c.exp))
        end
    endfunction

    function void check_phase(uvm_phase phase);
        if (n_checks == 0) `uvm_error("NO_CHECKS", "the scoreboard compared nothing in this test")
    endfunction

    function void report_phase(uvm_phase phase);
        `uvm_info("SCB", $sformatf("%0d comparisons, %0d mismatches", n_checks, n_mismatch), UVM_LOW)
    endfunction
endclass
