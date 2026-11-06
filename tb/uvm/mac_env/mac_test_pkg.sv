`timescale 1ns / 1ps

// mac_test_pkg - the uvm_tests of mac_env (Phase 2 Task 16). One test per sequence in mac_seq_lib.sv.
//
// mac_base_test: builds mac_env, starts a watchdog (+TIMEOUT_CYC=<cycles>, default 1,000,000 cycles of
// 10 ns; reaching it is UVM_FATAL TIMEOUT, so a hang fails, spec 10.1), waits for the reset to be released,
// runs the test's sequence, then mac_final_seq (all 16 results and npu_status, compared with npu_ref).
// Pass = UVM_ERROR : 0, UVM_FATAL : 0 and no SVA failure (the bound assertions report UVM_ERROR).
// Expected-fail tests (run.py / sim/tests.yaml) must fail with their stated error ID only.
package mac_test_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import npu_pkg::*;
    import mac_cmd_agent_pkg::*;
    import mac_dtcm_agent_pkg::*;
    import mac_env_pkg::*;

    `include "mac_seq_lib.sv"

    class mac_base_test extends uvm_test;
        `uvm_component_utils(mac_base_test)

        mac_env            env;
        virtual mac_cmd_if cmd_vif;
        int unsigned       timeout_cyc;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            env = mac_env::type_id::create("env", this);
            if (!uvm_config_db #(virtual mac_cmd_if)::get(this, "", "cmd_vif", cmd_vif))
                `uvm_fatal("NOVIF", "mac_base_test: no cmd_vif")
            if (!$value$plusargs("TIMEOUT_CYC=%d", timeout_cyc)) timeout_cyc = 1_000_000;
        endfunction

        // the test's sequence; mac_base_test itself runs none
        virtual function mac_base_seq make_seq();
            return null;
        endfunction

        task run_phase(uvm_phase phase);
            mac_base_seq  seq;
            mac_final_seq fin;
            phase.raise_objection(this);
            // the watchdog is a delay in this package's time unit (uvm_top.set_timeout takes the value in
            // uvm_pkg's unit, which is not this one)
            fork
                begin
                    #(timeout_cyc * 10ns);
                    `uvm_fatal("TIMEOUT", $sformatf("test still running after %0d cycles", timeout_cyc))
                end
            join_none
            @(posedge cmd_vif.clk iff cmd_vif.rst_n === 1'b1);
            seq = make_seq();
            if (seq != null) begin
                seq.env = env;
                seq.start(env.cmd_agent.sqr);
            end
            fin = mac_final_seq::type_id::create("final");
            fin.env = env;
            fin.start(env.cmd_agent.sqr);
            phase.drop_objection(this);
        endtask
    endclass

    `define MAC_TEST(TNAME, SEQ)                                              \
        class TNAME extends mac_base_test;                                    \
            `uvm_component_utils(TNAME)                                       \
            function new(string name, uvm_component parent);                  \
                super.new(name, parent);                                      \
            endfunction                                                       \
            virtual function mac_base_seq make_seq();                         \
                SEQ s = SEQ::type_id::create("seq");                          \
                return s;                                                     \
            endfunction                                                       \
        endclass

    `MAC_TEST(mac_single_k4,               mac_single_k4_seq)
    `MAC_TEST(mac_k_kmax,                  mac_k_kmax_seq)
    `MAC_TEST(mac_k0,                      mac_k0_seq)
    `MAC_TEST(mac_k_too_big,               mac_k_too_big_seq)
    `MAC_TEST(mac_k_mod4,                  mac_k_mod4_seq)
    `MAC_TEST(mac_misaligned,              mac_misaligned_seq)
    `MAC_TEST(mac_addr_oob,                mac_addr_oob_seq)
    `MAC_TEST(mac_addr_wraps_32bit,        mac_addr_wraps_32bit_seq)
    `MAC_TEST(mac_illegal,                 mac_illegal_seq)
    `MAC_TEST(mac_clr_vs_accum,            mac_clr_vs_accum_seq)
    `MAC_TEST(mac_forced_wrap,             mac_forced_wrap_seq)
    `MAC_TEST(mac_fifo_full,               mac_fifo_full_seq)
    `MAC_TEST(mac_read_while_busy,         mac_read_while_busy_seq)
    `MAC_TEST(mac_w1c,                     mac_w1c_seq)
    `MAC_TEST(mac_w1c_inflight,            mac_w1c_inflight_seq)
    `MAC_TEST(mac_d23,                     mac_d23_seq)
    `MAC_TEST(mac_busy_cyc,                mac_busy_cyc_seq)
    `MAC_TEST(mac_addr_cov_dropped,        mac_addr_cov_dropped_seq)
    `MAC_TEST(mac_mem_mirror_check,        mac_mem_mirror_check_seq)
    `MAC_TEST(mac_mem_mirror_inject,       mac_mem_mirror_inject_seq)
    `MAC_TEST(mac_war_inject,              mac_war_inject_seq)
    `MAC_TEST(mac_unwritten_entry_flagged, mac_unwritten_entry_flagged_seq)

    `undef MAC_TEST
endpackage : mac_test_pkg
