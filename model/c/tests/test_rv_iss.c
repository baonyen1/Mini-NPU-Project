/* Unit tests for rv_iss (Phase 1 plan, Task 12).
 * Run: make -C model/c test      (self-contained vectors, expected values worked out by hand)
 *      make -C model/c xcheck    (after python tools/rv32i_check/run_all.py: runs every program of the
 *                                 Python suites and compares registers and the whole RVVI trace)
 * Spec refs: 5 (extensions), 6 (custom-0), 10.2 (golden models), docs/core_isa.md section 9. */
#define _POSIX_C_SOURCE 200809L
#include <dirent.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "npu_ref.h"
#include "rv_iss.h"

#define CHECK_EQ(got, want) do {                                              \
    uint32_t g_ = (uint32_t)(got), w_ = (uint32_t)(want);                     \
    if (g_ != w_) {                                                           \
        fprintf(stderr, "FAIL %s:%d: %s = 0x%08x, expected %s = 0x%08x\n",    \
                __FILE__, __LINE__, #got, g_, #want, w_);                     \
        exit(1);                                                              \
    }                                                                         \
} while (0)

#define RUN(t) do { printf("  %-30s", #t); t(); printf("ok\n"); } while (0)

/* ---- instruction encoders -------------------------------------------------------------- */
static uint32_t R_(uint32_t f7, uint32_t rs2, uint32_t rs1, uint32_t f3, uint32_t rd, uint32_t op)
{ return (f7 << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op; }

static uint32_t I_(int32_t imm, uint32_t rs1, uint32_t f3, uint32_t rd, uint32_t op)
{ return (((uint32_t)imm & 0xFFFu) << 20) | (rs1 << 15) | (f3 << 12) | (rd << 7) | op; }

static uint32_t S_(int32_t imm, uint32_t rs2, uint32_t rs1, uint32_t f3)
{
    uint32_t u = (uint32_t)imm;
    return (((u >> 5) & 0x7Fu) << 25) | (rs2 << 20) | (rs1 << 15) | (f3 << 12) | ((u & 0x1Fu) << 7) | 0x23u;
}

static uint32_t B_(int32_t imm, uint32_t rs2, uint32_t rs1, uint32_t f3)
{
    uint32_t u = (uint32_t)imm;
    return (((u >> 12) & 1u) << 31) | (((u >> 5) & 0x3Fu) << 25) | (rs2 << 20) | (rs1 << 15) |
           (f3 << 12) | (((u >> 1) & 0xFu) << 8) | (((u >> 11) & 1u) << 7) | 0x63u;
}

static uint32_t U_(uint32_t imm20, uint32_t rd, uint32_t op) { return (imm20 << 12) | (rd << 7) | op; }

static uint32_t J_(int32_t imm, uint32_t rd)
{
    uint32_t u = (uint32_t)imm;
    return (((u >> 20) & 1u) << 31) | (((u >> 1) & 0x3FFu) << 21) | (((u >> 11) & 1u) << 20) |
           (((u >> 12) & 0xFFu) << 12) | (rd << 7) | 0x6Fu;
}

#define ADDI(rd, rs1, imm)  I_(imm, rs1, 0, rd, 0x13)
#define ADD(rd, rs1, rs2)   R_(0x00, rs2, rs1, 0, rd, 0x33)
#define SUB(rd, rs1, rs2)   R_(0x20, rs2, rs1, 0, rd, 0x33)
#define LUI(rd, imm20)      U_(imm20, rd, 0x37)
#define LW(rd, rs1, imm)    I_(imm, rs1, 2, rd, 0x03)
#define LH(rd, rs1, imm)    I_(imm, rs1, 1, rd, 0x03)
#define LB(rd, rs1, imm)    I_(imm, rs1, 0, rd, 0x03)
#define LHU(rd, rs1, imm)   I_(imm, rs1, 5, rd, 0x03)
#define LBU(rd, rs1, imm)   I_(imm, rs1, 4, rd, 0x03)
#define SW(rs2, rs1, imm)   S_(imm, rs2, rs1, 2)
#define SH(rs2, rs1, imm)   S_(imm, rs2, rs1, 1)
#define SB(rs2, rs1, imm)   S_(imm, rs2, rs1, 0)
#define MULOP(f3, rd, a, b) R_(0x01, b, a, f3, rd, 0x33)       /* mul=0 mulh=1 mulhsu=2 mulhu=3 div=4 divu=5 rem=6 remu=7 */
#define ZBBR(f7, f3, rd, a, b) R_(f7, b, a, f3, rd, 0x33)
#define CSR(f3, rd, csr, rs1) I_((int32_t)(csr), rs1, f3, rd, 0x73)   /* 1 rw 2 rs 3 rc 5 rwi 6 rsi 7 rci */
#define CUSTOM(f7, f3, rd, rs1, rs2) R_(f7, rs2, rs1, f3, rd, 0x0B)

/* ---- program builder ------------------------------------------------------------------- */
static uint32_t prog[ISS_ITCM_WORDS];
static uint32_t np;

static void begin(void) { np = 0; }
static void emit(uint32_t w) { prog[np++] = w; }
static void emit_li(uint32_t rd, uint32_t v)
{
    uint32_t hi = (v + 0x800u) & 0xFFFFF000u;
    int32_t  lo = (int32_t)(v - hi);                 /* -2048 .. 2047 */
    if (hi != 0u) {
        emit(LUI(rd, hi >> 12));
        if (lo != 0) emit(ADDI(rd, rd, lo));
    } else {
        emit(ADDI(rd, 0, lo));
    }
}

static void run(int mode, uint32_t steps, const uint32_t *dtcm, uint32_t ndtcm)
{
    iss_init(prog, np, dtcm, ndtcm, mode);
    for (uint32_t i = 0; i < steps; i++) (void)iss_step(NULL);
}

/* ---- encoders against the words the assembler produced (docs/core_isa.md section 6) ---------- */
static void t_encoders_match_assembler(void)
{
    CHECK_EQ(MULOP(0, 3, 1, 2), 0x022081b3u);   CHECK_EQ(MULOP(1, 3, 1, 2), 0x022091b3u);
    CHECK_EQ(MULOP(2, 3, 1, 2), 0x0220a1b3u);   CHECK_EQ(MULOP(3, 3, 1, 2), 0x0220b1b3u);
    CHECK_EQ(MULOP(4, 3, 1, 2), 0x0220c1b3u);   CHECK_EQ(MULOP(5, 3, 1, 2), 0x0220d1b3u);
    CHECK_EQ(MULOP(6, 3, 1, 2), 0x0220e1b3u);   CHECK_EQ(MULOP(7, 3, 1, 2), 0x0220f1b3u);
    CHECK_EQ(CSR(1, 3, 0x7c0, 1), 0x7c0091f3u); CHECK_EQ(CSR(2, 3, 0x7c0, 1), 0x7c00a1f3u);
    CHECK_EQ(CSR(3, 3, 0x7c0, 1), 0x7c00b1f3u); CHECK_EQ(CSR(5, 3, 0x7c0, 5), 0x7c02d1f3u);
    CHECK_EQ(CSR(6, 3, 0x7c0, 5), 0x7c02e1f3u); CHECK_EQ(CSR(7, 3, 0x7c0, 5), 0x7c02f1f3u);
    CHECK_EQ(I_(0, 0, 1, 0, 0x0F), 0x0000100fu);                       /* fence.i */
    CHECK_EQ(ZBBR(0x20, 7, 3, 1, 2), 0x4020f1b3u);                      /* andn */
    CHECK_EQ(ZBBR(0x20, 6, 3, 1, 2), 0x4020e1b3u);                      /* orn */
    CHECK_EQ(ZBBR(0x20, 4, 3, 1, 2), 0x4020c1b3u);                      /* xnor */
    CHECK_EQ(I_(0x600, 1, 1, 3, 0x13), 0x60009193u);                    /* clz */
    CHECK_EQ(I_(0x601, 1, 1, 3, 0x13), 0x60109193u);                    /* ctz */
    CHECK_EQ(I_(0x602, 1, 1, 3, 0x13), 0x60209193u);                    /* cpop */
    CHECK_EQ(ZBBR(0x05, 6, 3, 1, 2), 0x0a20e1b3u);                      /* max */
    CHECK_EQ(ZBBR(0x05, 7, 3, 1, 2), 0x0a20f1b3u);                      /* maxu */
    CHECK_EQ(ZBBR(0x05, 4, 3, 1, 2), 0x0a20c1b3u);                      /* min */
    CHECK_EQ(ZBBR(0x05, 5, 3, 1, 2), 0x0a20d1b3u);                      /* minu */
    CHECK_EQ(I_(0x604, 1, 1, 3, 0x13), 0x60409193u);                    /* sext.b */
    CHECK_EQ(I_(0x605, 1, 1, 3, 0x13), 0x60509193u);                    /* sext.h */
    CHECK_EQ(ZBBR(0x04, 4, 3, 1, 0), 0x0800c1b3u);                      /* zext.h */
    CHECK_EQ(ZBBR(0x30, 1, 3, 1, 2), 0x602091b3u);                      /* rol */
    CHECK_EQ(ZBBR(0x30, 5, 3, 1, 2), 0x6020d1b3u);                      /* ror */
    CHECK_EQ(I_(0x605, 1, 5, 3, 0x13), 0x6050d193u);                    /* rori 5 */
    CHECK_EQ(I_(0x287, 1, 5, 3, 0x13), 0x2870d193u);                    /* orc.b */
    CHECK_EQ(I_(0x698, 1, 5, 3, 0x13), 0x6980d193u);                    /* rev8 */
    CHECK_EQ(CUSTOM(0, 0, 0, 1, 2), 0x0020800bu);                       /* LOAD_WEIGHT */
    CHECK_EQ(CUSTOM(0, 1, 0, 1, 2), 0x0020900bu);                       /* LOAD_INPUT */
    CHECK_EQ(CUSTOM(0, 2, 0, 1, 0), 0x0000a00bu);                       /* COMPUTE clr=0 */
    CHECK_EQ(CUSTOM(1, 2, 0, 1, 0), 0x0200a00bu);                       /* COMPUTE clr=1 */
    CHECK_EQ(CUSTOM(0, 3, 3, 1, 0), 0x0000b18bu);                       /* READ_RESULT */
    CHECK_EQ(ADDI(1, 0, 5), 0x00500093u);
}

/* ---- RV32I ----------------------------------------------------------------------------- */
static void t_base_alu_and_x0(void)
{
    begin();
    emit(ADDI(1, 0, 5));
    emit(ADDI(0, 1, 7));                 /* writing x0 has no effect */
    emit(ADD(2, 1, 1));
    emit(SUB(3, 0, 1));                  /* -5 */
    emit(R_(0x00, 1, 3, 2, 4, 0x33));    /* slt  x4 = (-5 < 5)  = 1 */
    emit(R_(0x00, 1, 3, 3, 5, 0x33));    /* sltu x5 = (0xFFFFFFFB < 5) = 0 */
    emit(R_(0x20, 1, 3, 5, 6, 0x33));    /* sra  x6 = -5 >> 5 = -1 */
    emit(R_(0x00, 1, 3, 5, 7, 0x33));    /* srl  x7 = 0xFFFFFFFB >> 5 = 0x07FFFFFF */
    emit(I_(0x405, 3, 5, 8, 0x13));      /* srai x8 = -5 >> 5 = -1 (instruction bit 30 selects arithmetic) */
    emit(I_(0x005, 3, 5, 9, 0x13));      /* srli x9 = 0x07FFFFFF */
    emit(I_(0x004, 1, 1, 11, 0x13));     /* slli x11 = 5 << 4 = 80 */
    run(ISS_STUB, 11, NULL, 0);
    CHECK_EQ(iss_reg(0), 0u);  CHECK_EQ(iss_reg(1), 5u);   CHECK_EQ(iss_reg(2), 10u);
    CHECK_EQ(iss_reg(3), 0xFFFFFFFBu);  CHECK_EQ(iss_reg(4), 1u);  CHECK_EQ(iss_reg(5), 0u);
    CHECK_EQ(iss_reg(6), 0xFFFFFFFFu);  CHECK_EQ(iss_reg(7), 0x07FFFFFFu);
    CHECK_EQ(iss_reg(8), 0xFFFFFFFFu);  CHECK_EQ(iss_reg(9), 0x07FFFFFFu);  CHECK_EQ(iss_reg(11), 80u);
}

static void t_branches_and_jumps(void)
{
    begin();
    emit(ADDI(1, 0, 10));                /* 0x00 i = 10 */
    emit(ADDI(2, 0, 0));                 /* 0x04 sum = 0 */
    emit(ADD(2, 2, 1));                  /* 0x08 loop: sum += i */
    emit(ADDI(1, 1, -1));                /* 0x0C */
    emit(B_(-8, 0, 1, 1));               /* 0x10 bne x1, x0, loop */
    emit(J_(8, 5));                      /* 0x14 jal x5, +8  (x5 = 0x18) */
    emit(ADDI(6, 0, 99));                /* 0x18 skipped */
    emit(ADDI(7, 0, 1));                 /* 0x1C */
    emit(I_(0x2D, 0, 0, 8, 0x67));       /* 0x20 jalr x8, 0x2D(x0): target 0x2D & ~1 = 0x2C, x8 = 0x24 */
    emit(ADDI(9, 0, 99));                /* 0x24 skipped */
    emit(ADDI(9, 0, 99));                /* 0x28 skipped */
    emit(ADDI(10, 0, 3));                /* 0x2C */
    run(ISS_STUB, 2 + 30 + 1 + 1 + 1 + 1, NULL, 0);
    CHECK_EQ(iss_reg(2), 55u);  CHECK_EQ(iss_reg(5), 0x18u);  CHECK_EQ(iss_reg(6), 0u);
    CHECK_EQ(iss_reg(7), 1u);   CHECK_EQ(iss_reg(8), 0x24u);  CHECK_EQ(iss_reg(9), 0u);
    CHECK_EQ(iss_reg(10), 3u);
}

/* a JALR encoding with funct3 != 0 is not an instruction: no jump, no link */
static void t_jalr_funct3_is_nop(void)
{
    begin();
    emit(ADDI(1, 0, 0x100));
    emit(I_(0, 1, 1, 5, 0x67));
    emit(ADDI(6, 0, 7));
    run(ISS_STUB, 3, NULL, 0);
    CHECK_EQ(iss_reg(5), 0u);  CHECK_EQ(iss_reg(6), 7u);  CHECK_EQ(iss_pc(), 12u);
}

static void t_loads_and_stores(void)
{
    begin();
    emit(LUI(5, 0x10));                  /* x5 = DTCM base */
    emit_li(6, 0x8091A2B3u);
    emit(SW(6, 5, 0));
    emit(LW(10, 5, 0));
    emit(LB(11, 5, 0));  emit(LBU(12, 5, 0));  emit(LB(13, 5, 3));  emit(LBU(14, 5, 3));
    emit(LH(15, 5, 0));  emit(LHU(16, 5, 0));  emit(LH(17, 5, 2));  emit(LHU(18, 5, 2));
    emit(SB(6, 5, 5));                   /* byte 0xB3 into lane 1 of word 1 */
    emit(SH(6, 5, 10));                  /* half 0xA2B3 into the upper half of word 2 */
    emit(SH(6, 5, 13));                  /* 0x1000D: bit 0 ignored, bit 1 = 0 -> lower half of word 3 */
    emit(SH(6, 5, 19));                  /* 0x10013: bit 0 ignored, bit 1 = 1 -> upper half of word 4 */
    emit(LW(19, 5, 4));  emit(LW(20, 5, 8));  emit(LW(21, 5, 12));  emit(LW(22, 5, 16));
    run(ISS_STUB, 21, NULL, 0);
    CHECK_EQ(iss_reg(10), 0x8091A2B3u);
    CHECK_EQ(iss_reg(11), 0xFFFFFFB3u);  CHECK_EQ(iss_reg(12), 0xB3u);
    CHECK_EQ(iss_reg(13), 0xFFFFFF80u);  CHECK_EQ(iss_reg(14), 0x80u);
    CHECK_EQ(iss_reg(15), 0xFFFFA2B3u);  CHECK_EQ(iss_reg(16), 0xA2B3u);
    CHECK_EQ(iss_reg(17), 0xFFFF8091u);  CHECK_EQ(iss_reg(18), 0x8091u);
    CHECK_EQ(iss_reg(19), 0x0000B300u);  CHECK_EQ(iss_reg(20), 0xA2B30000u);
    CHECK_EQ(iss_reg(21), 0x0000A2B3u);  CHECK_EQ(iss_reg(22), 0xA2B30000u);
}

/* ---- M extension ----------------------------------------------------------------------- */
static void t_m_mul_corners(void)
{
    begin();
    emit_li(1, 0x80000000u);  emit_li(2, 0x80000000u);
    for (uint32_t f3 = 0; f3 < 4; f3++) emit(MULOP(f3, 10 + f3, 1, 2));
    emit_li(3, 0xFFFFFFFFu);  emit_li(4, 0xFFFFFFFFu);
    for (uint32_t f3 = 0; f3 < 4; f3++) emit(MULOP(f3, 14 + f3, 3, 4));
    emit_li(5, 0x7FFFFFFFu);  emit_li(6, 2);
    for (uint32_t f3 = 0; f3 < 4; f3++) emit(MULOP(f3, 18 + f3, 5, 6));
    run(ISS_STUB, np, NULL, 0);
    CHECK_EQ(iss_reg(10), 0u);           CHECK_EQ(iss_reg(11), 0x40000000u);
    CHECK_EQ(iss_reg(12), 0xC0000000u);  CHECK_EQ(iss_reg(13), 0x40000000u);
    CHECK_EQ(iss_reg(14), 1u);           CHECK_EQ(iss_reg(15), 0u);
    CHECK_EQ(iss_reg(16), 0xFFFFFFFFu);  CHECK_EQ(iss_reg(17), 0xFFFFFFFEu);
    CHECK_EQ(iss_reg(18), 0xFFFFFFFEu);  CHECK_EQ(iss_reg(19), 0u);
    CHECK_EQ(iss_reg(20), 0u);           CHECK_EQ(iss_reg(21), 0u);
}

static void t_m_div_cases(void)
{
    begin();
    emit_li(1, 5);  emit_li(2, 0);
    emit(MULOP(4, 10, 1, 2)); emit(MULOP(5, 11, 1, 2)); emit(MULOP(6, 12, 1, 2)); emit(MULOP(7, 13, 1, 2));
    emit_li(3, 0xFFFFFFF9u);                                   /* -7 */
    emit(MULOP(4, 14, 3, 2)); emit(MULOP(6, 15, 3, 2));
    emit_li(4, 0x80000000u);  emit_li(5, 0xFFFFFFFFu);
    emit(MULOP(4, 16, 4, 5)); emit(MULOP(6, 17, 4, 5));         /* -2^31 / -1 */
    emit_li(6, 2);
    emit(MULOP(4, 18, 3, 6)); emit(MULOP(6, 19, 3, 6));         /* -7 / 2 */
    emit_li(7, 7);  emit_li(8, 0xFFFFFFFEu);
    emit(MULOP(4, 20, 7, 8)); emit(MULOP(6, 21, 7, 8));         /* 7 / -2 */
    emit(MULOP(5, 22, 3, 6)); emit(MULOP(7, 23, 3, 6));         /* unsigned */
    run(ISS_STUB, np, NULL, 0);
    CHECK_EQ(iss_reg(10), 0xFFFFFFFFu);  CHECK_EQ(iss_reg(11), 0xFFFFFFFFu);
    CHECK_EQ(iss_reg(12), 5u);           CHECK_EQ(iss_reg(13), 5u);
    CHECK_EQ(iss_reg(14), 0xFFFFFFFFu);  CHECK_EQ(iss_reg(15), 0xFFFFFFF9u);
    CHECK_EQ(iss_reg(16), 0x80000000u);  CHECK_EQ(iss_reg(17), 0u);
    CHECK_EQ(iss_reg(18), 0xFFFFFFFDu);  CHECK_EQ(iss_reg(19), 0xFFFFFFFFu);
    CHECK_EQ(iss_reg(20), 0xFFFFFFFDu);  CHECK_EQ(iss_reg(21), 1u);
    CHECK_EQ(iss_reg(22), 0x7FFFFFFCu);  CHECK_EQ(iss_reg(23), 1u);
}

/* ---- Zbb ------------------------------------------------------------------------------- */
static void t_zbb_unary(void)
{
    begin();
    emit_li(1, 0);           emit_li(2, 1);           emit_li(3, 0x80000000u);   emit_li(4, 0xFFFFFFFFu);
    emit_li(5, 0x80000F0Fu); emit_li(6, 0x00010200u); emit_li(7, 0x11223344u);   emit_li(8, 0x80);
    emit_li(9, 0x80018001u); emit_li(30, 0x7F);
    emit(I_(0x600, 1, 1, 11, 0x13));  emit(I_(0x601, 1, 1, 12, 0x13));          /* clz 0, ctz 0 */
    emit(I_(0x600, 2, 1, 13, 0x13));  emit(I_(0x601, 3, 1, 14, 0x13));          /* clz 1, ctz 2^31 */
    emit(I_(0x602, 4, 1, 15, 0x13));  emit(I_(0x602, 5, 1, 16, 0x13));          /* cpop */
    emit(I_(0x287, 6, 5, 17, 0x13));  emit(I_(0x698, 7, 5, 18, 0x13));          /* orc.b, rev8 */
    emit(I_(0x604, 8, 1, 19, 0x13));  emit(I_(0x604, 30, 1, 20, 0x13));         /* sext.b */
    emit(I_(0x605, 9, 1, 21, 0x13));  emit(ZBBR(0x04, 4, 22, 9, 0));            /* sext.h, zext.h */
    run(ISS_STUB, np, NULL, 0);
    CHECK_EQ(iss_reg(11), 32u);  CHECK_EQ(iss_reg(12), 32u);  CHECK_EQ(iss_reg(13), 31u);  CHECK_EQ(iss_reg(14), 31u);
    CHECK_EQ(iss_reg(15), 32u);  CHECK_EQ(iss_reg(16), 9u);
    CHECK_EQ(iss_reg(17), 0x00FFFF00u);  CHECK_EQ(iss_reg(18), 0x44332211u);
    CHECK_EQ(iss_reg(19), 0xFFFFFF80u);  CHECK_EQ(iss_reg(20), 0x7Fu);
    CHECK_EQ(iss_reg(21), 0xFFFF8001u);  CHECK_EQ(iss_reg(22), 0x00008001u);
}

static void t_zbb_binary(void)
{
    begin();
    emit_li(1, 0x80000001u);  emit_li(2, 1);  emit_li(3, 31);
    emit(ZBBR(0x30, 1, 10, 1, 2));  emit(ZBBR(0x30, 5, 11, 1, 2));              /* rol, ror by 1 */
    emit(ZBBR(0x30, 1, 12, 1, 0));  emit(ZBBR(0x30, 1, 13, 1, 3));              /* rol by 0, by 31 */
    emit(I_(0x61F, 2, 5, 14, 0x13));  emit(I_(0x605, 1, 5, 15, 0x13));          /* rori x2,31; rori x1,5 */
    emit_li(4, 0x80000000u);
    emit(ZBBR(0x05, 6, 16, 4, 2));  emit(ZBBR(0x05, 4, 17, 4, 2));              /* max, min */
    emit(ZBBR(0x05, 7, 18, 4, 2));  emit(ZBBR(0x05, 5, 19, 4, 2));              /* maxu, minu */
    emit_li(5, 0xF0F0F0F0u);  emit_li(6, 0xFF00FF00u);
    emit(ZBBR(0x20, 7, 20, 5, 6));  emit(ZBBR(0x20, 6, 21, 5, 6));  emit(ZBBR(0x20, 4, 22, 5, 6));
    run(ISS_STUB, np, NULL, 0);
    CHECK_EQ(iss_reg(10), 3u);          CHECK_EQ(iss_reg(11), 0xC0000000u);
    CHECK_EQ(iss_reg(12), 0x80000001u); CHECK_EQ(iss_reg(13), 0xC0000000u);
    CHECK_EQ(iss_reg(14), 2u);
    /* x1 = 0x80000001 rotated right by 5: 0x80000001 >> 5 = 0x04000000 and the low 5 bits (00001)
       come back at the top as 1 << 27 = 0x08000000, together 0x0C000000 */
    CHECK_EQ(iss_reg(15), 0x0C000000u);
    CHECK_EQ(iss_reg(16), 1u);          CHECK_EQ(iss_reg(17), 0x80000000u);
    CHECK_EQ(iss_reg(18), 0x80000000u); CHECK_EQ(iss_reg(19), 1u);
    CHECK_EQ(iss_reg(20), 0x00F000F0u); CHECK_EQ(iss_reg(21), 0xF0FFF0FFu); CHECK_EQ(iss_reg(22), 0xF00FF00Fu);
}

/* pack rd, rs1, rs2 with rs2 != x0 shares zext.h's encoding space but is not Zbb: a NOP */
static void t_zbb_pack_is_nop(void)
{
    begin();
    emit_li(1, 0x12345678u);  emit_li(2, 0xABCDu);  emit_li(5, 0x55);
    emit(ZBBR(0x04, 4, 5, 1, 2));
    run(ISS_STUB, np, NULL, 0);
    CHECK_EQ(iss_reg(5), 0x55u);
}

/* ---- Zicsr ----------------------------------------------------------------------------- */
static void t_csr_scratch_and_status(void)
{
    begin();
    emit_li(1, 0xF0F0);  emit_li(2, 0x00FF);
    emit(CSR(1, 10, 0x7c1, 1));  emit(CSR(2, 11, 0x7c1, 2));  emit(CSR(3, 12, 0x7c1, 2));
    emit(CSR(5, 13, 0x7c1, 5));  emit(CSR(6, 14, 0x7c1, 8));  emit(CSR(7, 15, 0x7c1, 1));
    emit(CSR(2, 16, 0x7c1, 0));  emit(CSR(5, 18, 0x7c1, 0));  emit(CSR(2, 19, 0x7c1, 0));
    emit(CSR(2, 20, 0x7c0, 0));                                  /* status = 0xF02 */
    emit_li(3, 0x100);  emit(CSR(1, 0, 0x7c0, 3));               /* csrrw x0: clear bit 8 */
    emit(CSR(2, 21, 0x7c0, 0));
    emit_li(4, 0xC00);  emit(CSR(2, 22, 0x7c0, 4));              /* csrrs: RMW result clears 9..11 */
    emit(CSR(2, 23, 0x7c0, 0));
    run(ISS_STUB, np, NULL, 0);
    CHECK_EQ(iss_reg(10), 0u);  CHECK_EQ(iss_reg(11), 0xF0F0u);  CHECK_EQ(iss_reg(12), 0xF0FFu);
    CHECK_EQ(iss_reg(13), 0xF000u);  CHECK_EQ(iss_reg(14), 5u);  CHECK_EQ(iss_reg(15), 0xDu);
    CHECK_EQ(iss_reg(16), 0xCu);  CHECK_EQ(iss_reg(18), 0xCu);  CHECK_EQ(iss_reg(19), 0u);
    CHECK_EQ(iss_reg(20), 0xF02u);  CHECK_EQ(iss_reg(21), 0xE02u);
    CHECK_EQ(iss_reg(22), 0xE02u);  CHECK_EQ(iss_reg(23), 0x002u);
}

static void t_csr_counters_and_unknown(void)
{
    begin();
    emit(CSR(2, 1, 0xB02, 0));                        /* minstret: 0 executed before it */
    for (int i = 0; i < 5; i++) emit(ADDI(0, 0, 0));
    emit(CSR(2, 2, 0xB02, 0));                        /* 6 before it */
    emit(CSR(2, 4, 0xB00, 0));  emit(CSR(2, 5, 0xC00, 0));    /* mcycle, cycle alias, consecutive */
    emit(SUB(6, 5, 4));
    emit(CSR(2, 7, 0xC02, 0));                        /* instret alias: 10 instructions before it */
    emit_li(8, 0x70000000u);  emit(CSR(1, 0, 0xB00, 8));      /* writes to counters are ignored */
    emit(CSR(2, 9, 0xB00, 0));                        /* so mcycle is still small */
    emit(CSR(2, 10, 0x7ff, 0));                       /* unknown CSR reads 0 */
    emit(CSR(2, 11, 0xC01, 0));                       /* time is not implemented */
    run(ISS_STUB, np, NULL, 0);
    CHECK_EQ(iss_reg(1), 0u);  CHECK_EQ(iss_reg(2), 6u);  CHECK_EQ(iss_reg(6), 1u);
    CHECK_EQ(iss_reg(7), 10u);
    CHECK_EQ(iss_reg(9) < 0x10000000u, 1u);
    CHECK_EQ(iss_reg(10), 0u);  CHECK_EQ(iss_reg(11), 0u);
}

/* ---- custom-0, stub mode --------------------------------------------------------------- */
static void t_custom_stub_log(void)
{
    uint32_t op, addr, k, clr;
    begin();
    emit_li(1, 0x10000);  emit_li(2, 16);
    emit(CUSTOM(0, 0, 0, 1, 2));  emit(CUSTOM(0, 1, 0, 1, 2));
    emit(CUSTOM(0, 2, 0, 2, 0));  emit(CUSTOM(1, 2, 0, 2, 0));
    emit(CUSTOM(0x7F, 4, 0, 1, 2));                       /* reserved funct3 -> ILLEGAL, funct7 ignored */
    emit(CUSTOM(0, 2, 7, 2, 0));                          /* rd is ignored for COMPUTE */
    emit_li(3, 0x35);  emit(CUSTOM(0, 3, 10, 3, 0));      /* READ_RESULT: idx = 0x35 & 0xF */
    run(ISS_STUB, np, NULL, 0);
    CHECK_EQ(iss_cmd_count(), 6u);
    iss_cmd_get(0, &op, &addr, &k, &clr);  CHECK_EQ(op, 0u); CHECK_EQ(addr, 0x10000u); CHECK_EQ(k, 16u); CHECK_EQ(clr, 0u);
    iss_cmd_get(1, &op, &addr, &k, &clr);  CHECK_EQ(op, 1u); CHECK_EQ(addr, 0x10000u); CHECK_EQ(k, 16u); CHECK_EQ(clr, 0u);
    iss_cmd_get(2, &op, &addr, &k, &clr);  CHECK_EQ(op, 2u); CHECK_EQ(addr, 0u);       CHECK_EQ(k, 16u); CHECK_EQ(clr, 0u);
    iss_cmd_get(3, &op, &addr, &k, &clr);  CHECK_EQ(op, 2u); CHECK_EQ(addr, 0u);       CHECK_EQ(k, 16u); CHECK_EQ(clr, 1u);
    iss_cmd_get(4, &op, &addr, &k, &clr);  CHECK_EQ(op, 3u); CHECK_EQ(addr, 0x10000u); CHECK_EQ(k, 16u); CHECK_EQ(clr, 0u);
    iss_cmd_get(5, &op, &addr, &k, &clr);  CHECK_EQ(op, 2u); CHECK_EQ(clr, 0u);
    CHECK_EQ(iss_reg(10), 5u);  CHECK_EQ(iss_reg(7), 0u);
}

/* ---- retire record, memory map, SIM MMIO ------------------------------------------------ */
static void t_retire_record_fields(void)
{
    rvvi_rec_t r[10];
    begin();
    emit(LUI(5, 0x10));  emit_li(6, 0x1234ABCDu);          /* lui + (lui, addi) */
    emit(SB(6, 5, 1));  emit(SH(6, 5, 2));  emit(SW(6, 5, 4));  emit(LW(7, 5, 4));
    emit(ADDI(0, 0, 5));  emit(J_(4, 8));  emit(ADDI(0, 0, 0));
    iss_init(prog, np, NULL, 0, ISS_STUB);
    for (int i = 0; i < 10; i++) (void)iss_step(&r[i]);
    /* (order, pc, rd, rd_wdata, mem_addr, mem_wdata, mem_wmask) worked out by hand */
    CHECK_EQ(r[0].rd, 5u);  CHECK_EQ(r[0].rd_wdata, 0x00010000u);
    CHECK_EQ(r[1].rd, 6u);  CHECK_EQ(r[1].rd_wdata, 0x1234B000u);
    CHECK_EQ(r[2].rd_wdata, 0x1234ABCDu);
    CHECK_EQ(r[3].mem_addr, 0x10001u);  CHECK_EQ(r[3].mem_wdata, 0xCDCDCDCDu);  CHECK_EQ(r[3].mem_wmask, 0x2u);
    CHECK_EQ(r[4].mem_addr, 0x10002u);  CHECK_EQ(r[4].mem_wdata, 0xABCDABCDu);  CHECK_EQ(r[4].mem_wmask, 0xCu);
    CHECK_EQ(r[5].mem_addr, 0x10004u);  CHECK_EQ(r[5].mem_wdata, 0x1234ABCDu);  CHECK_EQ(r[5].mem_wmask, 0xFu);
    CHECK_EQ(r[6].rd, 7u);  CHECK_EQ(r[6].rd_wdata, 0x1234ABCDu);
    CHECK_EQ(r[6].mem_addr, 0x10004u);  CHECK_EQ(r[6].mem_wdata, 0u);  CHECK_EQ(r[6].mem_wmask, 0u);
    CHECK_EQ(r[7].rd, 0u);  CHECK_EQ(r[7].rd_wdata, 0u);                           /* addi x0 */
    CHECK_EQ(r[8].rd, 8u);  CHECK_EQ(r[8].rd_wdata, 0x24u);                        /* jal links pc+4 */
    for (int i = 0; i < 10; i++) {
        CHECK_EQ(r[i].valid, 1u);  CHECK_EQ(r[i].trap, 0u);  CHECK_EQ(r[i].order, (uint64_t)i);
        CHECK_EQ(r[i].pc, (uint32_t)(4 * i));                  /* jal +4 lands on the next instruction */
    }
    CHECK_EQ(r[5].insn, SW(6, 5, 4));
}

static void t_memory_map_and_sim_mmio(void)
{
    int ended;
    begin();
    emit(LUI(5, 0x30));  emit_li(6, 0xDEADBEEFu);
    emit(SW(6, 5, 0));  emit(LW(7, 5, 0));                  /* unmapped: ignored, reads 0 */
    emit(SW(6, 0, 0));  emit(LW(8, 0, 0));                  /* the ITCM is not data */
    emit(LUI(9, 0x20));  emit(LW(10, 9, 0));  emit(LW(11, 9, 4));   /* write-only registers read 0 */
    emit(ADDI(12, 0, 0x4F)); emit(SB(12, 9, 4));                     /* SIM_PUTC 'O' */
    emit(ADDI(12, 0, 0x4B)); emit(SB(12, 9, 4));                     /* SIM_PUTC 'K' */
    emit(ADDI(13, 0, 1));  emit(SB(13, 9, 0));                       /* a byte write does not end the run */
    emit(SW(13, 9, 8));                                              /* neither does a neighbour */
    emit(SW(13, 9, 0));                                              /* word write of 1: PASS, the run ends */
    iss_init(prog, np, NULL, 0, ISS_STUB);
    ended = 0;
    for (uint32_t i = 0; i < np; i++) ended = iss_step(NULL);
    CHECK_EQ(ended, 1);  CHECK_EQ(iss_sim_ctrl_value(), 1u);
    CHECK_EQ(iss_reg(7), 0u);  CHECK_EQ(iss_reg(8), 0u);  CHECK_EQ(iss_reg(10), 0u);  CHECK_EQ(iss_reg(11), 0u);
    CHECK_EQ(iss_putc_count(), 2u);  CHECK_EQ(iss_putc_get(0), 0x4Fu);  CHECK_EQ(iss_putc_get(1), 0x4Bu);
    /* a fetch outside the ITCM is a NOP: jump to 0x4000 and keep going */
    begin();
    emit(LUI(1, 0x4));  emit(I_(0, 1, 0, 0, 0x67));
    run(ISS_STUB, 6, NULL, 0);
    CHECK_EQ(iss_pc(), 0x4000u + 4u * 4u);
}

static void t_init_images_and_mem_read(void)
{
    static uint32_t d[8];
    d[0] = 0xCAFEF00Du;  d[1] = 0x01020304u;
    begin();
    emit(LUI(5, 0x10));  emit(LW(10, 5, 0));  emit(LW(11, 5, 4));  emit_li(6, 0x55AA55AAu);  emit(SW(6, 5, 8));
    run(ISS_STUB, np, d, 2);
    CHECK_EQ(iss_reg(10), 0xCAFEF00Du);  CHECK_EQ(iss_reg(11), 0x01020304u);
    CHECK_EQ(iss_mem_read(0x10008u), 0x55AA55AAu);  CHECK_EQ(iss_mem_read(0x1000Bu), 0x55AA55AAu);
    CHECK_EQ(iss_mem_read(0x20000u), 0u);
    CHECK_EQ(iss_instret(), (uint64_t)np);
}

/* ---- ISS_FULL: the engine is npu_ref ----------------------------------------------------- */
static uint32_t pack4(int8_t l0, int8_t l1, int8_t l2, int8_t l3)
{
    return  (uint32_t)(uint8_t)l0        | ((uint32_t)(uint8_t)l1 << 8) |
           ((uint32_t)(uint8_t)l2 << 16) | ((uint32_t)(uint8_t)l3 << 24);
}

static void t_full_engine_dot_product(void)
{
    static uint32_t dt[ISS_DTCM_WORDS];
    int w[4][8], x[4][8];
    int32_t want[16];
    memset(dt, 0, sizeof dt);
    for (int i = 0; i < 4; i++)
        for (int t = 0; t < 8; t++) { w[i][t] = i * 3 + t - 5;  x[i][t] = i * 2 - t + 1; }
    /* quad s of the weight tile at 0x10100: word i = W[i][4s..4s+3]; inputs at 0x10200 the same way */
    for (int s = 0; s < 2; s++)
        for (int i = 0; i < 4; i++) {
            dt[0x40 + 4 * s + i] = pack4((int8_t)w[i][4*s], (int8_t)w[i][4*s+1], (int8_t)w[i][4*s+2], (int8_t)w[i][4*s+3]);
            dt[0x80 + 4 * s + i] = pack4((int8_t)x[i][4*s], (int8_t)x[i][4*s+1], (int8_t)x[i][4*s+2], (int8_t)x[i][4*s+3]);
        }
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++) {
            want[4*i+j] = 0;
            for (int t = 0; t < 8; t++) want[4*i+j] += w[i][t] * x[j][t];
        }
    begin();
    emit_li(1, 0x10100);  emit_li(2, 8);  emit_li(3, 0x10200);
    emit(CUSTOM(0, 0, 0, 1, 2));  emit(CUSTOM(0, 1, 0, 3, 2));  emit(CUSTOM(1, 2, 0, 2, 0));   /* LDW, LDI, COMPUTE clr=1 */
    for (uint32_t idx = 0; idx < 16; idx++) { emit(ADDI(4, 0, (int32_t)idx));  emit(CUSTOM(0, 3, 10 + idx, 4, 0)); }
    emit(CUSTOM(0, 2, 0, 2, 0));                                                              /* COMPUTE clr=0: accumulate again */
    emit(ADDI(4, 0, 5));  emit(CUSTOM(0, 3, 26, 4, 0));
    emit(CUSTOM(1, 2, 0, 2, 0));                                                              /* COMPUTE clr=1: restart */
    emit(CUSTOM(0, 3, 27, 4, 0));
    run(ISS_FULL, np, dt, ISS_DTCM_WORDS);
    for (uint32_t idx = 0; idx < 16; idx++) CHECK_EQ(iss_reg(10 + idx), (uint32_t)want[idx]);
    CHECK_EQ(iss_reg(26), (uint32_t)(2 * want[5]));
    CHECK_EQ(iss_reg(27), (uint32_t)want[5]);
    CHECK_EQ(iss_cmd_count(), 5u);
}

