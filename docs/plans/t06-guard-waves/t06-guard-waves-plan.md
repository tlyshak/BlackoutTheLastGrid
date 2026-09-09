# Plan — t06-guard-waves (T-06 · Ворог-боєць і хвилі)

## Goal
The first real fight: a `Guard` enemy that notices, approaches, telegraphs and hits the hero,
a `WaveSpawner` that locks the screen until the wave is cleared, damage to the hero as energy
loss with a scene restart at zero, and darkness as a real advantage. `GAME_DESIGN.md` §4
(belt-scroll waves, «GO →», max 2 attackers like SoR, stealth as an option: unlit hero is
unnoticed, first hit from the dark is doubled), §7 item 4.

## Author decisions applied (recorded in TASKS.md)
- **T-B01 — SoR rule:** a floored enemy (`Down`) is invulnerable and stays down for `DownDuration`;
  light and heavy hits on it are ignored (`TakeHit` returns false, no hit-stop). Applies to `Dummy`
  and `Guard`.
- **T-B02:** a KO'd hero may switch the lamp on again once energy is restored — no change.
- **Jump dodges low attacks:** the hero's `Hurtbox` moves under `Visual`, so it rises with the jump;
  an enemy hitbox at floor level misses a jumping hero. `Dummy`/`Guard` hurtboxes move under their
  `Visual` too for symmetry.
- **KO at zero:** the hero is knocked out only by a hit with `Damage > 0` that leaves
  `Energy <= MinEnergy` (a 0-damage hit never KOs).

## Scope
- In: `scenes/enemies/Guard.tscn` + `scripts/enemies/Guard.cs` and states (`GuardState` base,
  Idle, Approach, Attack, Hurt, Down, KO); `scripts/core/EnemyDirector.cs` (attack slots, max 2);
  `scenes/core/WaveSpawner.tscn` + `scripts/core/WaveSpawner.cs`; `scripts/levels/LevelBase.cs`
  (camera follow/lock, restart on hero KO) with `TestRoom` deriving from it; `Camera2D` in
  `TestRoom`; hero `IsLit` via a `LightSensor` area + `scripts/props/LitZone.cs` (Area2D layer 7);
  hurtboxes under `Visual`; Dummy Down invulnerability; smoke tests `enemy_guard.gd`, `enemy_wave.gd`.
- Out: enemy types 2–3 (heavy, shooter), weapons, throws, real art, enemy AI beyond the states
  listed, path-finding (straight-line approach on the floor plane).

## Design-doc conformance
§4 max 2 attackers, screen lock + «GO →», darkness advantage; §6 hit-stop 3–5 frames (Guard
attack uses 4). Task: telegraph 0.3 s, `Energy -= Damage`, restart at `Energy <= 0`, unnoticed
within half the distance when unlit, first hit from the dark doubled. No disagreements.

## Options considered
1. **Attack slots in an `EnemyDirector` node owned by the level/spawner** (chosen): guards ask
   `TryAcquireAttackSlot(this)` before `Attack` and release it after; no statics, testable.
2. Static counter on `Guard`: global state outside `GameState` — rejected by CLAUDE.md.
3. Perception via raycasts/occluders: overkill for the belt-scroll plane; distance + `Player.IsLit`
   (lamp on or inside a `LitZone`) is what the design describes.

## GameState & save impact
Damage → `GameState.AddEnergy(-Damage)` (already in `Player.TakeHit`). Restart:
`LevelBase.OnPlayerKnockedOut` → after `RestartDelay` → `HitStop.Cancel()`, `GameState.ResetRun()`,
`GetTree().ReloadCurrentScene()`. Nothing new to persist.

