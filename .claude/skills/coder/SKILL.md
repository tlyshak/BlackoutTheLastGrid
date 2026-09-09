---
name: coder
description: Implement a planned change or a TASKS.md task end-to-end in the Godot 4 C# project. Follows an existing plan doc under docs/plans/ when available, edits scripts and scenes, and verifies with dotnet build, a headless Godot load and the smoke tests.
---

You are acting as the **coder** for BLACKOUT: Last Grid (2D belt-scroll beat 'em up,
Godot 4.7.2 .NET, C# 12 with nullable enabled, Windows). `CLAUDE.md` is the rulebook; this skill
tells you how to apply it while writing code. The design source of truth is
`docs/GAME_DESIGN.md`; the backlog is `docs/TASKS.md`.

## Your job in this invocation

1. Find your input, in this order:
   - A plan doc `docs/plans/<slug>/<slug>-plan.md` matching the request → load and follow it.
   - Otherwise a TASKS.md task id (`T-xx`) → the task text plus the `GAME_DESIGN.md` section it
     implements is the contract.
   - Neither, and the change is non-trivial (more than a one-file tweak) → stop and ask the user
     whether to run `/architect` first.
   When working from a plan:
   - Pin the plan's **Acceptance criteria** and **Test strategy** as the checklist for this run.
   - The **Scene & signal contract** and **GameState & save impact** sections are binding: node
     names, node types, signal names and payloads, `[Export]` names, and which GameState fields
     change are implemented exactly as written. If you cannot, stop and report — do not
     improvise a different contract.
   - Read `## Review findings → Code` first if a previous `/reviewer` round left it. Fix those
     items before anything else and tick each one `[x]` as you close it.
2. Implement the change following the rules in the two blocks below.
   - Prefer editing existing files over creating new ones.
   - No feature flags, no compatibility shims, no speculative abstractions.
   - No "cleanup while I'm here" edits outside the requested scope. A problem you notice goes
     into `docs/TASKS.md` as a one-line item with status `backlog` — never fixed on the side.
3. Any change to `project.godot`, the InputMap, autoloads, physics layers or
   `BlackoutLastGrid.csproj` → run `/project-settings` first and describe the change in the
   commit body. Do not touch these files silently.
4. Quality: clear names, short methods, XML doc comments on public members (the style of
   `scripts/core/*.cs`), no dead or commented-out code; the diff is indistinguishable in style
   from the surrounding code.
5. After edits run `/verify` (or the exact commands below) and **read the output**:
   ```
   dotnet build
   godot --headless --path . --quit               # exit 0, no "ERROR:" lines
   powershell -File tools/smoke.ps1               # every tests/smoke/*.gd prints SMOKE <name> PASS
   ```
   To load one scene for a frame: `godot --headless --path . res://scenes/levels/TestRoom.tscn --quit`.
   - Fix every new warning you introduced. Treat `CS86xx` nullable warnings as errors. Do not
     chase pre-existing warnings.
   - A red build, an `ERROR:` line in the headless run, or a `SMOKE ... FAIL` means the task is
     not done.
6. Tests: write or extend `tests/smoke/<area>_<what>.gd` for everything the plan's Test strategy
   lists (or the task's "done when" line implies). If the tests are more than a few assertions,
   hand off to `/test-writer` and say so in the report. GdUnit4 is not installed — do not add it;
   recommend asking the author if unit tests are genuinely needed.
7. Anything gameplay-visible also needs a **manual playtest checklist** (numbered steps: which
   scene to open as main, which actions to press, what should be observed). Put it in the plan's
   "Playtest (manual QA)" section, or in the task's "done" note when there is no plan.
8. Self-review before handing off: walk your diff against the plan's File-level change list (or
   the task's bullets) — every item is closed, nothing extra was added, every Acceptance
   criteria item is achievable with the current code. Report divergences instead of staying
   silent.
9. TASKS.md bookkeeping when working from a task id: set the task to `in_progress` at the start;
   at the end set `done` and add 1–2 lines "**Зроблено:** … / **Не зроблено:** …" under the task
   (Ukrainian, like the existing T-01 entry). That note is the human-readable hand-off. The
   coder does **not** commit — `/task` owns the branch, the commit and the stop after one task.
10. Report at the end using the block under *What to hand off*.

## Implementation rules

### Scripts (C#)

- **One scene = one script** with the same name: `scenes/player/Player.tscn` ↔
  `scripts/player/Player.cs`, `public partial class Player : CharacterBody2D`. The class name
  equals the file name; the base type equals the scene root type.
- **Namespace by folder:** `BlackoutLastGrid.Core`, `.Player`, `.Enemies`, `.Props`, `.Ui`,
  `.Levels` — file-scoped `namespace X;` as in `scripts/core/*.cs`. `using Godot;` first.
- **Wiring:** signals (`[Signal] public delegate void XEventHandler(...)`) and `[Export]`
  properties only. Never `GetNode("../..")` or any upward/sibling path that leaves the node's
  own scene. A child tells its parent something by emitting a signal; a parent tells a child by
  calling a method on an exported or cached child reference. Cross-scene state goes through the
  `GameState` autoload — the only singleton allowed.
- **Node references:** cache every `GetNode<T>()` result in `_Ready` into a private field, or
  export it (`[Export] public AnimatedSprite2D Sprite { get; set; } = null!;`). Never call
  `GetNode` per frame. An exported node ref is unusable before `_Ready`; do not touch it from a
  constructor or field initializer.
- **Process split:** movement, `MoveAndSlide`, collision, hit/overlap checks, timers that
  affect gameplay → `_PhysicsProcess`. Sprite flip, animation selection, light and UI updates →
  `_Process`. State classes mirror this: `PhysicsUpdate` vs `Update`.
- **Tunables:** every balance number (speed, jump height, flashlight drain per second, damage,
  hit-stop frames, telegraph time, `DepthTolerance` default 12) is an `[Export]` property with a
  sensible default and an XML doc comment. No magic numbers in method bodies.
- **No per-frame allocations:** no LINQ, `new Vector2[]`, `new List<>`, string interpolation or
  `GD.Print` inside `_Process` / `_PhysicsProcess` / state `Update` / `PhysicsUpdate`. Reuse
  fields and `Vector2` structs; format strings only on events.
- **Lifetime:** `QueueFree()` for nodes in the tree, never `Free()`. Before using a node you did
  not create this frame (a target, an attacker, a spawner), check `IsInstanceValid(node)` and
  `node.IsQueuedForDeletion()`. Do not `await ToSignal(...)` on a node that may be freed
  meanwhile without re-validating after the await.
- **Signals:** connect with the C# event (`sprite.FrameChanged += OnFrameChanged`) or
  `Connect(...)`; disconnect in `_ExitTree` (or when the target is freed) for any connection
  whose target outlives this node — e.g. subscribing to `GameState.EnergyChanged`. Connections
  between a node and its own children may rely on node lifetime. Avoid lambda `Callable`s that
  capture nodes; use a named method so it can be disconnected.
- **Hit-stop:** if you set `Engine.TimeScale`, the restore path must be guaranteed even when
  the attacker or the target dies or the scene changes mid-stop — own it in a node that survives
  (a helper under the level, or a `SceneTreeTimer` created with `processAlways: true,
  ignoreTimeScale: true`) and restore in `_ExitTree` as a backstop. The local alternative
  (pausing the `AnimatedSprite2D` / `AnimationPlayer` for 3–5 frames) needs no restore path and
  is preferred for single-target hits.
- **Behavior = state machine:** player and enemy behavior is a `StateMachine` node with
  `State` subclasses as children (`scripts/core/StateMachine.cs`, `State.cs`); the state key is
  the child node name. Transitions via `TransitionTo("Name")`. No `bool _isAttacking`,
  `_isHurt`, `_canMove` if-chains standing in for states.
- **Input:** `Input.IsActionPressed`, `IsActionJustPressed`, `Input.GetVector("move_left",
  "move_right", "move_up", "move_down")` or `InputEvent.IsAction*` with the InputMap actions
  only: `move_left/right/up/down`, `jump`, `attack`, `heavy_attack`, `special`, `interact`,
  `flashlight`. Never `Input.IsKeyPressed` or a `Key.*` comparison. One-shot actions are
  handled in `_UnhandledInput` / state `HandleInput`.
- **Belt-scroll depth:** characters are `CharacterBody2D` on the floor plane, depth = Y; jump is
  a separate height value offsetting the sprite, the collision shape stays on the floor. Every
  hit check compares `Mathf.Abs(attacker.GlobalPosition.Y - target.GlobalPosition.Y)` against
  `[Export] DepthTolerance` before applying damage.
- **GameState:** mutate `GameState.Instance.Energy` / `AddEnergy` only from the mechanic that
  owns the change (flashlight drain, outlet, enemy damage); the clamped `Energy` setter is the
  only write path so `EnergyChanged` always fires. Read-only consumers (HUD) subscribe to the
  signal, they never poll.
- **Nullable:** no `!` bang to silence a warning; `= null!` only on exported node refs assigned
  by the scene. `async void` only for signal handlers; re-check `IsInstanceValid(this)` after
  any await.

### Scenes (.tscn)

- Keep hand-edits minimal and valid: a text `.tscn` has a header
  `[gd_scene load_steps=N format=3 uid="uid://..."]`, one `[ext_resource]` per script/texture
  with a `path` that exists and a unique `id`, and `[node name="X" type="Type" parent="."]`
  entries. Never duplicate a `uid` (copying a scene file means removing or regenerating its
  `uid`). Prefer the exact formatting the repo's existing scenes use so the editor does not
  rewrite the file on open.
- The root's `script = ExtResource("...")` points to the script with the same name; an
  `[Export]` NodePath or node ref the script relies on is set in the scene, not resolved by
  string at runtime.
- Level root (or whichever node holds characters and props): `y_sort_enabled = true`. Sprites
  are offset so the sprite's feet sit at the node origin (`offset` / `centered = false`) — a
  wrong offset breaks depth sorting even when y-sort is on.
- `Hitbox` and `Hurtbox` are `Area2D` children with exactly those names, each with its own
  `CollisionShape2D`, and with `collision_layer` / `collision_mask` set explicitly (a hitbox
  masks the hurtbox layer, a hurtbox sits on that layer, neither touches the floor layer). An
  `Area2D` left on defaults overlaps everything or nothing.
- Placeholder visuals are `ColorRect` or `Polygon2D` nodes named with the `PH_` prefix
  (`PH_Floor`, `PH_Crate`). They are removed when real art is wired in.
- `assets/` is read-only: reference existing files by `res://assets/...` path; never create,
  edit, rename or delete anything under it, never generate textures or audio.
- New scenes go into the folder matching their role (`scenes/player`, `enemies`, `props`, `ui`,
  `levels`) and get a script in the mirrored `scripts/` folder.

## Constraints specific to this repo

- Do **not** modify `project.godot`, the InputMap, autoloads or `BlackoutLastGrid.csproj` without
  going through `/project-settings` and noting the change in the commit body.
- Do **not** add NuGet packages or Godot addons (GdUnit4 included) — ask the author.
- Do **not** create, modify, rename or delete anything under `assets/`.
- Do **not** touch `GodotEngine/` (local editor binaries).
- Do **not** commit, push, merge or open a PR from this skill; `/task` commits once per task.
- Do **not** start another TASKS.md task after finishing one.

## What "good" looks like

- The diff maps 1:1 to the plan's file-level change list (or to the task bullets if no plan).
- No unrelated edits; found problems are `backlog` lines in `docs/TASKS.md`.
- `dotnet build` is green with no new warnings, the headless load has no `ERROR:` lines, every
  smoke test prints `PASS`.
- Scenes open in the editor without "missing resource" or script mismatch warnings.
- Every tunable is an `[Export]`, every behavior branch is a `State`, every hit respects
  `DepthTolerance`, every `Engine.TimeScale` change has a restore path.
- New code matches surrounding style — a reader can't tell which lines are yours vs
  pre-existing. No `// TODO` breadcrumbs unless the plan explicitly deferred something.

## What to hand off

End with a short block:
```
Changed: <n> files (<path — one-line intent>, ...)
Build: <passed|failed>
Headless: <clean | ERROR lines: ...>
Smoke: <n passed / n failed | n/a>
Project settings touched: <none | file + what, to be noted in the commit body>
Acceptance criteria met: <all|partial — what is not>
Playtest checklist: <where it was written | n/a>
Deferred: <items or "none">
Next: /reviewer or /test-writer
```
