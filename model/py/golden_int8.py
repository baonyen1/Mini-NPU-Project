"""Integer golden model of the Mini-NPU MLP (spec 9.3 and 10.2, decision D15).

Pure numpy, no torch: the notebook, `pack_weights.py` and the tests import it. The integer math
here is the oracle that the C model (`npu_ref`) and the RTL scoreboard are compared with, so it
has its own unit tests (model/py/tests/test_golden_int8.py) and is only used once they pass.

Arithmetic rules (spec 4.1, 4.4, 4.5):
  quantize_input : x0 = (p * 254 + 255) // 510            int8 in 0..127
  layer          : acc = x @ W.T + b                       int32, exact (bound <= 2**31 - 1)
  requant        : y = clamp((acc * M + 2**(S-1)) >> S, 0, 127)   arithmetic shift, round half up
  last layer     : logit = acc, no requant; label = argmax over the first 10 of the padded outputs
"""
import hashlib
import json
import os

import numpy as np

INT32_MAX = 2**31 - 1


def quantize_input(p):
    """Spec 4.1: x0 = (p * 254 + 255) // 510, result in 0..127. `p` holds pixel values 0..255."""
    return ((p.astype(np.int32) * 254 + 255) // 510).astype(np.int8)


def compute_bound(w_q, b_q):
    """Spec 4.5: B_j = sum_i |w_q[j][i]| * 127 + |b_q[j]|, bound = max_j B_j."""
    abs_sum = np.sum(np.abs(w_q.astype(np.int64)), axis=1) * 127
    total = abs_sum + np.abs(b_q.astype(np.int64))
    return int(np.max(total))


def find_ms(real, bound):
    """Spec 4.4: the largest S in 1..31 with M = round(real * 2**S) >= 1 and
    bound * M + 2**(S-1) <= 2**31 - 1. Raises if no S fits."""
    for S in range(31, 0, -1):
        M = int(np.round(real * (2 ** S)))
        if M >= 1 and bound * M + (2 ** (S - 1)) <= INT32_MAX:
            return M, S
    raise ValueError(
        f"find_ms: no S in 1..31 gives M >= 1 and bound*M + 2^(S-1) <= 2^31-1 "
        f"(real={real}, bound={bound}); the layer scale or the weights are out of range"
    )


def requant(acc, M, S):
    """Spec 4.4: y = clamp((acc * M + 2**(S-1)) >> S, 0, 127), int8.
    The product is formed in int32; `find_ms` guarantees it cannot overflow for |acc| <= bound."""
    scaled = acc.astype(np.int32) * np.int32(M) + np.int32(1 << (S - 1))
    shifted = np.right_shift(scaled, S)
    return np.clip(shifted, 0, 127).astype(np.int8)


class IntModel:
    """Integer inference of the whole MLP.

    quant[i] = {'w_q': int8 (out, in), 'b_q': int32 (out,), 'M': int, 'S': int}.
    M and S are None on the last layer. The layer count is len(quant).
    """

    def __init__(self, quant):
        self.quant = quant
        self.n_layers = len(quant)

    def forward(self, x_int):
        """x_int: (N, in) int8. Returns {'act1': ..., 'act2': ..., 'logit': int32 (N, out incl.
        padded rows), 'label': argmax over logit[:, :10]}."""
        x = x_int.astype(np.int32)
        result = {}
        for i in range(self.n_layers):
            w_q = self.quant[i]['w_q'].astype(np.int32)
            b_q = self.quant[i]['b_q']
            acc = x @ w_q.T + b_q
            if i < self.n_layers - 1:
                y = requant(acc, self.quant[i]['M'], self.quant[i]['S'])
                result[f'act{i + 1}'] = y
                x = y.astype(np.int32)
            else:
                result['logit'] = acc
        result['label'] = np.argmax(result['logit'][:, :10], axis=1)
        return result


# ---- export reading ---------------------------------------------------------------------------

def read_mem_int8(path):
    """One int8 per line as 2 hex digits (two's complement) -> 1-D int8 array."""
    with open(path) as f:
        vals = [int(line, 16) for line in f.read().split()]
    return np.array(vals, dtype=np.uint8).view(np.int8)


def read_mem_int32(path):
    """One int32 per line as 8 hex digits (two's complement) -> 1-D int32 array."""
    with open(path) as f:
        vals = [int(line, 16) for line in f.read().split()]
    return np.array(vals, dtype=np.uint32).view(np.int32)


def load_export(export_dir):
    """Read the committed export (decision D14) back into `quant` and `manifest`.

    `.mem` files are row-major [out][in]; shapes come from manifest['layer_sizes'] and
    manifest['fc3_pad'] (the last layer is padded with zero rows from 10 to fc3_pad outputs).
    Returns (quant, manifest) with quant as accepted by IntModel.
    """
    with open(os.path.join(export_dir, 'manifest.json')) as f:
        manifest = json.load(f)
    with open(os.path.join(export_dir, 'requant.json')) as f:
        requant_json = json.load(f)

    sizes = manifest['layer_sizes']
    n_layers = len(sizes) - 1
    quant = []
    for i in range(n_layers):
        last = i == n_layers - 1
        out_size = manifest['fc3_pad'] if last else sizes[i + 1]
        in_size = sizes[i]
        w_q = read_mem_int8(os.path.join(export_dir, f'fc{i + 1}_weight.mem')).reshape(out_size, in_size)
        b_q = read_mem_int32(os.path.join(export_dir, f'fc{i + 1}_bias.mem'))
        if b_q.shape != (out_size,):
            raise ValueError(f"fc{i + 1}_bias.mem has {b_q.shape[0]} entries, expected {out_size}")
        if last:
            M = S = None
        else:
            M, S = requant_json[f'fc{i + 1}']['M'], requant_json[f'fc{i + 1}']['S']
        quant.append({'w_q': w_q, 'b_q': b_q, 'M': M, 'S': S})
    return quant, manifest


def file_sha256(path):
    """SHA-256 of a file, as recorded in manifest.json."""
    with open(path, 'rb') as f:
        return hashlib.sha256(f.read()).hexdigest()
