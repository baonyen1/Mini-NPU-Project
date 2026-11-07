`timescale 1ns / 1ps

// selftest_tb - dummy UVM tests for the self-test of run.py (Phase 2 Task 15 [support], run_py_selftest).
// They check run.py's judgement, not any design: no DUT, no DPI. Each one trips exactly one condition of
// run.py's pass rule (report summary, UVM_ERROR 0, UVM_FATAL 0, no simulator error):
//   selftest_pass:       reports nothing worse than UVM_INFO, so it ends with UVM_ERROR : 0, UVM_FATAL : 0
//   selftest_fail:       exactly one UVM_ERROR, ID SELFTEST_FAIL (expected-fail in sim/tests.yaml)
//   selftest_fatal:      one UVM_FATAL, ID SELFTEST_FATAL (expected-fail in sim/tests.yaml)
//   selftest_sva:        a failing immediate assertion ("# ** Error" in the log), UVM_ERROR 0, UVM_FATAL 0
//   selftest_no_summary: $finish before the run phase ends, so no UVM report summary
//   selftest_hang:       a zero-time loop: simulated time stops, so only run.py's wall-clock limit ends it
// selftest_sva, selftest_no_summary and selftest_hang are not in sim/tests.yaml: no expectation in run.py's
// rules fits them (an expected-fail test needs the summary and error IDs). sim/selftest/check_run_py.py adds
// them, expected to pass, to a temporary test list and checks that run.py rejects them.
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

    class selftest_fatal extends selftest_base;
        `uvm_component_utils(selftest_fatal)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        // UVM ends the simulation here, after printing the report summary (UVM_FATAL : 1)
        function void body();
            `uvm_fatal("SELFTEST_FATAL", "selftest_fatal: the one deliberate fatal of this test")
        endfunction
    endclass

    class selftest_sva extends selftest_base;
        `uvm_component_utils(selftest_sva)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        // the assertion fails outside UVM (like a bound SVA without a UVM action block): the UVM counts stay
        // 0, only the simulator's "# ** Error" line shows it
        function void body();
            bit always_false = 1'b0;
            assert (always_false) else $error("selftest_sva: the one deliberate assertion failure of this test");
        endfunction
    endclass

    class selftest_no_summary extends selftest_base;
        `uvm_component_utils(selftest_no_summary)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        // ends the simulation before the objection is dropped (as a crash or a stray $finish would), so the
        // report phase never runs. The two count lines look like the summary's: only the missing
        // "UVM Report Summary" header tells run.py that the counts are not real.
        function void body();
            $display("UVM_ERROR :    0");
            $display("UVM_FATAL :    0");
            $finish;
        endfunction
    endclass

    class selftest_hang extends selftest_base;
        `uvm_component_utils(selftest_hang)

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        // never returns and never advances time (a testbench bug of this kind defeats any #delay watchdog)
        function void body();
            int unsigned spins = 0;
            while (1'b1) spins++;
        endfunction
    endclass
endpackage

module selftest_tb_top;
    import uvm_pkg::*;
    import selftest_pkg::*;

    initial run_test();
endmodule
