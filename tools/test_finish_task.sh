#!/usr/bin/env bash
# Regression test for tools/finish_task.sh and tools/finish_task.ps1 (support tooling).
# Builds a throw-away origin and two clones under a temp dir and drives the scripts with the regression skipped.
#   (1) rebase conflict, fixed by hand, script rerun -> the commit is pushed
#       (it used to print "Nothing to commit." and exit 0 while the commit stayed local)
#   (2) nothing to commit and nothing to push        -> exit 0, origin unchanged
#   (3) rebase still in progress                     -> exit 1, origin unchanged
#   tools/test_finish_task.sh
# The .ps1 half needs powershell.exe or pwsh; without one it is reported as SKIPPED, not as passed.
set -uo pipefail
repo=$(cd "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fails=0; skipped=""

ok()  { echo "  ok   $1"; }
bad() { echo "  FAIL $1"; fails=$((fails + 1)); }
expect() { if [ "$1" = "$2" ]; then ok "$3"; else bad "$3 (got '$1', want '$2')"; fi; }
winpath() { if command -v cygpath >/dev/null 2>&1; then cygpath -w "$1"; else echo "$1"; fi; }

ps=""
for c in powershell.exe pwsh; do command -v "$c" >/dev/null 2>&1 && { ps=$c; break; }; done

# run_script <flavour sh|ps1> <clone dir>  -> output in $out, exit status in $rc
run_script() {
  if [ "$1" = sh ]; then
    out=$(cd "$2" && SKIP_TESTS=1 bash tools/finish_task.sh "feat: student change" 2>&1); rc=$?
  else
    out=$("$ps" -NoProfile -ExecutionPolicy Bypass -File "$(winpath "$2/tools/finish_task.ps1")" -Message "feat: student change" -SkipTests 2>&1); rc=$?
  fi
}

# setup <dir>: origin with one commit (the scripts and f.txt), clone a = teammate, clone b = student
setup() {
  mkdir -p "$1"
  git init -q --bare -b main "$1/origin.git"
  for who in a b; do
    git clone -q "$1/origin.git" "$1/$who" 2>/dev/null
    git -C "$1/$who" config user.name "$who"
    git -C "$1/$who" config user.email "$who@example.com"
    git -C "$1/$who" config core.autocrlf false
  done
  mkdir "$1/a/tools"
  cp "$repo/tools/finish_task.sh" "$repo/tools/finish_task.ps1" "$1/a/tools/"
  echo base > "$1/a/f.txt"
  git -C "$1/a" add -A && git -C "$1/a" commit -q -m base && git -C "$1/a" push -q origin HEAD:main
  git -C "$1/b" pull -q origin main 2>/dev/null
}

origin_head() { git -C "$1/origin.git" rev-parse main; }

# teammate pushes a change to f.txt, student has a conflicting uncommitted change
make_conflict() {
  echo teammate > "$1/a/f.txt"
  git -C "$1/a" commit -q -am "teammate" && git -C "$1/a" push -q origin HEAD:main
  echo student > "$1/b/f.txt"
}

for flavour in sh ps1; do
  if [ "$flavour" = ps1 ] && [ -z "$ps" ]; then skipped="$skipped ps1"; echo "== finish_task.ps1: SKIPPED (no powershell.exe or pwsh) =="; continue; fi
  echo "== finish_task.$flavour =="
  d="$tmp/$flavour"

  echo " (1) conflict fixed by hand, then rerun"
  setup "$d/s1"; make_conflict "$d/s1"
  run_script "$flavour" "$d/s1/b"
  [ "$rc" -ne 0 ] && ok "first run stops at the rebase conflict (exit $rc)" || bad "first run should fail on the conflict"
  echo merged > "$d/s1/b/f.txt"
  git -C "$d/s1/b" add f.txt && GIT_EDITOR=true git -C "$d/s1/b" rebase --continue >/dev/null 2>&1
  run_script "$flavour" "$d/s1/b"
  expect "$rc" 0 "rerun exits 0"
  expect "$(git -C "$d/s1/b" rev-parse HEAD)" "$(origin_head "$d/s1")" "rerun pushed the local commit (origin/main == HEAD)"

  echo " (2) nothing to commit, nothing to push"
  setup "$d/s2"
  before=$(origin_head "$d/s2")
  run_script "$flavour" "$d/s2/b"
  expect "$rc" 0 "exit 0"
  case "$out" in *"Nothing to commit"*) ok "says there is nothing to do";; *) bad "no 'Nothing to commit' message: $out";; esac
  expect "$(origin_head "$d/s2")" "$before" "origin/main unchanged"

  echo " (3) rebase still in progress"
  setup "$d/s3"; make_conflict "$d/s3"
  run_script "$flavour" "$d/s3/b"                 # leaves the rebase stopped on the conflict
  before=$(origin_head "$d/s3")
  run_script "$flavour" "$d/s3/b"                 # student forgot 'git rebase --continue'
  [ "$rc" -ne 0 ] && ok "refuses to run (exit $rc)" || bad "should refuse while a rebase is in progress"
  case "$out" in *"rebase is still in progress"*) ok "tells the student to finish the rebase";; *) bad "no 'rebase is still in progress' message: $out";; esac
  expect "$(origin_head "$d/s3")" "$before" "origin/main unchanged"
done

echo
if [ "$fails" -eq 0 ]; then echo "RESULT: PASS${skipped:+ (SKIPPED:$skipped)}"; exit 0; fi
echo "RESULT: FAIL ($fails checks)${skipped:+ (SKIPPED:$skipped)}"; exit 1
