# Mini-NPU Phase 3 (Tuần 10–12): Implementation Plan — Clock Gating (D1) và Switching Activity (bản tiếng Việt)

> **Bản dịch để đọc cho dễ.** Bản chuẩn là bản tiếng Anh `docs/superpowers/plans/2026-10-15-mini-npu-phase3-gating-power.md`. Khi hai bản khác nhau, bản tiếng Anh thắng. Dịch ngày 2026-10-29 (commit ngay sau `a2b3a97`). Tên task, tên test, tên file, lệnh, câu commit và thuật ngữ kỹ thuật giữ nguyên tiếng Anh.

> **Cho agent:** BẮT BUỘC dùng sub-skill superpowers:subagent-driven-development (khuyến nghị) hoặc superpowers:executing-plans để làm plan này theo từng task. Các step dùng cú pháp checkbox (`- [ ]`) để theo dõi.
>
> **Luật của dự án (ghi đè dòng trên đối với phần được chấm điểm):** sinh viên tự viết toàn bộ RTL, logic golden model, UVM và firmware. Claude review dựa trên các test được nêu ở đây. Các task gắn **[support]** là tooling không chấm điểm, Claude có thể viết khi được yêu cầu.

**Mục tiêu:** Tới cuối tuần 12, D1 (clock gating cho MAC engine) giống D0 từng cycle trên mọi test soc (SC3), và đợt quét tỉ lệ idle synthetic E2 đã cho ra ước lượng switching activity M1/M2 cho D0 và D1 (SC4, phần synthetic).

**Kiến trúc:** Một `npu_clk_gate` (latch + AND, theo mẫu CoralNPU `hdl/verilog/ClockGate.sv`, do nhóm tự viết) gate `clk_mac`, clock cấp cho WBUF, IBUF, các register của PE và các accumulator (§7.3, §8). D0 và D1 chỉ khác nhau ở `GATING_EN`. Một harness tương đương chứng minh D1 = D0 trước khi đưa ra bất kỳ con số power nào; sau đó một VCD của `u_mac_engine`, chỉ lấy trong cửa sổ đo của firmware, được rút gọn thành số đếm toggle.

**Tech stack:** SystemVerilog trên QuestaSim (một simulator cho cả hai cấu hình, D1a), Python 3 (parse VCD, CSV, matplotlib), RISC-V GCC.

**Spec:** `docs/superpowers/specs/2026-10-04-mini-npu-design.md` §7.3, §8, §10.4, §10.5 (`cg_gate`), §10.6 (A-GATE-*), §11. Plan trước: `docs/superpowers/plans/2026-10-15-mini-npu-phase2-uvm-integration.md` (tag `phase2-d0` là baseline D0).

**Người phụ trách:** Track A = Nguyễn Hoàng Công Tấn, Track B = Nguyễn Thế Bảo.

| Task | Người phụ trách | Tuần |
|---|---|---|
| 20 · `npu_clk_gate` + D1 + SVA/coverage cho gating | Bảo | 10 |
| 21 · Harness tương đương D0/D1 | Tấn (script), cả hai chạy | 10–11 |
| 22 · Firmware synthetic theo tỉ lệ idle | Tấn | 11 |
| 23 · Cửa sổ VCD của engine + `toggle_count.py` | Bảo | 11–12 |
| 24 · Các lần chạy E2, CSV, biểu đồ | Bảo (`plots.py` có thể là **[support]**) | 12 |

## Ràng buộc chung (bổ sung cho Phase 3)