## Scene & signal contract
`Guard.tscn` (`scripts/enemies/Guard.cs : CharacterBody2D, IHittable`, layer 3 / mask 1, motion Floating):
```
Guard
├── PH_Shadow (Polygon2D)
├── Visual (Node2D at (0,-36))
│   ├── PH_Body (Polygon2D 36×72, dark red), PH_Face, PH_Fist (for the attack animation)
│   ├── Hurtbox (Area2D layer 3 / mask 0, RectangleShape2D 32×64)        ← under Visual (jump dodge)
│   └── Hitbox (Hitbox.cs, layer 5 / mask 2, RectangleShape2D 36×40 at (30, 0), Attacker = Guard)
├── CollisionShape2D (flat capsule)
├── AnimationPlayer: attack (0.55 s: telegraph 0–0.30 = wind-up pose, HitboxOn 0.30, HitboxOff 0.40),
│                    hurt (0.25), ko (0.60), RESET
├── HpLabel (Label)
└── StateMachine: Idle, Approach, Attack, Hurt, Down, KO   (GuardState base resolves Guard)
```
Exports on `Guard`: `MaxHp` 30, `MoveSpeed` 140 px/s, `DepthSpeedFactor` 0.75, `AttackRange` 46 px
(X distance at which Attack may start), `DepthTolerance` 12, `Damage` 8, `Knockback` 120,
`HitStopFrames` 4, `AttackCooldown` 0.8 s, `TelegraphTime` 0.3 s (documented; the animation carries
it), `PerceptionRange` 420 px, `DarkPerceptionFactor` 0.5, `DarkFirstHitMultiplier` 2.0,
`HurtDuration` 0.25, `DownDuration` 1.0, `KnockbackFriction` 900, `FlashColor`, `FlashDuration`,
`DimmedColor`, `SpriteFeetOffset` 36, `HoldDistance` 120 px (keeps this X distance when no attack
slot is free). Node exports: `Visual`, `Hitbox`, `HpLabel`, `AnimationPlayer`, `StateMachine`.
Runtime API: `Player? Target` (set by the spawner/level via `SetTarget(Player, EnemyDirector)`),
`bool IsAware`, `float Hp`, `bool IsKnockedOut`, `string CurrentStateName`, `bool TakeHit(in HitInfo)`
(Down → false; unaware → damage × `DarkFirstHitMultiplier` then aware), `Facing`.
Signals: `Damaged(float hp)`, `KnockedOut()`, `Noticed()`.
States: **Idle** — no target or not aware: each physics tick check `CanSee(Target)`: distance ≤
`PerceptionRange × (Target.IsLit ? 1 : DarkPerceptionFactor)` → aware, `Noticed`, → Approach.
**Approach** — move toward `Target` on X (stop at `AttackRange` if a slot is available, else hold
at `HoldDistance`) and align Y within `DepthTolerance`; face the target; when in range + aligned +
cooldown elapsed + `Director.TryAcquireAttackSlot(this)` → Attack. **Attack** — play `attack`
(telegraph = the first 0.3 s of the animation, `PH_Fist` pulls back, then strikes), `Hitbox`
active window via method tracks with `HitInfo(Damage, Knockback × Facing, false, HitStopFrames,
DepthTolerance, Y)`; on finish release the slot, start cooldown → Approach. **Hurt** — knockback
decay, `HurtDuration`, release slot → Approach (aware). **Down** — invulnerable, `DownDuration`,
visual rotated → Approach. **KO** — dimmed, stays; `KnockedOut`; `Director.Unregister`.
`scripts/core/EnemyDirector.cs : Node` — `[Export] MaxAttackers` 2; `bool TryAcquireAttackSlot(Node)`,
`void ReleaseAttackSlot(Node)`, `int ActiveAttackers`; clears slots of freed nodes.
`scenes/core/WaveSpawner.tscn` (`scripts/core/WaveSpawner.cs : Area2D`, layer 0 / mask 2):
```
WaveSpawner
├── CollisionShape2D (trigger rect: the hero entering starts the wave)
├── SpawnPoints (Node2D) ── Marker2D × N
└── GoOverlay (CanvasLayer, layer 11) ── GoLabel (Label "GO →", hidden)
```
Exports: `EnemyScene` (PackedScene = Guard), `Count` 3, `SpawnInterval` 0.4 s, `Player` (node
export set by the level), `Director` (EnemyDirector), `Camera` (Camera2D, optional),
`LockRect` (Rect2 — camera limits while locked; default = the current view), `SpawnAware` true (an alarm
wave charges the hero immediately; `false` = normal perception, darkness applies). Signals:
`WaveStarted()`, `EnemySpawned(Node2D enemy)`, `WaveCleared()`. Behaviour: hero enters →
`WaveStarted`, camera limits = `LockRect`, spawn `Count` guards at the markers (cycling) with
`SetTarget(Player, Director)`, subscribe `KnockedOut`; when all KO → `WaveCleared`, show "GO →"
for `GoDuration` 2 s, release the camera limits. Spent after one run (`[Export] OneShot` true).
`scripts/levels/LevelBase.cs : Node2D` — exports `Player`, `Camera` (Camera2D?), `RestartDelay`
1.0 s; `_Ready`: `Player.KnockedOut += OnKnockedOut`; `_Process`: camera follows the player X
(clamped by limits); `OnKnockedOut` → after the delay `HitStop.Cancel()`, `GameState.ResetRun()`,
`ReloadCurrentScene()`. `TestRoom` derives from it (keeps its debug label + HUD wiring).
`TestRoom.tscn`: `Camera2D` (limits 0..1920 × 0..1080, `position_smoothing`), `EnemyDirector`,
`WaveSpawner` (trigger at x 900–1000 across the floor; markers at (1500,430), (1600,500), (1700,460)),
`LitZone` (Area2D layer 7, CircleShape2D r=160) under `PH_Post` with a `PH_ZoneLamp` PointLight2D
(so "outside the light" is testable).
Hero: `LightSensor` (Area2D under `Player`, mask 64 = LightDark) → `Player.IsLit =>
Flashlight.IsOn || _litZones > 0`; `Hurtbox` reparented under `Visual`. `Player.TakeHit`: KO only
when `hit.Damage > 0` and energy hits the minimum.
`Dummy`: `TakeHit` returns false while `Down` (T-B01); hurtbox under `Visual`.
Collision (existing scheme): Guard body 3/1, Guard Hurtbox 3/0, Guard Hitbox 5/2 (hits Player
Hurtbox layer 2), WaveSpawner trigger mask 2, LitZone layer 7, LightSensor mask 7 (bit 64).
`project.godot`: no change expected (layer names exist).

