# npu_top directed program (plan Phase 2 Task 14): the Task 10 hand_4x4_k4 case end to end.
# LOAD_WEIGHT and LOAD_INPUT (K = 4) from DTCM, COMPUTE K = 4 with clr = 1, then READ_RESULT
# for idx 0..15, each compared with the expected table. Prints "hand ok" on SIM_PUTC, then writes
# SIM_CTRL = 0x1 (PASS); on the first mismatch prints "MISMATCH idx <letter>" ('a' + idx) and
# writes SIM_CTRL = 0x2 (FAIL).
# Data (model/c/tests/test_npu_ref.c, hand_setup) is in .data, which build.sh links at
# DTCM_BASE = 0x0001_0000 and npu_top_tb loads with +DTCM: weights at 0x0001_0000, inputs at
# 0x0001_0010, both quad-aligned (spec 6.3 rule 6).
# Custom-0 encodings (spec 6.1): .insn r 0x0B, funct3, funct7, rd, rs1, rs2.
    .option norelax                 # no gp-relative relaxation: nothing sets gp in this program
    .equ SIM_CTRL, 0x00020000
    .equ SIM_PUTC, 0x00020004

    .text
    .globl _start
_start:
    li    s0, SIM_CTRL
    li    s1, SIM_PUTC
    la    a0, w_quad                # 0x0001_0000
    la    a1, i_quad                # 0x0001_0010
    li    a2, 4                     # K = 4 int8 elements = one quad
    .insn r 0x0B, 0, 0, x0, a0, a2  # LOAD_WEIGHT a0, K
    .insn r 0x0B, 1, 0, x0, a1, a2  # LOAD_INPUT  a1, K
    .insn r 0x0B, 2, 1, x0, a2, x0  # COMPUTE K, clr = 1

    la    s2, expected
    li    s3, 0                     # idx = 4*i + j
    li    s4, 16
check:
    .insn r 0x0B, 3, 0, t0, s3, x0  # READ_RESULT t0, idx (the first one drains the engine)
    lw    t1, 0(s2)
    bne   t0, t1, fail
    addi  s2, s2, 4
    addi  s3, s3, 1
    blt   s3, s4, check

    la    a0, msg_ok
    call  puts
    li    t0, 0x1                   # PASS
    sw    t0, 0(s0)
end:
    j     end

fail:
    la    a0, msg_bad
    call  puts
    addi  t0, s3, 'a'               # which idx failed
    sw    t0, 0(s1)
    li    t0, '\n'
    sw    t0, 0(s1)
    li    t0, 0x2                   # FAIL
    sw    t0, 0(s0)
fail_end:
    j     fail_end

# puts(a0): writes the bytes of a NUL-terminated string to SIM_PUTC. Uses t0 and a0 only.
puts:
    lbu   t0, 0(a0)
    beqz  t0, 1f
    sw    t0, 0(s1)
    addi  a0, a0, 1
    j     puts
1:  ret

    .data
    .balign 16
# Weights: row i = W[i][0..3]; word i of the quad (spec 6.2), lane 0 = LSB.
w_quad:
    .word 0x04030201                # [   1,    2,    3,    4]
    .word 0xFCFDFEFF                # [  -1,   -2,   -3,   -4]
    .word 0x0000007F                # [ 127,    0,    0,    0]
    .word 0x80000000                # [   0,    0,    0, -128]
# Inputs: image j = x_j[0..3]; word j of the quad.
i_quad:
    .word 0x01010101                # [   1,    1,    1,    1]
    .word 0x00000001                # [   1,    0,    0,    0]
    .word 0x80808080                # [-128, -128, -128, -128]
    .word 0xFE02FE02                # [   2,   -2,    2,   -2]
# expected[4*i + j] = dot(row i, image j): plan Task 14 t_ldw_ldi_mac, HAND[] in test_npu_ref.c
expected:
    .word     10,    1, -1280,   -4
    .word    -10,   -1,  1280,    4
    .word    127,  127, -16256, 254
    .word   -128,    0, 16384,  256
msg_ok:
    .asciz "hand ok\n"
msg_bad:
    .asciz "MISMATCH idx "
    .balign 4                       # whole words only: the hex file holds 32-bit words
