`timescale 1ns / 1ps

// mac_dtcm_agent_pkg - reactive responder on mac_engine's DTCM port B (spec 7.1, 10.1; Phase 2 Task 16).
//
// It holds the DTCM contents as bit [127:0] mem[4096] (quad q = words 4q..4q+3, word 4q in bits [31:0],
// spec 6.2) and answers every b_req with mem[b_addr] in the next cycle. In a cycle that does not follow
// a b_req, b_rdata is X, so an engine that samples port B at the wrong time reads X.
//
// Every write goes through write_word(), which also calls npu_ref_mem_write, so the golden model's DTCM
// image always equals mem (Review Focus 2; mac_env's check_phase proves it over all 16,384 words).
// Sequences must only write while the engine is drained (the WAR rule, spec 6.3 rule 5).
// corrupt_word() is the one deliberate exception: it changes mem without the model, so that the test
// mac_mem_mirror_inject can show the mirror check is not vacuous.
package mac_dtcm_agent_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import npu_pkg::*;
    import npu_dpi_pkg::*;

    localparam int unsigned DTCM_WORDS = DTCM_BYTES / 4;

    class mac_dtcm_agent extends uvm_agent;
        `uvm_component_utils(mac_dtcm_agent)

        virtual mac_dtcm_if vif;
        bit [PORT_B_W-1:0]  mem [DTCM_QUADS];
        int unsigned        n_reads;           // port-B reads answered since the start

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual mac_dtcm_if)::get(this, "", "dtcm_vif", vif))
                `uvm_fatal("NOVIF", "mac_dtcm_agent: no dtcm_vif in uvm_config_db")
        endfunction

        // word_idx = (byte address - DTCM_BASE) / 4
        function void write_word(int unsigned word_idx, bit [31:0] data);
            if (word_idx >= DTCM_WORDS) begin
                `uvm_error("DTCM", $sformatf("write_word: word %0d out of range", word_idx))
                return;
            end
            mem[word_idx / 4][32 * (word_idx % 4) +: 32] = data;
            npu_ref_mem_write(word_idx, data);
        endfunction

        function bit [31:0] read_word(int unsigned word_idx);
            return mem[word_idx / 4][32 * (word_idx % 4) +: 32];
        endfunction

        function void write_byte_addr(bit [31:0] byte_addr, bit [31:0] data);
            write_word((byte_addr - DTCM_BASE) >> 2, data);
        endfunction

        function void corrupt_word(int unsigned word_idx, bit [31:0] data);
            mem[word_idx / 4][32 * (word_idx % 4) +: 32] = data;     // not mirrored, on purpose
        endfunction

        task run_phase(uvm_phase phase);
            vif.b_rdata = 'x;
            forever begin
                @(vif.rsp_cb);
                if (vif.rsp_cb.b_req === 1'b1) begin
                    vif.rsp_cb.b_rdata <= mem[vif.rsp_cb.b_addr];
                    n_reads++;
                end else begin
                    vif.rsp_cb.b_rdata <= 'x;
                end
            end
        endtask
    endclass
endpackage : mac_dtcm_agent_pkg
