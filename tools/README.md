# tools

Non-graded support tooling (quick checks, scripts).

- `finish_task.ps1` / `finish_task.sh`: regression, commit, rebase, push. Keep the two in sync.
- `test_finish_task.sh`: regression test for both scripts (throw-away origin and clones; `bash tools/test_finish_task.sh`, expects `RESULT: PASS`).
