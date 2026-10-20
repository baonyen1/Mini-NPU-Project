`timescale 1ns/1ps
// Non-graded verification harness: runs program.hex, dumps arch state.
// Hierarchy paths and the number of dumped data words are macro-selectable so
// the harness can follow plan Task 8 (spec memory map):
//   MEM_WORDS      number of data words written to rtl_state.txt (run.py passes it)
//   RF_PATH        register-file array of the DUT
//   DMEM_PATH      data-memory word array of the DUT
`ifndef MEM_WORDS
`define MEM_WORDS 256
`endif
`ifndef RF_PATH
`define RF_PATH dut.DECODE_STAGE.REGFILE.regs
`endif
`ifndef DMEM_PATH
`define DMEM_PATH dut.MEMORY_STAGE.LOAD_STORE_UNIT.DATA_MEMORY.memory
`endif
module tb_dump;
  reg clk=0, reset=1;
  wire [31:0] i0,i1,i2,i3,i4,i5,i6; wire j;
  RISC_V_Top dut(.clk(clk),.reset(reset),
    .Instruction_IF_ID(i0),.Instruction_address_IF_ID(i1),.Instruction_address_ID_EX(i2),
    .Instruction_address_EX_MEM(i3),.Instruction_address_MEM_WB(i4),.alu_out_EX_MEM(i5),
    .regfile_write_data_WB(i6),.jump_branch_signal(j));
  always #5 clk=~clk;
  integer k, f, cycles;
  initial begin
    if (!$value$plusargs("CYCLES=%d", cycles)) cycles = 2000;
    repeat(3) @(posedge clk); @(negedge clk) reset = 0;
    repeat(cycles) @(posedge clk);
    f = $fopen("rtl_state.txt","w");
    for (k=1;k<32;k=k+1) $fwrite(f,"x%0d %08x\n",k,`RF_PATH[k]);
    for (k=0;k<`MEM_WORDS;k=k+1) $fwrite(f,"m%0d %08x\n",k,`DMEM_PATH[k]);
    $fclose(f); $finish;
  end
endmodule
