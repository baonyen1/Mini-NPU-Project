# Coverage exclusions

Bins of the spec §10.5 covergroups that are excluded from the SC2 figure (100 % of declared bins, Phase 2
Task 19 Step 2). A bin may be listed here only when it truly cannot be hit, with the reason. An entry
counts only when both students have signed it; until then it is marked "proposed, needs both
signatures" and the bin still counts as a hole.

Not exclusions: the `ignore_bins` declared in the covergroups themselves (for example `cg_cmd`'s
K = 0 or K = KMAX crossed with K mod 4 ≠ 0, which no K can produce) are part of the coverage model of
spec §10.5 and D24, not of this list.

## mac_env

| Bin | Reason | Signed A (Tấn) | Signed B (Bảo) |
|---|---|---|---|
| (none) | Every declared bin of `cg_cmd`, `cg_operand`, `cg_fifo`, `cg_state`, `cg_acc`, `cg_err` and `cg_addr` is hit in the merged D0 `mac_regress` run of 2026-11-10 (`docs/report/ch_verification.md`). `cg_gate` is declared in Phase 3. | | |

## core_env, soc_env

None yet (Tasks 17 and 18).
