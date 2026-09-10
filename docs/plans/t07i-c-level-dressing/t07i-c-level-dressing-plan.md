# Plan — t07i-c-level-dressing (T-07i-c · Імпрувмент прологу №3: наповнення сцени й іграбельність)

Backlog: [`docs/TASKS.md` → T-07i-c](../../TASKS.md). Design doc: [`docs/GAME_DESIGN.md` §3 (Рівень 0 —
Пролог) and §6 (Арт-напрям)](../../GAME_DESIGN.md). Shared visual contract:
[`../t07i-visual-kit/visual-brief.md`](../t07i-visual-kit/visual-brief.md). Previous iteration of
this level: [`../t07-prologue-mine/t07-prologue-mine-plan.md`](../t07-prologue-mine/t07-prologue-mine-plan.md).

**Branch position.** Third and last of the T-07i chain: branches off **T-07i-b**, which itself
branches off **T-07i-a**. `scripts/art/Palette.cs` and `scenes/actors/CharacterRig.tscn` are
assumed to exist per the brief and are **not re-planned here**; `GetTree().Paused` (pause menu
from T-07i-a) is assumed to exist and every node added here must behave correctly under it.

---

## Goal

The prologue currently reads as a schematic: three flat `ColorRect` rooms of one tone each, a
handful of placeholder boxes, no depth behind the action, no motion in the world, and no feedback
on a landed hit beyond hit-stop. T-07i-c dresses it: a parallax rock backdrop with a foreground
plane, textured floors/walls/ceiling with per-room colour identity, a mine-dump's worth of props
(carts, scrap, battery stacks, cables, pipes, signs, puddles, broken rigs, ladders, scaffolding),
ambient life (dust in the lamp beams, a flickering work lamp, a turning extractor fan, a moving
conveyor, sparks on the dead panel, drips), combat feedback (spark + flash at the point of impact,
landing dust, screen shake on a heavy hit and on a knockdown), and playability polish (camera
lookahead, readable dark/lit zones, vignette, prompt and cutscene pacing). The one piece of
technical debt named by the task — the `Interactable`→HUD prompt forwarding duplicated in
`TestRoom` and `Level00_Prologue` — moves into `LevelBase`.

The prologue's **flow, texts, balance, perception distances and energy costs stay exactly as they
are**; this task changes what the player sees, not what the game does.

---

## Scope

### In
- `scenes/levels/Level00_Prologue.tscn` — parallax group, backdrop/ground detail, ~15 new props,
  per-room FX groups, foreground plane, vignette instance, explicit `z_index` on the existing
  background nodes.
- New reusable pieces: `scenes/fx/ImpactFx.tscn` + `scripts/fx/ImpactFx.cs`,
  `scenes/ui/Vignette.tscn`, `scripts/levels/LevelFx.cs`, `scripts/props/FlickerLight.cs`.
- `scripts/levels/LevelBase.cs` — prompt forwarding (moved), camera lookahead, `ShakeCamera`,
  per-room FX gating through `RoomBounds.Fx`.
- `scripts/levels/TestRoom.cs`, `scripts/levels/Level00_Prologue.cs` — de-duplicated against the
  new `LevelBase`; the prologue keeps its own prompt **priority** as an override.
- `scripts/levels/RoomBounds.cs` — `[Export] Node2D? Fx`.
- `scripts/player/Player.cs` — one new signal, `Landed()`.
- `scenes/levels/TestRoom.tscn` — a `LevelFx` node so combat feedback is testable in the combat
  scene too.
- `tests/smoke/level_dressing.gd` (new) + keeping every existing smoke script green.
- `docs/TASKS.md` — status, done-note, the backlog lines listed under **Out of scope**.

### Out
- Anything under `assets/` (the brief's rule stands: procedural vector art in scenes, no files).
- Balance: damage, knockback, `PerceptionRange`, `DarkPerceptionFactor`, `FlashlightDrain`,
  `FinePenalty`, hit-stop frame counts, `DepthTolerance`.
- The prologue's scripted sequence: stage order, texts, doors, alarm, guard spawn, fine, ending.
- `Palette.cs` / `CharacterRig` (T-07i-b), main menu / pause / fullscreen (T-07i-a).
- Level 1 (T-08), save/load (T-09), audio, guard patrols, gamepad glyphs.
- `project.godot`, `.csproj`, InputMap, autoloads — **no change** (see File-level change list).
- New addons or NuGet packages.

### Out of scope → `docs/TASKS.md` backlog (exact lines for `/coder` to add)
```
### T-B09 · Процедурний шейдер породи для фонів · `backlog`
- `NoiseTexture2D` дає зерно, але шви між шарами й «страти» просяться в один спільний `.gdshader`
  (uv-шум + смуги). Оцінити після T-08, коли буде другий рівень із параллаксом.

### T-B10 · Порожня зона за межами рівня в камері · `backlog`
- Камера обмежена `limit_bottom = 1080`, а контент рівня закінчується на y≈640; у T-07i-c дірку
  закриває ближня смуга породи. Загальне рішення (letterbox / `default_clear_color` / межі камери
  по висоті контенту) — окремою задачею разом із T-08.

### T-B11 · Спільний параллакс-кіт рівнів · `backlog`
- Винести шари породи з `Level00_Prologue.tscn` в окрему сцену-заготовку, коли Level 1 (T-08)
  покаже, які параметри спільні.

### T-B12 · Єдиний ефект попадання для ворогів · `backlog`
- `Dummy`/`Guard` мають власний `FlashColor`-тween; після T-07i-c спалах і іскри дає `ImpactFx`.
  Звести до одного механізму, коли з'являться нові типи ворогів.
```

---

## Design-doc conformance

**Task and design doc agree.** Mapping, requirement by requirement:

| Task requirement | `GAME_DESIGN.md` | Verdict |
|---|---|---|
| Parallax rock backdrop, 3–4 layers | §6 «глибина через 3–4 шари параллаксу» | agrees — plan uses 3 background + 1 foreground |
| Floor occupies the lower part of the screen | §6 «підлога займає нижню ~40 % екрана» | **currently violated**: level content ends at world y≈640 while the camera shows y 0…1080, so ~40 % of the screen below the floor is the engine clear colour. The near rock band (M2) is the conformance fix, not scope creep. |
| Props from the mine-dump: batteries, electronics, carts, scrap | §3 «розбирають старі акумулятори та електроніку для заводу банди» | agrees |
| Dead ventilation, unpowered panel | §3 «відрубає вентиляцію… панель обезструмлена згори» | agrees — **the fan Rey tries to start must stay motionless**; the "rotating fan" of the task is a *second, smaller extractor fan* in room 1, which still has power |
| Hit feedback: flash on the enemy, sparks | §6 «спалах на ворогові, мальовані «іскри» — у нашому світі це буквально електричні розряди» | agrees — sparks are `EnergyPale`/`EnergyAmber` electric discharge, not fire |
| Hit-stop 3–5 frames | §6 | already implemented (`HitStop` autoload); this task must not disturb it |
| Cold concrete + warm light accents | §6 palette; brief palette table | agrees — `RockDeep/RockMid/RockNear/ConcreteCold/SteelCold` for rock and steel, `EnergyAmber/EnergyPale` for lamps |
| Lighting as the main visual device | §6 «Освітлення — головний візуальний прийом» | agrees — the reason hit sparks carry their own short-lived `PointLight2D` (see Options) |
| Depth layer table | brief «Шари глибини» — hard contract | every new node gets an explicit `z_index` from that table |

No disagreement found, nothing to ask the author about before implementation. Two judgement calls
recorded above (the extractor fan; the near band as a §6 conformance fix) rather than invented
silently.

---

## Options considered

### 1. `ParallaxBackground` + `ParallaxLayer` vs `Parallax2D` (Godot 4.7)
Both exist in the local build (verified against `GodotEngine/Godot_v4.7.2-stable_mono_win64.exe`
and `GodotSharp.xml`: `Godot.Parallax2D` with `ScrollScale`, `ScrollOffset`, `RepeatSize`,
`RepeatTimes`, `LimitBegin`, `LimitEnd`, `FollowViewport`, `IgnoreCameraScroll`, `ScreenOffset`;
the editor even ships a "Convert to Parallax2D" action for the legacy nodes).

- **`ParallaxBackground`** is a `CanvasLayer`. Being its own canvas, it is **not tinted by the
  level's `Darkness` (`CanvasModulate`) and not lit by the level's `PointLight2D`s** — the mine
  backdrop would render at full brightness behind a pitch-black foreground, and the flashlight
  would not touch it. It also sits outside the level's `z_index` ordering, so the brief's depth
  table could not be enforced.
- **`Parallax2D`** (chosen) is a `Node2D` in the same canvas: darkness, lamps and the flashlight
  apply to it, `z_index` from the brief's table works, and it is the non-deprecated node in 4.3+.
  Cost: its transform is recomputed every frame, so the node's own `position` must not be authored
  by hand (use `ScreenOffset`/`ScrollOffset` and position the children instead) — a documented
  gotcha, not a blocker.

**Chosen: `Parallax2D`.**

### 2. `ShaderMaterial` (`.gdshader`) vs generated textures / vertex colours
- **Custom shader**: most expressive (rock grain, strata noise, animated haze) but adds a new file
  type nobody in the repo has yet, a compile-error surface that headless `--quit` will surface as
  `ERROR:`, and per-pixel cost across full-screen rock layers.
- **`GradientTexture2D` / `NoiseTexture2D` (built-in, generated at load) + `Polygon2D.VertexColors`
  + irregular polygon outlines** (chosen): `NoiseTexture2D` (`seamless = true`, `FastNoiseLite`)
  gives rock grain with no file and no shader; `GradientTexture2D` (linear or `fill = radial`)
  gives the light pools, the near-band falloff and the vignette; `Polygon2D.VertexColors` gives
  per-vertex gradients on strata and floors; a jagged polygon contour gives the broken rock edge.
  All of it is scene data, reviewable as a diff, zero import cost.

**Chosen: generated textures + vertex colours + polygon silhouettes; no `.gdshader` in the must
scope.** If the executor still wants rock noise beyond `NoiseTexture2D`, it goes in
`scenes/art/rock_noise.gdshader` as a nice-to-have and **the level must render correctly without
it** (see N5).

### 3. `GPUParticles2D` vs animated polygons (`AnimationPlayer`/`Tween`)
- **Particles** win where the motion is many small independent things: dust motes in a beam,
  impact sparks, landing dust, water drips. They are frozen by `Engine.TimeScale = 0` (correct
  during hit-stop) and by `GetTree().Paused` through `ProcessMode.Inherit` (correct on pause).
  They do **not** run in headless (dummy renderer), so smoke tests may assert flags and structure
  but never particle counts.
- **`AnimationPlayer` loops** win where the motion is one rigid body: the extractor fan's rotation
  and the conveyor's slats (animate the slat strip's `position:x` from `0` to `−Spacing` on a loop
  with one extra slat off each end — a perfect seamless belt with **no script at all**).
