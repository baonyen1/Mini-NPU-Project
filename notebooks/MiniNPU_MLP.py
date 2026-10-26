import marimo

__generated_with = "0.25.0"
app = marimo.App(width="full", auto_download=["html"])


@app.cell
def _(cfg, mo):
    mo.md(f"""
    # MLP MNIST 3 lớp lượng tử hóa int8 cho Mini-NPU

    **Ngày:** 2026-09-28 | **Trạng thái:** đã duyệt (2026-10-26)
    **Dự án:** Đồ án 2 – Mini-NPU RISC-V (cấu hình D0/D1)

    ## Kiến trúc mô hình

    | Lớp | Kích thước | Hoạt động |
    |-----|-----------|-----------|
    | FC1 | {cfg.layer_sizes[0]} → {cfg.layer_sizes[1]} | ReLU, requant về int8 |
    | FC2 | {cfg.layer_sizes[1]} → {cfg.layer_sizes[2]} | ReLU, requant về int8 |
    | FC3 | {cfg.layer_sizes[2]} → {cfg.layer_sizes[3]} (đệm {cfg.fc3_pad}) | Ra logit int32, không requant |

    **Mục tiêu:** Tạo (a) MLP int8 phân loại MNIST, (b) file xuất nạp vào TCM Mini-NPU, (c) golden model số nguyên cho UVM scoreboard.

    **Tiêu chí thành công:** Tính đúng bit quan trọng hơn độ chính xác. Mô hình tham chiếu số nguyên tái lập bit-chính-xác.
    """)
    return


@app.cell
def _():
    import marimo as mo
    import numpy as np
    import json
    import hashlib
    import os
    import sys
    from dataclasses import dataclass, field
    from typing import Optional

    try:
        import torch
        import torch.nn as nn
        import torch.nn.functional as F
        from torch.utils.data import DataLoader, Subset
        import torchvision
        import torchvision.transforms as transforms
        TORCH_AVAILABLE = True
    except ImportError:
        TORCH_AVAILABLE = False
    return (
        DataLoader,
        F,
        Subset,
        TORCH_AVAILABLE,
        dataclass,
        field,
        hashlib,
        json,
        mo,
        nn,
        np,
        os,
        sys,
        torch,
        torchvision,
        transforms,
    )


@app.cell
def _(dataclass, field, mo, os):
    # The export is committed (decision D14): model/py/export, resolved from this notebook's folder
    # so it does not depend on the kernel's working directory.
    _nb_dir = mo.notebook_dir() or os.getcwd()
    _export_dir = os.path.normpath(os.path.join(str(_nb_dir), "..", "model", "py", "export"))

    @dataclass
    class Config:
        layer_sizes: list = field(default_factory=lambda: [784, 64, 32, 10])
        seed: int = 0
        epochs: int = 15
        batch_size: int = 128
        lr: float = 1e-3
        calib_size: int = 10000
        percentile: float = 99.99
        n_test_vectors: int = 100
        n_per_digit: int = 10
        data_dir: str = "./data"
        export_dir: str = _export_dir
        fc3_pad: int = 12

    cfg = Config()
    cfg
    return (cfg,)


@app.cell
def _(mo):
    mo.md(r"""
    ## Đặc tả suy luận số nguyên (mục 4)

    ### Input (4.1)
    $$x_0 = (p \times 254 + 255) // 510$$
    kết quả trong 0..127, zero-point 0.

    ### Trọng số & bias (4.2)
    - $s_w = \max|W| / 127$, $w_q = \text{clip}(\text{round}(W/s_w), -127, 127)$
    - $b_q = \text{round}(b / (s_x \times s_w))$, không dùng $-128$

    ### Tích lũy (4.3)
    $$\text{acc}[j] = \sum_i x[i] \times w[j][i] + b_q[j] \quad (\text{int32})$$

    ### Requant sau FC1/FC2 (4.4)
    $$y[j] = \text{clamp}\left(\left\lfloor \frac{\text{acc}[j] \times M + 2^{S-1}}{2^S} \right\rfloor, 0, 127\right)$$
    $M$ nguyên dương, $S \in [1,31]$, mỗi lớp có cặp $(M,S)$ riêng. Phép chia $2^S$ là dịch phải số học (floor).

    ### Cận không tràn (4.5)
    $$B_j = \sum_i |w_q[j][i]| \times 127 + |b_q[j]|, \quad \text{bound} = \max_j B_j$$
    """)
    return


