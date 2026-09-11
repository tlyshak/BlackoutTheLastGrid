# Plan — t07s-e-dan-leads (T-07s-e · Дан веде, а не йде позаду — the guide companion)

Backlog: [`../../TASKS.md`](../../TASKS.md) → **T-07s-e**.
Design: [`../../GAME_DESIGN.md`](../../GAME_DESIGN.md) → §3, paragraph «Брат веде» — the one
principle that survives the story rewrite in progress: *Dan runs first and shows the way; Ray does
everything with his hands; Dan cannot be lost, hurt, stuck or waited for.*
Previous contract this plan edits: [`../t07s-a-escape-mechanics/t07s-a-escape-mechanics-plan.md`](../t07s-a-escape-mechanics/t07s-a-escape-mechanics-plan.md)
§9 (`Companion`) and its Design risk 4 («nothing ever waits for him»).

**Scope note (coordinator, 2026-09-11).** The prologue's story was rewritten again while this plan
was being made (no blast, no cave-ins; the threat is the guards; Dan is shot by a guard at the
end). Whether the circuit / gas / pump stay is undecided. This plan therefore covers **only what
survives any story**: the `Companion` in the guide role. Level wiring, the route through the
prologue, the cue table and **the final scene — a separate plan, after the author's decision.**

Branch: `task/t-07s-e-dan-leads` from `main` (`b59480d`).

---

## Goal

Give `Companion` a **`Lead`** state as a first-class alternative to `Follow`: the guide walks to
the next route point the level names, stops there, shows the way (facing, and a line the level
supplies), waits for the hero, calls out if he lags, does not come back for him, and stays
readable in the dark from a third of a screen ahead. All three anti-stuck safeguards are re-aimed
**forward** — to the route point, never behind the hero — and a room change or a respawn no
longer drags him behind. `Follow` stays untouched for `TestMine` and any future follower. The
level (any level) drives him with two calls, `LeadTo` / `RunTo`, from its own events; how a level
gates a route point on a hazard (lamp off, a guard gone, a gate opened) is the level's decision,
and the guide gives it the signals to do so.

## Scope

### In
- `scripts/actors/CompanionLead.cs` (new state) + `Companion.tscn` `Lead` node.
- `Companion` API: `LeadTo`, `RunTo`, `SetWarning`, `OnHeroRelocated`, `Vanish`; signals
  `HeroReached`, `HeroLagging`; exports below; forward failsafes; a hold is world-anchored.
- `LevelBase`: room change / respawn call a state-aware hook instead of `WarpBehind()`.
- Readability in the dark: `PH_DanLight` on the companion (light only for him and his bubble).
- `TestMine.tscn`: an opt-in `DanLeads` toggle with a three-marker route so the guide can be
  played by hand (F6) and driven by the smoke script.
- `tests/smoke/actors_companion.gd` extended (Follow sections kept; Lead sections added; the
  relocation sections rewritten).
- `docs/TASKS.md` status/done-note; one backlog line.

### Out
- Everything about the prologue: `Level00_Prologue.*`, its route, coordinates, cue table, the
  ending, `level_prologue*.gd`, `level_seals.gd`. **The final scene — separately, after the
  author's decision.**
- Any line of text (the script owns it); a crouch/duck pose; a lamp prop for Dan; painted art.
- `Follow` behaviour changes (none).
- Save/load of route progress (T-09; see *GameState & save impact*).

### Out of scope → `docs/TASKS.md` backlog (exact line for `/coder` to add)

```
### T-B22 · Дан: власне підсвічування vs. мальований арт · `backlog`
- `PH_DanLight` (T-07s-e) робить провідника і його бульбашку читабельними в темряві через `range_item_cull_mask`. Коли з'явиться мальований арт (`Visual/Sprite`), перевірити, чи бульбашку не варто винести в `CanvasLayer`, а світло замінити unshaded-матеріалом.
```

---

## Design-doc conformance

§3 «Брат веде [ПІДТВЕРДЖЕНО 2026-09-11]»: «біжить першим… каже, куди йти і що робити… руками все
робить Рей… біжить до наступної точки маршруту, там зупиняється і чекає, показує напрямок… якщо
Рей відстав — гукає, але не вертається… Він не помирає від геймплею: його не можна втратити,
недоглянути чи "зіграти краще"».

| Task requirement (T-07s-e, the `Companion` part) | Design | Verdict |
|---|---|---|
| `Lead` as the main state: run to the next point, stop, show direction, wait | «біжить до наступної точки… зупиняється і чекає, показує напрямок» | agree; «показує напрямок» = facing + the level's line (no art) |
| Calls if the hero lags, does not return | «гукає, але не вертається» | agree; `HeroLagging` is a signal, the level says the line; `Lead` never moves toward the hero |
| Anti-stuck re-done for «ahead»: warp forward, not behind | design silent on mechanics | plan decides: all three safeguards aim at the route point |
| Dan never uses his hands | «руками все робить Рей» | agree by construction — `collision_layer = 0`, no interaction, unchanged |
| He does not trigger zones, does not block gates | «(`layer 0`)» | unchanged |
| Cannot be lost / waited for | «не помирає від геймплею… нічого не чекає» | kept: every level-side wait on him is forbidden; `Arrived`/`HeroReached` are *informational* |
| Signals danger before the hero enters a hazard | «Дан окрикує» (gas paragraph) | plan gives the level a *stance* (`SetWarning`) and the gating signals; the text and the rule are the level's |
| Segment 1 / the ending | being rewritten | **out of this plan** |

