# Codebase review 1 — `main` @ b9ab71d (2026-09-09)

Whole-codebase audit (not a branch delta), written as a standalone file by explicit exception to
the reviewer skill's "no standalone report" rule. Reviewed against `CLAUDE.md`, `GAME_DESIGN.md`
§4 / §6 / §7, `docs/TASKS.md` and the three plans under `docs/plans/` (rounds already closed there
are not re-reported unless the fix is wrong). Surface: every file under `scripts/`, `scenes/`,
`tests/smoke/`, `tools/`, `project.godot`, `BlackoutLastGrid.csproj`, `.sln`, `.gitignore`,
`.gitattributes`, `docs/TASKS.md`. Working tree clean, nothing untracked.

Verification run by the reviewer (2026-09-09, from the repo root):
```
Build:    passed ; new warnings: none (0 Warning(s), 0 Error(s))
Import:   passed (godot --headless --path . --import, exit 0, no ERROR: lines)
Headless: passed ; warnings: 0   (godot --headless --path . --quit)
Smoke:    5 pass / 0 fail
          combat_dummy → PASS (14.6–14.7 s over 3 runs), core_gamestate → PASS,
          core_statemachine → PASS, player_flashlight → PASS (3.5 s), player_movement → PASS (5.4 s)
Scene:    res://scenes/levels/TestRoom.tscn --quit-after 5 → passed
Verdict:  verified
```
Findings marked **(probe)** were confirmed with throwaway GDScript scripts run headless against
`TestRoom.tscn` (not committed; numbers quoted are from those runs).

## Summary
The codebase at HEAD is the T-01…T-03 vertical slice: `GameState` and `HitStop` autoloads, a
generic `StateMachine`/`State`, the hero (`Player.tscn`, 8-way belt-scroll movement, fake-Z jump,
LightAttack1-3 / HeavyAttack / Hurt / KO states, `AnimationPlayer` method tracks gating a shared
`Hitbox`, `Flashlight` head lamp draining energy), the training `Dummy` (HP, flash, knockback,
Idle/Hurt/Down/KO), `TestRoom` with two dummies and a `CanvasModulate`, five smoke scripts and the
PowerShell smoke runner. Build, headless load, scene load and all smoke tests are green. The
architecture follows `CLAUDE.md` closely; the issues found are consistency gaps that the next tasks
(T-04…T-09) would turn into real bugs, plus one repository-hygiene item and one test-robustness item.

## Architecture & conventions conformance
- **Coupling:** no `GetNode("..")`, no absolute paths, no cross-scene `GetNode`. Every cross-node
  link is an `[Export]` (`Player.Visual/Sprite/Hitbox/StateMachine/Flashlight`, `Dummy.Visual/HpLabel/
  StateMachine`, `TestRoom.Player/DebugLabel`, `StateMachine.InitialState`) or a signal
  (`Player.StateChanged/Hurt/KnockedOut`, `Dummy.Damaged/KnockedOut`, `Hitbox.Hit`,
  `Flashlight.Toggled`, `GameState.EnergyChanged`, `StateMachine.StateChanged`). The only reach
  across a scene boundary is `Hitbox.TryHit` → `area.GetParent()` (`scripts/core/Hitbox.cs:85`),
  which is the documented Hurtbox contract. Conformant.
- **Global state:** `GameState.Instance` (`scripts/core/GameState.cs:30`) and `HitStop.Instance`
  (`scripts/core/HitStop.cs:17`) — both registered autoloads (`project.godot:17-20`). `HitStop`
  is a second static singleton, but it holds only the transient freeze deadline and was accepted
  in the T-02b round (S4). All other statics are `static readonly StringName`/`Color` constants.
  Conformant, with the note that the two autoloads assign `Instance` at different times
  (`GameState._Ready` vs `HitStop._EnterTree`) — see Nits.
- **Input:** only InputMap actions, cached as `StringName` (`Player.cs:16-22`,
  `Flashlight.cs:14`); no `Key.*`, `IsKeyPressed`, joypad constants anywhere (grep-verified).
  Conformant.
