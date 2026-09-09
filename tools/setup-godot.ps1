# tools/setup-godot.ps1 — idempotent local Godot .NET setup check (PowerShell 5.1 compatible).
#
# Run once per machine (and again after copying a new Godot build into GodotEngine\):
#     powershell -ExecutionPolicy Bypass -File tools/setup-godot.ps1
#
# What it does:
#   1. Verifies GodotEngine\Godot_v*_mono_win64.exe and the matching *_console.exe exist.
#   2. Verifies GodotEngine\GodotSharp\Api\Debug and Api\Release each contain
#      GodotPlugins.dll, GodotSharp.dll, GodotSharpEditor.dll. An incomplete copy makes Godot
#      crash with "Failed to get GodotPlugins initialization function pointer".
#   3. Creates GodotEngine\.gdignore if missing (so the editor never imports the engine folder).
#   4. Creates %USERPROFILE%\bin\godot.cmd (cmd/PowerShell) and %USERPROFILE%\bin\godot
#      (POSIX sh, for Git Bash) wrappers pointing at the console exe; existing files are
#      overwritten only if their content differs.
#   5. Warns if %USERPROFILE%\bin is not on PATH.
# Exit codes: 0 = everything present; 1 = something is missing (details printed).

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
$engineDir = Join-Path $root "GodotEngine"
$problems = @()
$summary = @()

function Write-Ok   { param([string]$m) Write-Host "  [ok]      $m" }
function Write-Miss { param([string]$m) Write-Host "  [MISSING] $m" }
function Write-Warn { param([string]$m) Write-Host "  [warn]    $m" }

Write-Host "setup-godot: repo root = $root"
Write-Host ""

# ---- 1. engine executables ---------------------------------------------------------------
Write-Host "Godot executables ($engineDir):"
$mainExe = $null
$consoleExe = $null
if (Test-Path $engineDir) {
    $mainExe = Get-ChildItem -Path $engineDir -Filter "Godot_v*_mono_win64.exe" -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
    $consoleExe = Get-ChildItem -Path $engineDir -Filter "Godot_v*_mono_win64_console.exe" -File -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending | Select-Object -First 1
}
else {
    $problems += "GodotEngine\ folder not found at $engineDir"
}
if ($null -ne $mainExe) { Write-Ok $mainExe.Name } else { Write-Miss "GodotEngine\Godot_v*_mono_win64.exe"; $problems += "Godot_v*_mono_win64.exe" }
if ($null -ne $consoleExe) { Write-Ok $consoleExe.Name } else { Write-Miss "GodotEngine\Godot_v*_mono_win64_console.exe"; $problems += "Godot_v*_mono_win64_console.exe" }
if ($null -ne $mainExe -and $null -ne $consoleExe) {
    $expectedConsole = $mainExe.BaseName + "_console.exe"
    if ($consoleExe.Name -ne $expectedConsole) {
        Write-Warn "version mismatch: $($mainExe.Name) vs $($consoleExe.Name)"
    }
}
Write-Host ""

# ---- 2. GodotSharp API assemblies --------------------------------------------------------
Write-Host "GodotSharp API assemblies:"
$requiredDlls = @("GodotPlugins.dll", "GodotSharp.dll", "GodotSharpEditor.dll")
foreach ($cfg in @("Debug", "Release")) {
    $apiDir = Join-Path $engineDir "GodotSharp\Api\$cfg"
    foreach ($dll in $requiredDlls) {
        $p = Join-Path $apiDir $dll
        if (Test-Path $p) { Write-Ok "GodotSharp\Api\$cfg\$dll" }
        else { Write-Miss "GodotSharp\Api\$cfg\$dll"; $problems += "GodotSharp\Api\$cfg\$dll" }
    }
}
Write-Host ""

if ($problems.Count -gt 0) {
    Write-Host "setup-godot: FAILED - missing:"
    foreach ($p in $problems) { Write-Host "  - $p" }
    Write-Host ""
    Write-Host "Copy the complete Godot .NET (mono) win64 build into GodotEngine\ (both exes + GodotSharp\)."
    Write-Host "An incomplete copy crashes Godot with 'Failed to get GodotPlugins initialization function pointer'."
    exit 1
}

# ---- 3. .gdignore ------------------------------------------------------------------------
$gdignore = Join-Path $engineDir ".gdignore"
if (Test-Path $gdignore) {
    $summary += ".gdignore: present"
}
else {
    New-Item -ItemType File -Path $gdignore | Out-Null
    $summary += ".gdignore: created"
}

# ---- 4. wrappers in %USERPROFILE%\bin ----------------------------------------------------
function Set-FileIfChanged {
    param([string]$Path, [string]$Content)
    if (Test-Path $Path) {
        $existing = [System.IO.File]::ReadAllText($Path)
        if ($existing -eq $Content) { return "unchanged" }
        [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
        return "updated"
    }
    [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
    return "created"
}

$binDir = Join-Path $env:USERPROFILE "bin"
if (-not (Test-Path $binDir)) {
    New-Item -ItemType Directory -Path $binDir | Out-Null
    $summary += "$binDir`: created"
}

$consolePath = $consoleExe.FullName
# Git Bash form: D:\a\b -> /d/a/b
$drive = $consolePath.Substring(0, 1).ToLower()
$posixPath = "/" + $drive + ($consolePath.Substring(2) -replace "\\", "/")

$cmdContent = "@echo off`r`n`"$consolePath`" %*`r`n"
$shContent = "#!/bin/sh`nexec `"$posixPath`" `"`$@`"`n"

$cmdPath = Join-Path $binDir "godot.cmd"
$shPath = Join-Path $binDir "godot"
$r1 = Set-FileIfChanged -Path $cmdPath -Content $cmdContent
$r2 = Set-FileIfChanged -Path $shPath -Content $shContent
$summary += "$cmdPath`: $r1"
$summary += "$shPath`: $r2"

# ---- 5. PATH check -----------------------------------------------------------------------
$onPath = $false
foreach ($entry in ($env:PATH -split ";")) {
    if ([string]::IsNullOrWhiteSpace($entry)) { continue }
    if ($entry.TrimEnd("\") -ieq $binDir.TrimEnd("\")) { $onPath = $true }
}

# ---- summary -----------------------------------------------------------------------------
Write-Host "Summary:"
Write-Host "  engine:        $($mainExe.FullName)"
Write-Host "  console:       $consolePath"
Write-Host "  posix wrapper: $posixPath"
foreach ($s in $summary) { Write-Host "  $s" }
if ($onPath) {
    Write-Host "  PATH:          $binDir is on PATH"
}
else {
    Write-Warn "$binDir is NOT on PATH - add it (User environment variables) so 'godot' resolves in new shells."
}
Write-Host ""
Write-Host "setup-godot: OK"
exit 0
