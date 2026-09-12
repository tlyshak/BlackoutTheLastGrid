# Plan — t-v2-01-prologue-v2 (T-V2-01 · Каркас v2: перемикач версій, асети, пайплайн спрайтів)

Branch `task/t-v2-01-prologue-v2-assets`, base commit `b5b3819`. Backlog: [`../../TASKS.md`](../../TASKS.md)
→ «Лінія v2», T-V2-01 (detailed here) and T-V2-02..04 (contract stubs only, §"Extension points").
Design: [`../../GAME_DESIGN.md`](../../GAME_DESIGN.md) §6a (two prologue versions), §3 (third story revision —
v2 tells the same story), §6 (art direction). Prior art this plan builds on:
[`../t07i-b-character-art/t07i-b-character-art-plan.md`](../t07i-b-character-art/t07i-b-character-art-plan.md)
(how the rig hangs on the `AnimationPlayer`, the frozen `HitboxOn/Off` times),
[`../t07s-e-dan-leads/t07s-e-prologue-v3-plan.md`](../t07s-e-dan-leads/t07s-e-prologue-v3-plan.md) (the v3
prologue map that v2 reproduces), [`../t07i-c-level-dressing/t07i-c-level-dressing-plan.md`](../t07i-c-level-dressing/t07i-c-level-dressing-plan.md)
(the procedural dressing v2 replaces).

Written by the architect only. No code, scenes, assets, `project.godot` or `TASKS.md` were touched; the TASKS.md
split is proposed in §"Task split" for the author to transfer.

---

## Goal

Build the **skeleton of the v2 prologue** next to the working v1 one (T-V2-01): a persisted **Game version:
v1 / v2** switch in Settings; New Game routed into `Main` (v1) or `v2/Main` (v2) with KO-restart and level
changes staying inside their version; a repeatable pipeline that turns the author's keyframe sheets
(`assets/art/v2/keyframes/*.svg`, 680×800, flat vector) into `SpriteFrames` driven by the **same
`AnimationPlayer` timings as v1**; v2 twins of `Player`/`Guard`/`Companion` that reuse the v1 scripts and
swap only the `Visual` subtree (`AnimatedSprite2D` instead of `CharacterRig`); a v2 `Level00_Prologue` that
is the v3 prologue with drawn backgrounds derived from the three mockups; and tests that prove **v1 did not
change**. The point of the skeleton is to let the author *see* the generated art in motion inside the real
prologue without touching v1 — every design decision below optimises for that, and every place where the art
and the frozen v1 metrics disagree is stated, not hidden.

## Scope

### In
- `GameSettings.GameVersion` (enum, `ConfigFile` persistence, signal), an `OptionButton` row in
  `SettingsMenu`, `Exposition` choosing `Main` vs `v2/Main`.
- `scenes/v2/**` twins: `Main`, `levels/Level00_Prologue`, `player/Player`, `enemies/Guard`,
  `actors/Companion` — same scripts, different scenes.
- Sprite pipeline: SVG import settings (`.import` sidecars), the region map
  (`assets/art/v2/keyframes/<sheet>.frames.json`, produced by the parallel agent — **an input, not a
  deliverable of this task**), a headless generator `tools/build_spriteframes.gd` that writes
  `scenes/v2/actors/*Frames.tres`, and an animation table `scenes/v2/actors/sprite_animations.json`.
- One additive script change in `Guard.cs` (`SetDown` plays a `down` animation when the scene has one; v1
  scenes have none and keep the 90° rotation) and one in `Exposition.cs` (`NextScenePathV2`).
- Drawn backgrounds: the derivative section files from `assets/art/v2/backgrounds/` (produced by the other
  agent — **an input**) placed under a `Backgrounds` node of the v2 level; `Room_Surface` keeps v1's
  procedural surface.
- Camera zoom for v2 (scene data only) — see Options §2.
- Smoke tests for the switch, routing, sprites, actor parity, level skeleton parity, backgrounds, and a git
  gate for "v1 untouched".
- Extension points for T-V2-02..04 (no code for them).

### Out
- Crowbar attacks, weapon state, tripwires, powerbanks-as-items (T-V2-02..04) — only their contracts.
- Any edit to files under `assets/art/v2/` other than generated `.import` sidecars (asset policy).
- Parallax layering of the drawn sections (needs layered derivatives — nice-to-have N4 if they appear).
- A v2 `TestRoom`/`TestMine`; v2 versions of Level 1+ (the v2 prologue exits into the shared
  `Level01_District.tscn`).
- Save/Load (T-09) — only the `CurrentScenePath` note.
- Re-authoring the floor band or any gameplay geometry for the art's proportions (see Design risks §1).

### Out of scope → `docs/TASKS.md` backlog (exact lines for the author to add)

