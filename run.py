#!/usr/bin/env python3
"""run.py - the single entry point for simulations (Phase 2 Task 15 [support]).

    python run.py --target mac_directed                 # a suite from sim/tests.yaml, D0
    python run.py --target mac_w1c --config d1          # one test, D1 (GATING_EN = 1)
    python run.py --target mac_directed --seeds 3 --cov # seeds 1..3, functional coverage saved (UCDB)
    python run.py --target mac_regress --cov            # each test with its own seed count (seeds key)
    python run.py --list                                # the tests and suites known to sim/tests.yaml
    python run.py --target selftest                     # run.py's own self-test (three dummy UVM tests)
    python run.py --target selftest --tests other.yaml  # the same with another test list

Every invocation gets a directory of its own, out/<date>/<config>/<HHMMSS>-<target>[-N]/ (printed at
the end), so no run overwrites the evidence of an earlier one and two concurrent runs share no work
library. In it, per env: build_<env>/ (the DPI-C library built from the env's C sources with gcc, then
vlog of the env's compile list); then one vsim per test and seed, log in <test>/<seed>/sim.log (and
cov.ucdb with --cov). A test runs seeds 1..N: N from --seeds when given, otherwise the test's seeds key in
sim/tests.yaml (default 1), so a suite can run its directed tests once and a random test 200 times. A suite may list tests and other suites (expanded recursively; a cycle stops).
A run passes when the log has the UVM report summary, UVM_ERROR : 0, UVM_FATAL : 0 and no simulator
error. An expected-fail test (sim/tests.yaml) must fail, and only with the IDs it lists. A run killed at
the wall-clock limit (--wall-limit) is a failure either way. The exit code is 0 only if every run
matched its expectation. <run directory>/manifest.yaml records the tools, the git revision and, per
run, the result, the GATING_EN value passed (gating_en: 1 | 0 | null) and the SHA-256 of its sim.log and
cov.ucdb. --config d1 is refused (exit 2, before any build) when the target needs an env without
gating: true in sim/tests.yaml, since such an env would silently run as D0.

Only QuestaSim is supported for now: Vivado (xsim) is no longer installed on the team machine
(CLAUDE.md section 10). vlog, vsim and gcc must be on PATH (QuestaSim: C:\\questasim64_10.7c\\win64).
"""
import argparse
import datetime
import hashlib
import os
import platform
import re
import shutil
import signal
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent
TESTS_YAML = ROOT / "sim" / "tests.yaml"


def shown(path):
    """A test list as printed: relative to the repository root when it is inside it."""
    try:
        return path.relative_to(ROOT).as_posix()
    except ValueError:
        return str(path)


def load_db(path):
    if not path.is_file():
        sys.exit(f"run.py: no test list {shown(path)}")
    with open(path, encoding="utf-8") as f:
        db = yaml.safe_load(f)
    # keys whose wrong type would silently change a run: gating: "false" (a string) is truthy and would
    # run the env as D1; seeds: "2" or true would not be the count it looks like
    for name, env in (db.get("envs") or {}).items():
        if "gating" in env and not isinstance(env["gating"], bool):
            sys.exit(f"run.py: env '{name}' in {shown(path)}: gating must be true or false (a YAML bool), "
                     f"not {env['gating']!r}")
    for name, spec in (db.get("tests") or {}).items():
        seeds = spec.get("seeds", 1)
        if isinstance(seeds, bool) or not isinstance(seeds, int) or seeds < 1:
            sys.exit(f"run.py: test '{name}' in {shown(path)}: seeds must be an integer >= 1, not {seeds!r}")
    return db


