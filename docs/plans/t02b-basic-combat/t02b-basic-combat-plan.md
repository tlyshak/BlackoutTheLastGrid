# Plan — t02b-basic-combat (T-02b · Базовий бій)

## Goal
Make hitting things feel right before any real enemy exists: a three-hit light combo and a heavy
attack on the hero, animation-driven hitbox windows, hit-stop, knockback/knockdown, a hurt flash,
and a training dummy with HP to receive it all in `TestRoom`. This is `GAME_DESIGN.md` §7 item 1a.

## Scope
- In: `Hitbox`/`HitInfo`/`IHittable`/`HitStop` in `scripts/core`; player states LightAttack1-3,
  HeavyAttack, Hurt, KO; `AnimationPlayer` on `Player` with method tracks that open/close the
  hitbox; `scenes/enemies/Dummy.tscn` + `scripts/enemies/Dummy.cs` (+ states); two dummies in
  `TestRoom` at different depths; smoke `tests/smoke/combat_dummy.gd`.
- Out: enemy AI/attacks (T-06), energy refund on hits (special, later), throws/juggles, real art
  and a real flash shader (placeholder = `Modulate` flash), jump attacks.

## Design-doc conformance
§4: light/heavy attack, 3–4 hit combo, hit-stop 3–5 frames, flash on the enemy. §6: hit-stop 3–5
frames. Task says "спалах шейдером (плейсхолдер — модуляція кольору)" → `Modulate` tween.
Hero damage → energy is T-06's rule, but `Player.TakeHit` already routes damage through
`GameState.Energy` so T-06 only adds enemies and the restart. Hit-stop stays within §6's 3–5
frames for every attack (heavy = 5; the first draft had 6, corrected in review round 1).

## Options considered
1. **Hitbox windows from `AnimationPlayer` method tracks** (chosen, as the task asks): attack
   animations exist even without art (they move a `PH_Fist` polygon) and the designer swaps in
   sprite frames later without touching code.
2. Timers inside the attack states: simpler, but the active window would drift from the future
   sprite animation. Rejected.
3. Hit-stop via pausing only the two animation players: local and safe, but the task and the
   design doc describe a global freeze; `Engine.TimeScale = 0` is used. The restore lives in the
   `HitStop` autoload (`ProcessMode = Always`), which restores the time scale from its own
   `_Process` using the wall clock — a `SceneTreeTimer` with a C# `Timeout` subscription was
   tried first and its callback never fired once the timer object went out of scope, so the
   restore must not depend on a temporary object. Since review #1 (T-03r) `Hitbox.TryHit`
   triggers it for every attacker.

## GameState & save impact
`Player.TakeHit` calls `GameState.AddEnergy(-Damage)`; KO when `Energy <= MinEnergy`. Nothing new
to persist.

## Scene & signal contract
`Player.tscn` additions:
```
Player
├── Visual
│   ├── PH_Fist (Polygon2D)           animated by the attack animations
│   └── Hitbox (Hitbox.cs, Area2D)    layer 4 / mask 3, Monitoring on, gated by Activate/Deactivate
│       └── CollisionShape2D (RectangleShape2D 36×40 at (30, 0))
├── AnimationPlayer                   light_1 (0.30 s), light_2 (0.30), light_3 (0.40), heavy (0.55),
│                                     hurt (0.30), ko (0.60); method tracks call Player.HitboxOn/HitboxOff
└── StateMachine
    ├── LightAttack1/2/3, HeavyAttack (PlayerAttack.cs)  exports below
    ├── Hurt (PlayerHurt.cs)
    └── KO (PlayerKO.cs)
```
`PlayerAttack` exports: `AnimationName` (StringName), `Damage` (hp), `Knockback` (px/s),
`Knockdown` (bool), `HitStopFrames` (frames), `NextCombo` (state name or ""), `ComboWindowStart`
(s from the start of the animation after which `attack` is buffered).
Defaults: L1 5/60/false/4/"LightAttack2"/0.06; L2 5/60/false/4/"LightAttack3"/0.06;
L3 8/160/false/5/""/0; Heavy 12/200/true/5/""/0. Light combo windows open at 0.06 s or as
soon as the hit window is active, so a press during the hit-stop still chains.
Player API: `AttackPressed`, `HeavyPressed`, `HitboxOn()`/`HitboxOff()` (animation method
tracks), `PlayAnimation` (now via `AnimationPlayer` when the animation exists there),
`IsAnimationPlaying(name)`, `CurrentAttack` (set by the attack state), `TakeHit(HitInfo)`,
`Hurt(float damage)` and `KnockedOut()` signals, `HurtKnockbackFriction` export.