static void t_full_engine_status_and_errors(void)
{
    begin();
    emit(CSR(2, 1, 0x7c0, 0));                               /* status after reset: fifo_empty only */
    emit(CUSTOM(0, 4, 0, 0, 0));                             /* reserved funct3 -> engine sets err_illegal */
    emit(CSR(2, 2, 0x7c0, 0));
    emit_li(3, 0x400);  emit(CSR(1, 0, 0x7c0, 3));           /* csrrw: write-1-to-clear bit 10 */
    emit(CSR(2, 4, 0x7c0, 0));
    emit_li(5, 0x12345);  emit(CSR(1, 0, 0x7c1, 5));  emit(CSR(2, 6, 0x7c1, 0));
    run(ISS_FULL, np, NULL, 0);
    CHECK_EQ(iss_reg(1), 0x2u);  CHECK_EQ(iss_reg(2), 0x402u);  CHECK_EQ(iss_reg(4), 0x2u);
    CHECK_EQ(iss_reg(6), 0x12345u);
}

/* stores to the DTCM are mirrored into the engine's image, so a LOAD sees what the core stored */
static void t_full_store_visible_to_engine(void)
{
    begin();
    emit(LUI(1, 0x10));  emit_li(2, 0x01010101u);
    for (int i = 0; i < 4; i++) emit(SW(2, 1, 4 * i));       /* weight quad: all lanes = 1 */
    emit(ADDI(3, 0, 4));
    emit(CUSTOM(0, 0, 0, 1, 3));  emit(CUSTOM(0, 1, 0, 1, 3));  emit(CUSTOM(1, 2, 0, 3, 0));
    emit(CUSTOM(0, 3, 10, 0, 0));                            /* acc[0][0] = 4 * (1 * 1) = 4 */
    run(ISS_FULL, np, NULL, 0);
    CHECK_EQ(iss_reg(10), 4u);
}

