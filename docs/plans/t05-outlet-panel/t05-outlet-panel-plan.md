# Plan — t05-outlet-panel (T-05 · Інтерактивні панелі та розетки)

## Goal
Give the energy economy its other half: outlets that refill `GameState.Energy` on `interact`, and
dead power panels that come alive after a short button sequence and switch on the lights bound to
them in the level. `GAME_DESIGN.md` §4 «Ліхтар = ресурс… поповнюється на розетках/панелях, які
треба оживляти», «Ремонт — 3–4 кнопки в правильному порядку, без складних міні-ігор».

## Scope
- In: `scripts/props/Interactable.cs` (base), `scenes/props/Outlet.tscn` + `Outlet.cs`,
  `scenes/props/PowerPanel.tscn` + `PowerPanel.cs`; the hero's `InteractionArea` + `Interact`
  state + `interact` input; HUD prompt (`HUD.ShowPrompt/HidePrompt`); a `PH_Lamp` `PointLight2D`
  in `TestRoom` switched on by the panel; smoke `tests/smoke/props_interact.gd`; playtest.
- Out: enemies reacting to lit rooms (T-06 — but the lamp is a `PointLight2D` on the level so T-06
  can add a `LitZone` next to it), art, sounds, a real repair UI (prompt text only), save state of
  activated panels (T-09 reads `IsActivated` later).

## Design-doc conformance
§4: outlets/panels refill the charge; the panel mini-interaction is a 3–4 button sequence with a
hint on screen — implemented literally (sequence of InputMap actions shown in the HUD prompt).
Task text: outlet «одноразово або з кулдауном» → both, by exports. No disagreements.

## Options considered
1. **Hero owns detection** (chosen): `Player/InteractionArea` (Area2D, mask = Interactable layer 6)
   collects nearby `Interactable`s, picks the nearest, exposes it; props stay passive and never
   reach into the hero.
2. Props detect the hero body and call into it: couples every prop to `Player`. Rejected.
3. Sequence input read by the hero state: duplicates input handling per prop type. Rejected — the
   panel polls its own input while active; the hero's `Interact` state just waits for `Finished`.

## GameState & save impact
`Outlet` calls `GameState.AddEnergy(Amount)`. `PowerPanel.IsActivated` and `Outlet` cooldown /
uses are per-scene runtime state; T-09 may persist `IsActivated` per panel id later (add a
`[Export] string SaveId` now, unused).

## Scene & signal contract
`scripts/props/Interactable.cs` — `public abstract partial class Interactable : Area2D`
(layer 6 Interactable, mask 0, `monitorable = true`, `monitoring = false`):
- Exports: `PromptText` (string, e.g. "Зарядити"), `SaveId` (string).
- API: `bool CanInteract` (virtual), `void Begin(Player player)` (abstract → emits `Finished` when
  done), `void Cancel()` (virtual, called if the hero leaves the state early).
- Signals: `Finished(bool success)`, `PromptChanged(string text)` (for props whose prompt changes,
  e.g. "Розряджена (7 с)").
