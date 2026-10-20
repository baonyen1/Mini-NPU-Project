/* rv_iss.c - untimed instruction-set simulator of the Mini-NPU core (spec 10.2, plan Task 12).
 * See rv_iss.h for the model and docs/core_isa.md for the instruction encodings.
 *
 * C99 rules of this project: all register arithmetic is done in uint32_t (wrap is defined), signed
 * operations go through int64_t, and no shift of a signed value is used. */
#include "rv_iss.h"
#include "npu_ref.h"
#include <string.h>

#define NOP          0x00000013u
#define CMD_LOG_MAX  65536u
#define PUTC_MAX     4096u

static uint32_t itcm[ISS_ITCM_WORDS];
static uint32_t dtcm[ISS_DTCM_WORDS];
static uint32_t xr[32];
static uint32_t pc_;
static uint64_t instret_;
static int      mode_;

static uint32_t sim_ctrl_last;
static uint8_t  putc_buf[PUTC_MAX];
static uint32_t putc_n;
static uint32_t cmd_log[CMD_LOG_MAX][4];
static uint32_t cmd_n;

/* ISS_STUB engine CSRs (the model of the core-only testbench stub, see rv_iss.h) */
static uint32_t stub_err;
static uint32_t stub_busy_cyc;

/* ---- small helpers ---------------------------------------------------------------------- */

static int64_t s32(uint32_t v) { return (int64_t)v - (int64_t)(v >> 31) * 4294967296LL; }

static uint32_t sext(uint32_t v, unsigned bits)     /* sign-extend the low `bits` bits, bits in 2..31 */
{
    uint32_t m = 1u << (bits - 1u);
    return ((v & ((m << 1) - 1u)) ^ m) - m;
}

static uint32_t sra32(uint32_t a, uint32_t sh)
{
    if (sh == 0u) return a;
    return (a >> sh) | ((a >> 31) ? ~(0xFFFFFFFFu >> sh) : 0u);
}

static uint32_t rol32(uint32_t a, uint32_t sh)
{
    sh &= 31u;
    return sh == 0u ? a : (a << sh) | (a >> (32u - sh));
}

static uint32_t clz32(uint32_t a) { uint32_t n = 0; while (n < 32u && !(a & (0x80000000u >> n))) n++; return n; }
static uint32_t ctz32(uint32_t a) { uint32_t n = 0; while (n < 32u && !(a & (1u << n))) n++; return n; }
static uint32_t cpop32(uint32_t a) { uint32_t n = 0; for (uint32_t i = 0; i < 32u; i++) n += (a >> i) & 1u; return n; }

static uint32_t rev8_32(uint32_t a)
{
    return (a >> 24) | ((a >> 8) & 0x0000FF00u) | ((a << 8) & 0x00FF0000u) | (a << 24);
}

static uint32_t orc_b32(uint32_t a)
{
    uint32_t r = 0;
    for (uint32_t i = 0; i < 4u; i++)
        if ((a >> (8u * i)) & 0xFFu) r |= 0xFFu << (8u * i);
    return r;
}

/* RV32M. a, b are the unsigned register values. */
static uint32_t muldiv(uint32_t f3, uint32_t a, uint32_t b)
{
    int64_t sa = s32(a), sb = s32(b);
    switch (f3) {
    case 0:  return (uint32_t)((uint64_t)a * (uint64_t)b);                    /* mul    */
    case 1:  return (uint32_t)((uint64_t)(sa * sb) >> 32);                    /* mulh   */
    case 2:  return (uint32_t)((uint64_t)(sa * (int64_t)b) >> 32);            /* mulhsu */
    case 3:  return (uint32_t)(((uint64_t)a * (uint64_t)b) >> 32);            /* mulhu  */
    case 4:  return b == 0u ? 0xFFFFFFFFu : (uint32_t)(sa / sb);              /* div: -2^31 / -1 = 2^31 in int64 */
    case 5:  return b == 0u ? 0xFFFFFFFFu : a / b;                            /* divu   */
    case 6:  return b == 0u ? a : (uint32_t)(sa % sb);                        /* rem: sign of the dividend */
    default: return b == 0u ? a : a % b;                                      /* remu   */
    }
}

