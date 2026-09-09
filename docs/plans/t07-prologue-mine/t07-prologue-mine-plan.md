# Plan — t07-prologue-mine (T-07 · Пролог (рівень 0): каркас, доопрацьований)

## Goal
The first playable level end to end: the mine-dump «Зміна» from `GAME_DESIGN.md` §3 — three
rooms (забій, вентиляційна, вихід) built from placeholders, a tutorial that teaches move / jump /
flashlight / interact, the fan panel that has no power, the alarm that brings the guards, the
first stealth moment in the dark, Dan's loss as a text cutscene, the foreman's fine, and the exit
to `Level01_District` (empty) through `Main.tscn`. The author asked for this level to be polished
before Level 1 starts, so the flow, pacing and prompts are the deliverable, not just the skeleton.

## Scope
- In: `scenes/levels/Level00_Prologue.tscn` + `scripts/levels/Level00_Prologue.cs` (derives from
  `LevelBase`); reusable pieces in `scripts/levels`/`scripts/props`: `RoomBounds` (camera limits +
  floor bounds per room), `Door`/`RoomTransition` (Area2D that moves the camera limits and the
  hero to the next room), `TutorialPrompt` (Area2D that shows a HUD prompt once), `Cutscene`
  (text lines over a dark overlay, advanced with `interact`/`attack`, skippable), `AlarmEvent`;
  `Main.tscn` becomes the entry point: `scripts/Main.cs` loads the current level (`GameState`
  gets `CurrentScenePath`), `Level01_District.tscn` as an empty scene with a placeholder label;
  HUD/prompt reuse from T-04/T-05, guards/waves/darkness from T-06, panel/outlet from T-05;
  smoke `tests/smoke/level_prologue.gd`; playtest.
- Out: art, audio, real dialogue system (labels only), save/load (T-09), Level 1 content (T-08).

## Design-doc conformance
§3 Рівень 0: mine-dump, Dan below, ventilation cut «нижні не платять — нижнім не світимо», foreman
fines the shift; tutorial = movement, jump, flashlight, panel interaction (the fan panel cannot be
started — «панель обезструмлена згори»), first stealth moment (hide from the guards clearing the
horizon); end = Rey returns to the district and sees the dead station. §4 stealth as option, not
the base. Deviation to state: the task says "з'являється `Guard`, герой має пройти до виходу" —
implemented as: alarm → two guards patrol the exit room; the hero can sneak past them unlit
(they do not notice within half distance) or fight; both reach the exit.

## Options considered
1. **One scene, three rooms side by side, camera limits per room** (chosen): belt-scroll feel,
   one `LevelBase`, transitions are just limit changes + a short hero walk-in.
2. Three separate scenes: more loading code, breaks the belt-scroll continuity. Rejected.
3. Cutscenes as separate scenes: overkill; a `Cutscene` CanvasLayer with a `Label` and a dark
   `ColorRect` is enough for placeholders.

## GameState & save impact
`GameState.CurrentScenePath` (string) set by `Main`/`LevelBase.GoToLevel` (T-09 persists it);
the prologue's fine: `GameState.AddEnergy(-FinePenalty)` at the foreman scene (export, default 20)
so the district level starts with a visibly reduced reserve; `ResetRun` unaffected.

