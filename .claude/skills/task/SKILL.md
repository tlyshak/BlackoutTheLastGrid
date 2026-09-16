---
name: task
description: Run the CLAUDE.md work cycle for exactly one docs/TASKS.md task end to end — status, branch, optional plan, implementation, /verify, smoke tests, one /reviewer round with a fix pass (coder + test-writer) and a post-fix /verify, playtest note, done-note, one commit. Never pushes or starts the next task.
---

You are acting as the **task runner** for BLACKOUT: Last Grid (Godot 4.7 .NET, C# 12). Usage:
`/task T-02` (or `/task` for the first `todo`). You own the whole cycle for **one** task and
delegate the specialised parts to `/architect`, `/coder`, `/verify`, `/test-writer`,
`/reviewer` and `/project-settings` — their rules apply inside this run. Steps 5–11 are the
same fixed pipeline `/orchestrator` runs
(`coder → verify → test-writer → reviewer → coder → test-writer → verify`); on top of it
`/task` owns the branch, the TASKS.md status and the commit.

## Your job in this invocation

1. **Read the sources of truth** — `CLAUDE.md` in full, the task block in `docs/TASKS.md`, and
   the `docs/GAME_DESIGN.md` section it references (§3 for levels, §4 for mechanics, §7 for the
   technical plan). Pick the task:
   - Id given → that task. Id omitted → the first heading with status `todo`, top to bottom.
   - Status `blocked` → stop; the author owes a decision. Quote the open question and ask.
   - Any other task already `in_progress` → stop and ask whether to resume it or override.
   - Status `done` → stop; say so. Nothing is re-done without explicit instruction.
   - Every clause of "Готово, коли:" is the acceptance criterion for this run; write it down.
2. **Preconditions** — `git status --porcelain` must be empty and the current branch must be
   `main` unless the user said otherwise. Then:
   ```
   git checkout -b task/<id-lowercase>-<short-name>
   ```
   `<short-name>` is 2–3 ASCII words from the title, e.g. `task/t-02-player-movement`,
   `task/t-02b-basic-combat`, `task/t-05-outlet-power-panel`.
3. **Set `in_progress`** — edit only the trailing status on the heading line
   (`### T-02 · … · \`todo\`` → `\`in_progress\``). Do not reflow the rest of the file. `/task`
   is the **only** skill that edits a TASKS.md status or done-note: `/coder` never does, and
   `/orchestrator` only reports the status to set.
4. **Plan — always** — run `/architect` with slug `t02-player-movement` (id without the dash,
   plus the short name) for every task. A small task gets a short plan (Goal, Scope, Design-doc
   conformance, Scene & signal contract when a scene is touched — from `/scene-design` —,
   File-level change list, Acceptance criteria, Test strategy, Playtest, empty Review findings);
   a large one gets the full template. The plan is what `/orchestrator` drives and what
   `/reviewer` judges against, so there is no "proceed without a plan" path.
5. **Run `/orchestrator <slug>` — for every task, no exceptions.** It executes the fixed
   pipeline `coder → verify → test-writer → reviewer → coder → test-writer → verify` against the
   plan and hands back its final report (per-step outcomes, the `/verify` block, the review
   verdict with blocker/should-fix counts, the Playtest checklist, the TASKS.md status to set,
   open items). `/task` does not re-implement any of those steps: the retry budget, the
   escalation rules and the "exactly one review + one fix pass" rule are the orchestrator's.
   Reminders that still apply inside the run: `/coder` follows CLAUDE.md conventions (one script
   per scene, signals + `[Export]`, `_PhysicsProcess` for movement/hits, `PH_*` placeholders,
   `StateMachine` + `State` children), any `project.godot`/InputMap/autoload/`.csproj` edit goes
   through `/project-settings`, and out-of-scope findings become `backlog` entries in
   `docs/TASKS.md`, not code. If the orchestrator **escalates** (needed addon/NuGet, an
   unsanctioned project-settings change, an asset that would need creating, a task-vs-
   GAME_DESIGN.md conflict, a `/verify` that stays red), stop here: no `done`, no commit —
   report the escalation to the author.
6. **Set `done` and write the note** — `done` only after the post-fix `/verify` (inside step 5) is
    green **and** the Round 1 verdict is `Ship: yes` — or `Ship: no` where every open item is
    one the author explicitly deferred (those go under Не зроблено). Otherwise leave
    `in_progress` and report. Change the heading status to `done` and append under the task's
    bullets, in the same shape T-01 uses (Ukrainian is fine here; the Зроблено / Не зроблено
    lines come from the coder's report, the playtest from `/test-writer`, the review line from
    the journal):
    ```
    - **Зроблено:** <1–2 lines: files/scenes/scripts, what works, how it was verified>
    - **Не зроблено:** <what was deferred and why, or "—">
    - **Рев'ю:** Round 1 — Ship: <yes|no>, закрито <n> Blockers / <n> Should-fix, відкрито: <…|—>
    - **Плейтест:** 1) відкрити scenes/levels/Level00_Sections.tscn як головну (F6) … 2) …
    ```
7. **One commit** — the fix pass is part of this same task commit: never commit before steps
    8–11 have run. Stage the task's files only (`git add -A`, then read `git status` and
    unstage anything unrelated; `.godot/`, `bin/`, `obj/` never appear). Message:
    ```
    feat(<area>): <what> [T-xx]

    - <file or scene>: <one-line intent>
    - ...
    project.godot: added <…> because <…>      # only if it changed — per /project-settings
    Verify: build passed, headless passed, smoke <n>/<n>

    Co-Authored-By: Claude Fable 5.1 <noreply@anthropic.com>
    ```
    `<area>` is the scenes folder the task lives in (`player`, `combat`, `props`, `ui`,
    `enemies`, `levels`, `core`). Use a heredoc or `-F` file for the multi-line message.
    Legacy exception: if the task was already committed before the review (a branch started
    under the old rules), a second commit `fix(<area>): review round 1 fixes [T-xx]` is
    allowed — the only case where a task has two commits.
