# npu_top directed program (plan Phase 2 Task 14, t_read_all): K = 64 with fixed pseudo-random data.
# Tables come from gen_data.py (plain-Python dot products), not from the DUT.
#   1  LDW, LDI, COMPUTE clr = 1, COMPUTE clr = 0 back to back -> all 16 results = 2 * e1 (table e2)
#   2  COMPUTE clr = 1 again -> e1 (clr really clears)
#   3  COMPUTE clr = 0       -> e2
#   4  COMPUTE clr = 0       -> e3 (accumulation continues across READ_RESULT)
# READ_RESULT reads all 16 indexes each time (idx = 4*i + j).
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
    NPU_LDW a0, a2
    NPU_LDI a1, a2

    STEP  1
    NPU_MAC a2, 1
    NPU_MAC a2, 0
    la    a4, e2
    call  chk16

    STEP  2
    NPU_MAC a2, 1
    la    a4, e1
    call  chk16

    STEP  3
    NPU_MAC a2, 0
    la    a4, e2
    call  chk16

    STEP  4
    NPU_MAC a2, 0
    la    a4, e3
    call  chk16
    j     pass

    .include "common_end.inc"

    .data
    .include "data_k64.inc"
msg_ok:
    .asciz "read_all ok\n"
msg_bad:
    .asciz "FAIL step "
    .balign 4