## Scene & signal contract
```
Main (Node) → scripts/Main.cs   [Export] PackedScene StartLevel = Level00_Prologue; instantiates it
Level00_Prologue (LevelBase → Level00_Prologue.cs)
├── CanvasModulate #0a0d14
├── Rooms (Node2D)
│   ├── Room_Zaboi (RoomBounds: rect (0,0,1920,1080), floor 300–600)          — «забій»
│   ├── Room_Vent  (RoomBounds: rect (1920,0,1920,1080))                       — «вентиляційна»
│   └── Room_Exit  (RoomBounds: rect (3840,0,1920,1080))                       — «вихід»
├── PH_ props per room (floor bands, walls, crates, conveyor, fan, lift cage)
├── Player (at (200, 480) facing right)
├── Camera2D + EnemyDirector (from LevelBase pattern)
├── HUD (instance)
├── Tutorial (Node) ── TutorialPrompt × 4 (Area2D triggers: «WASD — рух», «Space — стрибок над
│                     ящиком», «F — ліхтар (тут темно)», «E — панель»)
├── Doors: Door_1 (Zaboi→Vent, requires flashlight tutorial done), Door_2 (Vent→Exit, opens after
│          the alarm), Exit (Area2D at the lift; requires reaching it)
├── FanPanel (PowerPanel, [Export] Powered = false → sequence completes but `Activated` is replaced
│             by `FailedNoPower` → cutscene line «Немає живлення. Панель обезструмлена згори.»)
├── Outlet_1 (one-shot, in Zaboi) — teaches recharge
├── AlarmEvent (Node) — after FanPanel fails: flashing PH_AlarmLights (PointLight2D red, blink
│             via Tween), `GuardSpawner` (WaveSpawner, Count 2, no screen lock, OneShot) in Room_Exit,
│             guards patrol (Guard gets [Export] PatrolPoints? → out of scope: they stand at two
│             points facing the hero's approach; darkness rule does the stealth)
├── LitZones under two PH_ lamps in Room_Exit (the lit corridor); the dark path along the top wall
├── DanCutscene / ForemanCutscene / EndCutscene (Cutscene instances; text from GAME_DESIGN)
└── DebugLabel (as in TestRoom)
```
Flow (Level00_Prologue.cs, a small sequence state enum, not a StateMachine node — no per-frame
logic): Intro cutscene (2 lines: Rey and Dan at the shift) → tutorial prompts as the hero moves →
Door_1 → Vent room: FanPanel → sequence → «Немає живлення» line → Alarm (lights, sound-less) →
DanCutscene («Дан лишився внизу…», 2 lines) → Door_2 opens → Exit room: guards + lit corridor,
prompt «Вимкни ліхтар і пройди тінню — або бийся» → Exit area → ForemanCutscene (fine −20 energy)
→ EndCutscene («Мертва станція у вікні… Рішення: запустити її.») → `LevelBase.GoToLevel(Level01)`.
Signals: `RoomBounds` none (data); `Door.Entered(Player)`; `TutorialPrompt.Shown()`;
`Cutscene.Finished()`; `PowerPanel.FailedNoPower()` (new, T-05 panel gets `[Export] Powered`);
`Level00_Prologue.StageChanged(string stage)` for tests/debug.
Exports: `FinePenalty` 20, `AlarmBlinkPeriod` 0.5 s, `CutsceneSkippable` true, per-prompt text.

## File-level change list
- scenes/levels: `Level00_Prologue.tscn`, `Level01_District.tscn` (new, placeholder), `Main.tscn` (edit: Main.cs)
- scripts: `Main.cs` (new); scripts/levels: `Level00_Prologue.cs`, `RoomBounds.cs`, `Door.cs`,
  `LevelBase.cs` (edit: `GoToLevel`, room limits); scripts/props: `TutorialPrompt.cs`,
  `PowerPanel.cs` (edit: `Powered` + `FailedNoPower`); scripts/ui: `Cutscene.cs` + `scenes/ui/Cutscene.tscn`
- tests/smoke: `level_prologue.gd` (drives the whole flow headless: prompts, panel fail, alarm,
  guards spawned, sneak past unlit, exit, cutscenes finished, GoToLevel called → Level01 loaded)
- docs: this plan, TASKS.md; project.godot: `run/main_scene` stays `Main.tscn` (no change)

## Acceptance criteria
- Running `Main.tscn` starts the prologue; the intro cutscene shows and is dismissed with `interact`.
- Each tutorial prompt appears once when its trigger is entered and hides after the action is
  performed (or after `PromptTimeout`).