- **A small script** wins only where the motion needs randomness: lamp flicker
  (`FlickerLight.cs`, ~50 lines, `[Export]`-driven, reusable in Level 1). An `AnimationPlayer`
  with a hand-keyed irregular curve would also work; the script was chosen because Level 1 will
  want a dozen flickering lamps with different parameters.

**Chosen: all three, by the rule above.** Net new scripts for ambient life: exactly one.

### 4. Where the combat FX and the shake live
- **Inside `Hitbox`/`Player`/`Guard`**: touches combat classes, risks the balance and the review
  focus of T-02b/T-06. Rejected.
- **A `LevelFx` node per level** (chosen), the same shape as the existing `EnemyDirector`: a plain
  `Node` with `[Export]` references, subscribing to the hero's **public** signals
  (`Hitbox.Hit`, `Hurt`, `KnockedOut`, the new `Landed`) and spawning `ImpactFx`. No combat file
  changes except one added signal.
- **Camera shake in `LevelFx`** would give the `Camera2D` two owners. Instead `LevelBase` keeps
  sole ownership of the camera and exposes `ShakeCamera(amplitude, duration)`; `LevelFx` calls it
  through an `[Export] LevelBase Level` reference. `FollowPlayer` writes `GlobalPosition`,
  `ShakeCamera` writes `Offset` — one owner, two properties, no fight with `ApplyRoomBounds` or
  with `WaveSpawner`'s limit lock (which touches only `Limit*`).

### 5. How sparks stay visible in the dark
`Darkness` (`CanvasModulate` at ≈0.04) multiplies everything in the canvas; an additive-blended
spark multiplied by 0.04 is invisible, and relying on `CanvasItemMaterial.LightMode = Unshaded` to
escape the canvas modulate is engine-behaviour the plan will not bet on. §6 says lighting is the
main device — so **each `ImpactFx` carries its own short-lived `PointLight2D`** (`EnergyPale`,
`shadow_enabled = false`, energy tweened to 0 over the flash) which both lights the spark
particles and reads as an electric discharge. Same trick for the dead panel's sparks.

### 6. Restructuring the level scene vs additive dressing
Reparenting the existing `PH_*` nodes into tidy `Backdrop`/`Ground`/`Props` groups would break the
scene's `node_paths` exports and the node paths asserted by `tests/smoke/level_prologue.gd`
(`PH_Dan`, `PH_ZoneLamp`). **Chosen: additive.** Existing nodes keep their paths and only gain an
explicit `z_index` (and palette-aligned colours); all new dressing goes into new sibling groups.
The diff stays readable and the existing smoke script stays green unchanged.

---

## Recommended approach

1. **Depth first.** Give every existing background node its `z_index` from the brief's table, then
   add `Parallax` (3 × `Parallax2D`, z −100/−80/−60), `Backdrop` (z −40), `Ground` (z −20),
   `Foreground` (`Parallax2D`, z +40) and per-room `Fx_Room*` (z +20) groups. The gameplay plane
   (hero, guards, solid props) stays at z 0 under the level's `y_sort_enabled` root.
2. **Close the empty screen.** A `Ground/PH_NearBand` gradient band from y 604 to y 1080 across
   the whole level, `RockNear → RockDeep`, with rails/sleepers and a foreground rock lip.
3. **Texture the flats.** Keep the `ColorRect`s as base tone (retuned to the palette), overlay
   gradient/noise detail, strata bands, dirt patches and an irregular rock contour on ceiling and
   wall tops; give each room its own temperature (room 1 warm rust, room 2 cold concrete, room 3
   split: warm corridor / cold dark lane).
4. **Populate.** ~15 props by the collision rule below, all built from `Polygon2D` + `Line2D`
   outlines in the palette.
5. **Animate the world.** Dust in the lamp beams, one flickering lamp per room, the extractor fan
   and the conveyor on `AnimationPlayer` loops, drips into a puddle, sparks on the dead panel
   after `Stage.NoPower`. Gated per room by `RoomBounds.Fx` so only the visible room simulates.
6. **Combat feedback.** `ImpactFx` (sparks + flash light, self-freeing) on every landed hit,
   landing dust on touchdown, `ShakeCamera` scaled by the hit's `HitStopFrames`.
7. **Playability.** Camera lookahead + smoothing, vignette, an explicit dark lane decal in room 3,
   prompt forwarding into `LevelBase`, cutscene fade.

### Collision rule for dressing (non-negotiable, `/reviewer` checks it)
The hero's walkable band in every room is `FloorTop = 300 … FloorBottom = 600`.

- A prop whose visual base sits at **y ≤ 296** (against the back wall) is decoration: **no
  collision**, and y-sorting already draws it behind every character.
- A prop whose base sits **inside 300…600** must carry a `StaticBody2D` child named `Blocker`
  (`collision_layer = 1`, `collision_mask = 0`) matching its footprint, or it must be a flat
  floor decal at z −20 with no body at all.
- A prop whose base sits at **y ≥ 604** is below the belt: decoration in `Ground`/`Foreground`,
  no collision.
- **Nothing new may narrow the stealth lane** in room 3 (world y 300…410, x 3840…5760) or the
  ~100 px walking corridor past the crates in room 1.

---

## GameState & save impact

**No `GameState` change.** Nothing here reads or writes `Energy`, `Route`, `JournalsFound`,
`DistrictReputation` or `CurrentScenePath`; no new field, no new signal on the autoload; nothing
new for T-09 to persist. The FX, parallax and camera state are per-level view state that must be
rebuilt from the scene on load, and are deliberately not persisted.

`GameState.Energy` is still read indirectly by the HUD and the flashlight — untouched.

---

## Scene & signal contract

### New: `scenes/fx/ImpactFx.tscn` ↔ `scripts/fx/ImpactFx.cs`
```
ImpactFx            Node2D                z_index = 20   (partial class ImpactFx : Node2D)
├── Sparks          GPUParticles2D        one_shot = true, emitting = false, local_coords = false,
│                                         amount = 12, lifetime = 0.28, explosiveness = 0.95,
│                                         ProcessMaterial: radial spread, gravity 0, damping,
│                                         colour ramp EnergyPale → EnergyAmber → transparent,
│                                         CanvasItemMaterial blend_mode = Add
├── Flash           PointLight2D          enabled = false, shadow_enabled = false,
│                                         texture = radial GradientTexture2D, energy 0
└── (no other children)
```
| `[Export]` | Type | Default | Unit / meaning |
|---|---|---|---|
| `Sparks` | `GpuParticles2D` | — | the burst |
| `Flash` | `PointLight2D` | — | the discharge light |
| `SparkColor` | `Color` | `Palette.EnergyPale` | tint applied to `Sparks.Modulate` |
| `FlashEnergy` | `float` | `1.6` | peak light energy |
| `FlashTime` | `float` | `0.12` | s, energy → 0 |
| `Lifetime` | `float` | `0.35` | s, particle lifetime used by the guard timer |
| `FreeMargin` | `float` | `0.25` | s added to `Lifetime` before the guaranteed self-free |