`Outlet : Interactable` (`scenes/props/Outlet.tscn`):
```
Outlet (Interactable → Outlet.cs)  layer 6 / mask 0
├── PH_Body (Polygon2D 24×36, dark green box, origin at the floor contact)
├── PH_Indicator (Polygon2D 8×8; green when ready, grey while cooling down / spent)
└── CollisionShape2D (CircleShape2D r=40)   interaction radius
```
Exports: `Amount` 25 (energy), `Cooldown` 8 s (0 = no cooldown), `Uses` 1 (−1 = unlimited).
Behaviour: `Begin` → if ready: `AddEnergy(Amount)`, `Charged(float amount)` signal, uses−1,
cooldown timer (a `Timer` child or `_Process` countdown), indicator grey, `Finished(true)`; else
`Finished(false)`. `CanInteract` false while cooling down or spent (prompt "Розряджена").
`PowerPanel : Interactable` (`scenes/props/PowerPanel.tscn`):
```
PowerPanel (Interactable → PowerPanel.cs)  layer 6 / mask 0
├── PH_Body (Polygon2D 32×48 grey box)
├── PH_Screen (Polygon2D 20×12; red = dead, yellow = in sequence, green = active)
└── CollisionShape2D (CircleShape2D r=44)
```
Exports: `Sequence` (`string[]` of InputMap actions, default `["move_up", "attack", "move_down", "jump"]`),
`StepTimeout` 2.0 s (0 = none), `FailResetDelay` 0.5 s. Signals: `Activated()`, `SequenceStep(int index, int total)`,
`SequenceFailed()`. Behaviour: `Begin` → active: prompt via `PromptChanged` shows the sequence
with the current step highlighted (e.g. "↑ · J · ↓ · ␣" with a marker; use action display names
from a small map `move_up→"↑"`, `attack→"J"` …); in `_PhysicsProcess` while active read
`Input.IsActionJustPressed` for every tracked action (`move_*`, `jump`, `attack`, `heavy_attack`,
`special`); correct → next step; wrong → `SequenceFailed`, screen red, `Finished(false)` after
`FailResetDelay`; all steps → `IsActivated = true`, screen green, `Activated`, `Finished(true)`.
`CanInteract` false once activated (prompt "Працює").
Hero:
```
Player
├── InteractionArea (Area2D, layer 0, mask 32 = Interactable)   CollisionShape2D CircleShape2D r=36 at (0,-20)
└── StateMachine/Interact (PlayerInteract.cs)
```
`Player` API: `Interactable? CurrentInteractable` (nearest by distance among overlapping, re-picked
every physics step while more than one prop is in reach),
`bool InteractPressed` (`interact` just pressed), signal `InteractableChanged(Interactable? current)`.
`PlayerState.TryStartAction`: `InteractPressed && CurrentInteractable?.CanInteract == true` →
`Interact`. `PlayerInteract`: Enter → `ApplyFloorMove(Zero)`, connect `Finished`, `Begin(Player)`;
`Finished` → `Idle` on the next physics step (so the closing key of a sequence is not re-read by
Idle as a jump/attack); a prop that vanishes or goes inactive without `Finished` also releases the hero; Exit → disconnect (+ `Cancel()` if still active); attacks/moves ignored while
interacting; `Hurt`/`KO` may interrupt (T-06 hits) — `Exit` handles it.
HUD additions: `Prompt` (Label, bottom-centre, hidden by default), `ShowPrompt(string)`,
`HidePrompt()`. `TestRoom` wires: `Player.InteractableChanged` → prompt "E: <PromptText>" / hide;
the current interactable's `PromptChanged` → prompt text; `PowerPanel.Activated` → `PH_Lamp`
(`PointLight2D`, warm, texture = the same GradientTexture2D approach as the flashlight but radial
full-circle, `enabled = false`) `Enabled = true` and `PH_LampBody.modulate` brighter.
TestRoom layout: `Outlet` at (300, 560), `PowerPanel` at (1100, 430), `PH_Lamp` at (1100, 330).
Collision: Interactable layer 6 (bit 32); `Player/InteractionArea` mask 32; nothing else changes.
`project.godot`: no change (layer names exist; `interact` action exists).

## File-level change list
- scripts/props: `Interactable.cs`, `Outlet.cs`, `PowerPanel.cs` (new)
- scripts/player: `Player.cs` (InteractionArea, CurrentInteractable, InteractPressed, signal),
  `PlayerState.cs` (Interact transition + StateInteract const), `PlayerInteract.cs` (new)
- scripts/ui: `HUD.cs` (prompt API); scripts/levels: `TestRoom.cs` (wiring)
- scenes: `props/Outlet.tscn`, `props/PowerPanel.tscn` (new), `player/Player.tscn` (area + state),
  `ui/HUD.tscn` (Prompt label), `levels/TestRoom.tscn` (props, lamp)
- tests/smoke: `props_interact.gd` (new)
- docs: this plan, TASKS.md note. project.godot: no change.

## Acceptance criteria
- Given the hero next to the outlet with `Energy = 40`, pressing `interact` gives `Energy = 65`
  (capped at Max), `Charged(25)` fired, the hero passes through `Interact` and is back in `Idle`
  within 5 frames; pressing again within the cooldown does nothing (`Finished(false)`, energy
  unchanged); with `Uses = 1` the outlet stays spent after the cooldown.
