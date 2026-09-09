# Plan — t02b-basic-combat (T-02b · Базовий бій)

## Goal
Make hitting things feel right before any real enemy exists: a three-hit light combo and a heavy
attack on the hero, animation-driven hitbox windows, hit-stop, knockback/knockdown, a hurt flash,
and a training dummy with HP to receive it all in `TestRoom`. This is `GAME_DESIGN.md` §7 item 1a.

## Scope
- In: `Hitbox`/`HitInfo`/`IHittable`/`HitStop` in `scripts/core`; player states LightAttack1-3,
  HeavyAttack, Hurt, KO; `AnimationPlayer` on `Player` with method tracks that open/close the
  hitbox; `scenes/enemies/Dummy.tscn` + `scripts/enemies/Dummy.cs` (+ states); two dummies in
  `TestRoom` at different depths; smoke `tests/smoke/combat_dummy.gd`.
- Out: enemy AI/attacks (T-06), energy refund on hits (special, later), throws/juggles, real art
  and a real flash shader (placeholder = `Modulate` flash), jump attacks.

## Design-doc conformance
§4: light/heavy attack, 3–4 hit combo, hit-stop 3–5 frames, flash on the enemy. §6: hit-stop 3–5
frames. Task says "спалах шейдером (плейсхолдер — модуляція кольору)" → `Modulate` tween.
Hero damage → energy is T-06's rule, but `Player.TakeHit` already routes damage through
`GameState.Energy` so T-06 only adds enemies and the restart. No disagreements.

## Options considered
1. **Hitbox windows from `AnimationPlayer` method tracks** (chosen, as the task asks): attack
   animations exist even without art (they move a `PH_Fist` polygon) and the designer swaps in
   sprite frames later without touching code.
2. Timers inside the attack states: simpler, but the active window would drift from the future
   sprite animation. Rejected.
3. Hit-stop via pausing only the two animation players: local and safe, but the task and the
   design doc describe a global freeze; `Engine.TimeScale = 0` is used. The restore lives in a
   `HitStop` node that creates itself under the scene-tree root (`ProcessMode = Always`) and
   restores the time scale from its own `_Process` using the wall clock — a `SceneTreeTimer`
   with a C# `Timeout` subscription was tried first and its callback never fired once the timer
   object went out of scope, so the restore must not depend on a temporary object.

## GameState & save impact
`Player.TakeHit` calls `GameState.AddEnergy(-Damage)`; KO when `Energy <= MinEnergy`. Nothing new
to persist.

## Scene & signal contract
`Player.tscn` additions:
```
Player
├── Visual
│   ├── PH_Fist (Polygon2D)           animated by the attack animations
│   └── Hitbox (Hitbox.cs, Area2D)    layer 4 / mask 3, Monitoring on, gated by Activate/Deactivate
│       └── CollisionShape2D (RectangleShape2D 36×40 at (30, 0))
├── AnimationPlayer                   light_1 (0.30 s), light_2 (0.30), light_3 (0.40), heavy (0.55),
│                                     hurt (0.30), ko (0.60); method tracks call Player.HitboxOn/HitboxOff
└── StateMachine
    ├── LightAttack1/2/3, HeavyAttack (PlayerAttack.cs)  exports below
    ├── Hurt (PlayerHurt.cs)
    └── KO (PlayerKO.cs)
```
`PlayerAttack` exports: `AnimationName` (StringName), `Damage` (hp), `Knockback` (px/s),
`Knockdown` (bool), `HitStopFrames` (frames), `NextCombo` (state name or ""), `ComboWindowStart`
(s from the start of the animation after which `attack` is buffered).
Defaults: L1 5/60/false/4/"LightAttack2"/0.10; L2 5/60/false/4/"LightAttack3"/0.10;
L3 8/160/false/5/""/0; Heavy 12/200/true/6/""/0.
Player API: `AttackPressed`, `HeavyPressed`, `HitboxOn()`/`HitboxOff()` (animation method
tracks), `PlayAnimation` (now via `AnimationPlayer` when the animation exists there),
`IsAnimationPlaying(name)`, `CurrentAttack` (set by the attack state), `TakeHit(HitInfo)`,
`Hurt(float damage)` and `KnockedOut()` signals, `HurtKnockbackFriction` export.

`Dummy.tscn` (`scripts/enemies/Dummy.cs : CharacterBody2D, IHittable`, layer 3 / mask 1):
```
Dummy
├── PH_Shadow (Polygon2D)
├── Visual (Node2D at (0, -36))  PH_Body (Polygon2D 36×72, grey), PH_Face
├── CollisionShape2D (flat capsule)
├── Hurtbox (Area2D, layer 3 / mask 0, monitorable)  CollisionShape2D 32×64 at (0, -36)
├── HpLabel (Label above the head, "HP 30")
└── StateMachine: Idle, Hurt, Down, KO (DummyState.cs base)
```
Exports: `MaxHp` 30, `KnockbackFriction` 900 px/s², `HurtDuration` 0.25 s, `DownDuration` 1.0 s,
`FlashColor`, `FlashDuration` 0.12 s, `SpriteFeetOffset` 36. Signals: `Damaged(float hp)`,
`KnockedOut()`. `TakeHit`: ignored in KO; sets `Velocity.X = Knockback`, flashes, HP -= Damage;
HP <= 0 → KO, `Knockdown` → Down, else Hurt. Hurt/Down decay the velocity with the friction and
return to Idle. Down rotates `Visual` by 90°; KO stays down and dims.