API: `public void Play(int amount, float scale)` — sets `Sparks.Amount`, `Scale`, restarts the
burst, enables and tweens the flash, and **arms a guaranteed self-free**:
`GetTree().CreateTimer(Lifetime + FreeMargin, processAlways: false, processInPhysics: false, ignoreTimeScale: false)`
→ `QueueFree()`. `GpuParticles2D.Finished` also frees it (whichever comes first,
`IsInstanceValid` guarded). Scaled, non-always time is deliberate: the effect freezes with
hit-stop and with the pause menu and can never outlive the level; **headless never emits
`Finished`, so the timer is the only path a smoke test may rely on.**

### New: `scenes/ui/Vignette.tscn` (scriptless)
```
Vignette            CanvasLayer   layer = 5     (below HUD 10 and Cutscene 20)
└── PH_Vignette     TextureRect   anchors full rect, mouse_filter = Ignore (2),
                                  texture = GradientTexture2D(fill = radial, 256×256,
                                  (0,0,0,0) → OutlineDark @ 0.55), expand_mode = ignore size,
                                  stretch_mode = scale
```
No script: nothing to tune at runtime. Instanced by the level, not by `Main` (levels own their UI
today, as recorded in the T-07 review).

### New: `scripts/levels/LevelFx.cs` (a `Node` placed in a level scene, `EnemyDirector` pattern)
| `[Export]` | Type | Default | Meaning |
|---|---|---|---|
| `Level` | `LevelBase` | — | for `ShakeCamera` |
| `Player` | `Player` | — | the hero whose signals drive the FX |
| `ImpactFxScene` | `PackedScene` | `ImpactFx.tscn` | spawned per event |
| `FxParent` | `Node2D?` | `null` | where spawned FX are parented (defaults to the level) |
| `HitFxHeight` | `float` | `40` | px above the target's feet where the spark appears |
| `HitSparkAmount` | `int` | `12` | particles on a light hit |
| `HeavySparkAmount` | `int` | `22` | particles on a heavy hit |
| `HeavyHitStopFrames` | `int` | `5` | a hit with `HitStopFrames ≥` this counts as heavy |
| `HitShake` / `HeavyShake` / `KnockdownShake` | `float` | `3` / `7` / `11` | px amplitude |
| `ShakeTime` | `float` | `0.18` | s |
| `LandDustAmount` | `int` | `8` | particles under the feet on landing |
| `LandDustColor` | `Color` | `Palette.RockNear` | dust, not sparks |

Connections, made in `_Ready`, dropped in `_ExitTree`:
`Player.Hitbox.Hit(Node2D target)` → spark at `target.GlobalPosition + (0, −HitFxHeight)`, amount
and shake by `Player.CurrentAttack.HitStopFrames`; `Player.Hurt(float damage)` → spark on the hero
+ `HitShake`; `Player.KnockedOut()` → `KnockdownShake`; `Player.Landed()` → dust puff at the
hero's feet, no shake. Guards' hits on the hero are already covered by `Hurt`.

### Changed: `scripts/levels/LevelBase.cs`
New members (all `[Export]` for tunables, no magic numbers):

| Member | Type | Default | Meaning |
|---|---|---|---|
| `Hud` | `HUD?` | `null` | **moved up** from `TestRoom`/`Level00_Prologue`; the `.tscn` property name is unchanged, so no scene edit is needed |
| `PromptFormat` | `string` | `"E: {0}"` | **moved up** |
| `CameraLookahead` | `float` | `90` | px the camera leads the hero in his movement direction |
| `CameraLookaheadSpeed` | `float` | `3.5` | 1/s smoothing of the lookahead |
| `ShakeDecay` | `float` | `1` | fraction of the shake left after `duration` (linear decay) |
| `ShakeCamera(float amplitude, float duration)` | method | — | pseudo-random decaying `Camera.Offset`; a new call takes the larger amplitude |
| `protected virtual void RefreshPrompt()` | method | — | base: show `InteractablePrompt` or hide; overridden by the prologue |
| `protected string? InteractablePrompt` | property | — | formatted text of the prop in reach |
| `protected bool IsInteractableUsable()` | method | — | as today |

`LevelBase._Ready` now also subscribes `Player.InteractableChanged` and holds the
`FollowInteractable` / `OnPromptChanged` / `FormatPrompt` logic verbatim from the two levels;
`_ExitTree` unsubscribes and calls `FollowInteractable(null)`. `_Process(delta)` passes `delta`
into `FollowPlayer(double delta)`, which now computes
`targetLookahead = Sign(Player.Velocity.X) * CameraLookahead` (0 when standing), lerps `_lookahead`
towards it with `1 − Exp(−CameraLookaheadSpeed * delta)`, sets
`Camera.GlobalPosition.X = Player.GlobalPosition.X + _lookahead` and writes the decaying shake into
`Camera.Offset`. `_Ready` snaps the lookahead (no opening sweep). `ApplyRoomBounds` additionally
calls `Camera.ResetSmoothing()` **after** the limits are set, and swaps the active room's FX
(below). The camera's `Limit*` properties are still written only by `ApplyRoomBounds` and by
`WaveSpawner` — the shake never touches them, so a wave lock keeps working unchanged.

**Shake safety (`/reviewer` focus `hit-stop/timescale`):** the shake is driven by a remaining-time
counter decremented with the (scaled) `_Process` delta, so `Engine.TimeScale = 0` merely holds it;
when the counter hits 0 the code writes `Camera.Offset = Vector2.Zero` **exactly** (not a lerp
tail), and `_ExitTree` zeroes it too. It can never leave the camera displaced and never touches
`Engine.TimeScale`.

### Changed: `scripts/levels/RoomBounds.cs`
`[Export] public Node2D? Fx { get; set; }` — the ambient-FX group belonging to this room.
`LevelBase.ApplyRoomBounds` keeps `_activeRoom`; on a change it calls a private
`SetFxActive(Node2D group, bool on)` which, for the group and its descendants, sets
`GpuParticles2D.Emitting = on` and sets the group's `ProcessMode` to `Inherit`/`Disabled` (which
also stops the `AnimationPlayer` loops and `FlickerLight`). The group stays `Visible`; nothing
pops, because a non-active room is off-camera by construction (camera limits = room rect).

### Changed: `scripts/player/Player.cs`
```csharp
/// <summary>Emitted the physics frame the hero's height returns to 0 after a jump.</summary>
[Signal] public delegate void LandedEventHandler();
```
emitted from `IntegrateJump` in the branch that clamps `_z` to 0, only when the hero was airborne
on the previous step. No state-machine change, no balance change.

### Changed: `scripts/levels/Level00_Prologue.cs`
- deletes `Hud`, `PromptFormat`, `_currentInteractable`, `_interactablePrompt`,
  `FollowInteractable`, `OnInteractableChanged`, `OnPromptChanged`, `FormatPrompt`,
  `IsInteractableUsable` (all now in `LevelBase`);
- keeps its **priority** by `protected override void RefreshPrompt()` — cutscene → usable
  interactable → stage hint → tutorial hint → unusable interactable, exactly today's order;
- `[Export] GpuParticles2D? PanelSparks`, `[Export] PointLight2D? PanelSparkLight` — started in
  `OnFanPanelFailedNoPower` (the panel is dead from that moment on, §3), stopped never;
- `[Export] AnimationPlayer? ConveyorAnim` is **not** needed — the loop autoplays from the scene.

### Changed: `scripts/levels/TestRoom.cs`
Deletes the same six duplicated members; keeps only the debug label, the standing guard, and the
panel→lamp wiring. Net −45 lines.

### Changed: `scripts/props/FlickerLight.cs` (new script attached to `PointLight2D` nodes in level scenes, `LitZone` pattern)
| `[Export]` | Default | Unit |
|---|---|---|
| `BaseEnergy` | `1.1` | light energy at rest |
| `FlickerDepth` | `0.35` | fraction of `BaseEnergy` the dip can reach |
| `MinInterval` / `MaxInterval` | `0.07` / `0.9` | s between flicker events |
| `Smoothing` | `14` | 1/s approach to the target energy |
| `Active` | `true` | off = a steady lamp |

`_Process` only (visual), one cached `RandomNumberGenerator`, no allocation per frame; restores
`BaseEnergy` in `_ExitTree`; a `delta == 0` frame (hit-stop) is a no-op.

### Changed: `scripts/ui/Cutscene.cs` (nice-to-have N2)
`[Export] float FadeTime = 0.2f` (overlay `Root.Modulate.A` tween on `Play`/`Finish`) and
`[Export] float MinLineTime = 0.25f` (a line cannot be advanced by input before it has been on
screen that long — stops a double-tap from eating two lines). **If `MinLineTime` is implemented,
`tests/smoke/level_prologue.gd`'s tap loop must be updated in the same pass** (its `TAP_CAP` and
frame spacing assume an instantly skippable line).

### Scene map — `scenes/levels/Level00_Prologue.tscn`
`z` = final `z_index`; `col` = collision. Existing nodes keep their paths; only `z_index` and
palette-aligned colours change on them.

