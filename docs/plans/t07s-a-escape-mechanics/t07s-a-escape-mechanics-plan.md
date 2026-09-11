# Plan — t07s-a-escape-mechanics (T-07s-a · Механіки escape-головоломки прологу)

Backlog: [`docs/TASKS.md` → T-07s-a](../../TASKS.md). Design doc:
[`docs/GAME_DESIGN.md` §1 «Два контури», §2, §3 «Рівень 0 — Пролог» (переписаний 2026-09-10), §4, §6](../../GAME_DESIGN.md).
Shared visual contract: [`../t07i-visual-kit/visual-brief.md`](../t07i-visual-kit/visual-brief.md).
Previous iteration of this level: [`../t07-prologue-mine/t07-prologue-mine-plan.md`](../t07-prologue-mine/t07-prologue-mine-plan.md),
[`../t07i-c-level-dressing/t07i-c-level-dressing-plan.md`](../t07i-c-level-dressing/t07i-c-level-dressing-plan.md).
Project state and traps: [`docs/sessions/2026-09-10-session-02.md`](../../sessions/2026-09-10-session-02.md),
[`docs/sessions/2026-09-09-session-01.md` §5](../../sessions/2026-09-09-session-01.md).

**Branch:** `task/t-07s-a-escape-mechanics` off `main` (`30627ac`). Baseline on the branch:
`dotnet build` 0 Warning / 0 Error, `tools/smoke.ps1` → 15 passed, 0 failed.

**Spec revision (author, 2026-09-10, mid-planning).** Дослівно: «давай простіше, без таких
технічних деталей. Стався вибух, головний герой і брат тікають з шахти, щоб не загинути під
завалами». This plan is written against the **simplified** brief, not against a resource-management
puzzle. What that changed, concretely:

- No resource simulation: no gas refill timers, no water level system, no "what comes back when you
  cut the power" bookkeeping. **A hazard either exists or it has been removed — once and for ever.**