@app.cell
def _(mo, np, os, sys):
    # The integer golden math lives in model/py/golden_int8.py (decision D15, plan Task 2b): one
    # definition with its own unit tests (python -m pytest model/py/tests -v). Only the float-side
    # quantisation, which needs the trained weights, stays here.
    _py_dir = os.path.normpath(os.path.join(str(mo.notebook_dir() or os.getcwd()), "..", "model", "py"))
    if _py_dir not in sys.path:
        sys.path.insert(0, _py_dir)
    from golden_int8 import (
        INT32_MAX,
        IntModel,
        compute_bound,
        find_ms,
        load_export,
        quantize_input,
        read_mem_int8,
        requant,
    )

    def quantize_weight(W):
        """Mục 4.2: quantize weight symmetric int8, không -128."""
        s_w = np.max(np.abs(W)) / 127.0
        if s_w == 0:
            s_w = 1.0
        w_q = np.clip(np.round(W / s_w), -127, 127).astype(np.int8)
        return w_q, float(s_w)

    def quantize_bias(b, s_x, s_w):
        """Mục 4.2: b_q = round(b / (s_x * s_w))."""
        return np.round(b / (s_x * s_w)).astype(np.int32)

    return (
        INT32_MAX,
        IntModel,
        compute_bound,
        find_ms,
        load_export,
        quantize_bias,
        quantize_input,
        quantize_weight,
        read_mem_int8,
        requant,
    )


@app.cell
def _(DataLoader, F, TORCH_AVAILABLE, nn, np, torch, torchvision, transforms):
    if TORCH_AVAILABLE:
        class MLP(nn.Module):
            def __init__(self, layer_sizes):
                super().__init__()
                self.layers = nn.ModuleList([
                    nn.Linear(layer_sizes[i], layer_sizes[i+1], bias=True)
                    for i in range(len(layer_sizes) - 1)
                ])

            def forward(self, x):
                for i, layer in enumerate(self.layers):
                    x = layer(x)
                    if i < len(self.layers) - 1:
                        x = F.relu(x)
                return x

    def train_model(config):
        """Huấn luyện MLP float trên MNIST."""
        if not TORCH_AVAILABLE:
            raise RuntimeError("PyTorch không có sẵn")
        torch.manual_seed(config.seed)
        np.random.seed(config.seed)
        transform = transforms.Compose([transforms.ToTensor()])
        train_set = torchvision.datasets.MNIST(
            config.data_dir, train=True, download=True, transform=transform
        )
        train_loader = DataLoader(
            train_set, batch_size=config.batch_size, shuffle=True,
            generator=torch.Generator().manual_seed(config.seed)
        )
        model = MLP(config.layer_sizes)
        optimizer = torch.optim.Adam(model.parameters(), lr=config.lr)
        for epoch in range(config.epochs):
            model.train()
            for X, y in train_loader:
                X = X.view(X.size(0), -1)
                logits = model(X)
                loss = F.cross_entropy(logits, y)
                optimizer.zero_grad()
                loss.backward()
                optimizer.step()
        model.eval()
        return model, train_set

    def evaluate_float(model, test_set):
        """Đánh giá độ chính xác float."""
        model.eval()
        correct = 0
        total = 0
        with torch.no_grad():
            loader = DataLoader(test_set, batch_size=256, shuffle=False)
            for X, y in loader:
                X = X.view(X.size(0), -1)
                logits = model(X)
                pred = logits.argmax(dim=1)
                correct += (pred == y).sum().item()
                total += y.size(0)
        return correct / total

    return evaluate_float, train_model


