`timescale 1ns / 1ps

// selftest_tb - dummy UVM tests for the self-test of run.py (Phase 2 Task 15 [support], run_py_selftest).
// They check run.py's judgement, not any design: no DUT, no DPI.
//   selftest_pass: reports nothing worse than UVM_INFO, so it ends with UVM_ERROR : 0, UVM_FATAL : 0
//   selftest_fail: reports exactly one UVM_ERROR with the ID SELFTEST_FAIL (expected-fail in sim/tests.yaml)
// sim/selftest/check_run_py.py runs them through run.py as listed and with each expectation flipped.
package selftest_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"

    // raises an objection for a few ns so that the run phase, the report phase and the report summary
    // happen as in a real test
    class selftest_base extends uvm_test;
        `uvm_component_utils(selftest_base)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        virtual function void body();
        endfunction

        task run_phase(uvm_phase phase);
            phase.raise_objection(this);
            #10ns;
            body();
            phase.drop_objection(this);
        endtask
    endclass

    class selftest_pass extends selftest_base;
        `uvm_component_utils(selftest_pass)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void body();
            `uvm_info("SELFTEST", "selftest_pass: no error reported", UVM_LOW)
        endfunction
    endclass

    class selftest_fail extends selftest_base;
        `uvm_component_utils(selftest_fail)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void body();
            `uvm_error("SELFTEST_FAIL", "selftest_fail: the one deliberate error of this test")
        endfunction
    endclass
endpackage

module selftest_tb_top;
    import uvm_pkg::*;
    import selftest_pkg::*;

    // run.py passes -GGATING_EN=<0|1> to every top; this one only accepts it (nothing is gated here)
    parameter bit GATING_EN = 1'b0;

    initial run_test();
endmodule
