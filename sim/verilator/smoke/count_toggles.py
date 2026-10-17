#!/usr/bin/env python3
"""S4: count toggles of a VCD signal per clock cycle of `clk` (period 10 time units).
usage: count_toggles.py icg.vcd gclk [first_cycle last_cycle]"""
import sys


def parse(path, name):
    ids, changes, t = {}, [], 0
    with open(path) as f:
        for line in f:
            p = line.split()
            if not p:
                continue
            if p[0] == "$var" and p[4] == name and not ids.get(name):
                ids[name] = p[3]
            elif p[0].startswith("#"):
                t = int(p[0][1:])
            elif name in ids and len(p[0]) >= 2 and p[0][1:] == ids[name] and p[0][0] in "01xz":
                changes.append((t, p[0][0]))
    return changes


def main():
    path, name = sys.argv[1], sys.argv[2]
    lo = int(sys.argv[3]) if len(sys.argv) > 3 else 11
    hi = int(sys.argv[4]) if len(sys.argv) > 4 else 19
    ch = parse(path, name)
    per = {}
    prev = None
    for t, v in ch:
        if prev is not None and v != prev:
            per[t // 10] = per.get(t // 10, 0) + 1
        prev = v
    inside = sum(per.get(c, 0) for c in range(lo, hi + 1))
    # Cycle 0 is start-up; cycles lo-1 and hi+1 hold the last fall / first rise
    # around the gated window, so they carry 1 toggle each. All others carry 2.
    skip = {0, lo - 1, hi + 1}
    steady = {c: n for c, n in per.items() if not lo <= c <= hi and c not in skip}
    edges = [per.get(c, 0) for c in (lo - 1, hi + 1)]
    print(f"{name}: toggles in cycles {lo}..{hi} = {inside}")
    print(f"{name}: toggles/cycle in steady cycles = {sorted(set(steady.values()))}")
    print(f"{name}: toggles in boundary cycles {lo - 1},{hi + 1} = {edges}")
    ok = inside == 0 and set(steady.values()) == {2} and edges == [1, 1]
    print("RESULT:", "PASS" if ok else "FAIL")
    sys.exit(0 if ok else 1)


if __name__ == "__main__":
    main()