- Ưu tiên (luật dự án): SC3 trước mọi con số switching activity. Task 22–23 có thể viết song song với Task 21, nhưng dữ liệu E2 (Task 24) chỉ được tạo sau khi Task 21 pass.
- D0 = tag `phase2-d0` cộng các bản sửa bug, không gì khác. D0 và D1 dùng cùng binary, cùng phiên bản QuestaSim và cùng tuỳ chọn dump (công bằng, §11). `GATING_EN` là khác biệt duy nhất.
- Enable (§8): `en = !rst_n_sync || (fsm != IDLE) || !fifo_empty`, chỉ lấy từ register. Gating phải thêm **không** cycle nào: cạnh gated đầu tiên sau một lần push tới đúng lúc FSM cần nó.
- Metric (§11): M1 = số toggle của net `clk_mac`; M2 = số toggle của mọi net khác trong `u_mac_engine` (không tính các net clock `clk` và `clk_mac`, vì M1 và số cycle đã phủ chúng), tách thành M2-free / M2-gated theo clock domain (§7.3); cả hai tính theo mỗi 1.000 cycle free clock trong cửa sổ. Một toggle là bất kỳ chuyển đổi 0↔1 nào; chuyển từ hoặc tới x/z không được tính.
- Mọi hình và bảng đều ghi cấu hình, workload, seed và đơn vị, và mang nhãn **"switching-activity estimate"**. Cụm "measured power" không bao giờ xuất hiện.
- Mỗi cấu hình chạy một lần cho mỗi workload; chỉ được chạy lại sau một lỗi bên ngoài đã được ghi log (§11).

## Review Focus

1. **Push đúng cycle `en` xuống:** một lệnh được push đúng lúc engine vừa về idle phải bắt đầu ở cùng cycle như trên D0. Test: Task 20 `mac_gate_push_on_fall`.
2. **READ_RESULT sau một khoảng idle bị gate dài:** accumulator được đọc theo kiểu tổ hợp trong lúc `clk_mac` dừng (§7.3); giá trị phải là giá trị đã tính trước khoảng idle. Test: Task 20 `mac_gate_read_after_long_idle`.
3. **Harness tương đương không thể fail:** so sai file, hoặc so log rỗng, sẽ "chứng minh" tương đương một cách tầm thường. Test: Task 21 `eq_selftest_detects` (ba khác biệt được cài vào, mỗi cái phải được báo).
4. **Thiếu hoặc sai cửa sổ đo:** khi không có `MEAS_START`/`MEAS_STOP`, tool phải từ chối, không được đếm cả lần chạy hoặc không đếm gì. Test: Task 23 `toggle_no_window_errors`.
5. **Tính tỉ lệ idle ngoài cửa sổ:** code khởi tạo trước `MEAS_START` không được tính vào tỉ lệ. Test: Task 22 `synthetic_ratio_in_window` (tỉ lệ lấy từ các counter được sample tại các marker).

---

### Task 20: `npu_clk_gate`, cấu hình D1, assertion và coverage cho gating — Track B, tuần 10

**File:**
- Sửa: `rtl/prim/npu_clk_gate.sv` (latch trong suốt khi `clk` thấp, rồi AND; có input `test_en`; `/* verilator clock_enable */` ở output của latch; `GATING_EN=0` buộc `en` lên 1 bên trong cell, nên D0 vẫn giữ instance)
- Sửa: `rtl/npu/mac_engine.sv` (`en` theo §8; WBUF, IBUF, register của PE và accumulator chạy trên `clk_mac`; FIFO, FSM, CSR, `npu_busy_cyc`, bộ đếm port B chạy trên `clk`)
- Tạo: `tb/sva/gate_sva.sv` (A-GATE-1, A-GATE-2, `bind mac_engine`)
- Sửa: `tb/uvm/mac_env/mac_coverage.sv` (`cg_gate`: en lên, en xuống, en thấp đúng 1 cycle, en thấp ≥ 100 cycle; chỉ sample khi `GATING_EN=1`)
- Tạo: `tb/directed/npu_clk_gate_tb.sv`
- Sửa: `docs/mac_engine.md` (bảng clock domain, timing diagram của en cho một lần push sau idle)

**Interface:**
- Dùng: `mac_env` (Phase 2 Task 16), `run.py --config d0|d1` (`+define+GATING_EN=0|1`).
- Tạo ra: `module npu_clk_gate #(parameter bit GATING_EN = 1) (input logic clk, en, test_en, output logic gclk);` và net `u_mac_engine.clk_mac` (M1 được đếm trên đúng tên này).

