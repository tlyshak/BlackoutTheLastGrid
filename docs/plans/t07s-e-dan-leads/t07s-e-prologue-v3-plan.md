# Plan — t07s-e-prologue-v3 (T-07s-e · Prologue rebuilt for the third story revision: the escape from the mine, Dan leads)

- Task: [`../../TASKS.md`](../../TASKS.md) → **T-07s-e** (the level half; the companion half is
  [`t07s-e-dan-leads-plan.md`](t07s-e-dan-leads-plan.md), being implemented in parallel).
- Design: [`../../GAME_DESIGN.md`](../../GAME_DESIGN.md) → **§3 «Рівень 0 — Пролог: „Зміна“
  [ПІДТВЕРДЖЕНО 2026-09-11, третя редакція: втеча з шахти]»** (Експозиція / Хто / Чому тікають / Як /
  Кінець прологу / Структура: втеча з шахти / Прогресія (шість сегментів) / Готово, коли / Мова),
  plus §1 «Рік і експозиція», §2 (the powerbank Ray never spends), §4 (стелс як опція, ліхтар =
  ресурс), §6 (палітра рівня 0).
- Companion API this plan drives **as already present** (never re-planned here): `LeadTo(Vector2)`,
  `RunTo(Vector2)`, `SetWarning(bool)`, `OnHeroRelocated()`, `Vanish()`, `SetLampOn(bool)`, signals
  `Arrived`, `HeroReached`, `HeroLagging`, `LineShown`; the route is a `Node2D` of `Marker2D`
  children in route order (`WP_<key>`); `PH_DanLight` is his own head lamp.
- Previous prologue and everything it was reviewed for:
  [`../t07s-b-prologue-rebuild/t07s-b-prologue-rebuild-plan.md`](../t07s-b-prologue-rebuild/t07s-b-prologue-rebuild-plan.md)
  (§ *Review findings*: the depth bypass, the 220 px seal margin, the 6 px surface checkpoint, the
  cue order, the 60 s runner wall). Mechanics: [`../t07s-a-escape-mechanics/t07s-a-escape-mechanics-plan.md`](../t07s-a-escape-mechanics/t07s-a-escape-mechanics-plan.md).
- Player-facing text: **[`script-en.md`](script-en.md)** (written in parallel by the script agent).
  This plan never writes a line; it names the **event** each line hangs on. Every string the
  player sees comes from that file, in English.

Branch: `task/t-07s-e-dan-leads` (from `3657707`).

---

## Goal

Rebuild `scenes/levels/Level00_Prologue.tscn` + `scripts/levels/Level00_Prologue.cs` from the
seven-segment *escape puzzle* (methane accident, pump, extractor, sealing crew, foreman, surface
fight) into the **six-segment *escape from the mine* of GAME_DESIGN §3, third revision**: a short
exposition about 2073 before the game; the brothers at the face; Ray's **own** charge on the
conveyor motor; their blast and the dark; **two guards who come into the dark and drop their
powerbanks** (the first fight, and the first thing the player takes by force); Dan **leading** down
the drift (timber, one gas pocket, outlets); a lit drift with a **patrol** to sneak past or fight;
a dead cage with **one** circuit refusal (the drift's work lights); the cage ride; and, at the pit
head, the **armed overseer** who shoots Dan in a cutscene that plays the same way every time. Ray
walks out onto the surface with Dan's powerbank; level 1 follows. No foreman, no fine, no surface
fight, no sealing crew, no pump, no extractor, no second or third cave-in.

The level must be beatable from the exposition to `Level01_District`; the player must hit, jump,
light, kill the lamp in the gas, use a panel and pick a powerbank off a guard at least once each;
Dan must always be ahead and never make the player wait; no gate may be walked round in depth; the
player can never be locked in; Dan dies identically whatever the player did.

## Scope

### In
1. `scenes/levels/Level00_Prologue.tscn` rebuilt **in place** (Options 1): four rooms / 10 560 px,
   six segments, the placement table below; T-07i-c groups and names kept where they survive.
2. `scripts/levels/Level00_Prologue.cs` rewritten: new `Stage`, the charge → blast beat, the wave
   and the drops, Dan's route table (`LeadTo`/`LeadAtLeast`, gates on level conditions), the one
   refusal, the overseer scene, the exit.
3. **New** `scenes/ui/Exposition.tscn` ↔ `scripts/ui/Exposition.cs` — the 2073 text before the
   game, between the main menu and `Main` (Options 2); `scenes/ui/MainMenu.tscn` points New Game
   at it.
4. **New** `scenes/props/EnergyPickup.tscn` ↔ `scripts/props/EnergyPickup.cs` — a powerbank on the
   floor, `E` to take (+energy); `scripts/enemies/Guard.cs` gains `[Export] PackedScene? DropScene`
   (default `null` ⇒ byte-identical behaviour) spawned on KO (Options 3).
5. Text: every player-visible string from [`script-en.md`](script-en.md); cutscenes through the
   existing `Cutscene` overlay, Dan through `Companion.Say`.
6. Tests: `level_prologue.gd`, `level_prologue_escape.gd`, `level_seals.gd` rewritten;
   `level_dressing.gd`, `ui_menu.gd` updated; new `ui_exposition.gd`, `props_energy_pickup.gd`.
7. `docs/TASKS.md`: T-07s-e status, done-note, playtest block, backlog lines below.

### Out
- Anything in `Companion`, `CompanionLead`, `LevelBase.OnHeroRelocated`, `TestMine` — the parallel
  plan owns them. If `/coder` finds the Lead API missing a call this plan needs, that is a finding
  for the companion plan's review, not a silent edit here.
- Any change to `Guard` behaviour beyond the additive drop; any change to `WaveSpawner`, `LitZone`,
  `CaveIn`, `GasZone`, `DebrisPile`, `PowerPanel`, `PoweredMachine`, `Hoist`, `Cutscene`, `Outlet`.
- A crouch pose for Dan, a "down" animation for Dan, a gun sprite, painted art — all `PH_`.
- Dan's powerbank as a `GameState` item (T-B17 stays backlog: the bank is handed over in text and
  **never** added to `Energy`, per §2).
- Skip-all for cutscenes (T-B19). Save/load (T-09).
- `WatchZone.cs`, `scenes/props/WatchZone.tscn`, `tests/smoke/props_watchzone.gd`: **left in the
  repo, unused** (the T-B18 `Door.cs` precedent) — backlog line below.

### Out of scope → `docs/TASKS.md` backlog (exact lines for `/coder` to add)

```markdown
### T-B23 · `WatchZone` лишився без користувача · `backlog`
- Третя редакція прологу (T-07s-e) прибрала герметизаційну бригаду; `scripts/props/WatchZone.cs`,
  `scenes/props/WatchZone.tscn` і `tests/smoke/props_watchzone.gd` живуть без жодної сцени-споживача.
  Рішення як для `Door` (T-B18): лишити як будівельний блок стелсу для рівнів 2–3 або прибрати разом.

### T-B24 · Поза «лежить» для супутника · `backlog`
- Смерть Дана в пролозі показує `PH_DanDown` — статичний декал силуету на місці `Companion.Vanish()`.
  Коли буде мальований арт або `CharacterRig` отримає позу `down` (T-B08), замінити декал на анімацію
  падіння на самому `Companion` (`SetDown(bool)` за зразком `Guard`).

### T-B25 · «Продовжити» після T-09 має минати експозицію · `backlog`
- `Exposition.tscn` стоїть між меню і `Main` лише на шляху «New Game». Кнопка «Продовжити» (T-B05)
  має завантажувати `GameState.CurrentScenePath` напряму, ніколи не через експозицію.
```

---

## Design-doc conformance

Section implemented: **§3 «Рівень 0», третя редакція** — every paragraph; also §1 «Рік і
експозиція», §2 (the powerbank), §4 («стелс як опція», «ліхтар = ресурс», «зброя з рівня
підбирається» for the drops), §5 (Дан — «застрелений наглядачем»), §6 (level-0 palette, the lit
centre on the horizon).

| Requirement (task brief / §3) | Design doc | Verdict |
|---|---|---|
| exposition about 2073 before the prologue, no names, 3–5 screens | §1 «Рік і експозиція», §3 «Експозиція» | agree; a separate scene on the New Game path (Options 2) |
| Ray sets the charge (first `E`), the blast is theirs, seals the way back, lights go out | §3 «Як», segment 0–1 | agree; the charge also clears the jam ahead (Options 4) — the doc is silent on what blocks the drift before the blast, so the plan adds a gate and records it |
| two guards come into the dark; powerbanks drop; «that's ours now» | §3 «Як», segment 1, «Охорона» | agree; the fight is lit by the guards' own lamps (Options 5) |
| Dan runs first, stops, shows, calls, never returns, never hurt | §3 «Брат веде» | agree; the `Lead` contract of the companion plan |
| timber (`K`), one gas pocket in the dark, outlets | §3 segment 2, «Газ» | agree |
| lit drift, 2–3 guards with lamps, stealth in dark stripes **or** fight | §3 segment 3, «Охорона», §4 | agree; both routes are acceptance criteria |
| cage dead; **one** refusal: the drift's work lights; «won't take both» | §3 segment 4, «Головоломка — легка» | agree; `Hoist.RequiresWholeCircuit`, `Capacity = 1`, one `PoweredMachine` |
| overseer, armed, cutscene only; shoots; Dan dies always and identically; Ray leaves with the powerbank | §3 segment 5, «Брат веде», «Кінець прологу» | agree; the hero and Dan are placed by the level before the scene (Options 6) |
| surface: Ray, the mine behind, the lit centre ahead → level 1 | §3 «Кінець прологу», §6 | agree; a one-screen walk to the exit |
| no foreman, no fine, no surface fight, no crew, no pump/extractor, no upper/final collapse | §3 third revision | agree; all removed |
| everything the player sees is English | §3 «Мова» | agree |

Task and design doc agree on every row. Two places the doc is silent and the plan decides (both
recorded in *Options considered*, both reversible by one inspector field or one node): what blocks
the drift before the charge (the jam), and the gas pocket's warning window (1.2 s, Open question 1).

---

## Options considered

### 1. Rebuild the existing scene in place, or build a new one?

| Option | Trade-off |
|---|---|
| A. New `Level00_Prologue_v3.tscn` + script, old one deleted at the end | Clean slate; but a new `uid`, `Main.tscn` re-pointed, every test path changed, and the T-07i-c dressing (parallax, backdrop, ground, `Fx_*`, `Props`, vignette, `LevelFx`) would be copied by hand — 2 000 lines of `.tscn` with no diff to review. |
| **B (chosen). Rebuild `Level00_Prologue.tscn` in place: keep the T-07i-c structural groups, delete the nodes the story lost, move the ones it kept, add the new ones; shrink the world from 13 440 to 10 560 px** | Same `uid`, `Main.tscn` untouched, `git diff` reviewable per node, `level_dressing.gd` keeps its assertions (only room names and the width change). Cost: the scene carries the old node order; `/coder` must audit every `node_paths=` entry on the root. |

**What moves, what goes** (from the current scene):