8. **Push + PR — only on the author's command.** Authorised when the message that started
   this task (or a later one) says «пуш» / «push» / «PR» (e.g. «зроби T-03 і відкрий PR»).
   Then, and only then:
   ```
   git push -u origin task/<id>-<short-name>
   gh pr create --base <main | the stacked base branch> --head task/<id>-<short-name> \
     --title "T-xx: <title>" --body-file <scratch file>
   ```
   PR body: `## Summary` (the Зроблено / Не зроблено lines), `## Verification` (the `/verify`
   block as a code block), `## Review` (Round 1 line), `## Playtest` (the numbered checklist),
   then the standard footer. Never merge the PR; the author does. Without the authorisation,
   skip this step and state in the report that the branch is committed locally and the push +
   PR await the author's command.
9. **Stop.** Never merge, never start the next task. Final report = commit hash, branch, PR url
   (or "awaiting «пуш»"), the `/verify` block, the review line, the playtest checklist, open
   items.

The review and the fix pass inside `/orchestrator` run **exactly once**. A second round
(`### Round 2`) only on the author's explicit request.

## Constraints specific to this repo

- Every feature/task lives in its own feature branch off `main` (or off the branch of a not-yet-
  merged PR it depends on — then the PR targets that branch) and is delivered as a PR; nothing is
  committed on `main` directly.
- One task, one branch, one commit, one PR — the review fix pass is inside that commit. If the
  task turns out to need two commits, that is a sign it should be split — ask instead of
  committing twice. The only exception is the legacy case in step 7 (task committed before the
  review → `fix(<area>): review round 1 fixes [T-xx]`).
- `docs/TASKS.md` edits in this run: the heading status and the done-note only. Backlog entries
  found along the way go under `## Backlog` as `### T-xx · <title> · \`backlog\`` (next free id).
- Never create or modify anything under `assets/`. Missing art means a `PH_*` placeholder and a
  line in "Не зроблено".
- Never add addons or NuGet packages. If a task seems to need one, stop and ask.
- If the task references a scene that does not exist yet (`Level00_Sections.tscn` in T-02), creating it
  is part of the task — placeholders only, listed in the plan or the done-note.
- If `GAME_DESIGN.md` and the task disagree, the document wins; if it is ambiguous, ask before
  implementing — do not invent mechanics.

## What "good" looks like

- The branch diff is the task and nothing else; a reviewer can map every file to a bullet in
  the task block.
- "Готово, коли:" is demonstrably true: each clause is backed by a smoke check or a playtest step
  the author can follow in under two minutes.
- `/verify` verdict is `verified` with real output, and the commit body says how.
- The Round 1 journal has every Blocker and Should-fix ticked `[x]`, or listed as deferred in
  the done-note; the post-fix `/verify` is green.
- The done-note tells the author what to look at first when they open the branch.

## Output format

End with:
```
Task: T-xx · <title>  → done
Branch: task/t-xx-<short-name>
Commit: <hash> feat(<area>): <what> [T-xx]
PR: <url> | not pushed — awaiting the author's «пуш»
Plan: docs/plans/<slug>/<slug>-plan.md
Verify:
  Build:    <…>
  Headless: <…>
  Smoke:    <n pass / n fail> (<names>)
  Scene:    <…>
  Verdict:  <verified | not verified — why>
Review: Round 1 — Ship: <yes|no>, <n> blockers, <n> should-fix (closed <n>)
Playtest (manual QA):
1. …
Open items: <deferred work, backlog entries added, questions for the author | none>
Next: author reviews (and merges the PR); do not run /task again without permission
```