/* ---- memory ------------------------------------------------------------------------------ */

static int dtcm_index(uint32_t a, uint32_t *idx)
{
    if (a - ISS_DTCM_BASE < ISS_DTCM_WORDS * 4u) { *idx = (a - ISS_DTCM_BASE) >> 2; return 1; }
    return 0;
}

static uint32_t load(uint32_t a, unsigned n, int is_signed)
{
    uint32_t idx, w, v;
    if (!dtcm_index(a, &idx)) return 0u;                      /* unmapped: reads 0 (W2-1 open) */
    w = dtcm[idx];
    if (n == 1u)      v = (w >> (8u * (a & 3u))) & 0xFFu;
    else if (n == 2u) v = (w >> (16u * ((a >> 1) & 1u))) & 0xFFFFu;
    else              return w;
    return is_signed ? sext(v, 8u * n) : v;
}

/* Store; returns 1 when the store was a word write to SIM_CTRL. wdata / wmask are the lane-aligned
 * data and the byte enables that the core drives on the data bus. */
static int store(uint32_t a, unsigned n, uint32_t v, uint32_t *wdata, uint32_t *wmask)
{
    uint32_t idx, sh, mask;
    if (n == 1u)      { *wdata = (v & 0xFFu) * 0x01010101u;   *wmask = 1u << (a & 3u); }
    else if (n == 2u) { *wdata = (v & 0xFFFFu) * 0x00010001u; *wmask = (a & 2u) ? 0xCu : 0x3u; }
    else              { *wdata = v;                           *wmask = 0xFu; }
    if (a == ISS_SIM_CTRL && n == 4u) { sim_ctrl_last = v; return 1; }
    if (a == ISS_SIM_PUTC) { if (putc_n < PUTC_MAX) putc_buf[putc_n++] = (uint8_t)(v & 0xFFu); return 0; }
    if (!dtcm_index(a, &idx)) return 0;                       /* unmapped: ignored */
    if (n == 4u) {
        dtcm[idx] = v;
    } else {
        sh   = (n == 1u) ? 8u * (a & 3u) : 16u * ((a >> 1) & 1u);
        mask = (n == 1u ? 0xFFu : 0xFFFFu) << sh;
        dtcm[idx] = (dtcm[idx] & ~mask) | ((v << sh) & mask);
    }
    if (mode_ == ISS_FULL) npu_ref_mem_write(idx, dtcm[idx]);
    return 0;
}

/* ---- CSRs --------------------------------------------------------------------------------- */

static uint32_t csr_read(uint32_t c)
{
    switch (c) {
    case 0xB00: case 0xC00: return (uint32_t)instret_;                /* mcycle: one per instruction */
    case 0xB80: case 0xC80: return (uint32_t)(instret_ >> 32);
    case 0xB02: case 0xC02: return (uint32_t)instret_;                /* instructions executed before the reader */
    case 0xB82: case 0xC82: return (uint32_t)(instret_ >> 32);
    case NPU_CSR_STATUS:
        return mode_ == ISS_FULL ? npu_ref_csr_read(c) : (stub_err << 8) | 0x2u;
    case NPU_CSR_BUSY_CYC:
        return mode_ == ISS_FULL ? npu_ref_csr_read(c) : stub_busy_cyc;
    default: return 0u;                                               /* unknown CSR (W2-1 open) */
    }
}

static void csr_write(uint32_t c, uint32_t v)
{
    if (c != NPU_CSR_STATUS && c != NPU_CSR_BUSY_CYC) return;         /* counters, aliases, unknown: ignored */
    if (mode_ == ISS_FULL) { npu_ref_csr_write(c, v); return; }
    if (c == NPU_CSR_STATUS) stub_err &= ~((v >> 8) & 0xFu);          /* W1C on bits 11..8 */
    else                     stub_busy_cyc = v;
}

