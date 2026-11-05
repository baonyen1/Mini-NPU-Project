#!/usr/bin/env bash
# Task 11 stage 1: runs tb/directed/cmd_fifo_tb.sv on QuestaSim (Git Bash on Windows, or Linux), at the
# package depth (8) and at a depth that is not a power of two (5). Logs go to out/ (gitignored).
# Needs vlog/vsim on PATH (Windows: C:\questasim64_10.7c\win64). Exit 0 only if both runs print RESULT: PASS.
set -u
cd "$(dirname "$0")"
ROOT=../..
mkdir -p out; rm -rf out/work_fifo
vlib out/work_fifo >/dev/null
vlog -sv -work out/work_fifo "$ROOT/rtl/top/npu_pkg.sv" "$ROOT/rtl/npu/cmd_fifo.sv" \
     "$ROOT/tb/directed/cmd_fifo_tb.sv" > out/cmd_fifo_vlog.log 2>&1 || { cat out/cmd_fifo_vlog.log; exit 1; }
status=0
for depth in 8 5; do
    vsim -c -lib out/work_fifo -GDEPTH=$depth cmd_fifo_tb -do "run -all; quit -f" > out/cmd_fifo_d$depth.log 2>&1
    verdict=$(grep -E "RESULT:|Fatal|Error" out/cmd_fifo_d$depth.log | head -n 1)
    echo "DEPTH=$depth: $verdict"
    grep -q "RESULT: PASS" out/cmd_fifo_d$depth.log || status=1
done
exit $status
