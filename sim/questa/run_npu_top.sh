#!/usr/bin/env bash
# Task 14: runs the npu_top directed programs (tb/directed/prog/t_*.S, prebuilt hex files) on
# tb/directed/npu_top_tb.sv with QuestaSim, from Git Bash on Windows or from Linux. Logs go to
# sim/questa/out/ (gitignored).
#   bash sim/questa/run_npu_top.sh                  every program in D0 and D1, then checks that each
#                                                   program takes the same number of cycles in both (SC3)
#   bash sim/questa/run_npu_top.sh t_err_k          one program, D0 and D1
#   GATING=0 bash sim/questa/run_npu_top.sh         D0 only (GATING=1: D1 only, -GGATING_EN=1)
# Needs vlog/vsim on PATH (Windows: C:\questasim64_10.7c\win64). The hex files come from
# tb/directed/prog/build.sh (WSL). Exit 0 only if every run ends with RESULT: PASS, vsim exits with
# 0, no log has an "** Error" or "** Fatal" line, the checker summary is there without an ERROR line,
# every D1 run gated clk_mac off for at least one cycle, and, when both configurations run, the
# cycle counts agree.
set -u
cd "$(dirname "$0")/../.."                 # repo root: rtl/rtl.f lists paths relative to it
OUT=sim/questa/out
PROG=tb/directed/prog
mkdir -p "$OUT"; rm -rf "$OUT/work_npu_top"
vlib "$OUT/work_npu_top" >/dev/null
vlog -sv -work "$OUT/work_npu_top" -f rtl/rtl.f tb/directed/npu_top_tb.sv tb/directed/npu_top_chk.sv \
     > "$OUT/npu_top_vlog.log" 2>&1 || { cat "$OUT/npu_top_vlog.log"; exit 1; }

case "${GATING:-both}" in
    0) CONFIGS="0" ;; 1) CONFIGS="1" ;; both) CONFIGS="0 1" ;;
    *) echo "run_npu_top.sh: GATING must be 0, 1 or both"; exit 2 ;;
esac
if [ $# -ge 1 ]; then PROGS="$*"; else PROGS=$(cd "$PROG" && ls t_*.itcm.hex | sed 's/\.itcm\.hex$//'); fi

status=0
for p in $PROGS; do
    [ -f "$PROG/$p.itcm.hex" ] || { echo "run_npu_top.sh: $PROG/$p.itcm.hex missing (run build.sh)"; status=1; continue; }
    PLUS="+ITCM=$PROG/$p.itcm.hex"
    [ -f "$PROG/$p.dtcm.hex" ] && PLUS="$PLUS +DTCM=$PROG/$p.dtcm.hex"
    [ -f "$PROG/$p.plusargs" ] && PLUS="$PLUS $(tr -d '\015' < "$PROG/$p.plusargs")"   # optional extra plusargs, e.g. +EXPECT_STALL
    cycles=""
    for g in $CONFIGS; do
        log="$OUT/npu_top_${p}_d$g.log"
        rm -f "$log"                       # a stale log from an earlier run must not be graded
        vsim -c -lib "$OUT/work_npu_top" -GGATING_EN=$g npu_top_tb npu_top_chk_bind $PLUS -l "$log" \
             -do "run -all; quit -f" > /dev/null 2>&1
        rc=$?
        echo "---- $p D$g"
        [ -f "$log" ] || { echo "run_npu_top.sh: vsim wrote no log"; status=1; continue; }
        grep -E "^# (npu_top_tb:|npu_top_chk:|busy delta|PASS|FAIL|RESULT|\*\* (Error|Fatal))" "$log" | sed 's/^# //'
        [ "$rc" -eq 0 ] || { echo "run_npu_top.sh: vsim exit code $rc"; status=1; }
        if grep -qE "^# \*\* (Error|Fatal)" "$log"; then echo "run_npu_top.sh: ** Error/Fatal in $log"; status=1; fi
        grep -q "^# RESULT: PASS" "$log" || status=1
        # D1 must really gate clk_mac (npu_top_tb also fails RESULT for this); checked here as well
        # so that a testbench that stops printing the line cannot pass D1.
        if [ "$g" = "1" ]; then
            gated=$(sed -n 's/^# npu_top_tb: clk_mac .*gated_off=\([0-9-]*\).*/\1/p' "$log" | tail -n 1)
            if [ -z "$gated" ] || [ "$gated" -le 0 ]; then
                echo "run_npu_top.sh: D1 run with clk_mac gated off for '${gated:-?}' cycles (need > 0)"; status=1
            fi
        fi
        # the checker bound into npu_top (tb/directed/npu_top_chk.sv) must have run and found nothing
        grep -q "^# npu_top_chk: summary" "$log" || { echo "npu_top_chk: summary missing"; status=1; }
        if grep -q "^# npu_top_chk: ERROR" "$log"; then status=1; fi
        cycles="$cycles $(sed -n 's/^# npu_top_tb: .*cycles=\([0-9]*\).*/\1/p' "$log" | tail -n 1)"
    done
    if [ "$CONFIGS" = "0 1" ]; then
        set -- $cycles
        if [ "$#" -eq 2 ] && [ "$1" = "$2" ]; then
            echo "---- $p: D0 and D1 cycle-identical ($1 cycles)"
        else
            echo "---- $p: D0/D1 cycle counts differ or missing:$cycles"; status=1
        fi
    fi
done
if [ $status -eq 0 ]; then echo "RUN_NPU_TOP: PASS"; else echo "RUN_NPU_TOP: FAIL"; fi
exit $status
