# tools/smoke.ps1 — headless smoke-test runner (PowerShell 5.1 compatible).
#
# Runs every tests/smoke/*.gd script (GDScript, `extends SceneTree`) headless, one Godot
# process per script, and aggregates the results.
#
# Canonical command (the machine's execution policy is Restricted, so -ExecutionPolicy Bypass
# is required):
#     powershell -ExecutionPolicy Bypass -File tools/smoke.ps1 [-Filter <glob>] [-TimeoutSec <n>]
# Examples:
#     powershell -ExecutionPolicy Bypass -File tools/smoke.ps1
#     powershell -ExecutionPolicy Bypass -File tools/smoke.ps1 -Filter core_*
#     powershell -ExecutionPolicy Bypass -File tools/smoke.ps1 -Filter core_gamestate.gd -TimeoutSec 30
#
# Godot executable resolution order:
#     1. <repo>\GodotEngine\Godot_v*_mono_win64_console.exe
#     2. $env:GODOT
#     3. `godot` on PATH
#
# A script PASSES only if ALL of the following hold:
#     - the Godot process exited with code 0
#     - it finished within -TimeoutSec (default 60 s); on timeout the whole process tree is
#       killed (taskkill /T) and the script is reported TIMEOUT
#     - stdout/stderr contain the exact line `SMOKE <name> PASS`, where <name> is the script's
#       file name without `.gd` (so a script cannot pass by printing another script's name)
#     - stdout/stderr contain none of: `ERROR:`, `SCRIPT ERROR:`, `Unhandled exception`,
#       `CrashHandlerException`
# Otherwise the script FAILS with a one-word reason: EXIT <n> / TIMEOUT / ERROR-LINES / NO-PASS-LINE.
#
# Exit codes: 0 = every matched script passed; 1 = at least one failed OR no script matched
# (a test that did not run is NOT verified); 2 = Godot executable not found.
#
# Run `dotnet build` once before the first run (the .NET assembly must exist for autoloads).

