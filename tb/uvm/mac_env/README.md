# tb/uvm/mac_env

UVM env for `mac_engine` (spec §10.1, Phase 2 Task 16). Owner: Track B.

| File | What it holds |
|---|---|
| `mac_cmd_if.sv`, `mac_dtcm_if.sv` | the §7.1 ports with clocking blocks; `csr_re` is a verification-only CSR-read marker |
| `mac_probe_if.sv` | white-box FSM state and FIFO count, bound into `mac_engine` for `cg_fifo`/`cg_state` |
| `mac_cmd_agent_pkg.sv` | `mac_cmd_item` (PUSH, READ, CSR_RD, CSR_WR), driver, monitor, agent |
| `mac_dtcm_agent_pkg.sv` | port-B responder; `write_word` also writes `npu_ref` (Review Focus 2) |
| `mac_predictor.sv`, `mac_scoreboard.sv`, `mac_coverage.sv` | `npu_ref` (DPI-C) in program order, comparisons, the §10.5 covergroups |
| `mac_env_pkg.sv` | the env; its `check_phase` compares the responder memory with `npu_ref` over all 16,384 words |
| `mac_seq_lib.sv`, `mac_test_pkg.sv` | directed sequences and one `uvm_test` per §10.3 mac row |
| `mac_tb_top.sv`, `mac_dv.f` | top (DUT, binds of `tb/sva/mac_engine_sva.sv` and the probe) and compile list |

Run (QuestaSim on PATH): `python run.py --target mac_directed` (D0) or `--config d1`; one test: `--target mac_w1c`. Logs: `out/<date>/<config>/<test>/<seed>/sim.log`.
