#!/usr/bin/env python3
"""check_run_py.py - self-test of run.py (Phase 2 Task 15 [support], run_py_selftest).

    python sim/selftest/check_run_py.py                       # checks the repository's run.py
    python sim/selftest/check_run_py.py --run-py <copy>.py    # checks another run.py (e.g. a mutant)

Runs run.py on the dummy tests of sim/selftest/selftest_tb.sv, once per case below, and checks the exit
code, run.py's per-test "ok"/"BAD" lines (each test must run once) and, where given, a message. Each failing
case trips exactly one condition of run.py's rules (run.py run_one, main):
  pass rule:        report summary, UVM_ERROR : 0, UVM_FATAL : 0, no "# ** Error/Fatal" simulator line
  expected-fail:    must fail, with exactly the listed IDs (each listed ID seen, no other ID)
  any run:          killed at the wall-clock limit (--wall-limit) = failure
  case                         list change (temporary copy) / arguments      want
  as listed                    none                                          exit 0, all ok
  selftest_pass flipped        expect fail [SELFTEST_FAIL]                   exit 1, selftest_pass BAD (passes)
  selftest_fail flipped        expect pass                                   exit 1, selftest_fail BAD (UVM_ERROR)
  selftest_fatal flipped       expect pass                                   exit 1, selftest_fatal BAD (UVM_FATAL)
  selftest_fail ids []         expect_ids []                                 exit 1, BAD (an ID not listed)
  selftest_fail ids + absent   expect_ids [SELFTEST_FAIL, SELFTEST_ABSENT]   exit 1, BAD (a listed ID not seen)
  sim error / no summary       adds selftest_sva, selftest_no_summary,       exit 1, both BAD
                               expect pass
  wall-clock limit             adds selftest_hang, expect pass;              exit 1, BAD (killed)
                               --wall-limit 30
  nested suite                 suite [selftest, selftest_pass]               exit 0, all ok, each test once
  suite cycle                  suites a: [b], b: [a]                         exit 1, no run, "suite cycle"
  empty suite                  suite []                                      exit 1, no run, "expands to no test"
  seeds 0                      --seeds 0                                     exit 2, no run
  d1 without gating            --config d1 (env selftest has no gating key)  exit 2, no run, names the env
  d1 mixed suite               suite [mac_w1c, selftest_pass], --config d1   exit 2, no run, names env selftest
                               (env mac has gating: true, selftest none)
  gating not a bool            env selftest gating: "false" (a string)       exit 1, no run, "gating must be"
  seeds key                    selftest_pass seeds: 2                        exit 0, selftest_pass runs twice
  --seeds over the key         selftest_pass seeds: 2; --seeds 1             exit 0, every test once
  seeds key 0                  selftest_pass seeds: 0                        exit 1, no run, "seeds must be"
Every case that runs tests must print its run directory; at the end these directories must be distinct and
each must still hold every sim.log with the SHA-256 its manifest.yaml records (run.py overwrites no earlier
evidence). The changed lists are temporary copies (run.py --tests); sim/tests.yaml is never changed. Needs
what run.py needs (vlog, vsim, gcc on PATH) plus PyYAML. Prints RESULT: PASS / RESULT: FAIL; exits 0 / 1.
"""
import argparse
import copy
import hashlib
import re
import subprocess
import sys
import tempfile
from pathlib import Path
from typing import Callable, Dict, List, NamedTuple, Optional, Tuple

import yaml

ROOT = Path(__file__).resolve().parents[2]
TESTS_YAML = ROOT / "sim" / "tests.yaml"
SUITE = ("selftest_pass", "selftest_fail", "selftest_fatal")   # suite "selftest" in sim/tests.yaml
EXTRA = ("selftest_sva", "selftest_no_summary")                 # deliberately not in sim/tests.yaml
HANG = "selftest_hang"                                          # not listed either: needs a short --wall-limit
WALL_LIMIT_S = 30           # for the hang case; a selftest run takes a few seconds
CASE_LIMIT_S = 900          # a run.py that never returns fails its case instead of hanging this script