| Kept and moved | Deleted |
|---|---|
| `Rooms/Room_Face` (as is), `Room_Flood` → `Room_Drift`, `Room_Gas` → `Room_Patrol`, `Room_Surface`; `Fx_Face/Flood/Gas/Surface` renamed to match; `PH_Wall_*`, `PH_Floor_*`, `Backdrop/PH_WallTone_*`, `Ground/PH_FloorTone_*` (four of six) | `Room_Upper`, `Room_Cage`, `Fx_Upper`, `Fx_Cage`, their wall/floor tones, `PH_CageShaft`/`PH_CageCable` (moved into `Room_Patrol`), `PH_Support_*` beyond x 10 560 |
| `Parallax/*`, `Foreground`, `Vignette`, `LevelFx`, `HUD`, `PauseMenu`, `Cutscene`, `UI/DebugLabel`, `Camera2D`, `EnemyDirector`, `Circuit`, `PH_WallLeft`, `PH_WallRight` (→ x 10 520) | `Pump`, `Flood`, `Extractor`, `Lights_Cage`, `GasZone_Rehearsal`, `LitZone_Crew1/2`, `PH_Crew1/2`, `PH_CrewPool_1/2`, `WatchZone_Crew`, `DebrisPile_UpperSeal`, `CaveIn_Upper`, `DebrisPile_Ramp`, `PH_HitStrip_Ramp`, `PH_RampSlope`, `DebrisPile_Final`, `CaveIn_Final`, `PH_Foreman`, `PH_LampRoomDesk`, `Checkpoint_Farewell`, `Checkpoint_Gas1/2/PastPocket/Crew/Upper/Sight/RoadPower/RoadPay/RoadDays/Cage`, `Outlet_4` |
| `Crate`, `PH_Crate_Stack`, `Tutorial/MovePrompt`, `JumpPrompt`, `FlashlightPrompt`, `HeavyPrompt`, `WorkLamps`, `Fx_Face/Conveyor` + `BlastSparks` + `BlastSparkLight`, `PH_Conveyor*`, `PH_Coal_*` | — |
| `DebrisPile_BlastSeal` (→ x 1200), `CaveIn_Blast` (scripted, `monitoring = false`), `PH_DanFallen` (→ `PH_DanDown`, surface), `DebrisPile_Timber` + `PH_HitStrip_Timber` (→ x 3300), `GasZone_Pocket_A/B` (→ x 4500/4680), `Lights_Drift` + `DriftLamps` (→ `Room_Patrol`), `Hoist` (→ x 8500), `GuardSpawner` (→ `Room_Face`, the first fight), `Outlet_1..3`, `Checkpoint_Face`, `Checkpoint_Blast` → `Checkpoint_Dark`, `Checkpoint_Flood` → `Checkpoint_Drift`, `Checkpoint_Surface`, `Dan` | — |

### 2. Where does the exposition live, and how is it not shown on every restart?

| Option | Trade-off |
|---|---|
| A. First cutscene of the level, gated by a `GameState.ExpositionSeen` flag | One scene fewer; but a new global field with save semantics (T-09), a `ResetRun()` exception, and the flag survives «Quit to Main Menu → New Game», so the second run of the *session* skips the exposition unless the menu resets it — two places to get wrong. |
| B. `Main.cs` plays it once via a static bool | Static state (the repo bans static references for co-op reasons); invisible in the editor; untestable in isolation. |
| **C (chosen). A separate scene `scenes/ui/Exposition.tscn` on the New Game path: `MainMenu.NewGameScenePath` → `Exposition.tscn` → (on `Cutscene.Finished`) `ChangeSceneToFile(Main.tscn)`** | No global state. A KO restart is `ReloadCurrentScene` on `Main` (or a checkpoint respawn without any reload) — `Exposition` is never the current scene at that point, so it plays exactly once per New Game. Cost: one tiny scene + script, one property in `MainMenu.tscn`, one assertion in `ui_menu.gd`. `E` advances screens (`Cutscene.Skippable`); skip-all stays T-B19. |

### 3. Powerbanks from guards — how are they taken?

| Option | Trade-off |
|---|---|
| A. Automatic on walk-over (`Area2D` mask 2, `BodyEntered`) | Zero friction; but the first fight is in the dark and the player may never notice a thing was taken; and it teaches nothing — the design line is «відбирає енергію», a deliberate act. |
| B. Cutscene text only («they take the guards' banks») | No mechanic, nothing to learn, nothing to miss — and the design explicitly wants a pickup («збирає повербанк з охоронця» is in «Готово, коли»). |
| **C (chosen). `EnergyPickup : Interactable` — a powerbank on the floor with its own faint glow, `E` to take, `+Amount` energy, one use, freed after** | Same verb and HUD path as `Outlet` (`E: <prompt>`), visible in the dark by its own `PH_` light, and the HUD energy bar moving is the lesson. Spawned by the guard itself on KO through `Guard.DropScene` (additive export, default `null`), so the patrol guards drop too and any later level can reuse it. Fallback if `/reviewer` refuses touching `Guard`: the level connects `Guard.KnockedOut` per guard and instantiates the pickup itself — same prefab, same test, 15 lines in the level. |

### 4. What forces the charge before the player walks on?

Nothing in §3 blocks the drift ahead of the face; if the player can walk past the conveyor
without pressing `E`, there is no blast, no dark, no guards, and the level is broken by omission.

| Option | Trade-off |
|---|---|
| A. No gate; Dan waits at the motor and calls; the `E` prompt persists | Dan's leash and calls are informational by contract — nothing physically stops a player who ignores him. A broken level is one stubborn playtester away. |
| B. `Door` (T-B18) opened by the blast | Reads as a door in a coal drift; and a door the blast *opens* is odd. |
| **C (chosen). `DebrisPile_Jam` — a loaded cart train wedged across the drift just past the motor (`HeavyHitsToClear = 0`, solid from the start), which the blast throws clear: the level calls `Jam.Clear()` in the blast handler** | A real gate at every depth (the `DebrisPile` prefab already spans the band), a diegetic reason the charge is needed at all (Ray breaks the machine «правильно» — §2), and zero new code (`IClearable.Clear()` exists). The only cost is one more pile and one line. |

### 5. How does the blast fire — a walk trigger or the charge itself?

| Option | Trade-off |
|---|---|
| A. `Charge.Activated` arms `CaveIn_Blast`'s walk trigger past the seal (the T-07s-b pattern with the 220 px margin) | The trigger would have to sit past the jam, which is closed until the blast — circular; or before the jam with the seal behind it, which puts the charge, the seal and the trigger in 300 px and leaves the hero free to walk back into the seal during `Delay`. |
| **B (chosen). `Charge.Activated` → freeze the hero and play `CUT_BLAST`; on its `Finished` the level calls `CaveIn_Blast.Collapse()` directly (public, idempotent, «a level may script a collapse without a trigger»), clears the jam, kills the work lamps, tweens the darkness** | The hero is frozen from the moment the charge is set until the rubble is solid, so he is on the open side by construction — the exact reason the reviewer found the T-07s-b blast safe. The seal sits 200 px behind the panel's reach, so a hero standing at the panel is never inside the rubble. `CaveIn_Blast` keeps its dust, rumble and shake and ships with `monitoring = false`. |

### 6. The first fight in the dark — how is it fair?

| Option | Trade-off |
|---|---|
| A. Force the flashlight on before the wave (skip the prompt, `SetOn(true)`) | Takes the toggle away from the player in the one place it is being taught. |
| B. Give `Guard.tscn` a lamp | Changes every guard in the game for one fight. |
| **C (chosen). The guards bring the light: `PH_ArenaLamp` (a `PointLight2D`, «a hand lamp set down») and `LitZone_Arena` across the whole arena band are switched on by the level on `WaveStarted` and stay on** | The fight is lit whether or not the player pressed `F`; the guards spawn aware anyway, so the `LitZone` costs nothing in stealth terms; the dropped banks glow on their own. One light, one zone, no class change. |

### 7. The patrol — how are the dark stripes made honest?

`Guard.CanSeeTarget` sees a **lit** hero at 420 px in any direction and an **unlit** one at 210 px
in front only. A pool decal that shows only the lamp (T-07s-b: 220×170) leaves a 126 px strip
that is dark to the eye and still inside the cone — the S1 class of unfairness.

| Option | Trade-off |
|---|---|
| A. Pools as drawn lamps; rely on «in front only» and face the guards away | Once the hero is past a guard he *is* in front of it and within 210 px for a second — spotted with no visible cause. |
| **B (chosen). Each guard stands at one band edge (y 310 or 590), and its `LitZone` pool is the 420 × 220 rectangle that is a superset of the 210 px cone's in-band part; the decal is the pool + the 8 px sensor radius (the S1 rule). The dark stripe is the opposite band edge (80 px deep) and the 140 px columns between pools** | What is drawn dark is dark: outside the pool the hero is unlit *and* out of the cone, whatever the guard faces; inside it he is lit and seen. Lane changes happen in the columns, which Dan walks corner by corner so the route is shown. Cost: the stripes are narrow (80 px, the hero's body is 14 px tall on the band) — deliberately tight, see *Design risks* 3. |

### 8. The overseer scene — how does the shot land on a specific screen?

| Option | Trade-off |
|---|---|
| A. Add `Cutscene.LineShown(int)` and fire the FX on line *n* | Touches `Cutscene.cs` (T-07i) and binds the level to a line index the script agent may renumber. |
| **B (chosen). Two cutscene arrays back to back — `OverseerLines` (he is there, the gun comes up) → the shot FX (muzzle flash, shake, Dan gone, the fallen decal) → `DeathLines` (the powerbank, the last words) — the `Foreman → Guard` chaining pattern the current level already uses** | No class change; the script splits its text at the shot; the FX is one handler. |

---

## Recommended approach

A single `Node2D` level, 10 560 × 1080, y-sorted, four tiled `RoomBounds`, six segments. Flow is
**signals only**; `Checkpoint.Label` stays the event key for rooms and beats (T-07s-b's structural
idea, kept). Dan is driven by a **route table** in the level — one `Marker2D` per stop under
`DanRoute`, each stop with a *gate* (`Auto` = advance on his `Arrived`; `HeroReached` = advance when
the hero comes to him; `Event` = advance on a named level event) — and by `LeadAtLeast(key)` on
every checkpoint so he is never behind the hero's progress.

