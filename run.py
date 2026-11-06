#!/usr/bin/env python3
"""run.py - the single entry point for simulations (Phase 2 Task 15 [support]).

    python run.py --target mac_directed                 # a suite from sim/tests.yaml, D0
    python run.py --target mac_w1c --config d1          # one test, D1 (GATING_EN = 1)
    python run.py --target mac_directed --seeds 3 --cov # seeds 1..3, functional coverage saved (UCDB)
    python run.py --list                                # the tests and suites known to sim/tests.yaml

Per (env, config) it builds once: the DPI-C library from the env's C sources with gcc, then vlog of the
env's compile list. Then one vsim per test and seed. Logs: out/<date>/<config>/<test>/<seed>/sim.log.
A run passes when the log has the UVM report summary, UVM_ERROR : 0, UVM_FATAL : 0 and no simulator
error. An expected-fail test (sim/tests.yaml) must fail, and only with the IDs it lists. The exit code
is 0 only if every run matched its expectation. out/<date>/manifest.yaml records the tools and the
git revision of the run.

Only QuestaSim is supported for now: Vivado (xsim) is no longer installed on the team machine
(CLAUDE.md section 10). vlog, vsim and gcc must be on PATH (QuestaSim: C:\\questasim64_10.7c\\win64).
"""
import argparse
import datetime
import os
import platform
import re
import shutil
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(__file__).resolve().parent
TESTS_YAML = ROOT / "sim" / "tests.yaml"


def load_db():
    with open(TESTS_YAML, encoding="utf-8") as f:
        return yaml.safe_load(f)


def expand_target(db, target):
    if target in db.get("suites", {}):
        return list(db["suites"][target])
    if target in db.get("tests", {}):
        return [target]
    sys.exit(f"run.py: '{target}' is neither a test nor a suite in {TESTS_YAML.relative_to(ROOT)}")


