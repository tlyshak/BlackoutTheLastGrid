# Plan — t03r-review-fixes (T-03r · Виправлення за загальним рев'ю №1)

## Goal
Close the five Should-fix items (and the cheap nits) of `docs/reviews/2026-09-09-codebase-review-1.md`
before T-06 makes them real: hero stun restart, airborne re-entry into Jump, versioned `.import`
files, deterministic combo chaining in the smoke, hit-stop owned by the shared `Hitbox`.

## Scope
- In: S1–S5 from the review; nits with a one-line fix (Hitbox self-exclusion, `RESET` applied on
  interruption, `RouteType` pinned, `GameState.Instance` lifecycle aligned with `HitStop`,
  `MaxEnergy`/`MinEnergy` doc, shared `AnimHurt`/`AnimKO`, `Dummy.DimmedColor` export, `SmokeState`
  kept out of non-Debug builds, stale plan lines, TASKS.md note counts); regressions in smoke.
- Out: the author decisions listed in T-03r (jump dodge, KO at 0 energy, T-B01, `Main.tscn`).

## Design-doc conformance
No mechanics change. S5 keeps §6's hit-stop rule in one place for every attacker.

## GameState & save impact
`RouteType` gets explicit values `None = 0, Car = 1, Metro = 2` (T-09 will serialise them).
`GameState.Instance` is set in `_EnterTree` and cleared in `_ExitTree` like `HitStop`.

## Scene & signal contract
No scene tree changes. `Hitbox.TryHit` now calls `HitStop.Trigger(HitStopFrames)` itself after a
successful `TakeHit`; the `Hit(Node2D target)` signal stays for effects. `Player.PlayAnimation`
restarts an animation that is already playing (`Seek(0, update)`), so `Hurt` re-entry rewinds the
stun; `ResetPose()` applies the `RESET` keys immediately. `PlayerJump.Enter` only starts a jump
when grounded, so Jump can be entered as "already airborne"; `Player.Land()` is removed.

## File-level change list
- scripts/core: `Hitbox.cs` (self-exclusion, hit-stop), `GameState.cs` (enum values, lifecycle, doc)
- scripts/player: `Player.cs` (PlayAnimation restart, ResetPose, no OnHitboxHit, no Land),
  `PlayerJump.cs`, `PlayerHurt.cs`, `PlayerKO.cs` (shared anim names)
- scripts/enemies: `Dummy.cs` (`DimmedColor` export)
- tests/smoke: `combat_dummy.gd` (S4 deterministic chain, S1 hero restart), `player_movement.gd`
  (S2 airborne Idle), `player_flashlight.gd` (no drain during hit-stop — optional)
- `.gitignore` (drop `*.import`), `BlackoutLastGrid.csproj` (`Compile Remove="tests/**"` outside
  Debug) — both noted in the commit body per `/project-settings`
- docs: plans t02/t02b stale lines, TASKS.md (T-02b note count, T-B02 decision), this plan

## Acceptance criteria
- Given the hero in Hurt for 8 frames, a second `TakeDamage` returns him to Idle no earlier than
  17 frames after the second hit (hurt animation 0.30 s = 18 frames, minus frame alignment).
- Given the hero at the jump apex forced into Idle, `Height` decreases from the next frame, Jump is
  entered once, and the peak is not exceeded.
- Given a hit that connects, `Engine.TimeScale` becomes 0 without `Player` subscribing to `Hit`.
- `combat_dummy.gd` chains the combo by `AnimationTime`, not by a wall-clock wait.
- `git check-ignore -q assets/x.png.import` fails (not ignored); `dotnet build -c ExportRelease`
  succeeds without `tests/**`.
- Build, headless TestRoom load, smoke green.

## Test strategy
Regressions in the existing smoke scripts (see change list). Only by hand: the fist returning to
rest when an attack is interrupted.