| Group / node | Section | z | col | Content |
|---|---|---|---|---|
| `Parallax/PxRockFar` (`Parallax2D`, `scroll_scale = (0.15, 1)`) | whole level | −100 | no | `RockDeep` massif, jagged top contour, ~4200 px wide (covers 1920 + 0.15·(5760−1920)) |
| `Parallax/PxRockMid` (`0.35`) | whole level | −80 | no | `RockMid` strata bands (`VertexColors`), distant gallery arches, `NoiseTexture2D` grain |
| `Parallax/PxStruct` (`0.55`) | whole level | −60 | no | `RockNear`/`ConcreteCold` silhouettes: trestles, distant cart silhouettes, sagging cable lines, a far duct |
| `Backdrop/*` | per room | −40 | no | existing `PH_Wall_1..3`, `PH_Ceiling` (z set here) + new: irregular rock lip on the ceiling underside, strata overlay per room, wall dirt patches, `WarningSign_*`, pipe runs, valve wheels (room 2) |
| `Ground/PH_NearBand` | whole level | −20 | no | y 604→1080 gradient `RockNear → RockDeep`, rails + sleepers, **fixes the empty bottom of the screen** |
| `Ground/*` | per room | −20 | no | existing `PH_Floor_1..3`, `PH_FloorEdge`, `PH_Decals` (z set here) + new: floor gradient overlays (room 1 warm rust, room 2 cold steel, room 3 warm corridor), stains, spill marks, `PH_Puddle_*` (dark polygon + `EnergyPale` rim), `PH_ShadowLane` (room 3, x 3840…5760, y 300…410 — makes the stealth lane readable), light-shaft trapezoids under each lamp |
| `Props/*` (`Node2D`, **`y_sort_enabled = true`**) | per room | 0 | mixed | new solid dressing — see below |
| `Fx_Room1/2/3` (`Node2D`, referenced by `RoomBounds.Fx`) | per room | +20 | no | dust, flicker, conveyor/fan loops, drips, panel sparks |
| `Foreground` (`Parallax2D`, `scroll_scale = (1.25, 1)`) | whole level | +40 | no | near support silhouettes the camera passes, a hanging cable, a dark rock lip at the very bottom (y ≥ 900) — `OutlineDark`, 3 px outline per the brief |
| `Vignette` (instance) | — | CanvasLayer 5 | no | radial darkening |

**`Props` group content (the collision rule decides `col`):**

| Node | Room | Base y | col | Note |
|---|---|---|---|---|
| `Cart_1` | 1 | 560 | **Blocker** | вагонетка on the near rail, walk-around |
| `ScrapPile_1`, `ScrapPile_2` | 1 | 292 | no | dismantled electronics against the wall (§3) |
| `BatteryStack_1..3` | 1 | 288 | no | stacked accumulators by the conveyor |
| `Ladder_1` | 1 | 596 | no | flat against the hatch rim (`PH_Hatch`), decal-like |
| `PipeStack_1` | 2 | 294 | no | pipes and a coiled cable bundle |
| `BrokenRig_1` | 2 | 292 | no | dead control cabinet, hanging door |
| `Scaffold_1` | 2 | 310 | **Blocker** | under the fan duct, far side, leaves the corridor clear |
| `Cart_2` (overturned) | 3 | 545 | **Blocker** | near the lit corridor |
| `ScrapPile_3`, `CrateStack_1` | 3 | 290 | no | against the wall |
| `SeveredCable_1` | 3 | 296 | no | sparking cable end (its FX lives in `Fx_Room3`) |
| `ExitSign_1` | 3 | wall | no | arrow towards the lift, `EnergyAmber` |

**Y-sort trap (review focus `belt-scroll depth`):** `Props` must have `y_sort_enabled = true`. A
y-sorted subtree inside a y-sorted parent is merged into the parent's sort; a **non**-y-sorted
group would be drawn as one unit at the group's own Y and would repeat the `PH_LitFloor` bug fixed
in the T-07 review (S4). Groups at z ≠ 0 do not need it (z_index is compared before Y).

**Ambient FX inventory (the frame-budget contract):**

| Node | Room | Type | Notes |
|---|---|---|---|
| `Fx_Room1/DustBeam_1` | 1 | `GPUParticles2D` | motes in `PH_WorkLamp_1`'s beam, `amount = 16`, lifetime 4 s, `visibility_rect` bounded to the beam |
| `Fx_Room1/ConveyorAnim` | 1 | `AnimationPlayer` | loops the slat strip's `position:x` 0 → −Spacing |
| `Fx_Room1/ExtractorFan` + `FanAnim` | 1 | `Polygon2D` + `AnimationPlayer` | the *working* small ceiling fan (x ≈ 1600) — **not** the dead fan of room 2 |
| `Fx_Room1/Flicker` | 1 | `FlickerLight.cs` on `PH_WorkLamp_1` | |
| `Fx_Room2/DustBeam_2` | 2 | `GPUParticles2D` | `amount = 12` |
| `Fx_Room2/Drip` | 2 | `GPUParticles2D` | `amount = 6`, into `PH_Puddle_1` |
| `Fx_Room2/PanelSparks` + `PanelSparkLight` | 2 | `GPUParticles2D` + `PointLight2D` | started by the level at `Stage.NoPower`, `emitting = false` in the scene |
| `Fx_Room3/DustBeam_3`, `DustBeam_4` | 3 | `GPUParticles2D` | under the two `LitZone` lamps, `amount = 12` |
| `Fx_Room3/CableSparks` | 3 | `GPUParticles2D` | `amount = 8`, near the exit |

Ambient emitters: **9 total, at most 4 alive at once** (per-room gating). Transient `ImpactFx`:
at most ~3 concurrently in normal play. `PointLight2D` census after this task: 2 work lamps + 3
alarm + 2 zone + 1 flashlight + 1 panel spark + ≤ 3 transient flashes = **≤ 12, every one with
`shadow_enabled = false`**.

### `scenes/levels/TestRoom.tscn`
Adds a `LevelFx` node (wired to the room, the hero and `ImpactFx.tscn`) so combat feedback can be
exercised in the combat scene. No other change — the `Hud` and `PromptFormat` properties keep
their names when they move to `LevelBase`, so the stored values still resolve.

---

## File-level change list

### `scenes/`
- **`scenes/levels/Level00_Prologue.tscn`** *(edit, large)* — parallax group, backdrop/ground
  detail, `Props` group, per-room `Fx_Room*`, `Foreground`, `Vignette` instance, `z_index` on the
  existing background nodes, `RoomBounds.Fx` wiring, new `[Export]` targets for the panel sparks.
- **`scenes/levels/TestRoom.tscn`** *(edit, small)* — `LevelFx` node.
- **`scenes/fx/ImpactFx.tscn`** *(new)* — spark burst + flash light.
- **`scenes/ui/Vignette.tscn`** *(new)* — scriptless radial darkening layer.
- *(nice-to-have N5)* `scenes/art/rock_noise.gdshader` — optional rock grain; the level must look
  right without it.

### `scripts/`
- **`scripts/fx/ImpactFx.cs`** *(new)* — `Play(amount, scale)`, flash tween, guaranteed self-free.
- **`scripts/levels/LevelFx.cs`** *(new)* — hero signals → impact FX + `Level.ShakeCamera`.
- **`scripts/props/FlickerLight.cs`** *(new)* — irregular lamp flicker on a `PointLight2D`.
- **`scripts/levels/LevelBase.cs`** *(edit)* — prompt forwarding moved in, camera lookahead,
  `ShakeCamera`, room-FX gating in `ApplyRoomBounds`, `ResetSmoothing` on a room change.
- **`scripts/levels/RoomBounds.cs`** *(edit)* — `[Export] Node2D? Fx`.
- **`scripts/levels/Level00_Prologue.cs`** *(edit)* — de-duplicated; `RefreshPrompt` override;
  panel sparks at `Stage.NoPower`.
- **`scripts/levels/TestRoom.cs`** *(edit)* — de-duplicated.
- **`scripts/player/Player.cs`** *(edit, 6 lines)* — `Landed` signal.
- **`scripts/ui/Cutscene.cs`** *(edit, nice-to-have N2)* — `FadeTime`, `MinLineTime`.

### `tests/smoke/`
- **`tests/smoke/level_dressing.gd`** *(new)* — see Test strategy.
- **`tests/smoke/level_prologue.gd`** *(edit only if N2 lands)* — cutscene tap pacing.

### `docs/`
- **`docs/TASKS.md`** — T-07i-c `in_progress` → `done` with the 1–2 line note, plus the four
  `backlog` entries quoted under **Out of scope**.
- **`docs/plans/t07i-c-level-dressing/t07i-c-level-dressing-plan.md`** — this file; `/reviewer`
  fills `## Review findings`.

### `project.godot` / `.csproj`
**No change.** No new autoload, no InputMap action, no physics layer, no package. The `/project-settings`
skill is therefore not invoked. (The engine clear colour visible below the level content is fixed
inside the scene by `PH_NearBand`, not by a project setting — see backlog line T-B10.)

