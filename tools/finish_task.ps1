<#
.SYNOPSIS
  Finish a task: run the regression, then commit, rebase on the teammate's work and push.

.EXAMPLE
  .\tools\finish_task.ps1 -Message "feat(core): complete RV32I base"
.EXAMPLE
  .\tools\finish_task.ps1 -Message "docs: stall design" -SkipTests   # docs-only changes
#>
param(
  [Parameter(Mandatory = $true)][string]$Message,
  [switch]$SkipTests
)
$ErrorActionPreference = "Stop"
Set-Location (Split-Path -Parent $PSScriptRoot)

if (-not $SkipTests) {
  Write-Host "== Running tools/rv32i_check/run_all.py ==" -ForegroundColor Cyan
  python tools/rv32i_check/run_all.py
  if ($LASTEXITCODE -ne 0) { Write-Host "Regression FAILED - nothing committed." -ForegroundColor Red; exit 1 }
}

git add -A
git diff --cached --quiet
if ($LASTEXITCODE -eq 0) { Write-Host "Nothing to commit." -ForegroundColor Yellow; exit 0 }
git --no-pager diff --cached --stat
git commit -m $Message
if ($LASTEXITCODE -ne 0) { exit 1 }

Write-Host "== Pulling teammate's commits (rebase) ==" -ForegroundColor Cyan
git pull --rebase origin main
if ($LASTEXITCODE -ne 0) {
  Write-Host "Rebase conflict. Fix the files, 'git add' them, 'git rebase --continue', then run this script again." -ForegroundColor Red
  exit 1
}

if (-not $SkipTests) {
  # Re-test after the rebase: the teammate's commits may interact with yours.
  python tools/rv32i_check/run_all.py
  if ($LASTEXITCODE -ne 0) { Write-Host "Regression FAILED after rebase - not pushed. Your commit is local; fix and rerun." -ForegroundColor Red; exit 1 }
}

git push origin HEAD:main
if ($LASTEXITCODE -ne 0) { exit 1 }
Write-Host "Pushed. CI: https://github.com/baonyen1/Mini-NPU-Project/actions" -ForegroundColor Green