@app.cell
def _(
    DataLoader,
    F,
    INT32_MAX,
    Subset,
    compute_bound,
    find_ms,
    np,
    quantize_bias,
    quantize_weight,
    torch,
):
    def quantize_model(model, config, train_set):
        """Post-training quantization theo mục 4."""
        torch.manual_seed(config.seed)
        calib_indices = torch.randperm(
            len(train_set), generator=torch.Generator().manual_seed(config.seed)
        )[:config.calib_size]
        calib_subset = Subset(train_set, calib_indices)
        calib_loader = DataLoader(calib_subset, batch_size=config.batch_size, shuffle=False)
        model.eval()
        n_layers = len(model.layers)
        activations = {i: [] for i in range(n_layers - 1)}
        with torch.no_grad():
            for X, _ in calib_loader:
                X = X.view(X.size(0), -1)
                h = X
                for i, layer in enumerate(model.layers):
                    h = layer(h)
                    if i < n_layers - 1:
                        h = F.relu(h)
                        activations[i].append(h.cpu().numpy())
        s_y = {}
        for i in range(n_layers - 1):
            act = np.concatenate(activations[i], axis=0)
            p = np.percentile(act, config.percentile)
            s_y[i] = float(p) / 127.0
        s_in = 1.0 / 127.0
        input_scales = [s_in] + [s_y[i] for i in range(n_layers - 1)]
        quant = {}
        for i, layer in enumerate(model.layers):
            W = layer.weight.detach().cpu().numpy()
            b = layer.bias.detach().cpu().numpy()
            w_q, s_w = quantize_weight(W)
            s_x = input_scales[i]
            b_q = quantize_bias(b, s_x, s_w)
            bound = compute_bound(w_q, b_q)
            if bound > INT32_MAX:
                raise RuntimeError(f"Tràn! Layer {i} bound={bound} > INT32_MAX")
            if i < n_layers - 1:
                real = s_x * s_w / s_y[i]
                M, S = find_ms(real, bound)
                if M < 64:
                    print(f"⚠ FC{i+1} M={M} < 64, có thể mất độ chính xác")
            else:
                M, S = None, None
            quant[i] = {
                'w_q': w_q, 'b_q': b_q, 's_w': s_w, 's_x': s_x,
                's_y': s_y.get(i), 'M': M, 'S': S, 'bound': bound,
            }
            print(f"FC{i+1}: bound={bound:>12,}  M={M}  S={S}  s_w={s_w:.6f}  s_y={s_y.get(i)}")
        return quant

    return (quantize_model,)


@app.cell
def _(TORCH_AVAILABLE, np):
    def select_test_vectors(test_set, config):
        """Chọn 100 ảnh (10 mỗi chữ số, 10 ảnh đầu của từng chữ số)."""
        if not TORCH_AVAILABLE:
            raise RuntimeError("PyTorch không có sẵn")
        labels_np = np.array(test_set.targets)
        selected = []
        for digit in range(10):
            indices = np.where(labels_np == digit)[0][:config.n_per_digit]
            selected.extend(indices.tolist())
        images = []
        true_labels = []
        for idx in selected:
            img, label = test_set[idx]
            images.append(img.view(-1).numpy())
            true_labels.append(label)
        return np.stack(images), np.array(true_labels), selected

    return (select_test_vectors,)