- **Tunables:** every balance number is an `[Export]` with a default (`Player.cs:37-62`,
  `PlayerAttack.cs:15-34`, `Dummy.cs:24-43`, `Flashlight.cs:20-30`, `GameState.cs:37-42`).
  Exceptions are visual constants only (`Dummy.DimmedColor` `Dummy.cs:14`, animation names in
  `PlayerHurt.cs:13` / `PlayerKO.cs:9`) — Nits.
- **Placeholders:** every `Polygon2D`/`ColorRect` test visual is `PH_`-prefixed in all three scenes.
  Conformant.
- **One scene = one script:** `Player.tscn`↔`Player.cs`, `Dummy.tscn`↔`Dummy.cs`,
  `TestRoom.tscn`↔`TestRoom.cs`; `Main.tscn` has no script and no content (see Readiness question).
  Conformant.
- **Namespaces:** `BlackoutLastGrid.Core` (core), `.Actors` (player + flashlight), `.Enemies`,
  `.Levels`, `.Tests` (smoke support). Consistent.
- **Nullable:** `null!` only on scene-assigned exported node refs and the two autoload `Instance`
  statics; no `!` bangs elsewhere; build has 0 warnings. `GameState.Instance` is dereferenced
  without a null guard in `Player.TakeHit` and `Flashlight` (valid in-game; the `HitStop.Trigger`
  path does guard). Conformant.
- **XML docs:** every public type/member documented; `Player.PlayAnimation` lacks `<param>` tags.
  Fine.
- **Process split:** movement, `MoveAndSlide`, drain and input polling are in physics
  (`StateMachine._PhysicsProcess` → `PhysicsUpdate`, `Flashlight._PhysicsProcess`); the only
  `_Process` consumers are `HitStop` (wall-clock restore) and `TestRoom` (debug label). Visual
  transform updates happen from physics via `Player.UpdateVisual` — acceptable (transforms, not
  rendering).
- **Per-frame allocations:** none in `PhysicsUpdate`/`_PhysicsProcess` paths. `Hitbox.Activate`
  allocates one Godot array per activation (`Hitbox.cs:57`, plan-accepted); `TestRoom.RefreshLabel`
  formats a string when the rounded height changes (debug room only); `Dummy.UpdateHpLabel` per hit.
- **Belt-scroll rules:** `y_sort_enabled` on `TestRoom` (`TestRoom.tscn:11`); feet at the node
  origin for both actors (`Visual` at `(0, -36)`); `motion_mode = 1` (Floating) on both bodies;
  depth check in one shared place (`Hitbox.cs:91-95`) with `DepthTolerance` exported on the
  attacker and inclusive at exactly the tolerance (smoke-covered). Conformant.
- **Collision layers vs `[layer_names]`:** Player body 2/1, `Player/Hurtbox` 2/0
  (`Player.tscn:340-343`), `Player/Visual/Hitbox` 8/4 = layer 4 PlayerHitbox → mask 3 Enemy
  (`:322-324`), Dummy body 4/1, `Dummy/Hurtbox` 4/0 (`Dummy.tscn:45-49`), walls 1/0. All match
  `project.godot:76-84` and the plans' tables.
- **`.tscn` integrity:** `load_steps` correct in all three scenes (24 = 10 ext + 13 sub + 1;
  9 = 6 + 2 + 1; 5 = 3 + 1 + 1); scene uids unique (`ct2db4jsifoal`, `cx22u1thref1a`,
  `c5as8u6w2way2`, `daxl3pdeadvpe`); every `ext_resource` path exists; `node_paths` resolve; all
  animation track paths (`Visual/PH_Fist:position`, `Visual:modulate`, `Visual:rotation`,
  `Visual/PH_Body:rotation`, method track on `.`) resolve from the Player root; `HitboxOn`/
  `HitboxOff` exist on `Player`. All 23 script `.uid` files and the 5 smoke `.uid` files present and
  unique.
- **Lifecycle:** every subscription has an `_ExitTree` counterpart (`Player.cs:134-138`,
  `Hitbox.cs:47`, `TestRoom.cs:31`); `Dummy` guards its tween with `IsValid()` before `Kill()`
  (`Dummy.cs:143`); `HitStop` restores from the wall clock in a `ProcessMode.Always` node with an
  `_ExitTree` backstop. **(probe)** Freeing a Dummy in the middle of its hit-stop and flash tween →
  no errors, time scale restored in 69 ms. **(probe)** `reload_current_scene()` issued while
  `Engine.time_scale == 0` → reload OK, time scale back to 1 in 62 ms, both autoload `Instance`
  statics intact, the new room's hero Idle, a hit in the new room freezes/restores normally.
  `GameState.Energy` survives the reload (T-06 must call `ResetRun()` explicitly).

