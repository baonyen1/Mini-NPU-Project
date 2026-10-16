/* Unit tests for npu_ref (Phase 1 plan, Task 10).
 * Run: make -C model/c test
 * Spec refs: 6.2 data format, 6.3 semantics and errors, 6.4 CSRs. */
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include "npu_ref.h"

#define CHECK_EQ(got, want) do {                                              \
    uint32_t g_ = (uint32_t)(got), w_ = (uint32_t)(want);                     \
    if (g_ != w_) {                                                           \
        fprintf(stderr, "FAIL %s:%d: %s = 0x%08x, expected %s = 0x%08x\n",    \
                __FILE__, __LINE__, #got, g_, #want, w_);                     \
        exit(1);                                                              \
    }                                                                         \
} while (0)

#define RUN(t) do { printf("  %-28s", #t); t(); printf("ok\n"); } while (0)

#define ERR_ALL (NPU_ST_ERR_K | NPU_ST_ERR_ADDR | NPU_ST_ERR_ILLEGAL | NPU_ST_ERR_ALIGN)

/* ---- helpers ---------------------------------------------------------- */

/* 4 int8 lanes -> one DTCM word, lane 0 = LSB (spec 6.2). */
static uint32_t pack4(int8_t l0, int8_t l1, int8_t l2, int8_t l3)
{
    return  (uint32_t)(uint8_t)l0        | ((uint32_t)(uint8_t)l1 << 8) |
           ((uint32_t)(uint8_t)l2 << 16) | ((uint32_t)(uint8_t)l3 << 24);
}

static int32_t lane(uint32_t w, int t) { return (int8_t)(w >> (8 * t)); }

static uint32_t widx(uint32_t byte_addr) { return (byte_addr - NPU_DTCM_BASE) / 4u; }
static void put_word(uint32_t byte_addr, uint32_t w) { npu_ref_mem_write(widx(byte_addr), w); }
static uint32_t errs(void) { return npu_ref_status() & ERR_ALL; }

static void fill(uint32_t byte_addr, uint32_t nwords, uint32_t w)
{
    for (uint32_t i = 0; i < nwords; i++) put_word(byte_addr + 4 * i, w);
}

/* Hand case of the plan: weights at W0, inputs at I0, one quad each. */
#define W0 0x00010000u
#define I0 0x00010010u

/* HAND[4*i + j] = dot(row i, image j). */
static const int32_t HAND[16] = {
      10,    1, -1280,   -4,
     -10,   -1,  1280,    4,
     127,  127, -16256, 254,
    -128,    0, 16384,  256,
};

static void hand_setup(void)
{
    npu_ref_reset();
    put_word(W0 +  0, pack4(1, 2, 3, 4));
    put_word(W0 +  4, pack4(-1, -2, -3, -4));
    put_word(W0 +  8, pack4(127, 0, 0, 0));
    put_word(W0 + 12, pack4(0, 0, 0, -128));
    put_word(I0 +  0, pack4(1, 1, 1, 1));
    put_word(I0 +  4, pack4(1, 0, 0, 0));
    put_word(I0 +  8, pack4(-128, -128, -128, -128));
    put_word(I0 + 12, pack4(2, -2, 2, -2));
}

static void hand_run(void)
{
    npu_ref_cmd(NPU_OP_LDW, W0, 4, 0);
    npu_ref_cmd(NPU_OP_LDI, I0, 4, 0);
    npu_ref_cmd(NPU_OP_MAC, 0, 4, 1);
}

static void check_hand_acc(void)
{
    for (uint32_t idx = 0; idx < 16; idx++) CHECK_EQ(npu_ref_read(idx), HAND[idx]);
}

/* Overwrite the hand data in DTCM with zeros. A dropped LOAD that wrongly
 * executes would then pull zeros into the buffer and the result changes. */
static void scribble_hand_mem(void)
{
    fill(W0, 4, 0);
    fill(I0, 4, 0);
}