@app.cell
def _(TORCH_AVAILABLE, hashlib, json, np, os, sys, torch):
    def int8_to_hex(val):
        """int8 → 2 hex digits (two's complement)"""
        return format(int(val) & 0xFF, '02x')

    def int32_to_hex(val):
        """int32 → 8 hex digits (two's complement)"""
        return format(int(val) & 0xFFFFFFFF, '08x')

    def hex_to_int8(s):
        """hex → int8 signed"""
        val = int(s, 16)
        return val - 256 if val >= 128 else val

    def hex_to_int32(s):
        """hex → int32 signed"""
        val = int(s, 16)
        return val - (1 << 32) if val >= (1 << 31) else val

    def export_files(quant, test_input, test_expected, float_acc, int_acc, config):
        """Xuất tất cả file theo mục 6."""
        os.makedirs(config.export_dir, exist_ok=True)
        n_layers = len(config.layer_sizes) - 1

        # 1. Weight và bias files
        for i in range(n_layers):
            w_q = quant[i]['w_q'].copy()
            b_q = quant[i]['b_q'].copy()

            # Đệm  từ 10 lên 12
            if i == n_layers - 1 and w_q.shape[0] < config.fc3_pad:
                w_q = np.vstack([w_q, np.zeros((config.fc3_pad - w_q.shape[0], w_q.shape[1]), dtype=np.int8)])
                b_q = np.concatenate([b_q, np.zeros(config.fc3_pad - len(b_q), dtype=np.int32)])

            with open(os.path.join(config.export_dir, f'fc{i+1}_weight.mem'), 'w') as f:
                for row in w_q:
                    for val in row:
                        f.write(int8_to_hex(val) + '\n')

            with open(os.path.join(config.export_dir, f'fc{i+1}_bias.mem'), 'w') as f:
                for val in b_q:
                    f.write(int32_to_hex(val) + '\n')

        # 2. requant.json
        requant_data = {}
        for i in range(n_layers - 1):
            requant_data[f'fc{i+1}'] = {'M': quant[i]['M'], 'S': quant[i]['S']}
        with open(os.path.join(config.export_dir, 'requant.json'), 'w') as f:
            json.dump(requant_data, f, indent=2)

        # 3. testvec_input.mem
        with open(os.path.join(config.export_dir, 'testvec_input.mem'), 'w') as f:
            for img in test_input:
                for val in img:
                    f.write(int8_to_hex(val) + '\n')

        # 4. testvec_expected.npz
        np.savez(
            os.path.join(config.export_dir, 'testvec_expected.npz'),
            input=test_input.astype(np.int8),
            act1=test_expected['act1'].astype(np.int8),
            act2=test_expected['act2'].astype(np.int8),
            logit=test_expected['logit'].astype(np.int32),
            pred_label=test_expected['label'].astype(np.int64),
            true_label=test_expected['true_label'].astype(np.int64),
        )

        # 5. manifest.json
        files_to_hash = []
        for i in range(n_layers):
            files_to_hash.append(f'fc{i+1}_weight.mem')
            files_to_hash.append(f'fc{i+1}_bias.mem')
        files_to_hash.extend(['requant.json', 'testvec_input.mem', 'testvec_expected.npz'])

        sha256s = {}
        for fname in files_to_hash:
            path = os.path.join(config.export_dir, fname)
            with open(path, 'rb') as f:
                sha256s[fname] = hashlib.sha256(f.read()).hexdigest()

        manifest = {
            'seed': config.seed,
            'python_version': sys.version,
            'torch_version': torch.__version__ if TORCH_AVAILABLE else None,
            'numpy_version': np.__version__,
            'layer_sizes': config.layer_sizes,
            'fc3_pad': config.fc3_pad,
            's_in': 1.0 / 127.0,
            'layers': {},
            'float_accuracy': float_acc,
            'int8_accuracy': int_acc,
            'sha256': sha256s,
        }
        for i in range(n_layers):
            manifest['layers'][f'fc{i+1}'] = {
                's_w': float(quant[i]['s_w']),
                's_x': float(quant[i]['s_x']),
                's_y': quant[i]['s_y'],
                'M': quant[i]['M'],
                'S': quant[i]['S'],
                'bound': int(quant[i]['bound']),
            }

        with open(os.path.join(config.export_dir, 'manifest.json'), 'w') as f:
            json.dump(manifest, f, indent=2)

        print(f"✓ Đã xuất {len(files_to_hash)} file vào {config.export_dir}/")
        return manifest

    return export_files, hex_to_int32, hex_to_int8, int32_to_hex, int8_to_hex


