#!/usr/bin/env python3
"""Run every RV32I check and return a CI-friendly exit code.

Exit 0 when every test passes except the ones listed in expected_failures.txt.
Exit 1 when a test fails that is NOT listed (a regression), or when a listed test
now passes (remove it from expected_failures.txt in the same commit)."""
import runpy, os, sys, json, shutil
os.chdir(os.path.dirname(os.path.abspath(__file__)))
shutil.rmtree("build", ignore_errors=True)

print("=== ISA tests ===");                    runpy.run_path("tests_isa.py")
print("\n=== Hazard / control / random ===");  runpy.run_path("tests_hazard.py")

results = {}
for f in ("build/results_isa.json", "build/results_hazard.json"):
    results.update(json.load(open(f)))
expected = set()
if os.path.exists("expected_failures.txt"):
    for line in open("expected_failures.txt"):
        line = line.split("#", 1)[0].strip()
        if line:
            expected.add(line)

failed     = {k for k, ok in results.items() if not ok}
regressed  = sorted(failed - expected)
now_pass   = sorted(expected - failed)
known      = sorted(failed & expected)

print("\n=== VERDICT ===")
print(f"total {len(results)}, passed {len(results) - len(failed)}, "
      f"known failures {len(known)}")
if known:     print("  known (expected_failures.txt):", " ".join(known))
if regressed: print("  REGRESSION - unexpected failures:", " ".join(regressed))
if now_pass:  print("  NOW PASSING - remove from expected_failures.txt:", " ".join(now_pass))
ok = not regressed and not now_pass
print("RESULT:", "PASS" if ok else "FAIL")
sys.exit(0 if ok else 1)