- [ ] **Step 1: Viết các test fail:**
  - `npu_clk_gate_tb`: `en` thấp ở cycle 10–19 → 0 cạnh lên của `gclk` ở cycle 11–19, mỗi cycle một cạnh ở chỗ khác; với `GATING_EN=0` mỗi cycle đều có một cạnh; một glitch của `en` trong lúc `clk` cao không tới được `gclk`
  - `mac_gate_push_on_fall` (Review Focus 1): cho engine idle, rồi push ở cycle đầu tiên `en` thấp; cycle phát request port B của lệnh đó (tính từ lúc push) bằng giá trị trên D0
  - `mac_gate_read_after_long_idle` (Review Focus 2): COMPUTE, 500 cycle idle (bị gate), READ cả 16 → bằng `npu_ref`
  - `mac_gate_idle_mix`: `mac_rand_seq` với khoảng cách giữa các lệnh bị ép về {0, 1, 2, 150} cycle để trúng mọi bin của `cg_gate`
- [ ] **Step 2:** `run.py --target mac_gate --config d1` → FAIL.
- [ ] **Step 3:** Cài đặt.
- [ ] **Step 4:** `run.py --target mac_regress --config d1 --seeds 200 --cov` → 0 mismatch, 0 lần SVA fail (A-MAC-*, A-GATE-*), `cg_gate` 100 %; cùng lệnh đó với `--config d0` vẫn xanh. Rồi `run.py --target regress_d1` (suite của Phase 2 Task 19) → xanh (SC1 trên D1).
- [ ] **Step 5: Commit** `feat(npu): npu_clk_gate and D1 gating with assertions and cg_gate`.

---

### Task 21: Harness tương đương D0/D1 — Track A (script), cả hai chạy, tuần 10–11

**File:**
- Tạo: `tools/eq/compare_runs.py`, `tools/eq/tests/test_compare_runs.py` (pytest, thư mục lần chạy giả lập)
- Sửa: `tb/uvm/common/npu_rvvi_agent_pkg.sv` (`+RVVI_LOG=<file>`: mỗi lần retire một dòng, `order pc insn rd rd_wdata mem_addr mem_wdata mem_wmask trap`, hex, độ rộng cố định)
- Sửa: `tb/uvm/common/npu_sim_ctrl_monitor` (ở cuối test ghi `end.txt`: `mcycle=<dec> minstret=<dec>` đọc bằng backdoor từ các register CSR của core; đường dẫn hierarchy do Track A ghi trong `docs/core_isa.md`)
- Sửa **[support]**: `run.py --target eq_<suite>` = chạy `<suite>` với `--config d0` và `--config d1`, rồi `compare_runs.py`

**Interface:**
- Dùng: các test soc (Phase 2 Task 18), bản dump LOGITS của `soc_end_checker`.
- Tạo ra: `compare_runs.py <d0_dir> <d1_dir>` → thoát mã 0 khi và chỉ khi với mọi test: SHA-256 của `rvvi.log` bằng nhau, `end.txt` bằng nhau, `logits.hex` bằng nhau (nếu có). Khi fail, in ra test, số dòng RVVI đầu tiên bị lệch, và cả hai giá trị counter.

- [ ] **Step 1: Viết các test fail** (`test_compare_runs.py`, Review Focus 3):
  - `eq_selftest_pass`: hai thư mục lần chạy giả lập giống hệt → thoát mã 0
  - `eq_selftest_detects`: ba trường hợp, mỗi trường hợp phải thoát mã 1 và nêu tên field: một dòng RVVI khác; `mcycle` lệch 1; một word LOGITS khác
  - `eq_selftest_missing`: một test có ở D0 nhưng không có (hoặc có `rvvi.log` rỗng) ở D1 → thoát mã 1
