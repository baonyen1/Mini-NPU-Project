#!/usr/bin/env python3
"""check_run_py.py - self-test of run.py (Phase 2 Task 15 [support], run_py_selftest).

    python sim/selftest/check_run_py.py

Runs `run.py --target selftest` three times:
  1. with sim/tests.yaml as committed: both dummy tests must match their expectation, exit 0;
  2. with selftest_pass flipped to expected-fail (expect_ids [SELFTEST_FAIL]): exit 1, only it is BAD;
  3. with selftest_fail flipped to expected-pass: exit 1, only it is BAD.
The flipped lists are temporary copies (run.py --tests); sim/tests.yaml is never changed. Needs what
run.py needs (vlog, vsim on PATH) plus PyYAML. Prints RESULT: PASS / RESULT: FAIL; exits 0 / 1.
"""
import copy
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Dict, List, Optional

import yaml

ROOT = Path(__file__).resolve().parents[2]
RUN_PY = ROOT / "run.py"
TESTS_YAML = ROOT / "sim" / "tests.yaml"
TESTS = ("selftest_pass", "selftest_fail")


def run_selftest(tests_yaml: Optional[Path]) -> subprocess.CompletedProcess:
    """Run run.py on the selftest suite, with sim/tests.yaml or the given test list."""
    cmd = [sys.executable, str(RUN_PY), "--target", "selftest"]
    if tests_yaml is not None:
        cmd += ["--tests", str(tests_yaml)]
    return subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)


def verdicts(stdout: str) -> Dict[str, str]:
    """Map each selftest test to 'ok' or 'BAD' from run.py's per-run lines ("ok   <test> seed 1 ...")."""
    found: Dict[str, str] = {}
    for line in stdout.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[0] in ("ok", "BAD") and fields[1] in TESTS:
            found[fields[1]] = fields[0]
    return found


def flipped(db: dict, test: str) -> dict:
    """Copy of the test list with the expectation of one test reversed."""
    out = copy.deepcopy(db)
    spec = out["tests"][test]
    if spec.get("expect", "pass") == "pass":
        # the IDs the test would need to fail with, so that its passing is the only reason it is BAD
        spec["expect"] = "fail"
        spec["expect_ids"] = ["SELFTEST_FAIL"]
    else:
        spec.pop("expect", None)
        spec.pop("expect_ids", None)
    return out


def check(name: str, tests_yaml: Optional[Path], want_rc: int, want: Dict[str, str]) -> bool:
    proc = run_selftest(tests_yaml)
    got = verdicts(proc.stdout)
    ok = proc.returncode == want_rc and got == want
    print(f"{'ok ' if ok else 'BAD'}  {name:28s} exit {proc.returncode} (want {want_rc})  {got}", flush=True)
    if not ok:
        # indented, so that run.py's own "RESULT:" line is not read as this script's verdict
        for line in (proc.stdout + proc.stderr).splitlines():
            print("    | " + line)
    return ok


def main() -> int:
    with open(TESTS_YAML, encoding="utf-8") as f:
        db = yaml.safe_load(f)
    for test in TESTS:
        if test not in db.get("tests", {}):
            print(f"check_run_py: {test} is not in {TESTS_YAML}")
            print("RESULT: FAIL")
            return 1

    results: List[bool] = [check("as listed", None, 0, {t: "ok" for t in TESTS})]
    with tempfile.TemporaryDirectory(prefix="run_py_selftest_") as tmp:
        for test in TESTS:
            path = Path(tmp) / f"tests_flip_{test}.yaml"
            path.write_text(yaml.safe_dump(flipped(db, test), sort_keys=False), encoding="utf-8")
            want = {t: ("BAD" if t == test else "ok") for t in TESTS}
            results.append(check(f"{test} flipped", path, 1, want))

    passed = all(results)
    print("RESULT: PASS" if passed else "RESULT: FAIL")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
