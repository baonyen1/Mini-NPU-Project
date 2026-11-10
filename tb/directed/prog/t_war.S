# npu_top directed program (plan Phase 2 Task 14, t_war_safe; spec 6.3 rule 5): the WAR rule.
# buf_w/buf_i hold data set A (K = 16). Data sets A and B come from gen_data.py and differ at every
# result index.
#   1  LDW buf_w, LDI buf_i, COMPUTE clr = 1, READ_RESULT idx 0 (this drains the engine), then
#      overwrite buf_w/buf_i with set B, then READ_RESULT idx 1..15: all 16 results are still A
#      (the stores happened after the drain and cannot disturb the finished COMPUTE)
#   2  the same LDW/LDI/COMPUTE sequence on the overwritten buffers: all 16 results are B
#      (the engine reads what the core stored, i.e. port A writes are visible on port B)
#   3  overwrite with A again (right after a drain) and repeat: results are A again
    .option norelax
    .include "common.inc"

    .text
    .globl _start
_start:
    li    s0, SIM_CTRL
    li    s1, SIM_PUTC
    li    s3, 0
    li    a2, 16

    STEP  1
    la    a0, buf_w
    la    a1, buf_i
    NPU_LDW a0, a2
    NPU_LDI a1, a2
    NPU_MAC a2, 1
    li    s3, 0
    la    a4, ea
    NPU_RDR t0, s3                  # idx 0: the barrier
    lw    t1, 0(a4)
    bne   t0, t1, fail
    la    a5, src_b
    call  overwrite                 # WAR-safe: the engine is drained
    li    s3, 1
    la    a4, ea + 4
    call  chk_from                  # idx 1..15 of the finished COMPUTE (set A)

    STEP  2
    la    a0, buf_w
    la    a1, buf_i
    NPU_LDW a0, a2
    NPU_LDI a1, a2
    NPU_MAC a2, 1
    la    a4, eb
    call  chk16

    STEP  3
    la    a5, src_a
    call  overwrite                 # chk16 drained the engine
    la    a0, buf_w
    la    a1, buf_i
    NPU_LDW a0, a2
    NPU_LDI a1, a2
    NPU_MAC a2, 1
    la    a4, ea
    call  chk16
    j     pass

# overwrite(a5 = 32-word source): copies it over buf_w, buf_i (adjacent). Uses t0, t1, t2.
overwrite:
    la    t0, buf_w
    li    t2, 32
1:  lw    t1, 0(a5)
    sw    t1, 0(t0)
    addi  a5, a5, 4
    addi  t0, t0, 4
    addi  t2, t2, -1
    bnez  t2, 1b
    ret

# chk_from(s3 = first idx, a4 = table entry for it): checks idx s3..15. Uses t0, t1, s4.
chk_from:
    li    s4, 16
1:  NPU_RDR t0, s3
    lw    t1, 0(a4)
    bne   t0, t1, fail
    addi  a4, a4, 4
    addi  s3, s3, 1
    blt   s3, s4, 1b
    li    s3, 0
    ret

    .include "common_end.inc"

    .data
    .include "data_war.inc"
msg_ok:
    .asciz "war ok\n"
msg_bad:
    .asciz "FAIL step "
    .balign 4