- [ ] **Step 2:** `pytest tools/eq` → FAIL. **Step 3:** Cài đặt. **Step 4:** pytest xanh.
- [ ] **Step 5:** `run.py --target eq_soc_all` → mọi test soc giống hệt nhau trên D0 và D1 (SC3). Một khác biệt là một bug: tìm nguyên nhân gốc trước khi tính tới phương án dự phòng của SC3 (giống nhau về kết quả, kèm lý do viết trong `docs/mac_engine.md`).
- [ ] **Step 6: Commit** `test: D0/D1 equivalence harness, SC3 on soc tests`.

---

### Task 22: Firmware synthetic theo tỉ lệ idle — Track A, tuần 11

**File:**
- Tạo: `sw/synthetic/main.c` (lúc compile `-DIDLE_PCT={10,25,50,75,90}`, `-DBURSTS=20`)
- Sửa: `sw/Makefile` (`make -C sw TEST=synthetic IDLE_PCT=50` → `sw/build/synthetic_50/…`)
- Tạo: `sw/synthetic/README.md` (cách suy ra độ dài vòng lặp bận từ độ dài burst đo được)

**Interface:**
- Dùng: `npu.h`, `sim.h` (Phase 2 Task 13).
- Tạo ra: firmware mà, giữa `sim_meas_start()` và `sim_meas_stop()`, chạy `BURSTS` × (LDW K=256 + LDI K=256 + COMPUTE K=256 clr=1 + READ_RESULT idx 0, rồi một vòng lặp bận của scalar). Nó sample `mcycle` và `npu_busy_cyc` ngay sau `sim_meas_start()` và ngay trước `sim_meas_stop()` và lưu hai delta vào các word DTCM `0x0001_DDF4` (`d_mcycle`) và `0x0001_DDF8` (`d_busy`) (các word trống đầu tiên sau §9.2).

- [ ] **Step 1: Viết test fail** `synthetic_ratio_in_window` (Review Focus 5): với mỗi `IDLE_PCT`, testbench đọc hai word bằng backdoor và kiểm `|(1 − d_busy/d_mcycle)·100 − IDLE_PCT| ≤ 2`.
- [ ] **Step 2:** Chạy trên D0 → FAIL. **Step 3:** Cài đặt (hiệu chỉnh vòng lặp bận từ một burst đo được). **Step 4:** Cả năm tỉ lệ nằm trong ±2 điểm phần trăm; `eq_synthetic` (harness của Task 21) giống hệt trên D0/D1.
- [ ] **Step 5: Commit** `feat(sw): synthetic idle-ratio workload`.

---

### Task 23: Cửa sổ VCD của engine và `toggle_count.py` — Track B, tuần 11–12

**File:**
- Sửa: `tb/uvm/tb/npu_tb_top.sv` (dưới `+DUMP_ENGINE=<file>`: `$dumpfile(<file>)`, `$dumpvars(0, u_dut.u_mac_engine)`, `$dumpoff` ở thời điểm 0; `$dumpon` khi có `MEAS_START` (0x20), `$dumpoff` khi có `MEAS_STOP` (0x21); dump thêm free clock `u_dut.u_mac_engine.clk` để đếm cycle). Đây là system task của SV, nên cùng flow này chạy được trên Verilator nếu có lúc dùng tới D1a.
- Tạo: `power/net_domains.yaml` (tiền tố đường dẫn instance → `free` | `gated`, theo §7.3)
- Tạo: `power/toggle_count.py`, `power/tests/test_toggle_count.py`, `power/tests/vcd/*.vcd` (viết tay)

**Interface:**
- Tạo ra: `toggle_count.py <vcd> --domains power/net_domains.yaml --config d0|d1 --workload <name> --seed <n>` → thêm một dòng CSV ra stdout:
  `config,workload,seed,cycles,m1,m2_free,m2_gated,m1_per_kcyc,m2_per_kcyc,label` với `label = "switching-activity estimate"`. `cycles` = số cạnh lên của free clock trong cửa sổ. Parser dạng streaming (từng dòng), nên kích thước file chỉ bị giới hạn bởi ổ đĩa, không phải RAM.

