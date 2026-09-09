---
name: project-settings
description: Procedure for any change to project.godot (InputMap, autoloads, physics layer names, display/rendering), BlackoutLastGrid.csproj or the .sln — classify, justify against the task, edit in the documented format, verify headless, document in the commit body.
---

You are acting as the **project-settings gatekeeper** for BLACKOUT: Last Grid (Godot 4.7 .NET,
C# 12). `CLAUDE.md` forbids touching `project.godot`, InputMap or `.csproj` without describing
the change in the commit; this skill is how that description is earned. `/task`, `/coder` and
`/scene-design` route every such change through here.

## Your job in this invocation

1. **Classify** the requested change:
   - **additive** — a new InputMap action, a new autoload, a new layer name, a new `[Export]`-
     driven setting; nothing existing changes meaning.
   - **behavior-changing** — a new key bound to an existing action, a changed deadzone, a
     changed window size/stretch mode, a changed default texture filter, a `.csproj` property.
   - **breaking** — renaming or removing an action/autoload/layer, changing `run/main_scene`,
     changing `TargetFramework`/`LangVersion`/`Nullable`, touching `config/features`.
   Breaking changes stop here unless the task block in `docs/TASKS.md` names them explicitly.
2. **Justify** against the task: quote the bullet in `docs/TASKS.md` (or the plan's File-level
   change list) that requires it. "Nice to have" is not a justification — write it to backlog.
3. **Edit by hand** in the serialized format Godot itself writes (shapes below). Keep sections
   alphabetical as they already are (`[application]`, `[autoload]`, `[display]`, `[dotnet]`,
   `[input]`, `[layer_names]`, `[rendering]`), one blank line between sections, keys in the
   order Godot emits them. Do not open the editor to make the change — an editor save rewrites
   the whole file and buries the diff.
4. **Verify**:
   ```
   godot --headless --path . --quit
   ```
   must pass by `/verify`'s headless-load rules (a malformed `Object(...)` prints
   `ERROR: Parse error` and silently drops the action). Then add or extend a smoke script that
   asserts the new setting
   exists — `InputMap.has_action("dash")`, `root.has_node("AudioBus")`,
   `ProjectSettings.get_setting("layer_names/2d_physics/layer_2") == "Player"` — and run
   `powershell -ExecutionPolicy Bypass -File tools/smoke.ps1`. Finish with `dotnet build` if `.csproj` changed.
5. **Update every caller** for behavior-changing or breaking edits: grep the action or autoload
   name as a string across `scripts/` and `tests/` (`"move_left"`, `"GameState"`) and fix each.
6. **Write the commit-body paragraph** (mandatory, verbatim shape):
   ```
   project.godot: added InputMap action "dash" (Shift / RB) because T-02b bullet 3 requires a dodge input.
   ```
   One line per changed setting, prefixed with the file name (`project.godot:`,
   `BlackoutLastGrid.csproj:`). `/task` pastes it into the commit body as is.

## Serialized shapes (copy, then change only the marked values)

InputMap action with a keyboard key, a gamepad button and a stick axis (`deadzone` is the
action-level threshold; `physical_keycode` is the `Key` enum value — letters are their ASCII
uppercase code, `A`=65 … `Z`=90, Space=32, arrows Left/Up/Right/Down = 4194319/4194320/
4194321/4194322; `unicode` is the lowercase character code for printable keys and `0` otherwise):
```
dash={
"deadzone": 0.2,
"events": [Object(InputEventKey,"resource_local_to_scene":false,"resource_name":"","device":-1,"window_id":0,"alt_pressed":false,"shift_pressed":false,"ctrl_pressed":false,"meta_pressed":false,"pressed":false,"keycode":0,"physical_keycode":81,"key_label":0,"unicode":113,"location":0,"echo":false,"script":null), Object(InputEventJoypadButton,"resource_local_to_scene":false,"resource_name":"","device":-1,"button_index":10,"pressure":0.0,"pressed":false,"script":null), Object(InputEventJoypadMotion,"resource_local_to_scene":false,"resource_name":"","device":-1,"axis":5,"axis_value":1.0,"script":null)]
}
```
`button_index` follows `JoyButton`: A=0, B=1, X=2, Y=3, LB=9, RB=10, D-pad Up=11, Down=12,
Left=13, Right=14. `axis` follows `JoyAxis`: left stick X=0 / Y=1, right stick X=2 / Y=3,
LT=4, RT=5; `axis_value` is `-1.0` or `1.0` for the direction. Every existing action keeps the
pattern keyboard + gamepad — a keyboard-only action is incomplete.

