#!/usr/bin/env python3
"""check_run_py.py - self-test of run.py (Phase 2 Task 15 [support], run_py_selftest).

    python sim/selftest/check_run_py.py                       # checks the repository's run.py
    python sim/selftest/check_run_py.py --run-py <copy>.py    # checks another run.py (e.g. a mutant)

Runs run.py on the dummy tests of sim/selftest/selftest_tb.sv, once per case below, and checks the exit
code and run.py's per-test "ok"/"BAD" lines. Each failing case trips exactly one condition of run.py's rules
(run.py run_one):
  pass rule:        report summary, UVM_ERROR : 0, UVM_FATAL : 0, no "# ** Error/Fatal" simulator line
  expected-fail:    must fail, with exactly the listed IDs (each listed ID seen, no other ID)
  case                         list change (temporary copy)                  want
  as listed                    none                                          exit 0, all ok
  selftest_pass flipped        expect fail [SELFTEST_FAIL]                   exit 1, selftest_pass BAD (passes)
  selftest_fail flipped        expect pass                                   exit 1, selftest_fail BAD (UVM_ERROR)
  selftest_fatal flipped       expect pass                                   exit 1, selftest_fatal BAD (UVM_FATAL)
  selftest_fail ids []         expect_ids []                                 exit 1, BAD (an ID not listed)
  selftest_fail ids + absent   expect_ids [SELFTEST_FAIL, SELFTEST_ABSENT]   exit 1, BAD (a listed ID not seen)
  sim error / no summary       adds selftest_sva, selftest_no_summary,       exit 1, both BAD
                               expect pass
The changed lists are temporary copies (run.py --tests); sim/tests.yaml is never changed. Needs what run.py
needs (vlog, vsim on PATH) plus PyYAML. Prints RESULT: PASS / RESULT: FAIL; exits 0 / 1.
"""
import argparse
import copy
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable, Dict, List, NamedTuple, Optional

import yaml

ROOT = Path(__file__).resolve().parents[2]
TESTS_YAML = ROOT / "sim" / "tests.yaml"
SUITE = ("selftest_pass", "selftest_fail", "selftest_fatal")   # suite "selftest" in sim/tests.yaml
EXTRA = ("selftest_sva", "selftest_no_summary")                 # deliberately not in sim/tests.yaml


class Case(NamedTuple):
    name: str
    change: Optional[Callable[[dict], None]]   # edits a copy of the test list; None = list as committed
    target: str
    want_rc: int
    want: Dict[str, str]                       # test -> "ok" | "BAD"


def set_spec(test: str, **spec: object) -> Callable[[dict], None]:
    """A change that replaces the expectation of one test (its env stays)."""
    def change(db: dict) -> None:
        db["tests"][test] = {"env": db["tests"][test]["env"], **spec}
    return change


def add_extra(db: dict) -> None:
    """Lists selftest_sva and selftest_no_summary, expected to pass, in a suite of their own."""
    for test in EXTRA:
        db["tests"][test] = {"env": "selftest"}
    db["suites"]["selftest_extra"] = list(EXTRA)


def only_bad(bad: str) -> Dict[str, str]:
    return {t: ("BAD" if t == bad else "ok") for t in SUITE}


CASES = [
    Case("as listed", None, "selftest", 0, {t: "ok" for t in SUITE}),
    Case("selftest_pass flipped", set_spec("selftest_pass", expect="fail", expect_ids=["SELFTEST_FAIL"]),
         "selftest", 1, only_bad("selftest_pass")),
    Case("selftest_fail flipped", set_spec("selftest_fail"), "selftest", 1, only_bad("selftest_fail")),
    Case("selftest_fatal flipped", set_spec("selftest_fatal"), "selftest", 1, only_bad("selftest_fatal")),
    Case("selftest_fail ids []", set_spec("selftest_fail", expect="fail", expect_ids=[]),
         "selftest", 1, only_bad("selftest_fail")),
    Case("selftest_fail ids + absent",
         set_spec("selftest_fail", expect="fail", expect_ids=["SELFTEST_FAIL", "SELFTEST_ABSENT"]),
         "selftest", 1, only_bad("selftest_fail")),
    Case("sim error / no summary", add_extra, "selftest_extra", 1, {t: "BAD" for t in EXTRA}),
]


def verdicts(stdout: str) -> Dict[str, str]:
    """Map each test to 'ok' or 'BAD' from run.py's per-run lines ("ok   <test> seed 1 ...")."""
    found: Dict[str, str] = {}
    for line in stdout.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[0] in ("ok", "BAD"):
            found[fields[1]] = fields[0]
    return found


def check(case: Case, db: dict, run_py: Path, tmp: Path) -> bool:
    cmd = [sys.executable, str(run_py), "--target", case.target]
    if case.change is not None:
        changed = copy.deepcopy(db)
        case.change(changed)
        path = tmp / f"tests_{len(list(tmp.iterdir()))}.yaml"
        path.write_text(yaml.safe_dump(changed, sort_keys=False), encoding="utf-8")
        cmd += ["--tests", str(path)]
    proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True)
    got = verdicts(proc.stdout)
    ok = proc.returncode == case.want_rc and got == case.want
    print(f"{'ok ' if ok else 'BAD'}  {case.name:28s} exit {proc.returncode} (want {case.want_rc})  {got}",
          flush=True)
    if not ok:
        # indented, so that run.py's own "RESULT:" line is not read as this script's verdict
        for line in (proc.stdout + proc.stderr).splitlines():
            print("    | " + line)
    return ok


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--run-py", type=Path, default=ROOT / "run.py", help="the run.py to check")
    args = ap.parse_args()

    with open(TESTS_YAML, encoding="utf-8") as f:
        db = yaml.safe_load(f)
    missing = [t for t in SUITE if t not in db.get("tests", {})]
    if missing or list(db.get("suites", {}).get("selftest", [])) != list(SUITE):
        print(f"check_run_py: {TESTS_YAML} does not list suite selftest = {list(SUITE)}")
        print("RESULT: FAIL")
        return 1

    results: List[bool] = []
    with tempfile.TemporaryDirectory(prefix="run_py_selftest_") as tmp:
        for case in CASES:
            results.append(check(case, db, args.run_py.resolve(), Path(tmp)))

    passed = all(results)
    print(f"{sum(results)}/{len(results)} cases as expected")
    print("RESULT: PASS" if passed else "RESULT: FAIL")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