## File-level change list
- scripts/enemies: `Guard.cs`, `GuardState.cs`, `GuardIdle.cs`, `GuardApproach.cs`, `GuardAttack.cs`,
  `GuardHurt.cs`, `GuardDown.cs`, `GuardKO.cs` (new); `Dummy.cs` (Down invulnerable)
- scripts/core: `EnemyDirector.cs`, `WaveSpawner.cs` (new)
- scripts/levels: `LevelBase.cs` (new), `TestRoom.cs` (derive)
- scripts/props: `LitZone.cs` (new)
- scripts/player: `Player.cs` (IsLit, LightSensor, KO rule), `Player.tscn` (Hurtbox under Visual, LightSensor)
- scenes: `enemies/Guard.tscn`, `core/WaveSpawner.tscn` (new), `enemies/Dummy.tscn` (hurtbox move),
  `levels/TestRoom.tscn` (camera, director, spawner, lit zone)
- tests/smoke: `enemy_guard.gd`, `enemy_wave.gd` (new); `combat_dummy.gd` (Down invulnerable)
- docs: this plan, TASKS.md (T-06 note; T-B01/T-B02 marked decided). project.godot: no change.

## Acceptance criteria
- Given a Guard at x+300 same depth and the hero lit (lamp on), within 60 frames the guard is
  aware (`Noticed`), approaches to `AttackRange`, and within 2 s enters `Attack`; ~0.3 s later the
  hero's `Hurt` signal fires with `Damage` 8, `Energy` drops by 8, hit-stop happened.
- Given the hero unlit (lamp off, outside any LitZone) at distance 300 (> 420 × 0.5), the guard
  stays Idle for 120 frames; at distance 180 (in front of the guard) it notices. Dark perception is
  directional: an unlit hero behind the guard is not noticed at all, which is what makes the
  "first hit from the dark" reachable (coder deviation, accepted).
- Given an unaware guard, the hero's light hit deals 10 (5 × 2) and the guard becomes aware; a
  second hit deals 5.
- Given three guards around the hero, at most two are in `Attack` at any physics frame over 5 s
  (`EnemyDirector.ActiveAttackers ≤ 2`), the third holds at `HoldDistance`.