Task and design agree on every row in scope. Nothing to ask; the story questions are the
author's and are explicitly parked.

---

## Options considered

### 1. Where do route points come from?

| Option | Trade-off |
|---|---|
| A. `[Export] Vector2[]` on the level | Cheapest; but anonymous numbers, invisible in the editor, and the level still needs a *name* per point to bind its events to. The two such numbers that exist today (`DanFallenAt`, `DanLastStandAt`) each needed a `PH_` decal to be findable. |
| B. Reuse `Checkpoint`s + an offset | Zero new nodes; but the guide's stops are not the hero's respawns (a stop sits *before* a hazard, a respawn *behind* it), and it couples the respawn prop to one NPC. |
| **C (chosen). A per-level `Node2D` container of `Marker2D` children (`WP_<key>`), read once into a dictionary; the level calls `LeadTo(point)` by key** | Editable in the editor, no numbers in code, and the **child order is the route order**, which gives any level a free «never behind the hero's progress» rule (`LeadAtLeast(key)`). The companion itself only ever receives a `Vector2` — it knows nothing about keys, so the container is a level-side convention, demonstrated in `TestMine`. |

### 2. What happens when the hero overtakes the guide?

| Option | Trade-off |
|---|---|
| A. Re-target to «hero + offset» and sprint past him | A race; in the dark a moving target nobody sees; drags him through gates the level has not opened for him. |
| B. Warp ahead whenever the hero passes him | Pops on screen — the hero passing him *is* on screen. |
| **C (chosen). He keeps his route point; being passed is allowed; the level's next event re-leads him, with a warp only when the hero is more than `WarpDistance` (off-screen) ahead** | Honest and cheap: the guide falls behind only when the player chooses to outrun him. `LeadSpeed` 240 vs the hero's 220 makes it rare on a straight. |

### 3. Keep `Follow`?

| Option | Trade-off |
|---|---|
| A. Replace `Follow` with `Lead`; move `TestMine` to `Lead` | One state fewer; but `TestMine`'s companion sections prove *companion* invariants (walk-through, no triggers, failsafes) that do not care who leads, and a future level may want a follower. |
| **B (chosen). `Follow` stays; `Lead` is added; `Companion.tscn` keeps `InitialState = Follow`; a level opts into `Lead` by calling `LeadTo` in `_Ready`** | Zero churn in `level_mine.gd`; `actors_companion.gd` keeps its Follow sections as the characterization test. |

### 4. How is the guide readable 300–640 px ahead in a dark level?

Real problem hidden by the current build: Dan trails **56 px behind**, inside the head-lamp
cone, so he and his bubble (a world-space `Label` under the level's `CanvasModulate`) are lit by
Ray's lamp. Ahead of the cone both go black — suit `#c9752a` × mine dark `#0a0d14` ≈ (0.008,
0.004, 0.002). A guide the player cannot see is not a guide.

| Option | Trade-off |
|---|---|
| A. Bubble in a `CanvasLayer`, projected from his world position each frame | Crisp, immune to darkness; per-frame `GetGlobalTransformWithCanvas`; the *body* stays invisible — the player follows floating text. |
| B. Keep him inside the lamp cone (`LeadMaxGap` ≈ 200) | «Ahead» becomes «beside»; defeats the task. |
| **C (chosen). `PH_DanLight`: a `PointLight2D` child whose `range_item_cull_mask` is a render bit only his `Visual` and `Bubble` carry** | No code, no per-frame work, lights nothing else (not the floor, not the hero). He reads as a faint warm silhouette with a readable line. Cost: a visual convention the author must accept (*Open questions* 1) and +1 light without shadows. |

### 5. How does he signal danger before the hero enters?

| Option | Trade-off |
|---|---|
| A. The companion knows hazards (reads `GasZone`, `WatchZone`, guards) | Couples the actor to props; every new hazard edits `Companion`. |
| **B (chosen). The level decides when a point may be advanced (it already owns every hazard signal — `Flashlight.Toggled`, `GasZone.*`, `WatchZone.*`, `WaveSpawner.WaveCleared`); the guide provides the *stance* and the *timing signals*: `SetWarning(true)` = stand at the point facing the danger, never look back, never call; `HeroReached` = the moment the level may check its condition; `HeroLagging` = the moment to say a call** | The companion stays generic; a level expresses «he won't go into the gas while your lamp is on» as three lines in its own handlers. The stronger tell («he refuses to move») costs nothing. |

---

## Recommended approach

1. **`Lead` state** (`CompanionLead`). `LeadTo(Vector2)`: walk at `LeadSpeed`; keep at most
   `LeadMaxGap` ahead of the hero (the *leash*: farther → stop, turn to him; closer than
   `LeadResumeGap` → go on); arrive within `ArriveDistance`; face the direction of travel; after
   `LookBackSeconds` turn to the hero; emit `HeroReached` once when the hero comes within
   `HeroCloseDistance`; emit `HeroLagging` (after `CallAfterSeconds`, every `CallRepeatSeconds`,
   at most `MaxCallsPerStop`) while he does not. `RunTo(Vector2)`: the same without the leash, at
   `RunSpeed`. `SetWarning(true)`: at the point, face `TravelSign`, no look-back, no calls.