## Playtest (manual QA)
1. `TestRoom.tscn` (F6): бити манекен J під час стрибка — нічого не ламається; удар по герою поки
   неможливий (ворогів немає), тому решта перевіряється smoke-тестами.
2. Натиснути J і одразу K: кулак повертається у вихідне положення, а не лишається витягнутим.

## Review focus
`state machine`, `hit-stop/timescale`, `scene/tscn integrity`, `GameState usage`.

## Performance & frame budget
Unchanged.

## Risks
`Seek(0, update: true)` on every `PlayAnimation` call applies the first key immediately; the
walk/idle placeholders have no AnimationPlayer animation, so nothing visible changes today.

## Open questions
None (author decisions are tracked in T-03r itself).

## Review findings
_filled in by /reviewer_

### Round 1 — Ship: yes

#### Summary
Fix-pass for `docs/reviews/2026-09-09-codebase-review-1.md`: the hero's `hurt` (and every
`AnimationPlayer` animation) is rewound on `PlayAnimation` so a Hurt restart really restarts the
stun (S1); `PlayerJump.Enter` only launches when grounded so the airborne guard resumes the fall
(S2); `*.import` is no longer gitignored (S3); the combo smoke chains by `AnimationTime` /
`Hitbox.IsActive` instead of a wall-clock wait (S4); `Hitbox.TryHit` triggers `HitStop` for every
attacker and `Player.OnHitboxHit` is gone (S5). Nits closed: `ResetPose` applies RESET immediately,
`Hitbox` skips its own `Attacker`, `RouteType` values pinned, `GameState.Instance` lifecycle aligned
with `HitStop`, `MaxEnergy`/`MinEnergy` doc, shared `AnimHurt`/`AnimKO`, `Dummy.DimmedColor`
export, `tests/**` compiled only in Debug, stale plan lines, TASKS.md counts, T-B02. Three smoke
scripts gained regressions. Reviewed surface: commit 168ac5c (docs) + the full uncommitted working
tree (`git status --porcelain`: 15 modified files + the untracked plan directory); no scene changes.

Verification run by the reviewer (2026-09-09, repo root):
```
Build:    passed ; new warnings: none (0 Warning(s), 0 Error(s)); dotnet build -c ExportRelease also 0/0
Import:   skipped — assets unchanged (assets/ holds only .gitkeep files)
Headless: passed ; warnings: 0   (godot --headless --path . --quit)
Smoke:    5 pass / 0 fail (tools/smoke.ps1)
          combat_dummy → PASS, core_gamestate → PASS, core_statemachine → PASS,
          player_flashlight → PASS, player_movement → PASS
Scene:    res://scenes/levels/TestRoom.tscn --quit-after 5 → passed
Verdict:  verified
```
Extra evidence: `SmokeState` is present in `.godot/mono/temp/bin/Debug/BlackoutLastGrid.dll` and
absent from `.godot/mono/temp/bin/ExportRelease/BlackoutLastGrid.dll` (string scan); the smoke runs
(Debug) stay green. `git check-ignore -q assets/x.png.import` exits 1; no `.import` file exists in
the tree, so nothing new is untracked. Findings marked **(probe)** come from a throwaway GDScript
run headless against `TestRoom.tscn` (not committed).