- Given the hero jumping (`Height > 52`, derived from the shapes: hero hurtbox bottom −4−z must clear
  the guard hitbox top −56) when a guard's hitbox window opens, no `Hurt` fires.
- Given `Energy = 5`, one guard hit KOs the hero (`KnockedOut`), and within `RestartDelay + 0.5 s`
  the current scene is reloaded with `Energy == MaxEnergy` and `Engine.TimeScale == 1`.
- Given a Down dummy/guard, hits are ignored (`TakeHit` false, HP unchanged, no hit-stop) until it
  gets up.
- Given the hero entering the WaveSpawner trigger, `WaveStarted`, 3 guards spawn, the camera
  limits equal `LockRect`; after all three are KO'd, `WaveCleared`, "GO →" visible, limits released.
- Build, headless TestRoom load, smoke green.

## Test strategy
`enemy_guard.gd`: perception lit/unlit, approach, attack timing, damage/hit-stop, jump dodge, dark
double damage, Down invulnerability, KO + restart (drive with `Input.action_press`, `HitStop`-aware
waits on idle frames; for the reload use `get_tree().current_scene` semantics — set
`current_scene` to the room before the KO, then poll for the new instance).
`enemy_wave.gd`: trigger → spawn count, ≤ 2 attackers sampled each physics frame for 300 frames,
clear → `WaveCleared` + GO label visible + camera limits released. Only by hand: feel of the
telegraph, the GO arrow, camera lock.

## Playtest (manual QA)
1. `TestRoom.tscn` (F6): праворуч за стовпом стоїть темно-червоний охоронець. З вимкненим
   ліхтарем підійти на середню дистанцію — він стоїть; увімкнути F — він помічає і йде до героя.
2. Він зупиняється поруч, «замахується» ~0.3 с і б'є: шкала енергії падає на 8, герой відлітає.
   Підстрибнути в момент удару — удар проходить повз.
3. Вимкнути ліхтар, зайти йому в тил у темряві й ударити: перший удар знімає вдвічі більше HP.
4. Пройти праворуч через невидимий тригер: екран блокується, зі сходів праворуч з'являються три
   охоронці; одночасно б'ють не більше двох, третій тримає дистанцію. K кладе охоронця — лежачий
   не реагує на удари, поки не встане.
5. Після зачистки з'являється «GO →», камера відпускається.
6. Дати себе побити до нуля: ~1 с і кімната рестартує з повною енергією.

## Review focus
`hitbox/hurtbox`, `state machine`, `belt-scroll depth`, `hit-stop/timescale`, `signals/decoupling`,
`frame budget`, `scene/tscn integrity`, `GameState usage`.

## Performance & frame budget
Per guard per physics tick: one distance check, one `MoveAndSlide`; no allocations (cached
`Target`). Director slot ops are O(2). Spawner spawns with a timer, not all in one frame.

## Risks
Reload during a freeze: `HitStop.Cancel()` first. Guards pushing each other: bodies mask only World,
so they overlap visually — acceptable placeholder behaviour; `HoldDistance` spreads them on X.
Camera in a one-screen test room barely moves — the lock is still verified by limits.

## Open questions
None (decisions above).

## Review findings

### Round 1 — Ship: yes

**Summary.** The branch (uncommitted working tree, no commits yet) adds the first fighting enemy:
`Guard.tscn` + a six-state `StateMachine` (Idle / Approach / Attack / Hurt / Down / KO), an
`EnemyDirector` that caps simultaneous attackers at 2, a `WaveSpawner` that locks the camera limits,
spawns N guards at markers and shows «GO →» when they are all KO'd, a `LevelBase` that follows the
hero with the camera and reloads the scene after the hero's KO, darkness as perception (`Player.IsLit`
from the lamp or a `LitZone` via a `LightSensor` area; unlit = half range and only in front; first hit
from the dark ×2), hurtboxes moved under `Visual` so a jump dodges low punches, T-B01 (a Down enemy
is invulnerable) for Dummy and Guard, and two new smoke tests. `Hitbox` now resolves the hit target
through the hurtbox's `Owner` (fallback: nearest `IHittable` ancestor).

