# npu_top directed program (DV extension): the data-bus decode of npu_top. NOTE: the "reads 0 /
# writes ignored" policy for non-DTCM addresses is the provisional ruling of docs/core_isa.md
# (W2-1 still open), not a spec number; this test pins the policy so that a change is noticed.
#   1  lw from DTCM, then from SIM_CTRL (write-only MMIO) and from an unmapped address, back to
#      back, then from DTCM again: the DTCM word (0xDEADBEEF, also checked against the literal),
#      0, 0, the DTCM word. The 1-cycle DTCM read latency means the data-select must be
#      registered together with the request (dtcm_read_sel_q).
#   2  sw to an unmapped address is ignored (the following lw from it reads 0, the DTCM is intact)
#   3  byte stores: sb to the four byte lanes of one DTCM word, lw returns the combined word
    .option norelax
    .include "common.inc"

    .text
    .globl _start
_start:
    li    s0, SIM_CTRL
    li    s1, SIM_PUTC
    li    s3, 0

    STEP  1
    la    a5, word
    li    a6, 0x00030000            # unmapped
    lw    t2, 0(a5)
    lw    t3, 0(s0)                 # SIM_CTRL is write-only: reads 0
    lw    t4, 0(a6)
    lw    t5, 0(a5)
    la    t0, word
    lw    t1, 0(t0)                 # reference value, loaded alone
    li    t0, 0xDEADBEEF            # = word (.data): a DTCM that reads 0 everywhere would
    bne   t1, t0, fail              # otherwise pass every compare below
    bne   t2, t1, fail
    bnez  t3, fail
    bnez  t4, fail
    bne   t5, t1, fail

    STEP  2
    li    t0, -1
    sw    t0, 0(a6)
    lw    t4, 0(a6)
    bnez  t4, fail
    lw    t5, 0(a5)
    bne   t5, t1, fail

    STEP  3
    la    a5, scratch
    li    t0, 0x11
    sb    t0, 0(a5)
    li    t0, 0x22
    sb    t0, 1(a5)
    li    t0, 0x33
    sb    t0, 2(a5)
    li    t0, 0x44
    sb    t0, 3(a5)
    lw    t0, 0(a5)
    li    t1, 0x44332211
    bne   t0, t1, fail
    j     pass

    .include "common_end.inc"

    .data
word:
    .word 0xDEADBEEF
scratch:
    .word 0
msg_ok:
    .asciz "dmem_decode ok\n"
msg_bad:
    .asciz "FAIL step "
    .balign 4