@app.cell
def _(
    DataLoader,
    IntModel,
    TORCH_AVAILABLE,
    evaluate_float,
    export_files,
    np,
    quantize_input,
    quantize_model,
    select_test_vectors,
    torch,
    torchvision,
    train_model,
    transforms,
):
    def run_pipeline(config):
        """Chạy trọn pipeline: train → quantize → int_model → export."""
        if not TORCH_AVAILABLE:
            print("⚠ PyTorch không có sẵn. Chỉ chạy được test với dữ liệu tổng hợp.")
            return None

        # Train
        print("=== Bước 1: Huấn luyện ===")
        model, train_set = train_model(config)

        # Load test set
        transform = transforms.Compose([transforms.ToTensor()])
        test_set = torchvision.datasets.MNIST(
            config.data_dir, train=False, download=True, transform=transform
        )

        # Evaluate float
        float_acc = evaluate_float(model, test_set)
        print(f"Độ chính xác float: {float_acc*100:.2f}%")

        # Quantize
        print("\n=== Bước 2: Lượng tử hóa ===")
        quant = quantize_model(model, config, train_set)

        # Integer model
        print("\n=== Bước 3: Mô hình số nguyên ===")
        int_model = IntModel(quant)

        # Test vectors
        print("\n=== Bước 4: Chọn test vector ===")
        test_images_f, test_true_labels, _ = select_test_vectors(test_set, config)
        test_input = quantize_input(test_images_f * 255)

        # Run int inference
        expected = int_model.forward(test_input)
        expected['true_label'] = test_true_labels

        # Int8 accuracy on test vectors
        int_vec_acc = np.mean(expected['label'] == test_true_labels)
        print(f"Độ chính xác int8 trên test vector: {int_vec_acc*100:.2f}%")

        # Full int8 accuracy + label match rate
        test_loader = DataLoader(test_set, batch_size=256, shuffle=False)
        int_correct = 0
        int_total = 0
        label_match = 0
        with torch.no_grad():
            for X, y in test_loader:
                X_flat = X.view(X.size(0), -1)
                float_logits = model(X_flat)
                float_pred = float_logits.argmax(dim=1).numpy()

                X_np = X_flat.numpy() * 255
                x_int = quantize_input(X_np)
                result = int_model.forward(x_int)
                int_pred = result['label']

                int_correct += np.sum(int_pred == y.numpy())
                int_total += y.size(0)
                label_match += np.sum(int_pred == float_pred)
        int_acc = int_correct / int_total
        match_rate = label_match / int_total
        print(f"Độ chính xác int8 toàn tập test: {int_acc*100:.2f}%")
        print(f"Tỉ lệ khớp nhãn float↔int8: {match_rate*100:.2f}%")

        diff = (float_acc - int_acc) * 100
        if diff > 1.0:
            print(f"⚠ Cảnh báo: chênh lệch {diff:.2f} điểm phần trăm > 1")
        else:
            print(f"Chênh lệch: {diff:.2f} điểm phần trăm ✓")

        # Export
        print("\n=== Bước 5: Xuất file ===")
        manifest = export_files(quant, test_input, expected, float_acc, int_acc, config)

        print("\n=== Hoàn thành ===")
        return {
            'model': model,
            'quant': quant,
            'int_model': int_model,
            'manifest': manifest,
            'float_acc': float_acc,
            'int_acc': int_acc,
            'match_rate': match_rate,
            'test_input': test_input,
            'expected': expected,
        }

    return (run_pipeline,)


@app.cell
def _(mo):
    mo.md("""
    ## Chạy pipeline
    Pipeline: huấn luyện → lượng tử hóa → mô hình số nguyên → xuất file.
    Yêu cầu PyTorch và kết nối Internet (tải MNIST).
    """)
    return


@app.cell
def _(mo):
    run_btn = mo.ui.run_button(label="Chạy pipeline", kind="success")
    run_btn
    return (run_btn,)


@app.cell
def _(cfg, mo, run_btn, run_pipeline):
    mo.stop(not run_btn.value, mo.md("Nhấn **Chạy pipeline** để bắt đầu."))
    results = run_pipeline(cfg)
    return (results,)