- Given the hero away from any interactable, `interact` does nothing (state stays Idle).
- Given the hero at the panel, `interact` enters Interact, the prompt shows the sequence; pressing
  `move_up, attack, move_down, jump` in order emits `SequenceStep` 1..4, `Activated`, the lamp's
  `Enabled` becomes true, the hero returns to Idle; a wrong action mid-sequence emits
  `SequenceFailed`, the hero returns to Idle, the lamp stays off, and the panel can be retried.
- Given the panel activated, `CanInteract == false` and `interact` no longer starts it.
- `Player.InteractableChanged` fires with the outlet when entering its radius and with `null` when leaving.
- Build, headless TestRoom load, smoke green.

## Test strategy
Smoke `tests/smoke/props_interact.gd` (async): all criteria via `Input.action_press`, positions
set directly, signal recording; sequence steps pressed one physics frame each with a frame between
(the panel reads just-pressed per physics frame). Only by hand: prompt readability, lamp look.

## Playtest (manual QA)
1. `TestRoom.tscn` (F6): ліворуч унизу зелена розетка, праворуч сіра панель з червоним екраном і
   темна лампа над нею. Підійти до розетки — знизу з'являється підказка «E: Зарядити».
2. Увімкнути F, зачекати, доки енергія впаде до ~90, натиснути E біля розетки: шкала стрибає на
   +25, індикатор розетки сіріє; E ще раз — нічого (підказка «Розряджена»).
3. Підійти до панелі, E: підказка показує послідовність «↑ · J · ↓ · ␣», екран жовтий; натискати
   по черзі W, J, S, Space — кожна правильна кнопка підсвічує наступний крок; після останньої екран
   зелений, лампа над панеллю вмикається і освітлює ділянку.
4. Повторити на свіжому запуску, але натиснути неправильну кнопку: екран блимає червоним, герой
   знову вільний, панель можна почати заново.
5. Під час послідовності герой не рухається і не б'є.

## Review focus
`signals/decoupling`, `state machine`, `input map`, `exports/tunables`, `scene/tscn integrity`.

## Performance & frame budget
Interaction area: one Area2D on the hero; nearest-pick only on enter/exit (no per-frame sort when
the overlap set is unchanged). Panel polls a handful of actions only while active.

## Risks
`Interact` interrupted by `Hurt` (T-06) must `Cancel()` the panel — handled in `Exit`. The prompt
label uses InputMap display names; keyboard-only glyphs for now (gamepad glyphs later).

## Open questions
None.

## Review findings

### Round 1 — Ship: yes

#### Summary
Adds the interaction layer: `Interactable` base (`Area2D`, layer 6, passive), `Outlet` (instant refill,
uses + cooldown, countdown prompt) and `PowerPanel` (3–4-action sequence polled in `_PhysicsProcess`
only while active, step timeout, fail flash), the hero's `InteractionArea` + nearest-pick +
`InteractableChanged`, a new `Interact` player state that leaves on the physics step *after*
`Finished`, a HUD prompt label, TestRoom wiring (prompt forwarding, `PH_Lamp` on `Activated`) and a
thorough smoke `props_interact.gd`. `combat_dummy.gd` gets a `_settle()` helper. No change to
`project.godot`, `.csproj`, `assets/`.

Verification (run from the worktree): `dotnet build` — 0 warnings / 0 errors; import skipped —
assets unchanged; `godot --headless --path . --quit` — no `ERROR:` lines; TestRoom headless load —
clean; `tools/smoke.ps1` — **7 passed, 0 failed** (`SMOKE props_interact PASS`, `SMOKE combat_dummy PASS`).

#### Plan conformance
Plan: `docs/plans/t05-outlet-panel/t05-outlet-panel-plan.md`
TASKS.md: T-05 `in_progress` — correct for this stage; the "done / not done" note is not written yet
(expected; must land with the `done` status).
- Implemented as planned: `Interactable` API + signals; `Outlet` (Amount/Cooldown/Uses exports,
  `Charged`, `Finished(false)` refusal, indicator colours, per-second countdown prompt); `PowerPanel`
  (Sequence/StepTimeout/FailResetDelay, `Activated`/`SequenceStep`/`SequenceFailed`, glyph prompt with
  bracketed current step, `CanInteract` false once activated); `Player.InteractionArea` (mask 32,
  r=36 at (0,-20)), `CurrentInteractable`, `InteractPressed`, `InteractableChanged`;
  `PlayerState.TryStartAction` → `Interact`; `PlayerInteract` with `Cancel()` on `Exit`; HUD
  `ShowPrompt/HidePrompt`; TestRoom wiring incl. `PH_Lamp` (`GradientTexture2D` radial, `enabled=false`)
  and `PH_LampBody` modulate; positions (300,560)/(1100,430)/(1100,330); `SaveId`; smoke + playtest list.
