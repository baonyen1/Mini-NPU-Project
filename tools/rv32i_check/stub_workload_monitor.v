// TEMPORARY stub so rtl/core compiles without Senior Project 1 DFS blocks.
// run.py includes this file only while RISC_V_Top.v still instantiates
// workload_monitor. Remove the instance from RISC_V_Top.v, then delete this file.
module workload_monitor #(parameter WINDOW_SAMPLES=32, LOW_MAX_Q8=64, MED_MAX_Q8=112, HIGH_MAX_Q8=160)(
  input clk, reset, cpu_en, input [31:0] instruction, input load_use_stall, pipeline_flush,
  output [2:0] util_level, output util_valid, output [8:0] activity_q8);
  assign util_level = 3'd0; assign util_valid = 1'b0; assign activity_q8 = 9'd0;
endmodule