`Dummy.tscn` (`scripts/enemies/Dummy.cs : CharacterBody2D, IHittable`, layer 3 / mask 1):
```
Dummy
├── PH_Shadow (Polygon2D)
├── Visual (Node2D at (0, -36))  PH_Body (Polygon2D 36×72, grey), PH_Face
├── CollisionShape2D (flat capsule)
├── Hurtbox (Area2D, layer 3 / mask 0, monitorable)  CollisionShape2D 32×64 at (0, -36)
├── HpLabel (Label above the head, "HP 30")
└── StateMachine: Idle, Hurt, Down, KO (DummyState.cs base)
```
Exports: `MaxHp` 30, `KnockbackFriction` 900 px/s², `HurtDuration` 0.25 s, `DownDuration` 1.0 s,
`FlashColor`, `FlashDuration` 0.12 s, `SpriteFeetOffset` 36. Signals: `Damaged(float hp)`,
`KnockedOut()`. `TakeHit`: ignored in KO; sets `Velocity.X = Knockback`, flashes, HP -= Damage;
HP <= 0 → KO, `Knockdown` → Down, else Hurt. Hurt/Down decay the velocity with the friction and
return to Idle. Down rotates `Visual` by 90°; KO stays down and dims.

`TestRoom`: `Dummy` at (640, 450) (same depth as the hero) and `Dummy2` at (760, 470)
(20 px deeper → out of DepthTolerance 12 until the hero moves down).

Collision: `Player/Visual/Hitbox` layer 4 mask 3; `Dummy/Hurtbox` layer 3 mask 0; `Dummy` body
layer 3 mask 1.

## File-level change list
- scripts/core: `HitInfo.cs`, `IHittable.cs`, `Hitbox.cs`, `HitStop.cs` (new)
- scripts/player: `Player.cs` (edit), `PlayerState.cs` (edit: names), `PlayerIdle.cs`/`PlayerMove.cs`
  (edit: attack transitions), `PlayerAttack.cs`, `PlayerHurt.cs`, `PlayerKO.cs` (new)
- scripts/enemies: `Dummy.cs`, `DummyState.cs`, `DummyIdle.cs`, `DummyHurt.cs`, `DummyDown.cs`,
  `DummyKO.cs` (new)
- scenes: `Player.tscn` (edit: fist, hitbox, AnimationPlayer, states), `Dummy.tscn` (new),
  `TestRoom.tscn` (edit: two dummies)
- tests/smoke: `combat_dummy.gd` (new)
- docs: this plan, TASKS.md note. project.godot: no change.

## Acceptance criteria
- Given the hero next to the dummy at the same depth, pressing `attack` three times inside the
  combo windows runs LightAttack1 → 2 → 3 (state names observed in order) and the dummy's HP drops
  by 5+5+8; pressing `attack` once only runs LightAttack1 then returns to Idle.
- Given `heavy_attack`, the dummy enters `Down` (Visual rotated), HP −12, is pushed right, and
  gets up to Idle after `DownDuration`.
- Given a hit, `Engine.TimeScale` is 0 for the attack's `HitStopFrames` and is back to 1 within
  `HitStopFrames / physics_ticks + 0.05 s` of wall time; the dummy's `Modulate` changes and
  returns to white.
- Given `Dummy2` 20 px deeper, the same attack does not hit it (HP unchanged); after the hero
  moves down 20 px it does.
- Given the dummy at 0 HP, it is in `KO`, further hits are ignored (TakeHit returns false).
- Given `Player.TakeHit(HitInfo{Damage 10})`, the hero enters Hurt, `GameState.Energy` drops by
  10 and it returns to Idle; with `Damage` ≥ current energy it enters KO and stays.
