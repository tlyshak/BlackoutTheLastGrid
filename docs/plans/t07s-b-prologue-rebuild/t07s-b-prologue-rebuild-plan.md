# T-07s-b — Prologue: rebuild for the new story and the seven segments

- Task: [`docs/TASKS.md`](../../TASKS.md) → **T-07s-b · Пролог: перебудова під новий сюжет і сім сегментів**
- Design doc: [`docs/GAME_DESIGN.md`](../../GAME_DESIGN.md) → **§3 Рівень 0 — Пролог: «Зміна»**
  (Сетинг / Хто / Провина / Подія / Кінець прологу / Структура: escape-головоломка / Прогресія: сім сегментів / Мова)
- Mechanics this plan places (already merged, **not** re-designed here):
  [`../t07s-a-escape-mechanics/t07s-a-escape-mechanics-plan.md`](../t07s-a-escape-mechanics/t07s-a-escape-mechanics-plan.md)
- Visual contract to preserve: [`../t07i-c-level-dressing/t07i-c-level-dressing-plan.md`](../t07i-c-level-dressing/t07i-c-level-dressing-plan.md),
  [`../t07i-visual-kit/visual-brief.md`](../t07i-visual-kit/visual-brief.md)
- Player-facing text: **[`script-en.md`](script-en.md)** (written in parallel by the script agent).
  This plan never invents a line; it only says **where each cue fires**. Every string the player
  sees comes from that file, in English.
- Reference layout of the mechanics in a scene: `scenes/levels/TestMine.tscn` + `scripts/levels/TestMine.cs`.

---

## Goal

Rebuild `scenes/levels/Level00_Prologue.tscn` and `scripts/levels/Level00_Prologue.cs` from a
three-room «mine dump with an alarm and two guards» into the **coal-mine escape puzzle of
`GAME_DESIGN.md` §3**: seven segments from the coal face to the surface, the methane blast, the
brother Dan as a companion for the whole run, one power unit shared by every machine, the gas rule
that inverts the flashlight, the sealing crew, the cage with a single switch-off in sight of it, the
scripted death of the brother and the foreman's fine on the surface. Every mechanic already exists
(T-07s-a) and is proven in `TestMine`; this task is **placement, story flow and text**, not new
systems — with two small, named exceptions (§ *Options considered* 3 and 6).

The level must be beatable end-to-end from the main menu to `Level01_District`, must never lock the
player in a state with no way out, must never let a gate be walked around in depth, and must never
require waiting for Dan.

---

## Scope

### In

1. `scenes/levels/Level00_Prologue.tscn` rebuilt: six rooms / 13 440 px, the seven segments, all
   escape props placed (`PowerCircuit`, 5 circuit nodes, 2 + 1 gas pockets, 5 debris piles, 3
   cave-ins, 7 checkpoints, the crew's watch zone, 4 outlets, the companion).
2. `scripts/levels/Level00_Prologue.cs` rewritten: a new `Stage` sequence, checkpoint-driven room
   transitions and story beats, the circuit hand-over at the upper collapse, Dan's cue table, the
   foreman's fine, the hand-over to level 1.
3. `scripts/props/PoweredMachine.cs`: `[Export] StartsPowered` + `public void ForcePower()`
   (additive, default `false` ⇒ `TestMine` byte-identical in behaviour).
4. `scripts/props/WatchZone.cs` + `scenes/props/WatchZone.tscn`: the sealing crew's detection zone
   (the only new mechanic; see *Options considered* 6 for the authorised fallback).
5. Text: every player-visible string comes from [`script-en.md`](script-en.md), in English. Cutscenes
   via the existing `Cutscene` overlay; Dan's reactions via `Companion.Say` bubbles (author decision
   10 of T-07s-a).
6. Tests: `tests/smoke/level_prologue.gd` rewritten and **split in two**
   (`level_prologue.gd` + `level_prologue_escape.gd`), `tests/smoke/level_dressing.gd` updated to the
   new node names, `tests/smoke/props_circuit.gd` extended for `StartsPowered`/`ForcePower`, new
   `tests/smoke/props_watchzone.gd`.
7. `docs/TASKS.md`: status + done note + playtest block.

### Out

- Any change to the mechanics' behaviour from T-07s-a beyond item 3 above. If a placement needs a
  behaviour change, that is a finding for `/reviewer`, not a silent edit.
- `Level01_District`, `TestRoom`, `TestMine`, the menus, the HUD, `project.godot`, `.csproj`,
  `assets/`. `TestMine` stays as the mechanics fixture and is **not** deleted.
- Localisation machinery (`tr()`, `.csv`) — T-07s-d already ruled that out.
- Painted art. Everything visual is procedural `Polygon2D`/`Line2D`/`GPUParticles2D`/`PointLight2D`
  under the `PH_` prefix, palette from `BlackoutLastGrid.Art.Palette`.
- Dan's powerbank as a carried `GameState` item (→ backlog, below).
- A second review round; one review + one fix pass, per `CLAUDE.md`.

### Out of scope → `docs/TASKS.md` backlog (exact lines for `/coder` to add)

```markdown
### T-B17 · Повербанк Дана як предмет у `GameState` · `backlog`
- §2: Рей носить повербанк Дана всю гру і ніколи не витрачає. Зараз це лише рядок у кат-сцені
  прологу. Треба поле в `GameState` (+ іконка в HUD, + перевірка у фіналі) і збереження в T-09.
- Робити разом із T-07s-c (узгодження рівнів 1–5) або з T-09.

### T-B18 · `Door.cs` лишився без жодного користувача · `backlog`
- Після перебудови прологу (T-07s-b) переходи між кімнатами роблять контрольні точки, і `Door`
  не використовується в жодній сцені. Рішення: лишити як будівельний блок для T-08 (район) чи
  прибрати клас разом із `RoomBounds.ArrivalOffset`-контрактом.

### T-B19 · Пропуск кат-сцен цілком · `backlog`
- У пролозі 7+ кат-сцен; на плейтесті кожен повторний прогін коштує ~2 хвилини натискань `E`.
  Потрібен «skip all» (утримання `Esc` або окрема дія), спільний для `Cutscene`.

### T-B20 · Орієнтир на працюючу машину в темряві · `backlog`
- Якщо плейтест прологу покаже блукання: маркер/стрілка до панелі, названої у відмові контуру
  («Not enough power: Pump is running»). Дешева альтернатива — ще одна тепла лампа на сегмент.
```

---

## Design-doc conformance

