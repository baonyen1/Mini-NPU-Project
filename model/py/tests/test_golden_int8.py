"""Unit tests of golden_int8 (Phase 1 Task 2b, spec 10.2 gate): run
    python -m pytest model/py/tests -v
before the golden is used as an oracle. Includes the cross-check against the C model npu_ref."""
import ctypes
import json
import os
import shutil
import subprocess
import sys

import numpy as np
import pytest

HERE = os.path.dirname(os.path.abspath(__file__))
PY_DIR = os.path.dirname(HERE)
ROOT = os.path.dirname(os.path.dirname(PY_DIR))
EXPORT = os.path.join(ROOT, 'model', 'py', 'export')
sys.path.insert(0, PY_DIR)

import golden_int8 as g  # noqa: E402


# ---- helpers ----------------------------------------------------------------------------------

def py_requant(acc, M, S):
    """The spec formula in plain Python ints (floor shift): the independent reference."""
    return min(127, max(0, (int(acc) * int(M) + 2 ** (int(S) - 1)) >> int(S)))


def py_forward(quant, x_row):
    """Whole network in plain Python ints for one input vector."""
    x = [int(v) for v in x_row]
    out = {}
    n = len(quant)
    for i in range(n):
        w = quant[i]['w_q'].tolist()
        b = quant[i]['b_q'].tolist()
        acc = [sum(wij * xj for wij, xj in zip(row, x)) + bj for row, bj in zip(w, b)]
        if i < n - 1:
            x = [py_requant(a, quant[i]['M'], quant[i]['S']) for a in acc]
            out[f'act{i + 1}'] = x
        else:
            out['logit'] = acc
    return out


def random_quant(rng, sizes=(784, 64, 32, 12), reals=(0.002, 0.004)):
    """A random int8 network with the real shapes; M, S come from find_ms like in the notebook."""
    quant = []
    for i in range(len(sizes) - 1):
        w_q = rng.integers(-127, 128, size=(sizes[i + 1], sizes[i])).astype(np.int8)
        b_q = rng.integers(-5000, 5000, size=sizes[i + 1]).astype(np.int32)
        if i < len(sizes) - 2:
            M, S = g.find_ms(reals[i], g.compute_bound(w_q, b_q))
        else:
            M = S = None
        quant.append({'w_q': w_q, 'b_q': b_q, 'M': M, 'S': S})
    return quant


# ---- requant ----------------------------------------------------------------------------------

def test_requant_hand_vectors():
    cases = [(10, 1, 1, 5), (-5, 1, 1, 0), (1000, 1, 3, 125), (2000, 1, 3, 127), (7, 1, 2, 2)]
    for acc, M, S, want in cases:
        got = g.requant(np.array([acc], dtype=np.int32), M, S)
        assert int(got[0]) == want, (acc, M, S)


