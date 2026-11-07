`timescale 1ns / 1ps

// mac_engine_bind - binds the spec 10.6 assertions (mac_engine_sva) and the white-box probe (mac_probe_if)
// into every mac_engine instance (Phase 2 Task 16). A bind applies to all instances of its target module,
// wherever the module holding it is elaborated, so any top that wraps mac_engine (mac_tb_top, and later
// Task 18's npu_tb_top) instantiates this module once and gets the same checks:
//     mac_engine_bind u_mac_engine_bind ();
// The port expressions are names inside mac_engine (state_q, u_fifo.count_q, head, ...). The probe's
// instance name u_probe is fixed: the tops reach it as <engine instance>.u_probe.
module mac_engine_bind;
    bind mac_engine mac_engine_sva u_sva (
        .clk          (clk),
        .rst_n        (rst_n),
        .state        (state_q),
        .fifo_do_push (u_fifo.do_push),
        .fifo_pop     (fifo_pop),
        .fifo_full    (fifo_full),
        .fifo_empty   (fifo_empty),
        .fifo_count   (u_fifo.count_q),
        .rd_ready     (rd_ready),
        .b_req        (b_req),
        .b_addr       (b_addr),
        .buf_we       (wr_pend_q),
        .head_k       (head.k),
        .head_addr    (head.addr)
    );

    bind mac_engine mac_probe_if u_probe (
        .clk        (clk),
        .rst_n      (rst_n),
        .state      (state_q),
        .fifo_count (u_fifo.count_q),
        .fifo_full  (fifo_full)
    );
endmodule
