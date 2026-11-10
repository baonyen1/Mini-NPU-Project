# npu_top directed program (plan Phase 2 Task 14): the core stalls on a full command FIFO
# (spec 6.3 rule 3; FIFO_DEPTH = 8) and the results are still right.
#   1  LDW, LDI, then COMPUTE clr = 1 and 19 x COMPUTE clr = 0, K = 64, issued back to back
#      (22 commands, 16 cycles each in the engine): results = 20 * e1 (table e20)
#   2  COMPUTE clr = 1, then 10 x (LDW, LDI, COMPUTE clr = 0), 31 commands back to back:
#      results = 11 * e1 (table e11; the reloads write the same data)
# t_fifo_full.plusargs adds +EXPECT_STALL: npu_top_chk fails the run if the core never stalled on
# cmd_ready (so the test cannot pass without exercising the full FIFO).
    .option norelax
    .include "common.inc"

    .text
    .globl _start
_start:
    li    s0, SIM_CTRL
    li    s1, SIM_PUTC
    li    s3, 0
    la    a0, w64
    la    a1, i64
    li    a2, 64

    STEP  1
    NPU_LDW a0, a2
    NPU_LDI a1, a2
    NPU_MAC a2, 1
    .rept 19
    NPU_MAC a2, 0
    .endr
    la    a4, e20
    call  chk16

    STEP  2
    NPU_MAC a2, 1
    .rept 10
    NPU_LDW a0, a2
    NPU_LDI a1, a2
    NPU_MAC a2, 0
    .endr
    la    a4, e11
    call  chk16
    j     pass

    .include "common_end.inc"

    .data
    .include "data_k64.inc"
msg_ok:
    .asciz "fifo_full ok\n"
msg_bad:
    .asciz "FAIL step "
    .balign 4