/* The accumulators and both buffers still hold the hand case. */
static void expect_hand_state_kept(void)
{
    check_hand_acc();
    npu_ref_cmd(NPU_OP_MAC, 0, 4, 1);   /* recompute from the buffers */
    check_hand_acc();
}

/* Run the hand case, destroy its memory, issue one command, then check that
 * exactly `want_err` is set and nothing else changed. */
static void expect_dropped(uint32_t op, uint32_t addr, uint32_t k, uint32_t clr,
                           uint32_t want_err)
{
    hand_setup();
    hand_run();
    scribble_hand_mem();
    npu_ref_cmd(op, addr, k, clr);
    CHECK_EQ(errs(), want_err);
    expect_hand_state_kept();
}

static const uint32_t OPS3[3] = { NPU_OP_LDW, NPU_OP_LDI, NPU_OP_MAC };
static const uint32_t LOADS[2] = { NPU_OP_LDW, NPU_OP_LDI };

/* Both buffers = 1024 elements of -128 (K = KMAX). */
#define BIG_W 0x00010000u
#define BIG_I 0x00011000u
static void extremes_setup(void)
{
    npu_ref_reset();
    fill(BIG_W, 1024, 0x80808080u);
    fill(BIG_I, 1024, 0x80808080u);
    npu_ref_cmd(NPU_OP_LDW, BIG_W, 1024, 0);
    npu_ref_cmd(NPU_OP_LDI, BIG_I, 1024, 0);
}

static void check_all_acc(uint32_t want)
{
    for (uint32_t idx = 0; idx < 16; idx++) CHECK_EQ(npu_ref_read(idx), want);
}

/* ---- tests ------------------------------------------------------------ */

static void test_status_idle(void)
{
    npu_ref_reset();
    CHECK_EQ(npu_ref_status(), NPU_ST_FIFO_EMPTY);   /* untimed: busy=0 full=0 */
}

static void test_hand_4x4_k4(void)
{
    hand_setup();
    hand_run();
    check_hand_acc();
    CHECK_EQ(errs(), 0);
}

static void test_read_idx_masks(void)
{
    hand_setup();
    hand_run();
    CHECK_EQ(npu_ref_read(0x14), npu_ref_read(0x4));
    CHECK_EQ(npu_ref_read(0xFFFFFFF5u), npu_ref_read(0x5));
}

/* Random-looking data and an independent oracle that works straight from the
 * word arrays: catches quad/word/lane layout mistakes the hand case may hide. */
static void test_hand_k8_accumulate(void)
{
    enum { Q = 2 };                      /* 2 quads = K 8 */
    uint32_t wm[4 * Q], im[4 * Q], s = 12345u;
    for (int n = 0; n < 4 * Q; n++) {
        s = s * 1664525u + 1013904223u; wm[n] = s;
        s = s * 1664525u + 1013904223u; im[n] = s;
    }
    uint32_t want[16];
    for (int i = 0; i < 4; i++)
        for (int j = 0; j < 4; j++) {
            int32_t sum = 0;
            for (int q = 0; q < Q; q++)
                for (int t = 0; t < 4; t++)
                    sum += lane(wm[4 * q + i], t) * lane(im[4 * q + j], t);
            want[4 * i + j] = (uint32_t)sum;
        }
    const uint32_t WA = 0x00010000u, IA = 0x00010100u;

    /* (a) one COMPUTE with K = 8 */
    npu_ref_reset();
    for (int n = 0; n < 4 * Q; n++) { put_word(WA + 4 * n, wm[n]); put_word(IA + 4 * n, im[n]); }
    npu_ref_cmd(NPU_OP_LDW, WA, 8, 0);
    npu_ref_cmd(NPU_OP_LDI, IA, 8, 0);
    npu_ref_cmd(NPU_OP_MAC, 0, 8, 1);
    for (uint32_t idx = 0; idx < 16; idx++) CHECK_EQ(npu_ref_read(idx), want[idx]);

    /* (b) two COMPUTEs with K = 4, the second one accumulating (clr = 0) */
    npu_ref_reset();
    for (int n = 0; n < 4 * Q; n++) { put_word(WA + 4 * n, wm[n]); put_word(IA + 4 * n, im[n]); }
    npu_ref_cmd(NPU_OP_LDW, WA, 4, 0);
    npu_ref_cmd(NPU_OP_LDI, IA, 4, 0);
    npu_ref_cmd(NPU_OP_MAC, 0, 4, 1);
    npu_ref_cmd(NPU_OP_LDW, WA + 16, 4, 0);
    npu_ref_cmd(NPU_OP_LDI, IA + 16, 4, 0);
    npu_ref_cmd(NPU_OP_MAC, 0, 4, 0);
    for (uint32_t idx = 0; idx < 16; idx++) CHECK_EQ(npu_ref_read(idx), want[idx]);
    CHECK_EQ(errs(), 0);
}

