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
4. **Plan or proceed** — run `/architect` with slug `t02-player-movement` (id without the dash,
   plus the short name) when the task touches more than ~3 files, adds a new scene, or has a
   design choice (which node handles `interact`, how `_z` height is represented, where a spawner
   lives). Its **Scene & signal contract** section comes from `/scene-design`. Otherwise go
   straight to implementation. Never write a plan just to have one.
5. **Implement** following `/coder`: one script per scene with the same name, signals and
   `[Export]` for wiring, `_PhysicsProcess` for movement and hit checks, `PH_*` placeholders
   instead of art, `StateMachine` + `State` children for behaviour. Any edit to
   `project.godot`, InputMap, autoloads, layer names or `.csproj` goes through
   `/project-settings` first. Out-of-scope findings become `backlog` entries in `docs/TASKS.md`,
   not code. `/coder` hands back the Зроблено / Не зроблено text in its report — keep it for
   step 12; it does not write it into TASKS.md itself.
6. **Verify** with `/verify` — pass/fail criteria are defined there, not here. On any verdict
   other than `verified`, fix and re-run — at most **3** loops. If the third run is still not
   `verified`, stop, leave the branch as is, and report what is failing; do not mark the task
   `done` and do not commit an unverified state.
7. **Tests + playtest** — run `/test-writer` for the smoke scripts implied by the "Готово, коли:"
   line (and the plan's Test strategy) plus the numbered playtest checklist. Re-run
   `powershell -ExecutionPolicy Bypass -File tools/smoke.ps1` after they land (judged by
   `/verify`'s rules); a failing new script counts as a failed run in step 6's budget.
8. **Review** — run `/reviewer` on the branch delta (`main...HEAD` plus the working tree). It
   appends `### Round 1 — Ship: <yes|no>` to the plan's `## Review findings` section (when
   there is no plan it reports the same structure in chat — that chat review is then the
   journal for steps 9–10). Record the blocker count, the should-fix count and the verdict in
   the run ledger (the same TodoWrite/scratch list that holds the acceptance criteria from
   step 1). You fix nothing yourself at this step.
9. **Fix pass — code** — run `/coder` on exactly the journal's `#### Code` block (every
   Blocker and Should-fix; Nits optional) plus any red `/verify` result still open. `/coder`
   ticks each closed item `[x]`. Anything the author must decide — a design question, a
   conflict with `docs/GAME_DESIGN.md`, an addon or NuGet request — is **not** fixed: leave it
   unticked and list it for the final report and the done-note.
10. **Fix pass — tests** — run `/test-writer` on the journal's `#### Tests` block plus a
    regression smoke check (or playtest step) for every Blocker / Should-fix closed in step 9.
    It ticks the Tests items `[x]` and refreshes the playtest checklist if behaviour moved.
11. **Verify again** — run `/verify`; the verdict must be `verified`. Step 6's retry budget
    (**3** loops in total across the run) applies here too: if it is exhausted, stop, leave
    the branch as is and report what is failing — no `done`, no commit.
12. **Set `done` and write the note** — `done` only after the post-fix `/verify` (step 11) is
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
    - **Плейтест:** 1) відкрити scenes/levels/TestRoom.tscn як головну (F6) … 2) …
    ```
13. **One commit** — the fix pass is part of this same task commit: never commit before steps
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
14. **Stop.** Never push, never merge, never open a PR, never start the next task — the author
    reviews and pushes. Final report = commit hash, branch, the `/verify` block, the review
    line, the playtest checklist, open items.

Steps 8–11 run **exactly once**: one review, one fix pass. A second round (`### Round 2`) only
on the author's explicit request — the same rule as `/orchestrator`.

## Constraints specific to this repo

- One task, one branch, one commit — the review fix pass is inside that commit. If the task
  turns out to need two commits, that is a sign it should be split — ask instead of committing
  twice. The only exception is the legacy case in step 13 (task committed before the review →
  `fix(<area>): review round 1 fixes [T-xx]`).
- `docs/TASKS.md` edits in this run: the heading status and the done-note only. Backlog entries
  found along the way go under `## Backlog` as `### T-xx · <title> · \`backlog\`` (next free id).
- Never create or modify anything under `assets/`. Missing art means a `PH_*` placeholder and a
  line in "Не зроблено".
- Never add addons or NuGet packages. If a task seems to need one, stop and ask.
- If the task references a scene that does not exist yet (`TestRoom.tscn` in T-02), creating it
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
Plan: docs/plans/<slug>/<slug>-plan.md | none
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
Next: author reviews and pushes; do not run /task again without permission
```
