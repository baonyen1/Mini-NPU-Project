`timescale 1ns/1ps
// Non-graded verification harness: runs core_tb_top (core + ITCM + DTCM + SIM MMIO + engine stub),
// then dumps the architectural state to rtl_state.txt: x1..x31 and the first MEM_WORDS DTCM words.
// The run ends after +CYCLES cycles, or one cycle after a SIM_CTRL PASS/FAIL write (sim_done).
`ifndef MEM_WORDS
`define MEM_WORDS 1024
`endif
module tb_dump;
  reg clk=0, reset=1;
  wire sim_done;
  core_tb_top dut(.clk(clk), .reset(reset), .sim_done(sim_done));
  always #5 clk=~clk;
  integer k, f, cycles;
  reg dumped = 0;
  task dump_state;
    begin
      if (!dumped) begin
        dumped = 1;
        f = $fopen("rtl_state.txt","w");
        for (k=1;k<32;k=k+1) $fwrite(f,"x%0d %08x\n",k,dut.u_core.DECODE_STAGE.REGFILE.regs[k]);
        for (k=0;k<`MEM_WORDS;k=k+1) $fwrite(f,"m%0d %08x\n",k,dut.u_dtcm.mem[k]);
        $fclose(f);
      end
    end
  endtask
  initial begin
    if (!$value$plusargs("CYCLES=%d", cycles)) cycles = 2000;
    repeat(3) @(posedge clk); @(negedge clk) reset = 0;
    repeat(cycles) @(posedge clk);
    dump_state; $finish;
  end
  always @(posedge clk) if (sim_done) begin dump_state; $finish; end
endmodule