## Blockers
- none

## Should-fix
### S1. Hero `Hurt` re-entry does not restart the stun — the T-02b S3 fix covers the Dummy only
**File:** `scripts/player/PlayerHurt.cs:16` (`Enter` → `Player.PlayAnimation(Animation, AnimIdle)`),
`scripts/player/Player.cs:207-213` (`PlayAnimation` → `AnimationPlayer.Play`), `scripts/player/Player.cs:277`
(`TransitionToOrRestart(StateHurt)`)
**Problem / why it matters:** `TransitionToOrRestart` correctly calls `Exit`+`Enter` on the current
state, but the hero's `Hurt.Enter` only calls `AnimationPlayer.Play("hurt")`, and Godot 4's `play()`
on the animation that is already playing keeps its current position (documented behaviour). The
Dummy restarts because `DummyHurt.Enter` resets `_elapsed`; the hero's stun length is the `hurt`
animation, which is never rewound. **(probe)** `TakeDamage(2)` → 8 frames → `hurt` at 0.125 s →
second `TakeDamage(2)` → next frame the animation is at 0.138 s (continues) and the hero is back in
`Idle` **11 frames** after the second hit instead of 18; the Dummy under the same sequence returns
exactly 15 frames after its restart. TASKS.md T-02b claims "повторний удар перезапускає реакцію" for
both actors; the plan's S3 is marked `[x]`. The moment T-06 lets two Guards hit in quick succession,
the second hit's stun is silently shortened and combat rules differ between the hero and enemies.
**Fix:** A (correct, one place) — make `Player.PlayAnimation` (or a new `PlayAnimation(name, restart:
true)`) call `AnimationPlayer.Stop()` / `Seek(0, true)` before `Play` when `CurrentAnimation ==
animation`, and use it from `PlayerHurt.Enter`; B (local) — in `PlayerHurt.Enter`, `if
(Player.IsAnimationPlaying(Animation)) Player.AnimationPlayer.Seek(0.0, true);`. Either way add the
hero half of the S3 regression to `tests/smoke/combat_dummy.gd` (second `TakeDamage` 8 frames into
Hurt → `Idle` no earlier than 18 frames after the second hit).

### S2. Entering Idle/Move while airborne re-launches the jump (`StartJump` in `Jump.Enter`)
**File:** `scripts/player/PlayerState.cs:60-64` (`TryStartAction`: `IsAirborne` → `TransitionTo(StateJump)`),
`scripts/player/PlayerJump.cs:13-17` (`Enter` → `Player.StartJump()`), `scripts/player/Player.cs:172-175`
**Problem / why it matters:** the "back to Jump if somehow airborne" guard sends the hero into
`Jump`, whose `Enter` unconditionally sets `_zVelocity = JumpVelocity`. So any path that lands the
hero in Idle/Move mid-air does not just resume the fall — it fires a fresh jump from the current
height. **(probe)** jump, at frame 25 (`Height` 76.7, near the apex) force `TransitionTo("Idle")`
→ next frames 82.8, 88.6, 94.2, 99.5, 104.6: the hero shoots up again to ~157 px. Not reachable
today (Hurt/KO integrate the fall before leaving), which is why it is not a blocker, but T-06 (a
jump attack returning to Idle, a Guard grab interrupting a jump) or T-05 (an interact state) will
hit it, and the guard exists precisely for those cases. Also `Player.Land()` (`Player.cs:178-183`)
has no caller.
**Fix:** A (correct) — `PlayerJump.Enter`: `if (!Player.IsAirborne) Player.StartJump();` so the
state can be entered as "already in the air"; B (quick) — replace the guard in `TryStartAction` with
`Player.Land()` (snap to the floor) — cheaper but visibly wrong for a mid-air interruption. Add a
smoke step: force Idle at frame 25 → `Height` must decrease from the next frame and `Jump` must be
entered once.