def test_requant_matches_python_int():
    """Phase 4 Review Focus 1: >= 10,000 random cases inside the overflow bound, with negative acc
    and exact rounding ties ((acc*M) mod 2**S == 2**(S-1))."""
    rng = np.random.default_rng(20261023)
    n = ties = negatives = 0
    while n < 12000:
        S = int(rng.integers(1, 32))
        M = int(rng.integers(1, 2 ** int(rng.integers(1, 21))))
        bound = (g.INT32_MAX - 2 ** (S - 1)) // M
        if bound < 1:
            continue
        if n % 3 == 0 and M % 2 == 1:           # force a tie: M*acc = 2**(S-1) (mod 2**S)
            acc0 = (2 ** (S - 1) * pow(M, -1, 2 ** S)) % 2 ** S
            t_lo, t_hi = -((bound + acc0) // 2 ** S), (bound - acc0) // 2 ** S
            if t_hi < t_lo:
                continue
            acc = acc0 + int(rng.integers(t_lo, t_hi + 1)) * 2 ** S
            assert (acc * M) % 2 ** S == 2 ** (S - 1)
            ties += 1
        else:
            acc = int(rng.integers(-bound, bound + 1))
        assert abs(acc) * M + 2 ** (S - 1) <= g.INT32_MAX
        negatives += acc < 0
        got = int(g.requant(np.array([acc], dtype=np.int32), M, S)[0])
        assert got == py_requant(acc, M, S), (acc, M, S)
        n += 1
    assert ties > 1000 and negatives > 3000      # the generator really covers both cases


# ---- input quantisation and bound --------------------------------------------------------------

def test_input_quant_all_pixels():
    p = np.arange(256, dtype=np.uint8)
    got = g.quantize_input(p)
    for v in range(256):
        assert int(got[v]) == (v * 254 + 255) // 510
    assert (int(got[0]), int(got[2]), int(got[255])) == (0, 1, 127)


def test_bound_hand_case():
    w_q = np.array([[127, 127, 127, -127], [-127, 127, -127, 127]], dtype=np.int8)
    b_q = np.array([1000, -1000], dtype=np.int32)
    assert g.compute_bound(w_q, b_q) == 65516


def test_find_ms_is_largest_s():
    rng = np.random.default_rng(7)
    for _ in range(1000):
        real = float(10 ** rng.uniform(-4, -1))
        bound = int(rng.integers(10 ** 3, 10 ** 7))
        M, S = g.find_ms(real, bound)
        assert M >= 1 and bound * M + 2 ** (S - 1) <= g.INT32_MAX
        assert M == int(np.round(real * 2 ** S))
        for s2 in range(S + 1, 32):               # every larger S must violate a condition
            m2 = int(np.round(real * 2 ** s2))
            assert not (m2 >= 1 and bound * m2 + 2 ** (s2 - 1) <= g.INT32_MAX), (real, bound, S, s2)


def test_find_ms_boundaries():
    """The random sweep never reaches S = 31 or the exact limit, so pin both by hand."""
    # S = 31 is allowed: M = round(1e-4 * 2**31) = 214748 and 1000 * 214748 + 2**30 <= 2**31 - 1
    assert g.find_ms(1e-4, 1000) == (214748, 31)
    # exact limit: bound * M + 2**(S-1) == 2**31 - 1 is accepted ...
    assert g.find_ms(0.5, g.INT32_MAX - 1) == (1, 1)
    # ... and one more makes it overflow, so nothing fits
    with pytest.raises(ValueError):
        g.find_ms(0.5, g.INT32_MAX)


def test_find_ms_raises_when_nothing_fits():
    with pytest.raises(ValueError):
        g.find_ms(1e-12, 10 ** 7)                 # M would round to 0 for every S


# ---- forward ----------------------------------------------------------------------------------

def test_forward_matches_python_int():
    rng = np.random.default_rng(99)
    quant = random_quant(rng)
    x = rng.integers(0, 128, size=(20, 784)).astype(np.int8)
    x = np.vstack([x, np.full((1, 784), 127, dtype=np.int8)])
    got = g.IntModel(quant).forward(x)
    assert got['logit'].dtype == np.int32 and got['logit'].shape == (21, 12)
    for n in range(x.shape[0]):
        ref = py_forward(quant, x[n])
        assert got['act1'][n].tolist() == ref['act1'], n
        assert got['act2'][n].tolist() == ref['act2'], n
        assert got['logit'][n].tolist() == ref['logit'], n
        assert int(got['label'][n]) == int(np.argmax(ref['logit'][:10])), n


def test_forward_worst_case_no_wrap():
    w_q = np.zeros((12, 784), dtype=np.int8)
    w_q[0, :] = 127
    b_q = np.zeros(12, dtype=np.int32)
    out = g.IntModel([{'w_q': w_q, 'b_q': b_q, 'M': None, 'S': None}]).forward(
        np.full((1, 784), 127, dtype=np.int8))
    assert int(out['logit'][0, 0]) == 12_645_136 == g.compute_bound(w_q, b_q)


def test_argmax_ignores_padding():
    """Phase 4 Review Focus 3: padded outputs 10 and 11 never win."""
    w_q = np.zeros((12, 784), dtype=np.int8)
    low = np.array([5, 3, 9, 1, 0, 2, 7, 4, 6, 8, 0, 0], dtype=np.int32)
    high = low.copy()
    high[10:], high[:10] = [1000, 2000], low[:10]        # padded rows above every real row
    x = np.zeros((1, 784), dtype=np.int8)
    for b_q in (low, high):
        out = g.IntModel([{'w_q': w_q, 'b_q': b_q, 'M': None, 'S': None}]).forward(x)
        assert int(out['label'][0]) == 2 and 0 <= int(out['label'][0]) <= 9


# ---- the committed export (decision D14) ------------------------------------------------------

def test_export_roundtrip():
    quant, manifest = g.load_export(EXPORT)
    ref = np.load(os.path.join(EXPORT, 'testvec_expected.npz'))
    x = g.read_mem_int8(os.path.join(EXPORT, 'testvec_input.mem')).reshape(-1, manifest['layer_sizes'][0])
    assert np.array_equal(x, ref['input'])
    out = g.IntModel(quant).forward(x)
    assert np.array_equal(out['act1'], ref['act1'])
    assert np.array_equal(out['act2'], ref['act2'])
    assert np.array_equal(out['logit'][:, :10], ref['logit'])
    assert not out['logit'][:, 10:].any()            # padded outputs are exactly 0
    assert np.array_equal(out['label'], ref['pred_label'])
    for fname, digest in manifest['sha256'].items():
        assert g.file_sha256(os.path.join(EXPORT, fname)) == digest, fname


def test_export_requant_matches_rule():
    quant, manifest = g.load_export(EXPORT)
    with open(os.path.join(EXPORT, 'requant.json')) as f:
        requant_json = json.load(f)
    for i in (0, 1):
        layer = manifest['layers'][f'fc{i + 1}']
        assert layer['bound'] == g.compute_bound(quant[i]['w_q'], quant[i]['b_q'])
        M, S = g.find_ms(layer['s_x'] * layer['s_w'] / layer['s_y'], layer['bound'])
        assert (M, S) == (requant_json[f'fc{i + 1}']['M'], requant_json[f'fc{i + 1}']['S'])
        assert (M, S) == (quant[i]['M'], quant[i]['S'])


# ---- cross-check against the C model ----------------------------------------------------------

def build_npu_ref():
    """Compile model/c/npu_ref.c into a shared library with the host gcc."""
    gcc = shutil.which('gcc') or shutil.which('cc')
    assert gcc, "gcc is needed to build model/c/npu_ref.c (the same compiler as `make -C model/c test`)"
    ext = '.dll' if sys.platform.startswith('win') else '.so'
    out_dir = os.path.join(PY_DIR, 'build')
    os.makedirs(out_dir, exist_ok=True)
    lib = os.path.join(out_dir, 'libnpu_ref' + ext)
    cmd = [gcc, '-std=c99', '-O1', '-shared', '-I', os.path.join(ROOT, 'model', 'c'),
           os.path.join(ROOT, 'model', 'c', 'npu_ref.c'), '-o', lib]
    if not sys.platform.startswith('win'):
        cmd.insert(1, '-fPIC')
    subprocess.run(cmd, check=True)
    return ctypes.CDLL(lib)


def test_golden_tile_matches_npu_ref():
    """W1 rows 0..3 against test images 0..3 (K = 784, quad layout of spec 6.2): the engine tile
    C[i][j] read as idx 4*i + j equals W1[i] . x[j]. The engine adds no bias."""
    quant, manifest = g.load_export(EXPORT)
    k = manifest['layer_sizes'][0]
    assert k == 784 and k % 4 == 0
    w = quant[0]['w_q'][:4].astype(np.int64)
    x = g.read_mem_int8(os.path.join(EXPORT, 'testvec_input.mem')).reshape(-1, k)[:4].astype(np.int64)
    want = w @ x.T                                       # [i][j]

    lib = build_npu_ref()
    lib.npu_ref_read.restype = ctypes.c_uint32
    lib.npu_ref_status.restype = ctypes.c_uint32
    for fn, n in ((lib.npu_ref_mem_write, 2), (lib.npu_ref_cmd, 4)):
        fn.argtypes = [ctypes.c_uint32] * n
    lib.npu_ref_read.argtypes = [ctypes.c_uint32]
    lib.npu_ref_reset()

    dtcm_base, w_addr, i_addr = 0x00010000, 0x00010000, 0x00012000

    def put(rows, addr):
        """quad s, word i of the block = rows[i][4s .. 4s+3], lane t in bits [8t+7:8t] (spec 6.2)."""
        for s in range(k // 4):
            for i in range(4):
                word = 0
                for t in range(4):
                    word |= (int(rows[i][4 * s + t]) & 0xFF) << (8 * t)
                lib.npu_ref_mem_write((addr - dtcm_base) // 4 + 4 * s + i, word)

    put(w, w_addr)
    put(x, i_addr)
    lib.npu_ref_cmd(0, w_addr, k, 0)                     # LDW
    lib.npu_ref_cmd(1, i_addr, k, 0)                     # LDI
    lib.npu_ref_cmd(2, 0, k, 1)                          # MAC, clr = 1
    assert lib.npu_ref_status() & 0xF00 == 0             # no error bit
    for i in range(4):
        for j in range(4):
            got = np.uint32(lib.npu_ref_read(4 * i + j)).astype(np.int32)
            assert int(got) == int(want[i][j]), (i, j)