#### Plan conformance
Plan: `docs/plans/t03r-review-fixes/t03r-review-fixes-plan.md`
TASKS.md: T-03r `in_progress` — correct for this stage; the "Зроблено / Не зроблено" note is not
written yet (expected — must be added together with `done` before the commit). T-02b note now
reads "7 Should-fix (6 у плані T-02b + 1 у плані T-02)" and lists seven items — matches the two plan
journals (S1–S6 + T-02 S1). T-B02 (`backlog`) carries the T-03 N5 decision as the review asked.
- Implemented as planned: S1 (`Player.cs:194-203` `Play` + `Seek(0, update: true)`), S2
  (`PlayerJump.cs:15-23`, `Land()` removed, no caller left — grep-verified), S3 (`.gitignore:1-2`),
  S4 (`combat_dummy.gd:120-136` `_wait_combo_window`, `:288-304`; the T-02b S2 step `:483-492` now
  presses inside the freeze and checks the first physics frame), S5 (`Hitbox.cs:105-109`,
  `Player.cs:127-133` no `Hit` subscription), nits: self-exclusion `Hitbox.cs:88-91`, `RouteType`
  `GameState.cs:8-16`, `_EnterTree`/`_ExitTree`/`_Ready` `GameState.cs:84-100`, doc `:36-46`,
  `AnimHurt`/`AnimKO` used by `PlayerHurt.cs:14,25` / `PlayerKO.cs:10`, `Dummy.cs:40-41`,
  `BlackoutLastGrid.csproj:12-16`, t02 plan `PH_Face`, t02b plan HitStop/ComboWindowStart lines,
  hero Hurt-restart regression `combat_dummy.gd:616-649`, airborne-Idle regression
  `player_movement.gd:278-329`, no-drain-during-freeze `player_flashlight.gd:277-337`.
- Deviates from plan: `ResetPose()` (`Player.cs:226-234`) adds `Stop(keepState: true)` after the
  `Seek` — the plan and the review nit only asked for the keys to be applied immediately; the extra
  `Stop` is what produces S1 below. Acceptance criterion "no earlier than 18 frames" is asserted as
  `HURT_RESTART_MIN := 17` (`combat_dummy.gd:31`, comment explains frame alignment); observed 19/20/19
  in three runs — fine, but the plan text and the constant should say the same number (nit).
- Missing / partial: the fix commit does not exist yet. When it is made, its body **must** describe
  the `BlackoutLastGrid.csproj` (`Compile Remove="tests/**"` outside Debug) and `.gitignore`
  (`*.import` un-ignored) changes, as the plan's change list promises — without that note the
  project-settings rule makes the commit a Blocker.
- Accepted limitation (per plan / review nit): keeping `SmokeState.cs` out of an export also needs
  `tests/**` excluded in the export preset; `export_presets.cfg` is gitignored and does not exist
  locally, so that half cannot be versioned. Residual risk: an export PCK that still contains
  `tests/smoke/support/SmokeState.cs` with no matching class in the assembly — nothing in-game loads
  it (`core_statemachine.gd:17` is the only loader), so it is a log line at worst. Record the
  exclusion in the export-preset step of whichever task first creates the preset.
- Hard-look items requested for this round, all confirmed: **(probe)** `Seek(0, update: true)`
  right after `Play` has no method-track side effect — one light attack emits exactly one `Hit`
  signal (HP 30→25), the 3-hit combo emits three (HP 25/20/12, hits observed at `AnimationTime`
  0.083–0.098, i.e. the 0.08 s `HitboxOn` key still fires, no key fires twice); `hurt`'s frame-0
  keys are applied synchronously (a pose dirtied to `modulate (0.2,0.2,0.2)` / `PH_Body.rotation
  0.5` is white / 0 on the very next line after `TakeDamage`, then tints to (1, 0.39, 0.39) by
  0.067 s). **(probe)** `ResetPose` on an interrupted `light_1` (t = 0.083, hitbox active): `PH_Fist`
  is back at (14, −10) synchronously, `Hitbox.IsActive` false, `AnimationPlayer.IsPlaying()` true
  with `CurrentAnimation == "hurt"` at t = 0, Hurt → Idle after 19 frames, fist still at rest; a
  lethal hit mid-swing plays `ko` from 0 to `Visual.rotation` 1.571. `HitStop.Trigger` from
  `Hitbox` is core → core, no upward dependency; `_info.HitStopFrames` is the same value
  `CurrentAttack.HitStopFrames` carried before. `GameState.Instance = null!` in `_ExitTree`:
  `Node::_propagate_exit_tree` walks children in reverse order and the autoloads are the root's
  first children, so on quit every scene node leaves before `HitStop` and `GameState`; on
  `ReloadCurrentScene`/`queue_free` of a room the autoloads never leave; and no consumer
  (`Player`, `Flashlight`, `TestRoom`, `Dummy`) reads `GameState.Instance` from `_ExitTree` anyway —
  headless quit, scene quit and all five smoke teardowns print nothing.