static void test_clr_vs_acc(void)
{
    hand_setup();
    hand_run();
    npu_ref_cmd(NPU_OP_MAC, 0, 4, 0);          /* accumulate: every value doubles */
    for (uint32_t idx = 0; idx < 16; idx++) CHECK_EQ(npu_ref_read(idx), 2 * HAND[idx]);
    npu_ref_cmd(NPU_OP_MAC, 0, 4, 1);          /* clr: back to one copy */
    check_hand_acc();
}

static void test_extremes(void)
{
    extremes_setup();
    npu_ref_cmd(NPU_OP_MAC, 0, 1024, 1);
    check_all_acc(16777216u);                  /* 1024 * (-128)^2 */
    CHECK_EQ(errs(), 0);                       /* K = KMAX is legal */
}

/* The plan's 129 x 2^24 never reaches 2^32. 257 does: 128 -> 2^31 (signed
 * overflow point), 256 -> 0 (wrapped), 257 -> 2^24. */
static void test_wrap(void)
{
    extremes_setup();
    npu_ref_cmd(NPU_OP_MAC, 0, 1024, 1);                      /* total 1 */
    for (int n = 1; n < 128; n++) npu_ref_cmd(NPU_OP_MAC, 0, 1024, 0);
    check_all_acc(0x80000000u);                               /* total 128 */
    for (int n = 128; n < 256; n++) npu_ref_cmd(NPU_OP_MAC, 0, 1024, 0);
    check_all_acc(0u);                                        /* total 256 */
    npu_ref_cmd(NPU_OP_MAC, 0, 1024, 0);
    check_all_acc((uint32_t)(257ull * 16777216ull));          /* total 257 = 2^24 */
    CHECK_EQ(errs(), 0);
}

static void test_k0_noop(void)
{
    for (int o = 0; o < 3; o++)
        for (uint32_t clr = 0; clr < 2; clr++)
            expect_dropped(OPS3[o], 0xFFFFFFFFu, 0, clr, 0);  /* addr must not even be checked */
}

static void test_compute_k0_clr_keeps_acc(void)    /* Review Focus 5 */
{
    hand_setup();
    hand_run();
    npu_ref_cmd(NPU_OP_MAC, 0, 0, 1);
    check_hand_acc();
    CHECK_EQ(errs(), 0);
}

static void test_k_too_big(void)
{
    for (int o = 0; o < 3; o++) expect_dropped(OPS3[o], W0, 1028, 1, NPU_ST_ERR_K);
}

static void test_k_not_multiple_of_4(void)
{
    static const uint32_t ks[] = { 1, 2, 3, 6, 1022 };
    for (int o = 0; o < 3; o++)
        for (unsigned n = 0; n < sizeof ks / sizeof ks[0]; n++)
            expect_dropped(OPS3[o], W0, ks[n], 1, NPU_ST_ERR_K);
}

static void test_addr_out_of_range(void)
{
    for (int o = 0; o < 2; o++) {
        expect_dropped(LOADS[o], 0x0000FFF0u, 4, 0, NPU_ST_ERR_ADDR);   /* just below DTCM */
        expect_dropped(LOADS[o], 0x00000000u, 4, 0, NPU_ST_ERR_ADDR);   /* ITCM, not DTCM */
        expect_dropped(LOADS[o], 0x0001FFF0u, 8, 0, NPU_ST_ERR_ADDR);   /* runs past the end */
        expect_dropped(LOADS[o], 0x00020000u, 4, 0, NPU_ST_ERR_ADDR);   /* starts at the end */
    }
}

