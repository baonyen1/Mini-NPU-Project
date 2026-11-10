# npu_top directed program (plan Phase 2 Task 14, t_status_csr): npu_busy_cyc (CSR 0x7C1, spec 6.4)
# over a K = 1024 (= KMAX, 256 quads) COMPUTE; data 4 KB weights + 4 KB inputs from gen_data.py.
#   1  LDW/LDI K = 1024, drain; the drain's READ_RESULT idx 0 returns 0 (no COMPUTE yet; only
#      idx 0 is checked here, step 4 checks all 16 after the COMPUTE)
#   2  idle: two reads of npu_busy_cyc with no engine activity between them are equal
#   3  delta = busy(after COMPUTE) - busy(before) satisfies 256 <= delta <= 256 + 3 + 16
#      (spec 7.2: a command finishes within K/4 + 3 cycles of being popped; the +16 is slack for
#      the push/drain skew, an inference of this test, not a spec number); the delta is printed
#   4  the 16 results match the table e1024
#   5  csrw npu_busy_cyc, 0 then csrr reads 0 (a CSR write sets the value, D17; the engine is idle)
    .option norelax
    .include "common.inc"

    .text
    .globl _start
_start:
    li    s0, SIM_CTRL
    li    s1, SIM_PUTC
    li    s3, 0

    STEP  1
    la    a0, w1024
    la    a1, i1024
    li    a2, 1024
    NPU_LDW a0, a2
    NPU_LDI a1, a2
    DRAIN                           # t6 = acc[0]: no COMPUTE yet, so it must still be 0
    bnez  t6, fail
    csrr  s5, NPU_BUSY              # after the loads are done

    STEP  2
    csrr  t0, NPU_BUSY
    nop
    nop
    nop
    csrr  t1, NPU_BUSY
    bne   t0, t1, fail
    bne   t0, s5, fail

    STEP  3
    NPU_MAC a2, 1
    DRAIN
    csrr  s6, NPU_BUSY
    sub   s7, s6, s5                # delta
    li    t0, 256
    bltu  s7, t0, fail
    li    t0, 256 + 3 + 16
    bgtu  s7, t0, fail
    la    a0, msg_delta
    call  puts
    srli  t2, s7, 8                 # delta < 0x1000: three hex digits
    call  puthex1
    srli  t2, s7, 4
    call  puthex1
    mv    t2, s7
    call  puthex1
    li    t0, '\n'
    sw    t0, 0(s1)

    STEP  4
    la    a4, e1024
    call  chk16

    STEP  5
    csrw  NPU_BUSY, x0
    csrr  t0, NPU_BUSY
    bnez  t0, fail
    j     pass

    .include "common_end.inc"           # also provides puthex1

    .data
    .include "data_k1024.inc"
msg_ok:
    .asciz "busy_cyc ok\n"
msg_bad:
    .asciz "FAIL step "
msg_delta:
    .asciz "busy delta 0x"
    .balign 4