---

## Priorities

**Must (T-07i-c is not done without these):**
- **M1** Parallax: 3 background `Parallax2D` layers + 1 foreground layer, `z_index` exactly per the
  brief's table, distinct `scroll_scale`, no visible seam or empty edge inside any room's camera
  limits.
- **M2** No engine clear colour anywhere on screen in any of the three rooms; floors, walls and
  ceiling carry gradient/noise/strata detail; the three rooms are distinguishable by colour
  temperature.
- **M3** At least 12 new props placed by the collision rule, with the rule respected exactly.
- **M4** Ambient life in every room: dust in ≥ 2 lamp beams, ≥ 1 flickering lamp, the extractor
  fan turning, the conveyor moving, sparks on the dead panel after «Немає живлення». The room 2
  fan Rey fails to start stays motionless.
- **M5** Combat feedback: spark + flash at the impact point on every landed hit, dust on landing,
  screen shake on a heavy hit and on the hero's knockdown. `Engine.TimeScale` untouched; no
  residual `Camera.Offset`; every FX node frees itself; correct behaviour with the pause menu.
- **M6** Camera lookahead + smoothing tuned; `ApplyRoomBounds`, the door hops and the
  `WaveSpawner` camera lock behave exactly as before.
- **M7** Vignette present, below the HUD and the cutscene layer, mouse-transparent.
- **M8** Prompt forwarding lives in `LevelBase`; `TestRoom` and `Level00_Prologue` no longer
  duplicate it; the prologue's prompt priority is unchanged in behaviour.
- **M9** `dotnet build`, headless load, `tools/smoke.ps1` green including the new
  `level_dressing.gd`; the prologue still plays from the menu to `Level01_District`.

**Nice-to-have (do only with time left for verification; drop without guilt):**
- **N1** Water drips into a rippling puddle, cable sway, alarm-light haze cones.
- **N2** Cutscene fade + `MinLineTime` pacing (**requires** updating `level_prologue.gd`).
- **N3** `PH_Shadow` `z_index = −10` on `Player`/`Guard`/`Dummy` for full brief conformance
  (**conflicts with T-07i-b**, which rewrites those scenes — do it last or skip).
- **N4** Extract the parallax group into a reusable scene for Level 1 (backlog T-B11 otherwise).
- **N5** `rock_noise.gdshader` for finer rock grain.

---

## Acceptance criteria

1. Given the prologue is loaded, `Parallax` contains ≥ 3 `Parallax2D` nodes whose `z_index` values
   lie in [−100, −60] and whose `scroll_scale.x` values are distinct and strictly inside (0, 1),
   ordered so that the deeper `z_index` has the smaller `scroll_scale.x`; `Foreground` is a
   `Parallax2D` with `z_index == 40` and `scroll_scale.x > 1`.
2. Given the prologue is loaded, every existing background node carries its brief `z_index`:
   `PH_Wall_1..3` and `PH_Ceiling` = −40; `PH_Floor_1..3`, `PH_FloorEdge`, `PH_Decals` and the new
   `Ground` group = −20; `Fx_Room1..3` = +20; the `Props` group = 0 with `y_sort_enabled == true`.
3. Given the camera at any position allowed by any of the three rooms' limits, no screen pixel
   shows the engine clear colour: `Ground/PH_NearBand` covers world y from 604 to at least 1080
   across x 0…5760.
4. Given the hero stands in room 1, `Fx_Room1`'s `GPUParticles2D` descendants have
   `emitting == true` and `Fx_Room2`/`Fx_Room3` have `emitting == false` with `ProcessMode` =
   `Disabled`; after the hero walks through `Door_1`, the same holds with rooms 1 and 2 swapped.
5. Given the whole prologue scene, the number of `GPUParticles2D` nodes is ≤ 10 and each has
   `amount ≤ 32`; the number of `PointLight2D` nodes is ≤ 12 and **every one** has
   `shadow_enabled == false`.
6. Given an `ImpactFx` instance in the tree with `Play(12, 1)` called, `Sparks.Emitting` is true
   and `Flash.Enabled` is true within one frame, and the node is freed within
   `Lifetime + FreeMargin + 0.2 s` of real time; given `GetTree().Paused == true`, it is **not**
   freed while paused and is freed after the pause is lifted; `Engine.TimeScale` is 1.0 throughout.
7. Given `level.ShakeCamera(10, 0.2)`, `Camera.Offset` becomes non-zero within 2 frames and is
   **exactly** `Vector2.Zero` within `0.2 s + 5 frames`; `Camera.Limit*` are unchanged by the
   shake; freeing the level while a shake is running produces no error and leaves no offset.
8. Given the hero at x = 900 in room 1 (away from the camera limits) holding `move_right` for 30
   physics frames, `Camera.GlobalPosition.X − Player.GlobalPosition.X` is in
   `(0, CameraLookahead + 1]`; after the key is released and 60 frames pass, the difference is
   within ±2 px of 0.
9. Given the hero jumps in `TestRoom`, `Player.Landed` is emitted exactly once, on the physics
   frame `Height` returns to 0.
10. Given the hero stands next to the outlet in `TestRoom` (which no longer has its own prompt
    code), `Hud.PromptText == "E: Зарядити"`; given he steps away, the prompt is hidden. Given the
    prologue after Dan's cutscene with the hero still at the dead panel, the HUD shows the escape
    stage hint, not «Обезструмлена» (the T-07 S1 regression stays fixed).
11. Given the prologue is run from `Main`, every stage still fires in the order
    `Tutorial, Ventilation, NoPower, Alarm, Escape, Foreman, Ending, Done`, the fine is still
    `FinePenalty`, the unlit stealth lane still yields zero `Noticed`, and
    `Level01_District` still becomes the current scene — i.e. `tests/smoke/level_prologue.gd`
    passes unmodified (or with only the N2 pacing edit).
12. Given the prologue is loaded, a `Vignette` `CanvasLayer` exists with `0 < layer < 10` and its
    `TextureRect` has `mouse_filter == Ignore`.
13. `dotnet build` produces 0 errors and 0 new warnings; `godot --headless --path . --quit` prints
    no `ERROR:`/`SCRIPT ERROR:` line; `tools/smoke.ps1` exits 0 with every script `PASS`.

---

## Test strategy

Kind of change: **mostly new visual behaviour (`add-*`) plus one refactor of existing behaviour**
(prompt forwarding into `LevelBase`). The refactored behaviour **already has characterization
coverage** — `tests/smoke/level_prologue.gd` asserts the HUD prompt text at every beat and
`tests/smoke/props_interact.gd` covers the interactable prompts — so no new test has to land
before the refactor; those two must stay green **unmodified**, which is the regression proof.

GdUnit4 is still not available and is not requested.

### New: `tests/smoke/level_dressing.gd` (`extends SceneTree`, house style: `NAME`, `MAX_FRAMES`, `_check`, `_step`, `_finish`, `SMOKE level_dressing PASS|FAIL`)
Headless sees no graphics, so it asserts structure, flags, budgets and lifetimes:

1. **Load** `res://scenes/levels/Level00_Prologue.tscn`, `add_child`, `_settle()` (the heavy-scene
   catch-up helper copied from `level_prologue.gd`).
2. **Depth contract** — the `z_index` table of acceptance criteria 1–2, by node path; `Props`
   `y_sort_enabled == true`.
3. **Parallax** — ≥ 3 `Parallax2D` layers, distinct `scroll_scale.x` in (0, 1) ordered by depth,
   foreground `scroll_scale.x > 1`; no layer has `IgnoreCameraScroll == true`.
4. **Bottom coverage** — `Ground/PH_NearBand` exists and its polygon/rect reaches world y ≥ 1080
   across x 0…5760.
5. **Budget** — recursive census: `GPUParticles2D` count ≤ 10 with `amount ≤ 32` each;
   `PointLight2D` count ≤ 12, all `shadow_enabled == false`.
6. **Room-FX gating** — at `_Ready` room 1 emits and rooms 2–3 do not; teleport the hero into
   `Door_1` and walk him through (the doors report only `BodyEntered`, as `level_prologue.gd`
   already does), then re-check with the rooms swapped.
7. **`ImpactFx` lifetime** — instantiate `res://scenes/fx/ImpactFx.tscn`, `Play(12, 1)`, assert
   `Sparks.Emitting` / `Flash.Enabled`, then assert it is freed within `Lifetime + FreeMargin`
   (wall-clock capped, `create_timer(..., ignore_time_scale = true)` as the watchdog). Repeat with
   `get_tree().paused = true`: still alive after the same wait, freed after unpausing. Assert
   `Engine.time_scale == 1.0` at the end. **Never assert particle counts** — headless does not
   simulate them.
8. **Shake** — `ShakeCamera(10, 0.2)` → offset non-zero, then exactly `Vector2.ZERO`; limits
   unchanged; a shake started and then the level freed → no error (the runner fails on `ERROR:`).