- Deviates from plan: (1) `PlayerInteract` returns to Idle on the **next physics step** after
  `Finished` rather than inside the handler (`scripts/player/PlayerInteract.cs:57-66`) — deliberate,
  documented in the class doc, and it is what prevents the final sequence key from leaking into
  Idle; verified by probe in both tree orders (panel before and after the hero) for `jump` and
  `attack` as the closing key — no Jump / no attack. Plan text is now stale on this point.
  (2) Prompt format is `"[↑] J ↓ ␣"` (space-separated, bracket marker) instead of the plan's
  `"↑ · J · ↓ · ␣"` example — cosmetic. (3) `Interactable` gained `IsActive`, `CurrentPrompt`,
  `Activate()/Finish()/NotifyPromptChanged()`; HUD gained `PromptText` — contract extensions, fine.
  (4) `tests/smoke/combat_dummy.gd:68-75` `_settle()` is outside the plan's file list. Justified:
  the heavier TestRoom makes the post-`add_child` physics burst longer; I ran `main`'s
  `combat_dummy.gd` against this branch 3× and it fails deterministically
  (`Dummy Visual.modulate=(1,1,1,1) right after the hit, expected a flash`) — the ~100 ms stall
  delta lands as the flash tween's first step. This is a harness artefact of loading a scene from a
  `SceneTree` script mid-iteration, not a game-side ordering bug: Godot's first-frame delta after
  a load is the same for every project and no game clamp is warranted. Right fix, right place.
- Missing / partial: TASKS.md done-note (pending); `tests/smoke/props_interact.gd.uid` not
  generated while every other smoke script has one (nit N3).
- Accepted limitation (per plan, "nearest-pick only on enter/exit"): with two props both in reach
  the pick is stale until an enter/exit event — residual risk is a **wasted single-use outlet**
  (probe: hero 23 px from a panel and 52 px from an outlet, both in range, `interact` charged and
  spent the outlet). Graded S4 below because the plan's rationale was performance, and the fix costs
  nothing at N ≤ 3.
- Accepted limitation (per plan): keyboard-only glyphs and the hard-coded `"E: {0}"` — nit N2.
- Acceptance criteria: all literally met and asserted by `props_interact.gd` (Energy 40→65,
  `Charged(25)`, Interact→Idle in 2 frames, spent/cooldown refusal, cap at Max, sequence 1..4 →
  `Activated` → lamp on, wrong key → `SequenceFailed` → retry, `InteractableChanged` outlet/null).

#### Code
- [ ] **B — none**

- [x] **S1. Hero soft-locks in `Interact` when the prop dies or is cancelled from outside** —
  `scripts/player/PlayerInteract.cs:57-66` (`PhysicsUpdate`) — Should-fix
  **Problem / why it matters:** the state leaves only on `_finished`, and `Cancel()` is documented
  to emit no `Finished`. Any path that ends the interaction without `Finish()` — the prop being
  `queue_free`d (level script, T-09 restore replacing props, a future wave clearing a room) or any
  caller of the public `Interactable.Cancel()` other than `Exit` itself (a "power cut" event) —
  leaves the hero standing in `Interact` with movement and attacks ignored until an enemy hits him.
  Probe: panel freed one step into the sequence → still `Interact` after 120 frames, `move_right`
  ignored; only `TakeDamage` freed him. Nothing in the repo triggers it today, hence not a Blocker.
  **Fix:** in `PhysicsUpdate`, also transition to Idle when
  `_interactable is null || !IsInstanceValid(_interactable) || !_interactable.IsActive`
  (i.e. treat "no longer active" as finished). Two lines; keeps `Cancel()` silent as designed.