param(
    [string]$Filter = "*",
    [int]$TimeoutSec = 60
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$smokeDir = Join-Path $root "tests\smoke"

# Normalise the filter: accept both `core_gamestate.gd` and `core_*`.
$pattern = $Filter
if ($pattern -like "*.gd") { $pattern = $pattern.Substring(0, $pattern.Length - 3) }
if ([string]::IsNullOrWhiteSpace($pattern)) { $pattern = "*" }

# ---- resolve Godot executable ------------------------------------------------------------
function Resolve-Godot {
    param([string]$RepoRoot)
    $engineDir = Join-Path $RepoRoot "GodotEngine"
    if (Test-Path $engineDir) {
        $local = Get-ChildItem -Path $engineDir -Filter "Godot_v*_mono_win64_console.exe" -File -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($null -ne $local) { return $local.FullName }
    }
    if (-not [string]::IsNullOrWhiteSpace($env:GODOT) -and (Test-Path $env:GODOT)) {
        return (Resolve-Path $env:GODOT).Path
    }
    $cmd = Get-Command godot -ErrorAction SilentlyContinue
    if ($null -ne $cmd) { return $cmd.Source }
    return $null
}

$godot = Resolve-Godot -RepoRoot $root
if ($null -eq $godot) {
    Write-Host "SMOKE: Godot executable not found. Expected one of:"
    Write-Host "  - $root\GodotEngine\Godot_v*_mono_win64_console.exe (run tools/setup-godot.ps1)"
    Write-Host "  - `$env:GODOT pointing to the Godot .NET executable"
    Write-Host "  - 'godot' on PATH"
    exit 2
}

# ---- collect scripts ---------------------------------------------------------------------
$files = @()
if (Test-Path $smokeDir) {
    $files = @(Get-ChildItem -Path $smokeDir -Filter "$pattern.gd" -File | Sort-Object Name)
}
if ($files.Count -eq 0) {
    Write-Host "SMOKE: no scripts in tests/smoke matched '$Filter' - nothing was verified"
    Write-Host "SMOKE SUMMARY: 0 passed, 0 failed"
    exit 1
}

Write-Host "SMOKE: godot = $godot"
Write-Host "SMOKE: $($files.Count) script(s), timeout ${TimeoutSec}s each"
Write-Host ""

$errorPatterns = @("ERROR:", "SCRIPT ERROR:", "Unhandled exception", "CrashHandlerException")
$failed = @()
$passedCount = 0

foreach ($f in $files) {
    $name = [System.IO.Path]::GetFileNameWithoutExtension($f.Name)
    $rel = "tests/smoke/$($f.Name)"
    Write-Host "--- $rel"

    $tmpOut = [System.IO.Path]::GetTempFileName()
    $tmpErr = [System.IO.Path]::GetTempFileName()
    $timedOut = $false
    $exitCode = -1

    try {
        $godotArgs = @("--headless", "--path", "`"$root`"", "-s", $rel)
        $proc = Start-Process -FilePath $godot -ArgumentList $godotArgs -PassThru -NoNewWindow `
            -RedirectStandardOutput $tmpOut -RedirectStandardError $tmpErr
        # Touch .Handle so ExitCode is populated after exit (Start-Process -PassThru quirk).
        $null = $proc.Handle
        if (-not $proc.WaitForExit($TimeoutSec * 1000)) {
            $timedOut = $true
            # /T kills the child engine process spawned by the console launcher.
            & taskkill /PID $proc.Id /T /F | Out-Null
            try { $proc.WaitForExit(5000) | Out-Null } catch { }
        }
        else {
            $proc.WaitForExit()   # flush redirected streams
            if ($null -ne $proc.ExitCode) { $exitCode = [int]$proc.ExitCode } else { $exitCode = -1 }
        }
    }
    catch {
        Write-Host "  ERROR: failed to start Godot: $($_.Exception.Message)"
    }

    $outText = ""
    if (Test-Path $tmpOut) { $outText += (Get-Content -Path $tmpOut -Raw -ErrorAction SilentlyContinue) }
    if (Test-Path $tmpErr) { $outText += "`n" + (Get-Content -Path $tmpErr -Raw -ErrorAction SilentlyContinue) }
    Remove-Item -Path $tmpOut, $tmpErr -Force -ErrorAction SilentlyContinue

    $lines = @()
    if ($null -ne $outText) { $lines = @($outText -split "`r?`n") }

    # Echo the interesting lines; skip Godot's leading "[...]" noise (e.g. "[.NET] ...").
    foreach ($line in $lines) {
        if ($line -match "^\s*\[.*\]") { continue }
        if ($line -match "^SMOKE |ERROR:|SCRIPT ERROR:|Unhandled exception|CrashHandlerException") {
            Write-Host "  $line"
        }
    }

    $hasPassLine = $false
    $hasErrorLine = $false
    foreach ($line in $lines) {
        if ($line -match ("^SMOKE " + [regex]::Escape($name) + " PASS\s*$")) { $hasPassLine = $true }
        foreach ($p in $errorPatterns) {
            if ($line.Contains($p)) { $hasErrorLine = $true }
        }
    }

    $reason = $null
    if ($timedOut) { $reason = "TIMEOUT" }
    elseif ($exitCode -ne 0) { $reason = "EXIT $exitCode" }
    elseif ($hasErrorLine) { $reason = "ERROR-LINES" }
    elseif (-not $hasPassLine) { $reason = "NO-PASS-LINE" }

    if ($null -eq $reason) {
        $passedCount++
        Write-Host "  => PASS"
    }
    else {
        $failed += "$($f.Name) ($reason)"
        Write-Host "  => FAIL ($reason)"
    }
    Write-Host ""
}

Write-Host ("SMOKE SUMMARY: {0} passed, {1} failed" -f $passedCount, $failed.Count)
if ($failed.Count -gt 0) {
    foreach ($x in $failed) { Write-Host "  FAIL $x" }
    exit 1
}
exit 0