#### Code
- [x] **S1. `ResetPose()` leaves the `AnimationPlayer` with no current animation; the next `AnimationTime` read prints an `ERROR:`** — `scripts/player/Player.cs:226-234` (`ResetPose` → `Stop(keepState: true)`), `scripts/player/Player.cs:241` (`AnimationTime => AnimationPlayer.CurrentAnimationPosition`) — Should-fix
  **Problem / why it matters:** `AnimationPlayer.Stop()` (with or without `keepState`) clears the
  player's current animation (`playback.current.from = null`), and
  `get_current_animation_position()` fails with `ERR_FAIL_NULL_V_MSG` when that is null.
  **(probe)** `player.ResetPose()` from Idle, then `player.AnimationTime` →
  `ERROR: AnimationPlayer has no current animation.` / `at: get_current_animation_position
  (scene/animation/animation_player.cpp:732)`. On `main`, `ResetPose` was a bare `Play("RESET")`,
  which never nulls the current animation, so this is new on the branch. Today it is unreachable
  in-game: the only caller is `PlayerAttack.Exit` (`PlayerAttack.cs:61-64`), always followed by
  `Play("hurt"/"ko")` in the same call stack, and `PlayerAttack.PhysicsUpdate` only reads
  `AnimationTime` behind `IsAnimationPlaying` — which is why every smoke run is clean. Concrete
  failure: the first state that interrupts an attack **without** playing an `AnimationPlayer`
  animation — T-06 jump attack / grab returning to Idle, T-05 `Interact`, or simply a GDScript test
  calling `ResetPose()` — leaves the hero in this state, and every subsequent `AnimationTime` read
  (`combat_dummy.gd:127` reads it each frame before its own Idle check; a HUD/debug label would
  too) prints one `ERROR:` line per frame, which `tools/smoke.ps1` counts as a FAIL and which floods
  the game log. `ResetPose` is public API, so the trap is one caller away.
  **Fix:** A (correct, one line) — drop `AnimationPlayer.Stop(keepState: true)`: `Play(RESET)` +
  `Seek(0.0, update: true)` already applies the four RESET keys synchronously (probe-verified), the
  1 ms RESET clip finishes on the next idle frame and keeps a current animation, so `AnimationTime`
  stays readable and `IsAnimationPlaying(x)` is false for every real animation. B (defensive) —
  keep the `Stop` and make `AnimationTime` null-safe
  (`AnimationPlayer.IsPlaying() ? AnimationPlayer.CurrentAnimationPosition : 0.0`); trade-off:
  finished animations then report 0 instead of their end position (only diagnostics in the smoke
  scripts read it in that state). Either way add the one-line regression in *Tests*.

#### Tests
- [ ] Regression for S1 — after `player.ResetPose()` (or an attack interrupted into a state with no
  `AnimationPlayer` clip) `player.AnimationTime` must be readable with no `ERROR:` line, and
  `PH_Fist.position == (14, −10)` — `tests/smoke/combat_dummy.gd` (next to the hero Hurt-restart
  block, `:616-649`).
- [ ] Optional (plan accepted manual-only, but it is now cheap): the fist returning to rest on an
  interrupted swing is fully observable headless — hit `attack`, `await _step(6)`, `TakeDamage`,
  assert `PH_Fist.position == (14, −10)`, `Visual/Hitbox.IsActive == false`, `hurt` playing at
  `AnimationTime == 0` — `tests/smoke/combat_dummy.gd`. Would also cover S1 once fixed.
