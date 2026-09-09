# Plan — t03-flashlight-darkness (T-03 · Ліхтар і темрява)

## Goal
Make darkness the default and the head lamp the hero's main light and main resource: a
`PointLight2D` cone on the hero toggled with `flashlight`, a `CanvasModulate` base darkness in the
level, and an energy drain into `GameState.Energy` while the lamp is on (lamp dies at 0).
`GAME_DESIGN.md` §4 «Ліхтар = ресурс», §6 lighting, §7 item 2.

## Scope
- In: `scripts/player/Flashlight.cs` + `Flashlight` node in `Player.tscn` (`PointLight2D`, cone
  from a procedural `GradientTexture2D` sub-resource, toggled by the `flashlight` action, drains
  energy, dies at `MinEnergy`, follows facing and jump height); `CanvasModulate` `#0a0d14` in
  `TestRoom.tscn`; smoke `tests/smoke/player_flashlight.gd`; playtest.
- Out: HUD energy bar (T-04), outlets/panels that recharge (T-05), enemy perception in the dark
  (T-06), normal maps / real light textures (art), light occluders and shadows.

## Design-doc conformance
§6: "`PointLight2D` + `CanvasModulate` для темряви; ліхтар героя — конус світла з м'яким краєм".
The task says «текстура-градієнт»: no file under `assets/` exists and the agent never creates
art, so the cone is a `GradientTexture2D` built inside the scene (a Godot resource, not an art
asset); a painted texture can replace it in the inspector later. §4 says the charge refills at
outlets/panels — that is T-05; here the drain only goes down. No disagreements.

## Options considered
1. **Own `Flashlight : PointLight2D` node with its own script** (chosen): one node = one script,
   input polling and drain live with the light; `Player` only positions it (facing, height).
2. Toggle inside the player states: the lamp must work in every state (walking, attacking,
   hurt), so state-based handling would be duplicated. Rejected.
3. Light under `Visual` to inherit the flip: negative parent scale on a `Light2D` is not a
   documented-safe transform; the light is a direct child of `Player` and is rotated by π for
   facing left instead.

## GameState & save impact
Reads/writes `GameState.Energy` through `AddEnergy(-DrainPerSecond * delta)` every physics step
while on; after each drain it reads `Energy` back and switches off at `MinEnergy` (polling,
no signal subscription to clean up). `IsOn` is per-run transient
(starts off); nothing new to persist in T-09.

## Scene & signal contract
```
Player
└── Flashlight (PointLight2D → scripts/player/Flashlight.cs)  position (0, -HeadOffset), enabled = false
      texture = GradientTexture2D 512×256 (radial, fill_from (0, 0.5) → fill_to (0.5, 0.5): bright
      at the left edge fading to α = 0 on every other edge = a soft half-ellipse beam pointing +X),
      offset puts the left edge at the lamp, texture_scale 2.2, warm color
TestRoom
└── CanvasModulate  color #0a0d14 (base darkness)
```
Exports on `Flashlight`: `DrainPerSecond` float 1.0 (energy/s); `HeadOffset` float 60 px
(distance from the feet to the lamp); `BeamAngleDeg` float 0 (reserved tilt); `EnabledAtStart`
bool false. Signals: `Toggled(bool isOn)` emitted on every change (input, energy death,
`SetOn`). API: `bool IsOn`, `void Toggle()`, `void SetOn(bool on)` (refuses to turn on at
`MinEnergy` → stays off, no signal), `void Follow(int facing, float height)` called by
`Player.UpdateVisual`. Input: `flashlight` just-pressed polled in `_PhysicsProcess` (works in
every state, and headless via `Input.action_press`). Drain: in `_PhysicsProcess` while on;
when `GameState.Energy <= MinEnergy` after a drain → `SetOn(false)`.
`Player` gets `[Export] Flashlight Flashlight` and calls `Flashlight.Follow(Facing, Height)`
from `UpdateVisual`. No new collision layers. No `project.godot` change.

## File-level change list
- scripts/player: `Flashlight.cs` (new), `Player.cs` (edit: export + Follow call)
- scenes: `Player.tscn` (edit: Flashlight node + GradientTexture2D), `TestRoom.tscn` (edit:
  CanvasModulate)
- tests/smoke: `player_flashlight.gd` (new)
- docs: this plan, TASKS.md note. project.godot: no change.

## Acceptance criteria
- Given TestRoom, the root has a `CanvasModulate` child with color `#0a0d14` and the hero has a
  `Flashlight` `PointLight2D` with a texture, `enabled == false` at start.
- Given the lamp off and `Energy == MaxEnergy`, pressing `flashlight` once turns it on
  (`enabled`, `IsOn`, `Toggled(true)`); after 60 physics frames `Energy ≈ MaxEnergy − 1.0`
  (± 0.05); pressing again turns it off and the energy stops dropping.
