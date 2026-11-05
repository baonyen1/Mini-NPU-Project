#!/usr/bin/env bash
# Task 11: runs the mac_engine directed DPI suite (tb/directed/mac_engine_tb.sv) on QuestaSim, from Git Bash
# on Windows or from Linux. Builds model/c/npu_ref.c into the DPI library first. Logs go to out/ (gitignored).
#   bash sim/questa/run_mac_directed.sh            all tests
#   bash sim/questa/run_mac_directed.sh t_w1c      one test (+TEST=<name>)
# Needs vlog/vsim on PATH (Windows: C:\questasim64_10.7c\win64) and gcc. Exit 0 only on RESULT: PASS.
set -u
cd "$(dirname "$0")"
ROOT=../..
mkdir -p out; rm -rf out/work_mac
case "$(uname -s)" in MINGW*|MSYS*|CYGWIN*) LIB=out/npu_ref.dll ;; *) LIB=out/npu_ref.so ;; esac
gcc -std=c99 -O1 -shared -fPIC -I"$ROOT/model/c" -o "$LIB" "$ROOT/model/c/npu_ref.c" || exit 1
vlib out/work_mac >/dev/null
vlog -sv -work out/work_mac \
     "$ROOT/rtl/top/npu_pkg.sv" "$ROOT/rtl/npu/cmd_fifo.sv" "$ROOT/rtl/npu/mac_engine.sv" \
     "$ROOT/tb/uvm/common/npu_dpi_pkg.sv" "$ROOT/tb/directed/dtcm_model.sv" "$ROOT/tb/directed/mac_engine_tb.sv" \
     > out/mac_vlog.log 2>&1 || { cat out/mac_vlog.log; exit 1; }
PLUS=""
[ $# -ge 1 ] && PLUS="+TEST=$1"
vsim -c -lib out/work_mac -sv_lib "${LIB%.*}" mac_engine_tb $PLUS -do "run -all; quit -f" > out/mac_vsim.log 2>&1
grep -E "^# (PASS|FAIL|  FAIL|  latency|RESULT|---- |\*\* (Error|Fatal))" out/mac_vsim.log | sed 's/^# //'
grep -q "RESULT: PASS" out/mac_vsim.log