- One machine class, not four. `Pump` and `Extractor` were the same pattern ("a machine removes an
  obstacle"), so they are **one** `PoweredMachine` with an `[Export]` list of what it removes. The
  hoist (the exit) stays its own thin class. **`ConveyorPlatform` is dropped** (see
  *Design-doc conformance*).
- `PowerCircuit` semantics confirmed by the author: **refuse and name the culprit.** No silent
  preemption. Не хватає потужності → панель не вмикається і каже, яка машина зайняла контур.
- **Дан тікає разом із героєм** through the whole level and dies only at the final collapse ⇒ a
  simple follower NPC (`Companion`) is now part of this task and is **more important than the
  machines**.
- The pressure comes from **the mine collapsing** (scripted cave-ins at trigger points that cut the
  way back and push forward), not from a global timer or resource management.
- The gas rule stays — it is the most valuable idea in the design — but simple and fair: **a warning
  before the death**, and a zone is either dangerous or already cleared.

---

## Goal

T-07s-a builds the **mechanical vocabulary** of the rewritten prologue (`GAME_DESIGN.md` §3) and a
test scene to exercise it, without touching the prologue's content (that is T-07s-b). Six pieces:

1. **`PowerCircuit`** — the horizon's emergency circuit holds one machine at a time; a request that
   does not fit is **refused with the name of the machine that is occupying it**. This is the whole
   theme of the game (§1 «Два контури») in the scale of one mine, and the level's main lesson.
2. **`PoweredMachine`** — one class: a `PowerPanel` that, while powered, removes the obstacles it
   points at (a gas pocket, a blockage). Removal is one-shot and permanent.
3. **`Hoist`** — the exit; a `PoweredMachine` that demands the whole circuit, so at least once the
   player has to switch something off on purpose.
4. **`GasZone`** — the inversion of the game's core resource: light kills here. Entering with the
   head lamp on starts a short, loud warning window; if the lamp is still on when it runs out, the
   pocket ignites and the hero dies at the last checkpoint.
5. **`DebrisPile` + `CaveIn` + `Checkpoint`** — the collapsing mine: piles of timber that
   `heavy_attack` clears (the level's heavy-attack tutorial, without hitting a person), scripted
   cave-ins that seal the way back and hurry the player, and checkpoints so a death costs seconds,
   not the level.
6. **`Companion`** — Дан: follows the hero, trails and catches up, waits where the script says,
   speaks short lines on events, and **never blocks the hero or gates progress**. He is what makes
   his death at the end mean anything (§3 «Кінець прологу»).

Plus `scenes/levels/TestMine.tscn`, a fixture where every one of these can be checked in isolation
from the prologue's content, and where T-07s-b can copy working wiring from.

---

## Scope

### In
- New: `scripts/core/PowerCircuit.cs`, `scripts/props/IClearable.cs`,
  `scripts/props/PoweredMachine.cs`, `scripts/props/Hoist.cs`, `scripts/props/GasZone.cs`,
  `scripts/props/DebrisPile.cs`, `scripts/levels/CaveIn.cs`, `scripts/levels/Checkpoint.cs`,
  `scripts/actors/Companion.cs` + 3 state scripts, `scripts/levels/TestMine.cs`.
- New scenes: `scenes/props/PoweredMachine.tscn`, `scenes/props/Hoist.tscn`,
  `scenes/props/DebrisPile.tscn`, `scenes/actors/Companion.tscn`, `scenes/levels/TestMine.tscn`.
- Edited, **additively only**: `scripts/props/PowerPanel.cs` (a panel can be switched off again),
  `scripts/player/Player.cs` (`Kill()` / `Revive()`), `scripts/levels/LevelBase.cs` (checkpoint
  respawn instead of a full level reload, companion hand-holding on room changes).
- New smoke: `tests/smoke/props_circuit.gd`, `tests/smoke/props_gaszone.gd`,
  `tests/smoke/level_mine.gd`, `tests/smoke/actors_companion.gd`.
- `docs/TASKS.md` — status, done-note, the backlog lines listed under **Out of scope**.

### Out
- **The prologue's content** — `Level00_Prologue.tscn`, its texts, cutscenes, stages, node names,
  the seven segments: all T-07s-b. This task does not open that scene at all. Consequence:
  `tests/smoke/level_prologue.gd` must stay **byte-identical and green** — that is the proof of no
  regression, the same trick T-07i-c used.
- Combat balance: damage, knockback, `DepthTolerance`, `HitStopFrames`, `PerceptionRange`,
  `DarkPerceptionFactor`, `Flashlight.DrainPerSecond`, `FinePenalty`. Not one number.
- Art and audio files. Everything visual here is procedural (`Polygon2D`, `Line2D`,
  `GradientTexture2D`, `GPUParticles2D`, `PointLight2D`) per the visual brief; `assets/` untouched.
- `ConveyorPlatform` as a carrying platform (see *Design-doc conformance*) → backlog **T-B14**.
- A persistent on-screen circuit readout (a HUD list of machines with lamps). With
  refuse-and-name the panel's own prompt tells the player who is occupying the circuit, and each
  machine's screen colour shows its own state; a second UI surface is not worth it now →
  backlog **T-B15** if playtest says otherwise.
- The брат's animation library: `Companion.tscn` copies `idle`/`walk`/`RESET` from `Player.tscn`
  rather than sharing them → backlog **T-B16** (share rig animations via an `AnimationLibrary`).
- Water as a system (`WaterVolume`): removed by the simplification. A flooded drift is a
  `DebrisPile` with `HeavyHitsToClear = 0` (machine-only) and a water-coloured visual.
- Save/load of any of this (T-09), the sealing crew stealth encounter and the final fight (T-07s-b),
  Level 1 (T-08).

---

## Design-doc conformance

Sections implemented: **§1 «Два контури»** (the circuit is the city's scarcity in miniature),
**§2** (Рей is the horizon's technician — he is the one who can restart machines),
**§3 «Рівень 0 — Пролог»** including «Структура: escape-головоломка», the machine table and the
seven segments, **§4** (ліхтар = ресурс; темрява як вибір; ремонт панелі = 3–4 кнопки),
**§6** (газ показувати кольором повітря, а не іконкою; пил у промені; чорна палітра рівня 0).

Requirement-by-requirement:

| Task text (T-07s-a) | Design doc | Verdict |
|---|---|---|
| `PowerCircuit`, one machine at a time, `[Export]` capacity | §3 «Ядро головоломки: енергії вистачає на одну машину за раз» + machine table («потребує **всього** контуру») | agree |
| `GasZone`, lamp in gas = blast | §3 «Головна пастка-механіка: у газі не можна світити» | agree in substance, **hardened for fairness** — see below |
| `DebrisPile` cleared by `heavy_attack` | §3 segment 1 «Перший „важкий удар“ тут — не по людині, а по завалу з кріпильного лісу» | agree |
| Checkpoints | not mentioned in §3 | doc silent; a checkpoint is a fairness requirement of the two lethal mechanics the doc *does* mandate → added, and the doc needs no change |
| `Pump` drains `WaterVolume` / `Extractor` clears `GasZone` as separate machines | §3 machine table lists them as separate machines | **superseded by the author's simplification**: one `PoweredMachine` class, two instances with different `[Export]` targets and different `DisplayName`s. The *player-visible* fiction (насос, витяжка) is unchanged; only the class count is. |
| `ConveyorPlatform` carries the hero along X | §3 machine table: «Конвеєр — працює як рухома платформа на верхній горизонт» | **dropped from this task** by the simplification («менше типів машин»). The conveyor keeps its story role (the spark from its motor ignites the methane, §3 «Подія»); as a puzzle machine it is a third movement pattern that needs a change to `Player`'s motion integration. Recorded as backlog **T-B14**; if the author wants the upper horizon reached by a moving belt, that is a separate, self-contained task. Flagged in *Open questions*. |
| «смерть у газі / у воді» | §3 never says water kills — only that the pump makes a flooded drift passable | **resolved as: water does not drown.** A flooded drift is a blockage (impassable), not a second lethal hazard. Two lethal hazards in a tutorial level is one too many, and this keeps §3 literal. Flagged in *Open questions*; the mechanics support the other reading with one `[Export]` if the author disagrees. |
| Дан як компаньон на весь рівень | §3 says «Дан поруч і балакає» (segment 0) and «Дан виштовхує Рея у щілину» (кінець), and the current implementation leaves him behind at a hatch in segment 0 | **the author's revision wins**: Дан is a companion for the whole level. §3 does not contradict it — it is silent about segments 1–5. `GAME_DESIGN.md` needs no edit; T-07s-b will place him. |
| Скриптові обвали, що відрізають шлях назад | §3 segment 1 «Завал відрізає шлях назад» | agree, generalised into a reusable `CaveIn` |
| Зворотний хід контуру (segment 5) | §3 segment 5 «треба пройти назад і поснімати живлення з усього, що вмикав» | **this one will not work as written — see `## Design risks` §3.** It directly contradicts the author's own «завали відрізають шлях назад»: you cannot walk back through a sealed drift. Recommendation in the risks section: cut it to switching off **one** panel near the hoist. |

Where the doc is silent (checkpoint behaviour, warning windows, follower failsafes) the decisions
are recorded under **`## Resolved`** with the same "можна оскаржити" marker the previous session used
(`docs/sessions/2026-09-10-session-02.md` §3) — nothing was invented against the doc.

---

## Options considered

### 1. `PowerCircuit` — where does it live and how do machines join?

| Option | For | Against | Verdict |
|---|---|---|---|
| **A. Autoload** (a 4th singleton) | reachable from anywhere, survives scene reloads | the circuit is the *horizon's* emergency bus — one level's prop, not run state; CLAUDE.md allows global state only in `GameState`, and the architect rules forbid manager singletons beyond it; state would leak across a level reload and need explicit resetting | rejected |
| **B. Plain `Node` in the level scene, machines self-register in `_Ready`** | exactly the `EnemyDirector` pattern already in the repo (`scripts/core/EnemyDirector.cs`, a `Node` referenced by `[Export]` from `Guard`/`WaveSpawner`); one export per machine and no list to keep in sync; lifetime = the level's | the circuit's contents are not visible in the inspector | **chosen** |
| **C. `Resource`** shared by `[Export]` | data-ish, editable as a file | resources are shared between scene instances and outlive the tree; without `resource_local_to_scene` two loads of the level would share powered state — a subtle save/reload trap for no gain | rejected |
| **D. `[Export] PoweredMachine[] Machines` on the circuit** (circuit knows machines) | inspectable, explicit | duplicates the wiring (machine→circuit and circuit→machine) and silently breaks when one side is forgotten; T-07s-b would maintain a hand-written array | rejected; the circuit exposes `Machines` as a read-only runtime list instead |

### 2. `PowerCircuit` — what happens when the circuit is full?

| Option | For | Against | Verdict |
|---|---|---|---|
| **A. Auto-preempt** (switching B on silently switches A off) | zero backtracking, the lesson lands where the player stands | the *player* never makes the trade-off — the game makes it for them; the moment "I had to give something up" evaporates; and a machine dying off-screen is invisible | rejected — **author's explicit decision** |
| **B. Refuse and name the culprit** — the panel does not switch on and says «Не хватає потужності: працює Насос» | the scarcity is a decision the player takes, not a side effect; the message teaches both the rule *and* the fix in one line; no invisible state changes | costs a walk back to the other panel each time (mitigations in `## Design risks` §1) | **chosen (author-confirmed)** |
| **C. Refuse silently** («Немає живлення») | simplest | the player has no idea *why* and starts pressing buttons — this is the existing `FailedNoPower` dead-end message and it is exactly what must not happen here | rejected |

### 3. Checkpoint — how does a death not cost the level?

| Option | For | Against | Verdict |
|---|---|---|---|
| **A. Reload the scene, restore from a checkpoint id in `GameState`** | reuses the existing `RestartLevel` (`ReloadCurrentScene` + `ResetRun`) | level-local state in the run singleton (TASKS.md explicitly says the mine's machine state is *not* written to `GameState`); the intro cutscene and every stage replay; every cleared pile comes back; a 1–2 s hitch on every death | rejected |
| **B. Soft respawn — no scene reload**: `Player.Revive()`, warp to the checkpoint, restore energy, re-apply the checkpoint's `RoomBounds`, lamp forced off, `HitStop.Cancel()`, pause lifted | instant, keeps the world exactly as the player left it (this is the fairness point: one mistake costs seconds, not the puzzle); needs no new global state at all | needs two small additive methods on `Player` (`Kill`, `Revive`) and the level must be written so nothing is left in a half-scripted state | **chosen** |
| **C. Both: soft respawn for hazards, full reload for combat KO** | keeps T-06's KO restart untouched | two death paths that look identical to the player, and the KO path is the one that will be hit in segment 7 (the fight for Дан's powerbank) | rejected as a *rule*, but this is what falls out anyway: with **no** checkpoint armed `LevelBase` keeps the old `RestartLevel` behaviour, so `TestRoom` and the current prologue are bit-for-bit unchanged |

**Does a respawn reset the circuit / cleared obstacles?** No. Recorded decision: cleared is cleared,
powered stays powered. Resetting them would turn a single misstep into re-solving the puzzle, which
is the exact unfairness this section exists to prevent. `LevelBase` emits `Respawned` so a level
that ever wants a reset can do it itself — `LevelBase` stays free of puzzle knowledge.

### 4. `GasZone` — collision layer and how it learns the lamp is on

- **Layer:** *no new physics layer is needed and none is added.* Layer 7 `LightDark` is the wrong
  one (it is the "hero is lit" sensor channel, masked by `Player/LightSensor`, and its semantics are
  inverted here). `GasZone` is a trigger like `Door`, `TutorialPrompt` and `WaveSpawner`:
  `collision_layer = 0`, `collision_mask = 2` (Player), `monitorable = false`. Free bit 8 stays
  free. **`project.godot` is not touched by this task.**
- **Knowing the lamp state:** three candidates —
  1. poll `player.Flashlight.IsOn` every physics frame while the hero is inside (the
     `JumpableObstacle` pattern) — correct but pays a frame cost for a value that changes twice a
     minute;
  2. take a `[Export] Player` reference and subscribe once in `_Ready` — always subscribed, fires
     for zones on the other side of the level;
  3. **chosen:** on `BodyEntered(Player)` subscribe to that player's `Flashlight.Toggled`, on
     `BodyExited` unsubscribe. Zero per-frame work when nobody is inside, no export to wire, no
     `GetNode` outside the scene (the hero's `Flashlight` is a public `[Export]` property of
     `Player`, the same access `LevelFx` uses for `Player.Hitbox`). `_PhysicsProcess` is switched on
     **only** while the warning window is counting down.
- **What the blast does:** it routes into the **existing** death path — `Player.Kill()` sets the
  same `_knockedOut` flag `TakeHit` would, transitions to `KO` and emits `KnockedOut`, so
  `LevelBase` (and `LevelFx`'s camera shake) already handle it. One death path, one restart rule.
  A separate hazard-death path was rejected: it would need its own restart plumbing and its own bugs.
- **Teaching the rule before the first death** (this is the design point, not an implementation
  detail) — four layers, all mechanical, all in this task:
  1. the pocket is **visible before it is lethal**: an always-on greenish-yellow haze
     (`[Export] Color HazeColor`, §6 «показувати кольором повітря, а не іконкою`) plus a haze that
     brightens the moment the hero steps in, with the lamp on **or** off;
  2. a **warning window** (`[Export] float WarningSeconds = 0.8f`, ≈48 frames): entering with the
     lamp on — or switching it on inside — flares the haze and emits `WarningStarted`; switching the
     lamp off **or** stepping out cancels it. Only when it runs out does the pocket ignite. The
     player's first contact is a scare that teaches, not a corpse;
  3. `Companion.Say()` — Дан shouts on `WarningStarted`. A warning from a character costs no UI and
     is remembered;
  4. a **rehearsal pocket**: `WarningSeconds` is an `[Export]`, so T-07s-b can put a shallow pocket
     with a 1.5 s window and an exit two steps away before the real one.
  Plus `[Export] bool Lethal = true` / `[Export] float BlastDamage = 25f`: a non-lethal first
  pocket (a flash burn that costs energy and knocks the hero down) is one inspector value away if
  playtest says the death still reads as a gotcha.

### 5. Obstacles — one contract or a class per obstacle?

Chosen: a minimal interface `IClearable { bool IsCleared; void Clear(); }` in `scripts/props/`,
mirroring the existing `IHittable` idiom, implemented by `GasZone` (an `Area2D`) and `DebrisPile`
(a `StaticBody2D`). A shared abstract base class is impossible (different Godot base types), and two
concrete nullable exports on the machine (`GasTarget`, `BlockageTarget`) would have to grow every
time the level wants a third kind of obstacle. `PoweredMachine` therefore has exactly one
`[Export] Node2D[] ClearTargets`, resolved once in `_Ready` into a cached `IClearable[]` with a
`GD.PushWarning` for anything that does not implement it.

### 6. `DebrisPile` — which layer does the hero's `heavy_attack` find?

The hero's `Visual/Hitbox` has `collision_mask = 4`, i.e. layer 3 `Enemy`. Options: (a) put the
pile's `Hurtbox` on layer 3 — no project or `Player.tscn` change, and layer 3 in practice already
means "things a `Hitbox` may hit"; (b) add layer 8 `Destructible` and widen the hero's hitbox mask
to `4|128`. **(a) chosen**: (b) edits the shared `Player.tscn` combat wiring and `project.godot` for
a purely cosmetic gain, and nothing in the game keys off layer 3 as "an enemy" (`Guard` detection
targets the hero; `EnemyDirector` and `WaveSpawner` hold their enemies by reference, not by layer).
Recorded in the plan so `/reviewer` does not read it as an accident.

### 7. Test scene — extend `TestRoom` or add `TestMine`?

**New `scenes/levels/TestMine.tscn` + `scripts/levels/TestMine.cs : LevelBase`.** `TestRoom` is the
combat/movement fixture asserted by seven smoke scripts (`player_movement`, `player_flashlight`,
`combat_dummy`, `props_interact`, `actors_rig`, `level_dressing`, `ui_pause`); adding a lethal gas
zone, blocking rubble and a companion to it would put new bodies and areas inside the walk band
those tests measure, and would slow every one of them. A separate one-room fixture is ~120 lines of
`.tscn`, is the natural home for the four new smoke scripts, and doubles as the wiring reference
T-07s-b copies from. `TestRoom` gets **no change at all** in this task.

---

## Recommended approach

One level-owned `PowerCircuit` node; each machine is a `PowerPanel` subclass that asks the circuit
for power when its panel completes, and either switches on (removing the obstacles it points at,
permanently) or refuses with the name of the machine occupying the circuit. Because refusal is the
rule, `PowerPanel` learns to be switched **off** again (`CanPowerDown`, default `false`, so nothing
existing changes). Hazards and blockages are two node types behind one tiny interface. Death is one
path (`Player.Kill()` → the existing KO route) and `LevelBase` answers it with a soft respawn at the
last checkpoint when one is armed, and with the old full reload when none is. Дан is a
`CharacterBody2D` follower with a two-state machine, `collision_layer = 0` so he can never block or
trigger anything, and three independent anti-stuck failsafes. Everything is exercised in a new
one-room `TestMine.tscn`.

Ordering for `/coder` (each step compiles and leaves the smoke suite green):

1. `PowerPanel` additive changes + `props_circuit.gd` assertions that the **defaults** are unchanged
   (characterisation first, per the architect rules for a change to existing behaviour).
2. `PowerCircuit`, `IClearable`, `DebrisPile`, `GasZone`, `PoweredMachine`, `Hoist`.
3. `Player.Kill/Revive`, `Checkpoint`, `CaveIn`, `LevelBase` respawn.
4. `Companion` + states + scene.
5. `TestMine.tscn` / `.cs`, then the four smoke scripts.

---

## GameState & save impact

**No new `GameState` field and no new signal.** Reads/writes:

| Node | `GameState` touch | Why |
|---|---|---|
| `GasZone` | none directly | the blast calls `Player.Kill()`; energy is not the cause of death |
| `LevelBase.RespawnAtCheckpoint` | writes `Energy` (`= max(snapshot, MinRespawnEnergy)`), emits `EnergyChanged` through the existing setter | a respawn must not hand the player a run they cannot continue |
| `LevelBase.SetCheckpoint` | reads `Energy` (snapshot) | so the respawn restores what the player had, not a free refill |
| `PowerCircuit`, `PoweredMachine`, `DebrisPile`, `CaveIn`, `Companion` | none | the mine's circuit is level-local state; TASKS.md says so explicitly («стан у `GameState` не пишеться (рівень локальний)») |

`ResetRun()` is **not** called on a checkpoint respawn — that is the point of the whole section
(`RestartLevel` still calls it, unchanged).

**For T-09 (Save/Load):** if the author ever wants a mid-prologue save, three things would have to
be persisted and none of them exists in `GameState` today — name them here so T-09's plan can pick
them up: (1) the id of the armed checkpoint + its energy snapshot, (2) which machines are powered
(`PoweredMachine.SaveId` → `bool`), (3) which obstacles are cleared (`IClearable` node
`SaveId` → `bool`). `Interactable.SaveId` already exists for exactly this and every new panel gets
one filled in. Recommendation for T-09: the prologue is short enough to save only at checkpoints,
which reduces (1)–(3) to "checkpoint id + a bitmask".

---

## Scene & signal contract

Node names, `[Export]`s with defaults **and units**, signals with parameter types, layers/masks and
who connects to what. Placeholder visuals keep the `PH_` prefix; colours come from
`BlackoutLastGrid.Art.Palette` (visual brief), never as literal `Color(...)` in a script.
`z_index` values follow the brief's depth table.

### 1. `scripts/core/PowerCircuit.cs` — `partial class PowerCircuit : Node`

No scene: a plain `Node` placed in the level, exactly like `EnemyDirector`.

| `[Export]` | Type | Default | Unit / meaning |
|---|---|---|---|
| `Capacity` | `int` | `1` | power units the emergency bus can feed at once |
| `MachineName` | — | — | *(none; the name lives on the machine)* |

| Signal | Parameters | When |
|---|---|---|
| `MachineRegistered` | `(PoweredMachine machine)` | machine's `_Ready` |
| `MachinePowered` | `(PoweredMachine machine)` | a request was granted |
| `MachineReleased` | `(PoweredMachine machine)` | a machine was switched off (player or teardown) |
| `RequestRefused` | `(PoweredMachine machine, PoweredMachine blocking)` | not enough free capacity; `blocking` is the machine to switch off |
| `LoadChanged` | `(int used, int capacity)` | after any of the above |

Public API: `int Used`, `int Free => Capacity - Used`,
`IReadOnlyList<PoweredMachine> Machines`, `void Register(PoweredMachine)`,
`void Unregister(PoweredMachine)`, `bool TryPower(PoweredMachine machine, out PoweredMachine? blocking)`,
`void Release(PoweredMachine)`.

`TryPower` rules — no preemption, ever:
```
needed = machine.RequiresWholeCircuit ? Capacity : machine.PowerCost
if needed > Capacity            -> GD.PushWarning (level wiring error), refuse, blocking = null
if Free >= needed               -> grant, emit MachinePowered + LoadChanged, return true
else                            -> blocking = the longest-powered machine (registration order),
                                   emit RequestRefused, return false
```
`Release` is idempotent (a machine not powered is a no-op) — the panel may power down from inside a
signal handler. Both calls are event-driven; nothing in this class runs per frame
(`SetProcess(false)` / no `_Process` at all).

### 2. `scripts/props/IClearable.cs`

```csharp
public interface IClearable
{
    bool IsCleared { get; }
    void Clear();          // idempotent; permanent
}
```

### 3. `scenes/props/PoweredMachine.tscn` ↔ `scripts/props/PoweredMachine.cs`

`partial class PoweredMachine : PowerPanel` (which is `Interactable : Area2D`).

```
PoweredMachine        Area2D            layer 32 (6 Interactable), mask 0, monitoring = false,
                                        monitorable = true, script = PoweredMachine.cs
  PH_Body             Polygon2D         z_index 0, Palette.SteelCold, 3 px OutlineDark edge
  PH_Screen           Polygon2D         → [Export] Screen (inherited from PowerPanel)
  PH_RunLight         PointLight2D      enabled = false; on while powered (Palette.EnergyAmber)
  CollisionShape2D    CircleShape2D r=44 (same reach as PowerPanel.tscn)
```

Inherited `[Export]`s used with non-default values in the level: `PromptText = "Увімкнути"`,
`ActivatedPromptText = "Працює — зняти живлення"`, `Sequence = []` (empty ⇒ one `E` press switches
on; `PowerPanel.Begin` already completes immediately on an empty sequence — a 4-button repair per
switch-on would be tedium, and §4's «3–4 кнопки» is about *repairing* a dead panel, which T-07s-b
can still do by filling `Sequence` on the first machine only), `CanPowerDown = true`,
`SaveId` filled per instance.

New `[Export]`s:

| `[Export]` | Type | Default | Unit / meaning |
|---|---|---|---|
| `Circuit` | `PowerCircuit` | `null!` | the bus this machine draws from (level wires it) |
| `DisplayName` | `string` | `"Машина"` | the name other panels print when they refuse |
| `PowerCost` | `int` | `1` | units drawn while running |
| `RequiresWholeCircuit` | `bool` | `false` | `true` ⇒ needs `Capacity` units (the hoist) |
| `ClearTargets` | `Node2D[]` | empty | nodes implementing `IClearable`, cleared when powered |
| `OverloadPromptFormat` | `string` | `"Не хватає потужності: працює {0}"` | `{0}` = blocking machine's `DisplayName` |
| `OverloadPromptSeconds` | `float` | `3.0` | s the refusal text stays in the HUD |
| `RunLight` | `PointLight2D?` | `null` | switched with power |
| `RunFx` | `Node2D?` | `null` | optional emitter group enabled while running (steam, dust) |

| Signal | Parameters | When |
|---|---|---|
| `PowerChanged` | `(bool powered)` | after the circuit granted or released |
| `ActivationRefused` | `(string blockingName)` | the circuit refused; the prompt already shows it |

Behaviour:
- `_Ready`: `base._Ready()`, resolve `ClearTargets` → cached `IClearable[]`, `Circuit.Register(this)`.
- `_ExitTree`: `Circuit.Unregister(this)` (which releases if powered).
- `override Complete()` (made `protected virtual` on `PowerPanel`):
  `if (!Circuit.TryPower(this, out var blocking)) { RefuseActivation(); show overload prompt; emit ActivationRefused; return; }` else `base.Complete()`.
  The circuit is asked **before** the panel commits, so the player never sees the screen go green and
  die — and the reentrancy hazard of "activate → handler powers something down → `Finish(true)`
  anyway" never arises.
- `Activated` (inherited) ⇒ `SetPowered(true)`: `RunLight.Enabled = true`, `RunFx` on,
  `foreach (var t in _targets) t.Clear();` (permanent), `EmitSignalPowerChanged(true)`.
- `Deactivated` (new on `PowerPanel`) ⇒ `SetPowered(false)`: `Circuit.Release(this)`, lights/FX off,
  `EmitSignalPowerChanged(false)`. Targets stay cleared — **that is the design**.
- `CurrentPrompt` override: the overload text for `OverloadPromptSeconds` after a refusal, else
  `base.CurrentPrompt`. The countdown reuses the `_PhysicsProcess` the panel already owns; the HUD
  updates itself through the existing `PromptChanged` → `LevelBase.OnPromptChanged` chain — **no new
  UI wiring anywhere**.

### 4. `scenes/props/Hoist.tscn` ↔ `scripts/props/Hoist.cs`

`partial class Hoist : PoweredMachine` — the exit, kept a separate class because it is a separate
role (§3 machine table: «Кліть (підйомник) — єдиний вихід … потребує **всього** контуру»).

```
Hoist                 Area2D            as PoweredMachine (layer 32 / mask 0)
  PH_Cage             Polygon2D         Palette.SteelCold + OutlineDark
  PH_Screen           Polygon2D         → Screen
  PH_RunLight         PointLight2D      → RunLight
  CollisionShape2D    CircleShape2D r=48
  BoardingArea        Area2D            layer 0, mask 2 (Player), monitorable = false
    CollisionShape2D  RectangleShape2D 120×80 across the floor band
```
Instance values: `RequiresWholeCircuit = true`, `DisplayName = "Кліть"`,
`PromptText = "Запустити кліть"`, `CanPowerDown = false` (you do not switch off your way out).

| new `[Export]` | Type | Default | Meaning |
|---|---|---|---|
| `BoardingArea` | `Area2D?` | `null` | crossing it while powered departs |
| `RequiresPlayerBoarding` | `bool` | `true` | `false` ⇒ powering it is enough (tests) |

| Signal | Parameters | When |
|---|---|---|
| `Departed` | `(Player player)` | hero entered `BoardingArea` while powered (once) |

`BoardingArea.BodyEntered` is connected in `_Ready` and disconnected in `_ExitTree`; the level
decides what `Departed` means (cutscene → `GoToLevel`) — the hoist changes no scenes itself.

### 5. `GasZone` — `scripts/props/GasZone.cs`, built **inline** in level scenes

No `.tscn`: it follows the `LitZone` precedent (a script + an `Area2D` composed per level, because
its shape and haze polygon are level geometry). `partial class GasZone : Area2D, IClearable`.

```
GasZone               Area2D            layer 0, mask 2 (Player), monitoring = true,
                                        monitorable = false, script = GasZone.cs
  CollisionShape2D    RectangleShape2D  the pocket, across the floor band
  PH_Haze             Polygon2D         z_index +18, HazeColor a = HazeAlpha (§6: колір повітря)
  PH_HazeGlow         PointLight2D      enabled = false; flares during the warning
  PH_Motes            GpuParticles2D    optional; still motes = «немає тяги» (§6)
```

| `[Export]` | Type | Default | Unit / meaning |
|---|---|---|---|
| `WarningSeconds` | `float` | `0.8` | s between "lamp on inside the gas" and ignition |
| `Lethal` | `bool` | `true` | `false` ⇒ a flash burn instead of a death |
| `BlastDamage` | `float` | `25` | energy units, used only when `Lethal == false` |
| `BlastKnockback` | `float` | `220` | px/s, used only when `Lethal == false` |
| `BlastHitStopFrames` | `int` | `6` | physics frames of hit-stop on ignition |
| `Haze` | `CanvasItem?` | `null` | the air-colour layer |
| `HazeColor` | `Color` | `#b6c24a` @ 0.20 | greenish-yellow (a new `Palette.GasHaze` entry) |
| `HazeWarningColor` | `Color` | `#e0d24a` @ 0.42 | haze during the warning |
| `HazeFadeSeconds` | `float` | `0.9` | s the haze takes to disappear when cleared |
| `WarningLight` | `PointLight2D?` | `null` | flares while the warning counts down |
| `Motes` | `GpuParticles2D?` | `null` | stopped emitter once cleared |

| Signal | Parameters | When |
|---|---|---|
| `WarningStarted` | `()` | hero inside with the lamp on |
| `WarningStopped` | `()` | lamp off or hero left before ignition |
| `Ignited` | `(Player player)` | the window ran out |
| `Cleared` | `()` | `Clear()` — once, permanent |

Wiring and lifetime:
- `BodyEntered(Node2D)` → `if (body is Player p && !IsCleared) { _player = p; p.Flashlight.Toggled += OnLampToggled; Arm(p.Flashlight.IsOn); }`
- `BodyExited` → unsubscribe, `Disarm()`, `_player = null`.
- `OnLampToggled(bool on)` → `Arm(on)`.
- `Arm(true)` → `SetPhysicsProcess(true)`, haze → `HazeWarningColor`, `WarningLight.Enabled = true`,
  `EmitSignalWarningStarted()`. `_PhysicsProcess` counts `WarningSeconds` down and ignites.
- Ignite → `Disarm()`, `HitStop.Trigger(BlastHitStopFrames)`, `EmitSignalIgnited(p)`, then
  `Lethal ? p.Kill() : p.TakeDamage(BlastDamage, BlastKnockback * sign, true, BlastHitStopFrames)`.
- `Clear()` → `IsCleared = true`, `Disarm()`, unsubscribe, `Monitoring = false` **deferred**
  (`SetDeferred`, it may be called from a physics callback), haze tweened to alpha 0 over
  `HazeFadeSeconds`, motes stopped, `EmitSignalCleared()`. Idempotent.
- `_ExitTree` → unsubscribe unconditionally.
- Per-frame cost: `_PhysicsProcess` **only** while a warning is counting (≈48 frames per contact).

### 6. `scenes/props/DebrisPile.tscn` ↔ `scripts/props/DebrisPile.cs`

`partial class DebrisPile : StaticBody2D, IHittable, IClearable`.

```
DebrisPile            StaticBody2D      layer 1 (World), mask 0, script = DebrisPile.cs
  CollisionShape2D    RectangleShape2D 56×40   → [Export] BlockerShape (the wall)
  Hurtbox             Area2D            layer 4 (3 Enemy — "a Hitbox may hit this"), mask 0,
                                        monitoring = false, monitorable = true
    CollisionShape2D  RectangleShape2D 72×72
  PH_Rubble           Node2D            z_index 0, timber/rock Polygon2Ds (RustDeep / RockNear)
  PH_Dust             GpuParticles2D    one-shot on each hit and on clearing
```

| `[Export]` | Type | Default | Unit / meaning |
|---|---|---|---|
| `HeavyHitsToClear` | `int` | `2` | heavy hits needed; `0` ⇒ hands cannot clear it (machine only) |
| `RequiresKnockdown` | `bool` | `true` | only a hit with `HitInfo.Knockdown` counts — i.e. only `heavy_attack` (light 1–3 have `Knockdown = false`; light 3 shares `HitStopFrames = 5`, so frames are **not** a usable discriminator) |
| `BlockerShape` | `CollisionShape2D` | `null!` | disabled when cleared |
| `Rubble` | `Node2D?` | `null` | hidden / dropped when cleared |
| `Dust` | `GpuParticles2D?` | `null` | one-shot per hit |
| `StartsCleared` | `bool` | `false` | a pile a `CaveIn` will later create starts cleared+hidden |
| `SaveId` | `string` | `""` | for T-09 |

| Signal | Parameters | When |
|---|---|---|
| `Damaged` | `(int hitsLeft)` | a heavy hit landed and it is not yet clear |
| `Resisted` | `()` | a hit that does not qualify (light attack, or `HeavyHitsToClear == 0`) |
| `Cleared` | `()` | once, permanent |

`TakeHit(in HitInfo hit)`:
```
if (IsCleared) return false;
if (HeavyHitsToClear <= 0 || (RequiresKnockdown && !hit.Knockdown)) { EmitSignalResisted(); return false; }
_hits++; dust one-shot; if (_hits >= HeavyHitsToClear) Clear(); else EmitSignalDamaged(left);
return true;   // true ⇒ Hitbox fires hit-stop + its Hit signal ⇒ LevelFx sparks and shake for free
```
`Clear()` → `IsCleared = true`, `BlockerShape.SetDeferred("disabled", true)` (never inside a physics
flush — the `Door.ApplyLock` precedent), `Hurtbox.SetDeferred("monitorable", false)`, rubble hidden
or dropped, dust burst, `EmitSignalCleared()`. Idempotent.
`SetBlocked(bool)` public, used by `CaveIn` to *create* a pile: re-enables the shape and shows the
rubble (the inverse of `Clear`, used before the player can ever have cleared it).

**Depth trap (must be in the level's geometry, not in code):** `Hitbox.TryHit` compares the *root*
`GlobalPosition.Y` of the target against the attacker's Y with `DepthTolerance = 12 px`
(inclusive) — that number is the attacker's and a pile cannot widen it. So a pile is hittable only
when the hero stands within 12 px of the pile's **root Y**. Rule for every level:
place a pile's root at the centre of the room's floor band and mark the strip with a `PH_` floor
decal (`z_index −20`) so the player can see where to stand. Written into the playtest checklist and
into `TestMine`.

### 7. `Checkpoint` — `scripts/levels/Checkpoint.cs`, built inline in level scenes

`partial class Checkpoint : Area2D` (the `Door` precedent: script only, composed per level).

```
Checkpoint            Area2D            layer 0, mask 2 (Player), monitorable = false
  CollisionShape2D    RectangleShape2D 80 × floor-band height
  PH_Mark             Polygon2D         z_index −20 floor decal (Palette.EnergyAmber @ 0.25)
```

| `[Export]` | Type | Default | Unit / meaning |
|---|---|---|---|
| `RespawnOffset` | `Vector2` | `(0, 0)` | px added to the node's position on respawn |
| `Room` | `RoomBounds?` | `null` | bounds re-applied on respawn (camera limits + floor band) |
| `RestoresFullEnergy` | `bool` | `false` | `true` ⇒ respawn with `MaxEnergy` instead of the snapshot |
| `Label` | `string` | `""` | debug/test name, shown by `TestMine`'s debug label |

| Signal | Parameters | When |
|---|---|---|
| `Reached` | `(Checkpoint checkpoint)` | first time the hero crosses it (one-shot: `Monitoring = false` deferred) |

The checkpoint stores nothing; `LevelBase` owns the armed one.

### 8. `CaveIn` — `scripts/levels/CaveIn.cs`, built inline in level scenes

`partial class CaveIn : Area2D` — the scripted collapse. Cuts the way back, shakes the screen,
hurries the player. **Never lethal** (`Lethal` is not even an export: an unavoidable scripted death
is exactly the unfairness this plan is fighting).

```
CaveIn                Area2D            layer 0, mask 2 (Player), monitorable = false
  CollisionShape2D    RectangleShape2D  trigger strip across the floor band
```

| `[Export]` | Type | Default | Unit / meaning |
|---|---|---|---|
| `Level` | `LevelBase` | `null!` | for `ShakeCamera` (the `LevelFx` precedent: `NodePath("..")`) |
| `Blockage` | `DebrisPile?` | `null` | the pile that appears; must have `StartsCleared = true` |
| `Delay` | `float` | `0.35` | s between the trigger and the collapse (so it lands *behind* the hero) |
| `ShakeAmplitude` | `float` | `12` | px |
| `ShakeSeconds` | `float` | `0.7` | s |
| `Dust` | `GpuParticles2D?` | `null` | one-shot burst |
| `Rumble` | `Node2D?` | `null` | optional group enabled for the duration |

| Signal | Parameters | When |
|---|---|---|
| `Triggered` | `()` | the hero crossed; the delay starts |
| `Collapsed` | `()` | the pile is solid; the level can make Дан react |

One-shot: `Monitoring` off (deferred) on trigger; the delay uses
`GetTree().CreateTimer(Delay, processAlways: false, processInPhysics: false, ignoreTimeScale: true)`
— `processAlways: false` so a pause does not collapse the mine behind a pause menu, and
`ignoreTimeScale: true` so a hit-stop does not stretch it (the `LevelBase` KO-timer precedent).
Session-01 §5 trap: the timer handle is kept in a field and its `Timeout` is unsubscribed in
`_ExitTree`, because a C# subscription to a temporary `SceneTreeTimer` that goes out of scope does
not fire.

### 9. `scenes/actors/Companion.tscn` ↔ `scripts/actors/Companion.cs`

Дан. `partial class Companion : CharacterBody2D`.

```
Companion             CharacterBody2D   collision_layer = 0, collision_mask = 1 (World only),
                                        motion_mode = 1 (Floating), script = Companion.cs
  PH_Shadow           Polygon2D         z_index −10, Palette.ShadowSoft (copied from the Dan node
                                        already in Level00_Prologue.tscn)
  Visual              Node2D            position (0, −36)
    Rig               CharacterRig      instance; SuitColor = Palette.DanSuit,
                                        SkinColor = Palette.SkinWarm, Build = Slim
    Sprite            AnimatedSprite2D  empty slot (visual brief: kept for future painted art)
    Bubble            Label             → [Export] Bubble; hidden; short spoken lines
  CollisionShape2D    CapsuleShape2D r=7 h=28   (same as the hero's, so he fits where the hero fits)
  AnimationPlayer     AnimationPlayer   RESET / idle / walk copied verbatim from Player.tscn
                                        (identical `Visual/Rig/...` track paths) — see T-B16
  StateMachine        StateMachine      InitialState = Follow
    Follow            CompanionFollow
    Wait              CompanionWait
```

`collision_layer = 0` is the single most important value in this scene: it means Дан **cannot** push
the hero, cannot be hit, and cannot trigger `Door`, `TutorialPrompt`, `Checkpoint`, `CaveIn`,
`GasZone` or `WaveSpawner` (all of which mask layer 2 = Player). `mask = 1` keeps him out of walls.

| `[Export]` | Type | Default | Unit / meaning |
|---|---|---|---|
| `Target` | `Player` | `null!` | who he follows (the level wires it) |
| `MoveSpeed` | `float` | `205` | px/s while trailing (just under the hero's 220 so he *reads* as trailing) |
| `CatchUpSpeed` | `float` | `300` | px/s beyond `CatchUpDistance` |
| `FollowDistance` | `float` | `90` | px; closer than this he stops |
| `CatchUpDistance` | `float` | `260` | px; farther than this he hurries |
| `WarpDistance` | `float` | `900` | px; beyond this he is warped behind the hero at once |
| `StuckSeconds` | `float` | `2.5` | s of "wants to move, is not moving" before a warp |
| `DepthSpeedFactor` | `float` | `0.75` | matches the hero's belt-scroll depth factor |
| `SideOffset` | `float` | `-56` | px behind the hero along X, sign flipped by the hero's facing |
| `DepthOffset` | `float` | `10` | px of Y offset so he is never exactly on the hero's depth line |
| `BubbleSeconds` | `float` | `2.6` | s a line stays up |
| `Bubble` | `Label?` | `null` | the line label |
| `Visual` / `Rig` / `AnimationPlayer` | node refs | | flip, animation |
| `WalkAnimationMinSpeed` | `float` | `12` | px/s above which `walk` plays (the `GuardApproach` precedent: switch animation only on a change) |

| Signal | Parameters | When |
|---|---|---|
| `LineShown` | `(string text)` | `Say()` was called (levels/tests, and future audio) |
| `Arrived` | `()` | a `Wait` state reached its hold position |
| `Warped` | `()` | a failsafe warp happened (tests assert on this) |

Public API: `void Say(string text)`, `void WarpBehind()`, `void HoldAt(Vector2 position)`
(→ `Wait`), `void Resume()` (→ `Follow`), `bool IsWaiting`, `string CurrentStateName`.

States (both `partial class ... : CompanionState`, mirroring `PlayerState`/`GuardState`):
- **`Follow`** — `PhysicsUpdate`: target point = `Target.GlobalPosition + (−facing * SideOffset, DepthOffset)`,
  clamped to `Target.FloorTop … FloorBottom` (the hero's own public exports — Дан inherits the
  hero's floor band and therefore never needs `RoomBounds` of his own); if the distance is under
  `FollowDistance` → `Velocity = Vector2.Zero`, `MoveAndSlide()`, idle animation; else move at
  `MoveSpeed`/`CatchUpSpeed` with the depth factor. Failsafes: distance > `WarpDistance`, **or**
  `wants to move && Velocity.Length() < 5 px/s` for `StuckSeconds` → `WarpBehind()`.
- **`Wait`** — walks to the held position, emits `Arrived` once inside 12 px, then holds and plays
  `idle`. Used for the scripted beats (segment 0 chatter, the final collapse).

`WarpBehind()` puts him at the follow point, zeroes `Velocity`, and emits `Warped`. It is called by
the states' failsafes **and** by `LevelBase.ApplyRoomBounds` / `RespawnAtCheckpoint` — so a door
transition or a death never leaves Дан on the wrong side of a sealed drift.

Frame budget: one `DistanceSquaredTo`, one `MoveAndSlide` and one clamp per physics step; animation
selection in `_Process` only, and only when the animation actually changes. No allocation, no LINQ.

### 10. `scenes/levels/TestMine.tscn` ↔ `scripts/levels/TestMine.cs : LevelBase`

One room, 1920×1080 camera limits, floor band Y 300…600 — same geometry as `TestRoom`, so the
existing camera/pause/HUD expectations hold.

```
TestMine              Node2D            y_sort_enabled = true, script = TestMine.cs
  CanvasModulate                        #0a0d14 (the mine's darkness, as in TestRoom)
  PH_Background / PH_Floor / PH_FloorEdge   ColorRect, z −40 / −20
  PH_WallLeft / PH_WallRight            StaticBody2D layer 1
  Rooms
    Room_Main         RoomBounds        Rect (0,0,1920,1080), FloorTop 300, FloorBottom 600
  Circuit             PowerCircuit      Capacity = 1
  Checkpoints                           container ⇒ LevelBase [Export] Checkpoints
    Checkpoint_Start  Checkpoint        x 220, Room = Room_Main, Label = "Старт"
    Checkpoint_Gas    Checkpoint        x 900, Room = Room_Main, Label = "Перед газом"
  Props
    DebrisPile_Hand   DebrisPile        x 440, root Y 450 (band centre), HeavyHitsToClear = 2
    PH_HitStrip       Polygon2D         z −20 decal marking the ±12 px depth strip at Y 450
    Flood             DebrisPile        x 700, HeavyHitsToClear = 0 (machine only), water-blue rubble
    Pump              PoweredMachine    x 620, DisplayName "Насос", ClearTargets [Flood]
    GasZone_Pocket    GasZone           x 1000…1180, WarningSeconds 0.8
    Extractor         PoweredMachine    x 960, DisplayName "Витяжка", ClearTargets [GasZone_Pocket]
    CaveIn_Mid        CaveIn            x 1240 trigger, Blockage = DebrisPile_Back
    DebrisPile_Back   DebrisPile        x 1200, StartsCleared = true (appears on the cave-in)
    Hoist             Hoist             x 1720, RequiresWholeCircuit = true, DisplayName "Кліть"
    Outlet            Outlet            x 300 (recharge, so a test run cannot brick itself)
  Player              (instance)        x 150, Y 450
  Companion           (instance)        x 90,  Y 460, Target = Player
  Camera2D                              limits 0/0/1920/1080, position_smoothing_enabled
  HUD / PauseMenu / LevelFx / Vignette  (as in TestRoom; LevelFx gives sparks + shake for free)
  UI / DebugLabel     Label             circuit load, armed checkpoint, companion state
```

`TestMine.cs` responsibilities only (no puzzle logic in `LevelBase`):
`[Export] PowerCircuit Circuit`, `[Export] Label DebugLabel`, `[Export] Hoist Hoist`,
`[Export] GasZone Gas`, `[Export] Companion? Dan`; subscribes to `Circuit.LoadChanged`,
`Circuit.RequestRefused`, `Gas.WarningStarted/Ignited/Cleared`, `Hoist.Departed`,
`CaveIn.Collapsed`, `LevelBase.Respawned` and (a) updates the debug label, (b) makes Дан speak
(`Dan?.Say("Гасни! Газ!")` on `WarningStarted`, `"Швидше, тут сиплеться!"` on `Collapsed`) — which
is precisely the pattern T-07s-b will use in the prologue. `Departed` shows a label, no scene change
(this is a fixture, not a level).

### 11. Edited: `scripts/props/PowerPanel.cs` — additive, defaults preserve behaviour byte for byte

| new `[Export]` | Type | Default | Meaning |
|---|---|---|---|
| `CanPowerDown` | `bool` | `false` | an activated panel accepts `interact` again and switches off |

| new signal | Parameters | When |
|---|---|---|
| `Deactivated` | `()` | `PowerDown()` switched an activated panel off |
| `ActivationRefused` | `()` | a completed sequence was refused by a subclass (no `_deadNoPower`) |

Changes, all additive:
1. `CanInteract` → `(!IsActivated || CanPowerDown) && !_deadNoPower` (identical when
   `CanPowerDown == false`).
2. `Begin` → after the existing `CanInteract` guard: `if (IsActivated && CanPowerDown) { PowerDown(); Finish(true); return; }`.
3. `public void PowerDown()` — no-op unless `IsActivated`; clears `IsActivated`, screen →
   `DeadColor`, `EmitSignalDeactivated()`, `NotifyPromptChanged()`.
4. `private void Complete()` → `protected virtual void Complete()`; `StartFailFlash()` →
   `protected`.
5. `protected void RefuseActivation()` — flash + abort the attempt **without** setting
   `_deadNoPower` (so the player can retry after freeing the circuit) + `EmitSignalActivationRefused()`.

Nothing else in the class moves. `Powered`/`FailedNoPower`/`_deadNoPower` (the prologue's dead fan
panel) keep their exact semantics.

### 12. Edited: `scripts/player/Player.cs` — two additive methods

- `public void Kill()` — the hazard death. Extracted from the KO branch of `TakeHit` (which then
  calls the same private `KnockOut()`), so there is one KO path: sets `_knockedOut`, `HitboxOff()`,
  `TransitionToOrRestart(PlayerState.StateKO)`, `EmitSignalKnockedOut()`. Does **not** touch
  `GameState.Energy` — gas is not an energy cost.
- `public void Revive()` — the respawn: `_knockedOut = false`, `Velocity = Vector2.Zero`,
  `_z = 0`, `_zVelocity = 0`, `HitboxOff()`, `Flashlight.SetOn(false)`, `ResetPose()`,
  `StateMachine.TransitionToOrRestart(PlayerState.StateIdle)`, `UpdateVisual()`.
  Forcing the lamp off is deliberate: it guarantees a respawn next to a gas pocket cannot re-ignite
  it in the same second, and it re-teaches the rule.

No export, no balance value, no signal changes.

### 13. Edited: `scripts/levels/LevelBase.cs` — checkpoints, respawn, companion

| new `[Export]` | Type | Default | Meaning |
|---|---|---|---|
| `Checkpoints` | `Node2D?` | `null` | container whose `Checkpoint` children are connected in `_Ready` |
| `Companion` | `Companion?` | `null` | warped along on room changes and respawns |
| `RespawnDelay` | `float` | `0.9` | real s between death and respawn (mirrors `RestartDelay`) |
| `MinRespawnEnergy` | `float` | `30` | energy floor on respawn, so a death spiral is impossible |

| new signal | Parameters | When |
|---|---|---|
| `CheckpointArmed` | `(Checkpoint checkpoint)` | the hero reached a new checkpoint |
| `Respawned` | `()` | after a soft respawn (a level may reset its own puzzle state here) |

- `_Ready`: iterate `Checkpoints`' children once, connect each `Checkpoint.Reached`; `_ExitTree`
  disconnects.
- `OnCheckpointReached(cp)` → `_checkpoint = cp`, `_checkpointEnergy = GameState.Instance.Energy`,
  `EmitSignalCheckpointArmed(cp)`.
- `OnPlayerKnockedOut` (unchanged shape) → the timer's callback picks the route:
  `_checkpoint is null ? RestartLevel() : RespawnAtCheckpoint()`. **With no checkpoint the behaviour
  is exactly today's**, so `TestRoom`, `Level00_Prologue` and `level_prologue.gd` are untouched.
  The timer keeps `processAlways: false, ignoreTimeScale: true` (never respawn under a pause menu,
  never stretch the delay with a hit-stop).
- `public void RespawnAtCheckpoint()` — `HitStop.Cancel()`, `GetTree().Paused = false`,
  `Player.Revive()`, `Player.GlobalPosition = cp.GlobalPosition + cp.RespawnOffset`,
  `if (cp.Room is not null) ApplyRoomBounds(cp.Room)`,
  `GameState.Instance.Energy = cp.RestoresFullEnergy ? MaxEnergy : Mathf.Max(_checkpointEnergy, MinRespawnEnergy)`,
  `Companion?.WarpBehind()`, `EmitSignalRespawned()`. No scene reload, no `ResetRun()`.
- `ApplyRoomBounds(room)` gains one line: `Companion?.WarpBehind()` after the hero's band is set.

---

## File-level change list

### `scenes/`
| File | New/Edited | Intent |
|---|---|---|
| `scenes/props/PoweredMachine.tscn` | new | the generic circuit machine panel (body, screen, run light, reach shape) — instanced per machine with different exports |
| `scenes/props/Hoist.tscn` | new | the exit cage: machine panel + `BoardingArea` |
| `scenes/props/DebrisPile.tscn` | new | blocker + `Hurtbox` + rubble + dust; the heavy-attack target |
| `scenes/actors/Companion.tscn` | new | Дан: rig (DanSuit/Slim), shadow, bubble label, `RESET`/`idle`/`walk`, 2-state machine |
| `scenes/levels/TestMine.tscn` | new | the one-room fixture wiring every mechanic together |
| `scenes/levels/TestRoom.tscn` | **unchanged** | deliberately: seven smoke scripts measure it |
| `scenes/levels/Level00_Prologue.tscn` | **unchanged** | T-07s-b owns it |

### `scripts/`
| File | New/Edited | Intent |
|---|---|---|
| `scripts/core/PowerCircuit.cs` | new | the emergency bus: capacity, registration, refuse-and-name |
| `scripts/props/IClearable.cs` | new | 2-member contract shared by hazards and blockages |
| `scripts/props/PoweredMachine.cs` | new | `PowerPanel` + circuit request + permanent clearing of its targets |
| `scripts/props/Hoist.cs` | new | the exit machine: whole circuit, boarding area, `Departed` |
| `scripts/props/GasZone.cs` | new | haze, warning window, ignition, permanent clearing |
| `scripts/props/DebrisPile.cs` | new | `IHittable` blockage cleared by heavy hits and/or a machine |
| `scripts/levels/CaveIn.cs` | new | scripted collapse: seals the way back, shakes, hurries |
| `scripts/levels/Checkpoint.cs` | new | one-shot respawn anchor with its room and energy policy |
| `scripts/levels/TestMine.cs` | new | the fixture's own wiring, debug label, Дан's lines |
| `scripts/actors/Companion.cs` | new | the follower body, API (`Say`, `WarpBehind`, `HoldAt`) |
| `scripts/actors/CompanionState.cs` | new | shared base (resolves the owner, animation/state names) |
| `scripts/actors/CompanionFollow.cs` | new | trail / catch up / stop, three anti-stuck failsafes |
| `scripts/actors/CompanionWait.cs` | new | walk to a scripted spot, `Arrived`, hold |
| `scripts/props/PowerPanel.cs` | edited | `CanPowerDown`, `PowerDown()`, `Deactivated`, `Complete()` → `protected virtual`, `RefuseActivation()` — defaults unchanged |
| `scripts/player/Player.cs` | edited | `Kill()`, `Revive()`; KO branch of `TakeHit` extracted into the shared `KnockOut()` |
| `scripts/levels/LevelBase.cs` | edited | `Checkpoints`/`Companion`/`RespawnDelay`/`MinRespawnEnergy`, `CheckpointArmed`/`Respawned`, `RespawnAtCheckpoint()`, companion warp in `ApplyRoomBounds` |
| `scripts/art/Palette.cs` | edited | **one** new entry, `GasHaze = #b6c24a` (§6 «зеленувато-жовтий шар»); no existing colour touched |

### `tests/smoke/`
| File | New/Edited | Intent |
|---|---|---|
| `tests/smoke/props_circuit.gd` | new | circuit capacity, refuse-and-name, power-down, permanent clearing, hoist, **and** the `PowerPanel` defaults characterisation |
| `tests/smoke/props_gaszone.gd` | new | safe with the lamp off, warning window, cancel, ignition→KO, cleared zone is inert |
| `tests/smoke/level_mine.gd` | new | `TestMine` loads; pile resists light / falls to heavy; cave-in seals; checkpoint respawn keeps world state |
| `tests/smoke/actors_companion.gd` | new | follows, stops, catches up, warps, waits, never on the Player layer |
| every existing script | **unchanged** | `level_prologue.gd` staying byte-identical and green is the no-regression proof |

### `docs/`
| File | Intent |
|---|---|
| `docs/TASKS.md` | T-07s-a → `in_progress` → `done` + «Зроблено / Не зроблено / Рев'ю / Плейтест»; new backlog lines **T-B14** (`ConveyorPlatform` as a carrying platform), **T-B15** (on-screen circuit readout, if playtest asks), **T-B16** (share rig animations via an `AnimationLibrary` instead of copies) |
| `docs/GAME_DESIGN.md` | **no change** — the doc is the source of truth and the author edited it today |

### `project.godot` / `.csproj` / `.sln`
**No change.** Explicitly verified, because the task asked:

- **No new physics layer.** Every new area rides existing layers: `GasZone`, `Checkpoint`, `CaveIn`,
  `Hoist/BoardingArea` → `layer 0, mask 2` (Player), like `Door`/`TutorialPrompt`;
  `PoweredMachine`/`Hoist` roots → `layer 32` (6 Interactable), like `PowerPanel`;
  `DebrisPile` → `layer 1` (World) with its `Hurtbox` on `layer 4` (3 Enemy = "a `Hitbox` may hit
  this"); `Companion` → `layer 0, mask 1`. Free bit 8 stays free.
- **No new autoload.** `PowerCircuit` is a level node (`EnemyDirector` pattern).
- **No new InputMap action.** Everything uses `interact`, `heavy_attack`, `flashlight`, `move_*`.
- **No new package reference.**

⇒ the `project-settings` skill is **not** triggered by this task, and there is no settings paragraph
to put in the commit body. If `/coder` finds it cannot avoid a `project.godot` edit, that is a
**stop-and-ask**, not a judgement call.

---

## Acceptance criteria

Circuit:
1. Given `Circuit.Capacity = 1` and `Насос` powered, when the hero completes `Витяжка`'s panel,
   then `Витяжка.IsPowered == false`, `Насос.IsPowered` is still `true`, `Circuit.Used == 1`,
   `RequestRefused(Витяжка, Насос)` was emitted exactly once, and the HUD prompt reads
   `Не хватає потужності: працює Насос`.
2. Given the refusal above, when the hero interacts with `Насос` again (`CanPowerDown = true`),
   then `Насос.IsPowered == false`, `Deactivated` was emitted once, `Circuit.Used == 0`, and a
   second attempt at `Витяжка` now succeeds (`MachinePowered(Витяжка)`, `Circuit.Used == 1`).
3. Given `Насос` was powered at least once and is now switched off, `Flood.IsCleared` is still
   `true` and its `BlockerShape.Disabled` is still `true` — **clearing is permanent**.
4. Given `Hoist.RequiresWholeCircuit == true`, `Capacity == 1` and any machine powered, the hoist's
   panel refuses and names that machine; with nothing powered it switches on and emits
   `PowerChanged(true)`.
5. Given `PowerPanel` with default exports (`CanPowerDown == false`), an activated panel has
   `CanInteract == false` and `CurrentPrompt == ActivatedPromptText` — identical to `main`.

Gas:
6. Given the hero standing inside `GasZone_Pocket` with the lamp **off** for 3 s, `Ignited` was not
   emitted and `Player.IsKnockedOut == false`.
7. Given the hero inside with the lamp **on**, `WarningStarted` is emitted within one physics frame,
   and `Ignited` is emitted after `WarningSeconds` ± 2 frames.
8. Given a warning in progress, when the lamp is switched off before `WarningSeconds` elapses, then
   `WarningStopped` is emitted, `Ignited` is not, and re-arming works (lamp on again → a fresh full
   window).
9. Given `Ignited` with `Lethal == true`, `Player.IsKnockedOut == true` and `KnockedOut` was emitted
   once; `Engine.TimeScale` is back to `1.0` within 8 frames of real time (the blast's hit-stop must
   not stick — session-01 §5).
10. Given `GasZone_Pocket.Clear()` (via `Витяжка`), the hero may stand inside with the lamp on for
    3 s with no `WarningStarted` and no `Ignited`, `IsCleared == true`, and `Monitoring == false`.

Debris and collapse:
11. Given `DebrisPile_Hand.HeavyHitsToClear = 2`, three **light** attacks that connect emit
    `Resisted` and leave `BlockerShape.Disabled == false`; two **heavy** attacks emit
    `Damaged(1)` then `Cleared`, and `BlockerShape.Disabled == true`.
12. Given a hero standing 13 px away in depth from the pile's root Y, a heavy attack lands nothing
    (`Hitbox`'s inclusive 12 px rule); at 12 px it registers.
13. Given `CaveIn_Mid` crossed once, then after `Delay` `DebrisPile_Back.BlockerShape.Disabled ==
    false` (the way back is sealed), `Collapsed` was emitted once, and crossing the trigger again
    emits nothing.

Checkpoint / respawn:
14. Given `Checkpoint_Gas` reached with `Energy = 55` and then `Player.Kill()`, after
    `RespawnDelay` (real time): the hero's position is `Checkpoint_Gas.GlobalPosition +
    RespawnOffset` ± 2 px, `Player.IsKnockedOut == false`, `CurrentStateName == "Idle"`,
    `Flashlight.IsOn == false`, `Energy == max(55, MinRespawnEnergy)`, `Respawned` was emitted once,
    and **the scene was not reloaded** (the same `TestMine` instance, `Circuit.Used` and every
    `IsCleared` unchanged).
15. Given a level with **no** checkpoint armed (`TestRoom`, the current prologue), a hero KO still
    reloads the scene after `RestartDelay` with full energy — behaviour identical to `main`.
16. Given a respawn while the pause menu is open, nothing happens until the pause is lifted.

Companion:
17. Given Дан 400 px behind the hero, after 2 s the gap is under `CatchUpDistance`; when it is under
    `FollowDistance` his `Velocity == Vector2.Zero` and he plays `idle`.
18. Given the hero walking into Дан from any side, the hero's position after `MoveAndSlide` is
    unaffected (`collision_layer == 0`) and no `Door`/`Checkpoint`/`CaveIn`/`GasZone` signal fires
    from Дан crossing it.
19. Given Дан beyond `WarpDistance` (or unable to move for `StuckSeconds`), `Warped` is emitted and
    his distance to the hero is under `FollowDistance` on the next frame.
20. Given `HoldAt(p)`, he walks to `p`, emits `Arrived` once, and stays within 12 px of `p` while
    the hero walks away; `Resume()` returns him to `Follow`.
21. `Say("текст")` emits `LineShown("текст")`, shows `Bubble` and hides it after `BubbleSeconds`;
    a paused tree pauses the countdown.

Hygiene:
22. `dotnet build` → 0 Warning, 0 Error; `godot --headless --path . --quit` → no `ERROR:`;
    `godot --headless --path . res://scenes/levels/TestMine.tscn --quit` → no `ERROR:`;
    `tools/smoke.ps1` → **19 passed, 0 failed** (15 existing + 4 new).
23. `git diff main --stat` shows no change to `project.godot`, `BlackoutLastGrid.csproj`, `.sln`,
    anything under `assets/`, `scenes/levels/TestRoom.tscn`, `scenes/levels/Level00_Prologue.tscn`
    or any existing `tests/smoke/*.gd`.

---

## Test strategy

Automated level = smoke scripts only (GdUnit4 is still an unapproved addon; do not plan on it).
Each is `extends SceneTree`, checks in the first `_process` (autoloads are not in the tree during
`_init`), prints `SMOKE <name> PASS|FAIL: <reason>` and `quit(0|1)`; the file basename equals
`NAME`. Existing traps to respect (session-01 §5, session-02 §7):

- `_settle()` after `add_child(scene_instance)` — a heavy scene makes Godot catch up 6–8 physics
  steps in one iteration;
- during a hit-stop (`Engine.time_scale == 0`) physics steps arrive with `delta == 0`; anything
  waiting on wall-clock time uses `create_timer(t, true, false, true)`;
- C# does not expose optional parameters or overloads to GDScript — the new API is therefore called
  from tests as `TryPower` is **not** callable from GDScript (an `out` parameter): tests drive the
  circuit through the panels (`Begin`/`interact`) and read `Used`, `Free`, `IsPowered` and the
  signals, which is also the honest integration path;
- headless has **no graphics and does not simulate particles**: assert `Emitting`, `Visible`,
  `Enabled`, `Modulate`, `Disabled`, `Monitoring` and colours — never pixels; a `GpuParticles2D`
  one-shot is verified by `emitting == true`, not by seeing dust;
- comparing colours read back from a `.tscn` needs a tolerance (`_color_approx`, the T-07i-b lesson);
- a smoke script that hangs must `quit(1)` on a `MAX_FRAMES` counter rather than eat the runner's
  60 s timeout.

New scripts and their assertions:

**`tests/smoke/props_circuit.gd`** (new-feature coverage + characterisation of the edited class)
1. `PowerPanel` **defaults unchanged**: instance `scenes/props/PowerPanel.tscn`,
   `CanPowerDown == false`, complete its sequence, then `CanInteract == false` and
   `CurrentPrompt == ActivatedPromptText`; `Powered = false` still yields `FailedNoPower` and the
   permanent «Обезструмлена». *(This is the characterisation test the architect rules demand before
   a change to existing behaviour — it must pass on `main` too.)*
2. `TestMine`: `Circuit.Capacity == 1`, `Used == 0`, three machines + hoist registered
   (`Machines.size() == 4`).
3. Power `Насос` by walking the hero in and tapping `interact`: `MachinePowered`, `Used == 1`,
   `Flood.IsCleared == true`, `Flood/CollisionShape2D.disabled == true`.
4. Try `Витяжка`: `RequestRefused` once with `blocking == Насос`; `Витяжка.IsPowered == false`;
   HUD prompt text equals the formatted overload line; `Used` still 1.
5. Power down `Насос` (`interact` again): `Deactivated`, `Used == 0`, `Flood.IsCleared` **still**
   `true`.
6. Power `Витяжка`: granted; `GasZone_Pocket.IsCleared == true`.
7. Hoist while `Витяжка` runs → refused, names «Витяжка»; power `Витяжка` down → hoist granted,
   `PowerChanged(true)`.

**`tests/smoke/props_gaszone.gd`**
Sections mirroring acceptance 6–10, plus: `InputMap.has_action("flashlight")`;
`Engine.time_scale == 1.0` at the end (and the script resets it if not); the haze `Polygon2D`'s
alpha is `> 0` before `Clear()` and `0` after `HazeFadeSeconds`; `Monitoring == false` after
`Clear()`; the zone's `_PhysicsProcess` is off when nobody is inside (asserted indirectly: no
`WarningStarted` after the hero leaves and the lamp is toggled).

**`tests/smoke/level_mine.gd`**
`TestMine` instantiates with no error; node names exist; acceptance 11–16, i.e. the pile's
light-vs-heavy discrimination (driving real `attack`/`heavy_attack` taps, not synthetic
`TakeDamage`, so the `Knockdown` discriminator is really exercised), the depth-tolerance boundary at
12/13 px, the cave-in one-shot, and the respawn that keeps `Circuit.Used` and every `IsCleared` —
plus the negative: instantiate `TestRoom`, KO the hero, and assert the old reload path still runs
(no `Respawned`).

**`tests/smoke/actors_companion.gd`**
Acceptance 17–21 plus: `collision_layer == 0` and `collision_mask == 1` on the scene root (this one
assertion prevents the whole class of escort bugs); the hero's X after walking into Дан equals the
free-walk X ± 2 px; `WarpBehind()` from `ApplyRoomBounds` (call it via `Door.Entered` on a
`TestMine` room switch or directly) leaves him within `FollowDistance`.

**Only verifiable by hand** (→ Playtest): whether the refusal message *reads* as an instruction
rather than a failure; whether the gas haze is visible enough in the dark before the first warning;
whether 0.8 s is enough time to react; whether Дан's trailing distance feels like company rather
than a duckling; whether the cave-in shake reads as danger and not as a bug; whether the respawn
feels instant; the pile's floor decal being legible in the dark.

---

## Playtest (manual QA)

Self-contained: scene paths and key names only. Keys — WASD move, Space jump, **J** light attack,
**K** heavy attack, **E** interact, **F** head lamp, Esc pause.

1. Open `scenes/levels/TestMine.tscn` and run it as the main scene (**F6**). Expected: a dark mine
   room, the hero at the left, a second, slimmer figure (Дан) just behind him, the debug label at
   the top-left reading `Контур 0/1`.
2. Walk right and stop. Expected: Дан follows, closes to roughly one body-length behind and stops;
   he never pushes you and you walk **through** him if you turn back into him.
3. Walk to the pile of timber at x≈440 and press **J** three times. Expected: sparks and hit-stop on
   each hit, the pile does **not** break. Press **K** twice. Expected: dust, a screen shake, the
   pile collapses and you can walk through where it was.
4. Stand slightly above or below the marked floor strip at the pile and press **K**. Expected:
   nothing connects — the pile is only hittable from the marked strip (this is the belt-scroll depth
   rule, not a bug).
5. Walk to the water-blue blockage at x≈700 and press **K**. Expected: nothing but the "resisted"
   feel — hands do not clear this one. Walk to the panel at x≈620 («Насос») and press **E**.
   Expected: its screen turns green, its lamp comes on, the water drains and the way is open, the
   debug label reads `Контур 1/1`.
6. Walk on to the panel at x≈960 («Витяжка») and press **E**. Expected: it does **not** switch on;
   the prompt at the bottom reads **«Не хватає потужності: працює Насос»** and its screen flashes
   red and goes back to dark.
7. Walk back to «Насос» and press **E**. Expected: its screen goes dark, its lamp goes out, the
   label reads `Контур 0/1` — **and the drained water does not come back**.
8. Return to «Витяжка» and press **E**. Expected: it switches on and the greenish-yellow haze in the
   drift ahead fades out over about a second.
9. Switch «Витяжка» back off (**E**), walk into the haze area with the lamp **off** (**F** to make
   sure it is off) and stand there for a few seconds. Expected: nothing happens; the air is visibly
   tinted but you are safe in the dark.
10. Still inside the gas, press **F**. Expected: the haze flares, Дан shouts a line, and after
    roughly a second the pocket ignites: a flash, a hard shake, the hero goes down.
11. Wait about a second. Expected: you are standing again at the checkpoint before the gas, with the
    lamp **off**, energy topped up to at least a third, **and the level did not restart** — the
    cleared pile is still cleared and the circuit label is unchanged.
12. Repeat step 10, but press **F** again quickly (within the first half-second). Expected: the haze
    calms down, no explosion. The rule is a reaction test, not a trap.
13. Switch «Витяжка» on, walk through the cleared gas to x≈1240. Expected: a rumble, a screen shake,
    and a fresh collapse **behind** you that you cannot walk back through; Дан says a line and
    stays with you.
14. Walk to the cage at x≈1720 and press **E**. Expected: refused, naming «Витяжка». Walk back to
    «Витяжка», press **E** to switch it off, return to the cage and press **E**. Expected: the cage
    powers up; stepping into it shows the departure label.
15. Press **Esc** during the gas warning. Expected: the pause menu opens, the countdown stops, the
    haze freezes; «Продовжити» resumes the countdown where it was. Press **Esc** during the second
    between the death and the respawn. Expected: no respawn until you resume.
16. Walk Дан into a wall corner on purpose and run away for three seconds. Expected: he pops back to
    just behind you rather than staying stuck; he never blocks a panel prompt or a door.
17. Open `scenes/levels/TestRoom.tscn` (**F6**). Expected: everything behaves exactly as before this
    task — dummies, guard, wave, outlet, panel, pause, lamp. Let a guard beat you to zero energy:
    the level **reloads** (there are no checkpoints here), as it always did.
18. Open `scenes/Main.tscn` (**F5**) and play the prologue as far as the fan panel. Expected: no
    change of any kind — same texts, same alarm, same doors, same fine.

---

## Review focus

`signals/decoupling` · `state machine` · `belt-scroll depth` · `GameState usage`
(secondary: `exports/tunables`, `null-safety`, `hit-stop/timescale`, `scene/tscn integrity`).

Why these four: the whole task is nodes talking through signals and `[Export]`s with no
cross-scene `GetNode` (the circuit, the machines, the zone→lamp subscription, the checkpoint chain);
the companion must be a state machine and not a pair of booleans; the debris `Hurtbox` and the
companion's follow point live or die by the depth (Y) rules; and the respawn path must not smuggle
level-local state into `GameState`.

---

## Performance & frame budget

Per-frame work introduced, all in `_PhysicsProcess` unless noted:

| Node | Cost | Bound |
|---|---|---|
| `PowerCircuit` | **none** | no `_Process`/`_PhysicsProcess`; purely signal-driven |
| `PoweredMachine` | inherits `PowerPanel`'s polling, which is already gated to an active sequence; plus a countdown while the overload prompt shows | `SetPhysicsProcess(false)` otherwise |
| `GasZone` | one float countdown, **only** while a warning is armed (≈48 frames per contact) | `SetPhysicsProcess(false)` on `Disarm`/`BodyExited`/`Clear` |
| `DebrisPile` | none | reacts to `TakeHit` only |
| `CaveIn` | none | one `SceneTreeTimer`, then `Monitoring = false` |
| `Checkpoint` | none | one-shot, `Monitoring = false` after firing |
| `Companion` | one `DistanceSquaredTo`, one clamp, one `MoveAndSlide` per step; animation choice in `_Process` and only on a change (`WalkAnimationMinSpeed`, the `GuardApproach` precedent) | one follower in the level |
| `TestMine` / `LevelBase` | label text built only when a value changed (the `TestRoom` precedent) | no per-frame string building |

Allocations: none in any `_Process`/`_PhysicsProcess` — no LINQ, no `new` arrays, no closures, no
string concatenation on the hot path. The circuit's `List<PoweredMachine>` is built once in `_Ready`;
`PoweredMachine._targets` is a cached `IClearable[]` resolved once in `_Ready` (never a per-frame
`as` cast over an exported array). Node references are all `[Export]`s — no `GetNode` anywhere per
frame, and none outside a node's own scene.

`Area2D` count added to a level: one per gas pocket, one per checkpoint, one per cave-in, one
`Hurtbox` per pile, one boarding area. All have purposeful layer/mask pairs (`mask 2` or `mask 0`),
none monitors "everything", and `Hurtbox` monitoring stays `false` (it is monitor**able**, found by
the hero's active `Hitbox` — the existing pattern).

Lights: `+1 PointLight2D` per machine (run light, `shadow_enabled = false`) and `+1` per gas pocket
(warning flare, off by default). With three machines and one pocket in `TestMine` that is four extra
lights, none with shadows — well inside the budget the prologue already carries. For T-07s-b: keep
run lights `shadow_enabled = false`, they are the first thing to cut.

y-sort: the new props go into the level's existing `y_sort_enabled` parent as **grouped** nodes
(`Props`, `Checkpoints`), not one node per piece of rubble.

Hit-stop: the only new `HitStop.Trigger` call is the gas blast, and it goes through the existing
autoload whose restore runs off the wall clock in its own `_Process` — it cannot stick even if the
hero is freed during the freeze (session-01 §5). Every new timer uses
`ignoreTimeScale: true, processAlways: false`.

---

## Risks

1. **`PowerPanel` is shared.** It is used by `TestRoom` and by the prologue's dead fan panel, and it
   is covered in depth by `props_interact.gd` (855 lines). Mitigation: every change is additive with
   a default that reproduces today's behaviour exactly; `props_interact.gd` is **not edited** and
   must stay green; `props_circuit.gd` §1 asserts the defaults explicitly.
2. **Reentrancy around `Complete()`.** The circuit is asked *before* the panel commits, so no
   handler can run inside a half-finished activation. `Release` and `Clear` are idempotent, and every
   collision-shape toggle uses `SetDeferred` (the `Door.ApplyLock` precedent) so nothing mutates the
   physics space inside a flush.
3. **The debris depth rule** (12 px, inclusive, against the pile's **root** Y) will read as "my
   heavy attack does nothing" if a pile is placed off the walk band. Mitigation: the floor decal,
   acceptance 12, playtest step 4, and an explicit rule in this plan for T-07s-b.
4. **Respawn leaves the level half-scripted.** A soft respawn does not rewind cutscenes, tutorial
   prompts or wave spawners. Mitigation: `LevelBase.Respawned` exists so a level can fix its own
   state, and the rule for T-07s-b is: no checkpoint inside a scripted beat — checkpoints go at
   segment boundaries.
5. **`Player.Revive()` and the `KO` animation.** `PlayerKO` has no exit; `Revive` transitions with
   `TransitionToOrRestart` and calls `ResetPose()` first, because `AnimationPlayer.Play` on an
   already-playing animation does not rewind (session-01 §5) and `Stop(keepState)` after `RESET`
   leaves the player without a current animation.
6. **Дан and geometry** — the classic escort failure. Three independent failsafes
   (`WarpDistance`, `StuckSeconds`, and the explicit warp from `ApplyRoomBounds`/`RespawnAtCheckpoint`),
   `collision_layer = 0` so he can never block or trigger anything, and the rule that **no progress
   is ever gated on his position** except the scripted final beat. See `## Design risks` §4.
7. **Copied animations.** `Companion.tscn` duplicates `RESET`/`idle`/`walk` from `Player.tscn`. If
   T-07i-b's rig track paths ever change, the copies rot silently. Mitigation: identical
   `Visual/Rig/...` paths, `actors_companion.gd` asserts that all three animations exist, and
   T-B16 is filed.
8. **Smoke flake T-B13.** `combat_dummy.gd` crashes about 1 run in 5 with
   `STATUS_ILLEGAL_INSTRUCTION` — a pre-existing engine flake, not a regression. If it fires during
   this task's `/verify`, re-run and record it, do not chase it here.
9. **19 smoke scripts × up to 60 s.** The suite is getting long; the new scripts should share the
   `_settle`/`_tap` helpers' shape and keep their frame budgets tight (`MAX_FRAMES`).
10. **`Palette.cs` gains a colour.** One additive entry (`GasHaze`); no existing value may change —
    `actors_rig.gd` and `level_dressing.gd` compare colours read out of scenes.

---

## Design risks

Where this puzzle can stop being fun or stop being fair. Seven items; the first four are the
author's questions, answered directly.

### 1. «Одна машина за раз» може вилитись у нудне бігання по вимиканню панелей

**Assessment: this is the real risk of the task, and the author's "refuse and name" rule makes it
sharper, not softer.** Auto-preemption would have removed the walking entirely — and with it the
moment where the player, not the game, gives something up. So the walking has to be paid for by
design, not by mechanics:

- **The refusal is an instruction, not a wall.** «Не хватає потужності: працює Насос» tells you both
  what is wrong and where to go. Nobody searches.
- **One press per switch** — the machine panels ship with `Sequence = []`, so switching on or off is
  a single `E`. Keep the §4 button-sequence repair for **one** panel in the whole level (the first
  one, as a teaching beat), never as a toll on every toggle.
- **Never re-solve anything.** Clearing is permanent (`IClearable.Clear()` is one-way). A trip back
  is at most a walk, never a repeat of a puzzle.
- **Short loops.** T-07s-b rule: a machine's panel and the obstacle it removes should be within one
  screen of each other, and the two panels that compete for the circuit should be within ~2 screens.
  A cross-level round trip for one toggle is the failure mode.
- **Cap it at three circuit machines** in the prologue (насос, витяжка, кліть). §3's table has four
  because it counts the conveyor, which this task drops. Four competing machines in a 15-minute
  tutorial level is one too many.
- **The escape hatch is one number.** `Capacity` is an `[Export]`; if playtest says the middle
  segments drag, set `Capacity = 2` there and the loops halve without touching a line of code.

**Verdict:** works with three machines and short loops. If the first playtest reads as tedious,
raise `Capacity` before adding content.

### 2. Смерть від ліхтаря в газі як несправедливий gotcha

**Assessment: as literally written in §3 — «Ліхтар у загазованій ділянці = підрив» — it *is* an
unfair gotcha, and it would sour the whole segment.** The rule is the most valuable idea in the
design (it inverts light, the game's protective resource, into the thing that kills you), so it must
stay; what has to change is the delivery. Four mitigations, all mechanical and all in this task:

1. **See it before it can hurt you.** The pocket is a visible colour of the air (§6), always, lamp
   on or off, and it brightens when you step in.
2. **A warning window, not an instant death.** `WarningSeconds = 0.8` (≈48 frames): the haze flares,
   the light pulses, Дан shouts, and only then does it ignite. Turning the lamp off or stepping out
   cancels. The player's *first* contact is meant to be a near-miss.
3. **Cost seconds, not the level.** A checkpoint immediately before every gas pocket + a soft
   respawn (no reload, world state kept, lamp forced off).
4. **Rehearsal before examination.** `WarningSeconds` and `Lethal` are `[Export]`s, so T-07s-b can
   place a shallow first pocket with a 1.5 s window and an exit two steps away — and if it still
   reads badly, `Lethal = false` turns the first contact into a flash burn (energy + knockdown)
   with one inspector click.

**Verdict:** fair with the warning window; **not** fair without it. If exactly one thing from this
section survives review, it should be the warning window.

### 3. Зворотний хід контуру наприкінці як пуста робота

**Assessment: §3's segment 5 as written will not work, and it also contradicts the author's own new
direction.** Two independent reasons:

- **It is mechanically impossible now.** «Щоб не загинути під завалами» means cave-ins seal the way
  back (`CaveIn`). You cannot walk back through a sealed drift to switch off a pump. Segment 1's
  «завал відрізає шлях назад» and segment 5's «треба пройти назад» are mutually exclusive.
- **Even if it were possible, it would be empty.** With the simplification, everything the player
  changed is permanent: the water is gone, the gas is gone. A return trip through a route with no
  hazards, no decisions and no enemies is pure travel time — placed, of all moments, at the climax
  right before the brother's death.

**Recommendation (direct):** cut the reverse run. Replace it with **one** switch-off, at the
hoist: the cage demands the whole circuit (`RequiresWholeCircuit = true`), the last machine you used
is the one still running, and its panel sits **in sight of the cage** — twenty steps, not a level.
The lesson («щоб дати світло тут, треба забрати його там») lands in its strongest possible form,
at the exact moment the player wants out most, and it costs thirty seconds instead of three minutes.
If the author wants the walk-back to survive as a *beat*, the honest version is: the last panel is
on the far side of the drift the cave-in just sealed, so the route to it is **new** (a crawl the
drained water opened), and Дан goes with you — new geometry, not re-walked geometry.

### 4. Чи не буде супутник-брат застрягати в геометрії й ламати темп

**Assessment: this is the second-biggest risk in the task, above the machines.** Escort sections
fail in three ways and each has a countermeasure here:

- **He blocks the player** → impossible by construction: `collision_layer = 0`. The hero walks
  through Дан. He also cannot be hit, cannot trigger doors, checkpoints, cave-ins or gas, and cannot
  be seen by guards (nothing masks layer 0).
- **He gets stuck on geometry** → `mask = 1` keeps him out of walls, and two failsafes recover him
  without the player noticing: `WarpDistance = 900 px` (roughly half a screen past the edge) and a
  `StuckSeconds = 2.5` "wants to move but isn't" timer. Plus an explicit `WarpBehind()` on every
  room change and every respawn, so a door or a death never separates them. The warp is cheap and
  invisible in a dark mine — the correct trade for a companion that is scenery, not a puzzle.
- **He gates progress** → the hard rule for T-07s-b: **no "wait for Дан" gate anywhere**, except the
  final scripted collapse, and there he is put in place by `HoldAt()`, not asked to walk there.
  A companion who can never be lost cannot be lost.

The remaining risk is tonal, not technical: if Дан only trots behind in silence he is furniture and
his death lands on nobody. That is why `Say()` and the `LineShown` signal are in this task even
though the *lines* are T-07s-b's — the hooks must exist so his reactions can be attached to every
event (`WarningStarted`, `Collapsed`, `MachinePowered`, `RequestRefused`) rather than to a
cutscene-only script. **Verdict: solvable, provided nothing ever waits for him.**

### 5. Обвали як несправедлива смерть

A collapse the player cannot avoid must never kill. `CaveIn` therefore has no damage exports at all:
it seals, shakes and hurries. If a "run before the roof comes down" beat is ever wanted, it belongs
in a separate mechanic with a visible, telegraphed timer — not in the node that is used a dozen times
per level.

### 6. Темрява + відсутність карти = блукання

The level is black, the only light is the hero's lamp, and the gas rule pushes the player to walk
without it. That is atmosphere; it becomes frustration the moment the player does not know **where**
to go. The mechanics here help in three ways — the machine run light (a lit, warm point visible from
far away in a black room), the checkpoint floor decal (a landmark), and the panel prompt naming the
machine to go back to. The rule for T-07s-b: every segment should have **one** warm light visible
from its entrance. If playtest shows wandering, add run lights before adding signage.

### 7. «Вимкни, щоб увімкнути» може прочитатись як поломка, а не як правило

The first refusal is the moment the whole level either teaches itself or reads as a bug. It must not
be silent, and it must not be text-only: the panel flashes red (already in `PowerPanel`), the prompt
names the culprit, and Дан should say the rule out loud once
(«Тут живлення на одну машину, Рей»). Recommendation for T-07s-b: make the **first** refusal
unavoidable by design — put the second machine where the player must try it while the first is still
running — so the lesson is taught by the level and not by a tooltip.

---

## Resolved

Routine forks decided by the agent while planning, in the spirit of
`docs/sessions/2026-09-10-session-02.md` §3 — **can be overruled by the author**:

1. **No new physics layer, no new autoload, no InputMap change** ⇒ `project.godot` untouched
   (justification in the change list).
2. **A flooded drift does not drown you** — it is a `DebrisPile` with `HeavyHitsToClear = 0`. §3 only
   ever asks the pump to make it *passable*, and a second lethal hazard in a tutorial level is one
   too many.
3. **`ConveyorPlatform` dropped** from this task (backlog T-B14); the conveyor keeps its story role
   as the ignition source.
4. **`Hoist` kept as a thin subclass** rather than "a machine instance with a flag": the exit is a
   distinct role (boarding area, `Departed`) and it is 30 lines.
5. **Machine panels ship with an empty `Sequence`** (one `E` press); the §4 button-sequence repair is
   a one-off teaching beat for T-07s-b to place, not a toll on every toggle.
6. **A respawn does not reset the circuit or re-flood anything.** `LevelBase.Respawned` lets a level
   decide otherwise.
7. **`MinRespawnEnergy = 30`** so a respawn can never hand back an unplayable run.
8. **The debris `Hurtbox` reuses layer 3 (`Enemy`)** rather than adding a `Destructible` layer and
   editing the hero's hitbox mask.
9. **No on-screen circuit readout** (backlog T-B15); the refusal message plus the machines' own
   screens and run lights carry the state.
10. **`Palette.GasHaze` added** as the only palette change, because §6 names the colour of the gas
    and the visual brief forbids literal `Color(...)` in scripts.

---

## Open questions

1. **Water.** Confirmed reading: a flooded drift **blocks**, it does not drown (see *Resolved* §2).
   If the author wants drowning after all, it is a second `GasZone`-shaped hazard and about half a
   day — say so before `/coder` runs.
2. **The conveyor as a moving platform.** Dropped here (T-B14). Reaching the upper horizon in
   T-07s-b then needs another verb — a cleared debris ramp, a ladder, or a `Door`. Which?
3. **The reverse run (§3 segment 5).** This plan recommends cutting it to one switch-off near the
   hoist (`## Design risks` §3). That is a change to a confirmed design section, so it needs the
   author's word before T-07s-b builds the segment. `GAME_DESIGN.md` is **not** edited by this task.
4. **Дан's voice.** `Say()` shows a `Label` above his head. Is a bubble the right register for this
   scene, or should his lines go through the existing `Cutscene`-style overlay (which pauses the
   game)? The plan assumes bubbles for reactions and cutscenes for beats.
5. **The prologue's fine (−20 energy) and Level 1's starting energy** remain open from session 01
   §6. Unchanged by this task; it will matter for T-08.

---

## Author decisions (2026-09-11) — these override anything above
1. **Hoist back-run — CUT.** The author accepted the plan's Design-risk (c) verdict. There is no
   walk back through the mine. Instead: the hoist is in view, the last running machine sits next to
   it, and raising the hoist means cutting power to that machine — one visible, weighty decision
   inside a single screen. Nothing is ever re-solved.
2. **Three machines, not four:** extractor, pump, hoist. `ConveyorPlatform` is dropped to the
   backlog as the plan proposed — it taught nothing new and inflated panel-running.
3. **Gas fairness — take the plan's full mitigation**, not just the minimum: ~0.8 s warning window
   (kill the lamp and you live), the air visibly tinted before entry, Dan shouting, a checkpoint
   before the pocket, and a first "rehearsal" pocket with a longer window.
4. **Circuit semantics — refuse and name the blocker**, as already planned and confirmed earlier.
5. **All player-facing text is ENGLISH** (menus, HUD, prompts, tutorial, cutscenes, Dan's lines).
   Docs stay Ukrainian. Any `[Export]` string default this task introduces must be English.
   Retranslating the existing UI is T-07s-d and runs in parallel — do not touch UI text here.
6. **Push and PR are pre-authorised** for this run; merging stays with the author.
7. Scope discipline: the author wants level 0 polished and **no next level started**.

8. **Open question 1 (water)** — confirmed as planned: a flooded drift **blocks**, it does not
   drown. No second hazard.
9. **Open question 2 (reaching the upper horizon without the conveyor)** — a **cleared debris ramp**:
   reuse `DebrisPile`, so the verb is one the player already learned on the first collapse. No new
   mechanic, and it reinforces `heavy_attack` instead of introducing a fourth system.
10. **Open question 4 (Dan's voice)** — as the plan assumes: **bubbles for reactions**, the existing
   `Cutscene` overlay for story beats. Reactions must never pause the game; a bubble that would
   collide with a HUD prompt loses to the prompt.
11. **Open question 5 (the −20 fine and Level 1's starting energy)** — stays open on purpose. The
   author's scope for this run is level 0 only, and this belongs to T-08.


## Review findings

*filled in by /reviewer*
