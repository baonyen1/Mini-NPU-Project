# Shared definitions of the npu_top directed programs (plan Phase 2 Task 14, DV extension):
# constants, custom-0 macros (spec 6.1) and, in common_end.inc, the fail/puts tail.
# Register convention: s0 = SIM_CTRL, s1 = SIM_PUTC, s2 = step number, s3 = result index of the
# last check. A failing check jumps to `fail`, which prints "FAIL step <s2> <s3>" on SIM_PUTC (the
# step as two hex digits, e.g. "0e" for step 14; the result index as the letter 'a' + idx, 'a'..'p')
# and writes SIM_CTRL = 0x2. Each program defines msg_bad.
    .equ SIM_CTRL,   0x00020000
    .equ SIM_PUTC,   0x00020004
    .equ NPU_STATUS, 0x7C0
    .equ NPU_BUSY,   0x7C1
    .equ DTCM_BASE,  0x00010000

    .macro NPU_LDW rs1, rs2         # LOAD_WEIGHT  rs1 = byte address, rs2 = K
    .insn r 0x0B, 0, 0, x0, \rs1, \rs2
    .endm
    .macro NPU_LDI rs1, rs2         # LOAD_INPUT
    .insn r 0x0B, 1, 0, x0, \rs1, \rs2
    .endm
    .macro NPU_MAC rs1, clr         # COMPUTE rs1 = K, funct7[0] = clr
    .insn r 0x0B, 2, \clr, x0, \rs1, x0
    .endm
    .macro NPU_RDR rd, rs1          # READ_RESULT rd <- acc[rs1[3:0]]; the only barrier (spec 6.3 rule 4)
    .insn r 0x0B, 3, 0, \rd, \rs1, x0
    .endm
    .macro DRAIN                    # READ_RESULT idx 0 into t6, result unused
    .insn r 0x0B, 3, 0, t6, x0, x0
    .endm
    .macro STEP n
    li    s2, \n
    .endm
    .macro EXPECT_CSR csr, val      # fail unless CSR == val
    csrr  t0, \csr
    li    t1, \val
    bne   t0, t1, fail
    .endm
