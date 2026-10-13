# sim/questa

Siemens QuestaSim run scripts: UVM regression, functional coverage (`vcover report`),
VCD dumps for the D0/D1 switching-activity runs (spec §3.1 D1, D1a; §11).

Needs a **full QuestaSim licence**. The free Questa–Intel/Altera FPGA (Starter) editions
do not run `randomize`/`covergroup`, so a UVM bench with constrained random and coverage
fails there with a "verification license" checkout error (spec §17). Smoke tests S1–S3
(plan Task 0) confirm the licence; the fallback is Vivado xsim (S6).
