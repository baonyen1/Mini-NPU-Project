# isa_tour_wave.do -- QuestaSim view of the ISA-tour VCD (non-graded support tooling)
#
# In the QuestaSim Transcript (Tcl: use forward slashes):
#   cd C:/Users/nguye/Documents/3RD/SeniorProject/SeniorProject2/tools/rv32i_check
#   vcd2wlf build/isa_tour.vcd build/isa_tour.wlf
#   dataset close -all
#   vsim -view tour=build/isa_tour.wlf -do wave/isa_tour_wave.do
# ("tour=" fixes the dataset name; without it a second open becomes "isa_tour2"
#  and the paths below no longer match.)
#
# Then switch views by typing in the Transcript:
#   v0  whole run            (0 - 610 ns)
#   v1  M / Zbb / Zicsr / Zifencei   (55 - 165 ns)
#   v2  custom-0 handshakes  (165 - 235 ns)
#   v3  divider, 34 cycles   (185 - 560 ns)
#
# Timing in this run: clock period 10 ns, rising edges at 5 + 10k ns, reset released at 30 ns.

set D tour:/tb_dump

# ---- names instead of hex: instruction words and register numbers ----------------
radix define isa_insn {
    32'hff900093 addi_x1_-7,
    32'h00300113 addi_x2_3,
    32'h022081b3 mul_x3,
    32'h0a20e233 max_x4,
    32'h60209293 cpop_x5,
    32'hb0202373 csrr_x6_minstret,
    32'h0000100f fence.i,
    32'h00010437 lui_x8,
    32'h04040413 addi_x8,
    32'h00400493 li_x9_4,
    32'h0094000b LOAD_WEIGHT,
    32'h00500593 li_x11_5,
    32'h0005b50b READ_RESULT_x10,
    32'h0220c3b3 div_x7,
    32'h0000006f j_end,
    32'h00000013 bubble,
    -default hex
}
radix define isa_rd {
    5'd0 x0, 5'd1 x1, 5'd2 x2, 5'd3 x3, 5'd4 x4, 5'd5 x5,
    5'd6 x6, 5'd7 x7, 5'd8 x8, 5'd9 x9, 5'd10 x10, 5'd11 x11,
    -default unsigned
}

# ---- signals ----------------------------------------------------------------------
add wave -noupdate -divider {CLOCK}
add wave -noupdate -label clk   -color gray70 $D/clk
add wave -noupdate -label reset -color gray50 $D/reset

add wave -noupdate -divider {RETIRE (RVVI): one pulse = one instruction}
add wave -noupdate -label rvvi_valid -color {Spring Green} $D/dut/rvvi_valid
add wave -noupdate -label instruction -radix isa_insn -color Cyan -height 22 $D/dut/rvvi_insn
add wave -noupdate -label pc          -radix hex      -color Cyan $D/dut/rvvi_pc
add wave -noupdate -label rd          -radix isa_rd   -color Yellow $D/dut/rvvi_rd
add wave -noupdate -label rd_wdata    -radix hex      -color Yellow -height 22 $D/dut/rvvi_rd_wdata

add wave -noupdate -divider {CUSTOM-0 <-> ENGINE STUB}
add wave -noupdate -label cmd_valid -color Orange $D/dut/cmd_valid
add wave -noupdate -label cmd_ready -color Orange $D/dut/cmd_ready
add wave -noupdate -label cmd_op    -radix unsigned -color Orange $D/dut/cmd_op
add wave -noupdate -label rd_req    -color Magenta $D/dut/rd_req
add wave -noupdate -label rd_ready  -color Magenta $D/dut/rd_ready
add wave -noupdate -label rd_data   -radix hex -color Magenta $D/dut/rd_data

add wave -noupdate -divider {M DIVIDER / FETCH}
add wave -noupdate -label div_busy  -color Red $D/dut/u_core/div_busy
add wave -noupdate -label fetch_pc  -radix hex -color gray70 $D/dut/imem_addr

# ---- layout: ns timeline, one grid line per clock cycle ---------------------------
configure wave -namecolwidth 150
configure wave -valuecolwidth 170
configure wave -signalnamewidth 1
configure wave -timelineunits ns
configure wave -gridoffset 5ns
configure wave -gridperiod 10ns
update

# ---- cursors on the events you talk about ----------------------------------------
wave cursor add -time 85ns  -name {mul}
wave cursor add -time 125ns -name {fence.i}
wave cursor add -time 155ns -name {after 2 bubbles}
wave cursor add -time 175ns -name {cmd push}
wave cursor add -time 225ns -name {READ_RESULT retires}
wave cursor add -time 545ns -name {div retires}

# ---- views ------------------------------------------------------------------------
proc v0 {} { wave zoom range 0ns 610ns }
proc v1 {} { wave zoom range 55ns 165ns }
proc v2 {} { wave zoom range 165ns 235ns }
proc v3 {} { wave zoom range 185ns 560ns }
v1
echo "views: v0 (all) | v1 (M/Zbb/Zicsr/Zifencei) | v2 (custom-0) | v3 (divider)"
