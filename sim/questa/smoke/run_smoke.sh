#!/usr/bin/env bash
# Runs S1, S2, S3, S7 on QuestaSim. Logs go to out/ (gitignored).
set -u
QUESTA_HOME=${QUESTA_HOME:-/c/questasim64_10.7c}
cd "$(dirname "$0")"
mkdir -p out; rm -rf work
vlib work >/dev/null
echo "== S1 UVM =="
vlog -sv -work work uvm_hello.sv > out/s1_vlog.log 2>&1
vsim -c -work work tb_top +UVM_TESTNAME=hello_test -do "run -all; quit -f" > out/s1_vsim.log 2>&1
grep -E "\[HELLO\]|UVM_ERROR :|UVM_FATAL :|Error|license" out/s1_vsim.log
echo "== S2 DPI-C =="
gcc -shared -I"$QUESTA_HOME/include" -o out/dpi_add.dll dpi_add.c
vlog -sv -work work dpi_tb.sv > out/s2_vlog.log 2>&1
vsim -c -work work dpi_tb -sv_lib out/dpi_add -do "run -all; quit -f" > out/s2_vsim.log 2>&1
grep -E "c_add|c_xor32|Error" out/s2_vsim.log
echo "== S3 coverage =="
vlog -sv -work work cov_tb.sv > out/s3_vlog.log 2>&1
vsim -c -coverage -work work cov_tb -do "coverage save -onexit out/cov.ucdb; run -all; quit -f" > out/s3_vsim.log 2>&1
grep -E "coverage=|Error" out/s3_vsim.log
vcover report -details out/cov.ucdb > out/s3_report.txt 2>&1
grep -E "Covergroup|cp |TOTAL|%" out/s3_report.txt | head
echo "== S7 VCD scope =="
vlog -sv -work work vcd_scope.sv > out/s7_vlog.log 2>&1
vsim -c -voptargs=+acc -work work tb_vcd -do vcd_scope.do > out/s7_vsim.log 2>&1
grep -E "[$]var" engine.vcd
