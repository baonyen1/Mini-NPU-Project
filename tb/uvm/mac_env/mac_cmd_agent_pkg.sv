`timescale 1ns / 1ps

// mac_cmd_agent_pkg - the active agent on mac_engine's command, result-read and CSR ports (spec 7.1,
// 10.1; Phase 2 Task 16).
//
//   mac_cmd_item     one transaction: PUSH (cmd_* handshake), READ (rd_req until rd_ready), CSR_RD,
//                    CSR_WR, or, seen by the monitor only, RESET and POP (the engine pops the FIFO head
//                    in CHECK). gap = idle cycles before it. rdata is 4-state, so an X or Z the DUT
//                    returns reaches the scoreboard as such.
//   mac_cmd_driver   drives items through mac_cmd_if.drv_cb; READ and CSR_RD return rdata in the item,
//                    PUSH and READ return the cycles they waited (wait_cycles).
//   mac_cmd_monitor  turns what happened at each rising edge into items, in the order the golden model
//                    must see them within one cycle: RESET, CSR_RD, READ, CSR_WR, POP, PUSH. A CSR read
//                    sees the state before the edge. A W1C before the POP of the same edge is D23: the
//                    engine sets the popped command's error bit at that edge and the set wins, so the
//                    model applies the W1C first and the command after it. The FIFO holds the head
//                    before the edge, so a PUSH of the same edge is never the command popped.
//   mac_cmd_agent    sequencer + driver + monitor; ap carries the monitor's items.
package mac_cmd_agent_pkg;
    import uvm_pkg::*;
    `include "uvm_macros.svh"
    import npu_pkg::*;

    typedef enum {MAC_PUSH, MAC_READ, MAC_CSR_RD, MAC_CSR_WR, MAC_RESET, MAC_POP} mac_kind_e;

    class mac_cmd_item extends uvm_sequence_item;
        rand mac_kind_e      kind;
        rand npu_op_e        op;
        rand bit [31:0]      addr;
        rand bit [31:0]      k;
        rand bit             clr;
        rand bit [3:0]       idx;
        rand bit [11:0]      csr_addr;
        rand bit [31:0]      csr_wdata;
        rand int unsigned    gap;

        // results (driver) and observations (monitor)
        logic [31:0]         rdata;          // READ: rd_data; CSR_RD: csr_rdata (4-state)
        bit                  drained;        // CSR_RD: rd_ready was 1 in that cycle (engine idle, FIFO empty)
        bit                  cmd_ready;      // CSR_RD: cmd_ready in that cycle
        int unsigned         wait_cycles;    // PUSH: cycles with cmd_ready = 0; READ: cycles with rd_ready = 0

        constraint c_gap  { gap <= 20; }
        constraint c_kind { !(kind inside {MAC_RESET, MAC_POP}); }

        `uvm_object_utils(mac_cmd_item)

        function new(string name = "mac_cmd_item");
            super.new(name);
        endfunction

        function string convert2string();
            case (kind)
                MAC_PUSH:   return $sformatf("PUSH %s addr=%08x k=%0d clr=%0d", op.name(), addr, k, clr);
                MAC_READ:   return $sformatf("READ idx=%0d data=%08x", idx, rdata);
                MAC_CSR_RD: return $sformatf("CSR_RD 0x%03x = %08x%s", csr_addr, rdata, drained ? " (drained)" : "");
                MAC_CSR_WR: return $sformatf("CSR_WR 0x%03x <- %08x", csr_addr, csr_wdata);
                MAC_POP:    return "POP (CHECK)";
                default:    return "RESET";
            endcase
        endfunction
    endclass

    typedef uvm_sequencer #(mac_cmd_item) mac_cmd_sequencer;

    class mac_cmd_driver extends uvm_driver #(mac_cmd_item);
        `uvm_component_utils(mac_cmd_driver)

        virtual mac_cmd_if vif;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual mac_cmd_if)::get(this, "", "cmd_vif", vif))
                `uvm_fatal("NOVIF", "mac_cmd_driver: no cmd_vif in uvm_config_db")
        endfunction

        // Every wait for an edge goes through tick(), which records when the driver last stood at a
        // clocking event. A sequence may hand over an item in a time step where the driver did not see the
        // event (for example the first item, started by the test right at an edge): a drive issued then
        // could take effect one cycle early or be lost, so drive() first realigns to a clocking event.
        // Items that follow each other in zero time are already aligned and stay back to back.
        realtime t_cb = -1.0;

        task tick();
            @(vif.drv_cb);
            t_cb = $realtime;
        endtask

        task run_phase(uvm_phase phase);
            // known values before the first edge, then synchronous drives only
            vif.cmd_valid = 1'b0; vif.cmd_op = '0; vif.cmd_addr = '0; vif.cmd_k = '0; vif.cmd_clr = 1'b0;
            vif.rd_req = 1'b0; vif.rd_idx = '0;
            vif.csr_we = 1'b0; vif.csr_addr = CSR_NPU_STATUS; vif.csr_wdata = '0; vif.csr_re = 1'b0;
            tick();
            forever begin
                seq_item_port.get_next_item(req);
                if ($realtime != t_cb) tick();
                repeat (req.gap) tick();
                drive(req);
                seq_item_port.item_done();
            end
        endtask

        // Called at a clocking event (t_cb = now); every branch ends at a clocking event.
        task drive(mac_cmd_item it);
            it.wait_cycles = 0;
            case (it.kind)
                MAC_PUSH: begin
                    vif.drv_cb.cmd_op    <= it.op;
                    vif.drv_cb.cmd_addr  <= it.addr;
                    vif.drv_cb.cmd_k     <= it.k;
                    vif.drv_cb.cmd_clr   <= it.clr;
                    vif.drv_cb.cmd_valid <= 1'b1;
                    tick();
                    while (vif.drv_cb.cmd_ready !== 1'b1) begin   // accepted at the first edge with ready
                        it.wait_cycles++;
                        tick();
                    end
                    vif.drv_cb.cmd_valid <= 1'b0;                 // a following PUSH with gap 0 overrides it
                end
                MAC_READ: begin
                    vif.drv_cb.rd_idx <= it.idx;
                    vif.drv_cb.rd_req <= 1'b1;
                    tick();
                    while (vif.drv_cb.rd_ready !== 1'b1) begin    // READ_RESULT waits for the drain (spec 6.3 rule 4)
                        it.wait_cycles++;
                        tick();
                    end
                    it.rdata = vif.drv_cb.rd_data;
                    vif.drv_cb.rd_req <= 1'b0;
                end
                MAC_CSR_RD: begin
                    vif.drv_cb.csr_addr <= it.csr_addr;
                    vif.drv_cb.csr_re   <= 1'b1;
                    tick();
                    it.rdata = vif.drv_cb.csr_rdata;
                    vif.drv_cb.csr_re   <= 1'b0;
                end
                MAC_CSR_WR: begin
                    vif.drv_cb.csr_addr  <= it.csr_addr;
                    vif.drv_cb.csr_wdata <= it.csr_wdata;
                    vif.drv_cb.csr_we    <= 1'b1;
                    tick();
                    vif.drv_cb.csr_we    <= 1'b0;
                end
                default: `uvm_error("DRV", $sformatf("cannot drive item kind %s", it.kind.name()))
            endcase
        endtask
    endclass

    class mac_cmd_monitor extends uvm_monitor;
        `uvm_component_utils(mac_cmd_monitor)

        virtual mac_cmd_if vif;
        uvm_analysis_port #(mac_cmd_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
            ap = new("ap", this);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            if (!uvm_config_db #(virtual mac_cmd_if)::get(this, "", "cmd_vif", vif))
                `uvm_fatal("NOVIF", "mac_cmd_monitor: no cmd_vif in uvm_config_db")
        endfunction

        function void publish(mac_cmd_item it);
            `uvm_info("MON", it.convert2string(), UVM_HIGH)
            ap.write(it);
        endfunction

        task run_phase(uvm_phase phase);
            bit in_reset = 1'b0;
            mac_cmd_item it;
            forever begin
                @(vif.mon_cb);
                if (vif.mon_cb.rst_n !== 1'b1) begin
                    if (!in_reset) begin
                        it = mac_cmd_item::type_id::create("reset");
                        it.kind = MAC_RESET;
                        publish(it);
                    end
                    in_reset = 1'b1;
                    continue;
                end
                in_reset = 1'b0;
                if (vif.mon_cb.csr_re === 1'b1) begin
                    it = mac_cmd_item::type_id::create("csr_rd");
                    it.kind      = MAC_CSR_RD;
                    it.csr_addr  = vif.mon_cb.csr_addr;
                    it.rdata     = vif.mon_cb.csr_rdata;
                    it.drained   = (vif.mon_cb.rd_ready === 1'b1);
                    it.cmd_ready = (vif.mon_cb.cmd_ready === 1'b1);
                    publish(it);
                end
                if (vif.mon_cb.rd_req === 1'b1 && vif.mon_cb.rd_ready === 1'b1) begin
                    it = mac_cmd_item::type_id::create("read");
                    it.kind  = MAC_READ;
                    it.idx   = vif.mon_cb.rd_idx;
                    it.rdata = vif.mon_cb.rd_data;
                    publish(it);
                end
                if (vif.mon_cb.csr_we === 1'b1) begin
                    it = mac_cmd_item::type_id::create("csr_wr");
                    it.kind      = MAC_CSR_WR;
                    it.csr_addr  = vif.mon_cb.csr_addr;
                    it.csr_wdata = vif.mon_cb.csr_wdata;
                    publish(it);
                end
                if (vif.mon_cb.eng_pop === 1'b1) begin
                    it = mac_cmd_item::type_id::create("pop");
                    it.kind = MAC_POP;
                    publish(it);
                end
                if (vif.mon_cb.cmd_valid === 1'b1 && vif.mon_cb.cmd_ready === 1'b1) begin
                    it = mac_cmd_item::type_id::create("push");
                    it.kind = MAC_PUSH;
                    it.op   = npu_op_e'(vif.mon_cb.cmd_op);
                    it.addr = vif.mon_cb.cmd_addr;
                    it.k    = vif.mon_cb.cmd_k;
                    it.clr  = vif.mon_cb.cmd_clr;
                    publish(it);
                end
            end
        endtask
    endclass

    class mac_cmd_agent extends uvm_agent;
        `uvm_component_utils(mac_cmd_agent)

        mac_cmd_sequencer sqr;
        mac_cmd_driver    drv;
        mac_cmd_monitor   mon;
        uvm_analysis_port #(mac_cmd_item) ap;

        function new(string name, uvm_component parent);
            super.new(name, parent);
        endfunction

        function void build_phase(uvm_phase phase);
            super.build_phase(phase);
            sqr = mac_cmd_sequencer::type_id::create("sqr", this);
            drv = mac_cmd_driver::type_id::create("drv", this);
            mon = mac_cmd_monitor::type_id::create("mon", this);
        endfunction

        function void connect_phase(uvm_phase phase);
            drv.seq_item_port.connect(sqr.seq_item_export);
            ap = mon.ap;
        endfunction
    endclass
endpackage : mac_cmd_agent_pkg
