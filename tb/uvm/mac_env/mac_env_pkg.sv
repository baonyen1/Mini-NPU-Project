`timescale 1ns / 1ps

// mac_env_pkg - the UVM environment of mac_engine (spec 10.1; Phase 2 Task 16).
//
//   cmd_agent  (active)   PUSH / READ / CSR transactions on mac_cmd_if
//   dtcm_agent (reactive) port-B responder; its memory is mirrored into npu_ref on every write
//   predictor             cmd_agent.ap -> npu_ref (DPI-C) -> mac_check items
//   scoreboard            compares DUT and npu_ref
//   coverage              the spec 10.5 covergroups (cg_gate comes in Phase 3)
// The SVA of spec 10.6 (A-MAC-1..5) is bound to the DUT by mac_tb_top (tb/sva/mac_engine_sva.sv).
//
// check_phase proves Review Focus 2: an FNV-1a hash over all 16,384 words of the responder memory must
// equal the same hash over npu_ref's DTCM image (npu_ref_mem_read), in every test.
package mac_env_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import npu_pkg::*;
    import npu_dpi_pkg::*;
    import mac_cmd_agent_pkg::*;
    import mac_dtcm_agent_pkg::*;

    `include "mac_coverage.sv"
    `include "mac_scoreboard.sv"
    `include "mac_predictor.sv"

    class mac_env extends uvm_env;
        `uvm_component_utils(mac_env)

        mac_cmd_agent  cmd_agent;
        mac_dtcm_agent dtcm_agent;
        mac_predictor  predictor;
        mac_scoreboard scoreboard;
        mac_coverage   coverage;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            cmd_agent  = mac_cmd_agent::type_id::create("cmd_agent", this);
            dtcm_agent = mac_dtcm_agent::type_id::create("dtcm_agent", this);
            predictor  = mac_predictor::type_id::create("predictor", this);
            scoreboard = mac_scoreboard::type_id::create("scoreboard", this);
            coverage   = mac_coverage::type_id::create("coverage", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            cmd_agent.ap.connect(predictor.analysis_export);
            predictor.check_ap.connect(scoreboard.imp);
            predictor.dtcm = dtcm_agent;
            predictor.cov  = coverage;
        endfunction

        static function bit [31:0] fnv1a(bit [31:0] h, bit [31:0] w);
            for (int b = 0; b < 4; b++) h = (h ^ w[8 * b +: 8]) * 32'h0100_0193;
            return h;
        endfunction

        function void check_phase(uvm_phase phase);
            bit [31:0] h_rsp, h_ref, a, b;
            int        first_bad;
            h_rsp     = 32'h811C_9DC5;
            h_ref     = 32'h811C_9DC5;
            first_bad = -1;
            for (int unsigned w = 0; w < DTCM_WORDS; w++) begin
                a     = dtcm_agent.read_word(w);
                b     = npu_ref_mem_read(w);
                h_rsp = fnv1a(h_rsp, a);
                h_ref = fnv1a(h_ref, b);
                if (a != b && first_bad < 0) first_bad = w;
            end
            if (h_rsp != h_ref || first_bad >= 0)          // the word compare also covers a hash collision
                `uvm_error("MEM_MIRROR", $sformatf({"responder memory hash %08x, npu_ref DTCM hash %08x; first ",
                           "difference at word %0d: responder %08x, npu_ref %08x"}, h_rsp, h_ref, first_bad,
                           dtcm_agent.read_word(first_bad), npu_ref_mem_read(first_bad)))
            else
                `uvm_info("MEM_MIRROR", $sformatf("responder memory and npu_ref DTCM identical over %0d words (hash %08x)",
                          DTCM_WORDS, h_rsp), UVM_LOW)
        endfunction
    endclass
endpackage : mac_env_pkg
