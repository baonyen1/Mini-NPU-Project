# Tail shared by the npu_top directed programs: pass, fail, puts, puthex1, chk16. Included in .text after the
# main code. The program provides msg_ok and msg_bad (.data).
pass:
    la    a0, msg_ok
    call  puts
    li    t0, 0x1                   # PASS
    sw    t0, 0(s0)
end:
    j     end

fail:
    la    a0, msg_bad
    call  puts
    srli  t2, s2, 4                 # step, two hex digits (steps go past 9)
    call  puthex1
    mv    t2, s2
    call  puthex1
    li    t0, ' '
    sw    t0, 0(s1)
    addi  t0, s3, 'a'               # result index of the last chk16, 'a' when none
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

# puthex1(t2): prints the low nibble of t2 as a hex digit (0-9, a-f). Uses t0, t2.
puthex1:
    andi  t2, t2, 15
    li    t0, 10
    blt   t2, t0, 1f
    addi  t2, t2, 'a' - 10 - '0'
1:  addi  t2, t2, '0'
    sw    t2, 0(s1)
    ret

# chk16(a4 = table of 16 words): READ_RESULT idx 0..15 against the table; fails on the first
# mismatch with s3 = idx. Uses t0, t1, s3, s4, a4.
chk16:
    li    s3, 0
    li    s4, 16
1:  NPU_RDR t0, s3
    lw    t1, 0(a4)
    bne   t0, t1, fail
    addi  a4, a4, 4
    addi  s3, s3, 1
    blt   s3, s4, 1b
    li    s3, 0
    ret