### S3. `*.import` is gitignored — texture import settings will not be versioned once art lands
**File:** `.gitignore:3` (`*.import`)
**Problem / why it matters:** Godot's `.import` side files hold per-asset import settings (filter,
mipmaps, `process/normal_map`, compression) and are meant to be committed; only `.godot/` is
generated. With `*.import` ignored, the first painted sprite sheet or light texture tuned in the
editor (e.g. the normal-map flag that GAME_DESIGN §6 relies on) will import with defaults on every
other checkout and in CI, and `git status -- assets/` (the `/verify` trigger for `--import`) will
not show the change. `assets/` holds only `.gitkeep` today, so nothing is lost yet.
**Fix:** delete the `*.import` line (keep `.godot/`). If the intention was to keep binary noise out,
note that `.import` files are small text files. Mention the change in the commit body (repo config).

### S4. Combo chain in `combat_dummy.gd` relies on a 59 ms wall-clock margin
**File:** `tests/smoke/combat_dummy.gd:262-267` (`await _real_wait(0.15)` between hits), also `:446-449`
**Problem / why it matters:** after each hit the test waits for the time-scale restore on idle
frames, then a fixed 0.15 s of real time, then presses. **(probe)** the press is seen at
`AnimationTime` 0.241 s in every run; the `light_1` window closes at 0.300 s → 59 ms (≈3.5 physics
ticks) of slack. One stalled idle frame of 60 ms (a .NET GC pause, a loaded CI runner, the first run
after a rebuild) puts the press in `Idle`, the transitions become `[LightAttack1, Idle,
LightAttack1, …]` and the run fails although the game is correct. 3/3 local runs pass in 14.7 s; the
risk is on other machines.
**Fix:** drive the chain by animation time instead of the wall clock: after `_wait_restored`,
`await physics_frame` until `player.AnimationTime >= ComboWindowStart` and
`player.CurrentStateName == "LightAttackN"`, then press (fail explicitly if the state is already
`Idle`). Same idea for the S2 step (`:446-449`), which already self-diagnoses "idle frames too slow".

### S5. Hit-stop is triggered in `Player`, not in the shared `Hitbox` — T-06 will duplicate it
**File:** `scripts/player/Player.cs:289` (`OnHitboxHit` → `HitStop.Trigger(CurrentAttack.HitStopFrames)`),
`scripts/core/Hitbox.cs:97-101` (`TryHit` emits `Hit` after a successful `TakeHit`)
**Problem / why it matters:** `HitInfo.HitStopFrames` travels with the hit and `Hitbox` already
knows when a hit connected, yet the freeze is wired by the attacker via the `Hit` signal. `Guard`
(T-06) must remember to subscribe and call `HitStop.Trigger` too; forgetting it means enemy hits
have no hit-stop while the hero's do — the "duplicate hit logic drifting between actors" pattern
the reviewer checklist flags. Today there is one attacker, so this is preparation, not a bug.
**Fix:** in `Hitbox.TryHit`, after `hittable.TakeHit(...)` returns `true`, call
`HitStop.Trigger(_info.HitStopFrames)` and drop `Player.OnHitboxHit` (keep the `Hit` signal for
feedback such as sparks). `HitStop.Trigger` is already null-safe.

## Nits
- `Player.ResetPose()` is ineffective when an attack is interrupted: `Play("RESET")` is replaced by
  `Play("hurt")` in the same call stack before the RESET keys are applied. **(probe)** `light_1`
  interrupted at 0.12 s → `PH_Fist` stays at `(34, -10)` for the whole `hurt` animation and after.
  Cosmetic with the placeholder fist; use `AnimationPlayer.Seek(0, true)` on RESET, or key the fist
  in `hurt`/`ko` — `scripts/player/Player.cs:232-238`, `scripts/player/PlayerAttack.cs:57-65`.
- `Hitbox.TryHit` does not exclude its own `Attacker`; if a hitbox's mask ever includes the layer
  of its owner's hurtbox it hits itself. **(probe)** a `Player` instance with its hitbox mask set
  to 2 hit its own hurtbox first. Not reachable with the current layer plan (player hitbox mask 3,
  enemy hitbox mask 2), but `if (ReferenceEquals(target, Attacker)) return;` is a one-line
  safety — `scripts/core/Hitbox.cs:85-89`.