@app.cell
def _(cfg, mo):
    def memory_breakdown(config):
        sizes = config.layer_sizes
        fc3_out = config.fc3_pad
        weights = [
            sizes[0] * sizes[1],
            sizes[1] * sizes[2],
            sizes[2] * fc3_out,
        ]
        biases = [
            sizes[1] * 4,
            sizes[2] * 4,
            fc3_out * 4,
        ]
        total_w = sum(weights)
        total_b = sum(biases)
        input_bytes = sizes[0]
        act_bytes = sizes[1] + sizes[2]
        logit_bytes = fc3_out * 4
        total = total_w + total_b + input_bytes + act_bytes + logit_bytes
        return mo.md(f"""
    ## Bố cục bộ nhớ (mục 3)

    | Thành phần | Byte |
    |------------|------|
    | FC1 weight ({sizes[0]}×{sizes[1]}) | {weights[0]:,} |
    | FC2 weight ({sizes[1]}×{sizes[2]}) | {weights[1]:,} |
    | FC3 weight ({sizes[2]}×{fc3_out}) | {weights[2]:,} |
    | **Tổng trọng số int8** | **{total_w:,}** |
    | FC1 bias ({sizes[1]}×4) | {biases[0]:,} |
    | FC2 bias ({sizes[2]}×4) | {biases[1]:,} |
    | FC3 bias ({fc3_out}×4) | {biases[2]:,} |
    | **Tổng bias int32** | **{total_b:,}** |
    | Input ({sizes[0]}) | {input_bytes:,} |
    | Activation ({sizes[1]}+{sizes[2]}) | {act_bytes:,} |
    | Logit ({fc3_out}×4) | {logit_bytes:,} |
    | **Tổng cộng** | **{total:,}** ({total/1024:.1f} KiB) |
    """)

    memory_breakdown(cfg)
    return


@app.cell
def _(mo):
    mo.md("""
    ## Kiểm thử (mục 7)
    Các test đơn vị chạy với dữ liệu tổng hợp, chỉ cần NumPy.
    """)
    return


@app.cell
def _(hex_to_int32, hex_to_int8, int32_to_hex, int8_to_hex, np):
    def test_matmul_int8():
        """Test: nhân ma trận int8 × int8 → int32 khớp vòng lặp viết tay."""
        x = np.array([[1, 2, -3, 4]], dtype=np.int8)
        w = np.array([[1, -1, 2, 3],
                      [2, 1, -1, 0]], dtype=np.int8)
        b = np.array([5, -3], dtype=np.int32)
        acc = x.astype(np.int32) @ w.astype(np.int32).T + b
        # Tính tay: acc[0] = 1-2-6+12+5 = 10, acc[1] = 2+2+3+0-3 = 4
        expected = np.array([[10, 4]], dtype=np.int32)
        assert np.array_equal(acc, expected), f"{acc} != {expected}"
        print("✓ test_matmul_int8")

    def test_padding():
        """Test: đệm 10→12 không đổi argmax."""
        logits = np.array([[5, 3, 8, 1, 2, 6, 4, 7, 0, 9]], dtype=np.int32)
        padded = np.hstack([logits, np.zeros((1, 2), dtype=np.int32)])
        label = np.argmax(padded[:, :10], axis=1)
        assert label[0] == 9, f"Expected 9, got {label[0]}"
        print("✓ test_padding")

    def test_hex_conversion():
        """Test: chuyển đổi hex."""
        assert int8_to_hex(127) == '7f'
        assert int8_to_hex(-1) == 'ff'
        assert int8_to_hex(-127) == '81'
        assert int32_to_hex(1) == '00000001'
        assert int32_to_hex(-1) == 'ffffffff'
        assert hex_to_int8('7f') == 127
        assert hex_to_int8('ff') == -1
        assert hex_to_int8('81') == -127
        assert hex_to_int32('00000001') == 1
        assert hex_to_int32('ffffffff') == -1
        print("✓ test_hex_conversion")

    test_matmul_int8()
    test_padding()
    test_hex_conversion()
    print("\n✓ Tất cả test đơn vị passed!")
    return


@app.cell
def _(mo):
    mo.md("""
    ### Round-trip test (mục 7)
    Đọc lại toàn bộ file xuất, tính lại logit, phải khớp bit-chính-xác với `testvec_expected.npz`.
    SHA256 phải khớp `manifest.json`.
    Chỉ chạy sau khi pipeline hoàn thành.
    """)
    return


