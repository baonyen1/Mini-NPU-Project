`timescale 1ns/1ps
// Non-graded support tooling (presentation figure only).
// A second top-level module compiled next to tb_dump.v: Icarus elaborates every
// uninstantiated module as a root, so this adds a VCD dump without editing tb_dump.v.
// It dumps only the signals the "ISA tour" figure needs, to keep the file small
// and the GTKWave view readable on a projector.
//   +VCD=<path>   enable the dump and set the file name (no plusarg = no dump)
module wave_dump;
  reg [8*256-1:0] vcd_name;
  initial begin
    if ($value$plusargs("VCD=%s", vcd_name)) begin
      $dumpfile(vcd_name);
      // clock / reset
      $dumpvars(0, tb_dump.clk, tb_dump.reset);
      // retire port (RVVI): one rvvi_valid pulse per retired instruction
      $dumpvars(0, tb_dump.dut.rvvi_valid, tb_dump.dut.rvvi_pc, tb_dump.dut.rvvi_insn,
                   tb_dump.dut.rvvi_rd, tb_dump.dut.rvvi_rd_wdata);
      // custom-0 handshakes with the engine stub
      $dumpvars(0, tb_dump.dut.cmd_valid, tb_dump.dut.cmd_ready, tb_dump.dut.cmd_op,
                   tb_dump.dut.rd_req, tb_dump.dut.rd_ready, tb_dump.dut.rd_data);
      // divider busy (EX-stage stall source) and the fetch PC
      $dumpvars(0, tb_dump.dut.u_core.div_busy, tb_dump.dut.imem_addr);
    end
  end
endmodule
