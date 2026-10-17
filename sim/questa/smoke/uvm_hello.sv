// S1: Questa UVM + constrained randomization smoke test.
`include "uvm_macros.svh"
import uvm_pkg::*;

class rnd_item;
  rand bit [7:0] x;
  constraint c { x < 10; }
endclass

class hello_test extends uvm_test;
  `uvm_component_utils(hello_test)
  function new(string name, uvm_component parent);
    super.new(name, parent);
  endfunction
  task run_phase(uvm_phase phase);
    rnd_item it = new();
    phase.raise_objection(this);
    if (!it.randomize()) `uvm_error("HELLO", "randomize failed")
    `uvm_info("HELLO", $sformatf("Questa UVM ok, x=%0d", it.x), UVM_LOW)
    if (it.x >= 10) `uvm_error("HELLO", "constraint violated")
    phase.drop_objection(this);
  endtask
endclass

module tb_top;
  initial run_test();
endmodule