- The fan panel's sequence completes but ends in `FailedNoPower`, the alarm lights blink, Dan's
  cutscene plays, Door_2 opens.
- In the exit room two guards stand in the lit corridor; the hero passing along the dark path
  with the lamp off is not noticed (no `Noticed`), with the lamp on he is; reaching `Exit` plays
  the foreman cutscene, `Energy` drops by `FinePenalty`, the end cutscene plays, and
  `Level01_District` becomes the current scene with `GameState.CurrentScenePath` set.
- Hero KO in the prologue reloads the prologue (LevelBase rule).
- Build, headless prologue load, smoke green; the level is playable start to end in ≤ 4 minutes.

## Test strategy
`level_prologue.gd`: end-to-end drive with `Input.action_press`, positions set directly for room
hops, cutscenes skipped via `interact`, checks each stage via `StageChanged`. Only by hand: pacing,
text timing, whether the rooms read as a mine.

## Playtest (manual QA)
1. Запустити проєкт (F5): темна шахта, текст вступу; E — далі. Підказка «WASD — рух».
2. Дійти до ящика: підказка про стрибок; перестрибнути. Далі темніша ділянка: підказка «F».
3. Розетка — підказка «E»; зарядитися. Двері праворуч — перехід у вентиляційну (камера їде).
4. Панель вентилятора: набрати послідовність — «Немає живлення». Червоні лампи блимають, текст
   про Дана. Двері праворуч відкриваються.
5. Кімната виходу: освітлений коридор і два охоронці. Вимкнути ліхтар і пройти верхом у темряві —
   не помічають; або з ліхтарем — помічають і б'ють. Дійти до ліфта.
6. Текст бригадира (штраф −20 енергії на шкалі), текст про станцію, порожній рівень 1 з написом.

## Review focus
`signals/decoupling`, `state machine`, `scene/tscn integrity`, `GameState usage`, `input map`.

## Performance & frame budget
Three rooms in one scene ≈ a few dozen placeholder nodes and ≤ 6 lights; guards only after the
alarm. Cutscene overlay is a CanvasLayer toggled, not rebuilt.

## Risks
Depends on T-05 (`PowerPanel`, prompts) and T-06 (`Guard`, `LevelBase`, `LitZone`, darkness) —
starts after both are merged. Text is placeholder Ukrainian from the design doc, to be replaced.

## Open questions
None.

## Review findings

### Round 1 — Ship: no

Reviewed: the uncommitted working tree on `task/t-07-prologue-mine` (`git status --porcelain`: 5
modified, 22 untracked files — every entry read; `tests/smoke/level_prologue.gd` is being written
concurrently and is **out of scope this round**). No commits on the branch yet, so
`git diff main...HEAD` is empty; the surface is `git diff` + the untracked files.

**Verification (run by the reviewer):**
```
Build:    passed ; new warnings: none (0 Warning(s), 0 Error(s))
Import:   skipped — assets unchanged (nothing under assets/ in git status)
Headless: passed (godot --headless --path . --quit → only the engine banner, no ERROR/WARNING) ; warnings: 0
Smoke:    2 pass / 0 fail (-Filter core_*; the rest of the suite untouched by this branch, level_prologue.gd mid-edit)
          tests/smoke/core_gamestate.gd → PASS: SMOKE core_gamestate PASS
          tests/smoke/core_statemachine.gd → PASS: SMOKE core_statemachine PASS
Scene:    res://scenes/levels/Level00_Prologue.tscn --quit-after 5 → passed (no ERROR lines)
Probes:   2 throwaway GDScript drives through Main.tscn (scratchpad, not committed), exit 0, no ERROR lines:
          full flow Intro→Done, stage order ["Tutorial","Ventilation","NoPower","Alarm","Escape","Foreman","Ending","Done"],
          Level01 became current_scene, CurrentScenePath set, time_scale 1; KO restart reloads Main → fresh prologue at Intro;
          crate blocked/cleared/pop-out; flashlight-hint timeout unlocks Door_1; unlit top path 432 frames → 0 Noticed; lit zone → Noticed.
Verdict:  verified (build, headless, scene, core smoke green; the level smoke is pending from /test-writer)
```

