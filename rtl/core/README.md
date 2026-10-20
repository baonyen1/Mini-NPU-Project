# rtl/core

Scalar core: 5-stage RV32I from Senior Project 1, extended in Track A Phase 1 to RV32IM + Zicsr + Zifencei + Zbb + custom-0 (spec §5–6); see `docs/core_isa.md` and `docs/core_stall.md`. Instruction and data memories are outside the core (`rtl/mem`, `rtl/top`). `rtl/fpga/RISC_V_Fixed_Impl_Top.v` still uses the old core ports. Owner: Track A.
