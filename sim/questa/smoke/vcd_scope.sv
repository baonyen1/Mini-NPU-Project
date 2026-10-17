// S7: a DUT with an inner scope; only tb_vcd/dut/* must reach the VCD.
module inner(input logic clk, output logic [3:0] q);
  always @(posedge clk) q <= q + 1;
  initial q = 0;
endmodule
module tb_vcd;
  logic clk = 0, other = 0;
  logic [3:0] q;
  always #5 clk = ~clk;
  always #7 other = ~other;      // must NOT appear in the VCD
  inner dut(.clk(clk), .q(q));
endmodule