#### Summary
The branch turns `Main.tscn` into the entry point (`Main.cs` instantiates `StartLevel`, records
`GameState.CurrentScenePath`), adds the reusable level pieces (`RoomBounds`, `Door`,
`TutorialPrompt`, `JumpableObstacle`, `Cutscene`), gives `PowerPanel` a `Powered` flag with
`FailedNoPower`, extends `LevelBase` with `GoToLevel` / `ApplyRoomBounds`, and builds the whole
prologue as one three-room scene driven by a `Stage` enum and prop signals: intro → four tutorial
hints → Door_1 → dead fan panel → alarm (lights, darkness tint, two unaware guards in the exit room)
→ Dan's cutscene → Door_2 → sneak past or fight → lift → foreman fine (−20) → ending → `Level01_District`
(placeholder). The flow is verified end to end headless; the remaining work is readability polish.

#### Plan conformance
Plan: `docs/plans/t07-prologue-mine/t07-prologue-mine-plan.md`
TASKS.md: T-07 `in_progress` — correct for this round; the "done / not done" note is still missing (expected, add it with the fixes; mention `JumpableObstacle.cs` and that the HUD stays per level — the T-04 note "HUD переїде в Main" is now stale).
- Implemented as planned: `Main.tscn`/`Main.cs` loader; `GameState.CurrentScenePath` (level path, set by `Main` and `GoToLevel` — consistent with T-09 resuming a level directly); `LevelBase.GoToLevel` (HitStop cancelled, deferred `ChangeSceneToPacked`) and `ApplyRoomBounds`; `RoomBounds`, `Door` (blocker `SetDeferred`, re-lock behind the hero), `TutorialPrompt` (Shown/Completed, action or timeout), `Cutscene` (`Finished`, skippable, `ProcessMode.Always`, input consumed in physics, hero resumed deferred); `PowerPanel.Powered` + `FailedNoPower`; three rooms with `PH_` props, lit corridor with two `LitZone`s, `GuardSpawner` (Count 2, `SpawnAware=false`, trigger disabled), `StageChanged`, `FinePenalty`, `Level01_District.tscn` placeholder; all texts from §3; KO → Main reload (probe H).
- Deviates from plan: `AlarmEvent` node → `AlarmLights` container + code in the level (`Level00_Prologue.cs:312-414`) — fine; `JumpableObstacle.cs` is a new script not in the file list (needed for the jump hint; record it); the hero stays frozen from the panel failure through the alarm beat and Dan's cutscene (`OnCutsceneFinished` NoPower branch does not resume, `:248-250`) — a deliberate beat, acceptable, but see nits; `TutorialPrompt` gained `Completed` (plan listed `Shown` only) — good.
- Missing / partial: `tests/smoke/level_prologue.gd` (concurrent, not graded); TASKS.md done-note.
- Acceptance criteria: all met per the probe (intro dismissed with `interact`; every hint shows once and hides on action/timeout; panel → `FailedNoPower` → alarm → Dan → Door_2 open; unlit top path never noticed, lit zone noticed at 150 px; Exit → Foreman, energy 100→80, ending → Level01 with `CurrentScenePath`; KO reloads the prologue). Walking distance ≈ 5.6k px at 220 px/s ≈ 30 s + cutscenes → well under 4 min.
- Accepted limitation (per plan): guards have no patrol, they stand at two points — residual risk: none for the prologue (the darkness rule carries the stealth beat; verified).

