// S4: toy icg_cell (latch transparent while clk low, then AND), spec section 8.
module icg_cell (input logic clk, input logic en, output logic gclk);
  logic en_l;
  always_latch if (!clk) en_l = en;
  assign gclk = clk & en_l;
endmodule

module icg_tb;
  logic clk = 0, en = 1;
  logic gclk;
  int   cycle = 0;
  icg_cell dut (.clk(clk), .en(en), .gclk(gclk));
  always #5 clk = ~clk;
  // en is changed on the falling edge; low for cycles 10..19
  always @(negedge clk) begin
    cycle <= cycle + 1;
    en    <= !(cycle + 1 >= 10 && cycle + 1 <= 19);
  end
  initial begin
`ifdef VERILATOR
    $dumpfile("icg.vcd");
`else
    $dumpfile("icg.vcd");
`endif
    $dumpvars(0, icg_tb);
    #(5 * 2 * 30);
    $finish;
  end
endmodule