static void test_load_addr_wraps_32bit(void)       /* Review Focus 4 */
{
    for (int o = 0; o < 2; o++)
        expect_dropped(LOADS[o], 0xFFFFFFF0u, 8, 0, NPU_ST_ERR_ADDR);
}

static void test_last_quad_ok(void)
{
    for (int o = 0; o < 2; o++) {
        npu_ref_reset();
        npu_ref_cmd(LOADS[o], 0x0001FFF0u, 4, 0);
        CHECK_EQ(errs(), 0);
    }
}

static void test_addr_misaligned(void)
{
    for (int o = 0; o < 2; o++) {
        expect_dropped(LOADS[o], 0x00010004u, 4, 0, NPU_ST_ERR_ALIGN);
        expect_dropped(LOADS[o], 0x00010001u, 4, 0, NPU_ST_ERR_ALIGN);
        /* misaligned AND out of range: align is checked first, only it is set */
        expect_dropped(LOADS[o], 0x0001FFF4u, 8, 0, NPU_ST_ERR_ALIGN);
    }
}

static void test_mac_ignores_addr(void)
{
    expect_dropped(NPU_OP_MAC, 0x00000003u, 4, 1, 0);
}

static void test_illegal_op(void)
{
    expect_dropped(NPU_OP_ILLEGAL, W0, 4, 0, NPU_ST_ERR_ILLEGAL);
}

static void test_w1c(void)
{
    npu_ref_reset();
    npu_ref_cmd(NPU_OP_MAC, 0, 6, 0);                 /* err_k */
    npu_ref_cmd(NPU_OP_LDW, 0x0001FFF0u, 8, 0);       /* err_addr */
    npu_ref_cmd(NPU_OP_ILLEGAL, W0, 4, 0);            /* err_illegal */
    npu_ref_cmd(NPU_OP_LDI, 0x00010004u, 4, 0);       /* err_align */
    CHECK_EQ(errs(), ERR_ALL);                        /* sticky: all four are set */

    npu_ref_csr_write(NPU_CSR_STATUS, 0);             /* writing 0 clears nothing */
    CHECK_EQ(errs(), ERR_ALL);
    npu_ref_csr_write(NPU_CSR_STATUS, 0x7);           /* RO bits: no effect */
    CHECK_EQ(npu_ref_status(), ERR_ALL | NPU_ST_FIFO_EMPTY);
    npu_ref_csr_write(NPU_CSR_STATUS, NPU_ST_ERR_K);  /* clears only err_k */
    CHECK_EQ(errs(), ERR_ALL & ~NPU_ST_ERR_K);
    npu_ref_csr_write(NPU_CSR_STATUS, 0xF00);         /* clears the rest */
    CHECK_EQ(errs(), 0);
    CHECK_EQ(npu_ref_status(), NPU_ST_FIFO_EMPTY);
}

int main(void)
{
    printf("npu_ref unit tests\n");
    RUN(test_status_idle);
    RUN(test_hand_4x4_k4);
    RUN(test_read_idx_masks);
    RUN(test_hand_k8_accumulate);
    RUN(test_clr_vs_acc);
    RUN(test_extremes);
    RUN(test_wrap);
    RUN(test_k0_noop);
    RUN(test_compute_k0_clr_keeps_acc);
    RUN(test_k_too_big);
    RUN(test_k_not_multiple_of_4);
    RUN(test_addr_out_of_range);
    RUN(test_load_addr_wraps_32bit);
    RUN(test_last_quad_ok);
    RUN(test_addr_misaligned);
    RUN(test_mac_ignores_addr);
    RUN(test_illegal_op);
    RUN(test_w1c);
    printf("npu_ref: all tests passed\n");
    return 0;
}