9. **Lookahead** — acceptance criterion 8, using `camera.global_position` (unclamped; the clamped
   value is `get_screen_center_position()`).
10. **`Player.Landed`** — connect in `TestRoom`, tap `jump`, count exactly one emission at
    touchdown, and assert `Height == 0` at that moment.
11. **`LevelBase` prompt forwarding** — in `TestRoom`, teleport the hero next to the outlet →
    `Hud.PromptText == "E: Зарядити"`; away → hidden. Also assert `TestRoom` exposes the inherited
    `PromptFormat` (`room.get("PromptFormat") == "E: {0}"`) — i.e. the property really moved to the
    base and is still reachable from the scene.
12. **Vignette** — layer between 1 and 9, `TextureRect.mouse_filter == 2`.
13. **Teardown** — free everything, one frame, no error lines.

### Existing scripts that must stay green
`level_prologue.gd` (whole prologue flow — the regression net for anything the dressing might
break), `props_interact.gd`, `enemy_guard.gd`, `enemy_wave.gd` (camera limits with a wave lock —
the lookahead must not disturb them), `combat_dummy.gd`, `ui_hud.gd`, `player_movement.gd`,
`player_flashlight.gd`, `core_*`.

### Only verifiable by hand (→ Playtest)
Whether the mine reads as a mine; whether the parallax gives depth or just noise; whether the
darkness is still readable and the stealth lane is findable; whether the vignette is subtle or
oppressive; the *feel* of the lookahead, the shake and the hit sparks; the cutscene pacing;
whether the flicker is atmospheric or annoying; whether anything new visually blocks the hero.

---

## Playtest (manual QA)

*(rewritten after implementation — steps match what actually shipped; the nice-to-have N1–N5 are
not in the build, see the task note)*

1. Запусти гру (F5) і почни нову гру. **Очікувано:** пролог; за героєм видно **три плани породи**
   (масив, страти з арками, опори/вагонетка/провислі кабелі), що рухаються повільніше за нього,
   попереду — темна опора й кабель, які проходять швидше; **низ екрана не сірий/порожній** — там
   ближня темна порода з рейками і шпалами; по краях кадру — м'яка віньєтка, HUD і підказки крізь
   неї читаються.
2. Пройди кімнату 1 вправо (D). **Очікувано:** підлога, стіни й стеля не однотонні — зерно шуму,
   плями бруду, страти, нерівний край породи під стелею, теплий іржавий тон; у промені робочої
   лампи (x≈480) видно пил; та сама лампа **ледь мерехтить**; конвеєр **рухається** (смуги повзуть
   ліворуч); під стелею праворуч (x≈1700) **обертається** маленький витяжний вентилятор;
   попереджувальний знак на стіні.
3. Вагонетка (x≈1560, ближній край) — **пройти наскрізь не можна**, обходиш зверху або знизу;
   купи брухту, стоси акумуляторів, драбина біля люка стоять під стіною і **не заважають** —
   коридор між ящиками (x≈720) лишився таким самим, як був.
4. Стрибни (Space) кілька разів. **Очікувано:** при приземленні під ногами — коротка **хмарка
   пилу** з підсвіткою; тінь лишається на підлозі.
5. Камера: йди вправо, потім різко вліво. **Очікувано:** кадр не смикається; **зауваж**: кімнати
   прологу рівно завширшки з екран, тому камера в кімнаті стоїть по центру — випередження камери
   (`CameraLookahead`) вступить у дію на ширших кімнатах рівня 1. Переїзд камери між кімнатами
   (двері) — **такий самий, як раніше**.
6. Пройди двері в кімнату 2. **Очікувано:** кімната **холодніша за кольором** (бетон/сталь) проти
   теплої першої; другий трубопровід із двома вентилями, стоси труб, зламана шафа, риштування під
   вентканалом (крізь нього не пройдеш); під протікаючою трубою (x≈2300) **крапає** в калюжу з
   блідим обідком; у промені другої лампи теж видно пил.
7. Активуй панель вентилятора (E, послідовність ↑ J ↓ Space). **Очікувано:** «Немає живлення»;
   після цього на панелі **безперервно сипляться іскри з підсвіткою**; великий вентилятор у
   вентканалі **стоїть нерухомо** (це і є сенс сцени).
8. Тривога, кат-сцена про Дана. **Очікувано:** червоні лампи блимають як раніше; підказки не
   перекривають одна одну; пил і крапання в кімнаті 2 тривають.
9. Кімната 3. **Очікувано:** освітлений коридор чітко відрізняється від **темної смуги під
   стіною** — смуга видима як окрема темніша доріжка, а не просто «тут нічого не видно»;
   перекинута вагонетка (x≈4380) обходиться; біля виходу **іскрить обірваний кабель**; над
   ліфтом — бурштиновий знак-стрілка; у двох плямах світла видно пил.
10. Побийся з охоронцем (J, K). **Очікувано:** на кожному влучанні — короткий спалах і
    **електричні іскри в точці удару**; на важкому ударі (K) — помітна тряска екрана, на легкому —
    ледь відчутна; hit-stop лишається таким самим, як раніше (гра завмирає на кілька кадрів і
    **одразу** відмирає — жодних зависань).
11. Дай себе вдарити, а потім збити до KO. **Очікувано:** на попаданні по герою — червонястий
    сплеск іскор і тряска; сильніша тряска на нокдауні; через ~1 с рівень перезапускається зі
    вступу, **камера рівно по центру героя, без залишкового зсуву**.
12. Постав гру на паузу (Esc) під час бою і під час іскор на панелі. **Очікувано:** пил, іскри,
    мерехтіння, конвеєр і вентилятор **завмирають**; після «Продовжити» рухаються далі; нічого не
    зникло і не залишилось «завислим» на екрані.
13. Пройди до ліфта і закінчи пролог. **Очікувано:** штраф −20 на шкалі як раніше, кат-сцена,
    рівень 1; віньєтка присутня протягом усього рівня, але не заважає читати HUD і підказки.
14. Окремо: відкрий `scenes/levels/TestRoom.tscn` як головну (F6). **Очікувано:** підказка
    «E: Зарядити» біля розетки працює як раніше (форвардинг переїхав у `LevelBase`); удари по
    манекенах дають іскри й тряску; стрибок дає хмарку пилу.

## Review focus

`belt-scroll depth` (the `z_index` table and the `y_sort_enabled` group trap) ·
`hit-stop/timescale` (FX and shake must not touch `Engine.TimeScale`, must not get stuck, must
free themselves) · `frame budget` (light and particle census, per-room gating, no per-frame
allocations in `FollowPlayer`/`FlickerLight`) · `scene/tscn integrity` (no reparenting of existing
nodes, valid `uid`s, `node_paths` still resolving, `[editable path="GuardSpawner"]` overrides
preserved).

---

## Performance & frame budget

- **Per-frame C#:** `LevelBase.FollowPlayer` (one lerp, two float writes, one `Vector2` to
  `Camera.Offset` — no allocation), `FlickerLight._Process` (one RNG call at intervals, one lerp),
  `Level00_Prologue._Process` (unchanged: the debug label only on a height change). Nothing new in
  `_PhysicsProcess`; **no hit detection, no depth check and no movement moves out of the physics
  tick.** No LINQ, no `new` arrays, no string building, no closures in any per-frame path.
  `SetFxActive` walks a small subtree **only on a room change** (three times per playthrough).
- **Draw calls:** the dressing adds roughly 90–120 `Polygon2D`/`Line2D`/`TextureRect` canvas items.
  These are cheap and mostly outside the y-sorted plane; only ~15 new nodes join the y-sorted
  gameplay plane (grouped under `Props`, not one node per detail), keeping the sort bounded as the
  brief requires.
- **Lights:** ≤ 12 `PointLight2D` in the level, **all `shadow_enabled = false`** (shadowed lights
  are the first thing to cut and none is introduced). Only the current room's lamps and the
  transient flashes are ever in view.
- **Particles:** 9 ambient emitters, **≤ 4 active at once** thanks to `RoomBounds.Fx` gating,
  `amount ≤ 32` each and a bounded `visibility_rect` so nothing simulates across the whole level;
  ≤ 3 transient `ImpactFx` in normal play, each self-freeing. Worst case ≈ 200 particles.
- **Parallax:** four `Parallax2D` nodes recompute a transform per frame — negligible; their
  children are static.
- **Allocation churn:** one `ImpactFx` instance per landed hit (a few per second at most), freed
  by `Finished` or by its guard timer. Pooling was considered and rejected as premature; if a
  profile ever shows it, a 4-instance pool on `LevelFx` is a drop-in change.

---

## Risks

1. **The parallax is invisible under `Darkness`.** `CanvasModulate` at ≈0.04 flattens the far rock
   to near-black. Mitigation: author the far layers noticeably lighter than the wall colour, and
   accept that the parallax reads mostly in lamp-lit stretches — this is the intended "Inside"
   mood. Verify in playtest step 1; if it fails, raise the layer colours, not `Darkness` (that
   would change the stealth balance).
