# tb/uvm/mac_env

UVM env for `mac_engine` (spec §10.1, Phase 2 Task 16). Owner: Track B.

| File | What it holds |
|---|---|
| `mac_cmd_if.sv`, `mac_dtcm_if.sv` | the §7.1 ports with clocking blocks; `csr_re` and `eng_pop` are verification-only markers (a CSR read; the engine pops a command in CHECK, driven from the probe) |
| `mac_probe_if.sv` | white-box FSM state and FIFO count, bound into `mac_engine` for `cg_fifo`/`cg_state` and the pop marker |
| `mac_cmd_agent_pkg.sv` | `mac_cmd_item` (PUSH, READ, CSR_RD, CSR_WR; RESET and POP from the monitor), driver, monitor, agent |
| `mac_dtcm_agent_pkg.sv` | port-B responder; `write_word` also writes `npu_ref` (Review Focus 2) and checks the WAR rule (`WAR_RULE`) |
| `mac_predictor.sv`, `mac_scoreboard.sv`, `mac_coverage.sv` | `npu_ref` (DPI-C), each command applied when the engine pops it; comparisons (`MISMATCH`, `XVALUE`, `STATUS_RO`); the §10.5 covergroups |
| `mac_env_pkg.sv` | the env; its `check_phase` compares the responder memory with `npu_ref` over all 16,384 words |
| `mac_seq_lib.sv`, `mac_test_pkg.sv` | directed sequences and one `uvm_test` per §10.3 mac row; `mac_rand_seq` (constrained-random mix, §10.3) and its test `mac_rand` |
| `mac_tb_top.sv`, `mac_dv.f` | top (DUT; instantiates `tb/sva/mac_engine_bind.sv`, which binds `tb/sva/mac_engine_sva.sv` and the probe into `mac_engine`) and compile list (UVM 1.2 only through run.py) |

Run (QuestaSim on PATH): `python run.py --target mac_directed` (D0) or `--config d1`; one test: `--target mac_w1c`; random: `--target mac_rand --cov` (seeds 1..200, the `seeds` key of `mac_rand` in `sim/tests.yaml`; `--seeds N` overrides it; seed N runs with `-sv_seed N`; 400 steps per seed; the plusarg `+MAC_RAND_N=<steps>` changes that in a hand-run vsim, run.py does not pass it); the Task 19 regression, directed tests once and `mac_rand` with its 200 seeds: `--target mac_regress --cov`, then merge the UCDBs with `vcover merge -suppress 6854`. Logs: `out/<date>/<config>/<HHMMSS>-<target>/<test>/<seed>/sim.log`, one directory per run.py invocation (printed at the end, with its `manifest.yaml`).
