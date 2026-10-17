/* npu_ref.c - untimed golden model of the MAC engine (spec 6, 10.2). */
#include "npu_ref.h"
#include <assert.h>
#include <string.h>

#define NPU_ERR_MASK (NPU_ST_ERR_K | NPU_ST_ERR_ADDR | NPU_ST_ERR_ILLEGAL | NPU_ST_ERR_ALIGN)

/* ---- state (spec 6.2, 6.4) -------------------------------------------- */
static uint32_t dtcm[NPU_DTCM_WORDS];       /* the model's own DTCM image            */
static uint32_t wbuf[NPU_KMAX / 4][4];      /* 256 quads; wbuf[s][i] = word i of quad s */
static uint32_t ibuf[NPU_KMAX / 4][4];
static uint32_t acc[4][4];                  /* uint32_t: wrap mod 2^32 is defined in C */
static uint32_t err_bits;                   /* only bits 8..11 of npu_status         */
static uint32_t busy_cyc;                   /* CSR 0x7C1, a plain stored value       */

/* ---- internal helpers ------------------------------------------------- */

static void load_quads(uint32_t buf[NPU_KMAX / 4][4], uint32_t addr, uint32_t k)
{
    uint32_t quads = k / 4u;
    uint32_t base_word = (addr - NPU_DTCM_BASE) / 4u;

    for (uint32_t s = 0; s < quads; s++) {
        for (uint32_t i = 0; i < 4u; i++) {
            buf[s][i] = dtcm[base_word + 4u * s + i];
        }
    }
}

static int32_t dot4(uint32_t w_word, uint32_t i_word)
{
    int32_t sum = 0;
    for (int t = 0; t < 4; t++) {
        int32_t w_lane = (int8_t)(w_word >> (8 * t));
        int32_t i_lane = (int8_t)(i_word >> (8 * t));
        sum += w_lane * i_lane;
    }
    return sum;
}

static void run_mac(uint32_t k, uint32_t clr)
{
    uint32_t quads = k / 4u;

    for (uint32_t i = 0; i < 4u; i++) {
        for (uint32_t j = 0; j < 4u; j++) {
            if (clr != 0u) {
                acc[i][j] = 0u;
            }
            for (uint32_t s = 0; s < quads; s++) {
                acc[i][j] += (uint32_t)dot4(wbuf[s][i], ibuf[s][j]);
            }
        }
    }
}

/* ---- public API (ordered: status -> reset -> mem_write -> read -> cmd -> csr_write) ---- */

uint32_t npu_ref_status(void)
{
    return (err_bits & NPU_ERR_MASK) | NPU_ST_FIFO_EMPTY;
}

void npu_ref_reset(void)
{
    memset(dtcm, 0, sizeof(dtcm));
    memset(wbuf, 0, sizeof(wbuf));
    memset(ibuf, 0, sizeof(ibuf));
    memset(acc, 0, sizeof(acc));
    err_bits = 0u;
    busy_cyc = 0u;
}

void npu_ref_mem_write(uint32_t word_idx, uint32_t data)
{
    assert(word_idx < NPU_DTCM_WORDS);
    dtcm[word_idx] = data;
}

uint32_t npu_ref_read(uint32_t idx)
{
    uint32_t masked = idx & 0xFu;
    uint32_t row = (masked >> 2) & 0x3u;
    uint32_t col = masked & 0x3u;
    return acc[row][col];
}

void npu_ref_cmd(uint32_t op, uint32_t addr, uint32_t k, uint32_t clr)
{
    /* 1. Illegal opcode check */
    if (op != NPU_OP_LDW && op != NPU_OP_LDI && op != NPU_OP_MAC) {
        err_bits |= NPU_ST_ERR_ILLEGAL;
        return;
    }

    /* 2. K == 0 is a no-op (no error, clr is ignored) */
    if (k == 0u) {
        return;
    }

    /* 3. K range and multiple-of-4 check */
    if (k > NPU_KMAX || (k & 0x3u) != 0u) {
        err_bits |= NPU_ST_ERR_K;
        return;
    }

    /* 4. Address alignment and 64-bit bounds check (LDW / LDI only) */
    if (op == NPU_OP_LDW || op == NPU_OP_LDI) {
        if ((addr & 0xFu) != 0u) {
            err_bits |= NPU_ST_ERR_ALIGN;
            return;
        }
        uint64_t start = (uint64_t)addr;
        uint64_t end   = start + 4ull * (uint64_t)k;
        uint64_t limit = (uint64_t)NPU_DTCM_BASE + (uint64_t)NPU_DTCM_BYTES;
        if (start < (uint64_t)NPU_DTCM_BASE || end > limit) {
            err_bits |= NPU_ST_ERR_ADDR;
            return;
        }
    }

    /* 5. Execute valid command */
    if (op == NPU_OP_LDW) {
        load_quads(wbuf, addr, k);
    } else if (op == NPU_OP_LDI) {
        load_quads(ibuf, addr, k);
    } else {
        run_mac(k, clr);
    }
}

void npu_ref_csr_write(uint32_t addr, uint32_t data)
{
    if (addr == NPU_CSR_STATUS) {
        err_bits &= ~(data & NPU_ERR_MASK);
    } else if (addr == NPU_CSR_BUSY_CYC) {
        busy_cyc = data;
        (void)busy_cyc;
    }
}