- [x] **S2. Outlet prompt loses its `E: ` prefix after a use with no cooldown** —
  `scripts/props/Outlet.cs:113-115` (`Begin`) — Should-fix
  **Problem / why it matters:** `NotifyPromptChanged()` (114) runs while `IsActive` is still true,
  so `TestRoom.FormatPrompt` (`scripts/levels/TestRoom.cs:126-127`) returns the text without the
  key hint; `Finish(true)` (115) then clears `IsActive` but nothing re-announces the prompt. With
  the exported config `Uses = -1, Cooldown = 0` (plan: "0 = no cooldown") the HUD shows
  `Зарядити` instead of `E: Зарядити` until the hero leaves and re-enters (probe P5). Harmless for
  the TestRoom defaults (spent / cooling → no prefix anyway), wrong for a "free" outlet.
  **Fix:** call `Finish(true)` before `UpdateIndicator(); NotifyPromptChanged();` (the hero only
  sets a flag in its handler, so the order is safe), or have `Interactable.Finish` emit
  `PromptChanged` after clearing `IsActive`. `PowerPanel.Complete` has the same order but is
  unaffected (`IsActivated` → `CanInteract` false); align it anyway for one rule.

- [x] **S3. A `Sequence` action the panel never polls fails silently** —
  `scripts/props/PowerPanel.cs:96-104` (`_Ready`) vs `TrackedActions` (18-21) — Should-fix
  **Problem / why it matters:** `_Ready` warns only for actions missing from the InputMap.
  `interact` and `flashlight` exist in the InputMap but are not in `TrackedActions`, so a designer
  who sets `Sequence = ["move_up", "interact"]` gets a panel that can never be repaired — every
  attempt ends in a `StepTimeout` failure with no message (probe P9: step stuck at 1, `SequenceFailed`,
  no warning). Silent degradation.
  **Fix:** in the `_Ready` loop also `GD.PushWarning` when `System.Array.IndexOf(TrackedActions,
  (StringName)action) < 0` ("not polled during the sequence"); optionally make `TrackedActions`
  the union of itself and `Sequence`.