- Build, headless TestRoom load, smoke green.

## Test strategy
Smoke `tests/smoke/combat_dummy.gd` (async): instantiate `TestRoom`, place the hero at
(600, 450) facing right with the dummy at (640, 450); drive `attack`/`heavy_attack` with
`Input.action_press` for one physics frame; observe `CurrentStateName` per frame, `Dummy.Hp`,
`Engine.time_scale`, `Modulate`. Hit-stop freezes physics frames, so the test waits with
`create_timer(t, true, false, true)` (ignores time scale) where needed. Depth test with `Dummy2`.
Hero Hurt/KO via `Player.TakeDamage(damage, knockback, knockdown, hitStopFrames)` (a
Variant-friendly seam over `TakeHit`, since GDScript cannot build `HitInfo`). Only by hand: "feel"
of hit-stop and the fist motion.

## Playtest (manual QA)
1. Відкрити `scenes/levels/TestRoom.tscn` (F6). Два сірих манекени з написом `HP 30`, один на
   рівні героя, другий трохи нижче.
2. Підійти до першого і натиснути J тричі: кулак вилітає тричі, HP 30 → 25 → 20 → 12, на кожному
   попаданні гра завмирає на мить, манекен спалахує білим і відлітає трохи праворуч.
3. Натиснути K: важкий удар, манекен падає (лежить боком) на ~1 с, HP −12, потім встає.
4. Стояти на рівні першого манекена і бити в бік другого: другий не отримує шкоди, доки герой не
   спуститься до його лінії (W/S).
5. Добити манекен до 0: він лишається лежати темнішим, удари по ньому більше нічого не роблять.
6. Натиснути J один раз і не натискати більше: після першого удару герой повертається в Idle.

## Review focus
`hitbox/hurtbox`, `hit-stop/timescale`, `state machine`, `belt-scroll depth`, `scene/tscn integrity`.

## Performance & frame budget
Hitbox stays monitoring (one Area2D per actor); `GetOverlappingAreas()` allocates a Godot array
only on activation (a few times per second at most). Flash uses one Tween per hit.

## Risks
`Engine.TimeScale = 0` stops physics frames; anything awaiting `physics_frame` during a hit-stop
waits it out (fine in game, handled in tests). Hand-written `AnimationPlayer` tracks must keep
method names in sync with `Player` (`HitboxOn`/`HitboxOff`) — the smoke test would catch a rename.

## Open questions
None.

## Review findings

### Round 1 — Ship: yes

Reviewed at branch `task/t-02b-basic-combat`, commit d2aea6f (T-02b) on top of a13069d (T-02, see
`docs/plans/t02-player-movement/`), full delta `main...HEAD`, working tree clean. Cross-cutting
`scripts/core` findings live here. Verification re-run by the reviewer: `dotnet build` 0 warnings
/ 0 errors; `godot --headless --path . --quit` and `... res://scenes/levels/TestRoom.tscn
--quit-after 5` exit 0, no `ERROR:` lines; `tools/smoke.ps1` 4 passed / 0 failed. Findings marked
"probe" were confirmed with a throwaway GDScript driving `TestRoom.tscn` headless.

#### Summary
Adds the shared combat core (`Hitbox` always-monitoring and gated by `Activate`/`Deactivate` from
`AnimationPlayer` method tracks, `HitInfo`, `IHittable`, `HitStop` = `Engine.TimeScale = 0`
restored by a wall-clock node under the tree root), hero attack states LightAttack1-3 / HeavyAttack
with exported tunables and a buffered combo, Hurt / KO states, `Player.TakeHit` routing damage
into `GameState.Energy`, the training `Dummy` (HP, Modulate flash, knockback, Idle/Hurt/Down/KO),
two dummies in `TestRoom`, and `tests/smoke/combat_dummy.gd`.