def expand_suite(db, suite, path, stack=()):
    """The tests of a suite in order, each once. An entry is a test when a test of that name exists
    (suite mac_rand lists test mac_rand), otherwise a suite, expanded recursively."""
    if suite in stack:
        sys.exit(f"run.py: suite cycle {' -> '.join(stack + (suite,))} in {shown(path)}")
    tests = []
    for entry in db["suites"][suite] or []:
        if entry in db.get("tests", {}):
            found = [entry]
        elif entry in db.get("suites", {}):
            found = expand_suite(db, entry, path, stack + (suite,))
        else:
            sys.exit(f"run.py: suite '{suite}' lists '{entry}', neither a test nor a suite in {shown(path)}")
        tests += [t for t in found if t not in tests]
    return tests


def expand_target(db, target, path):
    if target in db.get("suites", {}):
        return expand_suite(db, target, path)
    if target in db.get("tests", {}):
        return [target]
    sys.exit(f"run.py: '{target}' is neither a test nor a suite in {shown(path)}")


def tool(name, why=""):
    path = shutil.which(name)
    if path is None:
        sys.exit(f"run.py: '{name}' is not on PATH{why}")
    return path


def first_line(cmd):
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, cwd=ROOT).stdout
        return out.strip().splitlines()[0] if out.strip() else "unknown"
    except OSError:
        return "not available"


def rel(path):
    """Paths handed to QuestaSim are relative to the repository root, with '/': vopt reads an absolute
    Windows path before the design unit name ("C:/.../work.top") as a library:unit and fails."""
    return Path(os.path.relpath(path, ROOT)).as_posix()


QUESTA_ENV = dict(os.environ)


def questa_home():
    return Path(tool("vsim")).resolve().parent.parent


def questa_ini(bdir):
    """Spec D1 asks for UVM 1.2, but the installation's modelsim.ini maps mtiUvm to uvm-1.1d. A copy in the
    run directory maps it to the precompiled uvm-1.2 instead; vlog and vsim find it through $MODELSIM."""
    home = questa_home()
    text = (home / "modelsim.ini").read_text(encoding="utf-8", errors="replace")
    text, n = re.subn(r"^mtiUvm\s*=.*$", f"mtiUvm = {(home / 'uvm-1.2').as_posix()}", text, flags=re.M)
    if n != 1:
        sys.exit("run.py: no mtiUvm line in the QuestaSim modelsim.ini")
    ini = bdir / "modelsim.ini"
    ini.write_text(text, encoding="utf-8")
    QUESTA_ENV["MODELSIM"] = str(ini)


def make_run_dir(target, config):
    """out/<date>/<config>/<HHMMSS>-<target>, with -2, -3, ... appended when it already exists (two
    invocations in the same second). mkdir without exist_ok claims the name atomically."""
    now = datetime.datetime.now()
    base = ROOT / "out" / now.date().isoformat() / config
    base.mkdir(parents=True, exist_ok=True)
    stem = f"{now:%H%M%S}-{re.sub(r'[^A-Za-z0-9_.-]', '_', target)}"
    for n in range(1, 1000):
        run_dir = base / (stem if n == 1 else f"{stem}-{n}")
        try:
            run_dir.mkdir()
            return run_dir
        except FileExistsError:
            continue
    sys.exit(f"run.py: no free run directory for {base / stem}")


def sha256(path):
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def build(env_name, env, run_dir):
    """Build the DPI library and compile the env once; return (work dir, library path without suffix)."""
    bdir = run_dir / f"build_{env_name}"
    bdir.mkdir()
    lib = bdir / "dpi"
    suffix = ".dll" if platform.system() == "Windows" else ".so"
    srcs = [str(ROOT / s) for s in env.get("dpi", [])]
    if srcs:
        inc = sorted({str((ROOT / s).parent) for s in env["dpi"]})
        cmd = [tool("gcc"), "-std=c99", "-O1", "-shared", "-fPIC"] + [f"-I{i}" for i in inc] + \
              ["-o", str(lib) + suffix] + srcs
        if subprocess.run(cmd, cwd=ROOT).returncode != 0:
            sys.exit("run.py: gcc failed to build the DPI library")
    work = bdir / "work"
    subprocess.run([tool("vlib"), rel(work)], cwd=ROOT, capture_output=True, check=True, env=QUESTA_ENV)
    log = bdir / "vlog.log"
    with open(log, "w", encoding="utf-8") as f:
        uvm_src = (questa_home() / "verilog_src" / "uvm-1.2" / "src").as_posix()
        rc = subprocess.run([tool("vlog"), "-sv", "-work", rel(work), f"+incdir+{uvm_src}", "-f", env["filelist"]],
                            cwd=ROOT, stdout=f, stderr=subprocess.STDOUT, env=QUESTA_ENV).returncode
    text = log.read_text(encoding="utf-8", errors="replace")
    if rc != 0 or re.search(r"Errors: [1-9]", text):
        print(text)
        sys.exit(f"run.py: vlog failed for env {env_name} ({log})")
    return work, (lib if srcs else None)


