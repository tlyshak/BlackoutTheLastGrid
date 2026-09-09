# Runs every tests/smoke/*.gd headless. Each script prints "SMOKE <name> PASS|FAIL ..."
# and exits with 0/1. This runner exits non-zero if any script fails or crashes.
# Usage: powershell -File tools/smoke.ps1 [-Filter core_*]
param([string]$Filter = "*")

$root = Split-Path -Parent $PSScriptRoot
$files = Get-ChildItem -Path (Join-Path $root "tests\smoke") -Filter "$Filter.gd" -File | Sort-Object Name
if ($files.Count -eq 0) { Write-Host "SMOKE: no tests matched '$Filter'"; exit 0 }

$failed = @()
foreach ($f in $files) {
    $rel = "tests/smoke/$($f.Name)"
    $out = & godot --headless --path $root -s $rel 2>&1 | Out-String
    $lines = $out -split "`r?`n" | Where-Object { $_ -match "^SMOKE |ERROR|SCRIPT ERROR" }
    $lines | ForEach-Object { Write-Host $_ }
    if ($LASTEXITCODE -ne 0 -or $out -notmatch "SMOKE \S+ PASS") { $failed += $f.Name }
}
Write-Host ""
Write-Host ("SMOKE SUMMARY: {0} passed, {1} failed" -f ($files.Count - $failed.Count), $failed.Count)
if ($failed.Count -gt 0) { $failed | ForEach-Object { Write-Host "  FAIL $_" }; exit 1 }
exit 0