#### Plan conformance
Plan: `docs/plans/t02b-basic-combat/t02b-basic-combat-plan.md`
TASKS.md: T-02b `done`; "Зроблено / Не зроблено" notes present and truthful (shader flash →
Modulate; `Player.TakeHit` only state-checked; restart in T-06); playtest checklist present.
- Implemented as planned: `Hitbox.cs` / `HitInfo.cs` / `IHittable.cs` / `HitStop.cs`; `PlayerAttack`
  exports and the four state nodes with exactly the plan's defaults (`scenes/player/Player.tscn:348-383`);
  `AnimationPlayer` with light_1/2/3, heavy, hurt, ko, RESET and `HitboxOn`/`HitboxOff` method
  tracks on `NodePath(".")` (all track paths resolve from the Player root; headless load clean);
  `Visual/Hitbox` layer 4 (bit 8) / mask 3 (bit 4) matches `Dummy/Hurtbox` layer 3 (bit 4) /
  mask 0; `Dummy.tscn` tree, exports, `Damaged` / `KnockedOut` signals; TestRoom dummies at
  (640, 450) and (760, 470); `Player.Hurt` / `KnockedOut` signals and `HurtKnockbackFriction`;
  `project.godot` unchanged in this commit.
- Deviates from plan: Test strategy says "Hero Hurt/KO via direct `TakeHit` calls" — the smoke
  (`tests/smoke/combat_dummy.gd:362-376`) drives `sm.TransitionTo("Hurt"/"KO")` instead, so the
  acceptance criterion "`Player.TakeHit(HitInfo{Damage 10})` → Energy −10 / KO at ≤ MinEnergy" has
  no automated coverage (S6). Heavy `HitStopFrames = 6` (`Player.tscn:381`) is the plan's own
  default, but GAME_DESIGN §6 says hit-stop 3–5 frames while the plan's Design-doc conformance
  claims "No disagreements" (S5). `Player.AnimationTime` (`Player.cs:215`) is API beyond the plan's
  list (harmless).
- Missing / partial: none of the File-level list. `HitStop.Cancel()` (`HitStop.cs:45-54`) is
  documented for "scene change, game over" but has no caller; the wall-clock restore covers it for
  now, T-06's restart should call it explicitly.
- Accepted limitation (per plan): global freeze via `Engine.TimeScale = 0` also freezes the attack
  animation, tweens and physics — residual risk: a press made during the freeze is dropped by the
  combo window (S2). `Hitbox.Activate` allocates one Godot array per activation — accepted, a few
  per second at most.

#### Code
- [x] **S1. Hurt / KO entered while airborne leave the hero floating** — `scripts/player/PlayerHurt.cs:15-22`, `scripts/player/PlayerKO.cs:15-21`, `scripts/player/Player.cs:224-250` — Should-fix
  **Problem / why it matters:** `Player.TakeHit` transitions straight to Hurt/KO; neither state
  integrates the jump, and Idle/Move never do. Probe: jump, at `Height` 45.75 → `TransitionTo("Hurt")`
  → 30 frames later state `Idle`, `Height` 45.75, `IsAirborne` true, `Visual.position.y` −81.75,
  still the same 60 frames later. The hero hangs in the air until the next jump press. Not reachable
  in T-02b (nothing attacks the hero) — it becomes a Blocker the moment T-06 enemies can hit a
  jumping hero.
  **Fix:** A (correct) — `Player.TakeHit` (or Hurt/KO `Enter`) resets `_z`/`_zVelocity` via a new
  `Player.Land()` and Hurt/KO `PhysicsUpdate` call `IntegrateJump(delta)` while `IsAirborne` so an
  airborne hero falls during the reaction; B (quick) — Idle/Move `PhysicsUpdate` guard
  `if (Player.IsAirborne) TransitionTo(StateJump)`.