`TestRoom`: `Dummy` at (640, 450) (same depth as the hero) and `Dummy2` at (760, 470)
(20 px deeper → out of DepthTolerance 12 until the hero moves down).

Collision: `Player/Visual/Hitbox` layer 4 mask 3; `Dummy/Hurtbox` layer 3 mask 0; `Dummy` body
layer 3 mask 1.

## File-level change list
- scripts/core: `HitInfo.cs`, `IHittable.cs`, `Hitbox.cs`, `HitStop.cs` (new)
- scripts/player: `Player.cs` (edit), `PlayerState.cs` (edit: names), `PlayerIdle.cs`/`PlayerMove.cs`
  (edit: attack transitions), `PlayerAttack.cs`, `PlayerHurt.cs`, `PlayerKO.cs` (new)
- scripts/enemies: `Dummy.cs`, `DummyState.cs`, `DummyIdle.cs`, `DummyHurt.cs`, `DummyDown.cs`,
  `DummyKO.cs` (new)
- scenes: `Player.tscn` (edit: fist, hitbox, AnimationPlayer, states), `Dummy.tscn` (new),
  `TestRoom.tscn` (edit: two dummies)
- tests/smoke: `combat_dummy.gd` (new)
- docs: this plan, TASKS.md note. project.godot: no change.

## Acceptance criteria
- Given the hero next to the dummy at the same depth, pressing `attack` three times inside the
  combo windows runs LightAttack1 → 2 → 3 (state names observed in order) and the dummy's HP drops
  by 5+5+8; pressing `attack` once only runs LightAttack1 then returns to Idle.
- Given `heavy_attack`, the dummy enters `Down` (Visual rotated), HP −12, is pushed right, and
  gets up to Idle after `DownDuration`.
- Given a hit, `Engine.TimeScale` is 0 for the attack's `HitStopFrames` and is back to 1 within
  `HitStopFrames / physics_ticks + 0.05 s` of wall time; the dummy's `Modulate` changes and
  returns to white.
- Given `Dummy2` 20 px deeper, the same attack does not hit it (HP unchanged); after the hero
  moves down 20 px it does.
- Given the dummy at 0 HP, it is in `KO`, further hits are ignored (TakeHit returns false).
- Given `Player.TakeHit(HitInfo{Damage 10})`, the hero enters Hurt, `GameState.Energy` drops by
  10 and it returns to Idle; with `Damage` ≥ current energy it enters KO and stays.
- Build, headless TestRoom load, smoke green.

## Test strategy
Smoke `tests/smoke/combat_dummy.gd` (async): instantiate `TestRoom`, place the hero at
(600, 450) facing right with the dummy at (640, 450); drive `attack`/`heavy_attack` with
`Input.action_press` for one physics frame; observe `CurrentStateName` per frame, `Dummy.Hp`,
`Engine.time_scale`, `Modulate`. Hit-stop freezes physics frames, so the test waits with
`create_timer(t, true, false, true)` (ignores time scale) where needed. Depth test with `Dummy2`.
Hero Hurt/KO via direct `TakeHit` calls. Only by hand: "feel" of hit-stop and the fist motion.

## Playtest (manual QA)
1. Відкрити `scenes/levels/TestRoom.tscn` (F6). Два сірих манекени з написом `HP 30`, один на
   рівні героя, другий трохи нижче.
2. Підійти до першого і натиснути J тричі: кулак вилітає тричі, HP 30 → 25 → 20 → 12, на кожному
   попаданні гра завмирає на мить, манекен спалахує білим і відлітає трохи праворуч.
3. Натиснути K: важкий удар, манекен падає (лежить боком) на ~1 с, HP −12, потім встає.
4. Стояти на рівні першого манекена і бити в бік другого: другий не отримує шкоди, доки герой не
   спуститься до його лінії (W/S).
5. Добити манекен до 0: він лишається лежати темнішим, удари по ньому більше нічого не роблять.
6. Натиснути J один раз і не натискати більше: після першого удару герой повертається в Idle.

## Review focus
`hitbox/hurtbox`, `hit-stop/timescale`, `state machine`, `belt-scroll depth`, `scene/tscn integrity`.

## Performance & frame budget
Hitbox stays monitoring (one Area2D per actor); `GetOverlappingAreas()` allocates a Godot array
only on activation (a few times per second at most). Flash uses one Tween per hit.

## Risks
`Engine.TimeScale = 0` stops physics frames; anything awaiting `physics_frame` during a hit-stop
waits it out (fine in game, handled in tests). Hand-written `AnimationPlayer` tracks must keep
method names in sync with `Player` (`HitboxOn`/`HitboxOff`) — the smoke test would catch a rename.

## Open questions
None.

## Review findings
_filled in by /reviewer_