/* ---- custom-0 ------------------------------------------------------------------------------ */

static void push_cmd(uint32_t op, uint32_t addr, uint32_t k, uint32_t clr)
{
    if (cmd_n < CMD_LOG_MAX) {
        cmd_log[cmd_n][0] = op; cmd_log[cmd_n][1] = addr; cmd_log[cmd_n][2] = k; cmd_log[cmd_n][3] = clr;
        cmd_n++;
    }
    if (mode_ == ISS_FULL) npu_ref_cmd(op, addr, k, clr);
}

/* ---- public API ---------------------------------------------------------------------------- */

void iss_init(const uint32_t *itcm_img, uint32_t itcm_words, const uint32_t *dtcm_img, uint32_t dtcm_words, int mode)
{
    memset(xr, 0, sizeof xr);
    memset(dtcm, 0, sizeof dtcm);
    for (uint32_t i = 0; i < ISS_ITCM_WORDS; i++) itcm[i] = NOP;
    if (itcm_img) for (uint32_t i = 0; i < itcm_words && i < ISS_ITCM_WORDS; i++) itcm[i] = itcm_img[i];
    if (dtcm_img) for (uint32_t i = 0; i < dtcm_words && i < ISS_DTCM_WORDS; i++) dtcm[i] = dtcm_img[i];
    pc_ = 0u; instret_ = 0u; mode_ = mode;
    sim_ctrl_last = 0u; putc_n = 0u; cmd_n = 0u;
    stub_err = 0xFu; stub_busy_cyc = 0u;
    if (mode_ == ISS_FULL) {
        npu_ref_reset();
        for (uint32_t i = 0; i < ISS_DTCM_WORDS; i++) npu_ref_mem_write(i, dtcm[i]);
    }
}