ERR_RE = re.compile(r"^# (UVM_ERROR|UVM_FATAL) .*?\[([^\]]+)\]", re.M)


def judge(text):
    """Return (finished, n_error, n_fatal, sim_errors, ids) from a vsim log."""
    finished = "UVM Report Summary" in text
    m_err = re.search(r"UVM_ERROR :\s*(\d+)", text)
    m_fat = re.search(r"UVM_FATAL :\s*(\d+)", text)
    n_err = int(m_err.group(1)) if m_err else -1
    n_fat = int(m_fat.group(1)) if m_fat else -1
    sim_errors = re.findall(r"^# \*\* (?:Error|Fatal).*$", text, re.M)
    ids = sorted({m.group(2) for m in ERR_RE.finditer(text)})
    return finished, n_err, n_fat, sim_errors, ids


def kill_tree(proc):
    """vsim starts the simulation kernel as a child process; kill both, not only vsim."""
    if os.name == "nt":
        subprocess.run(["taskkill", "/F", "/T", "/PID", str(proc.pid)], capture_output=True)
    else:
        os.killpg(proc.pid, signal.SIGKILL)
    proc.wait()


def run_limited(cmd, log, limit_s):
    """Run cmd with its output in log; kill it after limit_s seconds of wall-clock time (a zero-time loop
    never reaches the env's +TIMEOUT_CYC watchdog). Return True when the limit was hit."""
    group = {"creationflags": subprocess.CREATE_NEW_PROCESS_GROUP} if os.name == "nt" \
        else {"start_new_session": True}
    with open(log, "w", encoding="utf-8") as f:
        proc = subprocess.Popen(cmd, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT, env=QUESTA_ENV, **group)
        try:
            proc.wait(timeout=limit_s)
            return False
        except subprocess.TimeoutExpired:
            kill_tree(proc)
    with open(log, "a", encoding="utf-8") as f:
        f.write(f"\n# run.py: killed at the wall-clock limit of {limit_s} s (--wall-limit)\n")
    return True


