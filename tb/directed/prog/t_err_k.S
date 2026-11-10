# npu_top directed program (plan Phase 2 Task 14): err_k and the npu_status W1C path.
#   1. npu_status (CSR 0x7C0) after reset = 0x002: fifo_empty only, no error bit (spec 6.4, D18)
#   2. LOAD_WEIGHT with K = 6 (not a multiple of 4) is dropped and sets err_k (spec 6.3)
#   3. READ_RESULT idx 0 drains the engine (the only barrier, spec 6.3 rule 4; npu_status is not
#      one, docs/core_isa.md 7 item 4) and returns 0: the accumulators are reset (D18) and the
#      dropped command did not touch them
#   4. npu_status = 0x102: err_k set, sticky, engine idle, FIFO empty
#   5. csrw npu_status, 0x100 (W1C, csrrw as spec 6.4 asks) clears err_k: npu_status = 0x002
# Each check that fails prints "FAIL step <n as two hex digits>" on SIM_PUTC and writes SIM_CTRL = 0x2.
    .option norelax
    .equ SIM_CTRL,   0x00020000
    .equ SIM_PUTC,   0x00020004
    .equ NPU_STATUS, 0x7C0
    .equ DTCM_BASE,  0x00010000

    .text
    .globl _start
_start:
    li    s0, SIM_CTRL
    li    s1, SIM_PUTC

    li    s2, 1                     # step 1
    csrr  t0, NPU_STATUS
    li    t1, 0x002
    bne   t0, t1, fail

    li    a0, DTCM_BASE             # quad-aligned and in range: K is the only fault
    li    a2, 6
    .insn r 0x0B, 0, 0, x0, a0, a2  # step 2: LOAD_WEIGHT a0, K = 6 -> err_k

    li    s2, 3
    .insn r 0x0B, 3, 0, t0, x0, x0  # step 3: READ_RESULT t0, idx 0
    bnez  t0, fail

    li    s2, 4
    csrr  t0, NPU_STATUS
    li    t1, 0x102
    bne   t0, t1, fail

    li    s2, 5
    li    t1, 0x100
    csrw  NPU_STATUS, t1            # W1C err_k
    csrr  t0, NPU_STATUS
    li    t1, 0x002
    bne   t0, t1, fail

    la    a0, msg_ok
    call  puts
    li    t0, 0x1                   # PASS
    sw    t0, 0(s0)
end:
    j     end

fail:
    la    a0, msg_bad
    call  puts
    srli  t2, s2, 4                 # step, two hex digits (same format as common_end.inc)
    call  puthex1
    mv    t2, s2
    call  puthex1
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

# puthex1(t2): prints the low nibble of t2 as a hex digit (0-9, a-f). Uses t0, t2.
puthex1:
    andi  t2, t2, 15
    li    t0, 10
    blt   t2, t0, 1f
    addi  t2, t2, 'a' - 10 - '0'
1:  addi  t2, t2, '0'
    sw    t2, 0(s1)
    ret

    .data
msg_ok:
    .asciz "err_k ok\n"
msg_bad:
    .asciz "FAIL step "
    .balign 4                       # whole words only: the hex file holds 32-bit words
