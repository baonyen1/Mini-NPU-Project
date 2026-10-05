`timescale 1ns / 1ps

// ============================================================
// RISC_V_Impl_Top
//
// Synthesis/implementation wrapper for the RISC-V + Q-learning DFS
// system. RISC_V_Top exposes many internal debug buses for simulation.
// If that module is used directly as the implementation top, Vivado maps
// every debug bit to a physical IO pin and placement fails.
//
// This wrapper keeps CPU debug buses internal and exposes only the real
// DFS/frequency control outputs:
//   freq_idx          : 1..4 = 25/50/75/100 MHz
//   freq_update_valid : one-cycle pulse when DFS updates freq_idx
//   cpu_en            : effective CPU clock-enable generated from freq_idx
//   debug_led         : compact debug status
// ============================================================
module RISC_V_Impl_Top #(
    // Keep exploration enabled in the implementation build. Simulation
    // testbenches can set EPSILON=0 for deterministic policy evaluation.
    parameter [7:0] EPSILON = 8'd20
)(
    input  wire              clk,
    input  wire              reset,

    input  wire [7:0]        current_state,
    input  wire              valid_state,
    input  wire [7:0]        next_state,
    input  wire signed [15:0] reward,
    input  wire              reward_valid,

    output wire [2:0]        freq_idx,
    output wire              freq_update_valid,
    output wire              cpu_en,
    output wire [3:0]        debug_led
);

wire        rst_n;
wire signed [2:0] action_out;
wire              action_valid;
wire              agent_ready;
wire [2:0]        freq_before;
wire [2:0]        freq_after;
wire signed [2:0] applied_action;

wire [31:0] Instruction_IF_ID;
wire [31:0] Instruction_address_IF_ID;
wire [31:0] Instruction_address_ID_EX;
wire [31:0] Instruction_address_EX_MEM;
wire [31:0] Instruction_address_MEM_WB;
wire [31:0] alu_out_EX_MEM;
wire [31:0] regfile_write_data_WB;
wire        jump_branch_signal;
wire [2:0]  workload_raw_util;
reg  [2:0]  workload_util;
wire        workload_valid;
wire [8:0]  workload_activity_q8;
wire [7:0]  monitored_current_state;
wire [7:0]  monitored_next_state;

reg [1:0] cpu_en_phase;
reg       cpu_en_reg;
reg [2:0] cpu_en_window_count;
reg [2:0] cpu_en_observed_per_4;

assign rst_n  = ~reset;
assign cpu_en = cpu_en_reg;

// The frequency nibble still comes from the control/test environment, while
// the utilization nibble is always supplied by the hardware monitor.
// On valid_state, the agent sees the newest filtered monitor value while the
// same value is latched for debug and held throughout the complete episode.
assign monitored_current_state = {
    1'b0,
    valid_state ? workload_raw_util : workload_util,
    current_state[3:0]
};
assign monitored_next_state = {1'b0, workload_raw_util, next_state[3:0]};

always @(posedge clk or posedge reset) begin
    if (reset)
        workload_util <= 3'd1;
    else if (valid_state)
        workload_util <= workload_raw_util;
end

ql_dvfs_top #(
    .STATE_BITS   (8),
    .DATA_WIDTH   (16),
    .ADDR_WIDTH   (11),
    .EPSILON      (EPSILON),
    .ALPHA_SHIFT  (3),
    .GAMMA_SHIFT  (2),
    .FREQ_BITS    (3),
    .MIN_FREQ     (1),
    .MAX_FREQ     (4),
    .INITIAL_FREQ (2)
) DFS_CORE (
    .clk              (clk),
    .rst_n            (rst_n),
    .current_state    (monitored_current_state),
    .valid_state      (valid_state),
    .next_state       (monitored_next_state),
    .reward           (reward),
    .reward_valid     (reward_valid),
    .action_out       (action_out),
    .action_valid     (action_valid),
    .agent_ready      (agent_ready),
    .freq_idx         (freq_idx),
    .freq_before      (freq_before),
    .freq_after       (freq_after),
    .applied_action   (applied_action),
    .freq_update_valid(freq_update_valid)
);

// Effective-frequency model for simulation/synthesis demo:
// freq_idx 1 -> enable 1/4 cycles, 2 -> 2/4, 3 -> 3/4, 4 -> 4/4.
// The real FPGA clock is still clk; cpu_en throttles the CPU pipeline.
always @(posedge clk or posedge reset) begin
    if (reset) begin
        cpu_en_phase <= 2'b00;
        cpu_en_reg   <= 1'b0;
        cpu_en_window_count <= 3'd0;
        cpu_en_observed_per_4 <= 3'd0;
    end else if (freq_update_valid) begin
        // Start a fresh four-cycle observation window after every frequency
        // change so the debug count never mixes two different freq_idx values.
        cpu_en_phase          <= 2'b00;
        cpu_en_reg            <= 1'b0;
        cpu_en_window_count   <= 3'd0;
        cpu_en_observed_per_4 <= 3'd0;
    end else begin
        cpu_en_phase <= cpu_en_phase + 2'b01;

        if (cpu_en_phase == 2'd3) begin
            cpu_en_observed_per_4 <= cpu_en_window_count + cpu_en_reg;
            cpu_en_window_count   <= 3'd0;
        end else if (cpu_en_reg) begin
            cpu_en_window_count <= cpu_en_window_count + 3'd1;
        end

        case (freq_idx)
            3'd1: cpu_en_reg <= (cpu_en_phase == 2'd0);
            3'd2: cpu_en_reg <= (cpu_en_phase[0] == 1'b0);
            3'd3: cpu_en_reg <= (cpu_en_phase != 2'd3);
            3'd4: cpu_en_reg <= 1'b1;
            default: cpu_en_reg <= 1'b0;
        endcase
    end
end

(* dont_touch = "true" *)
RISC_V_Top CPU_CORE(
    .clk(clk),
    .reset(reset),
    .cpu_en(cpu_en),

    .Instruction_IF_ID(Instruction_IF_ID),
    .Instruction_address_IF_ID(Instruction_address_IF_ID),
    .Instruction_address_ID_EX(Instruction_address_ID_EX),
    .Instruction_address_EX_MEM(Instruction_address_EX_MEM),
    .Instruction_address_MEM_WB(Instruction_address_MEM_WB),
    .alu_out_EX_MEM(alu_out_EX_MEM),
    .regfile_write_data_WB(regfile_write_data_WB),
    .jump_branch_signal(jump_branch_signal),
    .workload_raw_util(workload_raw_util),
    .workload_valid(workload_valid),
    .workload_activity_q8(workload_activity_q8)
);

assign debug_led = {
    agent_ready,
    action_valid,
    freq_update_valid,
    jump_branch_signal
};

endmodule