- [x] **S4. Nearest prop is not re-picked while two props stay in reach** —
  `scripts/player/Player.cs:329-350` (`RefreshCurrentInteractable`, called only from enter/exit)
  — Should-fix (accepted in plan as a perf trade-off; residual risk reported here)
  **Problem / why it matters:** outlet at x=1500 and panel at x=1560 (both in reach from x≈1520 to
  1548): hero enters at 1520 → outlet; walks to 1548 (23 px from the panel, 52 px from the outlet)
  — prompt still `E: Зарядити`, `interact` charges and **spends** the outlet (probe P6b). In a level
  where an outlet stands next to a panel the player wastes a one-shot resource by standing on the
  wrong pixel; the prompt is also wrong for the whole overlap band.
  **Fix (cheap, keeps the plan's intent):** re-pick only when `_nearbyInteractables.Count > 1` — in
  `Player._PhysicsProcess` (2–3 distance compares, no allocation) or lazily in
  `PlayerState.TryStartAction` before reading `CurrentInteractable` (fixes the action, not the
  prompt). The per-frame version also fixes the prompt; prefer it.

#### Tests
- [x] Freed / externally cancelled prop mid-interaction (S1) — assert Idle within a few frames after
  `panel.queue_free()` (or `panel.Cancel()`) one step into the sequence — `tests/smoke/props_interact.gd`
- [x] Outlet `Uses=-1, Cooldown=0` — assert `hud.PromptText == "E: Зарядити"` after the use (S2) —
  `tests/smoke/props_interact.gd` (extend section 3c with a third outlet or a `Cooldown = 0` pass)
- [x] Two props in reach, hero moves inside the overlap band — assert `CurrentInteractable` and the
  prompt follow the nearer prop (S4) — `tests/smoke/props_interact.gd`
- [x] Panel *after* the hero in tree order: the `panel2` retry (`props_interact.gd:520-533`) ends
  with `jump` but only checks Idle; add `_transitions == ["Interact", "Idle"]` and the
  `NO_JUMP_FRAMES` loop there so both process orders are guarded by the suite (my probe passed both)
- [ ] Playtest: prompt glyphs `↑ ↓ ← → ␣` render in the HUD font (the theme sets no font; the
  default font may lack U+2423 — boxes would show) — plan playtest step 3

#### Nits
- Stale sequence marker during the fail flash: `Fail()` (`scripts/props/PowerPanel.cs:205-217`)
  sets `FailColor` but never `NotifyPromptChanged()`, although `CurrentPrompt` (90-93) already
  handles `_failing`; the HUD keeps `[↑] J ↓ ␣` for `FailResetDelay` (probe P8) — one call in `Fail()`.
- `TestRoom.PromptFormat = "E: {0}"` (`scripts/levels/TestRoom.cs:39`) and `ActionGlyphs`
  hard-code keyboard labels; plan accepts keyboard-only for now — record a backlog line for
  InputMap-derived glyphs (rebinding / gamepad).
- `tests/smoke/props_interact.gd.uid` missing while the other six smoke scripts have one — run the
  editor / `godot --headless --path . --import` once and commit it.
- `PowerPanel.HandlePress` (`scripts/props/PowerPanel.cs:177`) compares `StringName != string`,
  allocating a `StringName` per press; cache `Sequence` as `StringName[]` in `_Ready` if it bothers.
- `PowerPanel.Begin` is not guarded against a second `Begin` while `IsActive` (resets `_step`) —
  irrelevant until co-op (phase 2).
- Interaction ignores depth: a prop can be used from up to ~56 px away in Y (r=40/44 + 36, centre
  at (0,-20)); no plan requirement, just note it before levels get tight prop placement.
- Timers: `StepTimeout`/`FailResetDelay` count physics `delta` and `Outlet` cooldown counts
  `_Process` `delta`; both are scaled by `Engine.TimeScale`, so they freeze during hit-stop. Acceptable:
  a hit on the hero cancels the panel before its hit-stop, and the outlet's 4–5 frozen frames are
  invisible. No action.

#### What's done well
- The "leave on the next physics step" design is exactly right and robust to tree order — probes:
  panel before/after the hero, closing key `jump` and `attack`, `interact`+`move_up` on the same
  frame (step not consumed — the panel starts polling next frame), `TakeDamage` fired from inside
  the `Finished` handler in both subscription orders → `[Interact, Hurt, Idle]`, no errors.
- `Interactable` invariants are clean: `Finish` clears `IsActive` before emitting, `Cancel` emits
  nothing and is idempotent (`PowerPanel.Cancel` early-outs), no double `Finished` on any path.
- Signal hygiene: every subscription has its symmetric disconnect (`Player._ExitTree`,
  `PlayerInteract.Exit` with `IsInstanceValid`, `TestRoom.FollowInteractable` + `_ExitTree`).
  `AreaExited` does fire for a freed prop (probe P4) so `_nearbyInteractables` never holds a dead ref.
- No per-frame allocations: the panel polls 8 `StringName`s only while active, the outlet counts
  down only while cooling and emits `PromptChanged` once per second, `BuildSequencePrompt` runs per press.
- Scenes: uids unique across `scenes/`, `load_steps` correct in all four files, layer 32 / mask 0 /
  `monitoring=false` match the documented contract, `PH_` prefix everywhere, `node_paths` complete,
  `project.godot` untouched (layer 6 and `interact` already existed).
- `props_interact.gd` asserts behaviour, not defaults: no-jump after the closing key, no
  `HeavyAttack` from a wrong key, hit cancels without `Finished`, timeout no earlier than
  `StepTimeout`, retry after failure, prompt text at every stage.
- `_settle()` in `combat_dummy.gd` is a measured fix with a written rationale, confirmed necessary.

#### Verdict
Ship: yes — no blockers; build, headless, TestRoom and all 7 smoke scripts green; the four
Should-fixes are small (S1 and S2 are two-liners) and none affects the TestRoom defaults. First:
1) S1 — leave `Interact` when the prop is no longer active/valid (soft-lock guard); 2) S2 — emit the
prompt after `Finish` in `Outlet.Begin`; 3) S4 — re-pick the nearest prop while `Count > 1`, then
extend `props_interact.gd` for the three cases above and write the TASKS.md done-note.
