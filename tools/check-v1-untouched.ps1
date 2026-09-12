# tools/check-v1-untouched.ps1 — the git gate of the v2 line (T-V2-01, GAME_DESIGN §6a).
#
# The v2 scene set under scenes/v2/ must leave the v1 build byte-identical: this script diffs the
# v1 files against a base ref (default `main`) and fails when any of them differs. Run it from the
# repo root on a v2 branch, next to tools/smoke.ps1 (which cannot see git):
#     powershell -ExecutionPolicy Bypass -File tools/check-v1-untouched.ps1 [-Base <ref>]
#
# Three rules:
#   1. the v1 files listed below must not differ from the base in any way (added lines included);
#   2. every script under scripts/ that exists on the base is frozen too, except the few the plan
#      lets the v2 line extend (GameSettings, SettingsMenu, Exposition, Guard, SectionBackdrop) —
#      new scripts may be added, the shared ones may not drift by accident;
#   3. the author's art under assets/art/v2/ may be *added* on a branch (the derivative agents
#      commit their inputs there) but never modified, deleted or renamed — the asset policy.
#
# Exit codes: 0 = nothing differs; 1 = at least one v1 file differs (listed); 2 = git failed
# (not a repo, unknown base ref).

param(
    [string]$Base = "main"
)

$ErrorActionPreference = "Stop"

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# The v1 build: the scenes a v2 twin exists for, the entry points, the levels that share the
# actor scenes, and the project files the plan forbids touching.
$v1Files = @(
    "scenes/Main.tscn",
    "scenes/levels/Level00_Prologue.tscn",
    "scripts/levels/Level00_Prologue.cs",
    "scenes/player/Player.tscn",
    "scenes/enemies/Guard.tscn",
    "scenes/actors/Companion.tscn",
    "scenes/actors/CharacterRig.tscn",
    "scenes/ui/MainMenu.tscn",
    "scenes/ui/Exposition.tscn",
    "scenes/levels/TestRoom.tscn",
    "scenes/levels/TestMine.tscn",
    "scenes/levels/Level01_District.tscn",
    "project.godot",
    "BlackoutLastGrid.csproj"
)
$artDir = "assets/art/v2"
# The shared scripts the plan allows the v2 line to touch (additively); everything else under
# scripts/ that the base already has joins the frozen list below.
$scriptsDir = "scripts"
$allowedScripts = @(
    "scripts/core/GameSettings.cs",
    "scripts/ui/SettingsMenu.cs",
    "scripts/ui/Exposition.cs",
    "scripts/enemies/Guard.cs",
    "scripts/levels/SectionBackdrop.cs"
)

& git rev-parse --verify --quiet "$Base^{commit}" | Out-Null
if ($LASTEXITCODE -ne 0) {
    Write-Host "V1-UNTOUCHED: base ref '$Base' is not a commit in this repository"
    exit 2
}

$baseScripts = & git ls-tree -r --name-only $Base -- $scriptsDir
if ($LASTEXITCODE -ne 0) {
    Write-Host "V1-UNTOUCHED: git ls-tree failed on $scriptsDir"
    exit 2
}
foreach ($script in @($baseScripts)) {
    if ([string]::IsNullOrWhiteSpace($script)) { continue }
    if ($allowedScripts -contains $script) { continue }
    if ($v1Files -contains $script) { continue }
    $v1Files += $script
}

$differing = @()

$v1Diff = & git diff --name-only $Base -- @v1Files
if ($LASTEXITCODE -ne 0) {
    Write-Host "V1-UNTOUCHED: git diff failed"
    exit 2
}
foreach ($line in @($v1Diff)) {
    if (-not [string]::IsNullOrWhiteSpace($line)) { $differing += "$line (v1 file changed)" }
}

# Art: additions are allowed (--diff-filter excludes A), everything else is a violation.
$artDiff = & git diff --name-only --diff-filter=MDRTC $Base -- "$artDir/*.svg" "$artDir/**/*.svg"
if ($LASTEXITCODE -ne 0) {
    Write-Host "V1-UNTOUCHED: git diff failed on $artDir"
    exit 2
}
foreach ($line in @($artDiff)) {
    if (-not [string]::IsNullOrWhiteSpace($line)) { $differing += "$line (art modified, deleted or renamed)" }
}

# Uncommitted edits count too: a dirty v1 file is a change waiting to be committed.
$dirty = & git status --porcelain -- @v1Files
foreach ($line in @($dirty)) {
    if ([string]::IsNullOrWhiteSpace($line)) { continue }
    $path = $line.Substring(3).Trim()
    if (-not ($differing -like "$path *")) { $differing += "$path (uncommitted change)" }
}

if ($differing.Count -eq 0) {
    Write-Host "V1-UNTOUCHED PASS: $($v1Files.Count) v1 files and $artDir equal '$Base'"
    exit 0
}

Write-Host "V1-UNTOUCHED FAIL: $($differing.Count) file(s) differ from '$Base':"
foreach ($d in $differing) { Write-Host "  $d" }
exit 1
