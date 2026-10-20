#!/usr/bin/env python3
"""Run every check and return a CI-friendly exit code.

Exit 0 when every test passes except the ones listed in expected_failures.txt.
Exit 1 when a test fails that is NOT listed (a regression), or when a listed
entry no longer matches any failing test (remove it in the same commit).

expected_failures.txt entries are test names or fnmatch patterns (e.g. randm_*),
one per line, each with a dated reason after '#'."""
import runpy, os, sys, json, shutil, fnmatch
os.chdir(os.path.dirname(os.path.abspath(__file__)))
shutil.rmtree("build", ignore_errors=True)

# (title, script, results file). RefISS is checked first: it is the oracle.
SUITES = [
    ("RefISS hand-value unit check",  "test_refiss.py",   "build/results_refiss.json"),
    ("ISA tests",                     "tests_isa.py",     "build/results_isa.json"),
    ("Hazard / control / random",     "tests_hazard.py",  "build/results_hazard.json"),
    ("RV32M",                         "tests_m.py",       "build/results_m.json"),
    ("Zicsr / counters",              "tests_csr.py",     "build/results_csr.json"),
    ("Zbb / Zifencei",                "tests_zbb.py",     "build/results_zbb.json"),
    ("custom-0 (engine stub)",        "tests_custom.py",  "build/results_custom.json"),
    ("Memory map / SIM MMIO / RVVI",  "tests_mem.py",     "build/results_mem.json"),
]
results = {}
for title, script, res in SUITES:
    print(f"=== {title} ===")
    runpy.run_path(script)
    results.update(json.load(open(res)))
    print()

expected = []
if os.path.exists("expected_failures.txt"):
    for line in open("expected_failures.txt"):
        line = line.split("#", 1)[0].strip()
        if line:
            expected.append(line)

failed    = {k for k, ok in results.items() if not ok}
known     = {k for k in failed if any(fnmatch.fnmatchcase(k, p) for p in expected)}
regressed = sorted(failed - known)
stale     = sorted(p for p in expected if not any(fnmatch.fnmatchcase(k, p) for k in failed))

print("=== VERDICT ===")
print(f"total {len(results)}, passed {len(results) - len(failed)}, known failures {len(known)}")
if known:     print("  known (expected_failures.txt):", " ".join(sorted(known)[:12]), "..." if len(known) > 12 else "")
if regressed: print("  REGRESSION - unexpected failures:", " ".join(regressed))
if stale:     print("  NOW PASSING - remove from expected_failures.txt:", " ".join(stale))
ok = not regressed and not stale
print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
