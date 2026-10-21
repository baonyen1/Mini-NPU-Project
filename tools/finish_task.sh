#!/usr/bin/env bash
# Finish a task: run the regression, then commit, rebase on the teammate's work and push.
#   tools/finish_task.sh "feat(core): complete RV32I base"
#   SKIP_TESTS=1 tools/finish_task.sh "docs: stall design"     # docs-only changes
set -euo pipefail
cd "$(dirname "$0")/.."
msg="${1:?usage: tools/finish_task.sh \"commit message\"}"
run_tests() { [ "${SKIP_TESTS:-0}" = 1 ] || python3 tools/rv32i_check/run_all.py; }

if [ -d "$(git rev-parse --git-path rebase-merge)" ] || [ -d "$(git rev-parse --git-path rebase-apply)" ]; then
  echo "A rebase is still in progress: finish it (git add, git rebase --continue), then rerun."; exit 1
fi
run_tests || { echo "Regression FAILED - nothing committed."; exit 1; }
git add -A
if git diff --cached --quiet; then
  # Nothing new to commit. After a resolved rebase conflict the commit is still local: carry on and push it.
  git fetch origin
  ahead=$(git rev-list --count origin/main..HEAD)
  [ "$ahead" -gt 0 ] || { echo "Nothing to commit or push."; exit 0; }
  echo "Nothing new to commit; $ahead commit(s) not on origin/main yet - rebasing and pushing."
else
  git --no-pager diff --cached --stat
  git commit -m "$msg"
fi
git pull --rebase origin main || { echo "Rebase conflict: fix, git add, git rebase --continue, rerun."; exit 1; }
run_tests || { echo "Regression FAILED after rebase - not pushed."; exit 1; }
git push origin HEAD:main
echo "Pushed. CI: https://github.com/baonyen1/Mini-NPU-Project/actions"