2. **`Parallax2D` overwrites its own `position`.** Documented in the class: any position set after
   the node enters the tree is overridden. The coder must position the *children*, not the layer.
3. **Layer edges at the room limits.** Each room's camera window is 1920 px wide and the camera
   travels 3840 px of level; a layer at `scroll_scale = 0.15` must therefore span ≥ 1920 + 0.15·3840
   ≈ 2500 px (author ~4200 px for margin), or use `RepeatSize`/`RepeatTimes` with a seamless band.
   Mitigation: oversize the layers; check every room edge in playtest.
4. **Smoke regressions.** `level_prologue.gd` walks the hero by physics and asserts HUD text at
   each beat; new colliders placed inside the walk band would break it (and the game). The
   collision rule and acceptance criterion 11 exist precisely for this. `enemy_wave.gd` asserts
   camera limits around a wave lock — the lookahead touches `GlobalPosition` only.
5. **Hit-stop and pause.** Any FX using `Engine.TimeScale`, an always-processing timer, or a
   `Tween` bound to a freed node could freeze the game or leak. Contract: FX use scaled,
   non-always timers; the shake writes an exact zero at the end and in `_ExitTree`; `ImpactFx`
   frees itself on `Finished` **or** on its guard timer, whichever first, `IsInstanceValid`-guarded.
6. **Headless has no GPU particles.** Tests must assert flags and lifetimes only. A test that waits
   for `GpuParticles2D.Finished` will hang into the 60 s runner timeout.
7. **Merge conflicts with T-07i-b.** That branch rewrites `Player.tscn`/`Guard.tscn`/`Dummy.tscn`
   and `Player.cs`'s visual wiring. T-07i-c touches `Player.cs` only to add the `Landed` signal
   and (nice-to-have N3) `PH_Shadow.z_index`. Rebase on the final T-07i-b before the fix pass; do
   N3 last or skip it.
8. **`Cutscene.MinLineTime` (N2) can break `level_prologue.gd`'s tap loop.** Either implement both
   together or skip N2.
9. **Scope creep.** The dressing list is long; M1–M9 is the contract, N1–N5 is optional. A
   half-finished room is worse than three consistently dressed ones — dress room by room.
10. **`ProcessMode.Disabled` on an FX group** also removes any `CollisionObject2D` under it from
    the physics space. FX groups must contain no collision shapes (they do not, by design) — a
    reviewer check.

---

## Open questions

1. **`PH_` prefix for finished vector art.** CLAUDE.md reserves `PH_` for placeholders; the T-07i
   brief reframes procedural vector graphics as real art. **Default taken by this plan:** new
   *scene files* get real names (`ImpactFx.tscn`, `Vignette.tscn`), while individual flat-colour
   nodes inside level scenes keep the `PH_` prefix, consistent with everything already in
   `Level00_Prologue.tscn`, and **no existing node is renamed** (renames would break `node_paths`
   and smoke assertions). If the author prefers a clean break, it is a separate rename task across
   all scenes, not this one.
2. **Vignette strength.** Planned at `OutlineDark @ 0.55` at the screen edge. Purely taste; the
   playtest decides, and it is a one-value change in `Vignette.tscn`.
3. **The engine clear colour below the level content** is closed here by the near band; whether the
   project ever wants a global `default_clear_color` / letterbox is deferred to backlog **T-B10**
   (it would touch `project.godot` and needs `/project-settings`).

---

## Resolved (agent decision, 2026-09-10 — author asleep, routine defaults; may be overturned)
1. **`PH_` prefix — keep the plan's default.** New scene files get real names; existing nodes are
   NOT renamed, because renames break `node_paths` and smoke assertions for no visual gain. A
   project-wide rename is a separate task if the author ever wants one.
2. **Vignette — `OutlineDark @ 0.55`**, as planned; it is an `[Export]`, so the playtest can retune it.
3. **Near band closes the empty bottom of the frame** — approved, and it is a `must`, not a
   nice-to-have: an engine clear colour filling 40% of the screen is the single most "unfinished"
   thing on screen right now.
4. **Backlog numbering — renumber.** T-07i-a's plan claims `T-B03`–`T-B05` and T-07i-b's claims
   `T-B06`–`T-B08`. This plan's four backlog rows become **`T-B09`** (процедурний шейдер породи),
   **`T-B10`** (порожня зона за межами рівня), **`T-B11`** (спільний параллакс-кіт рівнів) and
   **`T-B12`** (єдиний ефект попадання для ворогів); update every in-plan cross-reference to the
   old ids at the same time.
5. **Motionless fan in room 2 — approved.** It matches §3 (Rey cannot start it) and the existing
   prologue script; the rotating exhaust fan belongs in room 1, as planned.


## Review findings

### Round 1 — Ship: no

#### Plan conformance
Plan: `docs/plans/t07i-c-level-dressing/t07i-c-level-dressing-plan.md` (read in full, `## Resolved`
included). TASKS.md: **wrong at review time** — T-07i-c is still `todo`, with no
Зроблено / Не зроблено / Рев'ю / Плейтест note and no T-B09–T-B12 backlog rows (S3).

- Implemented as planned: all of **M1–M9**. Parallax (`Parallax/PxRockFar|PxRockMid|PxStruct`,
  z −100/−80/−60, scroll_scale 0.15/0.35/0.55) plus `Foreground` (`Parallax2D`, z 40,
  scroll_scale 1.25); `Backdrop` (z −40) with per-room tone, tiled `NoiseTexture2D` grain, strata,
  dirt patches, a jagged ceiling rock lip, a second pipe run with valve wheels and three warning
  signs; `Ground` (z −20) with per-room floor tone (warm rust / cold steel / warm), floor grain,
  10 stains, the readable `PH_ShadowLane` for room 3, a puddle with a pale rim, four light shafts
  and `PH_NearBand` (x −400…6160, y 604…1140) with edge, 17 sleepers and two rails; 15 new props in
  a `y_sort_enabled` `Props` group, three of them with a `Blocker`; `Fx_Room1/2/3` (z 20) with
  7 emitters, the scrolling conveyor (`Sprite2D.region_rect` on an `AnimationPlayer` loop), the
  turning extractor fan in **room 1** while room 2's fan stays motionless, drips, and the dead
  panel's sparks + light; `FlickerLight` on both work lamps; `ImpactFx` + `LevelFx` (spark and
  flash on every landed hit, dust on landing, shake by `HitStopFrames`); `ShakeCamera` and the
  camera lookahead in `LevelBase`; `Vignette.tscn` on `CanvasLayer 5`; the `Interactable`→HUD
  forwarding moved into `LevelBase` with the prologue keeping its priority as a
  `RefreshPrompt()` override; `RoomBounds.Fx` per-room gating; `Player.Landed`.
- Deviates from plan (all deliberate, none a bug):
  1. **`Camera.ResetSmoothing()` in `ApplyRoomBounds` — not implemented.** `LevelBase.cs`,
     `ApplyRoomBounds`. The plan asks for it, but M6 and playtest step 5 both require the
     door-hop camera travel to stay *exactly* as before, and `limit_smoothed = true` is what
     produces that travel; `ResetSmoothing` would snap it. There is also no opening sweep to fix:
     every prologue room is exactly one viewport wide, so the camera is pinned at the room centre.
     The two plan statements contradict each other and the playtest/M6 side was taken.
  2. **Parallax layers use `repeat_size` + `repeat_times` instead of ~4200 px of hand-authored
     width** (`Level00_Prologue.tscn`, the four `Parallax2D` nodes). Verified empirically that
     `Parallax2D.position = camera_top_left * (1 − scroll_scale)`, so the required local span
     depends on the viewport width — and `window/stretch/aspect="expand"` makes that width
     unknown. Tiling removes plan risk #3 (layer edges at the room limits) outright.
  3. **No `CanvasItemMaterial blend_mode = Add` on the spark particles.** `CanvasModulate` at 0.04
     multiplies an additive item to nothing, so visibility comes entirely from the effect's own
     `PointLight2D`, which is the mechanism the plan's Option 5 chose. Adding both would fight.
  4. **`PH_Wall_1..3` are now translucent (alpha 0.72)** and palette-aligned
     (`Level00_Prologue.tscn`, the three wall `ColorRect`s). The walls are opaque `ColorRect`s
     covering y 0…300 across the whole level; at full alpha the whole parallax stack at z ≤ −60
     would be invisible. The plan sanctions "palette-aligned colours change on them"; this is the
     colour change that makes M1 observable at all. Residual risk: purely a look call — playtest
     steps 1–2 decide.
  5. **`FlickerLight` is attached to the existing `PH_WorkLamp_1` / `PH_WorkLamp_2`**, which are
     root children, not children of `Fx_Room1` / `Fx_Room2` as the ambient-FX inventory lists.
     The plan itself says the script goes "on `PH_WorkLamp_1`", and existing nodes must not be
     reparented, so the inventory row is the stale half. Residual risk: two `_Process` lerps keep
     running for off-camera rooms — one `RandfRange` at intervals plus one lerp each.