def run_one(test, spec, env, work, lib, config, seed, run_dir, args):
    rdir = run_dir / test / str(seed)
    rdir.mkdir(parents=True)
    log = rdir / "sim.log"
    ucdb = rdir / "cov.ucdb"
    do = "run -all; quit -f"
    cmd = [tool("vsim"), "-c", "-lib", rel(work)]
    # only an env whose top declares GATING_EN (gating: true in sim/tests.yaml) gets the D0/D1 parameter;
    # main() has refused --config d1 for any other env. None = no -GGATING_EN passed (recorded as null).
    gating_en = (1 if config == "d1" else 0) if env.get("gating", False) else None
    if gating_en is not None:
        cmd.append(f"-GGATING_EN={gating_en}")
    cmd += [env["top"], f"+UVM_TESTNAME={test}", "-sv_seed", str(seed)]
    if lib is not None:
        cmd += ["-sv_lib", rel(lib)]
    if args.timeout_cyc:
        cmd.append(f"+TIMEOUT_CYC={args.timeout_cyc}")
    if args.cov:
        cmd.append("-coverage")
        do = f"coverage save -onexit {rel(ucdb)}; " + do
    cmd += ["-do", do]
    killed = run_limited(cmd, log, args.wall_limit)
    finished, n_err, n_fat, sim_errors, ids = judge(log.read_text(encoding="utf-8", errors="replace"))
    passed = finished and n_err == 0 and n_fat == 0 and not sim_errors and not killed

    expect = spec.get("expect", "pass")
    if killed:
        # neither a pass nor the expected failure: the run did not end by itself
        ok = False
        why = f"killed at the wall-clock limit of {args.wall_limit} s (--wall-limit)"
    elif expect == "pass":
        ok = passed
        why = "" if ok else f"UVM_ERROR {n_err}, UVM_FATAL {n_fat}, IDs {ids}" + \
              ("" if finished else ", no UVM report summary") + (f", {sim_errors[0]}" if sim_errors else "")
    else:
        want = set(spec.get("expect_ids", []))
        ok = finished and not passed and not sim_errors and bool(ids) and set(ids) <= want and want <= set(ids)
        why = "" if ok else f"expected a failure with exactly {sorted(want)}, got IDs {ids}" + \
              ("" if finished else ", no UVM report summary")
    return ok, passed, why, log, (ucdb if args.cov else None), gating_en