int iss_step(rvvi_rec_t *rec)
{
    uint32_t ins = (pc_ >> 2) < ISS_ITCM_WORDS ? itcm[pc_ >> 2] : NOP;   /* a fetch outside the ITCM is a NOP */
    uint32_t op = ins & 0x7Fu, rd = (ins >> 7) & 31u, f3 = (ins >> 12) & 7u;
    uint32_t rs1 = (ins >> 15) & 31u, rs2 = (ins >> 20) & 31u, f7 = ins >> 25;
    uint32_t a = xr[rs1], b = xr[rs2];
    uint32_t iimm = sext(ins >> 20, 12);
    uint32_t simm = sext(((ins >> 25) << 5) | ((ins >> 7) & 31u), 12);
    uint32_t bimm = sext((((ins >> 31) & 1u) << 12) | (((ins >> 7) & 1u) << 11) |
                         (((ins >> 25) & 63u) << 5) | (((ins >> 8) & 15u) << 1), 13);
    uint32_t jimm = sext((((ins >> 31) & 1u) << 20) | (((ins >> 12) & 255u) << 12) |
                         (((ins >> 20) & 1u) << 11) | (((ins >> 21) & 1023u) << 1), 21);
    uint32_t npc = pc_ + 4u, w = 0u, shamt = (ins >> 20) & 31u, imm12 = ins >> 20;
    uint32_t mem_addr = 0u, mem_wdata = 0u, mem_wmask = 0u;
    int has_w = 0, sim_end = 0;

    switch (op) {
    case 0x33:                                             /* OP: base, M, Zbb */
        has_w = 1;
        if (f7 == 0x01u) { w = muldiv(f3, a, b); break; }
        switch (f3) {
        case 0: if (f7 == 0x00u) w = a + b; else if (f7 == 0x20u) w = a - b; else has_w = 0; break;
        case 1: if (f7 == 0x00u) w = a << (b & 31u); else if (f7 == 0x30u) w = rol32(a, b); else has_w = 0; break;
        case 2: if (f7 == 0x00u) w = (uint32_t)(s32(a) < s32(b)); else has_w = 0; break;
        case 3: if (f7 == 0x00u) w = (uint32_t)(a < b); else has_w = 0; break;
        case 4:
            if (f7 == 0x00u) w = a ^ b;
            else if (f7 == 0x20u) w = ~(a ^ b);                                   /* xnor */
            else if (f7 == 0x05u) w = (s32(a) < s32(b)) ? a : b;                 /* min */
            else if (f7 == 0x04u && rs2 == 0u) w = a & 0xFFFFu;                   /* zext.h (pack rd, rs1, x0) */
            else has_w = 0;
            break;
        case 5:
            if (f7 == 0x00u) w = a >> (b & 31u);
            else if (f7 == 0x20u) w = sra32(a, b & 31u);
            else if (f7 == 0x05u) w = a < b ? a : b;                              /* minu */
            else if (f7 == 0x30u) w = rol32(a, 32u - (b & 31u));                  /* ror */
            else has_w = 0;
            break;
        case 6:
            if (f7 == 0x00u) w = a | b;
            else if (f7 == 0x20u) w = a | ~b;                                     /* orn */
            else if (f7 == 0x05u) w = (s32(a) < s32(b)) ? b : a;                  /* max */
            else has_w = 0;
            break;
        default:
            if (f7 == 0x00u) w = a & b;
            else if (f7 == 0x20u) w = a & ~b;                                     /* andn */
            else if (f7 == 0x05u) w = a < b ? b : a;                              /* maxu */
            else has_w = 0;
            break;
        }
        break;
    case 0x13:                                             /* OP-IMM: base and Zbb */
        has_w = 1;
        switch (f3) {
        case 0: w = a + iimm; break;
        case 2: w = (uint32_t)(s32(a) < s32(iimm)); break;
        case 3: w = (uint32_t)(a < iimm); break;
        case 4: w = a ^ iimm; break;
        case 6: w = a | iimm; break;
        case 7: w = a & iimm; break;
        case 1:
            if (f7 == 0x00u) w = a << shamt;
            else if (f7 == 0x30u && shamt == 0u) w = clz32(a);
            else if (f7 == 0x30u && shamt == 1u) w = ctz32(a);
            else if (f7 == 0x30u && shamt == 2u) w = cpop32(a);
            else if (f7 == 0x30u && shamt == 4u) w = sext(a, 8);
            else if (f7 == 0x30u && shamt == 5u) w = sext(a, 16);
            else has_w = 0;
            break;
        default:
            if (f7 == 0x00u) w = a >> shamt;
            else if (f7 == 0x20u) w = sra32(a, shamt);
            else if (f7 == 0x30u) w = rol32(a, 32u - shamt);                      /* rori */
            else if (imm12 == 0x287u) w = orc_b32(a);
            else if (imm12 == 0x698u) w = rev8_32(a);
            else has_w = 0;
            break;
        }
        break;
    case 0x37: w = ins & 0xFFFFF000u; has_w = 1; break;                           /* lui */
    case 0x17: w = pc_ + (ins & 0xFFFFF000u); has_w = 1; break;                   /* auipc */
    case 0x03:                                                                    /* loads */
        mem_addr = a + iimm;
        switch (f3) {
        case 0: w = load(mem_addr, 1, 1); has_w = 1; break;
        case 1: w = load(mem_addr, 2, 1); has_w = 1; break;
        case 2: w = load(mem_addr, 4, 0); has_w = 1; break;
        case 4: w = load(mem_addr, 1, 0); has_w = 1; break;
        case 5: w = load(mem_addr, 2, 0); has_w = 1; break;
        default: mem_addr = 0u; break;
        }
        break;
    case 0x23:                                                                    /* stores */
        if (f3 <= 2u) {
            mem_addr = a + simm;
            sim_end = store(mem_addr, 1u << f3, b, &mem_wdata, &mem_wmask);
        }
        break;
    case 0x63: {                                                                  /* branches */
        int taken = 0;
        switch (f3) {
        case 0: taken = (a == b); break;
        case 1: taken = (a != b); break;
        case 4: taken = (s32(a) < s32(b)); break;
        case 5: taken = (s32(a) >= s32(b)); break;
        case 6: taken = (a < b); break;
        case 7: taken = (a >= b); break;
        default: break;
        }
        if (taken) npc = pc_ + bimm;
        break;
    }
    case 0x6F: w = pc_ + 4u; has_w = 1; npc = pc_ + jimm; break;                  /* jal */
    case 0x67:                                                                    /* jalr */
        if (f3 == 0u) { w = pc_ + 4u; has_w = 1; npc = (a + iimm) & ~1u; }
        break;
    case 0x73:                                                                    /* Zicsr; ecall/ebreak are NOPs */
        if (f3 != 0u && f3 != 4u) {
            uint32_t csr = ins >> 20, old = csr_read(csr);
            uint32_t opnd = (f3 & 4u) ? rs1 : a, nv = 0u;
            int wr = 0;
            switch (f3 & 3u) {
            case 1: nv = opnd;         wr = 1; break;                             /* csrrw / csrrwi */
            case 2: nv = old | opnd;   wr = (rs1 != 0u); break;                   /* csrrs / csrrsi */
            default: nv = old & ~opnd; wr = (rs1 != 0u); break;                   /* csrrc / csrrci */
            }
            if (wr) csr_write(csr, nv);
            w = old; has_w = 1;
        }
        break;
    case 0x0B:                                                                    /* custom-0 */
        switch (f3) {
        case 0: case 1: push_cmd(f3, a, b, 0u); break;                            /* LOAD_WEIGHT, LOAD_INPUT */
        case 2:         push_cmd(2u, 0u, a, f7 & 1u); break;                      /* COMPUTE */
        case 3:         w = (mode_ == ISS_FULL) ? npu_ref_read(a) : (a & 0xFu); has_w = 1; break;   /* READ_RESULT */
        default:        push_cmd(3u, a, b, 0u); break;                            /* reserved funct3: ILLEGAL */
        }
        break;
    default: break;                                       /* fence, fence.i and unknown encodings: NOP */
    }

    if (rec) {
        rec->valid = 1u; rec->order = instret_; rec->pc = pc_; rec->insn = ins; rec->trap = 0u;
        rec->rd = (has_w && rd != 0u) ? rd : 0u;
        rec->rd_wdata = (has_w && rd != 0u) ? w : 0u;
        rec->mem_addr = mem_addr; rec->mem_wdata = mem_wdata; rec->mem_wmask = mem_wmask;
    }
    if (has_w && rd != 0u) xr[rd] = w;
    pc_ = npc;
    instret_++;
    return sim_end;
}

uint32_t iss_reg(uint32_t index) { return xr[index & 31u]; }
uint32_t iss_pc(void) { return pc_; }
uint64_t iss_instret(void) { return instret_; }

uint32_t iss_mem_read(uint32_t byte_addr)
{
    uint32_t idx;
    return dtcm_index(byte_addr, &idx) ? dtcm[idx] : 0u;
}

uint32_t iss_sim_ctrl_value(void) { return sim_ctrl_last; }
uint32_t iss_putc_count(void) { return putc_n; }
uint32_t iss_putc_get(uint32_t i) { return i < putc_n ? putc_buf[i] : 0u; }
uint32_t iss_cmd_count(void) { return cmd_n; }

void iss_cmd_get(uint32_t i, uint32_t *op, uint32_t *addr, uint32_t *k, uint32_t *clr)
{
    if (i >= cmd_n) { *op = *addr = *k = *clr = 0u; return; }
    *op = cmd_log[i][0]; *addr = cmd_log[i][1]; *k = cmd_log[i][2]; *clr = cmd_log[i][3];
}
