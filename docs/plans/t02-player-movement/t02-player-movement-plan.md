# Plan — t02-player-movement (T-02 · Персонаж: belt-scroll рух і анімація)

## Goal
Give the game a controllable hero: a `Player` scene that walks in 8 directions on the belt-scroll
floor plane, jumps with a separate height axis (`_z`) while its shadow stays on the floor, flips
its sprite, and sorts by depth (Y) against props in a `TestRoom` level. This is MVP priority 1 in
`../../GAME_DESIGN.md` §7 and the base every later combat/enemy task builds on.

## Scope
- In: `scenes/player/Player.tscn` + `scripts/player/Player.cs`; player states Idle / Move / Jump
  on the shared `StateMachine`; `scenes/levels/TestRoom.tscn` + `scripts/levels/TestRoom.cs` with a
  floor and two `PH_` props at different Y; `[layer_names]` for the 2D physics layers in
  `project.godot`; smoke test `tests/smoke/player_movement.gd`; playtest checklist.
- Out: attacks, Hitbox, hurt/KO (T-02b), flashlight (T-03), HUD (T-04), real art (no files under
  `assets/art/player/` exist — see Design-doc conformance).

## Design-doc conformance
`GAME_DESIGN.md` §4 (belt-scroll: 8 directions, Y = depth, Y-sort) and §7 item 1 ("walk/idle sprite
sheet via `AnimatedSprite2D`; Y-sort"). The task text says to wire the walk sprite sheet from
`assets/art/player/`; that folder holds only `.gitkeep`. Per `CLAUDE.md` art is never created by
the agent, so the visual is a `PH_` placeholder and the `AnimatedSprite2D` slot is left empty but
wired: assigning a `SpriteFrames` with `idle`/`walk` animations in the inspector is all that is
needed later. No disagreement with the design doc otherwise.

## Options considered
1. **Gravity-less jump as a fake Z axis on the visual** (chosen): the body stays on the floor
   plane, `_z`/`_zVelocity` are plain floats integrated in `_PhysicsProcess`, `Visual.Position.Y =
   -(SpriteFeetOffset + _z)`. Depth sorting and floor clamping keep working during the jump.
2. Godot gravity on the `CharacterBody2D` with a rotated up direction: fights the belt-scroll
   model (Y is depth, not height) and breaks Y-sort mid-jump. Rejected.
3. Floor bounds as a `StaticBody2D` box: works for X walls (used for left/right) but top/bottom
   need soft clamping so the shadow never crosses the horizon line; exports are simpler for the
   test room, a level `Area2D` zone can replace them later (T-08).

## Recommended approach
Option 1 with exports for floor top/bottom on the player (test-room default), X walls in the room.
States are `State` children of a `StateMachine` node; they poll input in `PhysicsUpdate` via
`Input.GetVector(move_left, move_right, move_up, move_down)` and `Input.IsActionJustPressed("jump")`
so headless smoke tests can drive them with `Input.action_press`.

## GameState & save impact
No GameState change. Nothing to persist in T-09 from this task.

## Scene & signal contract
```
Player (CharacterBody2D, motion_mode = Floating)  → scripts/player/Player.cs   layer 2 / mask 1
├── PH_Shadow (Polygon2D, dark ellipse)            stays at (0,0) on the floor
├── Visual (Node2D)                                position (0, -SpriteFeetOffset - _z); Scale.X = ±1
│   ├── PH_Body (Polygon2D, 36×72 rectangle, orange) hidden automatically when Sprite has frames
│   └── Sprite (AnimatedSprite2D, no SpriteFrames yet) plays "walk"/"idle" if such animations exist
├── CollisionShape2D (CapsuleShape2D 28×14, rotated flat)  footprint on the floor
├── Hurtbox (Area2D, layer 2 / mask none, monitoring off)  present for T-02b, no logic
│   └── CollisionShape2D (RectangleShape2D 32×64, centred at -SpriteFeetOffset)
└── StateMachine (Node, StateMachine.cs)  InitialState = Idle
    ├── Idle (PlayerIdle.cs)
    ├── Move (PlayerMove.cs)
    └── Jump (PlayerJump.cs)
```
`PlayerState : State` (abstract) resolves `Player` from `Machine.GetParent<Player>()` in `_Ready`.

Exports on `Player`:
| Name | Type | Default | Unit | Why |
|---|---|---|---|---|
| MoveSpeed | float | 220 | px/s | walk speed on the floor plane |
| DepthSpeedFactor | float | 0.75 | × | vertical (depth) speed relative to horizontal, SoR-style |
| FloorTop | float | 300 | px | min Y of the feet (test room default) |
| FloorBottom | float | 600 | px | max Y of the feet |
| JumpVelocity | float | 380 | px/s | initial `_zVelocity` |
| Gravity | float | 900 | px/s² | pulls `_z` back to 0 |
| SpriteFeetOffset | float | 36 | px | distance from origin (feet) to the visual's pivot |
| DepthTolerance | float | 12 | px | reserved for hit checks (T-02b) |

Public API used by states/tests (no signals needed in T-02):
`Vector2 MoveInput` (read each physics step), `bool JumpPressed`, `float Height` (=`_z`),
`bool IsAirborne`, `void ApplyFloorMove(Vector2 input, double delta)`, `void StartJump()`,
`void IntegrateJump(double delta)` (returns to ground → `IsAirborne == false`),
`string CurrentStateName` (for the room's debug label). `Facing` (`int`, ±1).

Transitions: `Idle → Move` when input ≠ 0; `Move → Idle` when input = 0; `Idle|Move → Jump` on
`jump` just pressed; `Jump → Idle|Move` when `IsAirborne` becomes false.

Collision (recorded in `project.godot` `[layer_names]` this task, via `/project-settings`):
| Node | Layer | Mask | Why |
|---|---|---|---|
| Player | 2 Player | 1 World | slides along room walls only |
| Player/Hurtbox | 2 Player | — | found by enemy hitboxes later |
| TestRoom/PH_WallLeft, PH_WallRight | 1 World | — | keep the hero on screen |

TestRoom (Node2D, y_sort_enabled) → `scripts/levels/TestRoom.cs`:
`PH_Floor` (ColorRect at y = FloorTop, not sorted above anything), `Player` instance at (400, 450),
`PH_Crate` (Polygon2D, origin at its floor contact, y = 420), `PH_Post` (y = 520), two
`StaticBody2D` walls at x = 40 and x = 1880 (layer 1), `DebugLabel` (Label, top-left) showing
state and height. TestRoom owns the player; it reads only `Player.CurrentStateName`/`Height`.

## File-level change list
- scenes/: `scenes/player/Player.tscn` (new), `scenes/levels/TestRoom.tscn` (new)
- scripts/: `scripts/player/Player.cs`, `PlayerState.cs`, `PlayerIdle.cs`, `PlayerMove.cs`,
  `PlayerJump.cs` (new); `scripts/levels/TestRoom.cs` (new)
- tests/smoke/: `player_movement.gd` (new)
- docs/: this plan; `docs/TASKS.md` status + done-note (by /task)
- project.godot: `[layer_names]` 2D physics 1–7 (additive, see /project-settings) — commit body

## Acceptance criteria
- Given TestRoom, when `move_right` is held for 30 physics frames, the player's X increases by
  roughly `MoveSpeed × 0.5 s` and `Visual.Scale.X == 1`; holding `move_left` flips it to −1.
- Given the player at `FloorTop + 5`, holding `move_up` for 30 frames leaves `Position.Y ==
  FloorTop` (clamped), never above; same for `FloorBottom` with `move_down`.
- Given Idle, pressing `jump` switches the state to `Jump`, `Height` rises above 0 within 5
  frames and returns to 0 with the state back to `Idle` within 2 s; the shadow node stays at the
  root origin throughout.
- Given diagonal input (right+up), the player moves along both axes in the same frame.
- Given `PH_Crate` at y = 420 and the player at y = 450, the crate draws behind the player; at
  player y = 400 the crate draws in front (Y-sort; verified by playtest, structure checked by smoke:
  `y_sort_enabled` on the room and props with distinct Y).
- Build, headless load of `TestRoom.tscn`, and smoke run are green (`/verify`).

## Test strategy
Smoke `tests/smoke/player_movement.gd` (async template): instantiate `TestRoom.tscn`, find the
`Player`, drive `Input.action_press` and step physics frames, assert the criteria above except the
visual overlap. Also asserts InputMap actions exist and `ProjectSettings` has the layer names.
Only by hand: sprite overlap order, feel of the jump arc, wall collisions.

## Playtest (manual QA)
1. Open `scenes/levels/TestRoom.tscn` and run it (F6). Expected: dark floor band, an orange
   placeholder hero at the centre, a crate above him and a post below, a label "State: Idle  z: 0".
2. Hold D / →: hero walks right, label shows `Move`; hold A / ←: hero turns (flips) and walks left.
3. Hold W then S: hero moves up until the floor's top edge, then down until its bottom edge; he
   never leaves the floor band. Diagonals (W+D) move him diagonally.
4. Walk up past the crate (hero's feet above the crate's base): the crate now covers the hero.
   Walk down below it: the hero covers the crate. Same with the post.
5. Press Space: hero pops up (shadow stays on the floor), label shows `Jump` and z > 0, lands
   in ~0.8 s and returns to `Idle` (or `Move` if a direction is still held). Jumping while
   walking keeps the horizontal motion.
6. Walk into the left/right edge: the hero stops at the wall.

## Review focus
`state machine`, `belt-scroll depth`, `input map`, `exports/tunables`, `physics timing`,
`scene/tscn integrity`.

## Performance & frame budget
One `Input.GetVector` and one `MoveAndSlide` per physics step; no allocations per frame (input
vector is a struct, state names are cached `StringName`s). Nothing else.

## Risks
- Without art, `AnimatedSprite2D` is empty; `Player` must never call `Play` on a null
  `SpriteFrames` (guarded). When art lands, `PH_Body` is hidden automatically.
- `motion_mode = Floating` must be set or `MoveAndSlide` treats −Y as "up" and applies floor snapping.

## Open questions
None blocking. Whether floor bounds should move from `Player` exports to a level zone is deferred
to T-08.

## Review findings
_filled in by /reviewer_