#### Code
- Blockers: **none**.
- [x] **S1. Dead panel keeps offering "E: Запустити вентилятор" and hides the escape hint** — `scripts/levels/Level00_Prologue.cs:493` (`RefreshPrompt` priority) + `scripts/props/PowerPanel.cs:97,222-229` — Should-fix
  **Problem / why it matters:** after the no-power failure the panel is still `CanInteract` (`!IsActivated`), so when the hero is resumed after Dan's cutscene (still standing in the panel's 44 px radius) the interactable prompt wins over `EscapePromptText`. Probe step K: stage `Escape`, HUD = `E: Запустити вентилятор`; the escape hint appeared only after stepping away. The player has just been told the panel is dead and is invited to use it again; pressing E replays the whole sequence and fails again (probe L — no double stage transition thanks to the `_stage == Ventilation` guard, so no Blocker). The coder's own note flagged this.
  **Fix:** A (correct): in `PowerPanel`, after the first `FailedNoPower` set a `_deadNoPower` flag → `CanInteract => !IsActivated && !_deadNoPower`, `CurrentPrompt` → new `[Export] NoPowerPromptText = "Обезструмлена"`, and in `Level00_Prologue.RefreshPrompt` rank a non-ready prop's text below the stage hint (ready interactable → stage hint → tutorial hint → unusable-prop text). B (quick): in `OnFanPanelFinished` stop following the panel (`FollowInteractable(null)`, `_interactablePrompt = null`) and ignore `InteractableChanged` for `FanPanel` once `_stage >= NoPower` — still leaves the panel usable.
- [x] **S2. Rooms 1–2 have no light source: the move/jump tutorial happens in a uniformly black scene before the lamp is taught** — `scenes/levels/Level00_Prologue.tscn:87-88` (Darkness 0.039/0.051/0.078) and nodes `:110-297` (no `PointLight2D` before `AlarmLights`; compare `TestRoom.tscn:119` `PH_Lamp`) — Should-fix
  **Problem / why it matters:** with the modulate at ≈0.04 the crate row (0.45,0.32,0.18) renders at ≈5/255 and the floor at ≈2/255 — indistinguishable; Dan's figure, the hatch and the crate the "Space — стрибок через ящики" hint refers to are invisible until the player finds F on his own, yet the flashlight hint is third by design (§3 order: рух, стрибок, ліхтар). "F — ліхтар (тут темно)" cannot read as "here it is dark" when everywhere is equally dark. Rendering-only, so not probeable headless — the arithmetic above is the evidence.
  **Fix:** add 1–2 `PH_WorkLamp` `PointLight2D` (reuse `GradientTexture2D_lamp`) over the start/conveyor (x≈300–750) and one over the fan panel in room 2 (the objective), leaving x≈880–1900 unlit so the flashlight zone actually is the dark stretch; optionally a `PH_LampBody` polygon each. Alternative: a lighter `Darkness` for the забій tweened down at the flashlight zone (more code, same effect).
- [x] **S3. Flashlight hint with the lamp already on: F switches it OFF and still completes** — `scripts/levels/Level00_Prologue.cs:428-432,270` + `scripts/props/TutorialPrompt.cs:78-84` — Should-fix
  **Problem / why it matters:** a player who pressed F earlier (curiosity, or to see the crates — see S2) reaches x≈880 with the lamp on, reads "F — ліхтар (тут темно)", presses F → the lamp goes dark, the hint disappears and the door opens (probe D: lamp=true → after F lamp=false, `IsCompleted=true`, `Door1.Locked=false`). The hint teaches the opposite of what happened. The 6 s timeout path also unlocks Door_1 (probe F) — no soft-lock, keep it.
  **Fix:** make `TutorialPrompt.Complete()` public and in `OnHintShown` skip the hint when `ReferenceEquals(hint, FlashlightPrompt) && Player.Flashlight.IsOn` (complete immediately → Door_1 unlocks); or reword to "F — ліхтар увімк./вимк." (weaker).
