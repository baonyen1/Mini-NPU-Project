// S2: ints and a bit [31:0] through DPI-C.
module dpi_tb;
  import "DPI-C" function int c_add(input int a, input int b);
  import "DPI-C" function void c_xor32(input bit [31:0] a, input bit [31:0] b, output bit [31:0] r);
  bit [31:0] r;
  initial begin
    $display("c_add(2,3)=%0d", c_add(2, 3));
    c_xor32(32'hFFFF0000, 32'h0F0F0F0F, r);
    $display("c_xor32=%08h", r);
    $finish;
  end
endmodule