- Determinism of the new regressions (3 raw runs each): combo presses land at
  `LightAttack1@0.083` / `LightAttack2@0.083` every run — the first physics frame after the restore,
  ~217 ms before the 0.30 s window closes (was 59 ms); hero Hurt restart → Idle at 19 / 20 / 19
  frames (min 17); S2 apex 77.08 at frame 26, forced Idle at 76.92, then 76.50 → 72.33, transitions
  `[Idle, Jump, Idle]` — identical to the digit in all runs; flashlight freeze observed over 10 idle
  frames (74–75 ms) with an Energy range of exactly 0. Physics steps keep ticking with a zero delta
  during the freeze (see nit), which the idle-frame observation does not depend on.

#### Nits
- The plan's acceptance criterion says "no earlier than 18 frames" while the test asserts
  `HURT_RESTART_MIN := 17` — make them say the same thing (the comment's frame-alignment argument is
  fine; put the number in the plan) — `tests/smoke/combat_dummy.gd:31`, plan *Acceptance criteria*.
- Pre-existing comment now demonstrably inaccurate: "hit-stop … stops physics frames (awaiting
  `physics_frame` hangs until the restore)". **(probe)** `_step(6)` after a light tap completed
  inside the freeze (hurt entered at `Engine.time_scale == 0` and advanced only 8 ms over the next
  4 physics frames): Godot still runs physics steps at `time_scale` 0, with a zero delta. Harmless
  for the tests (idle-frame waits stay correct), but worth rewording so nobody relies on it —
  `tests/smoke/combat_dummy.gd:15-18`.
- `tests/smoke/player_movement.gd:302` connects a lambda to `player.StateChanged` and never
  disconnects it; fine because the room is freed at the end, just inconsistent with the script's
  other connections that are made once at setup.
- `Hitbox.cs:24` doc line runs past the file's ~100-column wrap.

#### What's done well
- The S1 fix is in the one place the review asked for (`PlayAnimation`), and it is the *right*
  rewind: `Seek(0, update: true)` applies frame-0 keys synchronously, so a restarted Hurt is visually
  and mechanically at 0 on the same line — and it demonstrably does not disturb method tracks.
- `Hitbox.TryHit` is now the single owner of the hit → hit-stop rule for every attacker; `Player`
  lost a subscription and a handler instead of gaining a flag. The self-exclusion sits before
  `_alreadyHit`, so an own-hurtbox overlap costs nothing.
- `PlayerJump.Enter` gating on `IsAirborne` is the smallest correct change; the dead `Land()` is
  gone rather than kept "just in case".
- The rewritten combo chaining reads the same condition `PlayerAttack` buffers on
  (`AnimationTime >= ComboWindowStart || Hitbox.IsActive`) from the live state node's export, fails
  loudly with the observed state and time, and moved the margin from 59 ms to ~217 ms.
- `GameState` now mirrors `HitStop` exactly (`_EnterTree` set, `_ExitTree` guarded clear, `_Ready`
  for the run value); `RouteType` pinned before T-09 serialises it; the csproj change is scoped to
  non-Debug configurations and verified in both directions.
- Docs bookkeeping is complete and truthful: T-02b count reconciled with the two plan journals,
  T-B02 opened for the T-03 N5 decision, stale plan lines corrected to the scene's real values.

#### Verdict
Ship: yes — no blockers; build, ExportRelease build, headless load, TestRoom load and all five
smoke scripts are green, every S1–S5 item and every listed nit is closed and probe-verified, and the
only new issue (S1: `Stop` in `ResetPose` leaves no current animation) is unreachable in the shipped
tree and a one-line fix. First: 1) S1 — remove `AnimationPlayer.Stop(keepState: true)` from
`ResetPose` (or null-guard `AnimationTime`) and add the one-line regression; 2) write the T-03r
"Зроблено / Не зроблено" note, set `done`, and make sure the commit body describes the `.csproj`
and `.gitignore` changes; 3) align the 17-vs-18 frame wording between the plan and the test.
