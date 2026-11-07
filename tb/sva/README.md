# tb/sva

SVA assertion modules bound to the DUT (spec §10.6).

| File | What it holds |
|---|---|
| `mac_engine_sva.sv` | A-MAC-1..5 with a cover per property; failures report `UVM_ERROR` with the assertion ID |
| `mac_engine_bind.sv` | module `mac_engine_bind`: binds `mac_engine_sva` and `mac_probe_if` (from `tb/uvm/mac_env/`) into every `mac_engine`; a top instantiates it once (`mac_tb_top` now, Task 18's `npu_tb_top` later) |