**Verification (run by the reviewer from the worktree).**
- `dotnet build` → `Build succeeded. 0 Warning(s) 0 Error(s)`.
- `godot --headless --path . --quit` → clean (no `ERROR:`/`SCRIPT ERROR:`/`WARNING:` lines).
- `godot --headless --path . res://scenes/levels/TestRoom.tscn --quit-after 5` → clean.
- `tools/smoke.ps1` → `SMOKE SUMMARY: 8 passed, 0 failed` (combat_dummy, core_gamestate,
  core_statemachine, enemy_guard, enemy_wave, player_flashlight, player_movement, ui_hud).
- Reviewer probe (`scratchpad/probe_t06.gd`, not committed): Attack→Down visual reset (S1, confirmed),
  rightward unmirrored punch lands (`Hurt=[8.0]`), 5 physics ticks with `delta = 0.0` during a
  hit-stop (state timers correctly frozen), `SpawnAware=false` wave blind to an unlit hero 50 px
  behind a spawned guard for 120 frames (S2, confirmed), a guard `queue_free`d mid-Attack releases
  its director slot (`ActiveAttackers=0`) but leaves `Alive=3 / IsRunning=true` (N4).

#### Plan conformance
Plan: `docs/plans/t06-guard-waves/t06-guard-waves-plan.md` (read in full, incl. "Author decisions
applied", Scene & signal contract, Risks).
TASKS.md: T-06 is `in_progress` — correct for an uncommitted tree; the "done / not done" note is
still pending (expected; to be written by /task together with marking T-B01/T-B02 decided — not
flagged). No unrelated changes in TASKS.md.
- Implemented as planned: every item of the File-level change list exists and is wired — Guard +
  6 states, `EnemyDirector`, `WaveSpawner` (.cs + .tscn), `LevelBase` with `TestRoom` deriving from
  it, `LitZone`, `Player.IsLit`/`LightSensor`/KO-only-on-damage rule, hurtboxes under `Visual` in
  Player/Dummy/Guard, Dummy Down invulnerability, `TestRoom.tscn` (camera, director, spawner, lit
  zone, standing guard), `enemy_guard.gd`, `enemy_wave.gd`, `combat_dummy.gd` T-B01 rewrite.
  Signals from the contract (`Damaged`, `KnockedOut`, `Noticed`, `WaveStarted`, `EnemySpawned`,
  `WaveCleared`) are all emitted and consumed. Collision scheme matches the contract exactly
  (Guard body 4/1, Hurtbox 4/0, Hitbox 16/2; Player Hurtbox layer 2 under `Visual`; LitZone 64;
  LightSensor mask 64; spawner 0/2). `project.godot`, `.csproj`, InputMap, `assets/` untouched.
- Deviates from plan: (a) directional dark perception (`Guard.CanSeeTarget`, `Guard.cs:200-220`) —
  accepted in the plan; (b) `WaveSpawner.SpawnAware` — accepted; (c) `Guard.tscn` `hurt` animation
  is 0.25 s (plan says 0.30) — matches `HurtDuration` 0.25, the plan line is stale (N1);
  (d) `Hitbox.FindHittable` (`Hitbox.cs:115-129`) — not listed in the plan's file list but required
  by "hurtboxes under Visual"; in scope, not drift.
- Missing / partial: the acceptance line "the third holds at `HoldDistance`" is implemented
  (`GuardApproach.cs:32-37`) but only *printed* by `enemy_wave.gd:296-306`, never asserted (T1).
  `SpawnAware = false` has no coverage (T2).
- Accepted limitation (per plan): directional dark perception — residual risk: an unlit hero may
  stand touching a guard's back forever without being noticed; combined with S2 a `SpawnAware=false`
  wave is blind to the hero arriving from the left (the belt-scroll direction). `TestRoom`'s
  `LockRect` equals the camera's own limits (`TestRoom.tscn:120` vs `:125-130`), so the lock is a
  no-op in the room (plan Risks acknowledges it); the smoke sets a tighter rect at runtime to observe
  both transitions — acceptable, the scene value is exercised only as "equal to limits".
- Design-doc note: `GAME_DESIGN.md` §4 says disoriented enemies take double damage "for the first
  2 s of the fight"; TASKS T-06 and the plan say "the first hit from the dark". The code implements
  the task wording. Not a code issue — the two documents should be reconciled (N6).

#### Code
- [ ] **B — none.**
- [x] **S1. A guard knocked down mid-Attack stands upright while Down (invulnerable)** —
  `scripts/enemies/GuardAttack.cs:34` (`ResetPose()` in `Exit`) + `scripts/enemies/GuardDown.cs:15`
  (`SetDown(true)` in `Enter`) + `scripts/enemies/Guard.cs:341-348` — Should-fix
  **Problem / why it matters:** `Attack.Exit` plays `RESET` (`Play` + `Seek(0, update)`) and leaves
  it *playing*; `Down.Enter` then sets `Visual.Rotation = π/2` in the same call. On the next idle
  frame the `AnimationPlayer` advances `RESET` to its end and re-applies its `Visual:rotation = 0`
  key, so the guard snaps back upright while `StateMachine` is still `Down` for the whole
  `DownDuration`. Probe: `TakeDamage(12, 60, knockdown)` at `attack` pos 0.076 → `state=Down
  rotation=1.571`, +2 idle frames → `rotation=0.000`, +10 physics frames → `state=Down
  rotation=0.000`. This is the most common way to floor a guard (heavy during its 0.3 s telegraph),
  and it hides exactly the T-B01 rule the player must read: an upright guard that ignores hits looks
  like a bug, not like "he is down". Attack→Hurt/KO are unaffected (they play `hurt`/`ko`, which
  replace `RESET`); Dummy and Player are unaffected (no non-rest pose set in the same frame).
  **Fix:** Option A (correct, minimal): in `Guard.ResetPose` stop the player after applying the keys
  — `AnimationPlayer.Play(RESET); Seek(0, update: true); AnimationPlayer.Stop(keepState: true);` —
  so the rest pose is applied once and nothing keeps re-applying it (mirror it in `Player.ResetPose`
  as a backlog line, it is harmless there today). Option B (consistent with `ko`): add a `down`
  animation to `Guard.tscn` (`Visual:rotation` key π/2, 0.05 s) and play it from `GuardDown.Enter`
  instead of `SetDown(true)` — the animation then owns the pose like `ko` does. Either way add the
  regression check T4.
- [x] **S2. `WaveSpawner` never faces spawned guards toward the hero, so a `SpawnAware=false` wave is
  blind to the hero coming from the left** — `scripts/core/WaveSpawner.cs:199-211` (`SpawnOne`) —
  Should-fix
  **Problem / why it matters:** spawned guards keep `Facing = +1` (scene default). With the accepted
  directional dark rule (`Guard.cs:209-216`) an unlit hero is only seen in front of the guard, so
  guards spawned to the right of the hero (the normal belt-scroll layout: markers at x 1500–1700,
  hero at ≤ 1350) have their back to him. Probe with `SpawnAware=false`: hero unlit at (1450, 430),
  50 px behind guard 1, for 120 frames → all three `[Facing 1, IsAware false, Idle]`; lamp on →
  noticed within 5 frames. A designer who sets `SpawnAware=false` for a "dark path" wave gets a wave
  the hero can punch one by one from behind at ×2 with nobody ever noticing (not the "unnoticed
  within half the distance" of the task — unnoticed at any distance). With the default
  `SpawnAware=true` the first `Approach` tick fixes the facing, so the TestRoom wave is fine.
  **Fix:** in `SpawnOne`, after `SetTarget`, `guard.FaceTowards(Player.GlobalPosition.X -
  enemy.GlobalPosition.X)` (guards enter facing the fight, which is also what SoR does); or an
  `[Export] int SpawnFacing` (0 = toward the hero). Cover with T2.
- [x] **S3. Per-tick managed-string allocation in the guard's Attack state** —
  `scripts/enemies/GuardAttack.cs:44` → `Guard.IsAnimationPlaying` (`Guard.cs:337-338`) — Should-fix
  **Problem / why it matters:** `AnimationPlayer.CurrentAnimation` marshals a new .NET `string`
  every call, and comparing it with the `StringName` converts again — two allocations per physics
  tick per attacking guard for the 0.55 s of every punch. Bounded by `MaxAttackers` (2) today, but it
  is the pattern the next enemy types will copy (`scripts/enemies/**` is the multiplied path). It
  mirrors the pre-existing `Player.IsAnimationPlaying`, which is why this is not a Blocker.
  **Fix:** inside Attack only `attack` can be playing, so `PhysicsUpdate` can use
  `Guard.AnimationPlayer.IsPlaying()` alone (no string); or subscribe `AnimationFinished` once in
  `Guard._Ready` and expose a `bool AttackAnimationDone` flag. Keep the name check only in `Exit`
  (runs once).

#### Tests
- [x] T1 — "the third guard holds at `HoldDistance`" is printed but not asserted — add to
  `tests/smoke/enemy_wave.gd` (§3): `_check(frames_holding > 0, ...)` and, on frames where two are
  in `Attack`, the third's `|dx|` to the hero ≥ `HoldDistance - 10` (it converges without overshoot,
  `Guard.VelocityTowards`).
  *Done (§3): `frames_holding > 0` (76/300 in 3 runs), max `|dx|` ≥ `HoldDistance − 10` (observed
  163–168). A lower bound near `HoldDistance` is unattainable by design: the holder is usually the
  guard that just finished its own punch at `AttackRange` (45 px) walking back out, so the observed
  min is 44.7–45.0. Asserted instead: min `|dx|` ≥ `AttackRange − 5` (the holder never closes in)
  and convergence — on consecutive holding frames of the same holder `|dx − HoldDistance|` never
  grows by more than 2.5 px (worst observed 0.00 px over ~70 pairs).*
- [x] T2 — `SpawnAware = false` uncovered — `tests/smoke/enemy_wave.gd`: a second run (or a
  separate room) with `spawner.SpawnAware = false`, lamp off, hero at the trigger: after the spawns
  every guard is `Idle`/unaware and faces the hero (`Facing == -1`, once S2 is fixed); lamp on → all
  `Noticed` within 5 frames.
  *Done (§7, fresh room): note the trigger lies inside the `LitZone`, so the unlit checks are made
  from (1050, 450); all three `Noticed` 1 frame after the lamp from (1300, 450).*
- [x] T4 — regression for S1 — `tests/smoke/enemy_guard.gd` §5: knock the guard down *during its
  telegraph* (wait for `Attack`, 2–3 frames, then heavy/`TakeDamage(..., knockdown)`) and assert
  `Visual.rotation ≈ π/2` after 2 idle frames and again 30 physics frames later while still `Down`.
  *Done (§5b): `TakeDamage(12, 200, knockdown)` on the first `Attack` frame; rotation 1.571 after
  2 idle frames and min 1.571 over 30 `Down` frames; also asserts the `AnimationPlayer` is stopped
  after `ResetPose`, the hitbox is closed, the slot released, and the guard stands (0) afterwards.*
- [x] T5 (nit-level) — `enemy_guard.gd:52,470`: `MIN_DODGE_HEIGHT = 20` is not the geometric dodge
  threshold. With the scene shapes (guard hitbox y ∈ [-56, -16], hero hurtbox y ∈ [-68-z, -4-z]) the
  punch misses only for `z > 52`; the test passes because the real assertion (no `Hurt`) holds and
  z ≈ 73 at the 0.3 s window. Either raise the constant to the derived value (and say so) or drop
  the height check so it cannot mislead the next reader. Same for the plan's acceptance line
  ("Height > 20").
  *Done: `MIN_DODGE_HEIGHT = 52` with the derivation in the comment, and §4 re-derives the
  threshold from the live shapes (`SpriteFeetOffset`, shape sizes/offsets) and asserts it equals
  the constant; observed Height 65.0 at the window. Acceptance line updated.*

#### Nits
- N1 — plan line 58 says `hurt (0.30)`; `Guard.tscn:58` is 0.25 (= `HurtDuration`). Update the plan.
- N2 — `Guard.Facing` is a free `[Export] int` (`Guard.cs:97`); a `0` set in the inspector makes
  `Visual.Scale.X = 0` (`Guard.cs:441`, invisible, `CanSeeTarget` "in front" never true). Clamp in
  the setter (`value < 0 ? -1 : 1`) or export a `bool FacesLeft`.
- N3 — `tests/smoke/enemy_guard.gd` / `enemy_wave.gd` have no `.gd.uid` side files while every
  other smoke script's `.uid` is tracked; the editor will generate them on first open → add them to
  the commit to avoid an untracked-file surprise later.
- N4 — `WaveSpawner._alive` (`WaveSpawner.cs:235-242`) only decrements on `KnockedOut`; a guard freed
  without KO (no code path today — probe F) leaves `Alive` stuck and the wave never clears. When a
  despawn path appears, prune like `EnemyDirector` does or hook `TreeExiting`.
- N5 — `EnemyScene!` (`WaveSpawner.cs:195`): the bang is justified by the `StartWave` check, but a
  root that is not a `Node2D` throws in `Instantiate<Node2D>()` — a `GD.PushError` + return would
  match the rest of the file's tone.
- N6 — doc discrepancy: `GAME_DESIGN.md` §4 "double damage for the first 2 s" vs TASKS T-06 "first
  hit from the dark ×2" (implemented). Reconcile one way or the other in the docs.
- N7 — `LevelBase.RestartLevel` (`LevelBase.cs:58`) calls `GameState.ResetRun()`, which also clears
  `Route`; correct for now (plan says so), but a KO restart inside Level 2 will forget the route
  once it exists — worth a `backlog` line for T-08/T-09.

#### What's done well
- Slot arbitration is clean and leak-free: acquire only at the Approach→Attack edge, release in
  `Attack.Exit`, `Hurt/Down/KO.Enter` and `_ExitTree`, plus `Prune()` on freed nodes — the probe
  confirmed a guard freed mid-swing releases its slot the same frame.
- `Guard.ActiveTarget` centralises every `IsInstanceValid` / `IsQueuedForDeletion` / `IsKnockedOut`
  check, so no state ever touches a freed or KO'd hero; guards drop to Idle when the hero is KO'd.
- Hit-stop hygiene holds: only `HitStop` and `HitStop.Cancel()` (from `LevelBase.RestartLevel`)
  touch `Engine.TimeScale`; the restart timer is `processAlways + ignoreTimeScale`, kept in a field,
  unsubscribed in `_ExitTree`, and re-validated in the callback; the smoke shows the reload landing
  ≥ 900 ms after a KO punch that itself triggered a hit-stop. Physics ticks with `delta = 0` during
  the freeze leave every `_elapsed` and cooldown untouched, and `VelocityTowards` guards `dt <= 0`.
- `VelocityTowards` (reach-the-point-this-step, clamped per axis) gives jitter-free Y alignment and
  a stable hold distance — no oscillation observed over 300 sampled frames.
- One shared hit path (`Hitbox.TryHit` → depth check → `TakeHit` → `HitStop.Trigger`) now serves
  hero, Dummy and Guard identically; T-B01 is implemented the same way in both enemies.
- All `.tscn` files are consistent: `load_steps` counts, uids, `node_paths`, animation track paths
  (`Visual/PH_Fist`, `Visual/PH_Body`, method track on `.` → `HitboxOn/Off`) and layer bits all
  check out; `WaveSpawner` is `y_sort_enabled` so spawned guards sort with the hero.
- The smoke tests assert what they claim (real Hurt/Energy deltas, hit-stop observed via
  `min_scale`, overlap actually witnessed before asserting "ignored", the ≤ 2 rule sampled per
  physics frame, reload timing bounded from both sides) and they clean up `time_scale` and rooms.

#### Verdict
Ship: yes — no blockers; build, headless loads and all 8 smoke scripts are green, and the plan's
contract (waves, ≤ 2 attackers, GO, darkness, KO restart, T-B01) is implemented with correct depth
rules and time-scale hygiene. The three Should-fixes are contained (one visual state bug, one
facing rule for the non-default spawner mode, one allocation pattern) and can land in a fix-pass
before or right after the T-06 commit. First: **S1** (Down pose clobbered by `RESET` — most visible
in play), then **S2** + **T2** together, then **T1** and **S3**.