@app.cell
def _(IntModel, cfg, hashlib, json, load_export, mo, np, os, read_mem_int8, results):
    def test_roundtrip(config):
        """Test: đọc lại file xuất, tính lại logit, khớp bit-chính-xác."""
        export_dir = config.export_dir
        quant_loaded, _ = load_export(export_dir)

        # Đọc input
        test_input = read_mem_int8(os.path.join(export_dir, 'testvec_input.mem')).reshape(
            config.n_test_vectors, config.layer_sizes[0])

        # Đọc expected
        expected = np.load(os.path.join(export_dir, 'testvec_expected.npz'))

        # Chạy int model với dữ liệu đọc lại
        int_model_loaded = IntModel(quant_loaded)
        result = int_model_loaded.forward(test_input)

        # Kiểm tra bit-chính-xác
        assert np.array_equal(result['act1'], expected['act1']), "act1 không khớp!"
        assert np.array_equal(result['act2'], expected['act2']), "act2 không khớp!"
        assert np.array_equal(result['logit'][:, :10], expected['logit'][:, :10]), "logit không khớp!"
        assert np.array_equal(result['label'], expected['pred_label']), "label không khớp!"
        print("✓ Logit, activation, label khớp bit-chính-xác")

        # Kiểm tra sha256 khớp manifest
        with open(os.path.join(export_dir, 'manifest.json')) as f:
            manifest = json.load(f)
        for fname, expected_hash in manifest['sha256'].items():
            path = os.path.join(export_dir, fname)
            with open(path, 'rb') as f:
                actual_hash = hashlib.sha256(f.read()).hexdigest()
            assert actual_hash == expected_hash, f"SHA256 không khớp cho {fname}"
        print("✓ Tất cả SHA256 khớp manifest.json")
        print("\n✓ test_roundtrip passed!")

    mo.stop(results is None, mo.md("⏭ Round-trip test: bỏ qua (pipeline chưa chạy hoặc PyTorch không có sẵn)"))
    test_roundtrip(cfg)
    return


@app.cell
def _(mo):
    mo.md(r"""
    ### Tái lập (mục 7)
    Chạy pipeline hai lần cùng seed, mọi checksum SHA256 phải giống hệt.
    Chỉ chạy sau khi pipeline đầu tiên đã hoàn thành.
    """)
    return


@app.cell
def _(cfg, json, mo, os, results, run_pipeline):
    def test_reproducibility(config):
        """Test: chạy pipeline hai lần cùng seed, checksum phải giống hệt."""
        # Lưu checksum từ lần chạy đầu
        first_manifest_path = os.path.join(config.export_dir, 'manifest.json')
        with open(first_manifest_path) as f:
            first_manifest = json.load(f)
        first_sha = first_manifest['sha256']

        # Chạy lại pipeline
        print("=== Chạy lại pipeline (lần 2) ===")
        results_2 = run_pipeline(config)
        if results_2 is None:
            print("⏭ Bỏ qua: PyTorch không có sẵn")
            return

        # Đọc manifest lần 2
        with open(first_manifest_path) as f:
            second_manifest = json.load(f)
        second_sha = second_manifest['sha256']

        # So sánh checksum
        all_match = True
        for fname, hash_1 in first_sha.items():
            hash_2 = second_sha.get(fname)
            if hash_2 is None:
                print(f"✗ {fname}: thiếu ở lần 2")
                all_match = False
            elif hash_1 != hash_2:
                print(f"✗ {fname}: checksum khác nhau")
                all_match = False
        if all_match:
            print(f"✓ Tất cả {len(first_sha)} file có checksum giống hệt giữa 2 lần chạy")
            print("\n✓ test_reproducibility passed!")
        else:
            raise AssertionError("Reproducibility test thất bại: checksum không khớp")

    mo.stop(results is None, mo.md("⏭ Tái lập test: bỏ qua (pipeline chưa chạy hoặc PyTorch không có sẵn)"))
    test_reproducibility(cfg)
    return


@app.cell
def _(mo):
    mo.md("""
    ## Test tương tác (mục 8)
    Load model từ file xuất, chọn test vector bằng slider, xem kết quả suy luận.
    """)
    return