2. **Forward failsafes.** (1) farther than `WarpDistance` from the point, or the hero farther than
   `WarpDistance` *ahead* of him → warp to the point. (2) stuck `StuckSeconds` → warp to the point.
   (3) `OnHeroRelocated()` from the level: `Follow` → `WarpBehind()` as today; `Wait`/`Lead` →
   nothing unless the hero is more than `WarpDistance` away, then warp to the held/route point.
   A hold or a route point is a world position; the level re-issues what it wants after a respawn.
3. **The level drives.** A `Node2D` of `Marker2D`s in route order (Options 1C) and two level
   helpers — `LeadTo(key)` from explicit events (a gate cleared, a machine powered, a guard gone)
   and `LeadAtLeast(key)` from the hero's checkpoints (never behind his progress). `TestMine`
   shows the pattern; the prologue applies it in its own plan.
4. **Readability**: `PH_DanLight` (Options 4C).
5. **`Vanish()`**: the one irreversible call a level uses when the guide leaves the story (how and
   when — the level's plan).

### Priorities

| # | Item | Must / nice |
|---|---|---|
| M1 | `CompanionLead` + `Lead` node; `LeadTo`/`RunTo`; `HeroReached`/`HeroLagging`; exports | must |
| M2 | Forward failsafes; world-anchored holds; `LevelBase.OnHeroRelocated` hook | must |
| M3 | `SetWarning` stance; `Vanish` | must |
| M4 | `PH_DanLight` | must |
| M5 | `TestMine` `DanLeads` toggle + 3 markers (the only place a human can play the guide until the prologue plan lands) | must |
| M6 | `actors_companion.gd` Lead sections + rewritten relocation sections | must |
| N1 | `LookBackSeconds` turn at a stop | nice |
| N2 | `LeadAtLeast` helper in `TestMine` (documented pattern for the prologue) | nice |

---

## GameState & save impact

**No `GameState` change.** No field or signal of the autoload is read or written. The guide's
state (current route point, state name, `IsGone`) is per-level scene state; T-09 autosaves on
scene change only, so nothing here needs persisting. **T-09 note:** if mid-level saves are ever
added, the level must save its own route key and the companion's state name — not `GameState`.

---

## Scene & signal contract

### A. `scenes/actors/Companion.tscn` ↔ `scripts/actors/Companion.cs` (root: `CharacterBody2D`) — edited

```
Companion (CharacterBody2D)  layer 0 / mask 1, motion_mode Floating   → scripts/actors/Companion.cs
├── PH_Shadow (Polygon2D)              unchanged, light_mask 1
├── Visual (Node2D, (0,−36))           light_mask = 3  (bit 1 = the hero's lamp, bit 2 = own light)   ← changed
│   ├── Rig (CharacterRig)             unchanged
│   └── Sprite (AnimatedSprite2D)      unchanged (empty slot)
├── Bubble (Label)                     light_mask = 3                                                  ← changed
├── PH_DanLight (PointLight2D)         NEW: position (0,−60), energy 0.75, shadow_enabled false,
│                                      range_item_cull_mask = 2, texture = inline GradientTexture2D
│                                      (radial 256², white→transparent), texture_scale 1.6 (≈205 px:
│                                      the bubble's far corner (±110, −116) is ≈124 px from the light)
├── AnimationPlayer                    unchanged (RESET / idle / walk)
├── CollisionShape2D (Capsule r7 h28)  unchanged
└── StateMachine (StateMachine.cs)     InitialState = Follow (unchanged)
    ├── Follow (CompanionFollow.cs)    unchanged
    ├── Wait   (CompanionWait.cs)      edited: a hold is world-anchored
    └── Lead   (CompanionLead.cs)      NEW
```

New `[Export]`s (every T-07s-a export keeps its default):

| Name | Type | Default | Unit | Why |
|---|---|---|---|---|
| `LeadSpeed` | float | 240 | px/s | walking while leading — just over the hero's 220 so he reads as leading and is rarely overtaken on a straight |
| `RunSpeed` | float | 300 | px/s | `RunTo`; equals `CatchUpSpeed`, so nothing new ever moves faster than the hero has already seen |
| `LeadMaxGap` | float | 640 | px | the leash: farther ahead of the hero than this he stops and turns; keeps his bubble (±110) inside a 1920 px view with the hero centred and 90 px lookahead (640 + 110 + 90 < 960) |
| `LeadResumeGap` | float | 380 | px | leash hysteresis: he resumes once the hero is closer than this |
| `HeroCloseDistance` | float | 160 | px | at the point, the hero within this fires `HeroReached` (once per point) |
| `LookBackSeconds` | float | 1.5 | s | at a stop, seconds facing the way before he turns to look for the hero (N1); ignored while warning |
| `CallAfterSeconds` | float | 5 | s | at a stop or leashed, seconds with the hero farther than `LeadResumeGap` before `HeroLagging` |
| `CallRepeatSeconds` | float | 10 | s | interval between repeated `HeroLagging` at the same stop |
| `MaxCallsPerStop` | int | 2 | calls | after this he is quiet until the next point — the anti-nag cap |
| `OvertakeDistance` | float | 120 | px | the hero counts as «ahead of him» past this (tests, docs) |

Reused unchanged by `Lead`: `WarpDistance` 900, `StuckSeconds` 2.5, `StuckSpeed`, `StuckProgress`,
`ArriveDistance` 12, `DepthSpeedFactor` 0.75, `BubbleSeconds`, `WalkAnimationMinSpeed`.
`MoveSpeed` 205 stays the `Follow`/`Wait` speed.

Public API added / changed:

| Member | Meaning |
|---|---|
| `void LeadTo(Vector2 target)` | set `LeadTarget`, `TravelSign = sign(target.X − X)` (0 keeps facing), leash on, speed `LeadSpeed`, enter `Lead`. **No-op if already leading to the same point** (re-issuing never re-fires `Arrived`). |
| `void RunTo(Vector2 target)` | as `LeadTo` with the leash off and `RunSpeed`. |
| `void SetWarning(bool on)` | warning stance at the point: face `TravelSign`, no look-back, no `HeroLagging`. Cleared automatically by the next `LeadTo`/`RunTo`. |
| `void OnHeroRelocated()` | the level's hook after a hero teleport (room bounds, respawn): `Follow` → `WarpBehind()`; `Wait`/`Lead` → warp to the held/route point only if the hero is farther than `WarpDistance`, else nothing. |
| `void Vanish()` | `Visible = false`, `ProcessMode = Disabled`, `Stop()`, `Say("")`, `IsGone = true`. Irreversible for the level instance. |
| `void WarpBehind()` | unchanged behaviour for `Follow`; **no longer moves `HoldPosition`** when waiting. |
| `Vector2 LeadTarget`, `int TravelSign`, `bool IsLeading`, `bool IsAtLeadTarget`, `bool IsLeashed`, `bool IsWarning`, `bool IsGone` | read-only state for levels and tests. |

Signals (existing `LineShown`, `Arrived`, `Warped` unchanged; `Arrived` now also fires once per
`LeadTo`/`RunTo` on reaching the point):

| Signal | Params | Emitted when | Who listens |
|---|---|---|---|
| `HeroReached` | () | in `Lead`, at the point, the first time the hero is within `HeroCloseDistance` of it | the level (gate a point on a condition, say a line); `TestMine` (event label); tests |
| `HeroLagging` | () | in `Lead`, at the point or leashed, the hero farther than `LeadResumeGap` for `CallAfterSeconds`, then every `CallRepeatSeconds`, ≤ `MaxCallsPerStop` per point; never while warning | the level (a call line); `TestMine`; tests |

Connections: the owning level connects in `_Ready` and disconnects in `_ExitTree` (the existing
pattern for `LineShown`).

**`Lead` state — `PhysicsUpdate`** (all of it in the physics tick; animation stays in
`Companion._Process`):
1. `offset = LeadTarget − GlobalPosition`.
2. Failsafe 1: `|offset| > WarpDistance` → `WarpTo(LeadTarget)`, return. Hero ahead of him by more
   than `WarpDistance` along `TravelSign` → `WarpTo(LeadTarget)`, return (the route point is the
   ceiling; being there is always right).
3. `|offset| ≤ ArriveDistance` → **at the point**: `Stop()`; first time: `FaceTowards(TravelSign)`,
   `NotifyArrived()`, reset the call counter and timers. Then: warning → keep facing `TravelSign`;
   else after `LookBackSeconds` face the hero. `HeroReached` once when the hero is within
   `HeroCloseDistance`. Lag timer → `HeroLagging` (rate-limited, capped, off while warning or
   without a hero). Return.
4. **Walking**: leash (if on and a hero exists): `behind = (X − hero.X) × TravelSign`;
   `behind > LeadMaxGap` → leashed; leashed and `behind < LeadResumeGap` → released. Leashed →
   `Stop()`, face the hero, run the lag timer, return. Else
   `Move(VelocityTowards(LeadTarget, delta, speed))`, `FaceTowards(velocity.X)`; failsafe 2:
   `IsStuck` → `WarpTo(LeadTarget)`.
   Without a hero (`ActiveTarget` null) he still walks to the point and holds it — a guide with
   nobody to guide stands where the script put him.
   `Enter` clears stuck/arrived/leash/call state; `Exit` clears the warning.

**`Wait` — one change:** `WarpBehind()` no longer rewrites `HoldPosition`. A hold is a world
position; the level re-issues holds on respawn where it wants them (the prologue already does).

**`Follow` — unchanged.**

### B. `scripts/levels/LevelBase.cs` — edited (no scene)

`ApplyRoomBounds` and `RespawnAtCheckpoint` call `Companion?.OnHeroRelocated()` instead of
`Companion?.WarpBehind()`. Doc of the `Companion` export updated («the level tells him the hero
was teleported; what he does about it depends on his state»). Nothing else.

### C. `scenes/levels/TestMine.tscn` ↔ `scripts/levels/TestMine.cs` — edited (fixture)

```
TestMine (Node2D, y_sort)
├── DanRoute (Node2D)                  NEW; children in route order:
│   ├── WP_A (Marker2D)  (800, 460)    on the free stretch (760…1470: no blocker, no trigger)
│   ├── WP_B (Marker2D)  (1300, 460)
│   └── WP_C (Marker2D)  (1460, 460)   short of the DebrisPile_Back blocker (1472…1528)
├── Companion                          unchanged position (90, 460); Target = Player
└── (everything else unchanged)
```

| `[Export]` (TestMine) | Type | Default | Why |
|---|---|---|---|
| `DanLeads` | bool | **false** | opt-in: `_Ready` → `Companion.LeadTo(WP_A)`; `Checkpoint_Start` reached → `WP_B`; `Checkpoint_Gas` reached → `WP_C`. Off by default so `level_mine.gd` and the Follow sections of `actors_companion.gd` see the fixture exactly as today. |
| `DanRoute` | `Node2D` | `DanRoute` | the marker container |
| `LeadLine` / `CallLine` | string | «This way.» / «Come on!» | fixture-only English strings shown on `Arrived` / `HeroLagging` so a human sees the events; not shipping text |

`TestMine` connects `Companion.Arrived`, `HeroReached`, `HeroLagging` (event label + the two
lines) in `_Ready`, disconnects in `_ExitTree`. The smoke script drives `Lead` with direct calls
and does not depend on `DanLeads`.

Collision: nothing changes anywhere — `Companion` layer 0 / mask 1; markers have no physics.

Owner scenes:

| Scene | Instantiates | Wires |
|---|---|---|
| `TestMine.tscn` | `Companion`, `DanRoute` markers | `Companion → Player`, `DanRoute`, `DanLeads`, the two fixture lines |
| `Level00_Prologue.tscn` | `Dan` | **untouched in this task**; keeps working because `Follow` and `HoldAt` are unchanged and `OnHeroRelocated` in `Follow` is `WarpBehind` |

Belt-scroll: origin at the feet, `Visual` at (0, −36), depth = Y; route points are authored on
the walk band by the level (he inherits no floor band in `Lead`; `Follow` still clamps to the
hero's). No `_z`, no `Hitbox`/`Hurtbox` — he never fights, never gets hit.

State machine: `Follow ⇄ Wait ⇄ Lead`; `HoldAt` → `Wait`, `LeadTo`/`RunTo` → `Lead`, `Resume` →
`Follow`. No transition originates inside a state — every one is a level call.

Needs `/project-settings`: **none.** `light_mask` / `range_item_cull_mask` bits are render layers,
not physics layers; no InputMap, autoload or `.csproj` change. `/coder` greps the project for any
existing use of render bit 2 (`light_mask`, `range_item_cull_mask`) and reports it — none expected.

Open questions: see the section at the end.

---

## File-level change list

### `scenes/`
| File | Intent |
|---|---|
| `scenes/actors/Companion.tscn` | add `StateMachine/Lead` (script `CompanionLead.cs`); add `PH_DanLight` with an inline `GradientTexture2D`; `light_mask = 3` on `Visual` and `Bubble`; `InitialState` stays `Follow`; `load_steps`/ids updated |
| `scenes/levels/TestMine.tscn` | add `DanRoute` + `WP_A/B/C`; wire `DanRoute`, `DanLeads = false`, `LeadLine`, `CallLine` |

### `scripts/`
| File | Intent |
|---|---|
| `scripts/actors/CompanionLead.cs` | **new** — the `Lead` state |
| `scripts/actors/CompanionState.cs` | `StateLead = "Lead"` |
| `scripts/actors/Companion.cs` | new exports, signals, `LeadTo`/`RunTo`/`SetWarning`/`OnHeroRelocated`/`Vanish`, read-only state; `WarpBehind` no longer moves a hold; class doc rewritten for the guide role |
| `scripts/actors/CompanionWait.cs` | doc only (a hold is world-anchored) |
| `scripts/levels/LevelBase.cs` | `OnHeroRelocated()` in `ApplyRoomBounds` / `RespawnAtCheckpoint`; doc |
| `scripts/levels/TestMine.cs` | `DanLeads`, `DanRoute`, the route dictionary + `LeadTo(key)` helper (and `LeadAtLeast`, N2), checkpoint → next point, `Arrived`/`HeroReached`/`HeroLagging` → event label + lines |

### `tests/smoke/`
| File | Intent |
|---|---|
| `tests/smoke/actors_companion.gd` | keep §1–9 (the Follow characterization) with `EXPECTED_STATES += "Lead"` and the new export defaults; **rewrite §10–11** (relocation is state-aware; a hold no longer moves); **add** the Lead sections listed in *Test strategy*; add the `PH_DanLight` contract. If the script no longer fits the 60 s runner budget, split the Lead sections into `tests/smoke/actors_guide.gd` — same helpers, same fixture. |

### `docs/`
| File | Intent |
|---|---|
| `docs/TASKS.md` | T-07s-e `in_progress` → `done` with the done-note («що зроблено: провідник; що не зроблено: маршрут прологу і фінал — окремий план») and the playtest checklist; add T-B22 |
| `docs/plans/t07s-e-dan-leads/t07s-e-dan-leads-plan.md` | this file; `## Review findings` by `/reviewer` |

### `project.godot` / `.csproj` / `.sln`
**None.**

Order for `/coder`: (1) the `Lead` state and exports with the fixture route (`TestMine`) — new
behaviour, tests land with it; (2) **before** M2 changes `WarpBehind`/`LevelBase`, rewrite
`actors_companion.gd` §10–11 to the new relocation semantics in the same commit-step, since they
are the characterization of the behaviour being changed; (3) `PH_DanLight`; (4) headless check
that `Level00_Prologue.tscn` still loads and `level_prologue*.gd` / `level_seals.gd` stay green
(the prologue is untouched and relies only on `Follow`, `HoldAt`, `WarpTo`).

---

## Acceptance criteria

All on `scenes/levels/TestMine.tscn` unless stated; «Dan» = the fixture's `Companion`.

1. Given `Companion.tscn` instantiated → `StateMachine` has `Follow`, `Wait`, `Lead`; `InitialState` is `Follow`; `PH_DanLight` exists with `range_item_cull_mask == 2` and `shadow_enabled == false`; `Visual.light_mask & 2 != 0`, `Bubble.light_mask & 2 != 0`, `PH_Shadow.light_mask == 1`.
2. Given the defaults → `LeadSpeed 240`, `RunSpeed 300`, `LeadMaxGap 640`, `LeadResumeGap 380`, `HeroCloseDistance 160`, `LookBackSeconds 1.5`, `CallAfterSeconds 5`, `CallRepeatSeconds 10`, `MaxCallsPerStop 2`, `OvertakeDistance 120`; every T-07s-a default unchanged (`MoveSpeed 205`, `WarpDistance 900`, `StuckSeconds 2.5`, `SideOffset −56`, …).
3. Given `TestMine` loaded with `DanLeads = false` → Dan is in `Follow` (today's assertion); given `DanLeads = true` → after settle Dan is in `Lead` with `LeadTarget == WP_A`.
4. Given the hero at (800, 450) and Dan at (760, 460), `LeadTo((1300, 460))` → within 160 physics frames `Arrived` fired exactly once, Dan within `ArriveDistance` of the point, `velocity == 0`, animation `idle`, `Facing == +1`, `IsAtLeadTarget == true`; a second `LeadTo` with the same point fires no second `Arrived` and does not move him.
5. Given Dan at the point and the hero placed at (1250, 450) → `HeroReached` fires exactly once; the hero moving away and back does not fire it again for the same point; a new `LeadTo` to another point re-arms it.
6. Given `LeadMaxGap = 300`, `LeadResumeGap = 180` (set by the test), the hero at (800, 450) and Dan at (820, 460), `LeadTo((1460, 460))` → Dan stops with `IsLeashed == true` at x ≤ 800 + 300 + 8 and faces the hero (`Facing == −1`); given the hero then placed at (1300, 450) → `IsLeashed == false` within 3 frames and he reaches the point.
7. Given `CallAfterSeconds = 0.3`, `CallRepeatSeconds = 0.3`, Dan at his point and the hero 700 px behind → `HeroLagging` fires exactly `MaxCallsPerStop` (2) times within 1.2 s and never again while the hero stays; given the hero comes within `HeroCloseDistance` → no `HeroLagging` afterwards at that point.
8. Given `SetWarning(true)` at the point and the same lag setup → zero `HeroLagging` after 1.2 s, and `Facing == TravelSign` after `LookBackSeconds` (he does not look back); given the next `LeadTo` → `IsWarning == false`.
9. Given Dan wedged at (380, 460) with `DebrisPile_Hand`'s blocker at 412…468 and `LeadTo((520, 460))` → `Warped` fires after `StuckSeconds` (same slack as the Follow stuck test) and Dan is within `ArriveDistance` of **(520, 460)** — on the far side of the blocker, never behind the hero.
10. Given `LeadTo` to a point farther than `WarpDistance` → `Warped` within 3 frames and Dan at the point; given the hero placed more than `WarpDistance` **ahead** of Dan along `TravelSign` → `Warped` and Dan at the point within 3 frames.
11. Given Dan in `Lead` at his point and `ApplyRoomBounds(StartRoom)` with the hero 300 px away → no `Warped`, position unchanged; with the hero 1000 px away → `Warped`, Dan at his point (not behind the hero). Given Dan in `Follow` → `ApplyRoomBounds` still warps him behind (today's §10). Given Dan in `Wait` at a hold and the hero 1000 px away → he stays on the hold; `HoldPosition` unchanged.
12. Given `RunTo((1460, 460))` from (800, 460) with the hero at (760, 450) and `LeadMaxGap = 300` → `IsLeashed` never becomes true and his x advances by `RunSpeed × dt` ± 5 % over 30 frames.
13. Given `Vanish()` → `Visible == false`, `ProcessMode == Disabled`, `IsGone == true`, `velocity == 0`, `IsSpeaking == false`, and 60 frames later `GlobalPosition` unchanged; a subsequent `LeadTo` does not move him.
14. Given the hero standing on Dan's point for 10 frames → the hero does not move (no push); given the hero walking through a leading Dan → the same distance as with the way clear (today's walk-through assertion, kept); given Dan led onto `Checkpoint_Start`, `CaveIn_Mid`, `GasZone_Rehearsal` → none of them sees him (today's §4, kept).
15. Given `DanLeads = true` and the hero walked across `Checkpoint_Start` then placed on `Checkpoint_Gas` → `LeadTarget` is `WP_B` then `WP_C`; each `Arrived` puts `LeadLine` in the bubble once; `HeroLagging` puts `CallLine`.
16. Given the full suite → `level_mine.gd`, `level_prologue.gd`, `level_prologue_escape.gd`, `level_seals.gd`, `props_*.gd` unchanged and green; `godot --headless --path . --quit` prints no `ERROR:`/`WARNING:` from these scenes; `dotnet build` 0 warnings.

---

## Test strategy

Kind of change: **new feature (`Lead`) + behaviour change (relocation / hold semantics)** on a
scene with an existing smoke script. Only smoke tests exist (GdUnit4 not approved).

| Script | Proves |
|---|---|
| `tests/smoke/actors_companion.gd` — existing §1–9 | AC 1–2 (extended defaults and the light contract), 3 (`Follow` default), 14 — kept verbatim as the characterization that `Follow` did not change |
| — rewritten §10–11 | AC 11: relocation per state; a hold is world-anchored (today's §11 asserts the opposite and is replaced, not deleted silently — the comment says why) |
| — new Lead sections (direct `LeadTo`/`RunTo`/`SetWarning`/`Vanish` calls on the free stretch 760…1470; exports shortened where a wait is real-time) | AC 4–10, 12, 13 |
| — new fixture section (`DanLeads = true` set on the instance before `add_child`) | AC 15 |
| `tests/smoke/level_mine.gd` and the prologue scripts | AC 16 — untouched, must stay green |

Budget: the Follow sections already take ~2 real seconds of bubble/pause waits; the Lead sections
are frame-counted except the lag timers (shortened to 0.3 s). If the runner's 60 s is threatened,
split into `actors_guide.gd` (same style) — the plan pre-authorises the split.

Only verifiable by hand → Playtest: whether 640 px «ahead» feels like a guide or a runaway;
whether two calls per stop nag; whether the self-lit figure reads as «the brother» or as a bug;
whether the warning stance (facing the danger, not you) is understood without a line.

---

## Playtest (manual QA)

1. Open `scenes/levels/TestMine.tscn`, select the root node, tick **DanLeads** in the inspector,
   run the scene (F6). Expected: Dan walks from the start to the first marker (past the outlet),
   stops, faces right, and shows «This way.» in his bubble; the top-left label reads `Lead`.
2. Stand still 6–10 s. Expected: he turns to look at you after ~1.5 s, then says «Come on!» once,
   again ~10 s later, and then nothing more.
3. Walk to him. Expected: the event label reports the hero reached him; he does not move (the
   fixture advances him on checkpoints, not on your arrival).
4. Walk on across the first checkpoint. Expected: he sets off ahead of you toward the second
   marker; while you walk he stays ahead, no more than about a third of a screen; stop and he stops
   and turns to you; walk and he goes on.
5. Sprint past him (hold D). Expected: you can pass him — he does not race you; he still stops at
   his marker behind you and waits there.
6. Cross the second checkpoint. Expected: he walks to the third marker and stops short of the
   rubble; he never presses against it.
7. Switch the lamp off in the dark stretch and look at him from a distance. Expected: he and his
   bubble stay faintly visible; the floor around him does not light up.
8. Untick **DanLeads**, run again. Expected: Dan trails you as before (Follow); nothing else changed.
9. Open `scenes/levels/Level00_Prologue.tscn` via `scenes/Main.tscn` (F5) and play to the pump.
   Expected: identical to before this task — Dan follows, is found after the blast, holds at the
   scripted beats (the prologue is untouched by this plan).
10. Question for the author: is the faintly lit guide (step 7) an acceptable visual convention?

---

## Review focus

`state machine` (three states, every transition a level call; no boolean chains — leash /
arrived / warning are state-local fields, not level flags) · `signals/decoupling` (`Companion`
knows nothing about hazards, keys or levels; new signals connected in `_Ready`, dropped in
`_ExitTree`) · `scene/tscn integrity` (`Lead` node, `PH_DanLight`, `light_mask` bits, `TestMine`
markers, `load_steps`) · `physics timing` (leash / arrive / hero-close in `_PhysicsProcess`;
look-back and the light are cosmetic).

---

## Performance & frame budget

- `CompanionLead.PhysicsUpdate`: one `LengthSquared`, one signed X difference, one
  `VelocityTowards`, one `MoveAndSlide` — the `Follow` cost plus one subtraction. Timers are
  float accumulators. No allocation, no LINQ, no `GetNode`.
- `Companion._Process`: unchanged (bubble countdown, gait).
- Level side: nothing per frame; route lookup is a dictionary hit at event time.
- Lights: +1 `PointLight2D`, no shadows, cull mask limited to two items — the cheapest light in
  any level; counts stay bounded.
- y-sort: a `Node2D` of `Marker2D`s under the y-sorted root draws nothing; acceptable.
- Physics: no new shapes anywhere.

---

## Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | A level authors a route point *past* a closed gate; the stuck watchdog then warps him through it | the contract says points sit ≥ 50 px short of a blocker; the stuck warp goes **to the point**; AC 9 shows the mechanism; the level's own tests must assert the side (the prologue plan will) |
| R2 | `WarpBehind` no longer moving a hold breaks a caller | callers today: `Follow`'s failsafes and `LevelBase` (replaced by the hook); the prologue re-issues its holds in `OnRespawned` already; `actors_companion.gd` §11 rewritten |
| R3 | Render bit 2 already used by a level light with a custom `range_item_cull_mask` | `/coder` greps `light_mask` / `range_item_cull_mask`; none expected |
| R4 | The 60 s runner wall for `actors_companion.gd` | lag timers shortened to 0.3 s; split pre-authorised |
| R5 | `Lead` with no hero (`Target` null) misbehaves in a fixture | he walks to the point and holds it; leash/calls are skipped without a hero (AC-implied; add a one-liner assertion if cheap) |
| R6 | `TestMine`'s `DanLeads` default drifts to `true` in the scene | AC 3 asserts the default; `level_mine.gd` keeps its Follow assertion |

---

## Design risks

Direct assessment, guide only.

**1. He runs too far ahead.** One number: `LeadMaxGap = 640`. A third of a screen is the limit at
which his self-light is still a landmark and his bubble still readable; at a screen-half (900) he
is a rumour. The leash also has a feel cost — every stop is a micro-nag («he keeps looking at
me»). It engages only when the player *stops* (240 vs 220 px/s gains 20 px/s; opening 640 px on a
straight takes 32 s), so in practice it triggers at puzzle loops, where he is usually *at a point*
anyway and not on the leash. **Low; tunable by one export; playtest step 4.**

**2. He waits too close / stands in the way.** He cannot block (layer 0); the contract puts points
50–60 px short of a gate and 30 px off the hero's usual line, so y-sort never flickers. The
bubble-over-prompt rule (a HUD prompt hides his bubble) prevents text collision at panels. If a
point crowds a panel, the level moves the marker — no code. **Low.**

**3. He repeats himself.** Three sources, each capped in the companion: `HeroReached` once per
point; `HeroLagging` ≤ 2 per point, only after 5 s with the hero > 380 px away (a player working a
panel 100 px away is never called); `Arrived` once per point (and `LeadTo` to the same point is a
no-op, so a respawn re-issue never re-fires it). Direction lines are the level's; the pattern the
prologue plan should copy is «once per route key, survives respawn». **Low if the script respects
its own ≥ 3 s rule.**

**4. Does he give the answer away?** Honest answer: **only if the level makes him.** Nothing in
`Lead` walks to a *solution*; he walks to the point the level names, and the contract's guidance
is: stops sit at the *obstacle*, never at the switch that opens it; direction lines say *where the
next thing is*, not *what to switch*; a line that names the fix (today's «Kill the lights») fires
only *after* the game has already named the culprit in the HUD. The `SetWarning` stance is the
strongest tell this plan adds — «he won't go in» — and it states the rule, not the solution: the
decision (go dark, or power the fan) stays the player's, and the guide follows it. **Acceptable;
the real test is the prologue plan's cue table, which must be reviewed against exactly this rule.**

**5. The guide is invisible in the dark.** Found while planning: 300–640 px ahead in a dark
level both he and his bubble are black today (they were only ever lit by the hero's lamp because
he trailed inside its cone). Without `PH_DanLight` the whole feature ships as text nobody can
read over a man nobody can see. The fix costs a convention — a faintly lit figure the world's
light does not explain. I think it is the right convention for a companion in a dark game (he is
the one thing you can see), but it is a visual decision the author owns — *Open questions* 1. If
the level ever has a stealth stretch, a lit guide inside it is a readable contradiction; the
cheapest answer there is the level dimming `PH_DanLight.energy` for that stretch (one export).

**6. A player who outruns him.** Deliberate sprinting past the guide turns him into a follower for
a few hundred px until the level's next event re-leads him. Honest — the player chose it — and
the re-lead is a walk or an off-screen warp, never a pop. **Low.**

---

## Open questions

1. **`PH_DanLight` (Options 4C).** Ship the guide as a faintly lit figure whose light touches
   nothing else? Default if unanswered: yes, energy 0.75 (the alternative — a `CanvasLayer` bubble —
   leaves his body invisible).
2. **`RunSpeed = 300`** for unleashed legs, or `LeadSpeed` everywhere with only the leash off?
   Default: 300 (already his catch-up speed).
3. **Prologue wiring, route, cue table and the final scene** — a separate plan after the author's
   story decision. Nothing in this plan pre-empts it.

---

## Author-side decisions (2026-09-11) — these override anything above
1. **Open question 1 (Dan invisible in the dark) — resolved diegetically: Dan carries his own
   headlamp.** `PH_DanLight` is not a rendering trick but his lamp: a `PointLight2D` on the rig,
   on by default, with a public `SetLampOn(bool)` on `Companion`. Before a gas pocket the level
   turns it OFF first — Dan goes dark, then shouts — so the rule is *shown* before it is *said*.
   In the third story revision (2026-09-11) nothing says his lamp is broken; drop that line.
2. `InitialState = Follow` stays as planned; `TestMine` gains `DanLeads` (default false).
3. Waypoints as a `Marker2D` container, as planned.
4. Story-specific parts (route, cues, ending) are a separate plan — the story is being revised
   for a third time today; do not guess at it.


## Review findings

filled in by `/reviewer`

---

Plan ready. Invoke /coder to implement.