Autoload (the `*` means "singleton, add to the tree", which every autoload here uses; the name
is the node name under `root` and the C# class must be a `partial class` deriving from `Node`):
```
[autoload]

GameState="*res://scripts/core/GameState.cs"
```

Physics layer names (section is created the first time; numbering follows `/scene-design`):
```
[layer_names]

2d_physics/layer_1="World"
2d_physics/layer_2="Player"
2d_physics/layer_3="Enemy"
2d_physics/layer_4="PlayerHitbox"
2d_physics/layer_5="EnemyHitbox"
2d_physics/layer_6="Interactable"
2d_physics/layer_7="LightDark"
```

Display / rendering keys stay in their existing sections (`[display]`
`window/size/viewport_width=1920`, `[rendering]`
`textures/canvas_textures/default_texture_filter=1`); a new key is appended in place, not
moved.

`.csproj` (`Godot.NET.Sdk/4.7.2`, `net8.0`, C# 12, nullable on, `GodotEngine/**` and `.godot/**`
excluded from compilation): additive edits are a new `<PropertyGroup>` line or an
`<ItemGroup>` for `Compile Remove`; anything that adds a `<PackageReference>` is a NuGet
dependency and is forbidden here. The `.sln` is never edited by an agent.

## Forbidden

- New addons (`addons/`, `[editor_plugins]`), plugins or NuGet packages — including GdUnit4 —
  without the author's explicit approval in this conversation.
- Changing `config/features` (`"4.7", "C#", "Forward Plus"`); the engine version and renderer
  are the author's decision.
- Renaming or removing an existing action, autoload or layer name without updating every caller
  found by grepping the quoted string across `scripts/` and `tests/`, and without a smoke check
  for the new name.
- Changing `run/main_scene` for convenience during a task; run another scene with
  `godot --headless --path . res://scenes/levels/TestRoom.tscn --quit` or F6 instead.
- Editing `project.godot` through the editor UI as part of an agent run.

## Constraints specific to this repo

- The ten canonical actions (`move_left/right/up/down`, `jump`, `attack`, `heavy_attack`,
  `special`, `interact`, `flashlight`) are the InputMap; a task that seems to need an eleventh
  action must cite the task bullet, otherwise it is a backlog entry.
- Layer names must match the `/scene-design` table exactly; scenes reference layers by number,
  so a renamed layer silently changes meaning for every `.tscn`.
- An autoload is only ever `GameState`-shaped global state; per-scene managers live in the scene.
- Never commit `.godot/`, `export_presets.cfg` or anything under `GodotEngine/`.

## What "good" looks like

- The diff of `project.godot` is a few lines in one section, formatted exactly like its
  neighbours; a second agent could paste it back from the commit body alone.
- A smoke script proves the setting exists, and the headless run is clean.
- The commit body says what changed and which task bullet demanded it.

## Output format

End with:
```
Change: <additive | behavior-changing | breaking> — <file>: <what>
Justified by: <docs/TASKS.md T-xx bullet n | plan File-level change list item | NOT JUSTIFIED — sent to backlog>
Edited: <file(s) and section(s)>
Callers updated: <list | none needed>
Verify: headless <passed | failed — line> ; smoke <tests/smoke/<name>.gd → PASS|FAIL> ; build <passed | n/a>
Commit body line(s):
project.godot: added … because …
```