/* ---- cross-check with the Python suites (make xcheck) ------------------------------------- */
static int ends_with(const char *s, const char *suffix)
{
    size_t a = strlen(s), b = strlen(suffix);
    return a >= b && strcmp(s + a - b, suffix) == 0;
}

static uint32_t read_bin(const char *path, uint32_t *words, uint32_t max_words)
{
    FILE *f = fopen(path, "rb");
    uint32_t n = 0;
    uint8_t b[4];
    if (!f) { fprintf(stderr, "cannot open %s\n", path); exit(1); }
    while (n < max_words && fread(b, 1, 4, f) == 4)
        words[n++] = (uint32_t)b[0] | ((uint32_t)b[1] << 8) | ((uint32_t)b[2] << 16) | ((uint32_t)b[3] << 24);
    fclose(f);
    return n;
}

static int xcheck(const char *dir, int min_programs)
{
    static uint32_t img[ISS_ITCM_WORDS];
    DIR *d = opendir(dir);
    struct dirent *e;
    int programs = 0;
    unsigned long long records = 0;
    if (!d) { fprintf(stderr, "xcheck: cannot open %s (run python tools/rv32i_check/run_all.py first)\n", dir); return 1; }
    while ((e = readdir(d)) != NULL) {
        char tag[256], path[1024], line[256];
        uint32_t want[32] = {0}, steps = 0, nwords;
        FILE *f;
        if (!ends_with(e->d_name, ".ref.txt")) continue;
        snprintf(tag, sizeof tag, "%.*s", (int)(strlen(e->d_name) - strlen(".ref.txt")), e->d_name);
        snprintf(path, sizeof path, "%s/%s.ref.txt", dir, tag);
        f = fopen(path, "r");
        if (!f) { fprintf(stderr, "cannot open %s\n", path); return 1; }
        while (fgets(line, sizeof line, f)) {
            unsigned r, v;
            if (sscanf(line, "x%u %x", &r, &v) == 2 && r < 32) want[r] = v;
            else if (sscanf(line, "steps %u", &steps) == 1) { }
        }
        fclose(f);
        snprintf(path, sizeof path, "%s/%s.bin", dir, tag);
        nwords = read_bin(path, img, ISS_ITCM_WORDS);
        iss_init(img, nwords, NULL, 0, ISS_STUB);
        snprintf(path, sizeof path, "%s/%s.ref_trace.txt", dir, tag);
        f = fopen(path, "r");
        if (!f) { fprintf(stderr, "cannot open %s\n", path); return 1; }
        for (uint32_t i = 0; i < steps; i++) {
            rvvi_rec_t r;
            unsigned long long order;
            unsigned pc, insn, rd, rdv, ma, mw, mm, trap;
            (void)iss_step(&r);
            if (!fgets(line, sizeof line, f) ||
                sscanf(line, "%llx %x %x %x %x %x %x %x %x", &order, &pc, &insn, &rd, &rdv, &ma, &mw, &mm, &trap) != 9) {
                fprintf(stderr, "%s: trace file ends at record %u\n", tag, i);
                return 1;
            }
            if (r.order != order || r.pc != pc || r.insn != insn || r.rd != rd || r.rd_wdata != rdv ||
                r.mem_addr != ma || r.mem_wdata != mw || r.mem_wmask != mm || r.trap != trap || r.valid != 1u) {
                fprintf(stderr, "%s: retire record %u differs (pc C=0x%x py=0x%x, insn C=0x%x py=0x%x, rd_wdata C=0x%x py=0x%x)\n",
                        tag, i, r.pc, pc, r.insn, insn, r.rd_wdata, rdv);
                return 1;
            }
            records++;
        }
        fclose(f);
        for (uint32_t r = 1; r < 32; r++)
            if (iss_reg(r) != want[r]) {
                fprintf(stderr, "%s: x%u = 0x%08x, RefISS has 0x%08x\n", tag, r, iss_reg(r), want[r]);
                return 1;
            }
        programs++;
    }
    closedir(d);
    printf("xcheck: %d programs, %llu retire records identical to RefISS\n", programs, records);
    if (programs < min_programs) {
        fprintf(stderr, "xcheck: only %d programs found, expected at least %d\n", programs, min_programs);
        return 1;
    }
    return 0;
}

int main(int argc, char **argv)
{
    if (argc >= 2 && strcmp(argv[1], "xcheck") == 0)
        return xcheck(argc >= 3 ? argv[2] : "../../tools/rv32i_check/build", argc >= 4 ? atoi(argv[3]) : 100);
    printf("rv_iss unit tests\n");
    RUN(t_encoders_match_assembler);
    RUN(t_base_alu_and_x0);
    RUN(t_branches_and_jumps);
    RUN(t_jalr_funct3_is_nop);
    RUN(t_loads_and_stores);
    RUN(t_m_mul_corners);
    RUN(t_m_div_cases);
    RUN(t_zbb_unary);
    RUN(t_zbb_binary);
    RUN(t_zbb_pack_is_nop);
    RUN(t_csr_scratch_and_status);
    RUN(t_csr_counters_and_unknown);
    RUN(t_custom_stub_log);
    RUN(t_retire_record_fields);
    RUN(t_memory_map_and_sim_mmio);
    RUN(t_init_images_and_mem_read);
    RUN(t_full_engine_dot_product);
    RUN(t_full_engine_status_and_errors);
    RUN(t_full_store_visible_to_engine);
    printf("all rv_iss tests passed\n");
    return 0;
}