- [x] **S4. `PH_LitFloor` decals Y-sort above the hero and guards in the stealth/fight corridor** — `scenes/levels/Level00_Prologue.tscn:456-465, 483-492` — Should-fix
  **Problem / why it matters:** the opaque floor polygons are children of `LitZone_1/2` (Area2D at y=505) under the y-sorted level, so the whole subtree is drawn at sort key 505 — after any character whose feet are at y<505. A hero fighting at (4400,450) has his lower half painted over by the "lit floor"; guards walking up from y=580 to the hero's lane vanish the same way. The corridor is exactly where the fight option happens.
  **Fix:** move both polygons to a `PH_Decals` `Node2D` at position (0,300) placed right after `PH_Floor_3` (same Y as `FloorTop`, so every character sorts after it), with absolute polygon coordinates; keep the `CollisionShape2D`, lamp light and lamp body under the `LitZone`s.
- [x] **S5. `Cutscene.Skippable` is overwritten after the cutscene's own soft-lock guard ran** — `scripts/levels/Level00_Prologue.cs:160` vs `scripts/ui/Cutscene.cs:66-70` — Should-fix
  **Problem / why it matters:** `Cutscene._Ready` (child, runs first) validates `Skippable`/`LineDuration`; the level then assigns `Cutscene.Skippable = CutsceneSkippable`. Flip the exported `CutsceneSkippable` to `false` in the inspector with `LineDuration` 0 → the intro shows line 1 forever, hero disabled, no input works — the game is stuck on the first screen.
  **Fix:** validate in `Cutscene.Play` (if `!Skippable && LineDuration <= 0f` → warn and set `Skippable = true`), or turn `Skippable` into a property whose setter re-validates.

#### Tests
- [ ] `tests/smoke/level_prologue.gd` (in progress by /test-writer, not graded here) — should assert, beyond the stage order: `Hud.PromptText` at each beat (WASD → Space → F → outlet "E: Зарядити" → panel → sequence glyphs → ALARM → Escape hint → Sneak hint), **including the HUD text after Dan's cutscene while the hero still stands at the panel (S1 regression)**; a second sequence at the dead panel produces no new `StageChanged`; both guards `IsAware == false` and `Idle` while Dan's cutscene plays; unlit walk along y=320 from x=3920 to 5500 → 0 `Noticed`; lamp off inside `LitZone_1` → `Noticed`; Exit → `Foreman`, energy −`FinePenalty`, `GuardSpawner.process_mode == Disabled`; `Done` → `current_scene` is `Level01_District`, `GameState.CurrentScenePath` set; KO in the prologue → `current_scene` is `Main` again with a fresh level at `Intro`; `Engine.time_scale == 1` at the end.
- [ ] Crate obstacle — `tests/smoke/level_prologue.gd` or a props smoke: hero at x=670 holding right stays ≤ 684; jump from 660 clears to x>750 with `Shape.disabled` true only while `Height >= ClearHeight`; hero teleported to 712 is pushed out within 6 physics frames and can walk again (probe C confirms; keep it covered).
- [ ] Flashlight hint timeout unlocks `Door_1` without F (probe F) — keep as a smoke assertion; the soft-lock guard is worth a line.
- [ ] Playtest checklist (rendering-only, headless cannot see it): S2 (can the crates/Dan be seen before F?), S4 (hero over the lit floor), the camera pan at both doors (`limit_smoothed` + 80 px arrival hop), the 1.5 s frozen alarm beat, gate strip covering the hero when crossing at y<450, lift cage covering the hero at the exit.