- [x] **S2. `attack` pressed during the hit-stop of the same attack is dropped** — `scripts/player/PlayerAttack.cs:58-63`, `scenes/player/Player.tscn:355, 364` (ComboWindowStart 0.1) vs `:45` (HitboxOn key 0.08) — Should-fix
  **Problem / why it matters:** the light hit lands at animation time ≈ 0.08 s and freezes the
  animation; on the first physics step after the restore `AnimationTime` is still < 0.1, so the
  press seen there is not buffered and the combo ends. Probe: hit at `AnimationTime` 0.0819, attack
  held through the freeze → first physics step at 0.0889 → transitions `[LightAttack1, Idle]`;
  control press 60 ms after the restore → `[LightAttack1, LightAttack2, Idle]`. A single deliberate
  press inside the 67 ms freeze (the natural moment to press in a SoR-style game) loses the combo.
  **Fix:** A (correct) — buffer when `Player.AnimationTime >= ComboWindowStart || Player.Hitbox.IsActive
  || HitStop.IsActive` (the window opens with the hit); B (quick, scene only) — set `ComboWindowStart`
  of LightAttack1/2 to ≤ 0.05 so it precedes the hit key. Add the "press during freeze" case to the
  smoke (see Tests).
- [x] **S3. A second hit in the same reaction state does not restart the reaction** — `scripts/core/StateMachine.cs:94-97`, `scripts/enemies/Dummy.cs:92`, `scripts/enemies/DummyDown.cs:11-15`, `scripts/enemies/DummyHurt.cs:11`, `scripts/player/Player.cs:246`, `scripts/player/PlayerHurt.cs:12` — Should-fix
  **Problem / why it matters:** `TransitionTo` to the current state is a no-op, so `Enter` (which
  resets `_elapsed` / restarts the `hurt` animation) never runs on a repeat hit; damage, flash and
  knockback are applied but the timer is the old one. Probe: two heavies on Dummy2; the second lands
  while it is `Down` → HP 18→6, flash, new knockback, but it stands up 26 physics frames after the
  2nd hit instead of `DownDuration` = 60. Same path for the hero: Hurt→Hurt keeps the first `hurt`
  animation, so hit-stun does not refresh — that inconsistency between actors is exactly what
  T-06's combo rules would build on.
  **Fix:** A (correct) — add `StateMachine.Restart()` (Exit + Enter on the current state) and have
  `Dummy.TakeHit` / `Player.TakeHit` call it when `StateMachine.IsIn(target)`; B (local) — Hurt/Down
  states subscribe to `Dummy.Damaged` and reset `_elapsed` there.
- [x] **S4. `HitStop` is a static singleton with a self-installed root node** — `scripts/core/HitStop.cs:16, 78-94` — Should-fix
  **Problem / why it matters:** `CLAUDE.md` allows global state only in the `GameState` autoload;
  `HitStop` keeps `_instance` and the freeze deadline in statics and adds a node to `tree.Root` from
  inside a hit callback. It works (probe and smoke: the time scale is always restored, `_ExitTree`
  backstop present, single owner of `Engine.TimeScale`), but ownership is invisible in the tree and
  editor, `Cancel()` has no caller, and a second static singleton sets the precedent the rulebook
  forbids. Plan-accepted design, so not a blocker.
  **Fix:** A (correct) — register `HitStop` as an autoload via `/project-settings` (commit-body
  note) and drop `_instance` / `GetOrCreate`; B (quick) — create the node once from
  `GameState._Ready` as its child so the autoload is the owner and `Cancel()` is called from the
  T-06 restart.
