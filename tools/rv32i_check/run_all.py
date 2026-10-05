#!/usr/bin/env python3
"""Run every RV32I check: per-instruction tests, then hazard/control + random."""
import runpy, os
os.chdir(os.path.dirname(os.path.abspath(__file__)))
print("=== ISA tests ===");            runpy.run_path("tests_isa.py")
print("\n=== Hazard / control / random ==="); runpy.run_path("tests_hazard.py")