- Missing / partial: **N1–N5 are all out** except the drip+puddle half of N1 (no ripple, no cable
  sway, no alarm haze cones). N2 (cutscene fade / `MinLineTime`) deliberately skipped so
  `level_prologue.gd` could stay byte-identical — which it did, and that is the regression proof
  the plan asked for.
- Accepted limitation (per plan): the parallax reads only in lamp-lit stretches (plan risk #1) —
  residual risk: in the unlit halves of the level the three planes are near-black and the depth
  cue is carried by the near band and the foreground lip alone.
- Not in the plan, worth naming: **the camera lookahead is currently unobservable.** Every room
  (and `TestRoom`) is exactly 1920 px wide with camera limits to match, so the clamped screen
  centre never moves; only `Camera.GlobalPosition` leads, which is what the smoke test measures.
  The feature is correct and will show itself on the first room wider than the screen (T-08).

#### Code
- [x] **S1. `Props/Ladder_1` breaks the plan's collision rule** — `scenes/levels/Level00_Prologue.tscn`,
  node `Props/Ladder_1` (position `(330, 596)`) — Should-fix
  **Problem / why it matters:** the rule the plan calls non-negotiable says a prop whose visual
  base sits inside the walk band 300…600 must either carry a `Blocker` or be a flat floor decal at
  z −20 with no body. The ladder's base is at y 596 — inside the band — and it lives in `Props`
  at z 0 with no body. Concrete consequence: the ladder lies flat on the floor by the hatch, but
  because `Props` is y-sorted it is drawn **in front of** a hero standing at y < 596, so walking
  past x≈330 at y≈520 puts Rey behind a ladder that is supposedly on the ground. The plan's own
  prop table marks it `col = no` and calls it "decal-like", so the two halves of the plan
  disagree; the rule is the half that describes the visible defect.
  **Solution options:**
  - Option A (correct): move `Ladder_1` out of `Props` into the `Ground` group (z −20) with a
    small relative `z_index` so it draws above the floor tone/grain overlays and below every
    character — i.e. treat it as the floor decal the plan's table already calls it.
  - Option B (quick): give it a `Blocker`, which turns a flat ladder into an invisible wall in the
    hero's starting corridor. Rejected.
- [x] **S2. The enemies still flash by their own mechanism** — `scripts/levels/LevelFx.cs`, `_Ready` — Should-fix
  **Problem / why it matters:** `LevelFx` listens to `Player.Hitbox.Hit`, `Player.Hurt`,
  `Player.KnockedOut` and `Player.Landed`, which matches the plan ("Guards' hits on the hero are
  already covered by `Hurt`"). But `Dummy`/`Guard` keep their own `FlashColor` tween, so a hit now
  produces two independent visual reactions with different rules. Left alone in this task by
  design; the risk is that the two drift.
  **Fix:** make sure the backlog row **T-B12** ("єдиний ефект попадання для ворогів") actually
  lands in `docs/TASKS.md` so the duplication is on record (part of S3).
- [x] **S3. `docs/TASKS.md` bookkeeping missing** — `docs/TASKS.md`, the T-07i-c heading — Should-fix
  **Problem / why it matters:** T-07i-c is still `todo`, there is no
  **Зроблено / Не зроблено / Рев'ю / Плейтест** note in the T-07 format, and the four backlog rows
  the plan reserves (**T-B09** procedural rock shader, **T-B10** empty area outside the level in
  the camera, **T-B11** shared level parallax kit, **T-B12** one hit effect for enemies) are
  absent. Without them the deferred work and the accepted deviations above are lost.
  **Fix:** set the status to `done`, add the four-line note, add T-B09–T-B12 with the renumbering
  the plan's `## Resolved` item 4 mandates, and fix the plan's own stale `T-B03`–`T-B06`
  cross-references under **Out of scope**.

#### Tests
- [x] **T1. The dead panel's sparks are never asserted to ignite** — the whole point of playtest
  step 7 is that «Немає живлення» starts a permanent discharge. `level_dressing.gd` only proves
  the sparks stay **off** (group `fx_manual`, gating never touches them) and that the exports
  resolve. Cover it in `tests/smoke/level_dressing.gd`: emit `Door_1.Entered(player)` to push the
  stage to `Ventilation`, then emit `FanPanel.FailedNoPower()`, and assert `PanelSparks.emitting`
  and `PanelSparkLight.enabled` both become true.
- [x] **T2. `LevelFx` is never proven to actually spawn an effect** — the wiring is asserted
  (`Level`, `Player`, `ImpactFxScene`), but no test shows an `ImpactFx` appearing from a hero
  signal. Cover it in `tests/smoke/level_dressing.gd`: count `ImpactFx` children of the `TestRoom`
  around the existing jump and assert the landing dust puff appeared.

#### Nits
- `ImpactFx.Play` called twice on one instance leaves the first guard timer armed, so the second
  burst can be freed early — `scripts/fx/ImpactFx.cs`, `Play`. The XML doc already says "call
  once"; the spawner obeys it.
- `LevelBase._ExitTree` writes `Camera.Offset` without an `IsInstanceValid` guard —
  `scripts/levels/LevelBase.cs`, `_ExitTree`. Consistent with the existing unguarded `Player`
  dereference two lines above, so left alone.
- `PanelSparkLight` stays enabled after the hero leaves room 2 (disabling the group stops the
  emitter but not the light) — `scenes/levels/Level00_Prologue.tscn`, `Fx_Room2/PanelSparkLight`.
  Off-camera and one-way, so invisible.
- `Level00_Prologue`'s class doc still reads "The level owns the HUD prompt…"; ownership is now
  shared with `LevelBase` (the level owns only the priority) — `scripts/levels/Level00_Prologue.cs`.

#### What's done well
- **The existing scene was genuinely left alone.** No node reparented, no node renamed, no
  `node_paths` touched except the two new `PanelSparks` / `PanelSparkLight` entries and the three
  `RoomBounds.Fx` wirings — and `tests/smoke/level_prologue.gd` (856 lines of prologue flow) is
  byte-identical and green, which is exactly the regression proof the plan asked for.
- **Hit-stop and pause hygiene is right.** Nothing new touches `Engine.TimeScale`; `ImpactFx`'s
  guard timer is scaled and non-always so it freezes with both the hit-stop and the pause menu and
  can never outlive the level; the shake is driven by a remaining-time counter that writes an
  *exact* `Vector2.Zero` at the end and in `_ExitTree`. All three are asserted headlessly,
  including the paused case, which is the one nobody remembers to test.
- **The `Parallax2D` transform was measured, not guessed.** The layer offset formula
  (`camera_top_left * (1 − scroll_scale)`) was established empirically before authoring, and the
  answer led to tiling — which is why plan risk #3 cannot bite.
- **The frame budget is a test, not a promise:** the emitter/light census, the per-emitter `amount`
  cap and the "every light shadowless" rule are asserted over the whole loaded level, so the next
  level cannot quietly blow it.
- **`SetFxActive` uses a group opt-out (`fx_manual`) instead of special-casing the panel by name**,
  so the room gating and the level's own scripted emitter cannot fight, and the reason is in the
  XML doc.

#### Verdict
Ship: no — no Blockers, but S3 (TASKS.md bookkeeping) is mandatory before the task can be called
done, and S1 is a visible depth defect the plan's own rule predicts. Everything else is either an
accepted deviation or a Nit.
First: 1) S1 — `Ladder_1` into `Ground` as a floor decal; 2) S3 — TASKS.md status, note and
T-B09–T-B12 (plus the plan's stale backlog cross-references); 3) T1/T2 — panel-spark ignition and
a real `LevelFx` spawn in `level_dressing.gd`.

##### Fix pass (round 1) — all Should-fix and Tests items closed
- **S1 closed:** `Props/Ladder_1` moved into the `Ground` group (`z_index = 7`, i.e. −13 relative
  to Ground's −20) — a flat floor decal drawn above the floor tone/grain and below every character,
  with no body, exactly as the collision rule prescribes. `Props` now holds 14 props, still over
  the 12 the plan requires.
- **S2 closed:** the duplication is recorded as `T-B12` in `docs/TASKS.md`.
- **S3 closed:** T-07i-c is `done` with the four-line Зроблено / Не зроблено / Рев'ю / Плейтест
  note in the T-07 format, and `T-B09`–`T-B12` are in the backlog. This plan's own stale
  `T-B03`–`T-B06` cross-references were renumbered to `T-B09`–`T-B12` at the same time.
- **T1 closed:** `tests/smoke/level_dressing.gd` now pushes the stage with
  `Door_1.emit_signal("Entered", player)`, asserts `CurrentStage == Ventilation`, then emits
  `FanPanel.FailedNoPower()` and asserts `PanelSparks.emitting` and `PanelSparkLight.enabled`.
- **T2 closed:** the same script counts `ImpactFx` children of `TestRoom` inside the `Landed`
  handler (LevelFx is connected first, so its spawn has already happened) and asserts the landing
  dust puff exists — plus that no `ImpactFx` is in the room before anything happens.
- Nits left for the author, as recorded above.