```
### T-B26 · v2: пропорції хітбоксів під спрайти · `backlog`
- У v2 герой 108 px, а `Hurtbox` 32×64 / `Hitbox` 36×40 на висоті 16…56 px лишились від 72-px ріга (баланс заморожений у T-V2-01). Після плейтесту вирішити: лишити, або підняти/масштабувати форми **лише у сценах `scenes/v2/**`** (скрипти й `Damage`/`Knockback`/таймінги без змін).

### T-B27 · v2: параллакс із пошарових похідних секцій · `backlog`
- Якщо агент-різник дасть `*_far.svg` / `*_near.svg`, загорнути далекий шар у `Parallax2D (0.6, 1)` у `scenes/v2/levels/Level00_Prologue.tscn`. Без шарів — плоский фон (T-V2-01).

### T-B28 · v2: конус ліхтаря з мокапа як текстура `Flashlight` · `backlog`
- `assets/art/v2/backgrounds/cone.svg` (вирізаний конус) як `texture` ліхтаря у `scenes/v2/player/Player.tscn`; порівняти з `GradientTexture2D_beam` v1. Тільки вигляд — `PerceptionRange`/`LitZone` не чіпати.
```

---

## Design-doc conformance

| Requirement (task text / §6a) | Design doc | Plan |
|---|---|---|
| Switch **Game version: v1 / v2** in `SettingsMenu`, persisted via `GameSettings` | §6a "у Settings є перемикач … New Game веде у відповідний комплект сцен" | agree — `GameSettings.GameVersion`, `[game] version` in `user://settings.cfg`, `OptionButton` row |
| New Game → `Main` (v1) or `v2/Main` (v2); KO-restart stays in its version | §6a | agree — the branch is taken in `Exposition` (the exposition text is shared and must not be duplicated: §6a "текст і сюжет v2 = v3 без змін"); KO reloads the current scene (`v2/Main`), `GoToLevel` uses the v2 level's own `NextLevel` |
| Sprites from keyframes, stepped animation ~6–8 fps | §6a table, row "Персонажі" | agree — walk 4 phases / 0.6 s = 6.7 fps, attacks 3 keys / 0.3 s = 10 fps at the frozen hit times; idle is 4 keys over the cycle (2.5–3.3 fps — breathing is inherently slow; the doc's rate is for motion) |
| `Player`/`Guard`/`Companion` v2 — same scripts, other `Visual`, hitboxes/hurtboxes/balance unchanged | §6a "Спільне ядро … одне; сцени — різні" | agree — shapes, offsets, exports, animation lengths and method-track times are copied verbatim and **asserted equal by `v2_actors.gd`**. Two additive script changes (`Guard.SetDown`, `Exposition.NextScenePathV2`) keep v1 behaviour bit-for-bit |
| Derived backgrounds without characters from the three mockups; v2 prologue = copy of the v3 prologue | §6a rows "Фони", principle "арт v2 не редагується — лише похідні копії" | agree — the copies come from the other agent; this plan consumes them. The v2 level is a copy of the v3 scene with the same 87 root exports, asserted by `v2_level_skeleton.gd` |
| v1 never breaks | §6a principle | agree — no v1 `.tscn` is edited; `tools/check-v1-untouched.ps1` (git diff vs `main`) is an acceptance gate |
| v2 tells the same story (§3) | §3 third revision, §6a "Сюжет: та сама" | agree — cutscene lines and Dan's 30 cues are exports on the level root; the skeleton test asserts them equal to v1's |
| Weapons / tripwires / powerbanks everywhere | §6a rows | **T-V2-02..04**, contracts only (§"Extension points") |

**Silent in both documents → decided here (Open questions §1, §2):** the on-screen scale of the sprites
relative to the drawn backgrounds and to the frozen v1 metrics. The task says "balance unchanged", the art
says "hero = ¼ of the frame". They cannot both hold; §Options 2 and §Design risks 1 give the compromise.

No disagreement between task text and design doc was found. Task and design doc agree.

---

## Options considered

### 1. Where the v2 scenes live and how much is duplicated

- **(a) Separate scenes on the same scripts** — `scenes/v2/<same relative path>.tscn` with
  `script = res://scripts/<same path>.cs`. `Level00_Prologue.tscn` v2 is a full copy of the v1 scene with the
  same 87 root `[Export]` wirings (they are `NodePath`s — a copy keeps every path), the actor `ext_resource`s
  repointed to `scenes/v2/...`, the dressing groups replaced. Cost: a second 2 500-line scene; a gameplay fix
  in v1's map must be mirrored by hand. Mitigation: `v2_level_skeleton.gd` walks both trees and asserts the
  non-dressing node set (name, type, global position, collision layer/mask, shape) and every root export are
  equal — drift becomes a red test, not a surprise. **Chosen.**
- **(b) Inherited scene** (`[node instance=v1]` + overrides). Godot inherited scenes can override properties
  and add nodes but **cannot delete inherited nodes or swap the `PackedScene` an inherited node is an instance
  of**: the v2 level could only *hide* v1's `Player` and add a second one, leaving a hidden `CharacterBody2D`
  that still moves, senses `LitZone`s and reads input. Every future v1 edit would also leak into v2 and
  misalign the drawn backgrounds. Rejected.
- **(c) One level, `Visual` subtrees swapped by version at runtime.** `LevelBase.Player` is an `[Export]`
  wired in the `.tscn` and subscribed in `_Ready`; swapping actor scenes per version needs code in
  `_EnterTree` on every consumer, plus version checks in the level for the dressing. It edits the v1 scene and
  scripts heavily — the opposite of "v1 never breaks". Rejected.

Does `Level00_Prologue.cs` withstand (a)? Yes: it holds no scene path, no rig reference (`grep Rig` → none;
the three static rigs under `HeldGuards` are scene-only instances toggled via `HeldGuards.Visible`), and
`Main.cs` records whatever `StartLevel` it was given. `Player.Rig`/`Companion.Rig` are nullable and guarded
(`if (Rig is not null && Sprite.SpriteFrames is not null)`); `Companion.ApplyLightMask` copies `light_mask`
onto every `CanvasItem` descendant — an `AnimatedSprite2D` is one. `Guard.cs` has no `Rig` export at all.
The one script that assumes a rotatable rig is `Guard.SetDown` (see §3 change list).

### 2. Scale: sprites vs. frozen metrics vs. drawn backgrounds

Measured: sheet poses are ≈107 px tall (feet at pose-origin +32, head ≈ −75); mockup characters are
≈108 px in a 440-px frame (Ray: shadow y=404, head top ≈296; guard: 384 / 275). The v1 hero is 72 px, the
floor band is 300 px (4 hero heights); the mockup floor is ≈134 px (1.2 character heights). The ratio
(section scale ÷ sprite scale) that keeps the drawn floor at least as deep as the band is ≥ 2.2, i.e. **the
mine will be ≥2.2× larger relative to the people than the author drew it, whatever we do**, unless the band
is re-authored (out of scope: it would re-author the whole v3 map — gates, stripes, spawn rows, Dan's route).

| Option | World hero | On-screen hero (1080p) | Boxes vs body | Walk / jump vs body | Cost |
|---|---|---|---|---|---|
| A. `SpriteScale 0.67` → hero 72 px like the rig, sections scaled to match (0.67 → 456×295 px) | 72 | 72 (6.7 %) | as v1 | as v1 | backgrounds cover ¼ of the screen — absurd |
| B. `SpriteScale 1.5`, sections 2.8× (fill the screen), zoom 1 | 162 | 162 (15 %) | hurtbox covers 40 % of the body, punch box ends 17 px short of the drawn fist | 1.4 bodies/s, hop of 0.5 body | no camera change |
| **C. `SpriteScale 1.0` (hero 108 px), sections 1.88×, `Camera2D.zoom = 1.5`** | 108 | 162 (15 %) | hurtbox covers 60 % of the body, punch box reaches the drawn fist (48 vs ≈45 px) | 2 bodies/s, jump 0.74 body (v1 feel) | camera Y/zoom are scene data; world-space labels render 1.5× |
| D. as C with `zoom = 2.0` | 108 | 216 (20 %) | as C | as C | vertical window 540 px vs the 506 px the band + jump needs — no slack for the blast shake; labels 2× |

**Chosen: C** (zoom 1.5, default), with D as a one-number playtest alternative (Open question 2). C keeps every
frozen number *meaning* what it meant in v1 relative to the drawn body, and the same on-screen size as B.
Proportions (mine vs people) are identical in B, C and D — only the on-screen size differs — so the "cathedral
mine" compromise (pillars ≈ 3 hero heights instead of the drawn 1.6) is unavoidable; it is Design risk 1.

### 3. Who owns time: `AnimationPlayer` tracks vs. `SpriteFrames` fps

- **(A) `AnimationPlayer` stays the only clock.** Every v1 animation keeps its name, length and method-track
  times; its rig value tracks are replaced by two discrete value tracks `Visual/Sprite:animation` and
  `Visual/Sprite:frame`. The `AnimatedSprite2D` is a frame holder that is **never `Play()`ed** (`autoplay = ""`,
  animation speed irrelevant). Hit-stop (`Engine.TimeScale`) freezes it exactly as it freezes the rig;
  `Player.IsAnimationPlaying`/`AnimationTime`/`ResetPose` and `PlayerAttack`'s combo window are untouched;
  `Player.PlayAnimation` takes the same branch as in v1 (the `Sprite.Play` fallback is never reached). Frames
  hold until the next key — the stepped look §6a asks for. **Chosen.**
- (B) `AnimationPlayer` keeps only method tracks; the sprite plays its own `SpriteFrames` at N fps. Two
  clocks: hit-stop freezes one, a re-entered `hurt` restarts one, `RESET` cannot rewind the other. Rejected.
- (C) `Sprite2D:texture` keyed with `AtlasTexture`s per frame, no `SpriteFrames`. Works, but the empty
  `AnimatedSprite2D Sprite` slot was left in every actor precisely for `SpriteFrames`, `Player._Ready` and
  `Companion._Ready` test `Sprite.SpriteFrames`, and the editor previews `SpriteFrames`. Rejected.

Cross-fade between poses (two sprites, modulate tween) was considered and rejected: flat vector art ghosts
visibly during a fade; the SoR4 reference is held hand-drawn frames.

### 4. How `SpriteFrames` are produced

- (a) Hand-authored `.tres` — 20+ `AtlasTexture` sub-resources per sheet with hand-copied regions. Rejected.
- (b) Built at runtime from the JSON by a helper node/resource. No editor preview, JSON parsing at scene load,
  a runtime dependency on the map file. Rejected.
- **(c) A headless GDScript generator** (`tools/build_spriteframes.gd`, `extends SceneTree`, run with
  `godot --headless --path . -s tools/build_spriteframes.gd`) reads `<sheet>.frames.json` + the animation
  table and `ResourceSaver.save()`s `scenes/v2/actors/<Name>Frames.tres`. The `.tres` is committed and
  referenced by the v2 scenes; `v2_sprites.gd` rebuilds the expected regions from the JSON and asserts the
  `.tres` matches (single source of truth = the JSON; the `.tres` is a derived, reviewable artefact). No addon,
  no NuGet. **Chosen.**

### 5. Where the New-Game branch is taken

- (a) `MainMenu` picks `Exposition` vs a duplicated `scenes/v2/ui/Exposition.tscn` (zero script change,
  duplicated story text — exactly the drift §6a forbids). Rejected.
- **(b) `Exposition` reads `GameSettings.GameVersion` and picks `NextScenePath` (v1) or `NextScenePathV2`.**
  One branch point, one text. `MainMenu`, `Main.cs`, `LevelBase` unchanged. **Chosen.**
- (c) A path resolver on `GameSettings` mapping `res://scenes/X` → `res://scenes/v2/X` when it exists.
  Elegant but implicit; rejected for now (can be introduced when more scenes get v2 twins).

### 6. Three drawn sections onto four rooms

Rooms (v3 map): `Room_Face` (0…2880, segments 0+1: coalface, conveyor, blast, first fight), `Room_Drift`
(2880…5760, segment 2: timber, outlets, gas), `Room_Patrol` (5760…8640, segments 3+4: lit drift, cage),
`Room_Surface` (8640…10560, segment 5: surface). Sections: `section1_mineface` (face, conveyor, red lamps),
`section2_ventilation` (ducts, fan — the drift), `section3_exit` (the cage/exit).

- (a) Stretch each section to its room (×4.24 horizontally, ×2.8 vertically) — distorts. Rejected.
- (b) Mirror-tile (section, flipped copy, …) — doubles the conveyor, the cage, the fan. Rejected.
- **(c) One section per mine room, placed where its feature is, remainder filled with seamless
  pillar-to-pillar slices of the same section (`Sprite2D.region_enabled`), `Room_Surface` keeps v1's
  procedural surface** (the surface is a different palette and the emotional contrast beat; nothing drawn
  exists for it). **Chosen.** Mapping: Face ← section1 (conveyor end near the charge at 1400), Drift ←
  section2, Patrol ← section3 with the drawn cage aligned to `Hoist` at 8500.

---

## Recommended approach

1. **Switch.** `GameSettings.GameVersion : GameVersion { V1 = 0, V2 = 1 }`, default `V1`, persisted as
   `[game] version = <int>`; `GameVersionChanged(int)` emitted on real change. `SettingsMenu` gets a
   `VersionRow` (`Label "Game version"`, `OptionButton VersionOption` with items `v1` (id 0) / `v2` (id 1),
   a dim note "Applies to New Game"). `Exposition.OnFinished` changes scene to `NextScenePathV2` when
   `GameVersion == V2`, else `NextScenePath`. Nothing else in the run knows about versions.
2. **v2 scene set** (`scenes/v2/…`, scripts shared from `scripts/…`, no `scripts/v2/`): `Main.tscn`
   (`StartLevel` → v2 prologue), `levels/Level00_Prologue.tscn` (copy of v1, actors repointed, camera
   `zoom (1.5, 1.5)` / `position.y 450`, `HeldGuards` rigs → `Sprite2D`s, dressing → `Backgrounds`),
   `player/Player.tscn`, `enemies/Guard.tscn`, `actors/Companion.tscn`. Every v2 `.tscn` gets a **fresh
   `uid`** (duplicate uids are an import error).
3. **Sprite pipeline.** Import the four sheets at `svg/scale = 2.0` (1360×1600, crisp at zoom 1.5 with
   `Sprite.scale = 0.5`); generate `RayUnarmedFrames.tres`, `RayCrowbarFrames.tres`, `DanFrames.tres`,
   `GuardFrames.tres` from `<sheet>.frames.json` + `sprite_animations.json`; feet-align every frame with
   `AtlasTexture.margin` into one cell per sheet; the v2 `AnimationPlayer`s carry v1's names, lengths and
   method tracks with `Sprite:animation`/`Sprite:frame` discrete keys.
4. **Backgrounds.** Import the derivative sections at `svg/scale = 3.0`; place them as `Sprite2D`s at world
   scale 1.88 (node scale 0.627) with the drawn floor's far edge at world y ≈ 380 (offset −146), fill each
   room with slices, keep the black near lip, keep every gameplay light and decal.
5. **Tests** prove three invariants: v1 untouched (git gate + structural smoke), v2 == v1 in everything
   that is not `Visual`/dressing (actor parity, level skeleton parity, cutscene text parity), and the sprite
   data is consistent (regions inside the texture, every animation ≥1 frame, method times equal v1).
6. Ship as **three stacked PRs** (§"Task split") so the switch lands even if the map or the derivatives are
   late.

### Priorities

**Must:** switch + persistence + routing; v2 scene set; import settings; generator + 4 `.tres`; v2 actor
animations with v1 timings; `Guard.SetDown` → `down`; flat backgrounds on the three mine rooms; camera zoom;
`HeldGuards` sprites; all smoke tests in §Test strategy marked (must); `tools/check-v1-untouched.ps1`.
**Nice-to-have:** N1 walk cycle 0.45 s in the v2 scenes (less foot slide, see Design risks 2); N2 mockup
cone as the v2 flashlight texture (→ T-B28 if skipped); N3 `v2_level_prologue_escape.gd` /
`_patrol.gd` (the second and third thirds of the level on v2); N4 parallax from layered derivatives (→
T-B27); N5 a "dark" derivative without painted lamp glows for after the blast.

---

## GameState & save impact

**No `GameState` change.** Read/written as in v1: `MainMenu.OnNewGamePressed → GameState.ResetRun()`,
`Main._Ready → GameState.CurrentScenePath = StartLevel.ResourcePath` (now
`res://scenes/v2/levels/Level00_Prologue.tscn` in a v2 run), `LevelBase.GoToLevel → CurrentScenePath =
next.ResourcePath`. `Energy`, `Route`, `JournalsFound`, `DistrictReputation`, `EnergyChanged(float)` —
unchanged, same nodes.

**`GameSettings` (machine preference, not run state):** new `GameVersion` (enum `GameVersion`, default
`V1`, range `{V1, V2}`), persisted in `user://settings.cfg` under `[game] version`. It belongs on
`GameSettings`, not `GameState`, because it is chosen before a run exists, survives `ResetRun()`, and must
never be written into a save slot.

**For T-09:** `CurrentScenePath` already encodes the version through its path (`scenes/v2/…`). T-09 must
resume from the *path* and must not re-derive the scene from `GameSettings.GameVersion` (the player may have
flipped the setting between sessions). "Continue" (T-B05/T-B25) inherits the same rule.

---

## Scene & signal contract

`scene-design` output, per scene. All collision layers are the project's: 1 World, 2 Player, 3 Enemy,
4 PlayerHitbox, 5 EnemyHitbox, 6 Interactable, 7 LightDark (bits 1/2/4/8/16/32/64).

### A. Edited — `scenes/ui/SettingsMenu.tscn` ↔ `scripts/ui/SettingsMenu.cs`

Node tree change (inserted between `VolumeRow` and `AudioNote`):
```
Root/Panel/Margin/VBox/
  VersionRow            HBoxContainer   separation 16
    Label               Label           text "Game version", size_flags_horizontal 3
    VersionOption       OptionButton    items: "v1" (id 0), "v2" (id 1); custom_minimum_size (160, 0)
  VersionNote           Label           text "Applies to New Game — the current run keeps its version",
                                        font_size 16, colour as AudioNote
```
New `[Export] OptionButton VersionOption` (wired in the root's `node_paths`). Bindings: `VersionOption.ItemSelected(long index)` →
`_settings.GameVersion = (GameVersion)VersionOption.GetItemId((int)index)`; `_settings.GameVersionChanged(int)` →
`VersionOption.Select(VersionOption.GetItemIndex(version))` (`Select` does not emit `item_selected`, so the
sync never writes back); `SyncFromSettings()` selects the current value on `Open()`. Connect in `_Ready`,
disconnect in `_ExitTree`, exactly like the fullscreen/volume pairs. `Close()` still saves.

### B. Edited — `scripts/core/GameSettings.cs` (autoload script, no scene)

```csharp
public enum GameVersion { V1 = 0, V2 = 1 }
[Signal] public delegate void GameVersionChangedEventHandler(int version);   // enum as int for GDScript/tests
[Export] public GameVersion DefaultGameVersion { get; set; } = GameVersion.V1;
public GameVersion GameVersion { get; set; }  // emits GameVersionChanged only on a real change; no apply step
```
`Load()`: `[game] version` read as int, clamped to the enum range, else `DefaultGameVersion`. `Save()` writes it.
No new autoload, no InputMap action.

### C. Edited — `scripts/ui/Exposition.cs` (scene `scenes/ui/Exposition.tscn` **untouched**)

`[Export(PropertyHint.File, "*.tscn")] string NextScenePathV2 = "res://scenes/v2/Main.tscn"`.
`OnFinished`: `string next = GameSettings.Instance is { GameVersion: GameVersion.V2 } && NextScenePathV2.Length > 0 ? NextScenePathV2 : NextScenePath;`
then the existing deferred `ChangeSceneToFile(next)`. The v1 `.tscn` keeps `NextScenePath = res://scenes/Main.tscn`
and never sets the new export (the code default is enough), so it stays byte-identical.

### D. Edited — `scripts/enemies/Guard.cs` (both Guard scenes)

```csharp
private static readonly StringName AnimDown = "down";
public void SetDown(bool down)
{
    if (AnimationPlayer.HasAnimation(AnimDown))
    {
        if (down) PlayAnimation(AnimDown); else ResetPose();
        return;
    }
    Visual.Rotation = down ? Mathf.Pi / 2f : 0f;   // v1: no `down` animation → unchanged behaviour
}
```
`GuardDown.Enter` order (`ResetPose(); ReleaseAttackSlot(); SetDown(true)`) stays valid: `ResetPose` stops
the player, `SetDown(true)` then plays `down`. `GuardDown.Exit → SetDown(false) → ResetPose()` puts the stand
pose back before `Approach` plays `walk`. `Guard.ResetPose` still ends with `Stop(keepState: true)` — never
read `CurrentAnimationPosition` after it (T-07i-b trap).

### E. New — `scenes/v2/player/Player.tscn` ↔ `scripts/player/Player.cs` (`partial class Player : CharacterBody2D`)

Identical to v1 except the `Visual` subtree and the animation library:
```
Player (CharacterBody2D)            layer 2, mask 1, motion_mode 1 — as v1; exports as v1 except Rig unset
  PH_Shadow (Polygon2D)             visible = false  (the sheet bakes a shadow into every pose — see Risks 6)
  Visual (Node2D)                   position (0, −36)          ← SpriteFeetOffset 36 unchanged
    Sprite (AnimatedSprite2D)       sprite_frames = RayUnarmedFrames.tres, scale (0.5, 0.5), centered = true,
                                    autoplay = "", position (0, 36 − cellH·0.5/2)  → feet at Visual-local +36
    Hurtbox (Area2D)                layer 2, mask 0, monitoring false, RectangleShape2D 32×64 at (0,0) — as v1
    Hitbox (Area2D, Hitbox.cs)      layer 8, mask 4, RectangleShape2D 36×40 at (30,0) — as v1
  AnimationPlayer                   library "" = v2 animations (table §"Animation table")
  CollisionShape2D                  capsule r7 h28 rotated — as v1
  LightSensor / InteractionArea     as v1 (mask 64 / mask 32)
  Flashlight (PointLight2D, Flashlight.cs)   as v1, HeadOffset = 92 (cosmetic: the lamp is on the head of a 108-px body)
  StateMachine + 10 states          as v1, same exports (Damage 5/5/8/12, Knockback 60/60/160/200, HitStopFrames 4/4/5/5, windows)
```
`Rig` export left empty (`null`). No `[Export]` defaults change on the script. Signals: as v1
(`Hurt(float)`, `KnockedOut()`, `Landed()`, `StateChanged(string,string)`, `InteractableChanged(Interactable?)`).

### F. New — `scenes/v2/enemies/Guard.tscn` ↔ `scripts/enemies/Guard.cs`

As v1 (`layer 4, mask 1`; `Hurtbox` layer 4 / mask 0, 32×64; `Hitbox` layer 16 / mask 2, 36×40 at (30,0);
`HpLabel` at offset_top −130 instead of −100) with `Visual/Sprite` = `GuardFrames.tres` (scale 0.5, feet
aligned as in E), no `Rig`, `PH_Shadow` hidden, library = v2 guard animations **plus `down`**.

### G. New — `scenes/v2/actors/Companion.tscn` ↔ `scripts/actors/Companion.cs`

As v1 (`layer 0, mask 1`, `Visual.light_mask = 3`) with `Visual/Sprite` = `DanFrames.tres` (scale 0.5, feet
aligned), no `Rig`, `PH_Shadow` hidden, `PH_DanLight` at `(0, −45)` (was −24; `range_item_cull_mask = 2`
unchanged — `ApplyLightMask` copies mask 3 onto the sprite), `Bubble` offsets −150…−114 (was −116…−80).
Library: `idle`, `walk`, `RESET`.

### H. New — `scenes/v2/levels/Level00_Prologue.tscn` ↔ `scripts/levels/Level00_Prologue.cs`

A copy of v1 with:
- `ext_resource` `2_player` → `scenes/v2/player/Player.tscn`, `26_companion` → `scenes/v2/actors/Companion.tscn`,
  `28_guard` → `scenes/v2/enemies/Guard.tscn` (this also repoints `GuardWave.EnemyScene` and the three
  `Patrol/Guard_*`), `14_rig` removed; `29_pickup` (`EnergyPickup.tscn`) and `12_next` (`Level01_District.tscn`)
  stay shared.
- Root: same 87 exports, same values (asserted). `Camera2D`: `zoom = (1.5, 1.5)`, `position = (960, 450)`
  (window 90…810 world px: far-edge feet 300 − cell 120 − jump apex 80 = 100 ≥ 90; near-edge feet 600 + shadow
  ≤ 810). Limits unchanged (`RoomBounds.Rect` still 1080 tall; `WaveSpawner.LockRect (960,0,1920,1080)` unchanged).
- `HeldGuards/Overseer`, `PH_Guard_A`, `PH_Guard_B`: `Sprite2D` (`texture` = `AtlasTexture` sub-resource with the
  guard `stand` region ×2, `scale 0.5`, `flip_h` where facing −1), same positions; `PH_Gun` line kept under
  `Overseer`; `PH_HeldLamp` kept.
- **Dressing removed:** `Parallax/PxRockFar|Mid|Struct` and their children, `Backdrop/*`, `Ground/*`
  (except the Surface-room nodes), `Props/*`, `Foreground/PH_NearPost|Rim|Cable`, `PH_Wall_Face|Drift|Patrol`,
  `PH_Ceiling`, `PH_Floor_Face|Drift|Patrol`, `PH_FloorEdge`, `PH_Support_1..22`, `PH_Conveyor`, `PH_ConveyorEdge`,
  `PH_Coal_1..3`, `PH_CageShaft`, `PH_CageCable`.
- **Dressing kept:** everything with a collision shape or a light (`PH_WallLeft/Right/Shaft`, `WorkLamps`,
  `DriftLamps`, `PH_ArenaLamp`, `PH_Landmark_*` + bodies, `PH_Decals` light pools — the drawn detection
  rectangles of segment 3 — `PH_JamCarts`, `PH_Crate_Stack` visuals of the `JumpableObstacle`, `Fx_*`
  including `Fx_Face/Conveyor` (`ConveyorAnimation` export), `Foreground/PH_NearLip`, `Vignette`,
  `Darkness`, all `Room_Surface` nodes: `PH_Wall_Surface`, `PH_Floor_Surface`, `Parallax/PxSurface*`).
- **Added:** `Backgrounds` (`Node2D`, `z_index = −40`, not y-sorted):
  ```
  Backgrounds
    Section_Face    Sprite2D  texture section1 derivative (svg/scale 3), centered false, scale (0.6267, 0.6267)
                              position (0, −146)                       → covers x 0…1294, y −146…681
    Fill_Face_1..n  Sprite2D  same texture, region_enabled, region_rect = a pillar-to-pillar slice ×3
                              (e.g. mockup x 56…228 → region (168, 0, 516, 1320)), tiled x 1294…2880
    Section_Drift   Sprite2D  section2, position (2880 + 793, −146)   → x 3673…4967 (gas pocket 4410…4770 inside)
    Fill_Drift_*    …          tiled 2880…3673 and 4967…5760
    Section_Patrol  Sprite2D  section3, position (8640 − 1294 = 7346, −146) → the drawn cage lands at ≈8500
    Fill_Patrol_*   …          tiled 5760…7346
  ```
  (`0.6267 = 1.88 / 3.0`; section1's viewBox is 690×450, not 680×440 — its texture is 2070×1350 at
  `svg/scale 3`; use per-section sizes.) `Backgrounds` has no collision and no script.
- `Foreground` (`Parallax2D`, z 40) keeps only `PH_NearLip` moved down so it starts at y ≥ 681 (the section's
  bottom bar); the lip fills 681…810.
- No new signals; every connection is the one v1 makes (`Level00_Prologue.cs` connects by export).

### I. New — `scenes/v2/Main.tscn` ↔ `scripts/Main.cs`

`Main (Node)`, `StartLevel = scenes/v2/levels/Level00_Prologue.tscn`. Fresh uid.

### J. New resources — `scenes/v2/actors/*Frames.tres`, `scenes/v2/actors/sprite_animations.json`

Generated `SpriteFrames` (see §"Sprite pipeline"). No scripts.

### K. New tool — `tools/build_spriteframes.gd` (`extends SceneTree`, headless, exits 0/1)

Inputs: `assets/art/v2/keyframes/<sheet>.svg` (imported), `<sheet>.frames.json`, `scenes/v2/actors/sprite_animations.json`.
Output: `scenes/v2/actors/<Name>Frames.tres`. Prints the cell size per sheet (the coder copies it into
`Sprite.position`). Fails with a message if a pose referenced by the table is missing from the map.

### L. New tool — `tools/check-v1-untouched.ps1`

`git diff --quiet main -- <v1 file list>`; exit 1 with the list of differing files. The v1 file list:
`scenes/Main.tscn`, `scenes/levels/Level00_Prologue.tscn`, `scenes/player/Player.tscn`,
`scenes/enemies/Guard.tscn`, `scenes/actors/Companion.tscn`, `scenes/actors/CharacterRig.tscn`,
`scenes/ui/MainMenu.tscn`, `scenes/ui/Exposition.tscn`, `scenes/levels/TestRoom.tscn`,
`scenes/levels/TestMine.tscn`, `scenes/levels/Level01_District.tscn`, `project.godot`,
`BlackoutLastGrid.csproj`, `assets/art/v2/**/*.svg`.

---

## Sprite pipeline (the contract `/coder` implements)

### Inputs
- Sheets: `assets/art/v2/keyframes/{rey_unarmed,rey_crowbar,dan,guard}_keyframes.svg`, viewBox 680×800.
  Rows (title text at y=12/212/412/612, separators at y=160/360/560/760, pose groups
  `<g transform="translate(x, y)">` with row origins **y = 130 / 330 / 530 / 730**, feet at local **+32**
  (the baked shadow ellipse sits at cy=+32, ry=5), head ≈ −75 → poses ≈107 px tall.
- Region map (parallel agent): `assets/art/v2/keyframes/<sheet>.frames.json` = `{ "<pose>": {"x","y","w","h"} }`
  in viewBox px (bounding boxes, shadow included). If the map also carries an origin (`ox`,`oy`) the generator
  uses it; otherwise anchor = (bbox centre x, bbox bottom).
- Canonical pose ids the animation table references (the coder reconciles names with the map; the smoke test
  asserts every referenced id exists):

| Sheet | Row 1 (y 130) | Row 2 (y 330) | Row 3 (y 530) | Row 4 (y 730) |
|---|---|---|---|---|
| `rey_unarmed`, `dan` | `stand`(70) `walk_1`(170) `walk_pass`(270) `walk_2`(370) `jump_crouch`(490) `jump_air`(600) | `atk_windup`(90) `atk_hit`(250) `atk_exit`(400) `kick`(540) | `hit`(90) `knockback`(260) `knockdown`(470) | `idle_1`(70) `idle_2`(190) `idle_3`(310) `idle_4`(430) |
| `rey_crowbar` | as above | `atk_windup`(90) `atk_hit`(250) `atk_exit`(430) | as above | as above |
| `guard` | `stand`(70) `walk_1`(190) `walk_pass`(310) `walk_2`(430) | `telegraph`(90) `lunge`(260) | `hit`(80) `stagger`(220) `fly`(400) `knockdown`(556) | `idle_1..4` (70/190/310/430) |

(numbers = pose origin x from the sheet's `translate`.)

### Import settings (`.import` sidecars — asset *settings*, not art; committed per `.gitignore`)
- First `godot --headless --path . --import` creates `<file>.svg.import` for every SVG under `assets/art/v2/`.
- Edit `[params]`: sheets `svg/scale=2.0` (→ 1360×1600 RGBA, 8.7 MB each; only the three prologue sheets are
  loaded at runtime); derivative sections `svg/scale=3.0` (→ 2040×1320 / 2070×1350, ≈11 MB each); original
  mockups keep defaults (never referenced at runtime → never loaded). `mipmaps` off (no minification below
  0.5×zoom-1.5 = 0.75), filter default (linear). Re-run `--import`. `project.godot` is **not** touched.
- Godot's SVG rasteriser (ThorVG) ignores `<text>` (labels vanish — good), the C2PA `<metadata>` blob, and
  **does not render `<pattern>` fills** (`hatch`/`dots`/`grate`/`stripes` in the mockups) — tell the derivative
  agent to replace pattern fills with flat colours in the copies (Risks 3). Verify imported sizes in `v2_sprites.gd`.

### Generator (`tools/build_spriteframes.gd`)
For each sheet: load the texture, `s = tex.get_width() / 680.0` (= the import scale; section1-style 690-wide
files are not sheets). Cell = `(max w, max h)` over the poses used, ×s. For every animation in the table, one
`SpriteFrames` animation with **its pose sequence in order** (duplicates allowed, so the `AnimationPlayer`
`frame` keys are simply `0,1,2,…`), `loop = false`, `speed = 1.0` (never played). Each frame is an
`AtlasTexture { atlas = sheet, region = Rect2(x,y,w,h)·s, margin = Rect2(left, top, cellW − w·s − left, cellH − h·s − top) }`
with `left = cellW/2 − (anchorX − x)·s`, `top = cellH − h·s` (bottom-aligned feet, centred anchor). Writes
`scenes/v2/actors/<Name>Frames.tres`; prints `CELL <sheet> <w> <h>`.

### Animation table (`scenes/v2/actors/sprite_animations.json`) and the v2 `AnimationPlayer`s
Lengths and method-track times are **v1's, frozen** (T-07i-b rule); keys are `Visual/Sprite:animation`
(track 0, discrete) and `Visual/Sprite:frame` (track 1, discrete), frames listed = the `SpriteFrames`
animation's frame order.

| Actor · animation | Length | Keys (time → pose) | Method track (unchanged) |
|---|---|---|---|
| Player `idle` (loop) | 1.6 | 0 idle_1 · 0.4 idle_2 · 0.8 idle_3 · 1.2 idle_4 | — |
| Player `walk` (loop) | 0.6 (N1: 0.45) | 0 walk_1 · 0.15 walk_pass · 0.30 walk_2 · 0.45 walk_pass | — |
| Player `jump` | 0.25 | 0 jump_crouch · 0.10 jump_air (holds) | — |
| Player `light_1` | 0.30 | 0 atk_windup · 0.08 atk_hit · 0.18 atk_exit | HitboxOn 0.08 / HitboxOff 0.18 |
| Player `light_2` | 0.30 | as light_1 (no second punch drawn — Design risks 3) | 0.08 / 0.18 |
| Player `light_3` | 0.40 | 0 atk_windup · 0.12 kick · 0.24 atk_exit | 0.12 / 0.24 |
| Player `heavy` | 0.55 | 0 atk_windup · 0.22 atk_hit · 0.36 atk_exit (the long wind-up hold *is* the heavy read) | 0.22 / 0.36 |
| Player `hurt` | 0.30 | 0 hit · 0.12 knockback; `Visual:modulate` flash as v1 | — |
| Player `ko` | 0.60 | 0 knockback · 0.30 knockdown; `Visual:modulate` grey as v1; **no `Visual:rotation` track** | — |
| Player `RESET` | 0.001 | `Sprite:animation = idle`, `frame = 0`, `Visual:modulate` white, `Visual:rotation` 0 | — |
| Guard `idle`/`walk` | 1.6 / 0.6 | as Player | — |
| Guard `attack` | 0.55 | 0 telegraph · 0.30 lunge · 0.45 stand (the sheet's "telegraph 0.3 s" equals v1's HitboxOn) | HitboxOn 0.30 / HitboxOff 0.40 |
| Guard `hurt` | 0.25 | 0 hit · 0.12 stagger | — |
| Guard `ko` | 0.60 | 0 fly · 0.30 knockdown; no rotation | — |
| Guard `down` (**v2 only**) | 0.10 | 0 knockdown (holds) | — |
| Guard `RESET` | 0.001 | animation idle, frame 0, `Visual:rotation` 0, `Visual:modulate` as v1 | — |
| Companion `idle`/`walk`/`RESET` | 1.6 / 0.6 / 0.001 | as Player (Dan sheet) | — |

`AnimatedSprite2D` rules: `autoplay = ""`, never `Play()`; `animation` track index below the `frame` track so a
key that changes both applies the animation first; `frame_changed` unused. Facing flip = `Visual.scale.x`
as v1 (sheets face right; `Facing = 1` unflipped). Hit-stop, `ResetPose`, `IsAnimationPlaying`, `AnimationTime`
— unchanged code paths. The `RayCrowbarFrames.tres` is generated with the shared names (`idle`, `walk`,
`jump`, `hurt`, `ko`) plus `crowbar_windup/hit/exit` frames under `crowbar_1` so T-V2-02 can swap
`Sprite.SpriteFrames` without breaking the shared animations.

---

## File-level change list

Order matters for the stacked PRs (§"Task split"): A-files land first.

### `scenes/`
- **(A) edit** `scenes/ui/SettingsMenu.tscn` — `VersionRow` (`Label`, `OptionButton VersionOption`), `VersionNote`; root `node_paths` += `VersionOption`.
- **(A) new** `scenes/v2/Main.tscn` — `Main.cs`, `StartLevel` → v2 prologue; fresh uid.
- **(A) new** `scenes/v2/levels/Level00_Prologue.tscn` — in PR-A an exact copy of v1 (v1 actors, v1 dressing) except the uid: proves routing and the parity test; PR-B repoints actors + camera + `HeldGuards`; PR-C swaps the dressing for `Backgrounds`.
- **(B) new** `scenes/v2/player/Player.tscn`, `scenes/v2/enemies/Guard.tscn`, `scenes/v2/actors/Companion.tscn` — contracts E/F/G.
- **(B) new** `scenes/v2/actors/RayUnarmedFrames.tres`, `RayCrowbarFrames.tres`, `DanFrames.tres`, `GuardFrames.tres` — generated; `scenes/v2/actors/sprite_animations.json` — the table.
- **untouched, asserted:** every v1 `.tscn` (list in contract L).

### `scripts/`
- **(A) edit** `scripts/core/GameSettings.cs` — `GameVersion` enum/property/signal/persistence (contract B).
- **(A) edit** `scripts/ui/SettingsMenu.cs` — `VersionOption` export and bindings (contract A).
- **(A) edit** `scripts/ui/Exposition.cs` — `NextScenePathV2`, version pick (contract C).
- **(B) edit** `scripts/enemies/Guard.cs` — `SetDown` prefers a `down` animation (contract D).
- **untouched:** `Player.cs`, `Companion*.cs`, `Guard*State.cs`, `LevelBase.cs`, `Main.cs`, `MainMenu.cs`, `Level00_Prologue.cs`, `CharacterRig.cs`, `GameState.cs`.

### `tools/`
- **(B) new** `tools/build_spriteframes.gd` (+ its `.uid`) — contract K.
- **(A) new** `tools/check-v1-untouched.ps1` — contract L.

### `assets/` (side files only — no art created, changed, renamed or deleted)
- **(B) new** `assets/art/v2/keyframes/*.svg.import` — generated, `svg/scale=2.0`.
- **(C) new** `assets/art/v2/backgrounds/*.svg.import` — generated, `svg/scale=3.0`; `assets/art/v2/level0/*.svg.import` — generated, defaults.
- **inputs, not deliverables:** `assets/art/v2/keyframes/*.frames.json` (parallel agent), `assets/art/v2/backgrounds/*.svg` (derivative agent). Expected derivative names: `level0_section1_mineface_clean.svg`, `level0_section2_ventilation_clean.svg`, `level0_section3_exit_clean.svg`; optional `cone.svg`, `beam.svg`, `*_far.svg`/`*_near.svg`.

### `tests/smoke/`
- **(A) extend** `core_settings.gd` — `GameVersion` default, round-trip, signal-once.
- **(A) edit** `ui_menu.gd`, `ui_exposition.gd` — pin `GameVersion = 0` right after the `ConfigPath` redirect (otherwise a persisted "v2" on the dev machine re-routes them).
- **(A) new** `ui_settings_version.gd`, `ui_version_routing.gd`, `v2_level_skeleton.gd`, `v2_v1_untouched.gd`.
- **(B) refactor** `level_prologue.gd` — `NAME`/`MAIN_PATH`/`PROLOGUE_PATH` become overridable funcs (`_name()`, `_main_path()`, `_prologue_path()`); behaviour unchanged. **(B) new** `v2_level_prologue.gd` (`extends "res://tests/smoke/level_prologue.gd"`, overrides the three), `v2_sprites.gd`, `v2_actors.gd`.
- **(C) new** `v2_backgrounds.gd`. **(N3)** `v2_level_prologue_escape.gd`, `v2_level_prologue_patrol.gd` the same way.

### `docs/`
- `docs/TASKS.md` — **not edited by the architect**; the author transfers §"Task split" and the three backlog lines. `/coder` sets the status lines when running.

### `project.godot` / `.csproj`
- **No change.** No autoload (`GameVersion` lives on the existing `GameSettings`), no InputMap action, no physics layer, no package. `.import` sidecars are asset import settings; the commit body still documents them:
  `assets: import settings for assets/art/v2 (sheets svg/scale=2.0, derivative sections svg/scale=3.0); no art changed`.
  `project-settings` skill therefore not triggered; if `/coder` finds it must touch `project.godot` (e.g. `rendering/textures/canvas_textures/default_texture_filter`), stop and run the skill first.

---

## Extension points for T-V2-02..04 (contracts the skeleton must leave)

| Task | What it needs from the skeleton | Left by T-V2-01 | Added later (not now) |
|---|---|---|---|
| **T-V2-02 crowbar** | a second `SpriteFrames` with the same shared animation names; a way to swap it without touching `AnimationPlayer` timings; a hit that can open what a fist cannot | `RayCrowbarFrames.tres` generated (shared names + `crowbar_1`); `Player.Sprite.SpriteFrames` is a plain property (swap at runtime); attack states are scene nodes with `[Export] AnimationName` (new `CrowbarAttack1..n` states are additive scene nodes); `DebrisPile.RequiresKnockdown`/`HeavyHitsToClear` exist | `Weapon` state + pickup `Interactable`, `crowbar_*` animations on the v2 `AnimationPlayer` with their own HitboxOn/Off, a `HitInfo` flag or a `DebrisPile.RequiresWeapon` export |
| **T-V2-03 tripwire** | a beam texture; an alarm target; a jump check | `beam.svg` derivative requested (optional input); `WaveSpawner.StartWave()` is public and the v2 level wires `GuardWave`/`Patrol`; `Player.Height`/`IsAirborne` public (used by `JumpableObstacle.ClearHeight`); `LitZone` pattern for a visible-in-dark `Area2D` | `Tripwire : Area2D` (layer 0, mask 2, `[Signal] Tripped`, `[Export] WaveSpawner? Alarm`, `[Export] float ClearHeight`), one or two placed in the v2 level only |
| **T-V2-04 powerbanks** | a drawn pickup, pickups outside guard drops | `EnergyPickup : Interactable` (+25, `E`) exists; the v2 `Guard.DropScene` points at the shared `EnergyPickup.tscn`; `Guard.Dropped(Node2D)` signal exists | `scenes/v2/props/EnergyPickup.tscn` with a drawn sprite; instances on the conveyor/floor of the v2 level; the v2 Guard's `DropScene` repointed; balance of the count |

None of these require a change to the skeleton's scripts; all are scene additions under `scenes/v2/` plus new
scripts of their own.

---

## Acceptance criteria

Switch & routing
1. Given no `user://settings.cfg`, `GameSettings.GameVersion` reads `V1` (0) after `Load()`; `Save()` then `Load()` after setting `V2` reads `V2`; setting the same value twice emits `GameVersionChanged` once.
2. Given `SettingsMenu.Open()`, `VersionOption.Selected` equals the item whose id is `GameSettings.GameVersion`; selecting the other item sets `GameSettings.GameVersion` and `Close()` persists it; a `GameVersionChanged` from elsewhere re-selects the option without emitting `item_selected`.
3. Given `GameVersion = V2`, the exposition finishing → the tree's current scene is `res://scenes/v2/Main.tscn`, `Main.CurrentLevel` is an instance of `scenes/v2/levels/Level00_Prologue.tscn`, `GameState.CurrentScenePath == "res://scenes/v2/levels/Level00_Prologue.tscn"`. Given `V1` → `res://scenes/Main.tscn` and the v1 path, as before.
4. Given a v2 run, `LevelBase.RestartLevel()` → the current scene path is still `res://scenes/v2/Main.tscn`; the v2 level's `NextLevel` is `Level01_District.tscn` and `GoToLevel` records that path.
5. Given `GameVersion` flipped in the pause menu mid-run, the current level instance is unchanged (no scene change, no reload).

v1 untouched
6. `powershell -File tools/check-v1-untouched.ps1` exits 0 on the branch (every file in contract L equals `main`).
7. v1 `Player.tscn`/`Guard.tscn`/`Companion.tscn` still have `Visual/Rig` with `CharacterRig.cs` and `Visual/Sprite.sprite_frames == null`; `scenes/ui/Exposition.tscn` still has `NextScenePath == res://scenes/Main.tscn`; `MainMenu.tscn` still points at the exposition; all 29 existing smoke tests stay green.

Sprites
8. Each of the four `*Frames.tres` loads; for every animation in `sprite_animations.json` the `SpriteFrames` has it with ≥ 1 frame; every frame is an `AtlasTexture` whose `region` lies inside the sheet texture and equals the JSON bbox × the import scale (±0.5 px); `region.size + margin.size` is the same cell for every frame of a sheet.
9. Given the imported sheets, their texture size is 1360×1600 (`svg/scale=2.0`); given the derivative sections, 2040×1320 (or 2070×1350 for section 1).
10. Given the v2 `Player`, `Visual/Sprite.position.y + cellH·scale/2 == 36 ± 1` (feet at the actor origin); `Rig == null`; `PH_Shadow` hidden.

Actor parity (balance frozen)
11. For each pair (v1, v2) of `Player`, `Guard`, `Companion`: same script resource path; identical `[Export]` values on the root and on every `StateMachine` child (except `Rig`, `Sprite`), identical `Hurtbox`/`Hitbox` shape sizes, positions, layers and masks, identical `CollisionShape2D`; the `AnimationPlayer` has the same animation names (plus `down` on the v2 guard) with the same lengths, and for every method track the same `(time, method)` pairs.
12. Given a v2 `Guard` with `SetDown(true)`, `Visual.rotation == 0` and `AnimationPlayer.current_animation == "down"` (or the assigned animation is `down` after `Stop`); given a v1 `Guard`, `Visual.rotation == π/2` as before. `SetDown(false)` on v2 restores `Sprite.animation == "idle"`, `frame == 0`.
13. Given the v2 `Player` in `TestDamage`-style scripted hits (v1's `combat_dummy.gd` sequence against a v2 `Guard`): the same energy/HP deltas and hit-stop frames as v1 — the boxes and timings are the same objects.

Level parity
14. Given both prologue scenes instantiated, every root `[Export]` (87) compares equal (`NodePath`s as strings, arrays element-wise, `Vector2`s exact); `IntroLines`…`EndLines` and the 30 `Dan*Line` strings are equal.
15. Given both trees walked, skipping `Backgrounds`, `Parallax`, `Backdrop`, `Ground`, `Props`, `Foreground`, `Fx_*`, and every node whose name starts with `PH_` (except `PH_Wall*`, `PH_Decals/*`, `PH_ArenaLamp`, `PH_Landmark_*`, `PH_JamCarts` which are gameplay): the sets of (path, type, global position, `collision_layer`, `collision_mask`, shape size) are equal.
16. Given the v2 level, `Player`, `Dan`, `Patrol/Guard_1..3` and `GuardWave.EnemyScene` are v2 scenes (their `Visual/Sprite.sprite_frames != null`, no `Visual/Rig`); `Camera2D.zoom == (1.5, 1.5)`, `position.y == 450`; `HeldGuards` children are `Sprite2D`s with an `AtlasTexture` inside the guard sheet.
17. Given `v2_level_prologue.gd` (the v1 first-half script re-pointed at `v2/Main.tscn`), it passes: intro, crate, jam, charge, blast, dark, wave of two v2 guards, two pickups, Dan led to the timber — identical assertions.

Backgrounds
18. Given the v2 level, `Backgrounds/Section_Face|Drift|Patrol` have non-null textures from `assets/art/v2/backgrounds/`, `scale ≈ 0.6267`, `position.y == −146`; each mine room's x-range is covered by `Section_*` ∪ `Fill_*` without a gap (union of their world rects ⊇ room rect ∩ y ∈ [300, 600]); every `Fill_*` `region_rect` lies inside its texture; no `PH_Support_*`, `PH_Wall_Face|Drift|Patrol`, `PH_Floor_Face|Drift|Patrol` nodes exist; `Room_Surface` still has `PH_Floor_Surface`.
19. Given the world window at zoom 1.5 (90…810), the drawn floor far edge (world 380) and the floor band 300…600 are inside it, and the far 80 px of the band (300…380) coincide with the wall base — the dark stripe row of guard 2 (y 300…379) lies "against the rib".

Build & runtime
20. `dotnet build` 0 warnings / 0 errors; `godot --headless --path . --import` then `--quit` print no `ERROR:`; `tools/smoke.ps1` all green twice in a row (T-B21 flake rule respected: `PushWarning` steps only in small scripts).

---

## Test strategy

Kind: **new feature** (T-xx) + a **change to existing behaviour** for `Guard.SetDown` and `Exposition`
(characterization first: `enemy_guard.gd` already asserts the v1 knockdown rotation; `ui_exposition.gd`
already asserts the v1 route — both stay green and are extended, so the order "test first" is satisfied by
the existing scripts). No `project.godot` change → no InputMap check needed beyond the existing ones.

Smoke scripts (must unless marked):

| Script | Asserts |
|---|---|
| `core_settings.gd` (extend) | AC 1; `[game] version` key round-trips through the probe path; teardown untouched. |
| `ui_settings_version.gd` (new) | AC 2 on a `SettingsMenu` instance; `VersionOption` exists with ids 0/1; `Select` sync emits nothing. |
| `ui_version_routing.gd` (new) | AC 3, 4, 5: sets V2, instances `Exposition`, `Advance()`s to the end, awaits the deferred change, checks the current scene and `CurrentScenePath`; calls `RestartLevel()` on the v2 level and re-checks; sets V1 and repeats for `Main.tscn`. Restores the real `GameVersion` and `ConfigPath` on teardown. |
| `v2_v1_untouched.gd` (new) | AC 7 structural invariants (runs forever; the git gate is `tools/check-v1-untouched.ps1`, AC 6, run by `/verify` on this branch). Pinning SHA-256 of v1 files in the test was rejected: it would fail on every legitimate v1 change later. |
| `v2_sprites.gd` (new) | AC 8, 9, 10: parses the JSON, rebuilds regions, compares with each `.tres`; checks texture sizes; feet alignment on the three v2 actors. |
| `v2_actors.gd` (new) | AC 11, 12: loads v1 and v2 pairs, compares exports via `get_property_list()` filtered by `PROPERTY_USAGE_SCRIPT_VARIABLE`, shapes, layers, `get_animation_list()`, lengths, method tracks (`track_get_type == TYPE_METHOD`, key times, `method` names); `SetDown` behaviour on both. |
| `v2_level_skeleton.gd` (new) | AC 14, 15, 16. |
| `v2_level_prologue.gd` (new, `extends level_prologue.gd`) | AC 17, 13 (the wave fight on v2 guards). Requires the small refactor of `level_prologue.gd` to overridable path funcs. |
| `v2_backgrounds.gd` (new) | AC 18, 19. |
| N3 `v2_level_prologue_escape.gd`, `v2_level_prologue_patrol.gd` | the other two thirds on v2. |
| `ui_menu.gd`, `ui_exposition.gd` (edit) | pin `GameVersion = 0` after the `ConfigPath` redirect; otherwise unchanged. |

Each script: `extends SceneTree`, checks from the first `_process`, prints `SMOKE <name> PASS|FAIL: …`,
`quit(0|1)`, `MAX_FRAMES` guard, redirects `ConfigPath` before any `Save()` and asserts the real
`user://settings.cfg` timestamp unchanged. Heavy scripts (routing, level) boot the prologue: keep them
under the 60-s runner limit (the v1 halves do).

**Only verifiable by hand (→ Playtest):** whether the stepped walk reads as walking at 220 px/s; whether the
held telegraph frame reads as a threat; feet contact on the drawn floor; the flip of asymmetric poses (lamp
side); the cathedral-vs-drawn proportion; slice seams; the black lip; text sizes at zoom 1.5; the painted
lamp glows after the blast; whether `zoom 2.0` looks closer to the author's mockups.

---

## Playtest (manual QA)

1. Run the project (F5). Main menu → Settings. Expected: a row "Game version" with a dropdown showing `v1`, a note "Applies to New Game". Pick `v2`, Back, Quit. Run again → Settings. Expected: `v2` is still selected (persisted).
2. Settings → `v1`, Back → New Game. Expected: the 2073 exposition, then the prologue exactly as before (orange procedural Ray, Dan the same, procedural rock walls). Esc → Quit to Main Menu.
3. Settings → `v2`, Back → New Game. Expected: the same exposition text, then the mine drawn from the author's section 1 (timber sets, conveyor, red lamps), Ray as the drawn miner with the head lamp, Dan drawn and slimmer, both about 1.5× the old figure on screen. `ENERGY 100` in the HUD.
4. Hold D for two seconds. Expected: Ray steps through step / pass / step / pass at about 7 frames per second; the feet do not visibly skate more than they did on the old figure; the background scrolls; no seam or gap between the drawn section and the filler slices at any point of the room; nothing pops above the ceiling or below the dark bottom lip.
5. Press A. Expected: Ray flips to face left, the head lamp is now on the left side of the head.
6. Walk to the far edge (W until he stops) and press Space. Expected: Ray crouches then rises with the jump pose; at the top of the jump the head is still fully on screen; on landing the standing pose returns.
7. Go through the intro, charge and blast as in v1 (see the T-07s-e playtest, steps 2–3). Expected: identical cutscenes and lines; after the blast the drawn mine goes black and only the head lamp shows it; the painted red lamps read as dead in the dark (if they still glow under the flashlight — note it for the author, Risks 5).
8. Fight the two guards. Expected: press J — wind-up, punch, exit; the hit lands when the drawn fist is out; a third J shows the kick; K holds the wind-up longer and then punches, knocking the guard down; a knocked-down guard shows the lying pose (not a standing figure rotated 90°) and gets up into the standing pose; a guard's attack shows a held shocker telegraph (~0.3 s) then the lunge — if you step back during the held frame, the lunge misses. Hit-stop freezes both poses.
9. Take a hit. Expected: Ray shows the hit pose then the knockback pose with the same white flash as v1; energy drops by 8 as before.
10. Continue to the drift and patrol as in the v1 playtest (steps 6–9). Expected: section 2 (ducts, fan) in the drift, section 3 (the cage) in the patrol room with the drawn cage where the `Hoist` prompt is; the three light pools and the dark stripes are still drawn on the floor; the far dark stripe beside guard 2 sits against the wall base.
11. Cage and capture. Expected: the overseer and two guards behind are drawn guards (standing pose, gun line on the overseer), the `Held` cutscene, black, then the surface — the surface looks exactly as in v1 (grey dawn, lit centre).
12. Let Ray die in the gas (v1 playtest step 7). Expected: respawn at the checkpoint, still in the drawn mine (never back to the procedural one). Die before the first checkpoint (fight with the lamp on and lose) → the level restarts in v2.
13. Esc → Settings → `v1` → Back → Resume. Expected: the drawn mine continues; nothing reloads.
14. Regression: `scenes/levels/TestRoom.tscn` (F6), `TestMine.tscn` (F6), `Level01_District.tscn` (F6) — as before, procedural figures.
15. **Proportions — the coordinator's decision, balance frozen:** the hero is 108 world px at zoom 1.5 (≈15 % of the screen height), the pillars ≈3 heads tall, a power bank ≈⅔ of the hero's width, a door ≈2 heights, the rig's hit/hurt boxes ≈60 % of the drawn body (T-B26); the mine is ≈2.2× larger relative to the people than in the mockups. **Questions for the author:** (a) accept it, or file a task for a v2-only shallower walk band plus a re-authored map? (b) 15 % on-screen hero (zoom 1.5) or 20 % (zoom 2.0 — one number in `scenes/v2/levels/Level00_Prologue.tscn`)? (c) Is the 4-phase walk acceptable, or should two in-betweens per step be drawn? (d) Should the v2 hit/hurt boxes move up to the drawn fist/torso (T-B26)?
16. No dark rectangle behind any figure (Ray, Dan, the wave guards, the patrol); in the capture the three held guards overlap as figures, not as cards. The filler walls between a section and the room edge show a niche under a pillar repeating — the fan and the information board appear once per screen. On the surface: the v1 rock parallax, no strip of mine sky above the wall.

---

## Review focus

`scene/tscn integrity` (fresh uids, repointed `ext_resource`s, 87 exports intact, no dangling `14_rig`),
`asset policy` (nothing under `assets/` but `.import` sidecars; derivatives consumed, not authored),
`hitbox/hurtbox` (byte-equal shapes/timings between v1 and v2 pairs), `null-safety` (`Rig == null` paths,
`GameSettings.Instance` null in tests). Then the rest of the checklist.

---

## Performance & frame budget

- **Per frame:** the v2 actors lose `CharacterRig._Process` (the front-arm rebuild) and 9 polygons each; an
  `AnimatedSprite2D` is one quad. Discrete `AnimationPlayer` tracks cost nothing between keys. No new
  `_Process`/`_PhysicsProcess` code anywhere; no allocations added (`GameVersion` is an enum; the settings
  row builds no strings per frame).
- **Physics:** unchanged (same `Area2D`s, same shapes, same `MoveAndSlide` calls, hitboxes enabled only on
  method-track windows). Depth checks in `_PhysicsProcess` as before.
- **Draw:** backgrounds 3 sections + ≈15 slices = ≈18 `Sprite2D` quads at z −40 (v1 drew hundreds of
  polygons); y-sorted root gains nothing (`Backgrounds` is not y-sorted and sits at z −40).
- **Textures / VRAM:** 3 sheets × 8.7 MB + 3 sections × ≈11 MB ≈ 60 MB, loaded once with the level; the
  crowbar sheet and the original mockups are never referenced at runtime. Import: ThorVG rasterisation of
  35–105 KB SVGs at 2–3× takes ≈1 s each, once.
- **Lights:** unchanged count (≤ 12, `shadow_enabled = false`); zoom makes the flashlight cover more of the
  window (cosmetic, same world size).
- **Zoom:** `Camera2D.zoom` is free; `limit_smoothed`/`position_smoothing` unchanged.

---

## Risks

1. **Region map late or different.** The plan depends on `<sheet>.frames.json`. Mitigation: the generator fails
   loudly on a missing pose; PR-A does not need it; the canonical id table above lets the coder reconcile names.
2. **Derivative sections late / with characters.** PR-C only; the v2 level in PR-A/B ships with the copied v1
   dressing and stays playable.
3. **ThorVG import gaps.** `<pattern>` fills (hatch/dots/grate/stripes) and `clip-path` may render empty or
   black; `width="100%"` + viewBox 690×450 on section 1. Mitigation: the derivative agent replaces patterns with
   flat fills; `v2_sprites.gd` asserts imported sizes; the coder eyeballs the imported textures in the editor
   before wiring.
4. **A persisted `v2` on the dev machine re-routes v1 tests.** `ui_menu.gd`/`ui_exposition.gd` pin V1;
   `ui_version_routing.gd` restores the real value on teardown.
5. **Painted light in the backgrounds.** The mockups bake lamp glows and a red-lit zone; after the blast the
   `CanvasModulate` darkens them, but the flashlight will reveal "glowing" dead lamps. Cosmetic; N5 asks for a
   dark derivative.
6. **Baked shadows.** Every pose carries its own shadow ellipse; it lifts with the body during the 0.3-s jump
   and the `PH_Shadow` polygon must be hidden to avoid a double shadow. Ask the author for shadow-free sheets
   (Design risks 4).
7. **Duplicate uids.** Copied `.tscn`s must get fresh `uid://` values (generate with `ResourceUID.create_id()`
   in a headless one-liner or let the editor re-save); the import would otherwise warn and the wrong scene could
   resolve.
8. **Scene copy drift.** The v2 level is a 2 500-line copy; `v2_level_skeleton.gd` is the guard, and the task
   split keeps PR-A's copy exact so the parity test starts green.
9. **Two clocks by accident.** If anyone calls `Sprite.Play()` (or sets `autoplay`), frames advance twice.
   `v2_actors.gd` asserts `autoplay == ""`; the plan forbids `Play()` on the sprite.
10. **Guard `down` on v1.** The additive branch is gated on `HasAnimation("down")`; `enemy_guard.gd` (v1)
    keeps asserting the rotation.
11. **Runner time.** Booting the v2 prologue loads ≈60 MB of textures; the routing test boots two prologues.
    Keep under 60 s; if not, split like the v1 halves.

---

## Design risks

1. **The art's proportions vs. the frozen metrics (the honest one).** The author drew people at ¼ of the
   frame and a floor 1.2 people deep. v1's band is 300 px = 4 hero heights and every gate, stripe, spawn row and
   route point is authored to it. With balance frozen, the drawn mine must be scaled ≥ 2.2× relative to the
   people (pillars ≈ 3 heads instead of 1.6), whatever zoom or sprite scale is chosen — zoom only changes how big
   everything is on screen (15 % at 1.5, 20 % at 2.0), not the mine-to-people ratio. The skeleton will therefore
   look like "small people in a big mine" compared to the mockups. If the author wants the mockup composition,
   the honest fix is a v2-only shallower band (≈180 px) and a re-authored v2 map — a separate task, not a
   tweak. The alternative (hero 162 world px, zoom 1) gives the same picture with worse-fitting boxes and a
   sluggish-looking walk; rejected.
2. **Stepped walk from 3 keys.** A 4-phase cycle at 0.6 s = 6.7 fps with 33 world px (0.3 body) travelled per
   held frame; the stride implied by the keys (≈0.8 body) is shorter than the 1.2 bodies covered per cycle, so
   the feet will slide ≈35 %. On screen this will read as a classic 16-bit walk — acceptable, but **in motion it
   is a step down from the rig's smooth (if puppet-like) 60-fps limb rotation**. N1 (0.45-s cycle in the v2
   scenes only — cosmetic, not balance) cuts the slide to ≈10 %. Everything else — attacks landing on the frozen
   hit times, the held shocker telegraph, hit/knockback/knockdown poses, a real lying pose instead of a rotated
   figure — will look **better** than the rig. Recommendation: ask the author for **two in-betweens per step
   (6-key cycle)** and a **landing frame**; ship the skeleton with the 3 keys meanwhile.
3. **No variety in the light combo.** `light_1` and `light_2` reuse the same three punch frames; only `light_3`
   (kick) and `heavy` (long wind-up) differ. Ask for a second punch pose (a hook or the other arm).
4. **Baked shadows and labels in the sheets.** Shadows lift with jumps; the row labels are ignored by the
   rasteriser but sit close to the poses — the map must not include them. Ask for shadow-free sheets.
5. **Painted lighting in the backgrounds** (lamp glows, red-lit zone) fights the game's real lighting after the
   blast. Ask for a dark variant, or accept.
6. **Flat backgrounds have no parallax.** v1's three rock layers gave depth; the flat sections will feel like a
   backdrop until layered derivatives exist (T-B27).
7. **What I expect to break first in the build:** feet alignment (a wrong `margin` shows as a hovering or
   sunk figure — caught by AC 10 only for the cell, not per pose; playtest step 4/6 catches the rest), the
   `frame` key applied before the `animation` key on the same time (track order), and the section-1 viewBox
   size (690×450) in slice arithmetic.

---

## Task split (proposal for `docs/TASKS.md` — the author transfers)

Stacked PRs from `task/t-v2-01-prologue-v2-assets`; each has its own `/verify` and review round.

```
### T-V2-01a · Каркас v2 — перемикач версій і маршрутизація · `todo`
- `GameSettings.GameVersion` (enum, `[game] version`, сигнал), рядок «Game version» в `SettingsMenu`, `Exposition.NextScenePathV2`; `scenes/v2/Main.tscn` + `scenes/v2/levels/Level00_Prologue.tscn` як точна копія v1 (свіжий uid); `tools/check-v1-untouched.ps1`.
- Тести: `core_settings.gd` (розширити), `ui_settings_version.gd`, `ui_version_routing.gd`, `v2_level_skeleton.gd`, `v2_v1_untouched.gd`; пін V1 у `ui_menu.gd`/`ui_exposition.gd`.
- Готово, коли: перемикач працює й зберігається; New Game у v2 запускає `v2/Main` з копією прологу; KO-рестарт лишається у v2; v1 побайтово не змінився.

### T-V2-01b · Каркас v2 — пайплайн спрайтів і персонажі v2 · `todo` (stacked на T-V2-01a; потребує `*.frames.json`)
- `.import` аркушів (`svg/scale=2.0`), `tools/build_spriteframes.gd`, `sprite_animations.json`, чотири `*Frames.tres`; `scenes/v2/{player/Player,enemies/Guard,actors/Companion}.tscn` з тими самими скриптами, `AnimationPlayer` з таймінгами v1; `Guard.SetDown` → `down`; у v2-пролозі — актори v2, `Camera2D.zoom 1.5 / y 450`, `HeldGuards` як `Sprite2D`.
- Тести: `v2_sprites.gd`, `v2_actors.gd`, `v2_level_prologue.gd` (extends `level_prologue.gd`).
- Готово, коли: v2-пролог грається зі спрайтами до рівня 1; форми/таймінги/експорти дорівнюють v1 (тест); `enemy_guard.gd` v1 зелений.

### T-V2-01c · Каркас v2 — намальовані фони · `todo` (stacked на T-V2-01a; можна паралельно з 01b; потребує `assets/art/v2/backgrounds/*_clean.svg`)
- `.import` похідних секцій (`svg/scale=3.0`); `Backgrounds` у v2-пролозі: секція на кімнату + слайси, `Room_Surface` — процедурна; прибрати `PH_`-декорації v1, лишити світло/декалі/колізії.
- Тести: `v2_backgrounds.gd`.
- Готово, коли: три кімнати шахти намальовані без швів, поверхня як у v1; `v2_level_skeleton.gd` зелений.
```

If the author prefers one PR, the order inside it is the same (A → B → C) and the `Review findings` journal
below is shared.

---

## Open questions

1. **Scale compromise (Design risks 1):** accept "small people in a big mine" for the skeleton? Default in
   this plan: yes, zoom 1.5, hero 108 world px. The alternative (re-author a v2 band) is a new task.
2. **`zoom` 1.5 or 2.0?** One number; the plan ships 1.5 (slack for the blast shake, smaller labels).
3. **More frames from the author?** Two walk in-betweens per step, a landing frame, a second punch, shadow-free
   sheets, a dark background variant. The skeleton does not wait for them.
4. **Pose ids in `frames.json`:** if the parallel agent's names differ from the canonical table, the coder
   maps them in `sprite_animations.json` — confirm that is acceptable rather than renaming the map.
5. **Walk cycle 0.45 s in v2 (N1):** cosmetic length change in v2 scenes only — allowed under "balance frozen"?
   Default: yes.
6. **Three stacked PRs or one?** Default: three.

---

## Coordinator decisions (2026-09-12)
1. **Scale — as recommended:** hero 108 px in world space, camera zoom 1.5, balance untouched. The
   honest route to the mockup look (a shallower walk band and a re-authored v2 map) is filed as a
   separate task, not smuggled into this one.
2. **Split — three steps, one feature branch, one PR.** The author asked for one feature branch off
   `main`; 01a (switch + v2 scene copies + drift test) lands first, then 01b (sprites + actors) and
   01c (backgrounds) run in parallel worktrees and are merged back. Each step is its own commit.
3. **Asks for the author — carried to the PR, not blocking:** two in-between frames per step
   (a six-key walk cycle), a landing frame, a distinct second light attack, sheets without baked
   shadows, and a dark variant of the backgrounds without painted lamps.
4. **Derived backgrounds already exist** (`assets/art/v2/backgrounds/`, full + back/mid/floor
   layers, characters/cone/beams removed) and the region maps are committed — 01b and 01c do not
   wait for anything. The `<pattern>` fills the plan warns about: check on first import; if ThorVG
   drops them, the cutter agent replaces them with flat fills in the derived copies only.
5. The v2 exposition text is shared with v1 (`Exposition.NextScenePathV2`), as planned.
6. Saved `GameVersion = V2` on a machine must not re-route `ui_menu.gd`/`ui_exposition.gd` —
   pin V1 in those tests, as the plan found.


## Review findings

### Round 1 — Ship: no

Reviewed at `5b794e5` (`task/t-v2-01-prologue-v2-assets`, clean tree), delta `main...HEAD`: 95 files, 11 commits.
Verification run by the reviewer: `dotnet build` 0 warnings / 0 errors; `godot --headless --import`, `--quit` and
`res://scenes/v2/Main.tscn --quit` — no `ERROR:`/`SCRIPT ERROR:`; `tools/smoke.ps1` **38 passed, 0 failed**
(one run, no T-B13/T-B21 flake seen); `tools/check-v1-untouched.ps1` PASS. Screenshots
`scratchpad/v2_prologue_1..4.png` and `backdrops_seam_*.png` inspected.

#### Summary
The branch adds a persisted `GameSettings.GameVersion` switch with a `SettingsMenu` row, routes «New Game» through
`Exposition.NextScenePathV2`, and builds the whole v2 scene set under `scenes/v2/` on the shared scripts: three
actor twins whose `AnimationPlayer`s drive an `AnimatedSprite2D` through discrete `animation`/`frame` tracks,
four generated `SpriteFrames` (`tools/build_spriteframes.gd` from the region maps + `sprite_animations.json`),
a data-driven `SectionBackdrop` (`Back` parallax / `Mid` / `Floor` layers, slice fill, seams on pillars) with three
inherited room scenes, and the v2 prologue with v2 actors, the three backdrops, camera zoom 1.5 and `HeldGuards`
as `Sprite2D`s. Eight `v2_*` smoke tests plus a git gate prove v1 untouched, v1↔v2 parity and the sprite data.

#### Plan conformance
Plan: `docs/plans/t-v2-01-prologue-v2/t-v2-01-prologue-v2-plan.md` (+ `## Coordinator decisions`), design §6a.
TASKS.md: T-V2-01 is `done` with a truthful «Зроблено / Не зроблено» note and the playtest — **but `done` was set
before this review and before a Ship: yes (CLAUDE.md step 4), and the note files the baked-card defect as backlog
T-B30 instead of fixing it in the task** → S1. T-B26..T-B30 landed as `backlog` lines as required.
- Implemented as planned: switch/persistence/signal (contract B), `SettingsMenu` row (A), `Exposition` as the single
  branch point (C), `Guard.SetDown` → `down` gated on `HasAnimation` (D), actor twins E/F/G on the shared scripts
  with the frozen shapes/exports/timings (verified in the `.tscn`s: `HitboxOn/Off` 0.08/0.18, 0.12/0.24, 0.22/0.36,
  guard 0.30/0.40; `animation` track index 0 below `frame` index 1; `autoplay` unset; no `Play()` on the sprite —
  `Player.PlayAnimation` always takes the `AnimationPlayer` branch because every name exists there), v2 level (H)
  with camera 1.5/450, `HeldGuards` `Sprite2D`s on the guard `stance` region (46,66,218,278 = JSON bbox ×2),
  `scenes/v2/Main.tscn` (I), generator (K), git gate (L), `.import` sidecars at 2.0/3.0, no `project.godot`/`.csproj`
  change, commit bodies document the sidecars and the `.claude/settings.json` narrowing.
- Verified v1 byte-identical myself: `git diff --stat main...HEAD` lists **no** file under `scenes/levels/`,
  `scenes/player/`, `scenes/enemies/`, `scenes/actors/`, `scenes/props/`, `scenes/Main.tscn`, `project.godot`,
  `.csproj`; the only script edits are `GameSettings.cs` (additive), `SettingsMenu.cs` (additive), `Exposition.cs`
  (`PickNextScene` falls back to `NextScenePath` when the autoload is missing or `V1`), `Guard.cs` (`SetDown` keeps
  the 90° rotation when no `down` animation exists — `enemy_guard.gd` still asserts it), new `SectionBackdrop.cs`.
- Deviates from plan (accepted, surfaced): v2 actors live in `scenes/v2/actors/` (plan: `player/`, `enemies/`);
  test names differ (`v2_version_switch.gd` replaces `core_settings.gd`-extend + `ui_settings_version.gd` +
  `ui_version_routing.gd`; `v2_spriteframes.gd` replaces `v2_sprites.gd`) — coverage is equivalent or better
  (verified line by line, see Tests); pose ids follow the region map (`attack_windup`, `stance`…) per Open question 4;
  `AtlasTexture.margin` is written as `(left, top, left+right, top+bottom)` — **the plan's formula was wrong**,
  Godot's `margin.size` is the *total* padding (`texture size = region.size + margin.size`), the generator is right
  and additionally re-derives feet line and origin x from the map and fails on a mismatch; backgrounds come as
  `_back/_mid/_floor` layers (plan: one flat section), so N4 parallax is partly in (`Back` at scroll 0.6);
  section 1 viewBox was normalised to 680×440 by the cutter (the plan's 690×450 caveat is moot);
  the surface room lost the v1 `Parallax/PxRock*` layers (removed with the `Parallax` node) and got a flat
  `PH_Sky_Surface` instead — declared in TASKS, see S3.
- Missing / partial: N1 (0.45 s walk) not applied — fine; N2 cone → T-B28; N5 dark variant → not done, declared.
- Accepted limitation (per plan / coordinator §1): hero 108 px on 72-px boxes, mine ≈2.2× larger relative to
  people than the mockups — residual risk: the author's first impression of proportions; the TASKS playtest
  says «Рей ≈108 px» but does not carry the plan's questions (zoom 1.5 vs 2.0, pillars ≈3 heads, boxes at 60 % of
  the body → T-B26) → S6.

#### Code
- [x] **B1. Every v2 sprite carries the sheet's dark canvas and the row separator** — `assets/art/v2/keyframes/*_keyframes.svg:1`
  (`<rect width="680" height="800" fill="#0d1018"/>` + `<rect x="0" y="160" width="680" height="8" fill="#151212"/>` per
  row), consumed by `assets/art/v2/keyframes/*.frames.json` (all 64 pose bboxes end below `floor_rect_y`, so each region
  contains the canvas *and* a strip of the separator), `scenes/v2/actors/*Frames.tres`, and the `HeldGuards` regions in
  `scenes/v2/levels/Level00_Prologue.tscn:942-970` — Blocker
  **Problem:** the region is a bounding box on an opaque sheet, so each `AtlasTexture` is an opaque card; `PH_Shadow`
  is hidden, the baked shadow is inside the card, and the card's bottom edge is the separator's own colour.
  **Why it blocks:** the point of the task is «let the author *see* the generated art in motion». In
  `v2_prologue_1_face_start.png` Ray and Dan stand on dark rectangles; in `v2_prologue_3_patrol.png` the guard is a
  dark card with «HP 30» on it; in `v2_prologue_4_cage_held.png` the three held guards are three overlapping cards.
  That is what the author sees first — it cannot be shown as the v2 line. Filing it as backlog T-B30 while marking
  T-V2-01 `done` inverts the definition of done («New Game у v2 запускає пролог … зі спрайтами»).
  **Solution options:**
  - Option A (correct, already in progress in a parallel worktree): derived sheets without the canvas rect, the four
    separator rects and the `<text>` labels, in a new folder (`assets/art/v2/sprites/`), **same viewBox 680×800 and
    the same pose `translate`s**. Then the region maps stay valid unchanged (bboxes, `origin`, `margin`, `feet_y_per_pose`
    are viewBox coordinates independent of fills); only these pointers move: `sprite_animations.json` `sheet`
    (keep `map` where it is or copy it — the generator reads them independently), the `.import` sidecar for each new
    sheet with `svg/scale=2.0` (otherwise the generator's `s` becomes 1 and `v2_spriteframes.gd` fails on 1360×1600),
    regenerate the four `.tres` (the pinned `1_sheet` ext id and the kept uid make the diff a one-line path change),
    `Level00_Prologue.tscn` ext `14_guardsheet`, and the sheet paths in `v2_spriteframes.gd`. The `.claude/settings.json`
    deny on `assets/art/v2/keyframes/*.svg` and `tools/check-v1-untouched.ps1` (additions under `assets/art/v2/**`
    allowed, modifications flagged) both already permit exactly this. Check afterwards that the cutter did not touch
    any pose geometry: `v2_spriteframes.gd` already re-derives regions from the map, so a moved pose shows as a
    misaligned figure only in playtest — add the alpha probe from Tests §1.
  - Option B (quick, lossy): make the canvas colour transparent at import — not possible for a rasterised SVG
    without editing the file; a chroma-key shader on the sprites would also eat the `#0d1018` tones inside the
    figures. Rejected.
  Also fix the bookkeeping: close T-B30 in this task's fix pass (or reword it as done), and align its text with the
  real path (`assets/art/v2/sprites/`, not `keyframes/*_keyframes_clean.svg` — the latter is denied by
  `.claude/settings.json` `Edit(assets/art/v2/keyframes/*.svg)`).
  **Closed** by `1922499` (merge `c9b5741`, worktree `wt/v2-cards`): Option A — `assets/art/v2/sprites/*_keyframes.svg`
  derived by `tools/derive_sprite_sheets.py` (pose group only, same viewBox and translates), `.import` at 2.0,
  `sprite_animations.json` `sheet` → `sprites/`, the four `.tres` regenerated (one path line each), `HeldGuards`
  ext `14_guardsheet` → `sprites/`; `v2_spriteframes.gd` asserts the sheets come from `sprites/` and the four corner
  texels of every region are transparent (falsified against `keyframes/`: 268 findings). Verified in the fix pass:
  `v2_spriteframes.gd` PASS, `GUARD_SHEET` in `v2_prologue_integration.gd` → `sprites/`, plus the HeldGuards corner
  probe added there. T-B30 reworded and closed as done by the same merge.

- [x] **S1. T-V2-01 marked `done` before review and Ship** — `docs/TASKS.md` (T-V2-01 status line) — Should-fix
  **Problem / why it matters:** CLAUDE.md step 4: `done` only after a green post-fix `/verify` and Ship: yes. The
  status also carries the B1 defect into the «done» state.
  **Fix:** `in_progress` until the fix pass lands; then `done` with the note updated (B1 fixed, T-B30 closed).
  **Closed:** status set to `in_progress` for the fix pass and to `done` only after the post-fix verification; a
  «Рев'ю» line names Round 1, B1 and S1–S7; the Зроблено/Не зроблено note no longer files B1 as backlog.

- [x] **S2. Fill slices repeat unique props — the drift and patrol walls read as wallpaper** —
  `scenes/v2/levels/Backdrop_Drift.tscn:15` (`LeftFillTexture = level0_section3_exit_mid.svg` with the default
  `LeftFillSlice (72, 322)`), `scenes/v2/levels/Backdrop_Patrol.tscn` (same default for its left fill),
  `scripts/levels/SectionBackdrop.cs:54` — Should-fix
  **Problem / why it matters:** mockup columns 72…322 of section 3 contain the red-headed information board
  (100…250), the control box on the column (258…286) and a tripwire post — distinctive one-off props. In
  `v2_prologue_3_patrol.png` the same board appears twice on one screen; in `backdrops_seam_face_drift.png` the
  drift's left third is the exit section's board + box repeated. The face room's right fill (section 1, 228…418)
  repeats the ventilation fan on the beam. It is the second thing the author will notice after B1.
  **Fix:** per-room slice columns with plain wall between pillars (the exports exist for exactly this): e.g. a
  section-3 column without the board/box, a section-1 column without the fan; keep the pillar-edge rule so
  `v2_backdrops.gd:200-209` (seams on pillars) stays meaningful. Data change in the two room scenes only.
  **Closed:** probed the three mid layers (row 100 pillar runs 55–73, 227–245, 417–435, 597–615; wall-band colour
  signatures per column): **no pillar-to-pillar bay is prop-free** in any mockup (section 1: board / doors+fan /
  door+pipe+panel; section 2: arch+panel / fan housing / housing+panel; section 3: board+box / cage). The honest
  filler is section 1 columns **370…470** — plain black wall at both cuts (363–380 and 447–479 are one colour down
  the band), one pillar (417–435) and the third door niche under it, no fan (ends 365), no board, no panel. All four
  fills (`Backdrop_Face` right, `Backdrop_Drift` left+right, `Backdrop_Patrol` left) use that column of
  `level0_section1_mineface_mid.svg`, so a room seam is the same texture cut at the same x (the pillar's right edge
  435): Face `FillTo` 2716.6, Drift `SectionX` 842.4 / `FillFrom` −163.4 / `FillTo` 2807, Patrol `SectionX` 1684.8 /
  `FillFrom` −73 (the drawn cage 2403…2817 still covers the Hoist at 2740, and is no longer cut by the room end).
  Script defaults and docs follow the convention. `v2_backdrops.gd`: seam = texture continuity + pillar right edge
  at row 100; every filler column must be plain wall at both cuts and hold exactly one pillar-sized run on rows
  100/130/150 (falsified with the old (228, 418): fan run on rows 130/150). Renders `scratchpad/v2_fixpass_*.png`.
  Remaining: a niche repeats every 188 px (architecture, not a one-off prop) — a prop-free derivative is T-B32.

- [x] **S3. `PH_Sky_Surface` is a patch over a far-layer leak, not a sky** — `scripts/levels/SectionBackdrop.cs:150-175`
  (`BuildBack`: `spanTo = s·roomRight + (1−s)·ViewWidth + BackMargin` in base space, never clipped to the room),
  `scenes/v2/levels/Level00_Prologue.tscn:313-318` (`PH_Sky_Surface`, z −60, x 8640…10560, y 0…300) — Should-fix
  **Problem / why it matters:** with scroll 0.6 the Patrol room's back tiles (base x ≤ ≈6016) display at
  `b + 0.4·cameraLeft`, i.e. up to world ≈9470 while the camera is in the Surface room, so the mine sky/hills would
  show behind the surface. The opaque rect hides it for y 0…300 (the rest is covered by `PH_Floor_Surface` z −20 and
  `Ground/PH_NearBand` z 4 by luck of the layer stack). `v2_prologue_integration.gd:202-207` then pins the patch
  as if it were design. It is declared in TASKS, so honest — but the mechanism is wrong and every future room added
  after a backdrop room needs the same patch.
  **Fix:** clip the far layer at the room edge when the room has no right neighbour: an `[Export] float BackClipTo`
  (default `+inf`, set on `Backdrop_Patrol` to `RoomWidth`) passed as `clipTo` to `AddSlice`, or `Parallax2D.limit_end`.
  Keep `PH_Sky_Surface` only if the surface is meant to have a flat sky (then say so in its name/TASKS); the plan's
  «surface as in v1» is otherwise no longer true because the v1 `Parallax/PxRock*` layers went with the `Parallax` node.
  **Closed — with a different mechanism, because the suggested one cannot work:** measured headless, `Parallax2D`
  places a tile at `b + (centre − w/2)·(1 − s)` (w = viewport *pixel* width, zoom ignored), so the leak depends on
  the camera, not on the base span — a base-space `clipTo` at `RoomWidth` is a no-op (the span ends at ≈6016
  anyway), and `limit_end` glues the layer to the screen beyond the limit (`pos = o − s·L`) instead of clipping.
  Fix: `SectionBackdrop._Process` shows `Back` only while the current camera's `LimitLeft/LimitRight` overlap the
  room — `LevelBase.ApplyRoomBounds` sets them the moment the hero arrives, so the mine's sky is off on the surface
  before the black beat fades (no pop; window-overlap would have leaked for as long as the smoothing converges).
  `BuildBack` now covers the window for every camera centre from half a window left of the room to half a window
  right of it (the slide-in after a limit switch) with the real Parallax2D formula; `BackMargin` stays 320 for
  shake. `PH_Sky_Surface` deleted; the v1 `Parallax` node (PxRockFar/PxRockMid/PxStruct, verbatim) is back with
  the container at z −80 so its layers (−180/−160/−140) sit strictly under the painted `Back` (−120): hidden in the
  mine by the opaque painted sky, seen on the surface as in v1. Skeleton test untouched by it (`Parallax` is
  dressing). Tests: `v2_backdrops.gd` drives the TestBackdrops camera limits (whole mine / patrol / surface / face)
  and checks each `Back.visible`; `v2_prologue_integration.gd` calls `ApplyRoomBounds(Room_Surface|Room_Patrol)`
  and checks the same on the level, plus rock layers below the painted z. Note: the old coverage formula in the
  test (`o·(1 − s)`) was off by 128 px and passed only thanks to the margin — replaced.

- [x] **S4. Hidden `PH_Wall_Face|Drift|Patrol` kept only to satisfy a test rule** —
  `scenes/v2/levels/Level00_Prologue.tscn:282-305` (`visible = false` `ColorRect`s), `tests/smoke/v2_level_skeleton.gd:30`
  (`PHYSICAL_PH_PREFIXES = ["PH_Wall", "PH_Landmark_"]`) — Should-fix
  **Problem / why it matters:** the prefix rule was written in this task and treats a `ColorRect` as physical; the
  physical walls are `PH_WallLeft/Right/Shaft` (`StaticBody2D`). Three dead nodes in the scene, and the skeleton diff
  cannot tell «hidden» from «shown» (`_record` compares no `visible`/`z_index`), so it proves less than it looks.
  T-B29 defers this, but it is a three-line test change plus deleting three nodes — do it here.
  **Fix:** in `_is_dressing`, treat a `PH_*` node as physical iff it is/has a `CollisionObject2D` or `Light2D`
  descendant (or list `PH_WallLeft/Right/Shaft`), delete the three `ColorRect`s; add `visible` to `_record` for
  gameplay nodes.
  **Closed:** the three `ColorRect`s deleted from `scenes/v2/levels/Level00_Prologue.tscn`; `v2_level_skeleton.gd`
  lists `PH_WallLeft/Right/Shaft` in `PHYSICAL_PH` (prefix rule now only `PH_Landmark_`) and records `visible` for
  every gameplay `CanvasItem` (falsified: `PH_WallLeft.visible = false` in v2 → «visible true / visible false»).
  `v2_prologue_integration.gd` asserts the three walls are gone (not merely hidden). T-B29 reworded.

- [x] **S5. `Flashlight` compared «by class only» also drops its balance exports** — `tests/smoke/v2_level_skeleton.gd:115-117`,
  `tests/smoke/v2_actors.gd:39-43` (`SHAPE_NODES` has no `Flashlight`) — Should-fix
  **Problem / why it matters:** I checked the claim behind the relaxation: `HeadOffset` is cosmetic —
  `Flashlight.ApplyTransform` only positions the `PointLight2D`; gameplay reads `Flashlight.IsOn`
  (`Player.IsLit` `scripts/player/Player.cs:146`, `GasZone.cs:204-207`, `WatchZone.cs:147`, `Guard.cs:224`) and the
  lit-zone sensor is the separate `LightSensor` `Area2D` on the actor root, which *is* compared. So 92 vs 60 is not a
  balance change. But the class-only compare also skips `DrainPerSecond`, `EnabledAtStart`, `BeamAngleDeg` — the
  energy drain *is* balance and nothing else asserts it equal (today both scenes use the defaults, so no drift yet).
  **Fix:** compare the `Flashlight` on everything except `position`/`HeadOffset` (skeleton), or add `Flashlight` to
  `v2_actors` export comparison with `HeadOffset` excluded.
  **Closed:** `v2_level_skeleton.gd` records the actor `Flashlight` as class + `DrainPerSecond` + `EnabledAtStart`
  (`LAMP_BALANCE`), skipping only `HeadOffset`/`BeamAngleDeg`/position (falsified: `DrainPerSecond = 2` on the v2
  Player's lamp → «DrainPerSecond 1.0 / 2.0»).

- [x] **S6. Proportions decision not carried to the author** — `docs/TASKS.md` T-V2-01 «Плейтест» — Should-fix
  **Problem / why it matters:** the coordinator froze balance and accepted «small people in a big mine»; the playtest
  note says only «Рей ≈108 px». The author will see pillars ≈3 heads tall, the powerbank ⅔ of Ray's width and a door
  nearly two Rays tall without being told it is a known compromise or what the alternatives are.
  **Fix:** add the plan's Playtest §15 questions (a) zoom 1.5 vs 2.0 — one number in `Level00_Prologue.tscn`;
  (b) mine-to-people ratio ≈2.2× the mockups, honest fix = a v2-only shallower band + re-authored map (separate task);
  (d) boxes at 60 % of the body → T-B26. Two lines.
  **Closed:** TASKS.md playtest step (4) and `## Playtest` §15 below now state the numbers (hero 108 px at zoom 1.5,
  pillars ≈3 heads, power bank ≈⅔ of the hero's width, door ≈2 heights, boxes ≈60 % of the body) and the questions
  (accept, or a shallower-band + re-authored-map task; zoom 1.5 vs 2.0; T-B26).

- [x] **S7. `tools/check-v1-untouched.ps1` guards fewer files than the plan's «untouched» list** —
  `tools/check-v1-untouched.ps1:27-42` — Should-fix (low)
  **Problem / why it matters:** the gate lists the v1 scenes and `Level00_Prologue.cs` only; the plan's script list
  (`Player.cs`, `Companion*.cs`, `Guard*State.cs`, `LevelBase.cs`, `Main.cs`, `MainMenu.cs`, `CharacterRig.cs`,
  `GameState.cs`) and the v1 tests (`enemy_guard.gd`, `combat_dummy.gd`, …) are not in it, so a future v2 change that
  edits one of them passes the gate. Dirty-tree detection is correct (`git diff` against the working tree + the
  `status --porcelain` pass); the art rule correctly allows additions and flags M/D/R under `assets/art/v2/**/*.svg`.
  **Fix:** extend `$v1Files` with the plan's list; optionally `assets/art/v2/**/*.json` under the same M/D/R rule.
  **Closed:** the checker adds every `scripts/**` file that exists on the base ref (`git ls-tree`) to the frozen
  list except the five the plan allows (`GameSettings.cs`, `SettingsMenu.cs`, `Exposition.cs`, `Guard.cs`,
  `SectionBackdrop.cs`); new scripts stay allowed (falsified: an uncommitted line in `scripts/player/Player.cs` →
  FAIL «scripts/player/Player.cs (uncommitted change)»). v1 tests and the `.json` maps are not added (the v1 test
  bases gained overridable hooks in this task by design).

#### Tests
- [x] **Alpha probe on the generated frames** — the test that would have caught B1 and guards the clean sheets: for
  every `AtlasTexture` in each `*Frames.tres`, read the sheet `Image` and assert the region's four corner pixels have
  alpha 0 (and, stronger, that the row of pixels at the cell's feet line outside the body bbox is transparent) —
  `tests/smoke/v2_spriteframes.gd`. Also assert the `HeldGuards` regions the same way in `v2_prologue_integration.gd`.
  **Closed:** corners in `v2_spriteframes.gd` (B1 merge) and for the three `HeldGuards` regions in
  `v2_prologue_integration.gd` (falsified: `14_guardsheet` → `keyframes/` → «corner texel … opaque (alpha 1.00)»).
- [x] **Room x literals** — `v2_backdrops.gd:34-36` and `v2_prologue_integration.gd:40-42` duplicate 0/2880/5760/8640
  from the level's `Rooms/Room_*`; read them from the level in the integration test so a moved room fails the coverage
  check — `tests/smoke/v2_prologue_integration.gd`.
  **Closed:** `BACKDROPS` names the level room; position and `RoomWidth` are compared to `Rooms/Room_*.Rect`
  (falsified: `Backdrop_Drift` moved to 2900 → «expected the level's Room_Drift rect»). `v2_backdrops.gd` keeps its
  own room table (it has no level).
- [x] **Playtest checklist** — add the S6 questions and «no dark rectangle behind any figure; the held guards overlap
  as figures, not as cards» to the TASKS playtest after B1.
  **Closed:** both in TASKS.md playtest (2) and (4).
- Verified by reading (subagent audit + own checks): every `v2_*` script quits 1 only through `_finish()`/watchdog, no
  `push_warning`-only failure paths; checks run from `_process` (autoloads present); `v2_actors.gd:379-386` pins the
  exact hit windows; `:398` asserts the `animation` track index below the `frame` track; `:466-478` exercises
  `SetDown` on both versions; `v2_spriteframes.gd:175` asserts `autoplay == ""`, `:181-182` the feet line at the actor
  origin; `v2_version_switch.gd:138-140,279-282` restores the real `GameVersion`/`ConfigPath` and asserts the real
  `settings.cfg` mtime unchanged; `v2_level_prologue*.gd` override only `_name/_main_path/_prologue_path` and the base
  scripts use those everywhere (no leftover const use); the escape run correctly exits into the shared
  `Level01_District`. Commit «falsified» claims match the assertions they name.

#### Nits
- `ui_exposition.gd:110` sets the real autoload's `GameVersion = 0` without redirecting `ConfigPath` and never restores
  it; harmless today (nothing saves in that script), but a later `Save()` in the same process would overwrite a
  machine's «v2». Redirect + restore like `ui_menu.gd`.
- `v2_version_switch.gd:217-218` — the `expo_scene == null` early exit leaves `ConfigPath = PROBE_PATH` (failing run
  only).
- `.claude/settings.json` — the narrowing is as intended (originals `keyframes/*.svg`, `level0/**`, legacy folders,
  audio stay denied; `Bash rm/mv *assets/*` unchanged); pre-existing gap: only `Edit(...)` is denied, `Write(...)` never
  was — consider mirroring the deny list for `Write`.
- `v2_v1_untouched.gd` has no `MAX_FRAMES` (synchronous, relies on the runner's 60 s) — fine, but every other script
  has one.
- `scripts/levels/SectionBackdrop.cs:184` `sectionWidth = section.GetWidth() / ImportScale` — correct, but the
  `_back` viewBox height (440) and `DrawnFloorTop` (280) are only right for these three files; a comment naming the
  assumption would help the next cutter.
- `HeldGuards/Overseer` offset (−31, −121) puts the pose origin x ≈ 23 tex px left of the node (feet are on the
  origin vertically) — cosmetic, visible only against the drawn cage.

#### What's done well
- **One clock.** The v2 `AnimationPlayer`s carry v1's names, lengths and method tracks verbatim; the sprite is a frame
  holder (`autoplay` unset, never `Play()`ed); hit-stop, `ResetPose`, `IsAnimationPlaying`, `AnimationTime` and the
  combo window are literally the same code paths. `Guard.SetDown`'s `down` branch composes correctly with
  `GuardDown.Enter` (`ResetPose` → `SetDown(true)` plays `down`) and `Exit` (`ResetPose` before Approach's `walk`).
- **The generator is honest and stable:** it re-derives feet line and origin x from the map and fails the build on a
  mismatch instead of producing a hovering figure; deterministic sub-resource ids, pinned `1_sheet` ext id and a kept
  uid make regeneration diff-free; the margin semantics are right (the plan was wrong).
- **`SectionBackdrop`** is all exports, no magic numbers; seams meet on pillar edges (`FillTo == next.FillFrom`
  asserted to 0.05 px); the three `_back` layers are byte-identical, so overlapping parallax copies coincide.
- **v1 is byte-identical** (checked by diff, not by the checker's word), and the three shared-script edits are
  provably neutral for v1 (`HasAnimation("down")` gate, `NextScenePathV2` default path, `_name()` defaults).
- The backgrounds README states the `<pattern>` → flat-fill replacement, what was cut and what was kept, with
  coordinates — exactly the honesty the asset policy needs.

#### Verdict
Ship: no — B1 is the whole point of the task: as it stands, the author's first look at v2 is figures on dark cards.
Everything underneath (switch, parity, pipeline, backdrops) is sound and well tested; the fix is a re-point, not a
redesign. First: (1) B1 — clean sheets in `assets/art/v2/sprites/` + re-point `.import`/table/`.tres`/level, add the
alpha probe; (2) S1 + S4 — status back to `in_progress`, fix the `PH_Wall` test rule and delete the hidden walls;
(3) S2 — plain-wall fill slices, then S6/S3.