- [ ] **Step 1: Viết các test fail:**
  - `toggle_known_counts`: một VCD viết tay có 10 cycle free clock, `clk_mac` chạy 6 cycle trong đó, một net dữ liệu ở gated domain có 3 lần chuyển và một net dữ liệu ở free domain có 4 lần chuyển → `cycles=10, m1=12, m2_gated=3, m2_free=4`
  - `toggle_ignores_x_to_value`: phép gán ban đầu `x→0/1` ở `$dumpon` đầu tiên không phải toggle
  - `toggle_no_window_errors` (Review Focus 4): một VCD không có đoạn `$dumpon` nào, hoặc một file rỗng → thoát mã 2 với thông báo `no measurement window`
  - `toggle_unmapped_net_errors`: một net có đường dẫn không khớp tiền tố nào trong `net_domains.yaml` → thoát mã 2 và nêu tên net
- [ ] **Step 2:** `pytest power/tests` → FAIL. **Step 3:** Cài đặt. **Step 4:** pytest xanh.
- [ ] **Step 5:** Smoke: `synthetic` với `IDLE_PCT=50` trên D0 và D1 cho ra hai dòng; kiểm tra hợp lý ghi trong commit message: `m1_per_kcyc` của D0 ≈ 2.000 (hai cạnh mỗi cycle), `m1_per_kcyc` của D1 lệch không quá 10 % so với 2.000 × phần thời gian busy.
- [ ] **Step 6: Commit** `feat(power): engine VCD window and toggle counter`.

---

### Task 24: Dữ liệu E2, biểu đồ, bảng kết quả — Track B (biểu đồ là **[support]** nếu được yêu cầu), tuần 12

**File:**
- Tạo: `power/plots.py` (CSV → `out/<date>/e2/fig_m1.png`, `fig_m2.png`, `fig_change.png`)
- Sửa **[support]**: `run.py --target e2` = 5 tỉ lệ × {d0, d1} với `+DUMP_ENGINE`, rồi `toggle_count.py`, rồi `plots.py`
- Tạo: `out/<date>/e2/e2.csv`, `docs/results/e2.md` (bảng: tỉ lệ, M1/M2 mỗi kcycle cho D0 và D1, % thay đổi; ngày chạy, git hash, phiên bản QuestaSim, seed)

**Interface:**
- Dùng: Task 21–23.
- Tạo ra: `docs/results/e2.md` và các hình dùng cho chương báo cáo ở Phase 4; đường cong E2 dùng cho bước đối chiếu E4 ở Phase 4 (§11).

- [ ] **Step 1: Kiểm cổng:** `run.py --target eq_soc_all` và `eq_synthetic` xanh trên commit hiện tại. Nếu không, dừng lại (ưu tiên của dự án).
- [ ] **Step 2:** `run.py --target e2` → 10 lần chạy, 10 dòng CSV.
- [ ] **Step 3:** Mỗi hình hiện cấu hình, workload, seed, đơn vị và nhãn "switching-activity estimate"; `% change = (D1 − D0) / D0 × 100` cho từng metric và tỉ lệ.
- [ ] **Step 4:** Viết `docs/results/e2.md`: chỉ có số liệu cộng một đoạn về ý nghĩa của M1 so với M2 (M1 ≈ phần thời gian busy; M2 phản ánh hoạt động dữ liệu, §11). Không có khẳng định nào tính bằng mW.
- [ ] **Step 5: Commit** `data: E2 synthetic switching-activity sweep` và gắn tag `phase3-d1`.

## Exit checklist của Phase 3

- [ ] SC1 trên D1: `run.py --target regress_d1` xanh, 0 lần SVA fail, `cg_gate` 100 %
- [ ] SC3: `eq_soc_all` và `eq_synthetic` giống hệt (hoặc phương án dự phòng đã ghi lại kèm nguyên nhân gốc)
- [ ] SC4 (synthetic): `docs/results/e2.md` và các hình, tất cả gắn nhãn "switching-activity estimate"
- [ ] Các test Review Focus 1–5 hoạt động như mô tả
- [ ] Tag `phase3-d1` đã push; `manifest.yaml` đã cập nhật