#### Nits
- `PowerPanel.StartFailFlash` does not `NotifyPromptChanged`, so during the 0.5 s red flash the HUD keeps "↑ J ↓ [␣]" with the last key still bracketed (probe H) — pre-existing T-05 `Fail` path, now also the no-power path — `scripts/props/PowerPanel.cs:246-257`.
- `GuardSpawner` has `LockRect` set but no `Camera` → dead config, and "GO →" pops after both guards are KO'd although nothing was locked — `scenes/levels/Level00_Prologue.tscn:612-618`.
- `Director` is exported but never used by the script (only the scene wires it into the spawner) — `scripts/levels/Level00_Prologue.cs:102`.
- Cutscene hint says "E — далі" but `attack` (J) advances too — `scenes/ui/Cutscene.tscn:66`, `scripts/ui/Cutscene.cs:34,76`.
- `MovePrompt` reads "WASD — рух" but completes only on `move_right` — `scenes/levels/Level00_Prologue.tscn:548`.
- The hero is frozen for `AlarmToDanDelay` (1.5 s) with no overlay, only the ALARM hint and blinking lights — fine as a beat, confirm in playtest that it does not read as a hang — `scripts/levels/Level00_Prologue.cs:248-250,320`.
- `PH_LiftCage` (sort y=600) hides the hero entering the lift; door `PH_Gate` strips (sort y=450, span 150..600) cover a hero crossing at y<450 for a few frames — placeholder-acceptable — `scenes/levels/Level00_Prologue.tscn:517-528, 329-331, 364-366`.
- `FinePenalty` clamps at 0: a player who drained the lamp below 20 starts Level 1 with 0 energy and a lamp that refuses to switch on (`Flashlight.SetOn` at `MinEnergy`) — T-08's problem (needs an outlet at the district start); add a `backlog` line in TASKS.md rather than fixing here.
- `Main.cs` summary is accurate; the T-04 note "HUD переїде в Main.tscn" is now stale (each level instances its own HUD, which is fine) — say so in the done-note.

#### What's done well
- Purely signal-driven flow with a stage enum and no per-frame logic; `RefreshPrompt` is event-driven (no per-frame string work), `_Process` only refreshes the debug label on height change.
- Cutscene freeze uses `ProcessMode.Disabled` on the hero and the hints, which (with `DisableMode.Remove`) also pulls their bodies/areas out of the physics space — verified: no lamp drain, no hits, no prompt triggers during cutscenes, guards stay `Idle`/unaware; resume is deferred so the closing E/J press is never re-read by the hero (probe: `Idle` after every cutscene, no stray interaction).
- Scene-change hygiene: `HitStop.Cancel()` before both `ReloadCurrentScene` and the deferred `ChangeSceneToPacked`; tweens killed and the Dan timer disconnected in `_ExitTree`; `SceneTreeTimer` with `ignoreTimeScale`; `SetDeferred` on the door blocker and on the prompt's `Monitoring` (physics-callback safe); `IsInstanceValid` backstops on both timers.
- The stealth geometry works out of the box: the top lane (y≤400) is outside both `LitZone`s and outside the guards' 210 px dark cone (dy=260), the lit floor notices at 150 px — sneak and fight both reach the exit, exactly §4 "стелс як опція".
- `.tscn` integrity is clean: unique uids, `load_steps` correct in all four scenes, `[editable path="GuardSpawner"]` overrides survive a reload (Marker positions confirmed at (4550,580)/(5050,580) after the Main reload), every `node_paths` entry resolves, no dangling `ext_resource`.
- `FailedNoPower` stage guard (`_stage == Ventilation`) makes the repeatable panel harmless for the flow.

#### Verdict
Ship: no — zero blockers and the level is functionally complete and verified end to end, but the author set "polished before Level 1" as the bar and S1–S4 are each a player-visible confusion in the tutorial or the stealth room (dead panel re-offered while the escape hint is hidden; the first two hints in a black room; the lamp hint that turns the lamp off; the lit floor painting over the fighters). All four are small, scene- or prompt-level changes; one more round. First: S1 (dead panel + prompt priority), S2 (work lamps in rooms 1–2), S4 (decal sort), then S3 and S5.
