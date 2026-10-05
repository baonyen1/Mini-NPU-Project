`timescale 1ns/1ps
// Non-graded verification harness: runs program.hex, dumps arch state.
module tb_dump;
  reg clk=0, reset=1, cpu_en=1;
  wire [31:0] i0,i1,i2,i3,i4,i5,i6; wire j; wire [2:0] u; wire v; wire [8:0] a;
  RISC_V_Top dut(.clk(clk),.reset(reset),.cpu_en(cpu_en),
    .Instruction_IF_ID(i0),.Instruction_address_IF_ID(i1),.Instruction_address_ID_EX(i2),
    .Instruction_address_EX_MEM(i3),.Instruction_address_MEM_WB(i4),.alu_out_EX_MEM(i5),
    .regfile_write_data_WB(i6),.jump_branch_signal(j),.workload_raw_util(u),
    .workload_valid(v),.workload_activity_q8(a));
  always #5 clk=~clk;
  integer k, f, cycles;
  initial begin
    if (!$value$plusargs("CYCLES=%d", cycles)) cycles = 2000;
    repeat(3) @(posedge clk); @(negedge clk) reset = 0;
    repeat(cycles) @(posedge clk);
    f = $fopen("rtl_state.txt","w");
    for (k=1;k<32;k=k+1) $fwrite(f,"x%0d %08x\n",k,dut.DECODE_STAGE.REGFILE.regs[k]);
    for (k=0;k<256;k=k+1) $fwrite(f,"m%0d %08x\n",k,dut.MEMORY_STAGE.LOAD_STORE_UNIT.DATA_MEMORY.memory[k]);
    $fclose(f); $finish;
  end
endmodule