- Given `Energy = 0.3` and the lamp on, within 30 frames the lamp is off, `Toggled(false)` was
  emitted once, `Energy == MinEnergy`; pressing `flashlight` now leaves it off.
- Given the hero facing left, the light's rotation is π (beam points −X); facing right → 0;
  during a jump the light's Y follows `-(HeadOffset + Height)`.
- Build, headless TestRoom load, smoke green.

## Test strategy
Smoke `tests/smoke/player_flashlight.gd` (async): all criteria above via `Input.action_press`,
`GameState` and node inspection. Only by hand: how dark the room looks, the cone's softness and
reach, that the debug label on the `CanvasLayer` stays readable.

## Playtest (manual QA)
1. Відкрити `scenes/levels/TestRoom.tscn` (F6): кімната майже чорна (синьо-сірий відтінок), напис
   стану зверху видно, силуети героя й манекенів ледь помітні.
2. Натиснути F: перед героєм з'являється теплий конус світла, підлога і манекен у конусі стають
   видимими. Натиснути F ще раз — темрява.
3. Із увімкненим ліхтарем постояти 10 с: у Remote-інспекторі автолоада `GameState` поле `Energy`
   падає зі 100 приблизно до 90 (шкала на екрані з'явиться в T-04); вимкнути — падіння зупиняється.
4. Повернутися ліворуч (A): конус дивиться ліворуч. Стрибнути: конус піднімається разом із героєм.
5. Розрядити енергію до 0 (для тесту тимчасово виставити `MaxEnergy` = 3 у інспекторі автолоада
   або почекати): ліхтар гасне сам і більше не вмикається.

## Review focus
`GameState usage`, `input map`, `exports/tunables`, `signals/decoupling`, `frame budget`,
`scene/tscn integrity`.

## Performance & frame budget
One `PointLight2D` (Forward+ 2D lighting is cheap at this count); one `AddEnergy` call per physics
step while on; no allocations per frame.

## Risks
`AddEnergy(-1/60)` per step is far above `GameState`'s float tolerance, so the drain accumulates
(the setter always stores the clamped value since the T-01 review). `CanvasModulate` also dims
`PH_` placeholder polygons — expected, that is the point.

## Open questions
None.

## Review findings

### Round 1 — Ship: yes

#### Summary
The branch adds the head lamp: `scripts/player/Flashlight.cs` (a `PointLight2D` script that polls
`flashlight` in `_PhysicsProcess`, drains `GameState.Energy` via `AddEnergy`, switches itself off at
`MinEnergy`, refuses to turn on without energy, emits `Toggled`), a `Flashlight` node in
`Player.tscn` with a procedural `GradientTexture2D` beam, `Player.Flashlight` export + `Follow(Facing,
Height)` from `UpdateVisual`, a `CanvasModulate #0a0d14` in `TestRoom.tscn`, and the smoke test
`tests/smoke/player_flashlight.gd`. Reviewed surface: `git status --porcelain` (4 modified, 4
untracked entries; `main...HEAD` is empty, everything is in the working tree). All entries covered;
`docs/plans/t03-flashlight-darkness/` is this plan, `scripts/player/Flashlight.cs.uid` is the
generated side file.

Verification run by the reviewer (2026-09-09):
```
Build:    passed ; new warnings: none (0 Warning(s), 0 Error(s))
Import:   skipped — assets unchanged
Headless: passed ; warnings: 0   (godot --headless --path . --quit)
Smoke:    5 pass / 0 fail
          combat_dummy → PASS, core_gamestate → PASS, core_statemachine → PASS,
          player_flashlight → PASS, player_movement → PASS
Scene:    res://scenes/levels/TestRoom.tscn --quit-after 5 → passed
Verdict:  verified
```
Reviewer probes (throwaway GDScript, not committed) confirmed: during a real `HitStop.Trigger`
(4-frame light hit on the Dummy) `_PhysicsProcess` still runs but with `delta == 0` for exactly the
frozen frames — drain over a 31-frame window with 5 frozen frames was `26/60 = 0.4333`, i.e. the lamp
does not drain during hit-stop; with `get_tree().paused = true` the drain is 0 (Player is
`Pausable`); a hit that zeroes the energy while the lamp is on switches it off on the next physics
tick with exactly one `Toggled(false)`; a KO'd hero with `Energy == 0` cannot turn the lamp on.

#### Plan conformance
Plan: `docs/plans/t03-flashlight-darkness/t03-flashlight-darkness-plan.md`
TASKS.md: T-03 is `in_progress`; the done-note is not written yet — expected at this stage, not a
finding. No new `backlog` lines were needed.
- Implemented as planned: `Flashlight.cs` with the four exports (`DrainPerSecond` 1.0,
  `HeadOffset` 60, `BeamAngleDeg` 0, `EnabledAtStart` false), `IsOn` / `Toggle` / `SetOn` /
  `Follow`, `Toggled` signal on every change and silent refusal at `MinEnergy`; `Player.Flashlight`
  export wired via `node_paths` and `Follow` from `UpdateVisual` (`Player.cs:304`); `Flashlight`
  node as a direct child of `Player` (not under the flipped `Visual`), rotation π for facing left;
  `CanvasModulate` on the `TestRoom` root canvas (the `UI` `CanvasLayer` has its own canvas, so the
  debug label stays unmodulated); smoke test covers every acceptance criterion; playtest list
  present; `project.godot` untouched (the `flashlight` action already existed with F / joypad 9).
- Deviates from plan: the plan's *GameState & save impact* and *Scene & signal contract* say the
  lamp "listens to `EnergyChanged` to switch off at `MinEnergy`"; the code polls `state.Energy`
  right after its own drain (`scripts/player/Flashlight.cs:64-69`). Functionally equivalent within
  one physics tick (probe: a hit zeroing the energy turns the lamp off next tick) and it avoids a
  subscription that would need `_ExitTree` cleanup — the code is the better of the two, the plan
  text is stale (Nit N1).
- Accepted limitation (per plan): the cone is a procedural `GradientTexture2D`, to be replaced by a
  painted texture later — residual risk: the current gradient is not a cone and has a hard clipped
  edge (S1 below).
- Acceptance criteria: all five literally hold (smoke green: on/off via input, drain 1.0 ± 0.05 over
  60 frames, death at 0.3 energy with one `Toggled(false)`, refusal afterwards, rotation π / 0,
  Y = −(HeadOffset + Height) mid-jump; build, headless, TestRoom load green).

#### Code

##### Blockers
- none

##### Should-fix
- [x] **S1. Beam texture is clipped by a hard straight edge and is a half-disc, not a cone** —
  `scenes/player/Player.tscn:28-34` (`GradientTexture2D_beam`) and `:355-357` (`Flashlight`
  `texture` / `offset` / `texture_scale`) — Should-fix
  **Problem / why it matters:** `GradientTexture2D` radial fill uses normalized coordinates:
  offset = |pos − fill_from| / |fill_to − fill_from|. With `fill_from (0, 0.5)`, `fill_to (1, 0.5)`
  on a 256×256 texture the gradient radius equals the full width, so at the top and bottom edges
  right next to the origin (pos `(0, 0)` / `(0, 1)`) the offset is only 0.5 → with the stops
  `0.35 → α 0.55`, `1 → α 0` that is **α ≈ 0.42**. Outside the texture rect the light is zero, so
  the beam ends in a straight horizontal cut 128 × 2.2 ≈ 282 px above and below the lamp with ~42 %
  intensity at the cut (it fades to 0 only along the top edge at x ≈ 0.87). Concrete scenario: in
  `TestRoom` (F6), lamp on, the lit area is a half-disc with two razor-straight top/bottom borders
  and it lights the floor 282 px straight up and down from the hero as much as it lights 282 px
  ahead — GAME_DESIGN §6 asks for «конус світла з м'яким краєм», playtest step 2 for «конус … перед
  героєм». Verified by the gradient formula (headless cannot render; `get_image()` is null there) —
  confirm visually in the playtest.
  **Fix (only `.tscn` values; the smoke test checks `texture != null` and is unaffected):**
  - Option A (correct, beam-shaped): `width = 512`, `height = 256`, `fill_to = Vector2(0.5, 0.5)`
    (radius = half the width → 256 × 128 px ellipse, α = 0 on every texture edge), keep
    `texture_scale = 2.2` (reach 563 px, vertical half-extent 282 px, soft everywhere) and set
    `offset = Vector2(563, 0)` (= 512 × 2.2 / 2 so the bright pole still sits on the lamp origin).
  - Option B (quick, half-disc but soft): keep 256×256, `fill_to = Vector2(0.5, 0.5)`,
    `texture_scale = 4.4`, `offset = Vector2(563, 0)`.
  Either way re-check playtest step 2 and 4 (edge softness, mirror when facing left — `offset` is
  in the light's local space, so the π rotation mirrors it).

#### Tests
- Smoke `tests/smoke/player_flashlight.gd` asserts what it claims: toggle + `Toggled` counts, drain
  computed from `Engine.physics_ticks_per_second` (60 frames → 1.0 ± 0.05 = 3 frames of slack, and
  `Engine.time_scale == 1` is asserted first), no drain while off, death from 0.3 energy with
  exactly one extra `false`, refusal with no signal, rotation via `angle_difference`, lamp Y vs
  `Height` read in the same frame, `SetOn` idempotency. `quit(1)` on failure and on the frame cap.
  Nothing missing against the plan's Test strategy.
- [ ] Optional coverage (not required by the plan): "no drain during hit-stop" and "lamp dies one
  tick after a hit zeroes the energy, `Toggled(false)` once" — both verified by reviewer probe;
  either fits `tests/smoke/player_flashlight.gd` (lamp on, `player.TakeDamage(5, 0, false, 0)` with
  `Energy = 1`) or `combat_dummy.gd` (lamp on, land one light hit, expect drop =
  (frames − HitStopFrames) / ticks).
- Playtest step 3 («у консолі/дебазі `GameState.Energy` падає») is not executable as written: nothing
  prints the energy and the debug label shows only state / z. Until T-04, watch `GameState › Energy`
  in the editor's Remote scene tree inspector, or rely on the smoke drain check — reword the step
  (see N4).

#### Nits
- N1. Plan text stale: "listens to `EnergyChanged`" → "polls `Energy` after each drain" —
  `docs/plans/t03-flashlight-darkness/t03-flashlight-darkness-plan.md:35,53-54`.
- N2. Dead scene values: `Flashlight._Ready` overwrites `enabled` and `position` unconditionally
  (`scripts/player/Flashlight.cs:41,48`), so `enabled = false` / `position = (0, -60)` in
  `scenes/player/Player.tscn:350-351` are informational only; a designer setting `enabled = true` in
  the inspector gets silently reverted — `EnabledAtStart` is the knob. A one-line doc comment on
  `EnabledAtStart` ("overrides the inspector `enabled`") would prevent the confusion.
- N3. `Toggled(true)` from `_Ready` when `EnabledAtStart` fires before any sibling can connect
  (`Flashlight.cs:43-46`); future listeners (HUD, enemy perception in T-06) must read `IsOn` on
  connect, not rely on the initial signal. Worth a sentence in the `Toggled` summary.
- N4. Playtest step 3 wording (see Tests).
- N5. A KO'd hero can still toggle the lamp once energy is restored (probe: `Energy = 50` while in
  `KO` → `IsOn = true`). Unreachable today (KO only at `Energy == 0`, recharge needs `interact` in
  T-05), so no failure scenario; note it for T-05/T-06 (either `Player` calls `SetOn(false)` on KO or
  the outlet is unusable while KO'd).
- N6. Side files: `scripts/player/Flashlight.cs.uid` is untracked and should be committed with the
  script (siblings are tracked); `tests/smoke/player_flashlight.gd.uid` does not exist yet while the
  other four smoke scripts have one — an editor scan (or `godot --headless --path . --import`)
  generates it; commit it for consistency.
- N7. `HeadOffset` (60) and `Player.SpriteFeetOffset` (36) both describe the placeholder body's
  geometry; when real art lands, both need retuning together. Not a bug — two different anchors.

#### What's done well
- The lamp owns its mechanic end to end (input, drain, death, signal) in one node with one script;
  `Player` only positions it — exactly the plan's option 1, no state duplication across the seven
  player states, no `GetNode` across the scene boundary.
- `SetOn` semantics are tight: refusal at `MinEnergy` without a signal, idempotent, `IsOn` and
  `Enabled` always move together; `Toggle` and `EnabledAtStart` both go through it.
- No per-frame allocations, `StringName` cached, drain through `AddEnergy` so the clamp and
  `EnergyChanged` rules of T-01 hold; delta-scaled drain means hit-stop (delta 0) and slow-mo are
  handled for free — verified by probe.
- Light placed as a direct child of `Player` and rotated instead of parented under the negatively
  scaled `Visual` — the right call for a `Light2D`.
- `.tscn` integrity is clean: `load_steps = 24` = 10 ext + 13 sub + 1, unique sub-resource ids,
  `node_paths` extended, `CanvasModulate` on the level canvas so the `UI` `CanvasLayer` stays
  readable.
- The smoke test is a real test: signal-count assertions, drain math derived from the tick rate,
  guard checks that fail loudly when the C# assembly is stale, and every branch ends in `quit()`.

#### Verdict
Ship: yes — no blockers; build, headless, TestRoom load and all five smoke scripts are green, and
every acceptance criterion holds. The one Should-fix is a `.tscn`-only texture correction (S1) that
makes the beam a soft cone instead of a hard-edged half-disc. First: 1) S1 texture values
(Option A) + playtest steps 2/4; 2) N1 plan wording + N4 playtest step 3; 3) N6 commit the `.uid`
side files.