@app.cell
def _(IntModel, cfg, load_export, mo, np, os, read_mem_int8, results):
    def load_model_from_files(config):
        """Load toàn bộ model từ file xuất trong export_dir."""
        export_dir = config.export_dir
        quant_loaded, manifest = load_export(export_dir)
        test_input = read_mem_int8(os.path.join(export_dir, 'testvec_input.mem')).reshape(
            config.n_test_vectors, config.layer_sizes[0]
        )
        expected = np.load(os.path.join(export_dir, 'testvec_expected.npz'))
        return IntModel(quant_loaded), test_input, expected, manifest

    mo.stop(results is None, mo.md("⏭ Load model: bỏ qua (pipeline chưa chạy hoặc PyTorch không có sẵn)"))
    model_loaded, test_inputs, test_expected, manifest_loaded = load_model_from_files(cfg)
    print(f"✓ Đã load model từ {cfg.export_dir}/")
    print(f"  FC1 weight shape: {model_loaded.quant[0]['w_q'].shape}")
    print(f"  FC2 weight shape: {model_loaded.quant[1]['w_q'].shape}")
    print(f"  FC3 weight shape: {model_loaded.quant[2]['w_q'].shape}")
    print(f"  Test vectors: {test_inputs.shape[0]} ảnh")
    print(f"  Float accuracy: {manifest_loaded['float_accuracy']*100:.2f}%")
    print(f"  Int8 accuracy:  {manifest_loaded['int8_accuracy']*100:.2f}%")
    return model_loaded, test_expected, test_inputs


@app.cell
def _(mo, test_inputs):
    # UI chọn test vector
    vec_selector = mo.ui.slider(0, test_inputs.shape[0] - 1, step=1, value=0, label="Chọn test vector (0-99)")
    show_detail = mo.ui.checkbox(label="Hiện chi tiết activation & logit", value=True)

    mo.vstack([vec_selector, show_detail])
    return show_detail, vec_selector


@app.cell
def _(
    mo,
    model_loaded,
    np,
    show_detail,
    test_expected,
    test_inputs,
    vec_selector,
):
    import polars as pl
    import altair as alt

    # Lấy test vector theo slider
    _idx = vec_selector.value
    _x_int = test_inputs[_idx:_idx+1]
    _result = model_loaded.forward(_x_int)
    _true_label = int(test_expected['true_label'][_idx])
    _pred_label = int(_result['label'][0])

    # Hiển thị ảnh 28x28
    _img = _x_int.reshape(28, 28).astype(np.float32)

    # Logit chi tiết (10 chữ số)
    _logits = _result['logit'][0, :10]
    _digit_labels = [str(i) for i in range(10)]
    _bar_data = pl.DataFrame({
        'digit': _digit_labels,
        'logit': _logits.tolist(),
    })
    _chart = alt.Chart(_bar_data).mark_bar().encode(
        x=alt.X('digit:N', title='Chữ số'),
        y=alt.Y('logit:Q', title='Logit int32'),
        color=alt.condition(
            alt.datum.digit == str(_pred_label),
            alt.value('#2ca02c'),
            alt.value('#cccccc'),
        ),
        tooltip=['digit', 'logit'],
    ).properties(title=f"Logit theo chữ số", width=400, height=250)

    # Bảng thông tin
    _info = mo.md(f"""
    ### Kết quả suy luận – Test vector #{_idx}

    | Thông tin | Giá trị |
    |-----------|---------|
    | **Nhãn đúng** | {_true_label} |
    | **Dự đoán** | {_pred_label} |
    | **Kết quả** | {'✓ Đúng' if _pred_label == _true_label else '✗ Sai'} |
    | **Logit cao nhất** | {_logits[_pred_label]} |
    | **Logit nhãn đúng** | {_logits[_true_label]} |
    """)

    # Chi tiết activation
    if show_detail.value:
        _act1 = _result['act1'][0]
        _act2 = _result['act2'][0]
        _detail = mo.md(f"""
    #### Activation chi tiết

    **FC1 activation ({len(_act1)} neuron, sau ReLU + requant):**
    {_act1.tolist()}

    **FC2 activation ({len(_act2)} neuron, sau ReLU + requant):**
    {_act2.tolist()}

    **Logit int32 (10 chữ số):**
    {_logits.tolist()}
    """)
    else:
        _detail = mo.md("")

    mo.vstack([_info, mo.image(_img / 127.0), _chart, _detail])
    return


if __name__ == "__main__":
    app.run()