def tool(name):
    path = shutil.which(name)
    if path is None:
        sys.exit(f"run.py: '{name}' is not on PATH")
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
    build directory maps it to the precompiled uvm-1.2 instead; vlog and vsim find it through $MODELSIM."""
    home = questa_home()
    text = (home / "modelsim.ini").read_text(encoding="utf-8", errors="replace")
    text, n = re.subn(r"^mtiUvm\s*=.*$", f"mtiUvm = {(home / 'uvm-1.2').as_posix()}", text, flags=re.M)
    if n != 1:
        sys.exit("run.py: no mtiUvm line in the QuestaSim modelsim.ini")
    ini = bdir / "modelsim.ini"
    ini.write_text(text, encoding="utf-8")
    QUESTA_ENV["MODELSIM"] = str(ini)


def build(env_name, env, config, out_dir):
    """Build the DPI library and compile the env once; return (work dir, library path without suffix)."""
    bdir = out_dir / config / f"build_{env_name}"
    if bdir.exists():
        shutil.rmtree(bdir)
    bdir.mkdir(parents=True)
    questa_ini(bdir)
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


def run_one(test, spec, env, work, lib, config, seed, out_dir, args):
    rdir = out_dir / config / test / str(seed)
    rdir.mkdir(parents=True, exist_ok=True)
    log = rdir / "sim.log"
    do = "run -all; quit -f"
    cmd = [tool("vsim"), "-c", "-lib", rel(work), f"-GGATING_EN={1 if config == 'd1' else 0}",
           env["top"], f"+UVM_TESTNAME={test}", "-sv_seed", str(seed)]
    if lib is not None:
        cmd += ["-sv_lib", rel(lib)]
    if args.timeout_cyc:
        cmd.append(f"+TIMEOUT_CYC={args.timeout_cyc}")
    if args.cov:
        cmd.append("-coverage")
        do = f"coverage save -onexit {rel(rdir / 'cov.ucdb')}; " + do
    cmd += ["-do", do]
    with open(log, "w", encoding="utf-8") as f:
        subprocess.run(cmd, cwd=ROOT, stdout=f, stderr=subprocess.STDOUT, env=QUESTA_ENV)
    finished, n_err, n_fat, sim_errors, ids = judge(log.read_text(encoding="utf-8", errors="replace"))
    passed = finished and n_err == 0 and n_fat == 0 and not sim_errors

    expect = spec.get("expect", "pass")
    if expect == "pass":
        ok = passed
        why = "" if ok else f"UVM_ERROR {n_err}, UVM_FATAL {n_fat}, IDs {ids}" + \
              ("" if finished else ", no UVM report summary") + (f", {sim_errors[0]}" if sim_errors else "")
    else:
        want = set(spec.get("expect_ids", []))
        ok = finished and not passed and not sim_errors and bool(ids) and set(ids) <= want and want <= set(ids)
        why = "" if ok else f"expected a failure with exactly {sorted(want)}, got IDs {ids}" + \
              ("" if finished else ", no UVM report summary")
    return ok, passed, why, log


def write_manifest(out_dir, args, results):
    git = first_line(["git", "rev-parse", "HEAD"])
    dirty = bool(subprocess.run(["git", "status", "--porcelain"], capture_output=True, text=True,
                                cwd=ROOT).stdout.strip())
    manifest = {
        "date": datetime.datetime.now().isoformat(timespec="seconds"),
        "git": {"commit": git, "dirty": dirty},
        "tools": {
            "questasim": first_line([tool("vsim"), "-version"]),
            "questasim_licence": "full (UVM, randomize, covergroup and DPI-C verified in Task 0, docs/smoke/results.md)",
            "gcc": first_line([tool("gcc"), "--version"]),
            "python": sys.version.split()[0],
            "verilator": first_line(["verilator", "--version"]) if shutil.which("verilator")
                         else "not on PATH here (it runs under WSL on the team machine)",
        },
        "command": " ".join(sys.argv),
        "results": results,
    }
    path = out_dir / "manifest.yaml"
    old = yaml.safe_load(path.read_text(encoding="utf-8")) if path.exists() else None
    runs = (old.get("runs", []) if isinstance(old, dict) else []) + [manifest]
    path.write_text(yaml.safe_dump({"runs": runs}, sort_keys=False), encoding="utf-8")
    return path


def main():
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--simulator", default="questa", choices=["questa", "xsim"])
    ap.add_argument("--target", help="a test or a suite of sim/tests.yaml")
    ap.add_argument("--config", default="d0", choices=["d0", "d1"])
    ap.add_argument("--seeds", type=int, default=1, help="run seeds 1..N")
    ap.add_argument("--cov", action="store_true", help="save functional coverage (UCDB) per run")
    ap.add_argument("--timeout-cyc", type=int, help="override +TIMEOUT_CYC")
    ap.add_argument("--list", action="store_true", help="list tests and suites")
    args = ap.parse_args()

    db = load_db()
    if args.list:
        print("suites:", ", ".join(db.get("suites", {})))
        for name, spec in db["tests"].items():
            print(f"  {name:32s} env={spec['env']} expect={spec.get('expect', 'pass')}")
        return 0
    if not args.target:
        ap.error("--target is required")
    if args.simulator == "xsim":
        sys.exit("run.py: xsim is not supported yet (Vivado is not installed on the team machine)")

    tests = expand_target(db, args.target)
    out_dir = ROOT / "out" / datetime.date.today().isoformat()
    builds = {}
    results = []
    n_bad = 0
    for test in tests:
        spec = db["tests"][test]
        env_name = spec["env"]
        if env_name not in builds:
            print(f"== build {env_name} ({args.config})", flush=True)
            builds[env_name] = build(env_name, db["envs"][env_name], args.config, out_dir)
        work, lib = builds[env_name]
        for seed in range(1, args.seeds + 1):
            ok, passed, why, log = run_one(test, spec, db["envs"][env_name], work, lib,
                                           args.config, seed, out_dir, args)
            expect = spec.get("expect", "pass")
            verdict = ("PASS" if passed else "FAIL") + ("" if expect == "pass" else " (expected fail)")
            print(f"{'ok ' if ok else 'BAD'}  {test:32s} seed {seed}  {verdict}  {why}", flush=True)
            results.append({"test": test, "config": args.config, "seed": seed, "expect": expect,
                            "result": "pass" if passed else "fail", "matches_expectation": ok,
                            "log": log.relative_to(ROOT).as_posix()})
            n_bad += 0 if ok else 1
    manifest = write_manifest(out_dir, args, results)
    print(f"{len(results) - n_bad}/{len(results)} runs as expected; manifest {manifest.relative_to(ROOT).as_posix()}")
    print("RESULT: PASS" if n_bad == 0 else "RESULT: FAIL")
    return 0 if n_bad == 0 else 1


if __name__ == "__main__":
    sys.exit(main())