Section implemented: **`GAME_DESIGN.md` §3 — Рівень 0 «Зміна»**, all of it (Сетинг, Хто, Провина,
Подія, Кінець прологу, «Структура: escape-головоломка», the machine table, «Прогресія (сім
сегментів)», «Мова», «Готово, коли»). Also §4 («ліхтар = ресурс», «стелс як опція»), §6 (colour of
the air, warm hero / cold enemies) and §2 (both of Rey's motives are set up by the ending).

Requirement-by-requirement, task text vs. design doc:

| Requirement (TASKS.md T-07s-b) | Design doc | Verdict |
|---|---|---|
| seven segments, in the listed order | §3 «Прогресія (сім сегментів)» | **agree** |
| no way back; one switch-off at the cage | §3 segment 5 + «Походу назад НЕМАЄ» | **agree** |
| all player text English | §3 «Мова» | **agree** |
| cutscenes rewritten (brother, report, fine, missing report, surface) | §3 «Провина» + «Кінець прологу» | **agree** |
| fan panel becomes the extractor; `PH_Dan` becomes the brother | §3 machine table | **agree** |
| Dan accompanies segments 1→6, never lost, never killed by gameplay | §3 «Брат іде з тобою» | **agree** |
| gas section passable two ways; crew avoidable | §3 «Головна пастка-механіка» + segment 3 | **agree** |

Four places where the documents are **stale or contradict each other**. All four already have a
dated author decision, so nothing is invented here — the resolution is recorded, not chosen:

1. **§3 segment 4 says «конвеєр як платформа»**, while the same section says «Три машини, не
   чотири [ПІДТВЕРДЖЕНО 2026-09-11]» and drops the conveyor to the backlog (T-B14).
   **Resolution (T-07s-a author decision 9):** the upper horizon is reached through a **cleared
   debris ramp** — `heavy_attack` on a `DebrisPile`, a verb the player learned in segment 1. The
   conveyor keeps its story role only: it is the machine whose spark lights the methane.
2. **§3 «Готово, коли» says «кожен із чотирьох вузлів контуру»** — it counts the conveyor.
   **Resolution:** the rebuilt level has **five circuit nodes** — `Work lights`, `Pump`,
   `Extractor`, `Floodlight`, `Hoist` — of which **three open a way** (the §3 machine table:
   витяжка, насос, кліть) and **three force a switch-off** (pump forces the work lights off,
   extractor forces the pump off, hoist forces the floodlight off). The criterion is met and
   exceeded; the lights are circuit *load*, not a fourth puzzle machine.
3. **TASKS.md bullet «Зворотний хід — головне в головоломці»** contradicts the later bullet in the
   same task, **«Походу назад немає (2026-09-11)»**, and `GAME_DESIGN.md` §3 segment 5.
   **Resolution:** the dated bullet wins. There is no long back-run. What survives is two **short
   in-room loops** (760 px and ~1 100 px, both inside one camera view) — allowed explicitly by
   T-07s-a *Design risks* §1 («a machine's panel and the obstacle it removes within one screen; the
   two panels that compete within ~2 screens»). This is called out honestly in *Design risks* §2
   below: those loops are backtracking, just cheap backtracking.
4. **TASKS.md «конвеєр стає і сюжетною причиною вибуху, і платформою»** — the platform half is
   T-B14. Ignition half kept.

**Nothing here needs the author before `/coder` runs.** Two agent-level decisions that the author
may overturn are listed under *Resolved (agent decisions)*.

---

## Options considered

### 1. How does the camera/floor band change between segments — `Door`, or something else?

| Option | Trade-off |
|---|---|
| **A. Keep `Door` gates** (today's prologue) | Proven, has a visual gate, re-locks behind. But the new level's boundaries are open drifts sealed by rubble, not doorways; a `Door` would be a second, redundant sealing mechanic next to `CaveIn` + `DebrisPile`, and `PassDoor` teleports the hero, which reads badly in a continuous drift. |
| **B. One room for the whole level** | Simplest. Kills `RoomBounds.Fx` room gating (T-07i-c's frame-budget contract: only the active room's emitters run) and makes the camera limits useless. Rejected. |
| **C (recommended). Rooms tile; a `Checkpoint` at each boundary applies its own `RoomBounds`** | `Checkpoint` already carries `[Export] Room`, spans the whole band (80×320 prefab), fires once, and `RespawnAtCheckpoint` already re-applies that room. One `switch` on `Checkpoint.Label` in `OnCheckpointArmed` gives, at once: room bounds, FX gating, the armed respawn and the segment's story beat. Zero new classes. Cost: a small camera-limit jump at each boundary (the same jump `Door` produced, without the teleport). |

**Chosen: C.** `Checkpoint.Label` becomes the level's event key — this is the one structural idea of
the rewrite, and it is what makes «a checkpoint before every hazard» automatic instead of a rule
somebody has to remember.

### 2. Where do the circuit refusals happen, and how is a soft-lock made impossible?

The danger of this level is structural, not visual: **one-way seals + a circuit you can only free at
the running machine's own panel = a hard lock** if a seal ever falls between the player and a
machine that is still running.

| Option | Trade-off |
|---|---|
| A. No seals at all between segments 1 and 5 | Safe, but «шахта складається» and «шлях назад відрізано» disappear — that is the thing that pushes the player forward (§3). |
| B. Auto-preemption (a new machine silently takes the power) | Removes the lock **and** the lesson; explicitly rejected by the author (decision 4 of T-07s-a). |
| **C (recommended). An invariant plus one diegetic hand-over** | Only **three** cave-ins exist. Seal 1 (the blast) falls before anything is powered. Seal 2 (end of the gas segment) is the moment the mine cuts the lower horizon off: the level powers **down** every machine behind the seal and hands the single power unit to the cage floodlight ahead of it. Seal 3 is the final one, after which no machine is ever needed again. |

**Chosen: C.** It yields a checkable invariant `/reviewer` can hold the scene to:

> **Circuit reachability invariant.** At every moment of the run, every machine that *can* be
> powered has its panel on the player's side of every seal that has fallen. Enforced by: only three
> `CaveIn`s; none of them between a running machine and its competitor; and the second one calls
> `PowerDown()` on `Pump` and `Extractor` and `ForcePower()` on `Floodlight`.

And it is what makes §3 segment 5 literally true — at the cage, the last running machine is right
there, in view, and it is the only thing between you and the surface.

### 3. How does a machine come up already running (the work lights at the start of segment 2)?

§3 segment 2 requires that the pump's power be taken **from the working lights**, so the lights must
already hold the circuit when the player first tries the pump.

| Option | Trade-off |
|---|---|
| A. Level calls `Lights.Begin(Player)` in `_Ready` | Zero code change; `Interactable.Begin` does not touch the player and an empty `Sequence` completes immediately. But it fakes an interaction, emits `Finished(true)` into nowhere, and is untestable as intent. |
| **B (recommended). `[Export] bool StartsPowered` + `public void ForcePower()` on `PoweredMachine`** | ~15 lines, default `false` ⇒ nothing existing changes. Needed **twice**: the work lights at level start and the floodlight at the hand-over (option 2C), so it is not a one-off hack. Testable from smoke. |

**Chosen: B**, with A recorded as the fallback if `/reviewer` objects to touching a T-07s-a class.

### 4. The «upper horizon» in a belt-scroll with no vertical axis

| Option | Trade-off |
|---|---|
| A. Change the floor band per room (e.g. 260…560) to suggest height | 40 px of "up" that nobody reads, and it snaps the hero's Y on every room change and invalidates the uniform 320 px gate depth. Rejected. |
| **B (recommended). Same band everywhere (300…600); "up" is told, not simulated** | The cleared ramp pile leaves a visible slope decal, the backdrop changes (timbered drift → concrete gallery), the cage floodlight becomes visible at the far right, and Dan says it out loud (§3: «Дан це вимовляє вголос»). Uniform band keeps every gate shape (320 px) and `BlockerDepth` correct in every room. |

**Chosen: B.** Honest note in *Design risks* §5: this segment is the weakest of the seven and it is
carried by one line of dialogue and one silhouette.

### 5. The final collapse and Dan's death — how is the brother left behind without the companion's failsafes dragging him back?

`CompanionFollow` warps him to the hero after `StuckSeconds = 2.5` or past `WarpDistance = 900`, and
`LevelBase.ApplyRoomBounds` / `RespawnAtCheckpoint` call `WarpBehind()`, which moves even a held
position. So:

- On `CaveIn_Final.Collapsed` the level **immediately** calls `Dan.HoldAt(Dan.GlobalPosition)`.
  `CompanionWait` aims all three failsafes at the **held spot**, not at the hero, so his distance
  from Rey no longer matters and he stays behind the rubble.
- **No checkpoint may arm after the final collapse inside `Room_Cage`**, and the level's `Respawned`
  handler re-issues `HoldAt` for the farewell (the remedy `Companion.WarpBehind`'s own doc-comment
  prescribes). The only post-farewell checkpoint is `Checkpoint_Surface`, in the next room.
- Nothing in the segment can kill the hero (no gas, no watch zone, no enemy), so a respawn there is
  only possible through the debug path — but the guard is written anyway.

### 6. The sealing crew — which enemy?

§3: «вони в масках і з інструментом, **їх не побити на цьому етапі**; їх обходять у темряві».

| Option | Trade-off |
|---|---|
| A. `Guard` + `WaveSpawner` with `DarkPerceptionFactor = 0` | Zero new code and the rule «lamp on = seen» falls straight out. But a `Guard` **can** be beaten (just slowly), `IsAware` is sticky forever, and once noticed the player is in an unwinnable chase. Contradicts the design line above. Rejected. |
| B. Reuse `GasZone` with `Lethal = false` as a "searchlight" | Zero new code, proven lifecycle. But it reacts only to `Flashlight.IsOn`, so the crew's own lamp pools cannot matter — the segment collapses into «don't use your lamp», identical to the gas pocket two screens earlier, teaching nothing new. |
| **C (recommended). New `WatchZone : Area2D`, ~90 lines, modelled beat-for-beat on `GasZone`** | Reacts to `Player.IsLit` — i.e. to the head lamp **and** to the crew's `LitZone` lamp pools — so the segment is real navigation: weave through the dark lanes the pools leave. Warning window (0.6 s) keeps it fair; being caught is `Player.Kill()` ⇒ the existing soft-respawn pipeline; the crew themselves are scenery (`PH_` rigs, no collision, no script). Cost: one new class and one new prefab, and `IsLit` has no signal, so the zone polls one bool per physics frame **while the hero is inside it** (`SetPhysicsProcess` off otherwise). |

**Chosen: C**, and **B is pre-authorised as the shipping fallback** if the fix pass runs short of
time or `/reviewer` refuses a new mechanic: swap `WatchZone_Crew` for a `GasZone`-shaped searchlight,
drop the lamp pools, keep the crew as scenery. The «бригаду можна обійти» criterion survives either
way.

---

## Recommended approach

A single `Node2D` level scene, 13 440 × 1080, y-sorted, six tiled `RoomBounds`, seven segments.
Progress is driven by **signals only**; the level script has no per-frame logic beyond the debug
label (same rule the current prologue already follows).

- **Rooms and beats** come from `Checkpoint.Label` (*Options* 1). `OnCheckpointArmed(cp)` does
  `ApplyRoomBounds(cp.Room)` and then `switch (cp.Label)` for the beat: a cutscene, a Dan cue, a
  darkness tween, arming a trigger.
- **The circuit** is one `PowerCircuit` node, `Capacity = 1`, with five `PoweredMachine`s
  (`Hoist` is the subclass). The refusal text is already the teaching tool
  (`"Not enough power: {0} is running"`), and Dan says the rule out loud the first time
  (T-07s-a *Design risks* §7).
- **Hazards** are `GasZone` (three instances), `WatchZone` (one) and nothing else. Cave-ins never
  kill; the flooded drift blocks and does not drown; energy is never a gate (see below).
- **Dan** is a `Companion` instance wired to `LevelBase.Companion`, in `Follow` for the whole level
  except four scripted holds (blast, crew, farewell, surface). Every hold is followed by `Resume()`
  except the last. **Nothing ever waits for `Arrived`.**
- **Energy can never soft-lock the run.** Nothing in the prologue requires the lamp: every gate is
  opened by a panel or by `heavy_attack`, and every dark stretch is crossable blind (that is the
  point of the gas rule). Four `Outlet`s are comfort, not a gate; `LevelBase.MinRespawnEnergy = 30`
  covers the respawn case. This is an acceptance criterion, not an assumption.
- **The old prologue's content**: the fan panel becomes the `Extractor`; the panel sparks move to
  the blast; the guards and `WaveSpawner` move to the surface fight; `Door_1`/`Door_2`, the alarm
  stage, the blinking alarm lights and `AlarmPromptText`/`EscapePromptText` are **cut** (there is no
  alarm in the new story — the mine's own collapse is the pressure). `AlarmLights` may be reused as
  emergency beacons at the blast (nice-to-have). The tutorial prompts, the crate
  (`JumpableObstacle`), the outlet, `LitZone`, the parallax/backdrop/ground/foreground groups and
  the FX groups all survive.

### Priorities — must / nice-to-have

The scene grows from 1 892 to roughly 2 600–3 000 lines. `/coder` builds in this order and stops
adding polish when the **must** list is green.

**Must (the task is not done without these)**

| # | Item |
|---|---|
| M1 | Scene skeleton: 6 rooms, 7 checkpoints, player, Dan, HUD, pause, camera, `LevelFx`, `Vignette`, `PowerCircuit`, debug label |
| M2 | Segment 0–1: tutorial prompts, the conveyor, the blast (`CaveIn_Blast` + darkness tween + work lamps off), finding Dan, flashlight + outlet tutorial, the timber pile (`heavy_attack`) |
| M3 | Segment 2: `Work lights` running at start, pump refused by them, pump clears the flood |
| M4 | Segment 3: rehearsal pocket (1.5 s), extractor refused by the pump, real pocket (0.8 s) passable **either** by the extractor **or** in the dark |
| M5 | Segment 3 stealth: crew avoidable with the lamp off (option 6C, or the authorised 6B fallback) |
| M6 | Segment 4: ramp pile, `CaveIn_Upper`, the circuit hand-over, the cage visible |
| M7 | Segment 5–6: floodlight vs. hoist in one view, `CaveIn_Final`, Dan held behind it, the farewell cutscene, boarding |
| M8 | Segment 7: foreman cutscene, `FinePenalty`, one-guard fight for the powerbank, closing cutscene, `GoToLevel(Level01_District)` |
| M9 | Every gate spans the walk band and is proven un-bypassable (tests) |
| M10 | All player text English, from `script-en.md`; Dan's cue table wired |
| M11 | Tests: two prologue smoke scripts + `level_dressing.gd` + `props_circuit.gd` + `props_watchzone.gd`, all green with `tools/smoke.ps1` |

**Nice-to-have (cut first)**

N1 per-room prop dressing at the density T-07i-c gave rooms 1–3 (the new rooms ship with the
*structural* tier: backdrop wall, floor, floor edge, near band, one parallax extension, one or two
ambient emitters, one warm light) · N2 emergency beacons reusing `AlarmLights` · N3 the crew's
cutting-torch particle FX · N4 a fourth outlet · N5 a second, purely cosmetic cave-in during the
gas segment · N6 `PH_` signage labels in the mine · N7 the conveyor belt animation still running in
segment 0 · N8 a distinct backdrop palette per room.

---

## GameState & save impact

- **Read/written:** `GameState.Energy` — by `Outlet` (+25 per use, existing prop), by `Flashlight`
  (−1/s, existing), by `LevelBase.RespawnAtCheckpoint` (restores the checkpoint snapshot, floor
  `MinRespawnEnergy = 30`) and by the level once, at the foreman beat:
  `GameState.Instance.AddEnergy(-FinePenalty)` with `[Export] float FinePenalty = 20` (unchanged
  value and semantics from today's prologue). `EnergyChanged(float)` is emitted by the autoload as
  before; the HUD already listens.
- **`GameState.CurrentScenePath`** — written by `LevelBase.GoToLevel` at the hand-over to
  `Level01_District`, exactly as today.
- **`Route`, `JournalsFound`, `DistrictReputation`** — untouched.
- **No new field and no new signal on the autoload.** The prologue's progress lives in the level
  instance (`Stage`, the circuit, `IClearable` flags), which is correct: it is level state, not run
  state, and a checkpoint respawn deliberately keeps it without a reload.
- **For T-09 (Save/Load)** this task creates the following *named* state that a mid-prologue save
  would have to persist — T-09's plan should pick it up: `Level00_Prologue.CurrentStage`, the armed
  `Checkpoint.Label`, `PowerCircuit`'s powered machine (by `PoweredMachine.SaveId`), and the
  `IsCleared` flag of every `DebrisPile`/`GasZone` (by `DebrisPile.SaveId`; `GasZone` has no
  `SaveId` yet and would need one). Also named there: **Dan's powerbank** (→ backlog T-B17).

---

## Scene & signal contract

House rules that apply to every node below: `PH_` prefix on placeholder visuals; colours from
`BlackoutLastGrid.Art.Palette`, never a literal `Color(...)` in a script; `z_index` per the visual
brief's depth table; `Hitbox`/`Hurtbox` keep those exact names; every `[Export]` has a default and a
unit.

### A. `scripts/props/PoweredMachine.cs` — additive (two members)

| new `[Export]` | Type | Default | Unit / meaning |
|---|---|---|---|
| `StartsPowered` | `bool` | `false` | the machine holds the circuit from `_Ready` (the work lights) |

| new API | Signature | Behaviour |
|---|---|---|
| `ForcePower()` | `public void ForcePower()` | No-op when `IsPowered`. `Circuit.TryPower(this, out _)` — on success: mark the panel activated without an interaction (`_repaired = true`, `IsActivated = true`, screen → `ActiveColor`, `NotifyPromptChanged()`), then the existing `SetPowered(true)`; on failure `GD.PushWarning($"{Name}: ForcePower refused — the bus is already loaded")` and nothing changes. Never calls `Finish()` (there is no interaction to finish). |

`_Ready` gains, **after** `Circuit.Register(this)`:
`if (StartsPowered) { Callable.From(ForcePower).CallDeferred(); }` — deferred on purpose, so the
level (a parent, therefore `_Ready` *after* its children) has already connected `PowerChanged` and
`Circuit.LoadChanged` and sees the event. Implementation note for `/coder`: marking the panel
activated needs one new `protected void MarkActivated()` on `PowerPanel` (the body of `Complete()`
minus the `Powered` check and minus `Finish(true)`), and `Complete()` should then call it — no
duplicated state machine.

**Defaults preserve behaviour byte for byte**: `StartsPowered = false` everywhere in `TestMine` and
in `scenes/props/PoweredMachine.tscn`; `props_circuit.gd` must stay green unchanged, plus new §.

### B. New: `scenes/props/WatchZone.tscn` ↔ `scripts/props/WatchZone.cs`

`partial class WatchZone : Area2D` — the sealing crew's field of view. Mirrors `GasZone`'s proven
lifecycle; the only difference is **what** it watches (`Player.IsLit`, i.e. head lamp **or** a
`LitZone` pool) and **what** it does (a knock-out, not an explosion).

```
WatchZone             Area2D            collision_layer 0, collision_mask 2 (Player),
                                        monitoring = true, monitorable = false, script = WatchZone.cs
  CollisionShape2D    RectangleShape2D  the watched stretch, default 700 × 320 — across the WHOLE band
  PH_Alert            PointLight2D      enabled = false; flares during the warning (Palette.AlarmGlow)
```

| `[Export]` | Type | Default | Unit / meaning |
|---|---|---|---|
| `WarningSeconds` | `float` | `0.6` | s between "seen" and "caught" — kill the lamp or leave the pool and you live |
| `AlertLight` | `PointLight2D?` | `null` | flares while the warning counts down |
| `Room` | `RoomBounds?` | `null` | `_Ready` sanity check only: warn unless the shape spans `FloorTop…FloorBottom` (copied verbatim from `GasZone.WarnUnlessTheBandIsCovered`) |
| `Disabled` | `bool` | `false` | the level can retire the zone once the segment is over |

| Signal | Parameters | When |
|---|---|---|
| `Spotted` | `()` | the hero is inside **and** lit; the window starts |
| `LostSight` | `()` | he went dark or stepped out before the window ran out |
| `Caught` | `(Player player)` | the window ran out |

Wiring and lifetime (the `GasZone` template, and `/reviewer` should diff them):
`BodyEntered` → remember the player, `SetPhysicsProcess(true)`; `_PhysicsProcess` reads
`_player.IsLit` (polled, because `Player` exposes no `LitChanged` signal — one bool per frame, and
only while occupied) and runs the countdown; `BodyExited` → forget, `Disarm()`,
`SetPhysicsProcess(false)`; `Caught` → `Disarm()`, `EmitSignalCaught(p)`, `p.Kill()` ⇒ the existing
`LevelBase` KO → `RespawnDelay` → `RespawnAtCheckpoint()` path, which already forces the lamp off on
revive; `_ExitTree` → unsubscribe unconditionally.

**Why `Kill()` and not damage:** the level has exactly one failure verb already (gas), one respawn
pipeline, one checkpoint rule. A second, different punishment would need its own tuning and its own
test. Cost of being caught = the same «seconds, not the level».

### C. Rebuilt: `scenes/levels/Level00_Prologue.tscn`

Root `Level00_Prologue` — `Node2D`, `y_sort_enabled = true`, script `scripts/levels/Level00_Prologue.cs`.
World 13 440 × 1080. **Floor band 300…600 in every room** (Options 4): band centre **Y = 450**, so
every gate's root Y is 450 and `BlockerDepth = 320` covers 290…610.

#### Rooms (tiled; `Fx` per room for the T-07i-c gating contract)

| `RoomBounds` | `Rect` | `FloorTop`/`Bottom` | `Fx` | Segment |
|---|---|---|---|---|
| `Rooms/Room_Face` | `(0, 0, 2880, 1080)` | 300 / 600 | `Fx_Face` | 0 + 1 |
| `Rooms/Room_Flood` | `(2880, 0, 1920, 1080)` | 300 / 600 | `Fx_Flood` | 2 |
| `Rooms/Room_Gas` | `(4800, 0, 2880, 1080)` | 300 / 600 | `Fx_Gas` | 3 |
| `Rooms/Room_Upper` | `(7680, 0, 1920, 1080)` | 300 / 600 | `Fx_Upper` | 4 |
| `Rooms/Room_Cage` | `(9600, 0, 1920, 1080)` | 300 / 600 | `Fx_Cage` | 5 + 6 |
| `Rooms/Room_Surface` | `(11520, 0, 1920, 1080)` | 300 / 600 | `Fx_Surface` | 7 |

Every `Rect` is ≥ the 1920×1080 viewport, so the camera limits are always valid.

#### Placement table (the map)

`x` is world X; every gate and trigger sits at root **Y = 450** unless stated. "gate" = must span
the band.

| x | Node | Type / instance | Key values |
|---|---|---|---|
| **Room_Face — segment 0 (coal face, lights on)** ||||
| 200 | `Player` | `Player.tscn` | y 480 |
| 120 | `Companion` | `Companion.tscn` | y 490, `Target = Player` |
| 200 | `Checkpoint_Face` | `Checkpoint.tscn` | `Room_Face`, `Label = "face"` — arms on frame 1 |
| 420 | `Tutorial/MovePrompt` | `TutorialPrompt` | `CompletesOnAction = "move_right"` |
| 780 | `Tutorial/JumpPrompt` | `TutorialPrompt` | `CompletesOnAction = "jump"` |
| 820 | `Crate` | `JumpableObstacle` | y 470, kept from today's scene |
| 1100–1700 | `Fx_Face/Conveyor` | `Sprite2D` + `AnimationPlayer` | the ignition source; **no collision**, base y 292 |
| 1420 | `DebrisPile_BlastSeal` | `DebrisPile.tscn` | **gate**, `StartsCleared = true`, `HeavyHitsToClear = 0` |
| 1520 | `CaveIn_Blast` | `CaveIn.tscn` | `Blockage = DebrisPile_BlastSeal`, `Delay = 0.35`, `ShakeAmplitude = 26`, `ShakeSeconds = 1.6` |
| **Room_Face — segment 1 (blast, darkness, Dan)** ||||
| 1900 | `PH_DanFallen` | `Polygon2D` decal | where Dan is found (visual only) |
| 1840 | `Checkpoint_Blast` | `Checkpoint.tscn` | `Room_Face`, `Label = "dan"` |
| 1980 | `Tutorial/FlashlightPrompt` | `TutorialPrompt` | `CompletesOnAction = "flashlight"`, `Timeout = 6` |
| 2120 | `Outlet_1` | `Outlet.tscn` | y 560, `Uses = 3`, `Cooldown = 8` |
| 2320 | `Tutorial/HeavyPrompt` | `TutorialPrompt` | `CompletesOnAction = "heavy_attack"` |
| 2450 | `DebrisPile_Timber` | `DebrisPile.tscn` | **gate**, `HeavyHitsToClear = 2`, `+ PH_HitStrip` decal at y 450 |
| **Room_Flood — segment 2 (flooded drift, pump, first refusal)** ||||
| 2920 | `Checkpoint_Flood` | `Checkpoint.tscn` | `Room_Flood`, `Label = "flood"` |
| 3140 | `Lights_Drift` | `PoweredMachine.tscn` | `DisplayName = "Work lights"`, **`StartsPowered = true`**, `CanPowerDown = true`, `ClearTargets = []`, `RunLight = PH_DriftLamp`, `RunFx = Fx_Flood/DriftLamps` (a `Node2D` of 3 `PointLight2D`) |
| 3260 | `Outlet_2` | `Outlet.tscn` | y 560 |
| 3900 | `Pump` | `PoweredMachine.tscn` | `DisplayName = "Pump"`, `ClearTargets = [Flood]`, `Sequence = ["move_up","attack","move_down","jump"]` — **the one repair beat of the level** (§4's 3–4 buttons); every other machine keeps `Sequence = []` |
| 4260 | `Flood` | `DebrisPile.tscn` | **gate**, `HeavyHitsToClear = 0`, `modulate` water-blue |
| **Room_Gas — segment 3 (gas + crew)** ||||
| 4840 | `Checkpoint_Gas1` | `Checkpoint.tscn` | `Room_Gas`, `Label = "gas_rehearsal"` |
| 5100 | `GasZone_Rehearsal` | `GasZone.tscn` | **gate-width** (180×320), `WarningSeconds = 1.5`, `Room = Room_Gas`, *not* in any `ClearTargets` |
| 5340 | `Outlet_3` | `Outlet.tscn` | y 560 |
| 5620 | `Extractor` | `PoweredMachine.tscn` | `DisplayName = "Extractor"`, `ClearTargets = [GasZone_Pocket_A, GasZone_Pocket_B]` |
| 5820 | `Checkpoint_Gas2` | `Checkpoint.tscn` | `Room_Gas`, `Label = "gas_pocket"` |
| 6000 / 6180 | `GasZone_Pocket_A` / `_B` | `GasZone.tscn` ×2 | 180×320 each ⇒ a continuous 360 px pocket, `WarningSeconds = 0.8`, `Room = Room_Gas` |
| 6500 | `Checkpoint_Crew` | `Checkpoint.tscn` | `Room_Gas`, `Label = "crew"` |
| 7050 | `WatchZone_Crew` | `WatchZone.tscn` | shape **700 × 320** (x 6700…7400), `WarningSeconds = 0.6`, `Room = Room_Gas` |
| 6850 | `LitZone_Crew1` | `Area2D` + `LitZone.cs` | pool **220 × 170**, centred **y 520** ⇒ dark lane y 300…430 |
| 7200 | `LitZone_Crew2` | `Area2D` + `LitZone.cs` | pool **220 × 170**, centred **y 380** ⇒ dark lane y 470…600 |
| 6850 / 7200 | `PH_Crew1` / `PH_Crew2` | `CharacterRig` instances | `SuitColor = Palette.GuardSuit`, **no collision, no script**, base y 300 (behind the band) |
| 7540 | `DebrisPile_UpperSeal` | `DebrisPile.tscn` | **gate**, `StartsCleared = true`, `HeavyHitsToClear = 0` |
| 7600 | `CaveIn_Upper` | `CaveIn.tscn` | `Blockage = DebrisPile_UpperSeal`, `Delay = 0.35` — **the circuit hand-over fires on `Collapsed`** |
| **Room_Upper — segment 4 (upper horizon)** ||||
| 7720 | `Checkpoint_Upper` | `Checkpoint.tscn` | `Room_Upper`, `Label = "upper"` |
| 8300 | `DebrisPile_Ramp` | `DebrisPile.tscn` | **gate**, `HeavyHitsToClear = 2`, `+ PH_HitStrip` |
| 8900 | `Checkpoint_Sight` | `Checkpoint.tscn` | `Room_Upper`, `Label = "sight"` — Dan's «there it is» |
| 9100 | `Outlet_4` | `Outlet.tscn` | y 560 (nice-to-have N4) |
| **Room_Cage — segments 5 + 6** ||||
| 9640 | `Checkpoint_Cage` | `Checkpoint.tscn` | `Room_Cage`, `Label = "cage"` — **the last checkpoint before the surface** |
| 10120 | `Lights_Cage` | `PoweredMachine.tscn` | `DisplayName = "Floodlight"`, `StartsPowered = false` (the level calls `ForcePower()` at the hand-over), `CanPowerDown = true`, `ClearTargets = []` |
| 10700 | `DebrisPile_Final` | `DebrisPile.tscn` | **gate**, `StartsCleared = true`, `HeavyHitsToClear = 0` |
| 10760 | `CaveIn_Final` | `CaveIn.tscn` | `monitoring = false` **in the scene**; armed by the level on `Lights_Cage.PowerChanged(false)` |
| 11240 | `Hoist` | `Hoist.tscn` | `RequiresWholeCircuit = true`, `CanPowerDown = false`, `DisplayName = "Hoist"`, `BoardingArea` 120×320 in front |
| **Room_Surface — segment 7** ||||
| 11700 | `Checkpoint_Surface` | `Checkpoint.tscn` | `Room_Surface`, `Label = "surface"` |
| 12100 | `PH_Foreman` | `CharacterRig` instance | `SuitColor = Palette.GuardSuit`, no collision |
| — | `GuardSpawner` | `WaveSpawner.tscn` (moved) | `EnemyScene = Guard.tscn`, `Count = 1`, `LockRect` = `Room_Surface.Rect`, `Player`, `Director`, `Camera` wired; started by the level after the foreman cutscene |
| 11520–13440 | `Parallax/PxSurface*` | `Parallax2D` | dead district TEC behind (left), the lit centre on the horizon (right) — §3's closing image |

Distances that matter (and that `/reviewer` should re-measure in the scene): pump ↔ work-lights
panel **760 px**; extractor ↔ pump panel **1 720 px** (under two screens); hoist ↔ floodlight panel
**1 120 px** — *inside one 1920 px camera view*, which is what §3 segment 5 demands.

#### Structural groups kept from T-07i-c (do not rename, do not re-parent)

`Parallax/PxRockFar|PxRockMid|PxStruct` (`Parallax2D`, scroll 0.15 / 0.35 / 0.55, widened to cover
`1920 + scroll·(13440−1920)`), `Backdrop/*` (z −40), `Ground/*` (z −20, incl. `PH_NearBand` which
must now span the full 13 440 px so no clear colour shows at the bottom), `Props` (z 0,
**`y_sort_enabled = true`**), `Fx_<Room>` (z +20, one per room, referenced by `RoomBounds.Fx`),
`Foreground` (`Parallax2D` 1.25, z +40), `Vignette`, `LevelFx`, `HUD`, `PauseMenu`, `Cutscene`,
`UI/DebugLabel`, `Camera2D`, `EnemyDirector`.

Renames: `PH_Wall_1..3` → `PH_Wall_Face|Flood|Gas|Upper|Cage|Surface`, ditto `PH_Floor_*`,
`Fx_Room1..3` → `Fx_Face|Flood|Gas|Upper|Cage|Surface`, `Room_Zaboi|Vent|Exit` →
`Room_Face|Flood|Gas|Upper|Cage|Surface`. **`tests/smoke/level_dressing.gd` hard-codes every one of
those names and `LEVEL_WIDTH = 5760` and `STAGE_VENTILATION = 2`** — it must be updated in the same
commit (see *Test strategy*).

**Dressing tier rule** (so the four new rooms do not eat the whole task): each new room ships with
backdrop wall + floor + floor edge + near band + its parallax extension + 1–2 ambient emitters +
**one warm light visible from the room's entrance** (T-07s-a *Design risks* §6). Prop stacks at the
density of today's rooms 1–3 are nice-to-have N1.

**Collision rule for dressing** is unchanged and non-negotiable (T-07i-c): base y ≤ 296 or ≥ 604 ⇒
decoration, no collision; base inside 300…600 ⇒ a `StaticBody2D` child named `Blocker`
(layer 1, mask 0) or a flat floor decal. **Nothing new may narrow a walk lane**, and specifically
nothing may narrow the crew's dark lanes (y 300…430 at x 6700…7000 and y 470…600 at x 7050…7400).

### D. Rewritten: `scripts/levels/Level00_Prologue.cs`

`partial class Level00_Prologue : LevelBase`.

```csharp
public enum Stage { Intro, Face, Blast, Flood, Gas, Crew, Upper, Cage, Farewell, Surface, Fight, Ending, Done }
```

| Signal | Parameters | When |
|---|---|---|
| `StageChanged` | `(string stage)` | every stage change (kept from today: tests and the debug label use it) |

| `[Export]` | Type | Default | Unit / meaning |
|---|---|---|---|
| `FinePenalty` | `float` | `20` | energy taken by the foreman |
| `DarknessLit` | `Color` | `#8f97a3` | `CanvasModulate` while the station lighting is on (segment 0) |
| `DarknessMine` | `Color` | `#0a0d14` | after the blast (`Palette.OutlineDark`) |
| `DarknessSurface` | `Color` | `#6b7280` | overcast daylight on the surface |
| `DarknessFadeSeconds` | `float` | `1.2` | s of the tween between them |
| `CutsceneSkippable` | `bool` | `true` | unchanged |
| `IntroLines` … `EndLines` | `string[]` | `{}` | **one array per cutscene, filled from `script-en.md`** — see the cue table |
| `NextLevel` | `PackedScene` | `null!` | `Level01_District.tscn` |
| `StartRoom` | `RoomBounds` | `null!` | `Room_Face` |
| `Circuit` | `PowerCircuit` | `null!` | the single bus |
| `Lights` / `Pump` / `Extractor` / `Floodlight` | `PoweredMachine` | `null!` | wired for the hand-over and for Dan's cues |
| `Cage` | `Hoist` | `null!` | `Departed` → surface |
| `GasPockets` | `GasZone[]` | `{}` | all three, for Dan's shout |
| `Crew` | `WatchZone?` | `null` | the stealth zone |
| `BlastCollapse` / `UpperCollapse` / `FinalCollapse` | `CaveIn` | `null!` | the three seals |
| `DanFallenAt` | `Vector2` | `(1900, 520)` | where Dan is warped to at the blast |
| `WorkLamps` | `Node2D?` | `null` | segment-0 station lighting, hidden at the blast |
| `GuardSpawner` | `WaveSpawner` | `null!` | the surface fight |
| `Cutscene`, `Darkness`, `Tutorial`, `DebugLabel` | node refs | `null!` | as today |

Flow, entirely signal-driven:

- `_Ready`: `base._Ready()`, `ApplyRoomBounds(StartRoom)`, connect everything below, play
  `IntroLines`.
- `CheckpointArmed(cp)` → `ApplyRoomBounds(cp.Room!)` then `switch (cp.Label)`: `"face"` → stage
  `Face`; `"dan"` → stage `Blast` beat (Dan `Resume()` + cutscene); `"flood"` → `Flood`;
  `"gas_rehearsal"` → `Gas`; `"crew"` → `Crew` + `Dan.Say(DAN_CREW_DUCK)`; `"upper"` → `Upper`;
  `"sight"` → `Dan.Say(DAN_SIGHT)`; `"cage"` → `Cage`; `"surface"` → `Surface`.
- `BlastCollapse.Triggered` → stage `Blast`: freeze actors, shake, `PlayCutscene(BlastLines)`,
  tween `Darkness` → `DarknessMine`, `WorkLamps.Visible = false`, `Dan.WarpTo(DanFallenAt)` +
  `HoldAt(DanFallenAt)` + `SetBubbleSuppressed(true)`.
- `Circuit.RequestRefused(machine, blocking)` → `Dan.Say(...)` — the **first** refusal gets the
  rule line (`DAN_RULE`), later ones a short one (`DAN_REFUSED`). The panel already prints
  «Not enough power: {0} is running» itself; Dan never repeats the text.
- `Circuit.MachinePowered(machine)` / `MachineReleased(machine)` → Dan's per-machine cue.
- `GasZone.WarningStarted` (any of the three) → `Dan.Say(DAN_GAS)`. `Ignited` → `Dan.Say(DAN_GAS_BOOM)`.
- `Crew.Spotted` → `Dan.Say(DAN_CREW_SEEN)`; `Crew.Caught` → nothing extra (the KO pipeline runs).
- `UpperCollapse.Collapsed` → **the hand-over**: `Pump.PowerDown()`, `Extractor.PowerDown()`,
  `Floodlight.ForcePower()`, `Dan.Say(DAN_HANDOVER)`. (Order matters: release before power.)
- `Floodlight.PowerChanged(false)` → arm the final collapse:
  `FinalCollapse.SetDeferred(Area2D.PropertyName.Monitoring, true)`.
- `FinalCollapse.Collapsed` → stage `Farewell`: `Dan.HoldAt(Dan.GlobalPosition)`,
  `PlayCutscene(FarewellLines)`.
- `Cage.Departed(player)` → stage `Surface`: `PlayCutscene(ArrivalLines)`; on that cutscene's end,
  teleport the hero to `Room_Surface`, `ApplyRoomBounds(Room_Surface)`, tween `Darkness` →
  `DarknessSurface`, then `PlayCutscene(ForemanLines)` and `AddEnergy(-FinePenalty)`.
- Foreman cutscene end → stage `Fight`: `GuardSpawner.StartWave()`.
- `GuardSpawner.WaveCleared` → stage `Ending`: `PlayCutscene(EndLines)`.
- Ending cutscene end → stage `Done`: `GoToLevel(NextLevel)`.
- `Respawned` → if stage is `Farewell` or later, re-issue `Dan.HoldAt(...)`; otherwise
  `Dan.Resume()`. (Guard against `LevelBase`'s own `WarpBehind` moving a held spot.)
- `_ExitTree` disconnects **every** subscription above, and kills every tween.
- Prompt priority is unchanged from today's implementation (usable interactable → stage hint →
  active tutorial hint → unusable prop text; nothing during a cutscene).

Per-frame work: none beyond the existing debug-label refresh, which is already event-driven plus a
jump-height read in `_Process`.

### E. Dan's cue table — *where* each line fires (text lives in [`script-en.md`](script-en.md))

The plan owns the **cue ids**; `script-en.md` must supply one English line (or a short cutscene
array) per id. If the script agent used different ids, `/coder` maps them and records the mapping in
this plan under *Review findings*.

| # | Cue id | Kind | Trigger (exact) |
|---|---|---|---|
| 1 | `CUT_INTRO` | cutscene | `_Ready` |
| 2 | `DAN_S0_SHIFT` | bubble | `Checkpoint_Face` armed |
| 3 | `DAN_S0_MORE` | bubble | `MovePrompt.Completed` — «if we work, they give more» |
| 4 | `CUT_BLAST` | cutscene | `CaveIn_Blast.Triggered` |
| 5 | `DAN_FOUND` | bubble | `Checkpoint_Blast` armed (Dan `Resume()`) |
| 6 | `CUT_DAN_FOUND` | cutscene | same, after the bubble |
| 7 | `DAN_LAMP` | bubble | `FlashlightPrompt.Completed` — «that's your whole clock now» |
| 8 | `DAN_TIMBER` | bubble | `DebrisPile_Timber.Resisted` (a light attack bounced) |
| 9 | `DAN_RULE` | bubble | **first** `Circuit.RequestRefused` (the pump vs. the work lights) |
| 10 | `DAN_DARK` | bubble | `Lights_Drift.PowerChanged(false)` |
| 11 | `DAN_PUMP` | bubble | `Pump.PowerChanged(true)` |
| 12 | `DAN_GAS` | bubble | any `GasZone.WarningStarted` |
| 13 | `DAN_GAS_BOOM` | bubble | any `GasZone.Ignited` |
| 14 | `DAN_REFUSED` | bubble | every later `Circuit.RequestRefused` |
| 15 | `DAN_EXTRACTOR` | bubble | `Extractor.PowerChanged(true)` |
| 16 | `DAN_CREW_DUCK` | bubble | `Checkpoint_Crew` armed |
| 17 | `DAN_CREW_SEEN` | bubble | `WatchZone_Crew.Spotted` |
| 18 | `DAN_HANDOVER` | bubble | `CaveIn_Upper.Collapsed` |
| 19 | `DAN_SIGHT` | bubble | `Checkpoint_Sight` armed — «there's the cage» |
| 20 | `DAN_FLOODLIGHT` | bubble | `Hoist` refused by the floodlight (`RequestRefused` with `blocking == Floodlight`) |
| 21 | `CUT_FAREWELL` | cutscene | `CaveIn_Final.Collapsed` — the powerbank, «дійдеш» |
| 22 | `CUT_ARRIVAL` | cutscene | `Hoist.Departed` |
| 23 | `CUT_FOREMAN` | cutscene | arrival cutscene finished — the fine, the missing report |
| 24 | `CUT_END` | cutscene | `WaveCleared` — dead TEC behind, the lit centre ahead |

Dan is **silent** between cue 16 and cue 18 (§3: «Дан тут пригинається і замовкає сам») — `/coder`
calls `Companion.SetBubbleSuppressed(true)` on `Checkpoint_Crew` and `false` on
`CaveIn_Upper.Collapsed`; cue 17 is the single authorised exception and is issued before the
suppression, or via a direct label write, whichever the class allows.

---

## File-level change list

### `scenes/`

| File | Action | Intent |
|---|---|---|
| `scenes/levels/Level00_Prologue.tscn` | **rebuilt** | Six rooms, seven segments, the placement table above; keeps the T-07i-c group structure and every surviving prop |
| `scenes/props/WatchZone.tscn` | **new** | The crew's detection zone prefab (`Area2D` + shape 700×320 + `PH_Alert`) |
| `scenes/props/PoweredMachine.tscn` | untouched | `StartsPowered` defaults to `false`; no stored value changes |
| `scenes/levels/TestMine.tscn`, `TestRoom.tscn`, `Level01_District.tscn` | untouched | Must stay byte-identical; `/verify` checks with `git diff --stat` |

### `scripts/`

| File | Action | Intent |
|---|---|---|
| `scripts/levels/Level00_Prologue.cs` | **rewritten** | New `Stage`, checkpoint-driven beats, the circuit hand-over, Dan's cue table, the fine, the hand-over to level 1 |
| `scripts/props/WatchZone.cs` | **new** | `partial class WatchZone : Area2D`, the contract in §B |
| `scripts/props/PoweredMachine.cs` | **edited, additive** | `[Export] StartsPowered`, `public void ForcePower()` |
| `scripts/props/PowerPanel.cs` | **edited, additive** | `protected void MarkActivated()` extracted from `Complete()` so `ForcePower` reuses one code path |
| everything else under `scripts/` | untouched | No behaviour change to any other T-07s-a class |

### `tests/smoke/`

| File | Action | Intent |
|---|---|---|
| `tests/smoke/level_prologue.gd` | **rewritten** | Segments 0–2 + the first refusal + the gate-bypass proofs of that half |
| `tests/smoke/level_prologue_escape.gd` | **new** | Segments 3–7 (gas, crew, upper, cage, farewell, surface) — the split exists because one script cannot fit the level under the runner's 60 s timeout |
| `tests/smoke/level_dressing.gd` | **edited** | New room / wall / floor / Fx node names, `LEVEL_WIDTH = 13440`, the new stage constant, `PanelSparks` moved to `Fx_Face` |
| `tests/smoke/props_circuit.gd` | **edited** | New §: `StartsPowered` takes the bus in `_Ready`; `ForcePower()` on a loaded bus refuses and warns; `ForcePower()` marks the panel activated and `CanPowerDown` still switches it off |
| `tests/smoke/props_watchzone.gd` | **new** | The `WatchZone` contract in isolation (band coverage, lit vs. dark, the window, `Caught` → `Kill()`) |
| every other `tests/smoke/*.gd` | untouched | Must stay green |

### `docs/`

| File | Action |
|---|---|
| `docs/TASKS.md` | T-07s-b → `in_progress` → `done` + «Зроблено / Не зроблено / Рев'ю / Плейтест» + the four backlog entries T-B17…T-B20 |
| `docs/plans/t07s-b-prologue-rebuild/t07s-b-prologue-rebuild-plan.md` | this file; `## Review findings` filled by `/reviewer` |
| `docs/plans/t07s-b-prologue-rebuild/script-en.md` | **written by the parallel script agent**; this plan only references it |
| `docs/GAME_DESIGN.md` | **not edited** (the stale lines in §3 are recorded above; changing the design doc is the author's call) |

### `project.godot` / `.csproj` / `.sln`

**No change.** No new autoload, no new InputMap action (the level uses `move_*`, `jump`, `attack`,
`heavy_attack`, `interact`, `flashlight` — all present), no new physics layer (`WatchZone` reuses
mask 2 = Player; `LitZone` reuses layer 7 = LightDark), no new package. The `project-settings` skill
is therefore **not** triggered. If `/coder` finds it needs any of these, that is a stop-and-ask, not
a silent edit — `CLAUDE.md` requires such a change to be described in the commit body.

---

## Acceptance criteria

Given → action → expected observable result. `/reviewer` renders a verdict against these.

**Structure and flow**

1. Given `scenes/Main.tscn` run as the main scene, → wait for the intro cutscene and tap `interact`
   through it → `Level00_Prologue.CurrentStage == Stage.Face`, the hero is free, `Dan`'s
   `CurrentStateName == "Follow"`, `GameState.CurrentScenePath` ends with `Level00_Prologue.tscn`.
2. Given the run continues to the end → the `StageChanged` sequence observed is exactly
   `Face, Blast, Flood, Gas, Crew, Upper, Cage, Farewell, Surface, Fight, Ending, Done`, and after
   `Done` the tree's current scene is `Level01_District`.
3. Given the hero crosses each room boundary → `Camera2D.LimitLeft/Right` equal that room's
   `Rect` within 1 px, and `RoomBounds.Fx` gating leaves exactly one `Fx_*` group processing.
4. Given the hero stands anywhere in any room → `Player.FloorTop == 300` and
   `Player.FloorBottom == 600` (uniform band; no room changes it).

**Gates cannot be walked around in depth** (the T-07s-a lesson)

5. For **every** gate — `DebrisPile_Timber`, `Flood`, `DebrisPile_Ramp`, `DebrisPile_BlastSeal`,
   `DebrisPile_UpperSeal`, `DebrisPile_Final` — given the pile is not cleared and the hero walks
   right from 200 px before it **at `FloorTop + 10` and again at `FloorBottom − 10`**, → in both
   runs he stops at least 16 px short of the pile's X; after the pile is cleared the identical walk
   passes at least 64 px beyond it.
6. Given `GasZone_Rehearsal`, `_Pocket_A`, `_Pocket_B` and `WatchZone_Crew`, → each one's
   `CollisionShape2D` `RectangleShape2D.Size.Y >= 320` and the shape's world extent covers
   `FloorTop … FloorBottom`; each emits its warning with the trigger entered at `FloorTop + 20` and
   again at `FloorBottom − 20`.
7. Given `_Ready` on the whole level → the Godot log contains **no** `WARNING:` from
   `GasZone.WarnUnlessTheBandIsCovered` or from the equivalent check in `WatchZone`.

**The circuit**

8. Given the hero has just entered `Room_Flood` → `Lights_Drift.IsPowered == true` and
   `Circuit.Used == 1` **without any player input** (`StartsPowered`).
9. Given `Lights_Drift` is running and the hero completes the pump's repair sequence →
   `Circuit.RequestRefused` fires with `blocking == Lights_Drift`, `Pump.IsPowered == false`,
   `Pump.CanInteract == true` (retry allowed), and the HUD prompt contains
   `"Not enough power: Work lights is running"`.
10. Given the work lights are switched off and the pump is switched on → `Flood.IsCleared == true`,
    `Circuit.Used == 1`, and switching the pump off afterwards leaves `Flood.IsCleared == true`
    (permanence: nothing is ever re-solved).
11. Given the pump runs and the hero uses the extractor → refused with `blocking == Pump`; after the
    pump is switched off, the extractor powers and `GasZone_Pocket_A.IsCleared` and `_B.IsCleared`
    are both `true`.
12. Given the hero crosses `CaveIn_Upper` with **any** machine powered → within `Delay + 0.2 s`:
    `Pump.IsPowered == false`, `Extractor.IsPowered == false`, `Floodlight.IsPowered == true`,
    `Circuit.Used == 1`.
13. Given `Floodlight` runs and the hero uses the hoist → refused with `blocking == Floodlight`;
    given the floodlight is switched off first → the hoist powers, and entering `BoardingArea`
    emits `Departed` exactly once.
14. **Reachability invariant:** at every moment, for every machine `m` with `m.IsPowered == true`,
    no un-cleared, non-clearable `DebrisPile` lies between `Player.GlobalPosition.X` and
    `m.GlobalPosition.X`. Checked by the tests at the two seals (§ *Test strategy*).

**The gas rule is fair and has two solutions**

15. Given the hero enters `GasZone_Rehearsal` with the lamp **on** → `WarningStarted` fires,
    `WarningSeconds == 1.5`, and turning the lamp off inside the window → `WarningStopped`,
    `Player.IsKnockedOut == false`.
16. Given the hero enters `GasZone_Pocket_A` with the lamp on and does nothing →
    `Ignited` fires after `0.8 s ± 0.15`, `Player.IsKnockedOut == true`, and within
    `RespawnDelay + 0.3 s` the hero is at `Checkpoint_Gas2.RespawnPosition`, the level instance id is
    unchanged, `Player.Flashlight.IsOn == false`, and every `IClearable` cleared before the death is
    still cleared.
17. **Two ways:** given the pockets are **not** cleared and the lamp is off, a walk from x 5900 to
    x 6400 at band centre completes with `Ignited` never emitted. Given instead the extractor was
    powered, the same walk completes with the lamp **on** and `Ignited` never emitted.

**The crew**

18. Given the hero walks x 6650 → 7450 with the lamp off, along the dark lane
    (`y = 360` until x 7000, then `y = 540`) → `WatchZone_Crew.Spotted` never fires and
    `Player.IsKnockedOut == false`.
19. Given the hero stands inside `WatchZone_Crew` with the lamp off but **inside `LitZone_Crew1`**
    (x 6850, y 520) → `Player.IsLit == true` and `Spotted` fires; leaving the pool within 0.6 s →
    `LostSight`, no KO.
20. Given the hero stands inside `WatchZone_Crew` with the lamp **on** and does nothing → `Caught`
    fires, the hero respawns at `Checkpoint_Crew`, the level is not reloaded.

**Dan**

21. `Companion.CollisionLayer == 0` and the node has no `Hurtbox` ⇒ Dan cannot be hit, cannot block
    the hero, cannot trigger a `Checkpoint`, `CaveIn`, `GasZone` or `WatchZone`.
22. Given the hero is teleported to the far end of any segment → within 3 s
    `Dan.GlobalPosition.DistanceTo(Player.GlobalPosition) <= Companion.WarpDistance` and
    `Dan.CurrentStateName == "Follow"` (or `"Wait"` only during a scripted hold).
23. **No gate waits for Dan:** given Dan is teleported 4 000 px away (`WarpTo`) immediately before
    each of the three refusals and before the final collapse → every one of them still completes.
24. Given `CaveIn_Final.Collapsed` → `Dan.IsWaiting == true`, `Dan.GlobalPosition.X <
    DebrisPile_Final.GlobalPosition.X`, and 5 s later he is **still** on that side (no failsafe warp
    through the rubble).
25. Dan never reaches a knocked-out state: there is no code path in the level that calls anything
    lethal on `Companion`, and `Companion` exposes none.

**No dead ends, no soft-locks**

26. Given any segment and any state of the circuit reachable in that segment, there is always at
    least one action that advances the run: the tests walk the full level twice — once taking every
    optional machine, once taking none (dark route through the gas, no extractor) — and both reach
    `Stage.Done`.
27. Given `GameState.Energy == 0` at the start of any segment → the run still reaches `Stage.Done`
    (energy is never a gate).
28. Given the hero dies at any point after the first checkpoint → `LevelBase.RestartLevel()` is
    never called (no scene reload) and the run continues from the armed checkpoint.

**Text and tone**

29. Every string the player can see in the prologue — cutscene lines, tutorial prompts, panel
    prompts, `DisplayName`s, Dan's bubbles, HUD prompts — is English, and its source is
    `script-en.md` (or an English `[Export]` default). `grep -P '[\x{0400}-\x{04FF}]'` over
    `scenes/levels/Level00_Prologue.tscn` returns nothing.
30. Nothing in the prologue references the alarm, the old fan panel or the guards-on-the-horizon
    beat; the only enemy in the level is the single guard of the surface fight.

**Hygiene**

31. `dotnet build` → 0 warnings, 0 errors. `godot --headless --path . --quit` and
    `godot --headless --path . res://scenes/levels/Level00_Prologue.tscn --quit` → no `ERROR:` and no
    `WARNING:`. `tools/smoke.ps1` → all scripts pass, none times out.
32. `scenes/levels/TestMine.tscn`, `TestRoom.tscn`, `Level01_District.tscn`, `project.godot`,
    `.csproj`, `.sln` and `assets/` are byte-identical to `main`.

---

## Test strategy

Only automated level available: **smoke scripts** under `tests/smoke/`, `extends SceneTree`, checks
from `_process`, printing `SMOKE <name> PASS|FAIL: <reason>` and `quit(0|1)`. GdUnit4 is still not
approved and is not planned on.

This is a **new-feature / behaviour-change** task on a scene that already has two smoke scripts
(`level_prologue.gd`, `level_dressing.gd`). Both cover behaviour that this task deletes, so the
order is: **rewrite the prologue scripts together with the scene in the same commit**, and keep every
other script green untouched.

### The 60 s wall — why the prologue test is split in two

`tools/smoke.ps1` kills a script at 60 s; today's `level_prologue.gd` already budgets
`MAX_FRAMES = 8000 ≈ 55 s` for a 5 760 px level. The rebuilt level is 13 440 px with three more
cutscenes. One script cannot cover it. Split:

| Script | Covers | Budget |
|---|---|---|
| `tests/smoke/level_prologue.gd` | Boot through `Main.tscn`; intro cutscene; segment 0 tutorials; the blast (`Triggered` → cutscene → darkness colour → `Collapsed` → seal solid → hero alive); finding Dan; flashlight + outlet; the timber pile gate; `Checkpoint_Flood`; `StartsPowered`; the **first refusal**; the pump; the flood gate. Ends by asserting `Stage.Gas` was reached. | `MAX_FRAMES ≤ 6000` |
| `tests/smoke/level_prologue_escape.gd` | Instantiates the level **directly** (not through `Main`), teleports the hero segment by segment: gas (rehearsal window, pocket ignition + soft respawn, both routes), the crew, the upper collapse + hand-over, the cage (third refusal, final collapse, Dan held), boarding, the surface (fine, wave, ending, `GoToLevel`). | `MAX_FRAMES ≤ 6000` |

Both use the house helpers already in `level_mine.gd`/`level_prologue.gd`: `_check`, `_step`,
`_settle`, `_place`, `_walk_right`, `_tap`, `_wait_until`, `_watch_ms`, `_real_wait`,
`_skip_cutscene`, `_release_all`. **Teleport (`_place`) everywhere except where a walk is the
assertion** — that is what buys the frames.

### What the prologue scripts must prove (mapping to acceptance criteria)

1. **Stage order and hand-over** — AC 1, 2, 3, 4.
2. **Gate bypass is impossible** — AC 5, the `level_mine.gd` §2b pattern, applied to **each of the
   six piles**: assert `BlockerShape.shape.size.y >= 320` and the blocker's world extent covers the
   band, then `_walk_right` at `FloorTop + 10` and at `FloorBottom − 10` and check both stop short;
   then clear the pile (heavy hits, or the machine, or `Clear()` for a seal) and repeat the far-edge
   walk to prove the test itself was not what stopped him. **This is the single most important block
   in the whole suite** — it is the failure T-07s-a's review had to fix, and placement can
   re-introduce it even though the classes are now correct.
3. **Hazard band coverage** — AC 6, 7: for each `GasZone` and the `WatchZone`, arm it at both band
   edges (`props_gaszone.gd` §9 pattern) and assert `_Ready` produced no warning.
4. **The circuit** — AC 8–13: connect `Circuit.RequestRefused`, `MachinePowered`, `MachineReleased`,
   `LoadChanged`; drive the panels with `machine.Begin(player)` (the `level_mine.gd` idiom) and
   assert the blocking machine's identity and the prompt text.
5. **Reachability invariant** — AC 14: at the two seals, after `Collapsed`, assert
   `Pump.IsPowered == false and Extractor.IsPowered == false and Floodlight.IsPowered == true` and
   that `Circuit.FreeCapacity == 0` — i.e. the bus is never stranded behind rubble.
6. **Two routes through the gas** — AC 17: the dark walk, then a second pass on a fresh level
   instance with the extractor powered. Two level instances in one script are cheap when created
   directly (no `Main`).
7. **Crew** — AC 18, 19, 20, plus `props_watchzone.gd` for the class in isolation.
8. **Dan** — AC 21–25: assert `collision_layer == 0`; teleport him away before each gate
   (AC 23 — the "nothing waits for Dan" proof, and the cheapest possible insurance against the worst
   failure mode of an escort level); after the final collapse assert he is on the far side **and
   still there 5 s later** (this catches the `CompanionFollow` stuck-warp regression).
9. **No soft-lock** — AC 26, 27: the "minimal route" pass (no extractor, no outlets,
   `GameState.Energy = 0` forced at each segment entry) must still reach `Stage.Done`.
10. **Language** — AC 29: a check over the level's cutscene arrays and `DisplayName`s that no
    character falls in the Cyrillic range.

### Existing scripts that must stay green

`core_gamestate`, `core_settings`, `core_statemachine`, `player_movement`, `player_flashlight`,
`combat_dummy`, `enemy_guard`, `enemy_wave`, `actors_rig`, `actors_companion`, `props_interact`,
`props_gaszone`, `ui_hud`, `ui_menu`, `ui_pause`, `level_mine` — **untouched**.
`props_circuit` gains a section (`StartsPowered` / `ForcePower`); `level_dressing` is updated for the
renames and the new width and **keeps every one of its existing assertions** (z-table, parallax
ordering, `PH_NearBand` coverage, emitter/light census, room gating, `ImpactFx`, shake, lookahead,
`Player.Landed`) — the dressing contract does not change, only the node names it addresses.

### Only verifiable by hand → Playtest

Whether the level *reads*: whether the darkness is navigable, whether the refusal feels like a rule
and not a bug, whether the 0.8 s window feels fair at the controller, whether the crew's dark lanes
are visible enough to aim for, whether Dan's lines land, whether the farewell works emotionally,
whether the three walk-backs drag, and whether "we are higher now" is legible in segment 4.

---

## Playtest (manual QA)

Copy verbatim into the TASKS.md done-note. Run `scenes/Main.tscn` with **F5** unless a step says
otherwise.

1. **Main menu → New Game.** Expected: the intro cutscene, English text, `E` advances it; the HUD
   reads `ENERGY 100`.
2. **Segment 0 — the face.** Expected: the drift is **lit** (station lighting, not the mine's
   blue-black); Dan walks behind you and talks; the move and jump prompts appear; the crate blocks a
   walk and yields to a jump; the conveyor belt is running.
3. **The blast.** Walk past the conveyor. Expected: a heavy shake, the cutscene, the lights die and
   the screen goes to mine-dark, and behind you the drift is sealed by fresh rubble that no number
   of `K` presses opens.
4. **Finding Dan.** Walk right. Expected: Dan is on the floor, gets up, speaks, and follows you from
   here on. The flashlight prompt appears; `F` lights the lamp and the energy bar starts falling.
5. **The outlet** (`E`). Expected: `E: Charge` → energy +25 → `Drained`, then `Drained (Ns)`.
6. **The timber pile.** Expected: three `J` (light) presses do nothing and Dan comments; two `K`
   (heavy) presses clear it. Before clearing, try to walk around it along the **far wall** and along
   the **near edge of the floor** — neither gets through. Step out of the marked strip and `K`
   misses.
7. **Segment 2 — the flooded drift.** Expected: the work lights are already on; the water blocks the
   drift at every depth. Use the pump: the four-button repair runs, then the panel **refuses** —
   *«Not enough power: Work lights is running»* — and flashes red but stays usable. Dan says the
   rule.
8. **Switch the work lights off** (`E` on their panel). Expected: the drift goes dark, then the pump
   starts with one press and the water drains **for good** — switching the pump off later does not
   bring it back.
9. **Segment 3 — rehearsal gas.** Expected: the air ahead is visibly tinted before you enter it.
   With the lamp off it is harmless. Turn the lamp **on** inside it: the haze flares, Dan shouts, and
   you have ~1.5 s to press `F` again — do it, and you live.
10. **The extractor.** Expected: refused — *«Not enough power: Pump is running»*. Walk back one
    screen, switch the pump off, return, switch the extractor on; the pocket ahead clears for good.
11. **Or skip it:** on a fresh run, cross the 360 px pocket with the lamp **off** instead. Expected:
    you get through in the dark, unharmed, without ever touching the extractor.
12. **Death is cheap.** Deliberately stand in the real pocket with the lamp on. Expected: the blast,
    then a respawn at the checkpoint a few steps back — **the level does not reload**, the water is
    still drained, the lamp comes back off.
13. **Segment 3 — the sealing crew.** Expected: two workers under two lamp pools, and two dark lanes
    (far side first, then near side). With the lamp off, weave through — nobody reacts. Step into a
    lamp pool with the lamp still off: you are lit anyway, they spot you, and you have ~0.6 s to get
    out. Walk in with the lamp on and stand still: they take you, and you wake at the checkpoint.
14. **Segment 4 — up.** Expected: a big fall of rock; two `K` presses open it into a ramp; behind you
    the roof comes down and seals the gas drift; Dan says the power just moved. Further right the
    cage's floodlight is visible from a long way off.
15. **Segment 5 — the cage.** Expected: the cage and the floodlight are on the **same screen**. Use
    the cage: refused — *«Not enough power: Floodlight is running»*. Switch the floodlight off: the
    whole screen goes dark.
16. **Segment 6 — Dan.** Walk back towards the cage in the dark. Expected: the roof comes down
    **between you and Dan**; he stays on the far side and does not teleport through; the farewell
    cutscene plays (the powerbank, «you'll make it»). Then start the cage and step in.
17. **Segment 7 — the surface.** Expected: daylight (overcast), the foreman's cutscene, the fine —
    the HUD energy drops by 20 — then one guard comes for the powerbank. Beat him. The closing
    cutscene plays: the dead district TEC behind, the lit centre on the horizon. The game moves to
    level 1.
18. **Pause anywhere** (`Esc`), especially during a gas countdown and between a death and the
    respawn. Expected: everything waits; `Resume` continues; `Quit to Main Menu` works.
19. **Dan stress test.** Corner him, run away half a screen, cross a seal. Expected: he reappears
    behind you; he never blocks you (walk through him); he is never hurt; nothing in the level ever
    waits for him.
20. **Regression.** `scenes/levels/TestMine.tscn` (**F6**) and `scenes/levels/TestRoom.tscn`
    (**F6**) behave exactly as before this task.

---

## Review focus

For `/reviewer`, in order:

1. **`belt-scroll depth`** — every gate and hazard spans `FloorTop…FloorBottom`; every hittable pile
   sits at the band centre with its `PH_HitStrip`; nothing in the dressing narrows a lane.
2. **`scene/tscn integrity`** — six rooms wired to six `Fx` groups, valid `ext_resource` paths and
   `uid`s, `Props` y-sorted, node paths in `node_paths=PackedStringArray(...)` all resolving, the
   renamed nodes matching `level_dressing.gd`.
3. **`signals/decoupling`** — every subscription in `Level00_Prologue._Ready` has its mirror in
   `_ExitTree`; no `GetNode("../..")`; no polling of state that has a signal.
4. **`GameState usage`** — only `Energy` (the fine) and `CurrentScenePath` (the hand-over); no new
   global state.

Secondary, but specifically called out for this task: **`exports/tunables`** (no magic numbers in the
new level script — the darkness colours, the fade, the fine and the Dan-fallen position are all
`[Export]`) and **`null-safety`** (the level holds a dozen node references; `Companion` and `Crew`
are nullable on purpose and every use must be guarded).

---

## Performance & frame budget

- **Per-frame work in the level script: none new.** All flow is signal-driven; `_Process` keeps only
  today's debug-label refresh (a jump-height read plus a string rebuild **only when the value
  changed**).
- **`WatchZone`** polls one `bool` (`Player.IsLit`) per physics frame, and **only while the hero is
  inside it** — `SetPhysicsProcess(false)` on `BodyExited` and on `Disarm`. Worst case one zone, one
  poll. No allocation.
- **`GasZone`** is unchanged: `_PhysicsProcess` runs only while a warning counts (~48 frames per
  contact).
- **Emitters.** Six `Fx_*` groups, one active at a time via `RoomBounds.Fx` gating (T-07i-c's
  contract, already asserted by `level_dressing.gd`). Per-room budget: ≤ 3 emitters, `amount ≤ 32`,
  bounded `visibility_rect`. `PanelSparks` stays in the `fx_manual` group so the gating never
  touches it.
- **Lights.** Census after this task, all with `shadow_enabled = false`: per room at most 1 warm
  landmark + 1 machine `RunLight` + 3 `RunFx` lamps (`Lights_Drift` only) + 2 crew lamps + the
  hero's flashlight + ≤ 3 transient `ImpactFx` flashes + 1 `GasZone` warning flare + 1 `WatchZone`
  alert. Peak in `Room_Flood` and `Room_Gas` ≈ **11**, under `level_dressing.gd`'s `MAX_LIGHTS = 12`.
  The `RunFx` lamps are `PointLight2D`s whose parent `Node2D` is toggled `Visible` — invisible
  `CanvasItem`s cost nothing, which is exactly why the lights machine drives **lights** and never a
  `LitZone` (an `Area2D` keeps colliding while invisible — a trap `/coder` must not fall into).
- **y-sort.** Props stay grouped per room under `Props` (y-sorted), not one node per decal; the
  number of nodes directly under the y-sorted root does not grow with level width.
- **Physics vs. render.** Everything that decides anything — gate collisions, hazard triggers, depth
  checks, the `WatchZone` poll — is in `_PhysicsProcess`; the darkness tween, the bubbles and the
  debug label are `_Process`/`Tween`.
- **Scene size.** ~2 600–3 000 lines of `.tscn` load once at level start; no runtime instancing
  beyond `ImpactFx` and the single surface guard.

---

## Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | **A gate is placed so it can be walked around** (the exact failure T-07s-a's review had to fix). A pile whose root Y is not 450, or a room whose band differs, re-opens it. | Uniform band 300…600; AC 5/6; the smoke block walks both band edges into **every** gate. |
| R2 | **Soft-lock via the circuit** — a seal falls between the player and a running machine. | The reachability invariant (*Options* 2C), AC 14, the hand-over on `CaveIn_Upper.Collapsed`, and the "minimal route" test pass. |
| R3 | **Dan teleports through the final rubble** and ruins the farewell. | `HoldAt` issued in the `Collapsed` handler; `CompanionWait` aims its failsafes at the held spot; AC 24 asserts he is still there 5 s later; the `Respawned` handler re-issues the hold. |
| R4 | **`level_dressing.gd` breaks** on the renames and silently gets weakened instead of updated. | The change list names it; `/reviewer` must diff it assertion-by-assertion, not just check it is green. |
| R5 | **The smoke scripts blow the 60 s runner timeout.** | Split in two, `MAX_FRAMES ≤ 6000` each, teleports instead of walks except where the walk *is* the assertion. |
| R6 | **`StartsPowered`/`ForcePower` changes a T-07s-a class** and regresses `TestMine`. | Defaults `false`; `props_circuit.gd` and `level_mine.gd` must stay green **unchanged**; `TestMine.tscn` byte-identical (AC 32). |
| R7 | **Scope explosion** — 13 440 px of new dressing. | The must/nice-to-have split and the "dressing tier" rule; the four new rooms ship structural only. |
| R8 | **Text drifts from `script-en.md`** (the parallel agent renames cues). | The cue-id table is normative; `/coder` records any mapping in `## Review findings`. |
| R9 | **The intro is un-skippable on the twentieth playtest run.** | `CutsceneSkippable = true` keeps `E` advancing; a proper skip-all is backlog T-B19. |
| R10 | **`Door.cs` is left with no user** and reads as dead code. | Recorded deliberately here and as backlog T-B18 — it stays as the building block for T-08. |

---

## Design risks

Where this prologue can be boring, unfair or broken. Direct assessment, including the two places
where I think §3 as written does not work.

### 1. Three refusals in fifteen minutes is one refusal too many — and the middle one is the weak one

The level teaches «switch something off to switch something on» three times: work lights → pump,
pump → extractor, floodlight → hoist. The first is the lesson, the third is the payoff (it is the
moment the design is *about*: the light you need versus the way out, with your brother next to you).
**The middle one, pump → extractor, is the one that will feel like chores.** It costs a 1 720 px
round trip, it repeats a verb the player learned four minutes earlier, and its reward — clearing a
gas pocket — is *optional*, because the honest solution to that pocket is to walk it in the dark.

**Verdict: keep it, but make the dark route the obvious one.** Place the pocket so that the dark
walk is short (360 px ≈ 1.6 s), keep the extractor visible but off the critical path, and let the
extractor be the *cautious* player's option rather than the expected one. If the first playtest reads
long, **cut the extractor refusal first**: give the extractor `PowerCost = 1` on a circuit that the
level has already freed at the upper collapse — or simply set `Capacity = 2` for `Room_Gas` only,
which is one inspector field. Do **not** cut the first or the third refusal; the level has no lesson
without them.

### 2. «There is no way back» is not quite true, and the plan should stop pretending otherwise

The author cut the long back-run, correctly. But two short back-runs survive by construction: 760 px
to the work-lights panel and 1 720 px to the pump. They are backtracking. The defence is that they
are *short*, *signposted by the refusal text*, and *never re-solve anything* — which is exactly the
rule T-07s-a's Design risk §1 laid down. Still, if a playtester says «the level made me walk back
twice», that is a true statement and not a bug report to dismiss. The escape hatch is `Capacity`, and
it is one number.

### 3. The «upper horizon» segment is the weakest of the seven and is nearly content-free

In a belt-scroll with no vertical axis, «we climbed to the upper horizon» is a backdrop swap. After
cutting the conveyor platform, segment 4 contains: one debris pile (a verb from segment 1), a
sight-line to the cage, and one line of dialogue. **That is not a segment, it is a corridor.**

**Direct recommendation:** either (a) accept it as a deliberate breather between the crew and the
farewell — which is defensible, the level needs one quiet beat before the death — and keep it short
(1 920 px, one pile, one line), or (b) give it the one thing it can carry for free: **make the ramp
pile the level's only two-stage gate** — a pile that also needs the floodlight's light to be found
in the dark, so the player arrives at the cage screen already looking at the floodlight. I recommend
**(a)**, with the room kept deliberately short, because (b) adds a dependency between two segments
for a small gain. What I would **not** do is pad it with enemies: the prologue's one fight belongs on
the surface.

### 4. The sealing crew is the riskiest content in the task

It is the only new mechanic, the only unbeatable enemy, and the only place where the punishment for
a mistake is a knock-out by something you cannot fight back against. Three specific ways it goes
wrong: (i) the dark lanes are invisible in a dark room, so the player wanders into a pool and feels
cheated; (ii) `Player.IsLit` is true for a reason the player cannot see, and the detection reads as
random; (iii) the 0.6 s window is too short to react to something you did not know you had entered.

**Mitigations that are non-negotiable if this ships:** the lamp pools must be *visibly* lit floor
(a `PH_` floor decal at z −20 under each `LitZone`, matching its shape exactly — the pool the player
sees and the pool the physics uses must be the same rectangle); the crew must be visible from outside
the zone (their own lamps light them); `Spotted` must have an audible/visible tell (the alert light
plus Dan's line); and the checkpoint sits immediately before the zone.

**And if any of that is shaky at review time, take the fallback** (*Options* 6B): a `GasZone`-shaped
searchlight that only cares about the head lamp. It teaches less, but «бригаду можна обійти» still
holds and the segment cannot be unfair. I would rather ship the simple version than a clever one that
feels random.

### 5. The player can arrive at the farewell with no emotional investment in Dan

This is the risk that decides whether the prologue works at all, and **no amount of level design
fixes it — it is entirely `script-en.md` plus 24 correctly-placed cues.** Dan cannot be hurt, cannot
block, cannot be lost. Mechanically he is furniture. The only thing that makes him a person is that
he reacts to *the player's* decisions — every machine, every refusal, every gas warning — which is
why the cue table hangs off circuit and hazard signals rather than off cutscenes. If the fix pass has
to cut something from the cue table, cut cues 3, 8 and 14 (flavour) and keep 9, 10, 16, 18, 20
(reactions to decisions).

Second-order: Dan being silent through the crew segment (§3 asks for it) is right dramatically, but
it also means his longest stretch of screen time is mute. The line at cue 16 has to carry it.

### 6. Darkness plus 13 440 px with no map

The player will spend most of the level in the dark by choice, and the level is more than twice as
long as before. The countermeasures are all already in the plan — one warm light visible from each
room's entrance, machine run lights, checkpoint floor decals, and a refusal message that names where
to go — but they are a rule somebody has to actually follow while placing props. **If the first
playtest reports wandering, add lights before adding signage, and add signage before adding a map.**
A minimap in a fifteen-minute tutorial level would be an admission of defeat.

### 7. Death loops around the gas pocket

`MinRespawnEnergy = 30`, the lamp is forced off on revive, and the checkpoint sits before the pocket
— so a death costs about eight seconds. The residual risk is a player who does not connect «lamp» to
«explosion» and dies three times in a row. The rehearsal pocket at 1.5 s exists precisely for that,
and it is the one piece of the gas mitigation set I would refuse to cut. If playtest still shows
repeat deaths, the next lever is `Lethal = false` on the **first** pocket only (one inspector click,
turns the first contact into a flash burn).

### 8. What I think will actually break in the build (not in the design)

In rough order of likelihood: (1) a gate placed at the wrong Y, re-opening the depth bypass; (2) the
`Fx` room gating silently pointing two rooms at the same group after the renames; (3) the final
collapse firing on the player's *first* rightward pass because someone forgot that `CaveIn_Final`
ships with `monitoring = false`; (4) `level_dressing.gd` updated by weakening an assertion instead of
renaming a node; (5) the smoke split still timing out because the second script walks where it could
teleport.

---

## Resolved (agent decisions, may be overturned by the author)

1. **Room transitions are driven by `Checkpoint.Label`**, not by `Door`. `Door.cs` keeps existing but
   loses its only user (backlog T-B18).
2. **The stealth failure is a knock-out and the existing soft respawn**, not a bespoke push-back.
   One failure verb, one respawn pipeline, one test.
3. **Uniform floor band 300…600 in all six rooms** — height is told, not simulated.
4. **Five circuit nodes, three of which open a way**; the work lights and the floodlight are load,
   not puzzles. This is how §3's «чотири вузли» line is satisfied.
5. **Only one panel in the level keeps a repair `Sequence`** (the pump), as T-07s-a's plan proposed —
   §4's «3–4 кнопки» is a teaching beat, not a toll on every toggle.
6. **The old alarm beat is cut entirely** (no alarm in the new story); the guards move to the surface
   fight, the fan panel becomes the extractor, the panel sparks move to the blast.
7. **Four outlets**, `Uses = 3`, `Cooldown = 8` — comfort, never a gate.

## Open questions

1. **`WatchZone` as a new class** — approved here as *Options* 6C with 6B as a pre-authorised
   fallback. If the author wants **no** new mechanic in this task at all, say so before `/coder`
   runs and the crew ships as the `GasZone` searchlight.
2. **`StartsPowered` / `ForcePower` on `PoweredMachine`** — a T-07s-a class touched additively.
   Fallback without any code change: the level calls `Lights.Begin(Player)` in `_Ready` and there is
   no hand-over, which costs segment 5 its single switch-off. I do not recommend the fallback.
3. **The surface fight size** — one guard is planned («короткий, мотивований»). Two is also defensible
   and is one inspector field (`WaveSpawner.Count`). Author's call at playtest.
4. **Level 1's starting energy after the −20 fine** — still deliberately open (T-07s-a author
   decision 11); this task does not touch it.

---

## Author-side decisions (2026-09-11) — these override anything above

1. **The middle refusal (pump -> extractor) stays as planned**, despite being the weakest of the
   three. It is the only one that is *optional*, which is exactly what makes the third one land.
   But treat the architect's warning as a live risk: if the playtest reads as a trek, the fix is one
   inspector field (`Capacity = 2` in the gas room), not a redesign. Note it in the playtest sheet
   so the author is asked about it directly.
2. **Segment 4 stays a short breath** before the brother's death, exactly as recommended. Do NOT
   pad it with enemies or a second gate. A quiet corridor before that scene is the point.
3. **The sealing crew ships with every mitigation named in the plan** — floor decal matching the
   `LitZone` shape exactly, crew visible from outside the zone, alert light plus Dan's line, and a
   checkpoint right at the entrance. If review finds the segment wobbling, take the documented
   fallback (a floodlight shaped like a `GasZone`) rather than shipping an unfair stealth section.
4. **"No back-run" clarified in GAME_DESIGN §3**: short in-segment returns are the puzzle and stay;
   what is banned is re-walking solved ground before the final scene. The plan's two returns are
   within that.
5. **Texts come only from `script-en.md`.** Do not invent or "improve" lines while building. The
   gas shout stays `LAMP OFF!` — at `WarningSeconds = 0.8` a longer line physically cannot be read,
   and lengthening it turns an honest mechanic into a gotcha.
6. **Priorities:** ship all of must M1-M11 properly before touching any nice-to-have. A rough but
   correct seven-segment level beats a beautiful half.


## Review findings

### Cue mapping (recorded by `/coder`, 2026-09-11)

The plan owns the cue ids; `script-en.md` turned out to carry a slightly different set. Author-side
decision 5 ("texts come only from `script-en.md`, do not invent") settles every difference in favour
of the script. What was actually wired:

| Plan cue | Wired as | Note |
|---|---|---|
| `CUT_INTRO`, `CUT_BLAST`, `CUT_FAREWELL`, `CUT_FOREMAN`, `CUT_END` | `IntroLines`, `BlastLines`, `FarewellLines` (variant A), `ForemanLines`, `EndLines` (variant A) | as planned |
| `CUT_ARRIVAL` (`Hoist.Departed`) | **cut** | `script-en.md` row 35 puts the foreman's cutscene on `Hoist.Departed` itself; there is no arrival text to play |
| `CUT_DAN_FOUND` | **cut** | segment 1 in `script-en.md` has bubbles only, no cutscene |
| `DAN_S0_SHIFT` (cue 2) | **cut** | no such line; segment 0 has the two prompt lines plus one ambient line (`DanMotorLine`, 8 s after the intro) |
| `DAN_S0_MORE` (cue 3) | `DanMoveLine` / `DanJumpLine` on `TutorialPrompt.Shown` | the script binds these to `Shown`, not to `Completed` |
| `DAN_FOUND` (cue 5) | `DanFoundLine` + `DanUnhurtLine` 3 s later, on `Checkpoint_Blast` | `Companion.Arrived` is never waited on (plan rule) |
| `DAN_CREW_SEEN` (cue 17) | **cut** | `script-en.md` marks the whole stealth segment as deliberate silence; `WatchZone.Spotted` shows the alert lamp only |
| `DAN_HANDOVER` (cue 18) | `DanSealingLine` ("They're not digging. They're sealing it.") on `CaveIn_Upper.Collapsed` | the script's "stealth passed" line; the seal falls at that exact moment |
| `DAN_SIGHT` (cue 19) | `DanCageSeenLine` on `Checkpoint_Sight`, then `DanCagePowerLine`, `DanPayLine`, `DanDaysOffLine` on a timer chain, then `DanMumLine` on `Checkpoint_Cage` | the script's five segment-4 lines, in its order |
| `DAN_FLOODLIGHT` (cue 20) | `DanHoistRefusedLine` | as planned |
| — | `DanBoardLine` on `Hoist.PowerChanged(true)` | wired per the script, but unreachable in a normal run: the cage only starts after the farewell, and Dan is silent from then on (`script-en.md` row 34). Kept rather than moved, so the script stays the source of truth. |

Two placements diverge from the plan's table and are recorded here rather than silently changed:

1. **`Crate` sits at y 450, not y 470.** At 470 its 44×300 shape would leave a 20 px lane along the
   far wall; the crate is the jump lesson and must not be walkable around.
2. **`CaveIn_Final` sits at x 10 880, not 10 760**, and the level *places* Dan at
   `DanLastStandAt` (10 600) in the `Collapsed` handler instead of holding him where he happens to
   stand. With `DebrisPile_Final` at 10 700 there is no trigger position at which a follower 56 px
   behind the hero reliably ends up on the far side of the rubble; the farewell cutscene requires
   it, so the level makes it true. A `Checkpoint_Farewell` (trigger off in the scene, armed by the
   level at the collapse) keeps a death in segment 6 from respawning the hero behind the seal.
3. **The hand-over also calls `Lights.PowerDown()`**, not only the pump and the extractor: the work
   lights are behind the same seal, and a player who switched them back on would otherwise strand
   the bus.

*filled in by /reviewer*
