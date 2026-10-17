# S5: Zbb instruction and a custom-0 word via .insn
    .text
    max   a0, a1, a2
    .insn r 0x0B, 0, 0, x0, a0, a1