class Case(NamedTuple):
    name: str
    change: Optional[Callable[[dict], None]]   # edits a copy of the test list; None = list as committed
    target: str
    want_rc: int
    want: Dict[str, str]                       # test -> "ok" | "BAD"
    args: Tuple[str, ...] = ()                 # extra run.py arguments
    want_text: str = ""                        # must appear in run.py's output


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


def add_hang(db: dict) -> None:
    """Lists selftest_hang, expected to pass (only the wall-clock limit can end it)."""
    db["tests"][HANG] = {"env": "selftest"}


def add_suites(**suites: List[str]) -> Callable[[dict], None]:
    """A change that adds suites to the list."""
    def change(db: dict) -> None:
        db["suites"].update(copy.deepcopy(suites))
    return change


def set_env_key(env: str, key: str, value: object) -> Callable[[dict], None]:
    """A change that sets one key of one env."""
    def change(db: dict) -> None:
        db["envs"][env][key] = value
    return change


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
    Case("wall-clock limit", add_hang, HANG, 1, {HANG: "BAD"}, ("--wall-limit", str(WALL_LIMIT_S)),
         "killed at the wall-clock limit"),
    Case("nested suite", add_suites(selftest_nested=["selftest", "selftest_pass"]), "selftest_nested", 0,
         {t: "ok" for t in SUITE}),
    Case("suite cycle", add_suites(cycle_a=["cycle_b"], cycle_b=["cycle_a"]), "cycle_a", 1, {},
         want_text="suite cycle cycle_a -> cycle_b -> cycle_a"),
    Case("empty suite", add_suites(selftest_empty=[]), "selftest_empty", 1, {}, want_text="expands to no test"),
    Case("seeds 0", None, "selftest", 2, {}, ("--seeds", "0"), "--seeds must be at least 1"),
    # a d1 run of an env without GATING_EN would simulate D0 under a d1 label (SC3 would compare D0 with D0)
    Case("d1 without gating", None, "selftest", 2, {}, ("--config", "d1"),
         "uses env(s) without it: selftest"),
    # one env with gating is not enough: every env the suite needs must have it (no Questa time, refused
    # before the build)
    Case("d1 mixed suite", add_suites(selftest_mixed=["mac_w1c", "selftest_pass"]), "selftest_mixed", 2, {},
         ("--config", "d1"), "uses env(s) without it: selftest"),
    # the string "false" is truthy: read as a flag it would pass -GGATING_EN to an env without the parameter
    Case("gating not a bool", set_env_key("selftest", "gating", "false"), "selftest", 1, {},
         want_text="gating must be true or false"),
    Case("seeds key", set_spec("selftest_pass", seeds=2), "selftest", 0,
         {"selftest_pass": "ok twice", "selftest_fail": "ok", "selftest_fatal": "ok"}),
    Case("--seeds over the key", set_spec("selftest_pass", seeds=2), "selftest", 0, {t: "ok" for t in SUITE},
         ("--seeds", "1")),
    Case("seeds key 0", set_spec("selftest_pass", seeds=0), "selftest", 1, {}, want_text="seeds must be"),
]


def verdicts(stdout: str) -> Dict[str, str]:
    """Map each test to its verdict from run.py's per-run lines ("ok   <test> seed 1 ..."): 'ok' or 'BAD'
    (BAD if any of its runs is BAD), followed by the exact run count when it ran more than once ('ok twice',
    'ok 3x', ...). Only the seeds-key case wants a test more than once, and it then fails on any other count."""
    runs: Dict[str, List[str]] = {}
    for line in stdout.splitlines():
        fields = line.split()
        if len(fields) >= 2 and fields[0] in ("ok", "BAD"):
            runs.setdefault(fields[1], []).append(fields[0])
    found: Dict[str, str] = {}
    for test, seen in runs.items():
        verdict = "BAD" if "BAD" in seen else "ok"
        found[test] = verdict if len(seen) == 1 else f"{verdict} {'twice' if len(seen) == 2 else f'{len(seen)}x'}"
    return found


