# npu_top directed program (plan Phase 2 Task 14, t_errors): the four error bits of npu_status
# (spec 6.3 error table, 6.4) through the real core, FIFO and engine.
#   1  npu_status after reset = 0x002
#   2  valid LDW/LDI/COMPUTE of known data; acc[i][j] = 4*(i+1)*(2j+1) (table e_base)
#   3  err_align : LDW at w_junk + 4           -> npu_status 0x802 (only that bit); w_junk holds
#                  data unlike w_quad, so an LDW that was executed instead of dropped breaks step 14
#   4  err_addr  : LDW at 0x0001_FFF0, K = 8   -> 0xA02 (a + 4K runs past the DTCM end)
#   5  err_illegal : funct3 100                -> 0xE02
#   6  err_k     : LDI with K = 6              -> 0xF02
#   7  dropped commands left acc untouched (e_base)
#   8  csrw npu_status, 0xF00 (W1C) clears all four -> 0x002
#   9  W1C is per bit: a write of a clear bit leaves a set bit alone
#  10  err_addr below DTCM_BASE (a = 0x0000_FFF0)
#  11  K = 0 (LDW, LDI, COMPUTE clr = 1) is a no-op without an error and without clearing acc
#  12  K > KMAX (K = 2048, then 1028) COMPUTE clr = 1 is dropped: err_k, acc not cleared
#  13  funct3 101/110/111 with junk operands and clr = 1: err_illegal only, acc not cleared (D16)
#  14  after all the dropped LOADs a COMPUTE clr = 0 doubles acc (buffers were not overwritten;
#      catches the step 3 LDW from w_junk, whose aligned-down quad and the next one differ from w_quad)
# Every drain is READ_RESULT, the only barrier (spec 6.3 rule 4). A failing check prints
# "FAIL step <n as two hex digits> <idx letter>" and writes SIM_CTRL = 0x2.
    .option norelax
    .include "common.inc"

    .text
    .globl _start
_start:
    li    s0, SIM_CTRL
    li    s1, SIM_PUTC
    li    s3, 0

    STEP  1
    EXPECT_CSR NPU_STATUS, 0x002

    STEP  2
    la    a0, w_quad
    la    a1, i_quad
    li    a2, 4
    NPU_LDW a0, a2
    NPU_LDI a1, a2
    NPU_MAC a2, 1
    la    a4, e_base
    call  chk16
    EXPECT_CSR NPU_STATUS, 0x002

    STEP  3
    la    a0, w_junk
    addi  a0, a0, 4                 # misaligned by 4: must be dropped (err_align)
    li    a2, 4
    NPU_LDW a0, a2
    DRAIN
    EXPECT_CSR NPU_STATUS, 0x802

    STEP  4
    li    a0, 0x0001FFF0
    li    a2, 8
    NPU_LDW a0, a2
    DRAIN
    EXPECT_CSR NPU_STATUS, 0xA02

    STEP  5
    .insn r 0x0B, 4, 0, x0, x0, x0  # funct3 = 100: reserved
    DRAIN
    EXPECT_CSR NPU_STATUS, 0xE02

    STEP  6
    la    a0, i_quad
    li    a2, 6
    NPU_LDI a0, a2
    DRAIN
    EXPECT_CSR NPU_STATUS, 0xF02

    STEP  7
    la    a4, e_base
    call  chk16

    STEP  8
    li    t1, 0xF00
    csrw  NPU_STATUS, t1
    EXPECT_CSR NPU_STATUS, 0x002

    STEP  9
    li    a0, 0x00010008
    li    a2, 4
    NPU_LDI a0, a2                  # err_align through LOAD_INPUT
    DRAIN
    EXPECT_CSR NPU_STATUS, 0x802
    li    t1, 0x700                 # clear bits that are not set: nothing changes
    csrw  NPU_STATUS, t1
    EXPECT_CSR NPU_STATUS, 0x802
    li    t1, 0x800
    csrw  NPU_STATUS, t1
    EXPECT_CSR NPU_STATUS, 0x002

    STEP  10
    li    a0, 0x0000FFF0
    li    a2, 4
    NPU_LDW a0, a2                  # below DTCM_BASE
    DRAIN
    EXPECT_CSR NPU_STATUS, 0x202
    li    t1, 0x200
    csrw  NPU_STATUS, t1
    EXPECT_CSR NPU_STATUS, 0x002

    STEP  11
    la    a0, i_quad
    li    a2, 0
    NPU_LDW a0, a2
    NPU_LDI a0, a2
    NPU_MAC a2, 1                   # K = 0: no operation, clr is not applied
    DRAIN
    EXPECT_CSR NPU_STATUS, 0x002
    la    a4, e_base
    call  chk16

    STEP  12
    li    a2, 2048
    NPU_MAC a2, 1
    DRAIN
    EXPECT_CSR NPU_STATUS, 0x102
    la    a4, e_base
    call  chk16
    li    t1, 0x100
    csrw  NPU_STATUS, t1
    li    a2, 1028
    NPU_MAC a2, 1
    DRAIN
    EXPECT_CSR NPU_STATUS, 0x102
    la    a4, e_base
    call  chk16
    li    t1, 0x100
    csrw  NPU_STATUS, t1
    EXPECT_CSR NPU_STATUS, 0x002

    STEP  13
    li    a0, 0x00010004
    li    a2, 6
    .insn r 0x0B, 5, 1, x0, a0, a2
    DRAIN
    EXPECT_CSR NPU_STATUS, 0x402
    la    a4, e_base
    call  chk16
    .insn r 0x0B, 6, 1, x0, a0, a2
    .insn r 0x0B, 7, 1, x0, a0, a2
    DRAIN
    EXPECT_CSR NPU_STATUS, 0x402
    la    a4, e_base
    call  chk16
    li    t1, 0x400
    csrw  NPU_STATUS, t1
    EXPECT_CSR NPU_STATUS, 0x002

    STEP  14
    li    a2, 4
    NPU_MAC a2, 0                   # acc += same products: 2 * e_base
    la    a4, e_dbl
    call  chk16
    EXPECT_CSR NPU_STATUS, 0x002
    j     pass

    .include "common_end.inc"

    .data
    .balign 16
w_quad:                             # row i = (i+1) in every lane
    .word 0x01010101, 0x02020202, 0x03030303, 0x04040404
i_quad:                             # image j = (2j+1) in every lane
    .word 0x01010101, 0x03030303, 0x05050505, 0x07070707
    .balign 16
w_junk:                             # never a valid LDW source: target of the step 3 misaligned LDW.
    .word 0x7F7F7F7F, 0x7F7F7F7F, 0x7F7F7F7F, 0x7F7F7F7F   # two quads, both unlike w_quad, so a
    .word 0x7F7F7F7F, 0x7F7F7F7F, 0x7F7F7F7F, 0x7F7F7F7F   # load from w_junk or w_junk + 4 shows in step 14
# acc[i][j] = 4 lanes * (i+1) * (2j+1), idx = 4*i + j (computed by hand)
e_base:
    .word  4, 12, 20,  28
    .word  8, 24, 40,  56
    .word 12, 36, 60,  84
    .word 16, 48, 80, 112
e_dbl:
    .word  8,  24,  40,  56
    .word 16,  48,  80, 112
    .word 24,  72, 120, 168
    .word 32,  96, 160, 224
msg_ok:
    .asciz "errors ok\n"
msg_bad:
    .asciz "FAIL step "
    .balign 4                       # whole words only: the hex file holds 32-bit words
