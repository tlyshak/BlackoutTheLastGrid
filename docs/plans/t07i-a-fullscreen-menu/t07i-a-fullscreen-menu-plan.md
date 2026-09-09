# Plan — t07i-a-fullscreen-menu (T-07i-a · Імпрувмент прологу №1: повний екран, головне меню, пауза)

Task: [`../../TASKS.md` → T-07i-a](../../TASKS.md) · Design doc: [`../../GAME_DESIGN.md`](../../GAME_DESIGN.md)
(§8 Назва — логотип, §6 Арт-напрям — палітра, §7 Технічний план — збереження) ·
Shared brief: [`../t07i-visual-kit/visual-brief.md`](../t07i-visual-kit/visual-brief.md) ·
Previous session: [`../../sessions/2026-09-09-session-01.md`](../../sessions/2026-09-09-session-01.md)

## Goal
Give the game a shell. Today `run/main_scene` is `Main.tscn`, so launching the project drops the
player straight into the prologue in a 1920×1080 window with no way to pause, no way to quit
except Alt+F4, and no way to change anything. T-07i-a wraps the existing vertical slice in the
three screens every build needs before the author can hand it to anyone: a **main menu**
(`scenes/ui/MainMenu.tscn`, the new `run/main_scene`) with the §8 logo — the word BLACKOUT with
one glowing letter, built procedurally — and «Нова гра» / «Налаштування» / «Вихід»; a **settings
screen** (fullscreen checkbox, master volume, «Назад») persisted to `user://settings.cfg`; and a
**pause menu** on a new `pause` action (Продовжити / Налаштування / Вихід у головне меню). The
game starts **fullscreen** and toggles window/fullscreen on a new `toggle_fullscreen` action
everywhere, menu or level. The hard constraint: none of this may break the KO restart, which is
`SceneTree.ReloadCurrentScene()` on `Main` — so «Нова гра» must make `Main.tscn` the current
scene, not load it as a child of the menu.

## Scope

### In
- `project.godot`: `display/window/size/mode=3` (fullscreen at start), new InputMap actions
  `pause` and `toggle_fullscreen`, new autoload `GameSettings`, `run/main_scene` →
  `res://scenes/ui/MainMenu.tscn`.
- New autoload `scripts/core/GameSettings.cs` — user preferences (fullscreen, master volume),
  `user://settings.cfg` via `ConfigFile`, the global `toggle_fullscreen` handler.
- New scenes/scripts: `scenes/ui/MainMenu.tscn` + `scripts/ui/MainMenu.cs`,
  `scenes/ui/SettingsMenu.tscn` + `scripts/ui/SettingsMenu.cs`,
  `scenes/ui/PauseMenu.tscn` + `scripts/ui/PauseMenu.cs`.
- `scenes/ui/HudTheme.tres`: **additive** `Button` / `CheckBox` / `HSlider` / `PanelContainer`
  entries so the menus share the HUD's look. No existing entry is touched.
- `scripts/levels/LevelBase.cs`: optional `PauseMenu` reference, `GoToMainMenu()`, the
  "every transition unpauses" invariant, KO restart timer no longer runs while paused.
- `scripts/ui/Cutscene.cs`: one guard so a paused tree cannot advance a cutscene line.
- `scripts/levels/Level00_Prologue.cs`: the Dan-cutscene delay timer no longer runs while paused.
- `PauseMenu` instances added to `Level00_Prologue.tscn`, `Level01_District.tscn`, `TestRoom.tscn`.
- Smoke: `tests/smoke/ui_menu.gd`, `tests/smoke/ui_pause.gd`, `tests/smoke/core_settings.gd`,
  plus new assertions in `tests/smoke/core_gamestate.gd`.
- `docs/TASKS.md`: T-07i-a status/done-note, three new `backlog` entries (below).

### Out (→ `docs/TASKS.md` backlog)
Resolution / window-size selector and key rebinding; separate Music/SFX buses with their own
sliders; a «Продовжити» (resume saved run) button — that needs T-09; localization switch; credits
screen; menu music and UI sounds (no audio in the project at all yet); animated scene behind the
main menu (that is T-07i-c territory); replacing the `[Export]` menu colours with
`scripts/art/Palette.cs` (T-07i-b creates it).

Exact lines to add to `docs/TASKS.md` (next to `T-B02`, before `## Backlog`):

```
### T-B03 · Налаштування: роздільна здатність і рібіндінг клавіш · `backlog`
- Вибір роздільної здатності/режиму вікна списком і перепризначення дій InputMap у `SettingsMenu`,
  з персистенцією в `user://settings.cfg`. Зараз у налаштуваннях лише чекбокс повного екрана.

### T-B04 · Аудіо-шини Music/SFX і окремі повзунки гучності · `backlog`
- Додати шини `Music` і `SFX` під `Master`, три повзунки в налаштуваннях, персистенція.
  Зараз є лише `Master`, і в грі ще немає жодного звуку.

### T-B05 · Кнопка «Продовжити» в головному меню · `backlog`
- Після T-09: якщо є збереження — «Продовжити» відновлює забіг із `GameState.CurrentScenePath`.
  Зараз меню має лише «Нова гра».
```

## Design-doc conformance
- **§8 Назва** — "Для іконки/логотипу: слово BLACKOUT, у якому одна літера світиться (як єдине
  вікно в темній панельці)." The task text and the design doc **agree**; the plan implements the
  logo procedurally (Labels + an additive radial `GradientTexture2D` glow behind one letter,
  pulsing on a `Tween`), which is what the visual brief demands (no image files).
  Subtitle: §8 gives the Ukrainian localization «Відключення: Остання мережа», so the subtitle
  under the logo is **«ОСТАННЯ МЕРЕЖА»** (the brand word itself stays Latin). `[Export]`-driven,
  so the author can change it without a code edit.
- **§6 Арт-напрям / visual brief palette** — the menus use the brief's colours only
  (`RockDeep #12161d` ground, `OutlineDark #0a0d14` dim, `EnergyAmber #f0a326` accent,
  `EnergyPale #ffd98a` glow core, `SteelCold #4d5866` secondary text). The brief says T-07i-a
  "використовує палітру і той самий шрифт/тему, що HUD (`scenes/ui/HudTheme.tres`)" — hence the
  additive theme entries rather than a second theme resource (Godot 4 `Theme` has no inheritance).
- **§7 Технічний план** — "збереження → JSON через `FileAccess`" describes the **run save**
  (T-09). This task's `user://settings.cfg` is a `ConfigFile` of machine preferences and is a
  different file with a different lifetime; see *GameState & save impact*. No conflict.