def evidence_problem(run_dir: Path) -> str:
    """'' when run_dir's manifest.yaml lists at least one run and every sim.log it names exists with the
    recorded SHA-256; otherwise what is wrong."""
    manifest = run_dir / "manifest.yaml"
    if not manifest.is_file():
        return f"no {manifest}"
    results = (yaml.safe_load(manifest.read_text(encoding="utf-8")) or {}).get("results") or []
    if not results:
        return f"{manifest} lists no run"
    for entry in results:
        log = ROOT / entry["log"]
        if not log.is_file():
            return f"{log} is gone"
        if hashlib.sha256(log.read_bytes()).hexdigest() != entry["log_sha256"]:
            return f"{log} does not match its SHA-256 in {manifest}"
    return ""


def check(case: Case, db: dict, run_py: Path, tmp: Path, run_dirs: List[Path]) -> bool:
    cmd = [sys.executable, str(run_py), "--target", case.target, *case.args]
    if case.change is not None:
        changed = copy.deepcopy(db)
        case.change(changed)
        path = tmp / f"tests_{len(list(tmp.iterdir()))}.yaml"
        path.write_text(yaml.safe_dump(changed, sort_keys=False), encoding="utf-8")
        cmd += ["--tests", str(path)]
    try:
        proc = subprocess.run(cmd, cwd=ROOT, capture_output=True, text=True, timeout=CASE_LIMIT_S)
        rc: Optional[int] = proc.returncode
        out = proc.stdout + proc.stderr
    except subprocess.TimeoutExpired as e:
        rc = None
        partial = e.stdout or ""
        out = (partial.decode(errors="replace") if isinstance(partial, bytes) else partial) + \
            f"\ncheck_run_py: run.py did not return within {CASE_LIMIT_S} s"
    got = verdicts(out)
    ok = rc == case.want_rc and got == case.want and case.want_text in out
    m = re.search(r"^run directory: (.+)$", out, re.M)
    problem = ""
    if case.want:                               # a case that runs tests must leave its evidence
        problem = evidence_problem(ROOT / m.group(1).strip()) if m else "no 'run directory:' line"
        if m and not problem:
            run_dirs.append(ROOT / m.group(1).strip())
    elif m:
        problem = "a run directory although nothing should run"
    ok = ok and not problem
    print(f"{'ok ' if ok else 'BAD'}  {case.name:28s} exit {rc} (want {case.want_rc})  {got}"
          + (f"  {problem}" if problem else ""), flush=True)
    if not ok:
        # indented, so that run.py's own "RESULT:" line is not read as this script's verdict
        for line in out.splitlines():
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
    run_dirs: List[Path] = []
    with tempfile.TemporaryDirectory(prefix="run_py_selftest_") as tmp:
        for case in CASES:
            results.append(check(case, db, args.run_py.resolve(), Path(tmp), run_dirs))

    # the later cases must not have overwritten the evidence of the earlier ones
    problems = [p for p in (evidence_problem(d) for d in run_dirs) if p]
    if len(set(run_dirs)) != len(run_dirs):
        problems.append("two cases share a run directory")
    for problem in problems:
        print(f"BAD  evidence: {problem}")
    print(f"evidence: {len(run_dirs)} run directories, {'intact' if not problems else 'NOT intact'}")

    passed = all(results) and not problems
    print(f"{sum(results)}/{len(results)} cases as expected")
    print("RESULT: PASS" if passed else "RESULT: FAIL")
    return 0 if passed else 1


if __name__ == "__main__":
    sys.exit(main())