- [x] **S5. Heavy hit-stop 6 frames exceeds GAME_DESIGN §6 (3–5 frames)** — `scenes/player/Player.tscn:381`, plan "Defaults" line — Should-fix
  **Problem / why it matters:** `CLAUDE.md`: when code and document disagree, the document wins;
  the plan's conformance section claims no disagreement. One exported number.
  **Fix:** set `HeavyAttack.HitStopFrames = 5` (or get the author's OK and amend §6 to "3–6").
- [x] **S6. `Player.TakeHit` → energy / Hurt / KO has no automated coverage** — `tests/smoke/combat_dummy.gd:362-376` — Should-fix
  **Problem / why it matters:** the plan's test strategy and acceptance criterion name direct
  `TakeHit` calls; GDScript cannot build a C# `HitInfo`, so the smoke only drives the states and
  never checks `Energy −10`, `Hurt` signal, KO at `≤ MinEnergy` or `TakeHit` returning false after KO.
  **Fix:** add a Variant-friendly seam, e.g. `public bool TakeHit(float damage, float knockback,
  bool knockdown, int hitStopFrames)` on `Player` (builds the `HitInfo`), then assert in the smoke:
  Energy drops by 10, state `Hurt`→`Idle`, `Velocity.X` sign, KO when damage ≥ energy, further
  `TakeHit` → false and state stays `KO`.

#### Tests
- [x] S6 — `Player.TakeHit` energy/Hurt/KO path — `tests/smoke/combat_dummy.gd`.
- [x] Facing-left hit not covered (probe confirms it works: `Facing` −1, `Visual.scale` (−1, 1), HP
  30→25, dummy pushed left) — add one left-facing hit to `tests/smoke/combat_dummy.gd` so a future
  hitbox reparenting cannot break it silently.
- [x] Regression steps for S2 (press during freeze must chain) and S3 (second knockdown restarts
  `DownDuration`) once fixed — `tests/smoke/combat_dummy.gd`.
- Playtest checklist present in the plan and TASKS.md.

#### Nits
- `HitInfo.SourceY` is captured at activation (`scripts/core/Hitbox.cs:53`) and compared at
  `:91`; fine while attackers stand still during attacks (`PlayerAttack.cs:65`), stale for a future
  moving attack — read `Attacker.GlobalPosition.Y` live in `TryHit`.
- `scenes/player/Player.tscn:1` `load_steps=20` but the file has 9 ext + 11 sub-resources + the
  scene = 21; harmless (progress hint only), the editor will rewrite it.
- `scenes/levels/TestRoom.tscn:5` references `Dummy.tscn` without `uid=` while the Player
  reference has one; the editor will add it — consistent style.
- `scripts/player/Player.cs:186-208`: an attack state whose `AnimationName` is not on the
  `AnimationPlayer` silently ends on the next physics frame — a `GD.PushWarning` would make a
  renamed animation visible.
- An attack interrupted by Hurt/KO leaves `PH_Fist` at its last keyed position (no RESET on
  interruption) — cosmetic until art replaces the fist.
- `scripts/core/HitStop.cs:20` `IsActive => Engine.TimeScale == 0.0` — brittle if any slow-motion
  ever sets 0.5; track a bool.
- Design observation (plan-conformant): a light hit on a `Down` dummy stands it up into Hurt
  (`Dummy.cs:92` → `DummyDown.Exit` → `SetDown(false)`); SoR keeps floored enemies down — decide
  before T-06 copies the rule.
- `scripts/enemies/Dummy.cs:107` rotates `Visual` about its centre (36 px above the feet), so the
  "lying" body floats — placeholder cosmetic.

#### What's done well
- `Hitbox` stays monitoring and is gated by `Activate`/`Deactivate`: no `Monitoring` toggles inside
  physics callbacks, targets already overlapping are hit on activation, `_alreadyHit` gives exactly
  one hit per activation, and the depth check lives in one shared place — the player and future
  enemies cannot drift apart.
- `HitStop` restores from the wall clock in a `ProcessMode.Always` node under the root with an
  `_ExitTree` backstop — the freeze never depends on the attacker, target or level surviving; the
  probe and smoke confirm the restore every time, including multiple hits and the KO case.
- Attack states carry all balance in exports; `PlayerAttack.Exit` closes the hitbox on any
  interruption, so a Hurt/KO mid-swing cannot leave an active hitbox.
- `Dummy.TakeHit` orders transition → flash so the KO dim and the flash tween compose correctly;
  the previous tween is killed before a new flash.
- `combat_dummy.gd` asserts real behaviour: hit-stop start and bounded duration, the inclusive
  depth boundary at exactly `DepthTolerance`, a miss at 20 px with no time-scale dip, KO ignoring
  further hits, transition order — and resets `Engine.time_scale` on exit.
- Signal handlers are unsubscribed in `_ExitTree` (`Player.cs:125`, `Hitbox.cs:47`).

#### Verdict
Ship: yes — no blockers; build, headless and smoke are green and the task's "done when" is
literally true (3-hit combo, heavy knockdown, hit-stop). S1–S3 are real combat-feel/consistency
bugs that T-06 will expose, so fix them before enemies arrive. First: S2 (combo window vs freeze),
S3 (reaction restart), S1 (airborne Hurt).