- **Exposition** — `Exposition.tscn` between the menu and `Main` (Options 2).
- **Segment 0 (face)** — station light; move / jump prompts, the crate; Dan starts **past the
  crate** (he cannot jump; he is already up the drift, waving) and leads to the motor. `Charge` is a
  `PowerPanel` with the one repair `Sequence` of the level (§4's 3–4 buttons); `Jam` blocks the
  drift ahead.
- **Segment 1 (blast, dark, guards)** — `CUT_BLAST` with the hero frozen; `Collapse()`, `Jam.Clear()`,
  work lamps off, darkness → mine black, conveyor stopped; `Checkpoint_Dark`; flashlight prompt;
  the wave (2 guards, aware, lit by their own lamp), attack/heavy prompts; two `EnergyPickup`s;
  Dan's «that's ours now» on the first pickup.
- **Segment 2 (Dan leads)** — timber pile (`K` ×2), `Outlet_2`, one gas pocket (2 × 180 px) with a
  checkpoint before it; Dan reaches the pocket's edge, **his lamp goes off first**, then the shout;
  he advances only when the hero's lamp is off (`Flashlight.Toggled`), crosses dark, lamp back on.
- **Segment 3 (patrol)** — `Room_Patrol` is lit by `Lights_Drift` (`StartsPowered`); three placed
  `Guard`s in `Patrol`, pools per Options 7; Dan's lamp off, silent, corner-by-corner route in the
  stripes; stealth (no `Noticed`) or fight (guards beatable, they drop banks too).
- **Segment 4 (cage)** — `Lights_Drift`'s panel and the `Hoist` on one screen (600 px apart); cage
  refused («Not enough power: Work lights is running»), Dan's rule line; lights off → pools
  disabled, darkness → mine black, the patrol (if alive) loses its light; cage powered → Dan's
  «get in» (heard this time); boarding → `Departed`.
- **Segment 5 (overseer, surface)** — the level places the hero, Dan and the overseer at fixed
  markers behind the dark, arms `Checkpoint_Surface`, plays `CUT_OVERSEER` → shot FX + `Dan.Vanish()`
  + `PH_DanDown` → `CUT_DEATH`; `Companion = null`; the overseer leaves (export); a one-screen walk
  east to `LevelExit` → `CUT_END` → `GoToLevel(Level01_District)`.
- **Energy never gates anything** (as before): every gate is `E`, `K` or a jump; every dark
  stretch is crossable blind; outlets and pickups are comfort. `MinRespawnEnergy = 30` covers
  respawns.

### Priorities — must / nice-to-have

| # | Item | Must / nice |
|---|---|---|
| M1 | Scene skeleton: 4 rooms, checkpoints, player, Dan + `DanRoute`, HUD, pause, camera, `LevelFx`, vignette, `Circuit`, debug label; T-07i-c groups renamed | must |
| M2 | `Exposition.tscn/.cs`, `MainMenu.tscn` re-pointed, `ui_menu.gd` / `ui_exposition.gd` | must |
| M3 | Segment 0–1: charge (`Sequence`), jam, scripted blast with the hero frozen, darkness, flashlight prompt, the wave lit by the arena lamp, attack/heavy prompts | must |
| M4 | `EnergyPickup` + `Guard.DropScene`; two banks from the first fight; `props_energy_pickup.gd` | must |
| M5 | Segment 2: timber, outlet, gas pocket with Dan's lamp-off gate and the shout; both `SetLampOn` calls | must |
| M6 | Segment 3: lit drift, three guards, pools per Options 7, stealth route walkable, fight route winnable; pools disabled with the lights | must |
| M7 | Segment 4: lights ↔ cage on one screen, the one refusal, boarding | must |
| M8 | Segment 5: fixed placement, `CUT_OVERSEER` → shot FX → `CUT_DEATH`, `Vanish`, `PH_DanDown`, the surface walk, `LevelExit`, `CUT_END`, `GoToLevel` | must |
| M9 | Dan's full route table, `LeadAtLeast` on every checkpoint, respawn re-issue, silence in the patrol, calls elsewhere | must |
| M10 | Every gate spans the band and is proven un-bypassable; the seal never lands on the hero; the shaft wall | must |
| M11 | All text from `script-en.md`; cue table wired; zero Cyrillic | must |
| M12 | Tests green: three rewritten + two new + two updated, under 60 s each | must |
| N1 | Cart-train `PH_` decals on the jam (the prefab's rubble reads as a fall otherwise) | nice |
| N2 | The conveyor belt animation stopping at the blast | nice |
| N3 | `Outlet_3` after the gas | nice |
| N4 | `PH_Gun` polygon on the overseer rig and a pit-head `PH_` frame at the surface | nice |
| N5 | A `PH_` grated side drift with a warm light behind bars in segment 0 (what Dan saw — §3 «Чому тікають») | nice |
| N6 | Per-room dressing at T-07i-c density for `Room_Patrol` and `Room_Surface` | nice |

---

## GameState & save impact

- **Read / written:** `GameState.Energy` — by `Outlet` (+25, existing), by `Flashlight` (−1/s,
  existing), by `LevelBase.RespawnAtCheckpoint` (snapshot / `MinRespawnEnergy`, existing) and by
  **`EnergyPickup.Begin` (+`Amount`, new prop, default 25)**. `EnergyChanged(float)` is emitted by
  the autoload as before; the HUD listens. **The fine is gone** (`FinePenalty` removed with the
  foreman).
- **`GameState.CurrentScenePath`** — written by `Main` on boot and by `LevelBase.GoToLevel` at the
  hand-over, as today. `Exposition` does **not** write it (it is not a level; a resume must never
  land on it — T-B25).
- **`Route`, `JournalsFound`, `DistrictReputation`** — untouched.
- **No new field and no new signal on the autoload.** Dan's route key, the level `Stage`, the
  circuit's holder and the `IsCleared` flags are level-instance state, as before.
- **For T-09:** a mid-prologue save would need `Level00_Prologue.CurrentStage`, the armed
  `Checkpoint.Label`, the current route key, `PowerCircuit`'s holder, `DebrisPile.IsCleared` /
  `GasZone.IsCleared`, which `EnergyPickup`s were taken (they carry `SaveId` from `Interactable`),
  and which patrol guards are KO. Dan's powerbank → T-B17. «Continue» must bypass `Exposition` →
  T-B25.

---

## Scene & signal contract

House rules: `PH_` prefix on placeholder visuals; colours from `BlackoutLastGrid.Art.Palette`;
`z_index` per the visual brief; `Hitbox`/`Hurtbox` keep those names; every `[Export]` has a default
and a unit. Floor band **300…600 in every room**, band centre **Y = 450**, every gate at root
Y = 450 with a 320 px blocker (covers 290…610).

### A. New: `scenes/ui/Exposition.tscn` ↔ `scripts/ui/Exposition.cs`

```
Exposition (Node)                              → scripts/ui/Exposition.cs  (partial class Exposition : Node)
├── PH_Black (CanvasLayer, layer 0)
│   └── ColorRect  full-rect, Palette.OutlineDark  (a black ground under the overlay; the tree has no level here)
└── Cutscene (instance scenes/ui/Cutscene.tscn)
```

| `[Export]` | Type | Default | Meaning |
|---|---|---|---|
| `Lines` | `string[]` | `{}` | the 3–5 screens from `script-en.md` (`CUT_EXPOSITION`) |
| `NextScenePath` | `string` (`PropertyHint.File`, `*.tscn`) | `res://scenes/Main.tscn` | where the run starts |
| `Skippable` | `bool` | `true` | forwarded to `Cutscene.Skippable` |
| `Cutscene` | `Cutscene` | node ref | the overlay |

Flow: `_Ready` → `Cutscene.Skippable = Skippable; Cutscene.Finished += OnFinished; Cutscene.Play(Lines)`
(an empty array finishes deferred and goes straight to `Main` — a fixture may ship it empty).
`OnFinished` → `GetTree().CallDeferred(ChangeSceneToFile, NextScenePath)`. `_ExitTree` unsubscribes.
No `GameState` access, no input of its own (the overlay polls `interact`/`attack`). The pause
action is not handled here (no `PauseMenu` in the tree; nothing to pause).

`scenes/ui/MainMenu.tscn`: set `NewGameScenePath = "res://scenes/ui/Exposition.tscn"` on the root
(a stored property; `MainMenu.cs` untouched). `tests/smoke/ui_menu.gd:179` asserts the old value
and is updated.

### B. New: `scenes/props/EnergyPickup.tscn` ↔ `scripts/props/EnergyPickup.cs`

`partial class EnergyPickup : Interactable` — a powerbank lying where a guard fell.

```
EnergyPickup (Area2D)      collision_layer 32 (Interactable), collision_mask 0, monitoring false, monitorable true
├── CollisionShape2D       CircleShape2D r 40  (reach; the hero's InteractionArea r 36 finds it)
├── PH_Bank (Polygon2D)    a 22×12 slab, Palette.EnergyWarm, at (0, −6)
├── PH_Glow (PointLight2D) energy 0.35, texture_scale 0.5, shadow_enabled false, at (0, −8) — visible in the dark on its own
└── PH_Shadow (Polygon2D)  light_mask 1
```

| `[Export]` | Type | Default | Unit / meaning |
|---|---|---|---|
| `Amount` | `float` | `25` | energy added on pickup |
| `PromptText` (inherited) | `string` | from `script-en.md` (`PICKUP_PROMPT`) | shown as `E: <text>` by `LevelBase` |
| `FreeAfterPickup` | `bool` | `true` | `QueueFree()` deferred after `Finish(true)` (a fixture may keep it to assert) |

| Signal | Params | When |
|---|---|---|
| `Collected` | `(float amount)` | after `GameState.AddEnergy(Amount)`, before `Finish(true)` |

`Begin(player)`: `Activate()`; if already taken → `Finish(false)`; else `AddEnergy`, `EmitSignalCollected`,
`Finish(true)`, `CanInteract` becomes `false`, `QueueFree` deferred. Instantaneous like `Outlet`.
Y-sorted with everything else (origin at the floor contact). Depth: the pickup has no `Hurtbox`
and no depth rule — reach is the circle.

### C. Edited, additive: `scripts/enemies/Guard.cs`

| new `[Export]` | Type | Default | Meaning |
|---|---|---|---|
| `DropScene` | `PackedScene?` | `null` | instanced once in `MarkKnockedOut()`, **as a sibling** (`GetParent().AddChild`) at `GlobalPosition + DropOffset`, so it y-sorts with the guard under the same parent (`WaveSpawner` or the level's `Patrol`, both y-sorted). `null` ⇒ nothing, byte-identical to today. |
| `DropOffset` | `Vector2` | `(0, 6)` | px; just in front of the fallen body so the prompt does not sit on the HP label |

| new signal | Params | When |
|---|---|---|
| `Dropped` | `(Node2D drop)` | after the drop entered the tree (levels/tests) |

`Guard.tscn` is **not** edited (the default is `null`). `WaveSpawner` instances `Guard.tscn` as
is, so the level sets the drop **on the spawner's guards in `EnemySpawned`**
(`guard.DropScene = PickupScene`) and **in the scene** on the three placed patrol guards. `TestRoom`, `Level01_District`,
`enemy_guard.gd`, `enemy_wave.gd` see no change.

### D. Rebuilt: `scenes/levels/Level00_Prologue.tscn`

Root `Level00_Prologue` — `Node2D`, `y_sort_enabled = true`, script `scripts/levels/Level00_Prologue.cs`.
World **10 560 × 1080**.

#### Rooms

| `RoomBounds` | `Rect` | Floor | `Fx` | Segments |
|---|---|---|---|---|
| `Rooms/Room_Face` | `(0, 0, 2880, 1080)` | 300 / 600 | `Fx_Face` | 0 + 1 |
| `Rooms/Room_Drift` | `(2880, 0, 2880, 1080)` | 300 / 600 | `Fx_Drift` | 2 |
| `Rooms/Room_Patrol` | `(5760, 0, 2880, 1080)` | 300 / 600 | `Fx_Patrol` | 3 + 4 |
| `Rooms/Room_Surface` | `(8640, 0, 1920, 1080)` | 300 / 600 | `Fx_Surface` | 5 |

#### Placement table (the map)

`x` = world X; root Y = 450 unless stated; **gate** = spans the band.

| x | Node | Type / instance | Key values |
|---|---|---|---|
| **Room_Face — segment 0 (the face, lights on)** ||||
| 200 | `Player` | `Player.tscn` | y 480 |
| 960 | `Dan` | `Companion.tscn` | y 470, `Target = Player` — **starts past the crate** (he never crosses a `JumpableObstacle`: `collision_mask = 1` would wedge him); `_Ready` → `HoldAt(DanStart)` until the intro ends |
| 200 | `Checkpoints/Checkpoint_Face` | `Checkpoint.tscn` | `Room_Face`, `Label = "face"`, arms on frame 1 |
| 420 / 780 | `Tutorial/MovePrompt`, `JumpPrompt` | `TutorialPrompt` | kept |
| 820 | `Crate` | `JumpableObstacle` | y 450, 44×300, kept |
| 480 / 1000 / 1600 | `WorkLamps/*` | `PointLight2D` + `FlickerLight` | kept; hidden at the blast |
| 1100–1700 | `Fx_Face/Conveyor` | `Sprite2D` + `AnimationPlayer` | kept; `AnimationPlayer.Stop()` at the blast (N2) |
| 1200 | `DebrisPile_BlastSeal` | `DebrisPile.tscn` | **gate**, `StartsCleared = true`, `HeavyHitsToClear = 0` — blocker 1172…1228 |
| 1300 | `CaveIn_Blast` | `CaveIn.tscn` | `monitoring = false` (scripted only), `Blockage = DebrisPile_BlastSeal`, `Delay = 0`, `ShakeAmplitude = 26`, `ShakeSeconds = 1.6`, `Level` wired |
| 1400 | `Charge` | `PowerPanel.tscn` | `PromptText` = `CHARGE_PROMPT` (script), `Sequence = ["move_up","attack","move_down","jump"]` (**the one repair beat of the level**), `Powered = true`, `CanPowerDown = false`, `ActivatedPromptText` = `CHARGE_SET` (script). Reach r 44 ⇒ the hero's left edge ≥ 1342 while using it — 114 px clear of the seal |
| 1560 | `DebrisPile_Jam` | `DebrisPile.tscn` | **gate**, `StartsCleared = false`, `HeavyHitsToClear = 0`, `modulate` steel-grey (N1 decals) — cleared by the level on the blast |
| **Room_Face — segment 1 (blast, dark, the two guards)** ||||
| 1700 | `Checkpoints/Checkpoint_Dark` | `Checkpoint.tscn` | `Room_Face`, `Label = "dark"` (trigger 1660…1740, past the jam's blocker end 1588) |
| 1760 | `Tutorial/FlashlightPrompt` | `TutorialPrompt` | `CompletesOnAction = "flashlight"`, `Timeout = 6` |
| 2000 | `GuardWave` | `WaveSpawner.tscn` | trigger 40×400 at 2000; `EnemyScene = Guard.tscn`, `Count = 2`, `SpawnInterval = 0.6`, `SpawnAware = true`, `OneShot = true`, `LockRect = (960, 0, 1920, 1080)`, `Player`/`Director`/`Camera` wired; `SpawnPoints/Marker1` (860, −70) → world (2860, 380), `Marker2` (860, 90) → (2860, 540) — they come in from the dark right edge |
| 2400 | `LitZone_Arena` | `Area2D` + `LitZone.cs` | layer 64, shape **480 × 320** (the whole band, x 2160…2640), `CollisionShape2D.disabled = true` until `WaveStarted` |
| 2400 | `PH_ArenaLamp` | `PointLight2D` | y 430, energy 0.9, `enabled = false` until `WaveStarted`; + `PH_ArenaLampBody` polygon (a hand lamp on the floor) + `PH_ArenaPool` decal at z −20, **496 × 336** (zone + 8 px sensor radius) |
| 2200 | `Outlet_1` | `Outlet.tscn` | y 560, `Uses = 3`, `Cooldown = 8` |
| 2300 / 2360 | `Tutorial/AttackPrompt`, `HeavyPrompt` | `TutorialPrompt` | `monitoring = false` (level-triggered), `CompletesOnAction = "attack"` / `"heavy_attack"` |
| **Room_Drift — segment 2 (Dan leads)** ||||
| 2920 | `Checkpoint_Drift` | `Checkpoint.tscn` | `Room_Drift`, `Label = "drift"` |
| 3300 | `DebrisPile_Timber` | `DebrisPile.tscn` | **gate**, `HeavyHitsToClear = 2`, `PH_HitStrip_Timber` at (3300, 450) |
| 3700 | `Outlet_2` | `Outlet.tscn` | y 560 |
| 4200 | `Checkpoint_GasNear` | `Checkpoint.tscn` | `Room_Drift`, `Label = "gas_near"` — **the checkpoint before the pocket** |
| 4500 / 4680 | `GasZone_Pocket_A` / `_B` | `GasZone.tscn` ×2 | 180 × 320 each ⇒ one 360 px pocket (x 4410…4770), `WarningSeconds = 1.2` (Open question 1), `Room = Room_Drift` |
| 5000 | `Checkpoint_PastGas` | `Checkpoint.tscn` | `Room_Drift`, `Label = "past_gas"` |
| 5300 | `Outlet_3` | `Outlet.tscn` | y 560 (N3) |
| **Room_Patrol — segment 3 (the lit drift) + 4 (the cage)** ||||
| 5800 | `Checkpoint_Patrol` | `Checkpoint.tscn` | `Room_Patrol`, `Label = "patrol"` — the entrance checkpoint (§3) |
| 6200 / 6760 / 7320 / 7900 / 8460 | `DriftLamps/PH_DriftLamp_1..5` | `PointLight2D` | y 250, the lamp string; `DriftLamps` = `Lights_Drift.RunFx` (visible only while powered) |
| 6200 | `Patrol/Guard_1` | `Guard.tscn` | **y 310**, `Facing = −1`, `DropScene = EnergyPickup.tscn` |
| 6760 | `Patrol/Guard_2` | `Guard.tscn` | **y 590**, `Facing = −1`, `DropScene` |
| 7320 | `Patrol/Guard_3` | `Guard.tscn` | **y 310**, `Facing = −1`, `DropScene` |
| 6200 | `Patrol/LitZone_P1` | `Area2D` + `LitZone.cs` | layer 64, shape **420 × 220** centred **(6200, 410)** ⇒ x 5990…6410, y 300…520 |
| 6760 | `Patrol/LitZone_P2` | idem | centred **(6760, 490)** ⇒ x 6550…6970, y 380…600 |
| 7320 | `Patrol/LitZone_P3` | idem | centred **(7320, 410)** ⇒ x 7110…7530, y 300…520 |
| — | `PH_Decals/PH_PatrolPool_1..3` | `Polygon2D` z −20 | **436 × 236** each, centred on its zone (zone + 8 px) — the drawn light *is* the detection rectangle |
| 7700 | `Checkpoint_Cage` | `Checkpoint.tscn` | `Room_Patrol`, `Label = "cage"` (170 px past pool 3) |
| 7900 | `Lights_Drift` | `PoweredMachine.tscn` | `DisplayName = "Work lights"`, **`StartsPowered = true`**, `CanPowerDown = true`, `ClearTargets = []`, `RunFx = DriftLamps`, `Circuit` wired |
| 8500 | `Hoist` | `Hoist.tscn` | `RequiresWholeCircuit = true`, `CanPowerDown = false`, `DisplayName = "Cage"`, `BoardingArea` 120 × 320 at (8500, 450); **600 px from the lights panel — one screen** |
| 8500 | `PH_CageShaft`, `PH_CageCable` | `ColorRect` z −40 | moved from `Room_Cage` |
| 8640 | `PH_WallShaft` | `StaticBody2D` layer 1 / mask 0 | 40 × 400 at (8640, 450) — the shaft wall: the only way into `Room_Surface` is the cage (a teleport); a chasing guard (mask 1) can never follow |
| **Room_Surface — segment 5 (the overseer; the surface)** ||||
| 8700 | `Checkpoint_Surface` | `Checkpoint.tscn` | `Room_Surface`, `Label = "surface"`, **`monitoring = false`** — armed by code in the arrival handler (the S3 lesson: never 6 px from a trigger) |
| 8760 | `SurfaceArrival` | `[Export] Vector2` | (8760, 480) where the cage puts the hero |
| 8900 | `DanShotAt` | `[Export] Vector2` | (8900, 470); `PH_DanDown` (`Polygon2D`, z −20, hidden) at the same spot — the old `PH_DanFallen` decal, moved |
| 9160 | `Overseer` | `CharacterRig.tscn` instance in a `Node2D` | y 470, `SuitColor = Palette.GuardSuit`, facing −1, **no collision, no script**, `visible = false` until the beat; child `PH_Gun` (`Polygon2D`, N4) |
| 9120 | `PH_MuzzleFlash` | `PointLight2D` | y 410, energy 2.0, `enabled = false`; flashed for `MuzzleFlashSeconds` |
| 8640–10560 | `Parallax/PxSurface*` | `Parallax2D` | the dead TEC left, the lit centre right (kept from today's `Room_Surface`) |
| 10200 | `LevelExit` | `Area2D` | layer 0, mask 2, `monitorable = false`, shape 40 × 400 — the level connects `BodyEntered` |
| 10520 | `PH_WallRight` | `StaticBody2D` | moved from 13 400 |

Distances that matter (`/reviewer` re-measures): seal blocker end 1228 ↔ hero's left edge at the
charge ≥ 1342 (**114 px**); jam blocker end 1588 ↔ `Checkpoint_Dark` trigger start 1660;
pool columns **140 px** (6410…6550, 6970…7110); dark stripes **80 px** deep (y 521…600 beside
guards 1 and 3, y 300…379 beside guard 2); lights panel ↔ cage **600 px**.

#### Dan's route — `DanRoute` (`Node2D`, children in route order)

| Key (`WP_<key>`) | Position | Gate to the next | Notes |
|---|---|---|---|
| `charge` | (1300, 470) | `Event: Charge.Activated` | 100 px short of the panel; on the open side of the seal (1228) |
| `dark` | (1800, 470) | `Event: GuardWave.WaveCleared` | issued as `RunTo` after the blast cutscene; `SetWarning(true)` on `WaveStarted` (faces the fight, no calls), cleared on `WaveCleared` |
| `face_exit` | (2800, 470) | `HeroReached` → `LeadAtLeast("timber")` also on `Checkpoint_Drift` | |
| `timber` | (3220, 470) | `Event: TimberPile.Cleared` | 52 px short of the blocker (3272) |
| `gas_edge` | (4340, 470) | `Event: hero's lamp off` — on `Arrived`: `SetLampOn(false)`, then the shout, then `SetWarning(true)`; on `HeroReached`: advance if `!Player.Flashlight.IsOn`, else advance on `Flashlight.Toggled(false)` | 70 px before the pocket (4410) |
| `past_gas` | (4900, 470) | `HeroReached` | issued as `RunTo` (he crosses the pocket dark); on `Arrived`: `SetLampOn(true)` |
| `drift_exit` | (5700, 470) | `HeroReached` / `LeadAtLeast("patrol_in")` on `Checkpoint_Patrol` | |
| `patrol_in` | (5840, 470) | `HeroReached` | on `Arrived`: `SetLampOn(false)`, the duck line, then **silence** (`_danSilent = true`) |
| `p1` | (6250, 585) | `HeroReached` | near stripe beside guard 1 (dy 275, outside pool 1) |
| `c1` | (6480, 585) | `Auto` | column 1, near end |
| `c1b` | (6480, 315) | `Auto` | column 1, far end — the depth change is shown |
| `p2` | (6810, 315) | `HeroReached` | far stripe beside guard 2 |
| `c2` | (7040, 315) | `Auto` | |
| `c2b` | (7040, 585) | `Auto` | |
| `p3` | (7370, 585) | `HeroReached` | |
| `p3_out` | (7600, 585) | `Auto` | leaves the last pool before rising to the band centre |
| `cage` | (8420, 470) | `Event: Cage.PowerChanged(true)` → `RunTo("board")` | 80 px short of the hoist; silence ends here (the cage line); `SetLampOn(true)` on `Lights.PowerChanged(false)` |
| `board` | (8500, 470) | — | he is first at the cage |

`Auto` = the level re-leads on his `Arrived`; `HeroReached` = on his `HeroReached`; `Event` = on
the named level signal. `LeadAtLeast(key)` on every `Checkpoint.Label` (`drift → timber`,
`gas_near → gas_edge`, `past_gas → past_gas`, `patrol → patrol_in`, `cage → cage`) guarantees he is
never behind the hero's progress; `LeadTo` to the current key is a no-op, so a respawn re-issue
never re-fires `Arrived`. **No route point sits past a closed gate** (the companion plan's R1):
`charge` is on the open side of the seal (the seal falls *behind* it); `dark` is past the jam,
which is open by the time it is issued; `timber` is short of the pile; every patrol point is in a
stripe; `cage` is short of the boarding area.

### E. Rewritten: `scripts/levels/Level00_Prologue.cs`

`partial class Level00_Prologue : LevelBase`.

```csharp
public enum Stage { Intro, Face, Blast, Dark, Fight, Drift, Gas, Patrol, Cage, Shot, Surface, Ending, Done }
private enum Beat  { None, Intro, Blast, Overseer, Death, Ending }
private enum Gate  { Auto, HeroReached, Event }
```

| Signal | Params | When |
|---|---|---|
| `StageChanged` | `(string stage)` | every stage change (kept) |

| `[Export]` | Type | Default | Unit / meaning |
|---|---|---|---|
| `DarknessLit` / `DarknessMine` / `DarknessSurface` | `Color` | `#8f97a3` / `#0a0d14` / `#6b7280` | kept |
| `DarknessDrift` | `Color` | `#2b3040` | `Room_Patrol` while the work lights run (a lit drift is dim, not black) |
| `DarknessFadeSeconds` | `float` | `1.2` | s |
| `CutsceneSkippable` | `bool` | `true` | kept |
| `AmbientLineSeconds` | `float` | `8` | s after the intro before Dan's «what I saw» line |
| `MuzzleFlashSeconds` | `float` | `0.12` | s the flash light stays on |
| `ShotShakeAmplitude` / `ShotShakeSeconds` | `float` | `10` / `0.4` | px / s |
| `OverseerLeaves` | `bool` | `true` | hide the overseer after `CUT_DEATH` (Open question 2) |
| `IntroLines`, `BlastLines`, `OverseerLines`, `DeathLines`, `EndLines` | `string[]` | `{}` | one array per cutscene, from `script-en.md` |
| `Dan…Line` | `string` | from `script-en.md` | one export per cue id in the cue table (the current pattern) |
| `NextLevel` | `PackedScene` | `Level01_District.tscn` | |
| `StartRoom` / `SurfaceRoom` | `RoomBounds` | `Room_Face` / `Room_Surface` | |
| `Circuit` | `PowerCircuit` | | `Capacity = 1` |
| `Lights` | `PoweredMachine` | `Lights_Drift` | the one refusal |
| `Cage` | `Hoist` | | |
| `Charge` | `PowerPanel` | | `Activated` → the blast |
| `Jam` | `DebrisPile` | `DebrisPile_Jam` | cleared on the blast |
| `BlastCollapse` | `CaveIn` | `CaveIn_Blast` | `Collapse()` called by the level |
| `TimberPile` | `DebrisPile` | | `Resisted` / `Cleared` cues |
| `GasPockets` | `GasZone[]` | both halves | `WarningStarted` / `Ignited` |
| `GuardWave` | `WaveSpawner` | | `WaveStarted` / `EnemySpawned` / `WaveCleared` |
| `ArenaZone` | `LitZone` | | shape enabled on `WaveStarted` |
| `ArenaLamp` | `PointLight2D` | | enabled on `WaveStarted` |
| `Patrol` | `Node2D` | | children `Guard`: `SetTarget(Player, Director)` in `_Ready`, `Noticed`/`KnockedOut` connected |
| `PatrolPools` | `LitZone[]` | the three | shapes disabled on `Lights.PowerChanged(false)` |
| `PickupScene` | `PackedScene` | `EnergyPickup.tscn` | set on wave guards in `EnemySpawned` |
| `FirstOutlet` | `Outlet` | `Outlet_1` | one cue |
| `DanRoute` | `Node2D` | | the markers |
| `DanStart` | `Vector2` | `(960, 470)` | hold during the intro |
| `DanShotAt` | `Vector2` | `(8900, 470)` | |
| `SurfaceArrival` | `Vector2` | `(8760, 480)` | |
| `Overseer` | `Node2D` | | shown at the beat |
| `MuzzleFlash` | `PointLight2D` | | |
| `DanDownDecal` | `Node2D` | `PH_DanDown` | shown at the shot |
| `SurfaceCheckpoint` | `Checkpoint` | | armed by code on arrival |
| `LevelExit` | `Area2D` | | `BodyEntered` → `CUT_END` |
| `WorkLamps`, `BlastSparks`, `BlastSparkLight`, `ConveyorAnimation` (`AnimationPlayer?`) | node refs | | as today (+N2) |
| `Cutscene`, `Darkness`, `Tutorial`, `MovePrompt`, `JumpPrompt`, `FlashlightPrompt`, `AttackPrompt`, `HeavyPrompt`, `DebugLabel` | node refs | | |

Flow — signals only, no per-frame logic beyond the debug label:

- `_Ready`: `base._Ready()`, `ApplyRoomBounds(StartRoom)`, `Darkness.Color = DarknessLit`, read
  `DanRoute` into a `Dictionary<string, Vector2>` + an ordered key list; `Dan.HoldAt(DanStart)`;
  `SetTarget` on every `Patrol` guard; connect everything below; `PlayCutscene(Intro, IntroLines)`
  (empty ⇒ finishes deferred).
- Intro `Finished` → stage `Face`, `LeadTo("charge")`, `SayAfter(AmbientLineSeconds, DAN_GRATE)`.
- `CheckpointArmed(cp)` → `ApplyRoomBounds(cp.Room)`, `LeadAtLeast(key)` per label, then the beat:
  `"dark"` → stage `Dark`; `"drift"` → `Drift`; `"gas_near"` → `Gas`; `"patrol"` → `Patrol`,
  `TweenDarkness(DarknessDrift)` if `Lights.IsPowered`; `"cage"` → `Cage`.
- `Charge.Activated` → stage `Blast`, `PlayCutscene(Blast, BlastLines)` (hero frozen).
- Blast `Finished` → `BlastCollapse.Collapse()`, `Jam.Clear()`, `WorkLamps.Visible = false`,
  `ConveyorAnimation?.Stop()`, sparks on, `TweenDarkness(DarknessMine)`, `ResumeActors()`,
  `RunTo("dark")`, `SayLine(DAN_WAYBACK)`.
- `GuardWave.WaveStarted` → stage `Fight`, `ArenaZone` shape enabled (deferred), `ArenaLamp.Enabled = true`,
  `Dan.SetWarning(true)`, `AttackPrompt.Trigger()`, `SayLine(DAN_GUARDS)`.
  `EnemySpawned(enemy)` → `if (enemy is Guard g) { g.DropScene = PickupScene; g.Damaged += OnFirstGuardHit (once → HeavyPrompt.Trigger()); }`
  `WaveCleared` → `LeadTo("face_exit")`, `SayLine(DAN_LEAD)`.
- `EnergyPickup.Collected` (connected on `Guard.Dropped` for every guard) → first time `SayLine(DAN_OURS)`.
- `TimberPile.Resisted` / `Cleared` → cues; `Cleared` → `LeadTo("gas_edge")`.
- `Dan.Arrived` → route-table handler: `gas_edge` → `SetLampOn(false)`, `SayLine(DAN_GAS_WARN)`,
  `SetWarning(true)`; `past_gas` → `SetLampOn(true)`, `SayLine(DAN_GAS_PAST)`; `patrol_in` →
  `SetLampOn(false)`, `SayLine(DAN_DUCK)`, `_danSilent = true`; `cage` → `_danSilent = false`,
  `SayLine(DAN_CAGE)`; `Auto` keys → `LeadTo(next)`.
- `Dan.HeroReached` → `HeroReached` keys → `LeadTo(next)`; `gas_edge` → advance only if the lamp is
  off, else remember `_waitingForLampOff` and advance on `Player.Flashlight.Toggled(false)`.
- `Dan.HeroLagging` → `SayLine(DAN_CALL)` unless `_danSilent`.
- `GasZone.WarningStarted` → `SayLine(DAN_GAS_SHOUT / DAN_GAS_AGAIN)` — **bypasses `_danSilent`**
  (the T-07s-b nit). `Ignited` → `_diedInGas = true`.
- `Guard.Noticed` (any patrol guard, first) → `SayLine(DAN_SPOTTED)` if the script has one (may be silence).
- `Circuit.RequestRefused(Cage, Lights)` → `SayLine(DAN_RULE)`; any other refusal → `DAN_REFUSED`.
- `Lights.PowerChanged(false)` → every `PatrolPools[i]` shape `SetDeferred("disabled", true)`
  (an invisible `Area2D` keeps colliding — the T-07s-b trap), `TweenDarkness(DarknessMine)`,
  `Dan.SetLampOn(true)`, `SayLine(DAN_DARK)`. `PowerChanged(true)` (re-lit) → pools re-enabled,
  `DarknessDrift`.
- `Cage.PowerChanged(true)` → `RunTo("board")`, `SayLine(DAN_BOARD)`.
- `Cage.Departed(player)` → stage `Shot`: `Player.GlobalPosition = SurfaceArrival`,
  `ApplyRoomBounds(SurfaceRoom)`, `SetCheckpoint(SurfaceCheckpoint)`, `Dan.WarpTo(DanShotAt)`,
  `Dan.HoldAt(DanShotAt)`, `Overseer.Visible = true`, `TweenDarkness(DarknessSurface)`,
  `PlayCutscene(Overseer, OverseerLines)`.
- Overseer `Finished` → **the shot**: `ShakeCamera(ShotShakeAmplitude, ShotShakeSeconds)`,
  `MuzzleFlash.Enabled = true` + a `MuzzleFlashSeconds` timer to switch it off, `Dan.Vanish()`,
  `DanDownDecal.Visible = true`, then `PlayCutscene(Death, DeathLines)` — **on the same frame**, so
  the hero never gets a frame of control between the two.
- Death `Finished` → `Companion = null`, `_danSilent = true`, `Overseer.Visible = !OverseerLeaves`,
  stage `Surface`, `ResumeActors()`.
- `LevelExit.BodyEntered(Player)` → stage `Ending`, `PlayCutscene(Ending, EndLines)`; `Finished` →
  `Done`, `GoToLevel(NextLevel)`.
- `Respawned` → `Dan.LeadTo(currentKey)` (no-op if unchanged), and re-apply the stance of that key
  (`gas_edge` → lamp off + warning; patrol keys → lamp off); if the stage is `Shot` or later → nothing
  (Dan is gone). The armed checkpoint's room is already re-applied by `LevelBase`.
- `_ExitTree` disconnects **every** subscription above (including the per-guard and per-pickup
  ones, kept in lists), kills tweens, drops the line timer.
- Prompt priority unchanged (interactable → tutorial hint → unusable prop; nothing in a cutscene).
- `SetActorsPaused` also disables **`Patrol` and `GuardWave`** (`ProcessMode = Disabled`) so no guard
  moves during a cutscene.

### F. Dan's cue table — *where* each line fires (text in [`script-en.md`](script-en.md))

The plan owns the **events**; the script supplies one English line per row (or marks it silence).
If the script agent binds a line to a different event, `/coder` records the mapping under
*Review findings* (the T-07s-b precedent) — the script wins on *what*, this table on *when*.

| # | Cue id | Kind | Trigger (exact) |
|---|---|---|---|
| 0 | `CUT_EXPOSITION` | cutscene (3–5 screens) | `Exposition._Ready` |
| 1 | `CUT_INTRO` | cutscene (optional, may be empty) | `Level00_Prologue._Ready` |
| 2 | `DAN_MOVE` | bubble | `MovePrompt.Shown` |
| 3 | `DAN_JUMP` | bubble | `JumpPrompt.Shown` |
| 4 | `DAN_GRATE` | bubble | `AmbientLineSeconds` after the intro — what he saw behind the grate |
| 5 | `DAN_CHARGE` | bubble | `HeroReached` at `charge` — where the motor is (direction, not the button) |
| 6 | `CHARGE_PROMPT` / `CHARGE_SET` | HUD prompt | `Charge.PromptText` / `ActivatedPromptText` |
| 7 | `CUT_BLAST` | cutscene | `Charge.Activated` |
| 8 | `DAN_WAYBACK` | bubble | blast cutscene `Finished` (after `Collapse()`) |
| 9 | `DAN_LAMP` | bubble | `FlashlightPrompt.Shown` |
| 10 | `DAN_GUARDS` | bubble | `GuardWave.WaveStarted` |
| 11 | `PICKUP_PROMPT` | HUD prompt | `EnergyPickup.PromptText` |
| 12 | `DAN_OURS` | bubble | first `EnergyPickup.Collected` — «that's ours now» (§3) |
| 13 | `DAN_LEAD` | bubble | `WaveCleared` — down the drift |
| 14 | `DAN_CALL` | bubble | `HeroLagging` (any stop; never while silent or warning) |
| 15 | `DAN_TIMBER` | bubble | `TimberPile.Resisted` |
| 16 | `DAN_CLEARED` | bubble | `TimberPile.Cleared` |
| 17 | `DAN_OUTLET` | bubble | first `Outlet.Charged` |
| 18 | `DAN_GAS_WARN` | bubble, ≤ 12 chars | `Arrived` at `gas_edge`, **after** his lamp went off |
| 19 | `DAN_GAS_SHOUT` | bubble, ≤ 12 chars | any `GasZone.WarningStarted` (bypasses silence) |
| 20 | `DAN_GAS_AGAIN` | bubble | `WarningStarted` after a death here |
| 21 | `DAN_GAS_PAST` | bubble | `Arrived` at `past_gas` (lamp back on) |
| 22 | `DAN_DUCK` | bubble | `Arrived` at `patrol_in` — then silence until `cage` |
| 23 | `DAN_SPOTTED` | bubble or silence | first `Guard.Noticed` in the patrol |
| 24 | `DAN_CAGE` | bubble | `Arrived` at `cage` |
| 25 | `DAN_RULE` | bubble | `Circuit.RequestRefused(Cage, Lights)` — «won't take both» (§3) |
| 26 | `DAN_DARK` | bubble | `Lights.PowerChanged(false)` |
| 27 | `DAN_BOARD` | bubble | `Cage.PowerChanged(true)` — reachable this time |
| 28 | `CUT_OVERSEER` | cutscene | `Cage.Departed`, after the placement |
| 29 | — | FX only | the shot: flash, shake, Dan down |
| 30 | `CUT_DEATH` | cutscene | the shot, same frame |
| 31 | `CUT_END` | cutscene | `LevelExit` entered |

Dan is silent from cue 22 to cue 24 except cue 19. `SetBubbleSuppressed(true)` around every
cutscene as today (a bubble under an overlay is noise).

Text constraints the script must respect (from the current script's §0, unchanged): a bubble
≤ 40 chars, ≥ 3 s apart; the gas shout ≤ 12 chars; a cutscene screen ≤ 120 chars, 2–8 screens.

### G. Collision summary

| Node | Layer | Mask | Note |
|---|---|---|---|
| `EnergyPickup` | 32 | 0 | `Interactable` contract |
| `LitZone_Arena`, `LitZone_P1..3` | 64 | 0 | passive; the hero's `LightSensor` masks 64 |
| `PH_WallShaft`, `PH_WallRight` | 1 | 0 | walls |
| `LevelExit` | 0 | 2 | trigger |
| `Patrol/Guard_*` | 4 | 1 | `Guard.tscn` as is |
| `Dan` | 0 | 1 | unchanged |

Needs `/project-settings`: **none** — no autoload, no InputMap action, no physics layer name, no
package. `MainMenu.tscn`'s stored property is a scene edit, not a project setting.

---

## File-level change list

### `scenes/`
| File | Action | Intent |
|---|---|---|
| `scenes/levels/Level00_Prologue.tscn` | **rebuilt in place** | four rooms, six segments, the placement table; T-07i-c groups kept and renamed |
| `scenes/ui/Exposition.tscn` | **new** | the 2073 text between the menu and `Main` |
| `scenes/props/EnergyPickup.tscn` | **new** | the powerbank prefab |
| `scenes/ui/MainMenu.tscn` | **edited** | `NewGameScenePath = "res://scenes/ui/Exposition.tscn"` |
| `scenes/enemies/Guard.tscn`, `scenes/actors/Companion.tscn`, `scenes/levels/TestMine.tscn`, `TestRoom.tscn`, `Level01_District.tscn`, `scenes/Main.tscn`, `scenes/core/WaveSpawner.tscn` | untouched | `/verify` checks with `git diff --stat` (`Companion.tscn`/`TestMine.tscn` are the parallel plan's) |

### `scripts/`
| File | Action | Intent |
|---|---|---|
| `scripts/levels/Level00_Prologue.cs` | **rewritten** | the flow in §E |
| `scripts/ui/Exposition.cs` | **new** | `partial class Exposition : Node` |
| `scripts/props/EnergyPickup.cs` | **new** | `partial class EnergyPickup : Interactable` |
| `scripts/enemies/Guard.cs` | **edited, additive** | `DropScene`, `DropOffset`, `Dropped`; spawn in `MarkKnockedOut` |
| everything else under `scripts/` | untouched | `Companion*`, `LevelBase` belong to the parallel plan |

### `tests/smoke/`
| File | Action | Intent |
|---|---|---|
| `tests/smoke/level_prologue.gd` | **rewritten** | boot through `Main` (no exposition), segments 0–1, gates, the blast, the wave, the drops; ends at `Stage.Drift` |
| `tests/smoke/level_prologue_escape.gd` | **rewritten** | direct instance, segments 2–5: timber, gas (Dan's gate), patrol (both routes), the refusal, the ride, the shot ×2 positions, the exit |
| `tests/smoke/level_seals.gd` | **rewritten** | the one seal: scripted only, the hero frozen from `Activated` to `Collapsed`, never inside the rubble; the jam and the shaft wall span the band |
| `tests/smoke/level_dressing.gd` | **edited** | `ROOM_NAMES = ["Face","Drift","Patrol","Surface"]`, `LEVEL_WIDTH = 10560`, stage constant, `BlastSparks` still in `Fx_Face`; every other assertion kept |
| `tests/smoke/ui_menu.gd` | **edited** | `NewGameScenePath` == `Exposition.tscn` and it loads |
| `tests/smoke/ui_exposition.gd` | **new** | the exposition contract |
| `tests/smoke/props_energy_pickup.gd` | **new** | the pickup + the guard drop contract |
| `tests/smoke/props_watchzone.gd`, `props_circuit.gd`, `props_forcepower.gd`, `enemy_guard.gd`, `enemy_wave.gd`, `actors_companion.gd`, `level_mine.gd`, others | untouched | must stay green (`actors_companion.gd` is the parallel plan's) |

### `docs/`
| File | Action |
|---|---|
| `docs/TASKS.md` | T-07s-e level half: done-note «Зроблено / Не зроблено / Плейтест»; add T-B23…T-B25 |
| `docs/plans/t07s-e-dan-leads/t07s-e-prologue-v3-plan.md` | this file; `## Review findings` by `/reviewer` |
| `docs/plans/t07s-e-dan-leads/script-en.md` | **written by the script agent**; referenced only |
| `docs/GAME_DESIGN.md` | not edited |

### `project.godot` / `.csproj` / `.sln`
**No change.**

Order for `/coder`: (1) `EnergyPickup` + `Guard.DropScene` with `props_energy_pickup.gd` (new
behaviour, test lands with it; `enemy_guard.gd` must stay green unchanged); (2) `Exposition` +
`MainMenu.tscn` + `ui_exposition.gd` + the `ui_menu.gd` line; (3) the scene rebuild and the level
script with the three prologue scripts and `level_dressing.gd` **in the same commit-step** — they
are the characterization of what changes; (4) headless check that `TestMine`, `TestRoom`,
`Level01_District` still load silently.

---

## Acceptance criteria

Given → action → expected. `/reviewer` renders a verdict against these.

**Exposition and boot**
1. Given `MainMenu.tscn` → New Game → the current scene is `Exposition`; `Cutscene.IsPlaying`, `CurrentLine == 0`, `LineCount` = the script's screen count (3–5); every line free of Cyrillic.
2. Given the exposition → `interact` through it → the current scene becomes `Main` with `Level00_Prologue` as its child and `GameState.CurrentScenePath` = the prologue path; **`Exposition` is not in the tree**.
3. Given the level → `RestartLevel()` (reload) or a checkpoint respawn → no `Exposition` node ever appears; the intro cutscene (if any) plays again only on a full reload.

**Segment 0–1**
4. Given boot → `Stage.Intro` → `Face` after the intro; `Dan` at `DanStart` past the crate, `CurrentStateName == "Wait"` during the intro and `"Lead"` with `LeadTarget == WP_charge` after it; `Darkness.Color == DarknessLit`; `WorkLamps.Visible`.
5. Given the crate at x 820 → walking right at y 320, 450 and 580 stops before x 798; jumping crosses it (kept from today).
6. Given `DebrisPile_Jam` (x 1560) before the blast → walking right at `FloorTop + 20`, 450 and `FloorBottom − 20` stops short; `IsCleared == false`; the hero can reach the charge panel (x ≥ 1356) and its prompt reads `E: <CHARGE_PROMPT>`.
7. Given the charge sequence completed (`Charge.Activated`) → within the same frame `Stage.Blast`, `Player.ProcessMode == Disabled`, the blast cutscene playing; **`CaveIn_Blast.IsTriggered == false` until then and `monitoring == false` throughout**.
8. Given the blast cutscene finished → `BlastCollapse.HasCollapsed`, `DebrisPile_BlastSeal.IsCleared == false` and solid across the band (walk-left probes at three depths from x 1400 stop at x ≥ 1242), `DebrisPile_Jam.IsCleared == true` (walk-right passes x 1600), `WorkLamps.Visible == false`, `Darkness.Color → DarknessMine` within `DarknessFadeSeconds + 0.6`, the hero **not knocked out and his left edge > 1228**; `Dan.LeadTarget == WP_dark`, `Dan.X > Player.X`.
9. Given the flashlight prompt at 1760 → it shows once; `F` completes it; if the lamp is already on it auto-completes (kept).
10. Given the hero walks into `GuardWave` at x 2000 → `WaveStarted`; camera limits = `(960, 0, 2880, 1080)`; `ArenaLamp.Enabled == true`; `LitZone_Arena` shape enabled; `AttackPrompt.IsShown`; two `Guard`s spawned with `IsAware == true` and `DropScene != null`; `Dan.IsWarning == true`.
11. Given both guards knocked out (`TakeDamage` from the script, or real hits) → exactly two `EnergyPickup` nodes under `GuardWave`, each within 12 px of its guard's position + `DropOffset`; `WaveCleared`; camera limits restored to `Room_Face`; `Dan.IsWarning == false`, `LeadTarget == WP_face_exit`.
12. Given the hero in reach of a pickup with `Energy = 50` → the prompt is `E: <PICKUP_PROMPT>`; `interact` → `Energy == 75`, `Collected(25)` emitted, the node freed within 3 frames, the HUD prompt cleared; the first pickup makes Dan say `DAN_OURS` once (`LineShown`).
13. Given `Guard.tscn` instantiated with the default `DropScene == null` and knocked out → no child added to its parent; `enemy_guard.gd` and `enemy_wave.gd` green unchanged.

**Segment 2**
14. Given `DebrisPile_Timber` → gate at all three depths; two `heavy_attack`s from the strip clear it; a light attack fires `Resisted` and `DAN_TIMBER`; `Cleared` → `Dan.LeadTarget == WP_gas_edge`.
15. Given Dan arrived at `gas_edge` → `Dan.IsLampOn == false` (or `PH_DanLight.Enabled == false`) **before** `DAN_GAS_WARN` is shown (order asserted via `LineShown` after the lamp state), `IsWarning == true`, `Facing == +1`.
16. Given the hero reaches Dan at `gas_edge` with the lamp **on** → `LeadTarget` stays `WP_gas_edge`; given `flashlight` toggled off → within 3 frames `LeadTarget == WP_past_gas`; given the hero arrives with the lamp already off → advances on `HeroReached` at once.
17. Given Dan at `past_gas` → `IsLampOn == true`; the pocket (`GasZone_Pocket_A/B`) never saw him (`IsWarning == false` on both while he crossed).
18. Given the hero crosses x 4410…4770 with the lamp off → no `WarningStarted`, `Energy` unchanged, `Stage` reaches `Patrol` later without ever powering anything; given the lamp switched on inside → `WarningStarted` within 2 frames, `DAN_GAS_SHOUT` shown even while silent, `Ignited` after `WarningSeconds`, a soft respawn at `Checkpoint_GasNear` with the lamp off and `Energy ≥ 30`, the level instance intact, `Dan.LeadTarget` unchanged and his lamp still off.

**Segment 3 — the patrol**
19. Given the scene → for each of `LitZone_P1..3`: the shape is 420 × 220, clipped to the band it covers exactly the rectangle the decal `PH_PatrolPool_n` draws minus the 8 px sensor radius (derived from `Player/LightSensor` as `props_watchzone.gd` did); for each guard `g` at `(gx, gy)`: the opposite stripe's nearest edge is farther than `g.PerceptionRange × g.DarkPerceptionFactor` from `g` (static geometry: `|gy − stripeY| ≥ 211`).
20. **Stealth route.** Given a fresh instance, `Energy = 0`, lamp off, the hero walked (not teleported) along y 585 from x 5900 to 6440, up the column to y 315, along y 315 to 7000, down to y 585, along to 7620, then to the cage panel at y 450 → **no `Guard.Noticed`**, every guard still `Idle`, `Player.IsLit == false` throughout (sampled each frame), no KO.
21. **Fight route.** Given a fresh instance, the lamp on, the hero walked to x 6100 at y 450 → `Guard_1.Noticed` within 30 frames; given all three guards `TakeDamage`d to KO → three `EnergyPickup`s exist under `Patrol`; the cage panel is still reachable.
22. Given the patrol pools lit and `Lights_Drift.PowerDown()` → within 3 frames every pool shape `disabled == true`, the hero standing inside pool 2 reads `IsLit == false`, `DriftLamps.Visible == false`, `Darkness.Color → DarknessMine`; `ForcePower()` back → pools re-enabled.
23. Given Dan led through the patrol → his lamp is off from `patrol_in` until `Lights.PowerChanged(false)`; `HeroLagging` while silent produces **no** `LineShown`; his route points `p1`, `p2`, `p3` lie outside every pool rectangle and ≥ 211 px in depth from their guard.

**Segment 4 — the cage**
24. Given `Lights_Drift` at boot → `IsPowered == true` without input (`StartsPowered`), `Circuit.Used == 1`; the panel and `Hoist` are within one 1920 px view (`|8500 − 7900| ≤ 1120`).
25. Given the hero uses the cage while the lights run → `RequestRefused(Cage, Lights)`, the HUD prompt reads `Not enough power: Work lights is running`, `Cage.IsPowered == false`, `DAN_RULE` shown once; a second attempt shows `DAN_REFUSED`.
26. Given the lights switched off then the cage used → `Cage.IsPowered == true`, `Circuit.Used == 1`, `DAN_BOARD` shown, `Dan.LeadTarget == WP_board`; the lights panel now refuses (`Cage` blocking) and `Cage.CanPowerDown == false`.
27. Given the hero steps into `BoardingArea` → `Departed` exactly once; **`Stage.Shot`**; `Player.GlobalPosition == SurfaceArrival`; camera limits = `Room_Surface`; `ArmedCheckpoint.Label == "surface"`; `Dan.GlobalPosition == DanShotAt`; `Overseer.Visible == true`; the overseer cutscene playing; `Player.ProcessMode == Disabled`.
28. Given the same as 27 but the hero boarded from y 320 with Dan 600 px behind him (a second instance) → the positions and the cutscene state after `Departed` are **identical** to 27 (this is «the overseer shoots the same way whatever you did»).

**Segment 5 — the shot and the surface**
29. Given the overseer cutscene finished → on that frame: `MuzzleFlash.Enabled == true` (and `false` again after `MuzzleFlashSeconds + 0.1`), camera offset non-zero within 3 frames, `Dan.IsGone == true`, `Dan.Visible == false`, `PH_DanDown.Visible == true`, `DeathLines` playing, `Player.ProcessMode == Disabled` — no frame of control between the two cutscenes.
30. Given the death cutscene finished → `Stage.Surface`, `Companion == null` on the level, `Overseer.Visible == !OverseerLeaves`, the hero free; `GameState.Energy` **unchanged** by the scene (Dan's bank is never added — §2).
31. Given the hero walks east into `LevelExit` → `Stage.Ending`, `EndLines` playing; finished → `Stage.Done`, the current scene becomes `Level01_District`, `CurrentScenePath` ends with its path.
32. Given a KO on the surface (script `Kill()`) → respawn at `Checkpoint_Surface` in `Room_Surface`, never below.

**Invariants**
33. Every `DebrisPile` blocker and every `LitZone`/`GasZone`/`LevelExit`/`Checkpoint` shape spans 300…600; `PH_WallShaft` spans the band; no `_Ready` warning from any hazard.
34. Given `GameState.Energy = 0` forced at every checkpoint arming → the run still reaches `Stage.Done` (nothing needs the lamp).
35. Every `Checkpoint` arming is observed with `Dan.GlobalPosition.X ≥ Player.GlobalPosition.X − Dan.OvertakeDistance` (Dan ahead) except while `IsGone`.
36. The scene contains no `Pump`, `Extractor`, `Lights_Cage`, `WatchZone`, `CaveIn_Upper`, `CaveIn_Final`, `PH_Foreman`, `Checkpoint_Farewell`; the level script has no `FinePenalty`, `ForemanLines`, `GuardLines`.
37. Zero Cyrillic in any `string`/`string[]` export of the level, `Exposition`, every `Interactable.PromptText`, every `DisplayName`.
38. `dotnet build` 0 warnings; `godot --headless --path . --quit` and a headless load of `Level00_Prologue.tscn`, `Exposition.tscn`, `EnergyPickup.tscn` print no `ERROR:`/`WARNING:`; `git diff --stat` shows none of the untouched scenes.

---

## Test strategy

Kind of change: **new feature + behaviour change** on scenes with existing smoke scripts; only
smoke tests exist (GdUnit4 not approved). Order: the prop test lands with the prop, the exposition
test with the scene, and the three prologue scripts are rewritten in the same step as the scene
(they characterize what changes).

| Script | Proves | Budget |
|---|---|---|
| `tests/smoke/props_energy_pickup.gd` (new) | AC 12–13: the prefab contract (layer 32, reach, prompt, `+Amount`, `Collected`, freed, second `Begin` refused); `Guard.DropScene` spawns as a sibling at KO, `Dropped` emitted, `null` spawns nothing | frame-counted, < 5 s |
| `tests/smoke/ui_exposition.gd` (new) | AC 1–3: `MainMenu.NewGameScenePath` is the exposition and loads; `Exposition` plays its lines (count 3–5, English), `Finished` changes the scene to `Main` (watch `current_scene` for ≤ 60 frames), `Exposition` gone; an empty `Lines` goes straight to `Main` | < 5 s |
| `tests/smoke/level_prologue.gd` (rewritten) | AC 4–13, 33 (the face half), 35–38: boot through `Main`; intro; crate; jam gate at three depths; the charge sequence; the scripted blast with the hero frozen and on the open side; the flashlight prompt; the wave, arena light, drops, pickup, Dan's cues; ends at `Stage.Drift` | `MAX_FRAMES ≤ 6000` |
| `tests/smoke/level_prologue_escape.gd` (rewritten) | AC 14–32, 34: direct instance; timber; gas (Dan's lamp-first order, the gate on the hero's lamp, the dark crossing, one death → respawn); patrol: the **geometry assertion** (AC 19), the **walked stealth route** (AC 20), a second instance for the fight route (AC 21); pools off with the lights (AC 22); the refusal; boarding; the shot from two boarding positions (AC 27–29, two instances); the surface exit → `Level01_District`. `Energy = 0` from the gas on. | `MAX_FRAMES ≤ 6000`; if the walked stealth route (≈ 2 200 px ≈ 10 s) pushes it over, split the patrol into `tests/smoke/level_prologue_patrol.gd` — pre-authorised |
| `tests/smoke/level_seals.gd` (rewritten) | AC 7–8: the seal is scripted only (`monitoring == false` at boot; walking over `CaveIn_Blast` from either side does nothing); from `Charge.Activated` to `Collapsed` the hero's `ProcessMode` stays `Disabled`; his left edge > the seal's blocker end after; the jam and `PH_WallShaft` blockers span the band; a static margin assertion: seal blocker end + 100 ≤ the charge panel's reach start | < 15 s |
| `tests/smoke/level_dressing.gd` (edited) | the dressing contract on four rooms; keeps every existing assertion (z-table, parallax, `PH_NearBand` 0…10 560, emitter/light census with `MAX_ROOM_LIGHTS = 12`, room gating, `ImpactFx`, shake, lookahead, `Landed`) | as today |
| `tests/smoke/ui_menu.gd` (edited) | one constant | as today |

Existing scripts that must stay green untouched: `core_*`, `player_*`, `combat_dummy`,
`enemy_guard`, `enemy_wave`, `actors_rig`, `actors_companion` (parallel plan), `props_interact`,
`props_gaszone`, `props_circuit`, `props_forcepower`, `props_watchzone`, `ui_hud`, `ui_pause`,
`level_mine`.

Only verifiable by hand → Playtest: whether the 80 px stripes read as a route or as a pixel-hunt;
whether the first fight in the arena light feels fair with the lamp off; whether Dan going dark
before the pocket is understood without the line; whether the overseer scene lands; whether the
level feels short.

---

## Playtest (manual QA)

Run `scenes/ui/MainMenu.tscn` with **F5** unless a step says otherwise.

1. **New Game.** Expected: a black screen with the 2073 text, 3–5 screens, `E` advances; then the
   mine appears with the HUD reading `ENERGY 100`. Open the pause menu, choose Quit to Main Menu,
   New Game again: the exposition plays again (it is per New Game).
2. **The face.** Expected: the drift is lit; Dan is already up the drift past the crate, facing
   you, and says his lines; the move and jump prompts appear; the crate blocks a walk and yields to
   a jump; the belt runs; further right a loaded cart train blocks the drift at every depth (try
   the far wall and the near edge).
3. **The charge.** Stand at the motor panel (`E: …`). Expected: the four-button sequence, then the
   cutscene; you cannot move during it. After it: the roof is down **behind** you (no number of
   `K` presses opens it), the cart train is gone, the belt has stopped, the lamps are dead, the
   screen is mine-black, sparks fall. Dan is ahead in the dark, faintly lit by his own lamp.
4. **The lamp.** Walk right. Expected: the flashlight prompt; `F` lights the lamp and the energy
   bar starts falling. Walk on: two guards come out of the dark from the right and a hand lamp
   lights the stretch; the screen locks; the attack prompt shows `J`, and after your first hit the
   heavy prompt shows `K`. Try the fight with your lamp **off** — it must still be readable.
5. **The banks.** Expected: each fallen guard leaves a glowing powerbank; `E: …` takes it and the
   bar jumps by 25; Dan says his line on the first one. `GO →`, the lock releases.
6. **Down the drift.** Expected: Dan walks ahead and stops at the timber pile; `J` bounces off it
   and he comments; two `K` clear it; try the far wall and the near edge first — neither gets
   through. The outlet: `E: Charge` → +25 → `Drained (Ns)`.
7. **The gas.** Expected: before the tinted air Dan stops, **his lamp goes out first**, then he
   shouts. With your lamp on, walk up to him: he does not move. Press `F`: he goes into the pocket
   in the dark and waits on the far side, lamp back on. Cross with the lamp off: nothing happens.
   Now walk back in and press `F` inside: the haze flares, the shout, ~1.2 s, the blast — you wake
   at the checkpoint a few steps back, lamp off, the level not reloaded, Dan still where he was.
8. **The lit drift.** Expected: the screen brightens (the drift's lamp string is on); three guards
   stand under three lamps, each in a drawn pool of light; Dan's lamp goes off, he says one word
   and goes quiet. Follow him: along the near edge past the first guard, up the dark column, along
   the far edge past the second, down, along the near edge past the third. Nobody reacts as long as
   you stay out of the drawn light with your lamp off. Now step into a pool: they see you at once
   and come. Fight them: they go down, they drop banks.
9. **Spotted and ran.** On a fresh run, get spotted and run right. Expected: they chase (slower
   than you) into the cage screen; you can fight them there or use the panel between blows.
10. **The cage.** Expected: the lights panel and the cage on one screen. Use the cage: refused —
    *«Not enough power: Work lights is running»* — red flash, panel still usable; Dan says the rule.
    Switch the lights off: the drift goes black, the pools are gone (if a guard is still alive and
    you are unlit, he loses you), Dan's lamp comes back on. Use the cage: it powers; Dan runs to it
    and says *get in*. Step into it.
11. **The pit head.** Expected: daylight; Ray, Dan and an armed man at fixed spots — try step 11
    twice, once boarding from the far edge with Dan far behind you: the picture is the same. The
    cutscene; the shot (flash, shake); Dan is down; the second cutscene (the powerbank). The energy
    bar does **not** change. Then you are free; the man is gone (default).
12. **The surface.** Walk right. Expected: the dead plant behind, the lit centre on the horizon,
    the closing cutscene at the edge, then level 1.
13. **Pause anywhere** (`Esc`), including during the gas countdown, the wave and between a death and
    the respawn. Expected: everything waits; Resume continues; Quit to Main Menu works.
14. **Dan stress test.** Sprint past him, corner yourself, die in the gas twice, fight the patrol
    with him standing in a stripe. Expected: he is never hurt, never blocks you, never behind your
    checkpoint, never inside a lit pool, calls at most twice per stop and never during the patrol.
15. **Question for the author (yes/no):** is the level too short without the pump and the
    extractor (§ *Design risks* 6)? Is 1.2 s in the gas right, or back to 0.8?
16. **Regression.** `scenes/levels/TestMine.tscn` (**F6**), `TestRoom.tscn` (**F6**),
    `Level01_District.tscn` (**F6**) behave exactly as before.

---

## Review focus

1. **`belt-scroll depth`** — every gate and zone spans 300…600; the three pools are exactly the
   rectangles the decals draw (minus 8 px); no route point of Dan's inside a pool or past a gate.
2. **`scene/tscn integrity`** — four rooms ↔ four `Fx` groups; every `node_paths=` entry on the
   root resolves; no orphan `ext_resource`; deleted nodes deleted (no hidden `Pump` left behind);
   `CaveIn_Blast.monitoring = false`; `Checkpoint_Surface.monitoring = false`; `AttackPrompt`/
   `HeavyPrompt.monitoring = false`.
3. **`signals/decoupling`** — every subscription mirrored in `_ExitTree`, including per-guard and
   per-pickup ones; no `GetNode("../..")`; `Guard.DropScene` spawns as a sibling and nothing else.
4. **`null-safety`** — `Companion` becomes `null` at the death; every later use guarded;
   `Overseer`, `MuzzleFlash`, `ConveyorAnimation` nullable where the level can run without them.

Secondary: **`exports/tunables`** (no literal colour, time or position in the level script — every
one is an export or a marker) and **`GameState usage`** (`Energy` only through the props; the shot
adds nothing).

---

## Performance & frame budget

- **Level script per frame:** the debug-label refresh only (as today). Route lookups are
  dictionary hits at event time.
- **Guards:** three placed `Guard`s run `Idle.PhysicsUpdate` (one `LengthSquared` + a facing test)
  every physics frame for the whole level — 3 × trivial; the wave's two are freed with the level.
  `EnemyDirector` unchanged.
- **Areas:** four `LitZone`s (passive, `monitoring = false`), two `GasZone`s (physics only while
  warning), one `WaveSpawner` trigger, one `LevelExit`, checkpoints (one-shot). Pool shapes are
  *disabled*, never made invisible.
- **Lights (all `shadow_enabled = false`):** `Room_Face` peak = 3 work lamps (off after the blast)
  or arena lamp 1 + landmark 1 + sparks 1 + hero 1 + Dan 1 + 2 pickup glows + ≤ 3 `ImpactFx` = **10**;
  `Room_Patrol` peak = 5 drift lamps + hero + Dan + `Hoist.RunLight` + ≤ 3 pickup glows + ≤ 3
  `ImpactFx` = **14 if everything overlaps** — over `MAX_ROOM_LIGHTS = 12`. Rule: **no landmark
  light in `Room_Patrol`** (the drift is lit), pickup glows at energy 0.35 with a 0.5 texture scale
  are cheap, and the census counts placed lights only (`ImpactFx` and drops are transient) — the
  placed count is 8. `level_dressing.gd` asserts the placed census.
- **Emitters:** four `Fx_*` groups gated by room; `BlastSparks` in `fx_manual`; per-room ≤ 3.
- **y-sort:** `Patrol` and `GuardWave` are y-sorted containers; drops are their children; nothing
  new directly under the root except `DanRoute` (draws nothing).
- **Physics vs render:** gates, zones, the hero-close checks are physics; tweens, bubbles, the
  flash timer and the label are render/timer.
- **Scene size:** ~2 200 lines (down from 2 738); loads once.

---

## Risks

| # | Risk | Mitigation |
|---|---|---|
| R1 | The Lead API lands with a different signature or name than this plan assumes (`IsLampOn`, `OvertakeDistance`, `LeadTarget`) | `/coder` reads `Companion.cs` on the branch first and maps; a missing member is a finding for the companion plan, not an edit; AC 15/23/35 name the properties so the mismatch is caught at test time, not at playtest |
| R2 | A gate at the wrong Y re-opens the depth bypass (the T-07s-a/b failure) | uniform band; AC 5–6, 14, 33; every gate walked at three depths |
| R3 | The seal lands on a hero who is not frozen (a future edit connects a walk trigger) | `monitoring = false` asserted; `level_seals.gd` asserts `ProcessMode == Disabled` from `Activated` to `Collapsed` and the margin |
| R4 | The stripes are honest but unwalkable (80 px) | AC 20 walks them with input, not a teleport; if it fails on geometry, widen by moving the guards to y 305/595 (the pools follow) |
| R5 | A chasing guard reaches the pit head | `PH_WallShaft` (mask 1 blocks guards); `SetActorsPaused` disables `Patrol`/`GuardWave` in cutscenes |
| R6 | Dan wedged on the crate or a pile | he starts past the crate; every route point is short of every gate; the stuck warp goes to the point (companion plan AC 9) |
| R7 | The 60 s runner wall on `level_prologue_escape.gd` (the walked stealth route + four instances) | teleport everywhere else; the patrol split is pre-authorised |
| R8 | `Guard.DropScene` regresses T-06 | default `null`; `enemy_guard.gd`/`enemy_wave.gd` untouched and green; fallback = level-side spawning |
| R9 | The script agent binds a cue to another event | the cue table is normative on *when*; `/coder` records the mapping in *Review findings* |
| R10 | Light census over budget in `Room_Patrol` | no landmark there; placed count 8; `level_dressing.gd` |
| R11 | `WatchZone` looks like dead code | recorded as T-B23 |

---

## Design risks

Direct assessment, including the four the brief asks for.

### 1. Where the tutorial becomes overloaded

Segment 0–1 now teaches, in order: move, jump, a four-button panel sequence, a cutscene, the
lamp, light attack, heavy attack, a pickup — **eight verbs in the first 2 880 px**, against four in
the previous build. The panel sequence is the odd one out: it is the only *fiddly* input in the
level and it lands before the player has hit anything. Two mitigations are in the plan (the
sequence is the level's only one; the heavy prompt waits for the first hit so `J` and `K` are not
taught in the same second). What I would cut first if playtest shows fumbling: **the sequence on
the charge → `Sequence = []`** (one field), keeping the interaction as a single `E`. The design's
«3–4 кнопки» then has no home in the prologue, which I think is acceptable — it is a *repair*
mini-game and the prologue has no repair. **Medium; one field.**

### 2. Is the first fight in the dark fair?

Yes, by construction: the guards come with light (the arena lamp switches on with `WaveStarted`,
covers the whole band where the fight happens, and stays), they spawn aware (no stealth
misreading), there are two of them with the director's slot limit, `MaxHp 30` against light
damage — and the flashlight prompt sits 240 px before the trigger. The only unfair case is a
player who sprints past the prompt into the trigger *and* stands outside the pool — the guards walk
to him into his own lamp cone or into the pool. **Low.** The residual risk is the opposite: the
first fight is *easy* (two rank-and-file guards, no wave pressure), and the «that's ours now» beat
lands on a fight that felt like a formality. That is the script's problem more than the level's;
`Count = 3` is one field if the author wants it to cost something.

### 3. Does Dan give the answer away?

Checked against the companion plan's rule (stops at the obstacle, never at the switch; direction,
not solution; the fix named only after the HUD named it):
- `charge`: he stops 100 px short of the panel; the HUD prompt names the verb, Dan names the
  place. **Fine.**
- `gas_edge`: he goes dark first, then says the rule. He *is* giving the answer — but the answer is
  a survival rule with a 1.2 s window, and the design says so explicitly («Дан попереджає до входу»).
  **Intended.**
- The patrol: he walks the stripes corner by corner. This is the closest to «розжовує»: the
  stealth route is *shown*, not found. I think that is right for a prologue — the alternative is a
  player spotted with no idea why — and the fight route stays the player's choice (Dan never says
  «don't fight»). **Acceptable.**
- `cage`: he stops at the cage, not at the lights panel; the refusal text names the lights; his rule
  line («won't take both») comes *after* the refusal and states the rule, not the switch. **Fine.**
Where he *would* overstep is `DAN_CALL` if the script writes it as an instruction («kill the
lights!») — the cue table binds it to `HeroLagging`, a generic call. The script must keep it generic.

### 4. Is the level too short without the pump and the extractor?

Honest numbers: 10 560 px against 13 440; beats per segment 0–5: 4 / 4 / 3 / 2 / 2 / 3; walking
time ≈ 50 s, playing time on a first run I estimate **8–11 minutes** (against ~15 planned before),
of which cutscenes ≈ 2. Two of the previous build's three refusals are gone, and with them the two
short back-runs the reviewer called chores. What replaces them is *not* filler: a real fight, a
real stealth stretch with a fight fallback, and a death that happens on screen. I think the length
is right for a tutorial level whose ending has to land while the player still remembers the start
— the previous plan's own Design risk 5 («no emotional investment in Dan by the farewell») is
*helped* by the shorter run. If the author wants length, the cheap lever is `Room_Drift`: a
second pile or a second outlet-and-dark stretch, never a second refusal. **Do not add a fourth room
to hit a number.**

### 5. The stripes are narrow

80 px of honest darkness on a 300 px band, with the hero's body 14 px tall in depth: a player
who wanders 30 px off the edge is inside a pool and seen, and the pools are drawn to the pixel so
he sees why. This is the deliberate trade against the S1 unfairness; a wider stripe means a
smaller cone, and the cone is `Guard`'s (T-06) — one export, `DarkPerceptionFactor`, but changing
it changes every guard in the game. Dan walking the exact line is the mitigation. If playtest calls
it a pixel-hunt: move the guards to y 305 / 595 (stripes become 85–90 px) before touching the
cone. **Medium.**

### 6. The overseer scene has no gameplay tell before it

The player rides the cage and is shot at. Nothing in the level foreshadows an armed man (the
design keeps the shooter out of gameplay on purpose — «стрілець як тип ворога — пізніші рівні»). The
risk is that the death reads as a cutscene ambush rather than a consequence. The lever is text:
`DAN_GRATE` (what he saw), the patrol (the mine *is* guarded), and the overseer cutscene's first
screens. Level-side, N4 (`PH_Gun`) and the fixed staging (the man is *there* when the light comes
up, gun already raised) are all the plan can do. **Medium; script-owned.**

### 7. The pickup verb is `E`, and `E` is also the panel

A player standing between a fallen guard's bank and a panel gets whichever `Interactable` is
nearest (the hero's own rule). In the arena there is no panel; in the patrol the banks fall 600 px
from the lights panel. **Low**, but `/coder` must not place `Outlet_3` inside the patrol.

### 8. What I think will actually break in the build

In order: (1) the Lead API names (R1); (2) a `Patrol` guard's `SetTarget` forgotten so the fight
route never fires; (3) the pool shapes made *invisible* instead of *disabled*; (4) `Checkpoint_Surface`
left with its trigger on, arming 40 px too late; (5) the cutscene chain giving the hero one frame
between `Overseer` and `Death`; (6) `level_dressing.gd` «updated» by deleting an assertion.

---

## Open questions

1. **Gas warning window 1.2 s** (was 0.8 s on the real pocket, with a 1.5 s rehearsal pocket
   that no longer exists). Default if unanswered: 1.2. Reverting is one field.
2. **Does the overseer leave after the shot?** `OverseerLeaves = true` hides him after the death
   cutscene so Ray can walk east past an armed man without a fight; the script should say why
   (he goes to report, he reloads, Ray runs). Alternative: he stays, facing away.
3. **Two or three patrol guards?** Three planned (the stripe pattern needs the alternation to be
   shown twice). Two is one node fewer.
4. **A short `CUT_INTRO` at the face, or bubbles only?** The level supports both (an empty array
   costs nothing). The script decides.
5. **`Guard.DropScene` (additive on a T-06 class) vs level-side spawning.** Default: the export.
6. **Should being spotted in the patrol lock the camera to the room until the guards are down**
   (the SoR wave rule)? Not planned — a lock would forbid running; the shaft wall already keeps the
   chase out of the ending. One `WaveSpawner`-style lock if the author wants it.

---

## Author-side decisions (coordinator, 2026-09-11 — the author sleeps; may be overturned)
1. **Gas window — 1.2 s.** There is one pocket now and no rehearsal, so it carries both jobs;
   a longer window is the fair call. `[Export]`, one field to retune.
2. **The overseer does not chase.** He stays under the lamp, works the bolt, and that is all;
   the one-screen walk to `LevelExit` has no gameplay threat. Foreshadowing is script-owned.
3. **Two guards**, not three — it is the first fight and a tutorial. `Count = 3` is one field.
4. **`Coalface` stays a cutscene** as the writer built it. Yes, that is 5 + 7 screens before the
   first input — put it on the playtest sheet as a direct question to the author rather than
   second-guess the text; if it drags, the fix is cutting screens, not moving lines into bubbles.
5. **Rebuild in place**, as recommended — same `uid`, `Main.tscn` untouched.
6. **`EnergyPickup` as an `Interactable`** (E to pick up, +25) — the pickup is a decision, not a
   walk-over, which is the point of "that's ours now".
7. Script decisions already recorded at the end of `script-en.md` (Ray, Charge as cutscene, Banks
   as bubble, Overseer A, Surface A) apply here unchanged.
8. **Do not start until the Lead state has landed** (`wt/lead` → this branch). The route, the
   gates and the cue table all assume `LeadTo`/`HeroReached`/`SetWarning`/`SetLampOn`.


## Amendment (author, 2026-09-11, after the plan) — the ending changes
The author replaced the routine-confiscation shot with a **deliberate sacrifice**: at the cage the
guards (overseer + patrol) catch up from behind; the cage is slow; Dan sees Ray will not make it
if both run; he hands Ray his bank, turns back and **holds the guards on himself** until the cage
moves; they seize him, the overseer shoots; Ray sees it from the rising cage.
Consequences for this plan:
- Segment 5 / the `Overseer` section: the overseer no longer stands *at the exit ahead*; the threat
  comes **from behind**, from the drift they came through. Place guards (2 + overseer rig) at an
  export behind the cage on `Hoist.PowerChanged(true)`, keep everything scripted and identical
  whatever the player did: on boarding, freeze the hero in the cage, run the cutscene, cage lifts.
- No gameplay fight, no chase, no fail state — the scene is a cutscene as before.
- The cue table's `CUT_OVERSEER`/`CUT_DEATH` are replaced by the new scene the writer delivers
  (`script-en.md`, cutscene `Held`); `Vanish()` after it stays.
- Acceptance criterion "the death plays identically regardless of hero/Dan position" stays and
  now also covers "the guards' approach is not interactive".

## Review findings

filled in by `/reviewer`

---

Plan ready. Invoke /coder to implement.
