// S3: one coverpoint, 4 explicit bins, 2 of them hit -> 50.00 %.
module cov_tb;
  bit [1:0] v;
  covergroup cg;
    cp: coverpoint v { bins b0 = {0}; bins b1 = {1}; bins b2 = {2}; bins b3 = {3}; }
  endgroup
  cg c = new();
  initial begin
    v = 0; c.sample();
    v = 1; c.sample();
    $display("coverage=%0.2f", c.get_inst_coverage());
    $finish;
  end
endmodule
