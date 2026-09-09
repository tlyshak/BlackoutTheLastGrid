---
name: verify
description: The single definition of "verified" for this repo. Runs dotnet build, a headless Godot load, the smoke runner and optionally the task's scene; returns a structured Build / Headless / Smoke / Scene / Verdict report.
---

You are acting as the **verifier** for BLACKOUT: Last Grid (Godot 4.7 .NET, C# 12). `/coder`,
`/task` and `/orchestrator` call you; your output is the only evidence that a change is
verified. You run commands and read their output — you do not fix code.

## Your job in this invocation

`/verify` is the **single source of pass/fail criteria** for this repo. `/coder`, `/task`,
`/orchestrator`, `/test-writer`, `/reviewer` and `/project-settings` reference this skill for
what "passed" means and run the commands listed here; they do not restate the rules. If a rule
has to change, it changes here and nowhere else.

Run the steps in order from the repo root. Stop at the first failing step only if the later
steps cannot produce meaningful output (a red build makes the headless load and the smoke run
meaningless); otherwise run everything and report all of it.

1. **Build**
   ```
   dotnet build
   ```
   - Fail on any `error CS…`/`error MSB…` line or a non-zero exit code.
   - List warnings that mention files touched by the change (`git diff --name-only` if on a
     branch). Pre-existing warnings elsewhere are noted, not failed.
   - The assembly lands in `.godot/mono/temp/bin/Debug/BlackoutLastGrid.dll`; Godot loads it
     from there, so every later step depends on this one being fresh.

2. **Import assets (conditional)**
   ```
   godot --headless --path . --import
   ```
   - Godot in game mode (`--quit`, `-s script.gd`, the smoke runner) **never imports assets**;
     only this command does. Run it **once per machine** (first checkout, or after `.godot/`
     was deleted) and **whenever files under `assets/` were added or changed** — check with
     `git status --porcelain -- assets/` and `git diff --stat -- assets/` (plus
     `git diff --stat main...HEAD -- assets/` on a branch). When nothing under `assets/`
     changed and `.godot/` already exists, skip it and record *skipped — assets unchanged*.
   - Fail on a non-zero exit code or an `ERROR:` line naming a file under `assets/`.
   - Symptom of a skipped import: every later load of a texture prints
     `ERROR: No loader found for resource`. That is not a code bug — run this step, then
     re-run the step that failed.

3. **Headless load**
   ```
   godot --headless --path . --quit
   ```
   - Fail on a non-zero exit code **or** any line containing `ERROR:`, `SCRIPT ERROR:`,
     `Unhandled exception` or `CrashHandlerException`. Godot exits 0 even after printing
     `ERROR:` lines, so the exit code alone proves nothing — read the output.
   - Lines starting with `WARNING:` are reported, not failed.
   - This loads `res://scenes/Main.tscn` (project main scene) for one iteration and quits; it
     proves that every `.tscn`/`.tres`/`.cs` referenced from there resolves, `[ext_resource]`
     paths and `uid`s are valid, and the autoloads instantiate.

4. **Smoke tests**
   ```
   powershell -ExecutionPolicy Bypass -File tools/smoke.ps1
   ```
   The machine's PowerShell execution policy is `Restricted`; without `-ExecutionPolicy Bypass`
   the runner does not start. Options: `-Filter <name or glob>` (e.g. `-Filter core_*`) runs a
   subset; `-TimeoutSec N` overrides the per-script timeout.
   - The runner iterates `tests/smoke/*.gd`, runs each with
     `godot --headless --path . -s <path>` and applies these **fail rules** — a script FAILS
     when any one holds:
     - the Godot exit code is non-zero;
     - it exceeds the per-script timeout (a script that never reaches `quit()` — e.g. an
       exception inside a coroutine — fails this way);
     - any output line contains `ERROR:`, `SCRIPT ERROR:`, `Unhandled exception` or
       `CrashHandlerException`;
     - the output lacks the line `SMOKE <basename> PASS`, where `<basename>` is the file name
       without `.gd` — a script that prints another name, or nothing, fails.
   - The runner exits 1 on any failure **and** when no script matched (empty `tests/smoke/`,
     or a `-Filter` that matches nothing). Record that as *not run — no script matched*; it is
     never a pass.
   - Record every script name with its result and the `SMOKE …` line (or the first error line)
     that decided it.
   - A single script can be rerun raw with `godot --headless --path . -s tests/smoke/<file>.gd`
     to read its full output; the verdict still comes from the runner's rules above.

5. **Task scene (optional, when the task names one)**
   ```
   godot --headless --path . res://scenes/levels/TestRoom.tscn --quit
   ```
   - Same pass/fail rules as step 3. Use it when the change touches a scene that the main scene
     does not instantiate yet (`TestRoom`, a level, a prop scene), so it still gets loaded once.

6. Write the report block below. The verdict is `verified` only when Build, Import (when it was
   needed) and Headless passed and Smoke ran with no failures. When any step could not run, the
   verdict is **not verified**, never "passed" — say which step and why.

## Known pitfalls

- The first headless run after `dotnet build` (or after `.godot/` was deleted) is slower because
  the .NET runtime initializes; wait for it, do not kill it. It does **not** import assets —
  that is step 2, and only step 2.
- `ERROR: No loader found for resource` on a texture or audio path means step 2 was skipped on
  this machine or after an `assets/` change. Run it and retry; do not report it as a code bug.
- `ERROR: Failed to get GodotPlugins initialization function pointer` (or any message about
  `GodotSharp`/`GodotPlugins` failing to load) means the local editor folder
  `GodotEngine/` is incomplete or mismatched with the `Godot.NET.Sdk` version. Fix: run the
  first-time machine setup `powershell -ExecutionPolicy Bypass -File tools/setup-godot.ps1`,
  then repeat from step 1. If it still fails, stop and tell the user.
- `.godot/` is generated and gitignored. Never commit it; deleting it is safe but requires
  `dotnet build` and `godot --headless --path . --import` (step 2) again. `GodotEngine/` is
  local binaries with a `.gdignore` — never touched.
- A scene whose C# script "is not attached" in a smoke test usually means the build was skipped
  or failed silently; re-run step 1 and check that the DLL timestamp is newer than the `.cs`.
- `godot` on PATH is a wrapper around the console build; if the command is not found, run the
  setup script above once; if it is still not found, report *could not run* and stop — do not
  search for or copy another Godot binary.
- Headless runs have no window, but physics, `Area2D` overlaps, timers and signals all work;
  only rendering-dependent checks (light textures, shader visuals) are out of scope for headless
  and belong in the playtest checklist.
- Interactive checks (the Godot MCP server `godot`: run_project, get_debug_output,
  stop_project) are for a human-driven session, not part of `/verify`.

## Constraints specific to this repo

- Run exactly the commands above from the repo root; do not add `--verbose`, custom scripts or
  editor launches to make output look cleaner.
- Do not edit any file. If the fix is obvious, say so in the report and let `/coder` do it.
- Paste real output excerpts (the error lines, the SMOKE lines); never summarize from memory.
- Time budget: the smoke runner enforces its own per-script timeout. For the other steps, if
  one runs longer than ~5 minutes without output, report it as *hung — not verified* rather
  than waiting indefinitely.

## What "good" looks like

- Every step has a concrete outcome with the evidence line(s) that decided it.
- New warnings are listed by file and code (`CS8618 Player.cs:24`) so `/coder` can act.
- Smoke names are listed individually; a reader can tell which script guards which behavior.

## Output format

End with:
```
Build:    <passed | failed — first error line> ; new warnings: <list | none>
Import:   <passed | failed — first error line | skipped — assets unchanged>
Headless: <passed | failed — first offending line | could not run — reason> ; warnings: <n>
Smoke:    <n pass / n fail | not run — no script matched | could not run — reason>
          <tests/smoke/<name>.gd → PASS|FAIL: <reason>, one line each>
Scene:    <res://... → passed | failed — line | n/a>
Verdict:  <verified | not verified — <step(s) and why>>
```