- The design doc is **silent** on menus, pause and window mode. That is not an ambiguity to
  resolve: the TASKS.md T-07i-a block names all four features explicitly ("Гра стартує у
  повноекранному режимі", "`scenes/ui/MainMenu.tscn` … стає `run/main_scene`", "Екран
  налаштувань … і меню паузи … на дію `pause`", "Зміни `project.godot` (display, InputMap) — за
  скілом `/project-settings`"). Nothing here is invented.

## Options considered

### A. Where the `toggle_fullscreen` handler lives
1. **New `GameSettings` autoload with `_UnhandledInput` (recommended).** Works identically in the
   main menu, in a level, while paused (`ProcessMode = Always`), and in `TestRoom` opened with F6.
   One owner for "read the setting → apply it → persist it", which the settings screen and the
   hotkey both go through, so the checkbox can never disagree with the window. Cost: a third
   autoload (see *GameState & save impact* for why CLAUDE.md's "global state only in `GameState`"
   is not violated).
2. A node inside each menu/level scene. No new autoload, but the handler is duplicated in four
   scenes and is dead in any scene that forgets it; a level would have to reach the menu's
   settings object to keep the checkbox in sync — the kind of cross-scene lookup CLAUDE.md bans.
   Rejected.
3. Handle it in `MainMenu` only. Then F11 does nothing during play, which the task explicitly
   forbids ("працює і в меню, і в грі"). Rejected.

### B. Where the pause menu lives
1. **An instance of `PauseMenu.tscn` in each level scene, referenced by an `[Export]` on
   `LevelBase` (recommended).** Exactly the pattern `HUD.tscn` already uses in all three level
   scenes. Pause exists wherever a level exists and nowhere else — Esc in the main menu correctly
   does nothing. `LevelBase` already owns scene transitions (`RestartLevel`, `GoToLevel`), so
   "Вихід у головне меню" is one more transition method next to them, reached by a signal from
   the menu; the menu itself knows nothing about levels. Cost: three `.tscn` edits.
2. Put it in `Main.tscn`. Looks cheaper, but `LevelBase.GoToLevel` calls
   `ChangeSceneToPacked`, which **replaces `Main`** — the moment the prologue hands over to
   `Level01_District`, the pause menu is gone. Rejected.
3. Make `PauseMenu.tscn` an autoload scene. Always available, but then it is also alive over the
   main menu and needs an "am I allowed to pause here?" flag that some other scene has to set —
   coupling with no owner. Rejected.
4. Refactor `Main` into a persistent shell that swaps levels as children. Cleanest long-term, but
   it changes the KO restart contract the task explicitly asks to preserve
   (`ReloadCurrentScene` on `Main`) and is a T-08/T-09-sized refactor. Rejected for this task.

### C. Sharing the settings screen between the main menu and pause
1. **One `SettingsMenu.tscn`, instanced twice (recommended)** — once under `MainMenu`, once under
   `PauseMenu`. One scene, one script, one contract; each host owns its own instance and its
   visibility, no global lookup, no scene-change flicker between menus.
2. One global instance owned by `GameSettings`. Needs the autoload to own UI and both hosts to
   reach into it — inverted dependency. Rejected.
3. `SettingsMenu` as a separate `run`-level scene the menus change to. Loses the level behind the
   pause screen, and returning from settings during play would mean reloading the level. Rejected.

### D. How «Нова гра» starts the run
1. **`GetTree().ChangeSceneToFile("res://scenes/Main.tscn")`, path in an
   `[Export(PropertyHint.File, "*.tscn")] string` (recommended).** `Main` becomes the tree's
   current scene, so `LevelBase.RestartLevel()`'s `ReloadCurrentScene()` keeps reloading `Main`,
   which rebuilds the prologue — the mechanism from T-07 is untouched. Using a **path**, not an
   `[Export] PackedScene`, keeps `Main.tscn` → `Level00_Prologue.tscn` (and its whole prop graph)
   out of `MainMenu.tscn`'s `ext_resource` list, so the menu appears instantly instead of loading
   the level first.
2. `[Export] PackedScene` + `ChangeSceneToPacked` (the `GoToLevel` style). Same runtime result,
   but the prologue is loaded as a dependency of the menu at boot. Rejected on load time; noted
   as the fallback if the author prefers the `PackedScene` convention.
3. `AddChild(Main.Instantiate())` under the menu. **Breaks the task's hard constraint**:
   `CurrentScene` would still be `MainMenu`, so a KO would reload the *menu* instead of the level.
   Explicitly rejected — this is the failure mode the task warns about.

## Recommended approach
A1 + B1 + C1 + D1. Concretely:

- `GameSettings` autoload owns preferences and the hotkey; it is the only thing that calls
  `DisplayServer.WindowSetMode` and `AudioServer.SetBusVolumeDb`, and the only thing that reads or
  writes `user://settings.cfg`.
- `MainMenu.tscn` is the new `run/main_scene`: procedural logo, subtitle, three buttons, plus its
  own hidden `SettingsMenu` instance. «Нова гра» → `ResetRun()` + `ChangeSceneToFile(Main.tscn)`.
- `PauseMenu.tscn` is instanced in every `LevelBase` scene and wired through one `[Export]`.
  It owns `GetTree().Paused`, cancels any hit-stop when it opens, and emits
  `QuitToMenuRequested` for `LevelBase` to act on.
- Pause safety is enforced as **one invariant**: *any* scene transition
  (`RestartLevel`, `GoToLevel`, `GoToMainMenu`) sets `GetTree().Paused = false` and calls
  `HitStop.Cancel()` first, so the game can never come up frozen or time-scaled to 0.

## GameState & save impact
- **No `GameState` field or signal is added or changed.** `Energy`, `Route`, `JournalsFound`,
  `DistrictReputation`, `CurrentScenePath`, `EnergyChanged(float)` all keep their current shape.
- `GameState.ResetRun()` is **called** in two new places, both of which start a fresh run:
  `MainMenu` before changing to `Main.tscn` («Нова гра» must not inherit the energy left over from
  an abandoned run — today energy is only reset in `GameState._Ready`, i.e. once per process), and
  `LevelBase.GoToMainMenu()` when the player quits a run from the pause menu.
- **Why a second (third) autoload is not a `GameState` violation.** CLAUDE.md's rule is about
  *run state* — "енергія, маршрут рівня 2, зібрані щоденники, репутація". `GameSettings` holds
  **machine preferences** that are identical across runs, survive «Нова гра», and must never be
  written into a save slot. It is a service autoload of the same kind as `HitStop`, which is
  already registered and accepted. If the author prefers two autoloads over three, the fallback is
  to fold the two properties into `GameState` — listed in *Open questions*.
- **T-09 hand-off.** Two files, two lifetimes, no overlap:

  | | `user://settings.cfg` (this task) | run save (T-09) |
  |---|---|---|
  | Format | `ConfigFile` (ini) | JSON via `FileAccess` (§7) |
  | Content | `fullscreen`, `master_volume` | `Energy`, `Route`, `JournalsFound`, `DistrictReputation`, `CurrentScenePath`, level progress |
  | Written by | `GameSettings.Save()` | T-09 save system |
  | «Нова гра» | untouched | new/overwritten |
  | Scope | per machine, per user | per run |

  T-09 must **not** persist anything introduced here, and must not read `settings.cfg`.
  T-09 will add a «Продовжити» button to `MainMenu` (backlog T-B05) — the button row is built in
  the scene, so adding a fourth button is a scene edit plus one handler.

## Scene & signal contract

### `scripts/core/GameSettings.cs` — autoload, no scene
`partial class GameSettings : Node`, namespace `BlackoutLastGrid.Core`.
Registered as `GameSettings="*res://scripts/core/GameSettings.cs"`.

| Member | Type / default | Unit / notes |
|---|---|---|
| `Instance` | `static GameSettings` | assigned in `_EnterTree`, cleared in `_ExitTree` (the `GameState` pattern) |
| `[Export] ConfigPath` | `string = "user://settings.cfg"` | settable at runtime so smoke tests use a throwaway file |
| `[Export] DefaultFullscreen` | `bool = true` | used when the file is missing |
| `[Export] DefaultMasterVolume` | `float = 0.8` | linear 0…1 |
| `[Export] MuteThreshold` | `float = 0.001` | linear; at or below → bus muted instead of −∞ dB |
| `Fullscreen` | `bool` property | setter always applies to `DisplayServer` (so `Load()` of an unchanged value still reaches it) and emits `FullscreenChanged` only on a real change |
| `MasterVolume` | `float` property | clamped 0…1; setter always applies to bus 0 (same reason as `Fullscreen`) and emits `MasterVolumeChanged` only on a real change |
| `[Signal] FullscreenChanged(bool fullscreen)` | | |
| `[Signal] MasterVolumeChanged(float volume)` | | linear 0…1 |
| `void ToggleFullscreen()` | | flips `Fullscreen` |
| `void Load()` | | `ConfigFile.Load(ConfigPath)`; `Error.FileNotFound`/parse error → defaults (no `GD.PushError`, a missing file is normal); applies both values |
| `void Save()` | | writes both values; `GD.PushWarning` on a write error, never throws |

Behaviour:
- `_EnterTree`: `Instance = this; ProcessMode = ProcessModeEnum.Always;`
- `_Ready`: `Load(); SetProcessUnhandledInput(true);`
- `_UnhandledInput(InputEvent e)`: `if (e.IsActionPressed(ActionToggleFullscreen)) { ToggleFullscreen(); Save(); GetViewport().SetInputAsHandled(); }`
  (`static readonly StringName ActionToggleFullscreen = "toggle_fullscreen"` — no per-event string
  allocation; `_UnhandledInput` runs after GUI input, so a focused Button is never robbed.)
- Applying fullscreen: **guarded for headless** —
  `if (DisplayServer.GetName() == "headless") return;` before
  `DisplayServer.WindowSetMode(fullscreen ? DisplayServer.WindowMode.Fullscreen : DisplayServer.WindowMode.Windowed)`.
  The stored property still changes and still emits, so smoke tests assert the property, never the
  window.
- Applying volume: `AudioServer.SetBusMute(0, v <= MuteThreshold)` and
  `AudioServer.SetBusVolumeDb(0, Mathf.LinearToDb(Mathf.Max(v, MuteThreshold)))`. Bus 0 (`Master`)
  always exists, including under the dummy audio driver.

`user://settings.cfg` shape:
```ini
[display]
fullscreen=true

[audio]
master_volume=0.8
```

### `scenes/ui/MainMenu.tscn` ↔ `scripts/ui/MainMenu.cs`
`partial class MainMenu : Control`, namespace `BlackoutLastGrid.Ui`.

```
MainMenu                Control            (full rect, theme = HudTheme.tres) → MainMenu.cs
├── PH_Background       ColorRect          full rect, RockDeep #12161d, mouse_filter = Ignore
├── PH_Vignette         TextureRect        GradientTexture2D (radial, transparent → #0a0d14),
│                                          full rect, mouse_filter = Ignore
├── Center              VBoxContainer      anchors preset 8 (centre), separation 8
│   ├── LogoRow         HBoxContainer      alignment = Center — letters are built in _Ready
│   ├── Subtitle        Label              «ОСТАННЯ МЕРЕЖА», font_size 26, SteelCold, centred
│   ├── Spacer          Control            custom_minimum_size = (0, 56)
│   └── Buttons         VBoxContainer      separation 12, custom_minimum_size = (360, 0)
│       ├── NewGameButton    Button        «Нова гра»
│       ├── SettingsButton   Button        «Налаштування»
│       └── QuitButton       Button        «Вихід»
├── Version             Label              bottom-left, «BLACKOUT: Last Grid — прототип», font_size 16
└── Settings            SettingsMenu.tscn  instance, hidden
```

| `[Export]` | Type / default | Notes |
|---|---|---|
| `LogoRow` | `HBoxContainer` | letters are added here in `_Ready` |
| `NewGameButton`, `SettingsButton`, `QuitButton` | `Button` | |
| `Settings` | `SettingsMenu` | the instanced child |
| `NewGameScenePath` | `string = "res://scenes/Main.tscn"`, `PropertyHint.File, "*.tscn"` | the run entry point |
| `TitleText` | `string = "BLACKOUT"` | one Label per character |
| `GlowLetterIndex` | `int = 5` | 0-based → the `O`; clamped to the string length |
| `LetterFontSize` | `int = 112` | px |
| `LetterSpacing` | `int = 6` | px, `HBoxContainer` separation |
| `TitleColor` | `Color = #e6e1d0` | unlit letters |
| `GlowLetterColor` | `Color = #ffd98a` (EnergyPale) | the lit letter's glyph |
| `GlowColor` | `Color = #f0a326` (EnergyAmber) | the halo |
| `GlowTexture` | `Texture2D` | radial `GradientTexture2D` sub-resource in the `.tscn` |
| `GlowSize` | `Vector2 = (220, 220)` | px, halo box around the letter |
| `GlowPulsePeriod` | `float = 2.4` | s, one full dim→bright→dim cycle |
| `GlowMinAlpha` / `GlowMaxAlpha` | `float = 0.45` / `1.0` | halo alpha bounds |

Public for tests: `IReadOnlyList<Label> Letters`, `Label? GlowLetter`.

Behaviour:
- `_Ready`: build one `Label` per character of `TitleText` into `LogoRow` (`font_size`,
  `font_color`; the letter at `GlowLetterIndex` gets `GlowLetterColor` plus a child
  `TextureRect` named `Glow` — `GlowTexture`, `custom_minimum_size = GlowSize`,
  `ShowBehindParent = true`, `MouseFilter = Ignore`,
  `Material = new CanvasItemMaterial { BlendMode = Add }`); start one looping `Tween` on the
  halo's `modulate:a` between `GlowMinAlpha` and `GlowMaxAlpha`; connect the three buttons;
  `NewGameButton.GrabFocus()` so keyboard and gamepad work without a mouse.
- `NewGameButton.Pressed` → `GameState.Instance.ResetRun();`
  `GetTree().Paused = false;` (defensive; the menu is never reached paused)
  `GetTree().CallDeferred(SceneTree.MethodName.ChangeSceneToFile, NewGameScenePath);`
- `SettingsButton.Pressed` → `Settings.Open();` — on `Settings.Closed` → `SettingsButton.GrabFocus()`.
- `QuitButton.Pressed` → `GetTree().Quit();`
- All connections made in `_Ready`, removed in `_ExitTree`.
- No `_Process` / `_PhysicsProcess`.

### `scenes/ui/SettingsMenu.tscn` ↔ `scripts/ui/SettingsMenu.cs`
`partial class SettingsMenu : CanvasLayer`, namespace `BlackoutLastGrid.Ui`.
`layer = 30` (above `PauseMenu` 25 and `HUD` 10), `process_mode = 3` (Always) so it works while
the tree is paused.

```
SettingsMenu            CanvasLayer  layer = 30, process_mode = Always → SettingsMenu.cs
└── Root                Control      full rect, visible = false, theme = HudTheme.tres
    ├── PH_Dim          ColorRect    full rect, OutlineDark #0a0d14, alpha 0.85
    └── Panel           PanelContainer  centred, custom_minimum_size = (760, 440)
        └── Margin      MarginContainer  margins 32
            └── VBox    VBoxContainer    separation 20
                ├── Title          Label   «НАЛАШТУВАННЯ», font_size 40, EnergyAmber
                ├── FullscreenRow  HBoxContainer
                │   ├── Label              «Повний екран»  (size_flags_horizontal = Expand)
                │   └── FullscreenCheck    CheckBox
                ├── VolumeRow      HBoxContainer
                │   ├── Label              «Гучність»      (size_flags_horizontal = Expand)
                │   ├── VolumeSlider       HSlider  min 0, max 1, step 0.05, custom_minimum_size (320, 0)
                │   └── VolumeValue        Label    «80 %», custom_minimum_size (80, 0)
                ├── AudioNote      Label   «Звуку в грі ще немає — гучність застосується, коли з'явиться»,
                │                          font_size 16, SteelCold, autowrap
                └── BackButton     Button  «Назад»
```

| `[Export]` | Type / default |
|---|---|
| `Root` | `Control` |
| `FullscreenCheck` | `CheckBox` |
| `VolumeSlider` | `HSlider` |
| `VolumeValue` | `Label` |
| `BackButton` | `Button` |
| `VolumeFormat` | `string = "{0} %"` — `{0}` is the volume as a whole percent (`int`) |

Signal: `[Signal] delegate void ClosedEventHandler();`
Public: `bool IsOpen => Root.Visible;`, `void Open()`, `void Close()`.

Behaviour:
- `_Ready`: hide `Root`; connect `FullscreenCheck.Toggled`, `VolumeSlider.ValueChanged`,
  `BackButton.Pressed`; subscribe to `GameSettings.Instance.FullscreenChanged` and
  `MasterVolumeChanged`; `SetProcessUnhandledInput(false)`.
- `Open()`: read the current values from `GameSettings` into the widgets with
  `SetPressedNoSignal` / `SetValueNoSignal` (so syncing never writes back), show `Root`,
  `BackButton.GrabFocus()`, `SetProcessUnhandledInput(true)`.
- `Close()`: `GameSettings.Instance.Save()`, hide `Root`, `SetProcessUnhandledInput(false)`,
  `EmitSignalClosed()`.
- `FullscreenCheck.Toggled(bool)` → `GameSettings.Instance.Fullscreen = value;`
  `VolumeSlider.ValueChanged(double)` → `GameSettings.Instance.MasterVolume = (float)value;` and
  the label is rebuilt only when the whole percent changes (the `HUD.EnergyLabel` throttle rule).
- `FullscreenChanged` / `MasterVolumeChanged` from the autoload (e.g. F11 pressed while the screen
  is open) → update the widgets with the no-signal setters. This is the reason the hotkey and the
  checkbox can never disagree.
- `_UnhandledInput` (only while open): `ui_cancel` **or** `pause` → `Close()` +
  `GetViewport().SetInputAsHandled()`. Both are Escape, so this also stops the press from reaching
  the pause menu behind it.
- `_ExitTree`: unsubscribe from both autoload signals and the widget signals.
- No `_Process` / `_PhysicsProcess`.

### `scenes/ui/PauseMenu.tscn` ↔ `scripts/ui/PauseMenu.cs`
`partial class PauseMenu : CanvasLayer`, namespace `BlackoutLastGrid.Ui`.
`layer = 25` (above `HUD` 10 **and the `Cutscene` overlay, which is already on 20**, so the pause
screen never depends on sibling order to cover a cutscene; below `SettingsMenu` 30),
`process_mode = 3` (Always).

```
PauseMenu               CanvasLayer  layer = 25, process_mode = Always → PauseMenu.cs
├── Root                Control      full rect, visible = false, theme = HudTheme.tres
│   ├── PH_Dim          ColorRect    full rect, OutlineDark #0a0d14, alpha 0.7
│   └── Center          VBoxContainer  anchors centre, separation 16, custom_minimum_size (420, 0)
│       ├── Title           Label   «ПАУЗА», font_size 48, EnergyAmber, centred
│       ├── ResumeButton    Button  «Продовжити»
│       ├── SettingsButton  Button  «Налаштування»
│       └── QuitButton      Button  «Вихід у головне меню»
└── Settings            SettingsMenu.tscn  instance, hidden
```

| `[Export]` | Type / default |
|---|---|
| `Root` | `Control` |
| `ResumeButton`, `SettingsButton`, `QuitButton` | `Button` |
| `Settings` | `SettingsMenu` |
| `PauseEnabled` | `bool = true` — a level can switch pausing off for a beat without touching the menu's internals |

Signals:
```csharp
[Signal] public delegate void PauseToggledEventHandler(bool paused);
[Signal] public delegate void QuitToMenuRequestedEventHandler();
```

Public: `bool IsOpen => Root.Visible;`, `void Open()`, `void Resume()`.

Behaviour:
- `_Ready`: `ProcessMode = Always` (also set in the `.tscn`, belt and braces), hide `Root`,
  connect the three buttons and `Settings.Closed`, `SetProcessUnhandledInput(true)`.
- `_UnhandledInput(InputEvent e)`: `if (!PauseEnabled || Settings.IsOpen) return;`
  (the settings screen handles its own Escape and is deeper in the tree, but the explicit guard
  means the behaviour does not depend on input-propagation order)
  `if (e.IsActionPressed(ActionPause)) { if (IsOpen) Resume(); else Open(); GetViewport().SetInputAsHandled(); }`
  with `static readonly StringName ActionPause = "pause"`.
- `Open()`: `HitStop.Cancel();` **first** — a freeze in flight would otherwise leave
  `Engine.TimeScale = 0` under the menu and stall every tween/timer in it — then
  `GetTree().Paused = true;` `Root.Visible = true;` `ResumeButton.GrabFocus();`
  `EmitSignalPauseToggled(true);`
- `Resume()`: `Root.Visible = false;` (hiding releases the focused Button) `GetTree().Paused = false;`
  `EmitSignalPauseToggled(false);`
- `SettingsButton.Pressed` → `Settings.Open()`; `Settings.Closed` → `SettingsButton.GrabFocus()`.
- `QuitButton.Pressed` → `Resume(); EmitSignalQuitToMenuRequested();` — the menu never changes the
  scene itself; the level does, because the level owns transitions.
- `_ExitTree`: disconnect everything; if `IsOpen`, `GetTree().Paused = false` (a menu freed while
  open must not leave the tree frozen).
- No `_Process` / `_PhysicsProcess`.

### `scripts/levels/LevelBase.cs` (edited)
New members:

| Member | Type / default | Notes |
|---|---|---|
| `[Export] PauseMenu? Pause` | `null` | optional so a test-instanced level works without one |
| `[Export] MainMenuScenePath` | `string = "res://scenes/ui/MainMenu.tscn"`, `PropertyHint.File, "*.tscn"` | |
| `void GoToMainMenu()` | | `HitStop.Cancel(); GetTree().Paused = false; GameState.Instance.ResetRun(); GetTree().CallDeferred(SceneTree.MethodName.ChangeSceneToFile, MainMenuScenePath);` |

Wiring: `_Ready` → `if (Pause is not null) Pause.QuitToMenuRequested += GoToMainMenu;`
`_ExitTree` → the matching `-=` next to the existing `Player.KnockedOut` unsubscribe.

Edits to existing members (the pause invariant):
- `RestartLevel()` — add `GetTree().Paused = false;` right after `HitStop.Cancel();`.
- `GoToLevel(PackedScene)` — same line, same place.
- `OnPlayerKnockedOut()` — the restart timer changes from `processAlways: true` to
  `processAlways: false`. `ignoreTimeScale: true` stays (that is what protects the delay from
  hit-stop); `processAlways` only ever concerned pause, and a KO restart firing under an open
  pause menu — reloading the scene while `Paused` is true — is the bug it would cause.

### `scripts/ui/Cutscene.cs` (edited)
`_PhysicsProcess` gains a first line `if (GetTree().Paused) return;`. `ProcessMode.Always` stays
(it is what keeps the overlay alive while the level disables the hero), but with the guard a
paused tree can neither advance a line on a stray `interact`/`attack` nor accumulate
`LineDuration`. Without it, pausing during a cutscene silently skips lines.

### `scripts/levels/Level00_Prologue.cs` (edited)
`_danTimer` changes from `processAlways: true` to `processAlways: false`, same reasoning as the
KO restart timer: the alarm→Dan beat must not tick while the game is paused.

### Level scenes (edited)
`Level00_Prologue.tscn`, `Level01_District.tscn`, `TestRoom.tscn`: add a `PauseMenu.tscn` instance
named `PauseMenu` as a child of the level root (next to the existing `HUD` instance) and add
`Pause = NodePath("PauseMenu")` to the root node's `node_paths` export block. No other node in
these scenes changes.

### `scenes/ui/HudTheme.tres` (edited, additive only)
New sub-resources and entries, all in the brief's palette; **nothing existing is modified**
(`tests/smoke/ui_hud.gd` asserts the identity of the `Label` font colour and the two `ProgressBar`
styleboxes — they must stay byte-identical):
- `StyleBoxFlat_button_normal` — bg `#1b212b`, 1 px border `#39424f`, corner radius 3, content
  margins 16/10.
- `StyleBoxFlat_button_hover` — bg `#252d3a`, border `#4d5866`.
- `StyleBoxFlat_button_pressed` — bg `#39424f`, border `#f0a326`.
- `StyleBoxFlat_button_focus` — transparent bg, 2 px border `#f0a326` (the gamepad/keyboard cursor).
- `StyleBoxFlat_panel` — bg `#12161d` at alpha 0.96, 2 px border `#39424f`, corner radius 4.
- `Button/styles/normal|hover|pressed|focus|disabled`, `Button/colors/font_color` `#e6e1d0`,
  `font_hover_color`/`font_pressed_color` `#ffd98a`, `Button/font_sizes/font_size` 28.
- `PanelContainer/styles/panel`, plus `CheckBox` and `HSlider` colour/stylebox entries reusing the
  same boxes.

## File-level change list

### `scenes/`
| File | New/Edit | Intent |
|---|---|---|
| `scenes/ui/MainMenu.tscn` | new | Title screen; new `run/main_scene`. `Control` root + logo row + three buttons + `SettingsMenu` instance. |
| `scenes/ui/SettingsMenu.tscn` | new | Shared settings overlay (`CanvasLayer` 30, Always), instanced by both menus. |
| `scenes/ui/PauseMenu.tscn` | new | Pause overlay (`CanvasLayer` 25, Always) with its own `SettingsMenu` instance. |
| `scenes/ui/HudTheme.tres` | edit | Additive `Button` / `CheckBox` / `HSlider` / `PanelContainer` entries so menus match the HUD. |
| `scenes/levels/Level00_Prologue.tscn` | edit | Add the `PauseMenu` instance and the `Pause` node path on the root. |
| `scenes/levels/Level01_District.tscn` | edit | Same. |
| `scenes/levels/TestRoom.tscn` | edit | Same, so pausing is testable in the dev room too. |

### `scripts/`
| File | New/Edit | Intent |
|---|---|---|
| `scripts/core/GameSettings.cs` | new | Autoload: preferences, `user://settings.cfg`, apply to `DisplayServer`/`AudioServer`, global `toggle_fullscreen`. |
| `scripts/ui/MainMenu.cs` | new | Procedural §8 logo, three buttons, `ResetRun` + `ChangeSceneToFile(Main.tscn)`. |
| `scripts/ui/SettingsMenu.cs` | new | Widgets ↔ `GameSettings`, save on close, `ui_cancel`/`pause` closes. |
| `scripts/ui/PauseMenu.cs` | new | Owns `GetTree().Paused`, cancels hit-stop, emits `QuitToMenuRequested`. |
| `scripts/levels/LevelBase.cs` | edit | `Pause` export + `QuitToMenuRequested` wiring, `GoToMainMenu()`, unpause on every transition, KO timer no longer `processAlways`. |
| `scripts/ui/Cutscene.cs` | edit | One `GetTree().Paused` guard in `_PhysicsProcess`. |
| `scripts/levels/Level00_Prologue.cs` | edit | Dan-delay timer no longer `processAlways`. |

### `tests/smoke/`
| File | New/Edit | Intent |
|---|---|---|
| `tests/smoke/core_settings.gd` | new | `GameSettings` autoload: defaults, apply, `ConfigFile` round-trip on a throwaway path, signals, headless guard. |
| `tests/smoke/ui_menu.gd` | new | `MainMenu.tscn` wiring, logo letters + glow, buttons, «Нова гра» → `Main` becomes `current_scene` and a KO still reloads it. |
| `tests/smoke/ui_pause.gd` | new | `PauseMenu.tscn`: process modes, `Paused` on/off, hit-stop cancelled on open, `QuitToMenuRequested`, settings-first Escape, cutscene frozen while paused. |
| `tests/smoke/core_gamestate.gd` | edit | Assert the two new actions, the new autoload, `run/main_scene`, `display/window/size/mode`. |

### `docs/`
| File | Edit | Intent |
|---|---|---|
| `docs/plans/t07i-a-fullscreen-menu/t07i-a-fullscreen-menu-plan.md` | new | This plan. |
| `docs/TASKS.md` | edit | T-07i-a → `in_progress` → `done` + «Зроблено / Не зроблено» + Плейтест + Рев'ю lines; the three `T-B03…T-B05` backlog entries from *Scope → Out*. |

### `project.godot` / `.csproj`
`BlackoutLastGrid.csproj` and the `.sln` are **not** touched. `project.godot` changes are below and
were produced through the `project-settings` skill.

## `project.godot` — exact changes

Four edits, in the sections Godot already emits, keys in Godot's own order.

**1. `[application]` — `run/main_scene`** (classification: **breaking** — the entry point changes;
justified verbatim by the T-07i-a bullet «`scenes/ui/MainMenu.tscn` — початковий екран … стає
`run/main_scene`»):
```ini
[application]

config/name="BLACKOUT: Last Grid"
run/main_scene="res://scenes/ui/MainMenu.tscn"
config/features=PackedStringArray("4.7", "C#", "Forward Plus")
```
`Main.tscn` remains the run entry point, reached from «Нова гра»; nothing else referenced it as
`main_scene` (`grep -rn "main_scene" scripts/ tests/` → no hits; the smoke scripts load
`res://scenes/Main.tscn` by path and set `current_scene` themselves, so they are unaffected).

**2. `[autoload]` — the settings service** (classification: **additive**; justified by the bullets
«перемикання вікно/повний екран гарячою клавішею і в налаштуваннях» and «Екран налаштувань
(повний екран, гучність)», which need one owner reachable from both menus):
```ini
[autoload]

GameState="*res://scripts/core/GameState.cs"
HitStop="*res://scripts/core/HitStop.cs"
GameSettings="*res://scripts/core/GameSettings.cs"
```
Appended last, so `GameState` and `HitStop` are in the tree before it (`GameSettings` does not
depend on either, but keeping the existing two first keeps the diff to one line).

**3. `[display]` — start fullscreen** (classification: **behavior-changing**; justified by «Гра
стартує у повноекранному режимі»). `window/size/mode=3` is `DisplayServer.WINDOW_MODE_FULLSCREEN`
— Godot 4's borderless, alt-tab-friendly fullscreen, not exclusive (`4`). Stretch mode and aspect
are **unchanged**, as the task requires:
```ini
[display]

window/size/viewport_width=1920
window/size/viewport_height=1080
window/size/mode=3
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"
```

**4. `[input]` — two new actions** (classification: **additive**; justified by «перемикання
вікно/повний екран гарячою клавішею» and «меню паузи … на дію `pause`»). Appended after
`flashlight`, keeping the ten canonical actions untouched and in order:
```ini
pause={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194305,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null), Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":6,"pressure":0.0,"pressed":false,"script":null)]
}
toggle_fullscreen={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194342,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null), Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":true,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":4194309,"key_label":0,"unicode":0,"location":0,"echo":false,"script":null)]
}
```
- `pause`: `physical_keycode 4194305` = `Key.Escape`; `button_index 6` = `JoyButton.Start`.
- `toggle_fullscreen`: `physical_keycode 4194342` = `Key.F11`; second event `alt_pressed: true` +
  `4194309` = `Key.Enter` → Alt+Enter. **No gamepad event on purpose**: there is no conventional
  pad binding for a window mode, Start is already `pause`, and the setting is reachable from the
  settings screen with a pad. This is the one deliberate exception to "keyboard + gamepad on every
  action" in the `project-settings` skill and is called out here so `/reviewer` does not read it
  as an omission. `core_gamestate.gd`'s "≥ 2 events" rule still holds (F11 + Alt+Enter).

**Commit body paragraph** (verbatim, for `/task` to paste):
```
project.godot: changed run/main_scene to res://scenes/ui/MainMenu.tscn because T-07i-a bullet 2 makes the main menu the start screen (Main.tscn is now reached from «Нова гра», so LevelBase.RestartLevel's ReloadCurrentScene still rebuilds the level).
project.godot: added autoload GameSettings=res://scripts/core/GameSettings.cs because T-07i-a bullets 1 and 3 need one owner for the fullscreen/volume preferences, the user://settings.cfg persistence and the global toggle_fullscreen hotkey, shared by the main menu and the pause menu.
project.godot: set display/window/size/mode=3 (fullscreen) because T-07i-a bullet 1 requires the game to start fullscreen; window/stretch/mode stays "canvas_items".
project.godot: added InputMap action "pause" (Escape / gamepad Start) because T-07i-a bullet 3 requires the pause menu on a "pause" action.
project.godot: added InputMap action "toggle_fullscreen" (F11 / Alt+Enter, keyboard only by design) because T-07i-a bullet 1 requires a window/fullscreen hotkey that works in the menu and in the game.
```

## Acceptance criteria
1. Given a freshly built project, running it opens `MainMenu` — the word BLACKOUT with exactly one
   letter (index `GlowLetterIndex`, the `O`) in `GlowLetterColor` with a pulsing halo, the subtitle
   «ОСТАННЯ МЕРЕЖА», and the three buttons; `NewGameButton` has focus, so `ui_down`/`ui_accept`
   (keyboard and gamepad) navigate without a mouse.
2. Given the project settings, `ProjectSettings.get_setting("display/window/size/mode") == 3`,
   `run/main_scene == "res://scenes/ui/MainMenu.tscn"`, `window/stretch/mode == "canvas_items"`,
   and `InputMap.has_action("pause") && InputMap.has_action("toggle_fullscreen")` with ≥ 2 events
   each; the ten canonical actions are unchanged.
3. Given the main menu, pressing «Нова гра» → `GetTree().CurrentScene` is the `Main` node,
   `GameState.Energy == GameState.MaxEnergy`, and the prologue is running. Then, given the hero is
   KO'd in that run, after `RestartDelay` the tree's current scene is **still `Main`** and a fresh
   prologue is playing (the T-07 restart contract survives the menu).
4. Given a running level, pressing `pause` → `GetTree().Paused == true`, the pause overlay is
   visible over the HUD, `ResumeButton` has focus, and `Engine.TimeScale == 1.0` even if a
   hit-stop was in flight at that instant. Pressing `pause` again → `Paused == false`, the overlay
   is hidden, and the hero is controllable again.
5. Given the pause menu is open while a `Cutscene` is playing, no line advances and
   `Cutscene.CurrentLine` is unchanged after 30 real frames of `interact`/`attack` presses; after
   resuming, the cutscene advances normally.
6. Given the pause menu is open, «Налаштування» opens the settings overlay above it; Escape there
   closes settings and leaves the game **still paused**; Escape again resumes.
7. Given the pause menu, «Вихід у головне меню» → `GetTree().Paused == false`,
   `Engine.TimeScale == 1.0`, `GameState.Energy == MaxEnergy`, and the current scene is `MainMenu`.
8. Given the settings screen, ticking «Повний екран» sets `GameSettings.Instance.Fullscreen` and
   emits `FullscreenChanged`; pressing `toggle_fullscreen` (F11) while the screen is open flips
   both the property **and** the checkbox, and does not re-emit a change per widget update.
9. Given the volume slider moved to 0.5, `GameSettings.Instance.MasterVolume == 0.5 ± 0.001`,
   `AudioServer.GetBusVolumeDb(0) == Mathf.LinearToDb(0.5) ± 0.01`, and the value label reads
   «50 %»; at 0, `AudioServer.IsBusMute(0) == true`.
10. Given `GameSettings.ConfigPath` points at a file with `fullscreen=false` / `master_volume=0.35`,
    `Load()` yields exactly those values; given a missing file, `Load()` yields
    `DefaultFullscreen` / `DefaultMasterVolume` and prints **no** `ERROR:` line;
    `Save()` then `Load()` round-trips any value set in between.
11. Given `--headless`, no `DisplayServer.WindowSetMode` call is made (`DisplayServer.GetName()`
    guard) and `godot --headless --path . --quit` plus all smoke scripts finish with no `ERROR:`
    or `SCRIPT ERROR:` line.
12. Given `godot --headless --path . res://scenes/Main.tscn --quit`, the prologue still loads
    clean — the entry-point change does not hide the level from verification.
13. Given any level transition (`RestartLevel`, `GoToLevel`, `GoToMainMenu`), `GetTree().Paused` is
    `false` and `Engine.TimeScale` is `1.0` on the frame after it.
14. No new file under `assets/`; no new NuGet package or addon; `.csproj` unchanged.

## Test strategy
This is a **new feature** plus a **behaviour change to existing scripts** (`LevelBase`,
`Cutscene`), so the new smoke coverage is non-negotiable and the existing suite must stay green
untouched — in particular `tests/smoke/level_prologue.gd` (the prologue gains a `PauseMenu`
instance and two timer-flag changes) and `tests/smoke/ui_hud.gd` (the theme gains entries).
All scripts follow the house pattern: `extends SceneTree`, checks started from the first
`_process`, `SMOKE <name> PASS|FAIL: <reason>` + `quit(0|1)`, `MAX_FRAMES` safety net,
`await physics_frame` stepping, `current_scene` assigned by hand where a scene change is involved.

**`tests/smoke/core_settings.gd` (new)** — the autoload and the project settings it needs:
- `root.get_node_or_null("GameSettings") != null`; `process_mode == PROCESS_MODE_ALWAYS`.
- `ProjectSettings.get_setting("display/window/size/mode") == 3`,
  `"display/window/stretch/mode" == "canvas_items"`,
  `"application/run/main_scene") == "res://scenes/ui/MainMenu.tscn"`.
- Redirect `ConfigPath` to `user://settings_smoke.cfg`, delete any leftover, then:
  `Load()` with no file → `Fullscreen == DefaultFullscreen`, `MasterVolume == DefaultMasterVolume`;
  set `Fullscreen = false`, `MasterVolume = 0.35`, `Save()`; `FileAccess.file_exists` on the path;
  flip both to other values, `Load()` again → `false` / `0.35` back.
- Signal counting: connect `FullscreenChanged` / `MasterVolumeChanged`; setting the same value
  twice emits once; `ToggleFullscreen()` emits once and flips.
- Volume mapping: `MasterVolume = 0.5` → `AudioServer.get_bus_volume_db(0)` ≈ `linear_to_db(0.5)`;
  `MasterVolume = 0.0` → `AudioServer.is_bus_mute(0) == true`; restore 1.0 / unmuted at the end.
- Teardown: delete `user://settings_smoke.cfg` with `DirAccess.remove_absolute`, restore
  `ConfigPath` to `user://settings.cfg` and reload it, so the runner leaves no state behind and
  never overwrites the author's real preferences.

**`tests/smoke/ui_menu.gd` (new)**:
- `MainMenu.tscn` loads; root is a `Control` with `MainMenu.cs`; theme resource path ends with
  `HudTheme.tres`.
- After `add_child` + one frame: `LogoRow` has `TitleText.length()` Label children, their texts
  concatenate to `"BLACKOUT"`, exactly one of them carries a child named `Glow`
  (`show_behind_parent == true`, `mouse_filter == IGNORE`, material blend mode = add), and it is
  the one at `GlowLetterIndex`.
- The three buttons exist with the exact Ukrainian texts; `NewGameButton.has_focus()`.
- `NewGameScenePath == "res://scenes/Main.tscn"` **and** `load(NewGameScenePath) != null` (a typo
  in the path would otherwise only show at runtime).
- `Settings` export is a `SettingsMenu` instance and `IsOpen == false`; `SettingsButton` pressed →
  `IsOpen == true`; `Close()` → `IsOpen == false` and `SettingsButton.has_focus()`.
- End-to-end (last, because it replaces the tree's scene): `current_scene = menu`, set
  `GameState.Energy = 12`, press «Нова гра», wait for the deferred change → `current_scene.name ==
  "Main"`, the current scene has `Main.cs`, `GameState.Energy == MaxEnergy`, and the prologue
  level exists under it. Then call the level's `RestartLevel()` and confirm `current_scene` is
  again a `Main` with a fresh level — acceptance criterion 3, the one the task calls out.

**`tests/smoke/ui_pause.gd` (new)**:
- `PauseMenu.tscn` loads; root is a `CanvasLayer`, `layer == 25`,
  `process_mode == PROCESS_MODE_ALWAYS`; the nested `SettingsMenu` is `layer == 30`, also Always.
- `Open()` → `paused == true`, `Root.visible`, `ResumeButton.has_focus()`, and a
  `PauseToggled(true)` was emitted; `Resume()` → `paused == false`, hidden, `PauseToggled(false)`.
- Hit-stop safety without touching the C# static: set `Engine.time_scale = 0.0` by hand, `Open()`,
  assert `Engine.time_scale == 1.0` (the `HitStop.Cancel()` call inside `Open`).
- `Settings.Open()` then `pause` pressed → still `paused == true` and the settings overlay closed
  (the "settings first" guard); a second `pause` resumes.
- `QuitToMenuRequested`: connect, press `QuitButton`, assert the signal fired **and**
  `paused == false` — and that the menu itself did **not** change the scene (`current_scene`
  unchanged), since that is `LevelBase`'s job.
- Freeing an open pause menu leaves `paused == false`.
- Cutscene interaction: instance `scenes/ui/Cutscene.tscn`, `Play(["a","b"])`, set
  `paused = true`, hold `interact` for 30 physics frames → `CurrentLine == 0`; unpause, press
  `interact` → `CurrentLine == 1`.
- `LevelBase` invariant: instance `TestRoom.tscn` with `current_scene` set, `paused = true`, call
  `GoToMainMenu()` → after the deferred change, `paused == false`, `Engine.time_scale == 1.0`,
  `current_scene` is the `MainMenu`, `GameState.Energy == MaxEnergy`.

**`tests/smoke/core_gamestate.gd` (edited)** — the project-skeleton test grows the new
project-settings assertions (mandatory per the `project-settings` skill): the two new actions in a
separate `NEW_ACTIONS` list (still `≥ 2` events each, so the keyboard-only
`toggle_fullscreen` is covered), `root.has_node("GameSettings")`, `run/main_scene`, and
`display/window/size/mode`. The existing `ACTIONS` list and `Main.tscn` check stay as they are.

**Only verifiable by hand** (→ Playtest): whether the window actually goes fullscreen and back
(headless has no window and the code is guarded), whether the logo reads as "one lit window in a
dark block", the glow pulse rate, whether the menu is legible on a real monitor, whether the dim
layer sits above the HUD, whether Alt+Enter double-toggles because the OS/engine already handles
it, focus visibility with a gamepad, and the feel of pausing mid-combo.

## Playtest (manual QA)
1. Запустити гру (F5). Очікувано: **повний екран**, головне меню на темному тлі: слово
   **BLACKOUT**, у якому літера **O** світиться теплим і повільно пульсує; під ним «ОСТАННЯ
   МЕРЕЖА»; три кнопки; рамка виділення стоїть на «Нова гра».
2. Натиснути **F11**. Очікувано: гра переходить у вікно. **F11** ще раз — знову повний екран.
   Те саме перевірити через **Alt+Enter** (якщо один натиск нічого не змінює — записати: систему
   вже перехоплює ОС/движок, лишити тільки F11).
3. Стрілками/D-pad пройти по кнопках, натиснути **«Налаштування»**. Очікувано: панель налаштувань,
   чекбокс «Повний екран» відповідає поточному стану вікна, повзунок гучності, підпис про
   відсутність звуку, кнопка «Назад» у фокусі.
4. У налаштуваннях зняти галку «Повний екран» — вікно згортається у віконний режим одразу.
   Натиснути **F11** — галка сама ставиться назад. Посунути гучність на ~50 % — підпис показує
   «50 %». **Esc** або «Назад» — повернення в меню.
5. Вийти з гри (**«Вихід»**) і запустити знову. Очікувано: гра стартує в тому режимі вікна і з тією
   гучністю, які лишилися з кроку 4 (перевірка `user://settings.cfg`). Повернути «Повний екран».
6. **«Нова гра»**. Очікувано: пролог із самого початку — вступна кат-сцена, повна шкала енергії.
7. Під час кат-сцени натиснути **Esc**. Очікувано: меню паузи видно **поверх** тексту кат-сцени
   (перевірка `layer = 25` проти `Cutscene` на 20), гра стає на паузу, текст кат-сцени **не**
   гортається, скільки б не тиснути E чи J; «Продовжити» — кат-сцена йде далі з того самого рядка.
8. Пройти до охоронців у кімнаті виходу, почати бій і натиснути **Esc** у момент удару (у hit-stop).
   Очікувано: меню паузи з'являється миттєво і не «підвисає»; після «Продовжити» бій іде далі з
   нормальною швидкістю, а не в сповільненні.
9. На паузі натиснути **«Налаштування»** → **Esc**. Очікувано: закрилися лише налаштування, гра
   лишилась на паузі. Ще раз **Esc** — гра продовжилась.
10. Дати себе побити до нуля енергії і натиснути **Esc** одразу після нокауту. Очікувано: поки
    відкрито паузу, рівень не перезапускається; після «Продовжити» — рестарт прологу з початку
    (як і раніше), меню паузи знову працює у перезапущеному рівні.
11. На паузі натиснути **«Вихід у головне меню»**. Очікувано: головне меню, гра не заморожена
    (пульсація логотипа йде), «Нова гра» знову запускає пролог із повною енергією.
12. Пройти пролог до кінця (ліфт → бригадир → рівень 1). У порожньому «Рівні 1» натиснути **Esc**.
    Очікувано: меню паузи працює і там.
13. Геймпад: **Start** відкриває/закриває паузу, стік/D-pad ходить по кнопках, **A** натискає.
14. Окремо запустити `scenes/levels/TestRoom.tscn` (F6). Очікувано: **Esc** так само ставить на
    паузу, **F11** так само перемикає екран.

## Review focus
`input map`, `signals/decoupling`, `scene/tscn integrity`, `hit-stop/timescale`.
(Secondary, if there is room: `GameState usage` — `ResetRun` on «Нова гра» and on quit-to-menu.)

## Performance & frame budget
- **No new `_Process` or `_PhysicsProcess` anywhere.** `GameSettings` only implements
  `_UnhandledInput`; all three menu scripts are event-driven (`Pressed`, `Toggled`,
  `ValueChanged`, autoload signals). Action names are cached `static readonly StringName`s, so no
  string is allocated per input event.
- The one continuous cost is the main-menu logo `Tween` — a single `modulate:a` interpolation on
  one `TextureRect`, alive only while `MainMenu` is the current scene, freed with it.
- The volume label is rebuilt only when the whole percent changes (the `HUD.EnergyLabel` throttle
  rule), so dragging the slider allocates one string per percent step, not per frame.
- While paused, `GetTree().Paused = true` stops every level node; the only nodes still ticking are
  the `Always` autoloads (`GameState` — no `_Process`; `HitStop` — `SetProcess(false)` unless a
  freeze is in flight, and `PauseMenu.Open` cancels it; `GameSettings` — input only) and the two
  menu `CanvasLayer`s (input only). Pausing therefore *reduces* frame cost.
- Menus add no `Area2D`, no `PointLight2D`, no physics body and no y-sorted node; the glow is one
  additive `TextureRect` over a `GradientTexture2D` sub-resource, and the vignette one more.
- Node lookups: every widget reaches its script through an `[Export]`; no `GetNode` at runtime, no
  `GetNode("../..")` across scene boundaries. `LevelBase` reaches the pause menu only through its
  own `[Export]`, and the pause menu reaches the level only through a signal.

## Risks
1. **The headless load no longer covers the prologue.** `godot --headless --path . --quit` will
   now load `MainMenu` instead of `Main` → the level graph stops being exercised by the standard
   check. Mitigation: `/verify` must also run
   `godot --headless --path . res://scenes/Main.tscn --quit` (its "Scene" step), and
   `core_gamestate.gd` / `level_prologue.gd` keep loading `Main.tscn` by path. Call this out in the
   PR body so it does not silently rot.
2. **Alt+Enter may already be handled by the OS/engine on Windows**, which would toggle twice and
   look like "nothing happens". Playtest step 2 checks it; if it double-toggles, drop the second
   event from `toggle_fullscreen` and keep F11 (a one-line `project.godot` revert).
3. **`DisplayServer` under `--headless`.** Calling window functions on the headless driver can log
   errors, and the smoke runner fails on any `ERROR:` line. Mitigated by the explicit
   `DisplayServer.GetName() == "headless"` guard; the smoke scripts assert the *property*, never
   the window state.
4. **Smoke runs writing the author's real `user://settings.cfg`.** Mitigated by `ConfigPath` being
   settable and `core_settings.gd` using `user://settings_smoke.cfg` and deleting it. `/coder` must
   not hard-code the path inside `Load`/`Save`.
5. **A frozen game after a transition.** `GetTree().Paused` is global; if a scene changes while it
   is `true`, the next scene comes up dead. Mitigated by the invariant in `RestartLevel`,
   `GoToLevel`, `GoToMainMenu` and `PauseMenu._ExitTree`; acceptance criterion 13 and the pause
   smoke both check it.
6. **A stuck `Engine.TimeScale`.** Opening the pause menu during a hit-stop would otherwise leave
   `TimeScale = 0` under the menu. `PauseMenu.Open()` calls `HitStop.Cancel()` — a deliberate,
   documented behaviour change: **a hit-stop in flight is dropped when the player pauses**, it does
   not resume afterwards. Recorded here so `/reviewer` reads it as intent, not as a bug.
7. **Two Escape meanings.** `pause` and the built-in `ui_cancel` share Escape. Handled by
   `SettingsMenu` consuming the press (`SetInputAsHandled`) when it is open and by
   `PauseMenu`'s explicit `Settings.IsOpen` guard, so the order does not depend on input
   propagation. Watch for a third consumer appearing later (a dialog).
8. **Theme regressions.** `ui_hud.gd` asserts stylebox/colour *identity* for `ProgressBar` and
   `Label` in `HudTheme.tres`. The edit must be strictly additive — a re-save of the resource from
   the editor could reorder or rewrite existing entries. Edit the `.tres` by hand and re-run
   `ui_hud.gd`.
9. **Fullscreen at startup is inconvenient for development** (a fullscreen window on every F5).
   F11 is always available, and the setting persists after the first toggle, so this only bites
   once per machine.
10. **Three autoloads vs. the CLAUDE.md single-`GameState` rule** — argued in *GameState & save
    impact*; if the author disagrees, the fallback is two properties on `GameState` plus one
    handler node, which costs the hotkey-anywhere guarantee (see Open questions).
11. **Three level scenes gain a node.** `.tscn` edits must keep `ext_resource` paths and `uid`s
    valid and add `Pause` to each root's `node_paths` array; a stale `node_paths` entry silently
    nulls the export. `level_prologue.gd` and `enemy_wave.gd` instantiate these scenes directly and
    will catch a broken file immediately.
12. **T-07i-b/-c overlap.** `scripts/art/Palette.cs` arrives in T-07i-b; this task uses `[Export]`
    `Color`s with the brief's hex values instead, which T-07i-b or -c may later migrate. That is a
    known, accepted duplication of five colour constants, not a design decision to re-open.

## Open questions
1. **Third autoload.** Confirm `GameSettings` as a service autoload alongside `GameState` and
   `HitStop`. Fallback if not: `Fullscreen`/`MasterVolume` as `GameState` properties plus a small
   `Node` for the hotkey inside each menu/level — cheaper on autoloads, worse on duplication and
   on "F11 works everywhere".
2. **Fullscreen flavour.** `window/size/mode=3` (borderless fullscreen, alt-tab friendly,
   recommended) vs `4` (exclusive fullscreen, marginally lower latency, worse alt-tab). Plan
   assumes `3`.
3. **Subtitle wording.** «ОСТАННЯ МЕРЕЖА» (from §8's Ukrainian localization) vs the Latin
   «LAST GRID». `[Export] string`, so a one-word change either way; plan assumes the Ukrainian.
4. **Volume default.** Plan assumes `0.8` linear. If the author wants `1.0`, one `[Export`] default.
5. **«Нова гра» reference style.** Plan uses an exported **path** + `ChangeSceneToFile` to keep the
   prologue out of the menu's load graph, deviating from the `[Export] PackedScene` convention used
   by `Main.StartLevel` / `GoToLevel`. Confirm, or switch to `PackedScene` and accept the menu
   loading the whole level before it draws.

## Resolved (agent decision, 2026-09-10 — author asleep, routine defaults; may be overturned)
1. **Third autoload — yes.** `GameSettings` is a machine-preferences service, not run state, so it
   does not violate the CLAUDE.md rule that run state lives only in `GameState`. Document the new
   autoload in the commit body per `/project-settings`.
2. **Fullscreen flavour — `mode=3`** (borderless fullscreen). Alt-tab friendliness beats the
   marginal latency win of exclusive fullscreen for a 2D game.
3. **Subtitle — «ОСТАННЯ МЕРЕЖА»** (Ukrainian, matching §8's localization and the all-Ukrainian UI).
   Stays an `[Export]`, so the author can flip it in the inspector.
4. **Volume default — `0.8` linear**, as planned.
5. **«Нова гра» — exported path + `ChangeSceneToFile`**, as planned. Keeping the prologue out of
   the menu's load graph is worth the deviation from the `[Export] PackedScene` convention; note
   the deviation in the class doc comment so the next reader does not "fix" it.


## Review findings

### Round 1 — Ship: yes

#### Summary
The branch wraps the existing vertical slice in a shell: a procedural-logo main menu that is the
new `run/main_scene`, a shared settings overlay backed by a new `GameSettings` autoload with
`user://settings.cfg`, a pause menu instanced in all three level scenes, fullscreen at start plus
a `toggle_fullscreen` hotkey, and the "every transition unpauses and cancels hit-stop" invariant
in `LevelBase`. Build 0 warnings / 0 errors, headless load clean, smoke 13 passed / 0 failed
(3 new scripts), `res://scenes/Main.tscn` still loads clean under the new entry point.

#### Plan conformance
Plan: `docs/plans/t07i-a-fullscreen-menu/t07i-a-fullscreen-menu-plan.md` (read in full, including
`## Resolved`).
TASKS.md: **wrong at review time** — T-07i-a is still `todo` (the cycle wants `in_progress` during
the work and `done` at the end) and the three `T-B03…T-B05` backlog entries the plan's
*Scope → Out* lists verbatim are not in the file yet. See S2.
- Implemented as planned: `GameSettings` autoload (defaults, ConfigFile round-trip, headless
  `DisplayServer` guard, `toggle_fullscreen` in `_UnhandledInput` with a cached `StringName`);
  `MainMenu.tscn`/`.cs` with the §8 logo built from one Label per character, one lit letter, an
  additive `GradientTexture2D` halo on a looping Tween, «ОСТАННЯ МЕРЕЖА», three buttons, focus on
  «Нова гра», exported path + `ChangeSceneToFile` (Resolved #5); `SettingsMenu.tscn`/`.cs`
  instanced twice with the no-signal widget sync in both directions; `PauseMenu.tscn`/`.cs` at
  layer 20 / ProcessMode Always, `HitStop.Cancel()` first in `Open()`, `QuitToMenuRequested`
  instead of its own scene change, unpause backstop in `_ExitTree`; `LevelBase.Pause` +
  `GoToMainMenu()` + `GetTree().Paused = false` in all three transitions + the KO timer no longer
  `processAlways`; the `Cutscene` pause guard; the Dan timer; the `PauseMenu` instance and the
  `Pause` node path in all three level scenes; the four `project.godot` edits exactly as written
  in *`project.godot` — exact changes* (verified at runtime: `pause` → Escape + pad button 6
  (Start), `toggle_fullscreen` → F11 + Alt+Enter keyboard-only, `window/size/mode=3` =
  `WINDOW_MODE_FULLSCREEN`, not exclusive `4`); `HudTheme.tres` strictly additive — the diff
  touches exactly one pre-existing line, the `load_steps` header, so `ui_hud.gd`'s stylebox and
  font-colour identity checks are untouched and still green.
- Deviates from plan: `GameSettings.Fullscreen` / `MasterVolume`
  (`scripts/core/GameSettings.cs:63,82`) **apply** on every set, not only on a real change; only
  the *signal* is change-gated as the contract says. This is deliberate and correct — the backing
  fields are initialised to the defaults, so a `Load()` that reads back the same value would
  otherwise never reach `AudioServer`, leaving the master bus at 0 dB while the property claimed
  0.8 — but the contract row in *Scene & signal contract* and the XML doc are now stale. See S3.
- Missing / partial: the `docs/TASKS.md` line of the File-level change list (status, done-note,
  T-B03…T-B05). See S2.
- Accepted limitation (per plan): a hit-stop in flight is **dropped**, not resumed, when the
  player pauses (risk 6) — residual risk: a heavy hit that connects on the exact frame the player
  pauses loses its impact freeze; invisible in practice, documented in the plan.
- Accepted limitation (per plan): `toggle_fullscreen` has no gamepad event — residual risk: a
  pad-only player must go through «Налаштування»; the checkbox is reachable with a pad, so
  nothing becomes unreachable.
- Accepted limitation (per plan): the standard headless load now boots `MainMenu`, not the
  prologue (risk 1) — residual risk: a broken prologue would no longer fail
  `godot --headless --path . --quit`. Mitigated: `/verify` also loads `res://scenes/Main.tscn`
  (run this round, clean) and `level_prologue.gd` / `ui_menu.gd` both boot it by path.

#### Code
- [x] **S1. The pause overlay covers the cutscene only by accident of node order** —
  `scenes/ui/PauseMenu.tscn:9`, `scenes/ui/Cutscene.tscn:7`,
  `scenes/levels/Level00_Prologue.tscn:671,682` — Should-fix
  **Problem / why it matters:** `PauseMenu` and the pre-existing `Cutscene` are both
  `CanvasLayer` **layer 20**. Godot only falls back to tree order when the layer numbers tie, so
  today the pause menu draws on top purely because its node happens to sit after `Cutscene` in
  `Level00_Prologue.tscn` (verified on the packed state:
  `HUD(10) > Cutscene(20) > UI > PauseMenu(20)`). Any later edit that inserts the pause menu
  earlier — or an editor re-save that reorders children — puts the pause menu **behind** the
  cutscene's own 0.7-alpha overlay and text, and playtest step 7 (Esc during the intro cutscene)
  silently regresses into an unreadable screen. The plan picked 20 as "above HUD 10, below
  SettingsMenu 30" without noticing `Cutscene` already held 20.
  **Fix:** Option A (correct): give the pause menu its own band — `layer = 25` in
  `scenes/ui/PauseMenu.tscn`, update `PAUSE_LAYER` in `tests/smoke/ui_pause.gd` and the two
  places this plan states 20. Nothing else reads the number. Option B (cheap): keep 20 and assert
  in `ui_pause.gd` that the `PauseMenu` node comes after every other `CanvasLayer` in each level
  scene — locks the accident in place instead of making the intent explicit.
- [x] **S2. The plan's `docs/TASKS.md` work is not done** — `docs/TASKS.md:112` — Should-fix
  **Problem / why it matters:** T-07i-a is still `todo` although the branch implements it, and
  the three backlog entries `T-B03` (resolution / key rebinding), `T-B04` (Music/SFX buses) and
  `T-B05` («Продовжити») that the plan's *Scope → Out* dictates verbatim are missing. Without
  them the deliberately deferred scope is lost the moment this branch merges, and the next
  session cannot tell what was cut on purpose from what was forgotten.
  **Fix:** set the heading to `done`, add the «**Зроблено:** … / **Не зроблено:** …»,
  «**Рев'ю:**» and «**Плейтест:**» lines in the T-07 format, and paste the three `T-B03…T-B05`
  blocks next to `T-B02`, before `## Backlog`. (Status and done-note belong to `/task`, not to
  `/coder`.)
- [x] **S3. The `GameSettings` doc comments describe a setter that only *emits* on change, not
  one that always applies** — `scripts/core/GameSettings.cs:58-61,77-80` — Should-fix
  **Problem / why it matters:** the summaries read as if both the apply and the signal are
  change-gated. The apply is intentionally unconditional and that is load-bearing: it is the
  reason `Load()` of a value equal to the field default still reaches `AudioServer` /
  `DisplayServer`. A later reader "optimising" the apply behind the `changed` flag would
  reintroduce a silent mismatch between the stored volume and the master bus.
  **Fix:** one clause in each summary — applies always, emits only on a change — and the same
  correction to the *Scene & signal contract* row in this plan, so code and plan agree.

#### Tests
- [x] Acceptance criterion 8 is only half covered — the hotkey path into an **open** settings
  screen is untested. `SettingsMenu.OnFullscreenChanged` / `OnMasterVolumeChanged`
  (`scripts/ui/SettingsMenu.cs:160-167`) are the reason the checkbox and F11 can never disagree,
  and nothing exercises them. Add to `tests/smoke/ui_menu.gd`, with the settings screen open:
  call `GameSettings.ToggleFullscreen()`, assert `FullscreenCheck.button_pressed` followed, and
  count `FullscreenChanged` around it to prove the widget update does not emit again.
- [x] Acceptance criterion 9's widget path is untested — moving the slider itself. Add to
  `tests/smoke/ui_menu.gd`: drive `VolumeSlider` to 0.5, assert
  `GameSettings.MasterVolume == 0.5 ± 0.001`, `VolumeValue.text == "50 %"`, and at 0 that
  `AudioServer.is_bus_mute(0)` is true — then restore. `ConfigPath` is already redirected there.
- [x] Acceptance criterion 5 says `interact`/`attack` presses; `tests/smoke/ui_pause.gd` taps
  only `interact` at the paused cutscene. Add `attack` to that loop — it is the second half of
  the same `if` in `Cutscene._PhysicsProcess`.

#### Nits
- `LevelBase.GoToMainMenu` leaves `GameState.CurrentScenePath` pointing at the abandoned level —
  `scripts/levels/LevelBase.cs:113`. Harmless today (`Main._Ready` overwrites it on «Нова гра»),
  but T-B05's «Продовжити» would offer to resume a run the player just quit. One line now, or a
  note for T-09.
- `GameSettings.Save()` runs on every `toggle_fullscreen` press —
  `scripts/core/GameSettings.cs:126` — one small disk write per F11 tap.
- `[Export] public Texture2D GlowTexture { get; set; } = null!;` — `scripts/ui/MainMenu.cs:62` —
  `null!` on an exported *resource*, not a node ref. Safe (a null texture just draws nothing) but
  slightly outside the CLAUDE.md wording; `Texture2D?` would be honest.
- `LevelBase.RestartLevel` calls `GetTree()` twice — `scripts/levels/LevelBase.cs:81,84`.

#### What's done well
- The pause invariant is real, not aspirational: `RestartLevel`, `GoToLevel` and `GoToMainMenu`
  all lift `Paused` and the hit-stop, `PauseMenu.Open()` cancels the freeze **before** pausing,
  and `PauseMenu._ExitTree` unpauses a menu freed while open. `ui_pause.gd` proves each one,
  including `Engine.time_scale` forced to 0 before `Open()`.
- The headless `DisplayServer.GetName()` guard keeps the property observable while never touching
  a window, so the smoke scripts assert behaviour instead of skipping it.
- Both new UI smoke scripts redirect `GameSettings.ConfigPath` to a throwaway file **and** assert
  the player's real `user://settings.cfg` was not touched — risk 4 closed with a check, not a
  promise.
- The `HudTheme.tres` edit is verifiably additive (the diff removes exactly the `load_steps`
  line), which is what keeps `ui_hud.gd`'s stylebox identity assertions green.
- Event-driven throughout: no `_Process`/`_PhysicsProcess` in any of the three new scripts,
  cached `StringName`s for the actions, and the volume label rebuilt only when the whole percent
  changes.

#### Verdict
Ship: yes — no blockers; the three should-fixes are cheap and none of them changes behaviour that
is already proven green. First: (1) S2 — the TASKS.md status, done-note and the T-B03…T-B05
backlog entries; (2) S1 — an explicit layer for the pause overlay so it does not depend on
sibling order; (3) S3 plus the three test gaps around the settings widgets.
