/* Unit tests for npu_ref (Phase 1 plan, Task 10). Plain C asserts.
 * Write each test BEFORE the code it checks and watch it fail first. */
#include <assert.h>
#include <stdio.h>
#include "npu_ref.h"

/* Helper: pack 4 int8 lanes into one DTCM word, lane 0 = LSB (spec 6.2). */
static uint32_t pack4(int8_t l0, int8_t l1, int8_t l2, int8_t l3)
{
    return  (uint32_t)(uint8_t)l0        | ((uint32_t)(uint8_t)l1 << 8) |
           ((uint32_t)(uint8_t)l2 << 16) | ((uint32_t)(uint8_t)l3 << 24);
}

/* Word index of a DTCM byte address (use in tests, not in the model). */
static uint32_t widx(uint32_t byte_addr) { return (byte_addr - NPU_DTCM_BASE) / 4u; }

static void test_hand_4x4_k4(void)
{
    /* TODO(Bao): rows r0..r3 and images x0..x3 from the plan, expected
     * acc[i][j] read back with npu_ref_read(4*i + j). */
    (void)pack4; (void)widx;
}

/* TODO(Bao): hand_k8_accumulate, extremes, wrap, k0_noop,
 * compute_k0_clr_keeps_acc, k_too_big, k_not_multiple_of_4,
 * addr_out_of_range, load_addr_wraps_32bit, last_quad_ok, illegal_op,
 * w1c, addr_misaligned. */

int main(void)
{
    npu_ref_reset();
    test_hand_4x4_k4();
    printf("npu_ref: all tests passed\n");
    return 0;
}