- `Player/Hurtbox` is a child of the root, not of `Visual`, so it does not rise with the jump while
  the `Hitbox` does. **(probe)** an enemy-style hitbox (layer 5 / mask 2) at ground level hits the
  hero at `Height` 49.6. This is a design decision for T-06 (does jumping dodge low attacks?), not
  a bug — record the decision in the T-06 plan — `scenes/player/Player.tscn:340-347`.
- `tests/smoke/support/SmokeState.cs` is compiled into the game assembly (`BlackoutLastGrid.csproj`
  default globbing). Acceptable for now (one tiny class, no `[Tool]`/global-class side effects), but
  the cleanest option is to keep it out of exports:
  `<Compile Remove="tests/**" Condition="'$(Configuration)' != 'Debug'" />` in the csproj (Debug is
  what the editor and the headless smoke runs load, so the tests stay green), plus excluding
  `tests/` in the export preset. Alternatives (a GDScript `State`, a separate test assembly) do not
  work: `StateMachine` dispatches `Enter`/`Exit` as C# virtuals, and a second assembly is a project
  change needing agreement — `BlackoutLastGrid.csproj:10`.
- Dead API: `Player.Land()` (`scripts/player/Player.cs:178-183`) and `HitStop.IsActive`
  (`scripts/core/HitStop.cs:23`) have no callers; `HitStop.Cancel()` has none either (documented
  for T-06's restart — keep). Either use `Land()` in S2's fix or remove it.
- `PlayerState.AnimHurt` / `AnimKO` (`scripts/player/PlayerState.cs:22-25`) duplicate the private
  `Animation` names in `PlayerHurt.cs:13` / `PlayerKO.cs:9`; and unlike `PlayerAttack.AnimationName`
  these two are not exports. Pick one: export on the state, or the shared constants.
- `GameState.MaxEnergy` / `MinEnergy` are `[Export]` on an autoload *script* (no scene), so they are
  not editable in the inspector; only the Remote tree at runtime can change them (which is what
  the T-03 playtest step 5 relies on). Worth a doc comment — `scripts/core/GameState.cs:37-42`.
- `GameState.Instance` is assigned in `_Ready`, `HitStop.Instance` in `_EnterTree`, and only
  `HitStop` clears it in `_ExitTree`. Harmless for autoloads; align for consistency —
  `scripts/core/GameState.cs:80-85`, `scripts/core/HitStop.cs:26-41`.
- `Player.UpdateVisual` writes four transforms every physics tick even in Idle
  (`ApplyFloorMove(Vector2.Zero)` → `UpdateVisual` → `Visual.Position/Scale`, `Flashlight.Follow`).
  Negligible for one hero; do not copy the pattern into `Guard` × N — `scripts/player/Player.cs:300-305`,
  `PlayerIdle.cs:27`.
- `Dummy.DimmedColor` is a private constant while `FlashColor` is exported — `scripts/enemies/Dummy.cs:14`.
- `Dummy.tscn:49` `monitorable = true` is the default (harmless); `Player.tscn` omits it. Same
  meaning, different style.
- `RouteType` values are implicit (`None = 0 …`); pin them explicitly before T-09 writes them to
  JSON, and `tests/smoke/core_gamestate.gd:40` already depends on `None == 0` —
  `scripts/core/GameState.cs:8-16`.
- `TestRoom.tscn` has no `PH_` outlet/panel/spawn markers yet — expected, noted so T-05/T-06 extend
  this room rather than creating another.
- Docs: `docs/TASKS.md:45` says T-02b closed "7 Should-fix" — the plan journal has S1–S6 (six).
  `docs/TASKS.md:55` says T-03 opened "—", but the T-03 round asked for a decision (N5: a KO'd hero
  can toggle the lamp once energy is restored) that has no `backlog` line. Plan text stale vs code:
  `docs/plans/t02b-basic-combat/t02b-basic-combat-plan.md:29-34` still describes `HitStop` as a
  self-installed root node (it is an autoload); `:58` lists `ComboWindowStart` 0.10 for L1/L2 while
  `Player.tscn:380,389` and `:59-60` of the same plan say 0.06; `docs/plans/t02-player-movement/
  t02-player-movement-plan.md:47-50` still lacks `PH_Face` in the node tree (T-02 nit, still open).

## Tests
- Smoke runner (`tools/smoke.ps1`) is correct as specified: name-tied `SMOKE <basename> PASS`
  regex (`:144`), per-script timeout with `taskkill /T` (`:110-115`), exit-code check, `ERROR:` /
  `SCRIPT ERROR:` / `Unhandled exception` / `CrashHandlerException` substring detection on stdout +
  stderr (`:90, :143-148`), exit 1 on no match. Timing headroom is fine (longest script 14.7 s of
  60 s). `--import` is deliberately not part of the runner (verify skill step 2) — correct, since
  nothing under `assets/` exists; revisit when S3 is fixed and art lands.
- Missing coverage (see S1): hero Hurt→Hurt restart — `tests/smoke/combat_dummy.gd`.
- Missing coverage (see S2): Idle entered while airborne must not re-launch — `tests/smoke/player_movement.gd`.
- Flakiness (see S4): wall-clock combo chaining — `tests/smoke/combat_dummy.gd:267`.
- Optional (carried from the T-03 round, still open): no drain during hit-stop; lamp dies one tick
  after a hit zeroes the energy — `tests/smoke/player_flashlight.gd`.
- All five scripts assert real behaviour (state order, HP arithmetic, time-scale start and bounded
  duration, inclusive depth boundary, signal counts, per-frame clamp), run their checks after
  autoloads exist, and end in `quit(1)` on failure or frame cap — no "tests that don't test".

## Readiness for T-04…T-09
**T-04 HUD.** `GameState.EnergyChanged(float)` fires only on an actual change through the `Energy`
setter / `AddEnergy` (`GameState.cs:52-65`); `_Ready` writes the backing field silently, so the HUD
must read `Energy`, `MinEnergy`, `MaxEnergy` on connect for the bar range and initial value.
`Flashlight.Toggled(bool)` exists, but the HUD is a separate scene: give `HUD` an `[Export]
Flashlight` (or `Player`) that the level assigns, per the "signals + Export" rule; do not reach for
`GameState` to carry lamp state (per-player, transient). Two initial-signal pitfalls: `Toggled(true)`
from `EnabledAtStart` fires in `Flashlight._Ready` before siblings connect (`Flashlight.cs:43-46`), and
`Player.StateChanged` never re-emits the initial `""→Idle` transition because `StateMachine._Ready`
runs before `Player._Ready` subscribes (`Player.cs:129`, `StateMachine.cs:67`) — read `IsOn` /
`CurrentStateName` on connect, as `TestRoom._Ready` already does.

**T-05 outlets / panels.** `interact` is in the InputMap (E / joypad 10); layer 6 `Interactable` is
named but nothing uses it; `GameState.AddEnergy(+amount)` clamps and signals. `Player` has no
interaction area: add an `Interactor` `Area2D` (mask 6) or let props detect the body on layer 2 —
decide once, in the plan. Interaction should be a state (`Interact`) on the machine, not a flag, so
attacks/jump are blocked during the panel sequence. Open decisions from earlier rounds: a KO'd hero
can toggle the lamp after a recharge (T-03 N5) → either `Player` calls `Flashlight.SetOn(false)` on
KO or the lamp ignores input while `IsKnockedOut`; `Flashlight.SetOn(true)` refuses at exactly
`MinEnergy`, so an outlet must add energy before the lamp can be relit (fine).

**T-06 enemies / waves / restart.** `Hitbox` is reusable as is: `Attacker` defaults to the scene
owner (`Hitbox.cs:41`), the depth rule is shared, and **(probe)** an enemy hitbox on layer 5 / mask 2
finds `Player/Hurtbox` (layer 2, `monitoring = false`, `monitorable = true`) — the hero took 5 energy
and entered `Hurt` both grounded and at `Height` 49.6. `Guard` needs: `IHittable` on its root, an
`Area2D` named exactly `Hurtbox` on layer 3, `TransitionToOrRestart` for reactions (the `DummyState`
base + Idle/Hurt/Down/KO are a good template; consider promoting `DummyState` to a shared
`EnemyState`), and hit-stop on its hits (S5). `Player.TakeHit` ignores `HitInfo.Knockdown` (the hero
has no `Down` state) and any hit at `Energy <= MinEnergy` — including a 0-damage one **(probe)** —
is a KO, so a lamp drained to 0 makes the next touch lethal: confirm that is intended (GAME_DESIGN
§4 says the lamp charge replaces HP potions, not HP). Fix S1 before enemies can chain hits and S2
before any state can end mid-air. Restart: on `Player.KnockedOut` the level should call
`HitStop.Cancel()`, `GameState.ResetRun()`, then `GetTree().ReloadCurrentScene()` — **(probe)**
reloading during a freeze is safe and the autoload statics survive, but energy is *not* reset by the
reload itself. In smoke tests `current_scene` must be set (`get_tree().current_scene = room`) before
`reload_current_scene()` works. Darkness: `Flashlight.IsOn`/`Toggled` are enough for "lamp off";
"hero outside any light" needs the reserved layer 7. T-B01 (do light hits stand a floored enemy up?)
must be decided first; `Dummy.TakeHit` currently does (`Dummy.cs:92`).

**T-09 save/load.** State to persist: `Energy` (write through the setter so the HUD updates),
`Route` (`RouteType` — pin the enum values, S/N above), `JournalsFound`, `DistrictReputation`, plus
the current scene path. `MaxEnergy`/`MinEnergy` are tunables, not state. `ResetRun` keeps journals
and reputation by design (`GameState.cs:91-99`) — `Load` should be the only other writer. There is
no scene-change API yet to hang the autosave on; T-07 introduces it.

**Question (not a finding).** `scenes/Main.tscn` is still an empty `Node2D`; `--quit` therefore
proves only the autoloads. Should `Main` instantiate `TestRoom` (or a `Boot` scene that picks the
first level) so the project's main scene exercises the real tree? Decide when T-07 defines the flow.

## What's done well
- The belt-scroll model is right and consistent: origin at the feet, Y = depth, fake-Z jump
  offsetting only `Visual` with the shadow at the origin, `motion_mode = Floating`, one shared depth
  check in `Hitbox`, and `y_sort_enabled` where it matters. Nothing to undo here.
- All behaviour lives in `State` children of the shared `StateMachine`; no boolean state flags
  anywhere. `TransitionToOrRestart` / `Restart` give reactions a clean re-entry path, and the machine's
  signal ordering (emit after `CurrentState` update, before `Enter`) is documented and smoke-tested.
- `HitStop` is the single owner of `Engine.TimeScale`, restores from the wall clock in an
  `Always`-processing autoload, has an `_ExitTree` backstop, and — verified by probe — survives a
  Dummy freed mid-freeze and a scene reload mid-freeze.
- `Hitbox` stays monitoring and is gated by `Activate`/`Deactivate` from animation method tracks:
  one hit per target per activation, targets already overlapping are hit, the hurtbox contract is
  documented in the class remarks with the layer plan for enemies.
- `Flashlight` owns its mechanic end to end (input, drain via `AddEnergy`, death, refusal, signal),
  drain is delta-scaled so hit-stop and pause are handled for free, and the light is a direct child
  of `Player` rotated by π instead of parented under the negatively scaled `Visual`.
- Every subscription is undone in `_ExitTree`; every exported node ref is assigned in the scene;
  the build has zero warnings under `nullable enable`.
- The smoke suite is genuinely load-bearing: hit-stop start and bounded duration, inclusive depth
  boundary, per-frame floor clamp and jump arc, signal counts, drain math from the tick rate, guard
  checks that fail loudly when the C# assembly is stale, and a name-tied runner with real timeout
  and error-line rules. The plan journals document each round with `file:line` and probes.

## Verdict
Ship: yes
Reasoning: no blockers — build, headless, scene load and all five smoke scripts are green, and the
architecture matches `CLAUDE.md` in coupling, input, tunables, state handling, depth rules and
lifecycle. The five Should-fix items are consistency gaps and hygiene that T-06 (S1, S2, S5) and
the first art drop (S3) would otherwise convert into real bugs, plus one test-robustness item (S4).
First three things to tackle: 1) S1 — restart the hero's `hurt` animation on re-entry and add the
hero half of the S3 regression; 2) S2 — `PlayerJump.Enter` must not re-launch when already airborne;
3) S3 — stop ignoring `*.import`, then S5 / S4 before the T-06 plan is written.