def write_manifest(run_dir, args, results):
    git = first_line(["git", "rev-parse", "HEAD"])
    dirty = bool(subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True,
                                cwd=ROOT).stdout.strip())
    manifest = {
        "date": datetime.datetime.now().isoformat(timespec="seconds"),
        "git": {"commit": git, "dirty": dirty},
        # the test list decides the expectations; a flipped temporary copy (check_run_py.py) shows up here
        "tests": {"path": shown(args.tests), "sha256": hashlib.sha256(args.tests.read_bytes()).hexdigest()},
        "tools": {
            "questasim": first_line([tool("vsim"), "-version"]),
            "questasim_licence": "full (UVM, randomize, covergroup and DPI-C verified in Task 0, docs/smoke/results.md)",
            "gcc": first_line(["gcc", "--version"]),     # main() has checked that it is on PATH
            "python": sys.version.split()[0],
            "verilator": first_line(["verilator", "--version"]) if shutil.which("verilator")
                         else "not on PATH here (it runs under WSL on the team machine)",
        },
        "command": " ".join(sys.argv),
        "results": results,
    }
    # one manifest per run directory: nothing is appended to a shared file, so concurrent runs cannot race
    path = run_dir / "manifest.yaml"
    path.write_text(yaml.safe_dump(manifest, sort_keys=False), encoding="utf-8")
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--simulator", default="questa", choices=["questa", "xsim"])
    ap.add_argument("--target", help="a test or a suite of sim/tests.yaml")
    ap.add_argument("--config", default="d0", choices=["d0", "d1"])
    ap.add_argument("--seeds", type=int, help="run seeds 1..N of every test (default: the test's seeds key "
                                              "in the test list, else 1)")
    ap.add_argument("--cov", action="store_true", help="save functional coverage (UCDB) per run")
    ap.add_argument("--timeout-cyc", type=int, help="override +TIMEOUT_CYC")
    # a backstop for what +TIMEOUT_CYC cannot catch (a zero-time loop); mac_rand takes about 4 s per seed
    ap.add_argument("--wall-limit", type=int, default=600, metavar="SECONDS",
                    help="kill a vsim run after this wall-clock time and judge it a failure (default 600)")
    ap.add_argument("--list", action="store_true", help="list tests and suites")
    # another test list; sim/selftest/check_run_py.py uses it to flip one expectation in a temporary copy.
    # Paths inside the list (filelist, dpi) stay relative to the repository root.
    ap.add_argument("--tests", type=Path, default=TESTS_YAML, help="test list (default sim/tests.yaml)")
    args = ap.parse_args()

    if args.seeds is not None and args.seeds < 1:
        ap.error("--seeds must be at least 1")
    if args.wall_limit < 1:
        ap.error("--wall-limit must be at least 1 s")

    args.tests = args.tests.resolve()
    db = load_db(args.tests)
    if args.list:
        print("suites:")
        for name, entries in db.get("suites", {}).items():
            n = len(expand_target(db, name, args.tests))
            print(f"  {name:32s} {n:3d} tests = {' + '.join(entries or [])}")
        print("tests:")
        for name, spec in db["tests"].items():
            print(f"  {name:32s} env={spec['env']} expect={spec.get('expect', 'pass')} seeds={spec.get('seeds', 1)}")
        return 0
    if not args.target:
        ap.error("--target is required")
    if args.simulator == "xsim":
        sys.exit("run.py: xsim is not supported yet (Vivado is not installed on the team machine)")

    tests = expand_target(db, args.target, args.tests)
    if not tests:
        sys.exit(f"run.py: '{args.target}' expands to no test, nothing to run")
    if args.config == "d1":
        # without GATING_EN the env would run at its default (D0) while the manifest says d1, and a D0/D1
        # comparison (SC3) would compare D0 with D0; refuse before anything is built
        no_gating = sorted({db["tests"][t]["env"] for t in tests
                            if not db["envs"][db["tests"][t]["env"]].get("gating", False)})
        if no_gating:
            ap.error(f"--config d1 needs an env with 'gating: true' in {shown(args.tests)}; "
                     f"'{args.target}' uses env(s) without it: {', '.join(no_gating)} (run them with --config d0)")
    for name in ("vlog", "vsim"):
        tool(name)
    tool("gcc", " (QuestaSim compiles the DPI export wrapper of uvm_pkg with it for every UVM run, "
                "vsim-7019; it also builds an env's DPI-C library)")
    run_dir = make_run_dir(args.target, args.config)
    questa_ini(run_dir)
    builds = {}
    results = []
    n_bad = 0
    for test in tests:
        spec = db["tests"][test]
        env_name = spec["env"]
        if env_name not in builds:
            print(f"== build {env_name} ({args.config})", flush=True)
            builds[env_name] = build(env_name, db["envs"][env_name], run_dir)
        work, lib = builds[env_name]
        n_seeds = args.seeds if args.seeds is not None else spec.get("seeds", 1)
        for seed in range(1, n_seeds + 1):
            ok, passed, why, log, ucdb, gating_en = run_one(test, spec, db["envs"][env_name], work, lib,
                                                            args.config, seed, run_dir, args)
            expect = spec.get("expect", "pass")
            verdict = ("PASS" if passed else "FAIL") + ("" if expect == "pass" else " (expected fail)")
            print(f"{'ok ' if ok else 'BAD'}  {test:32s} seed {seed}  {verdict}  {why}", flush=True)
            # gating_en: the -GGATING_EN value actually passed to vsim (1, 0, or null when none was passed)
            entry = {"test": test, "config": args.config, "gating_en": gating_en, "seed": seed, "expect": expect,
                     "result": "pass" if passed else "fail", "matches_expectation": ok,
                     "log": log.relative_to(ROOT).as_posix(), "log_sha256": sha256(log)}
            if ucdb is not None:
                entry["cov"] = ucdb.relative_to(ROOT).as_posix()
                entry["cov_sha256"] = sha256(ucdb) if ucdb.is_file() else "missing"
            results.append(entry)
            n_bad += 0 if ok else 1
    manifest = write_manifest(run_dir, args, results)
    print(f"{len(results) - n_bad}/{len(results)} runs as expected; manifest {manifest.relative_to(ROOT).as_posix()}")
    print(f"run directory: {run_dir.relative_to(ROOT).as_posix()}")
    print("RESULT: PASS" if n_bad == 0 else "RESULT: FAIL")
    return 0 if n_bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
