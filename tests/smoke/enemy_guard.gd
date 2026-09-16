extends SceneTree
# Smoke: the Guard enemy (T-06) — Guard.tscn wiring (script, layers, painted sprite, states, export
# defaults), Level00_Sections wiring (EnemyDirector, Camera2D limited to the starting room, the
# guard standing at the end of the drift with the hero as target, hero LightSensor + Hurtbox under
# Visual), then in a fresh level per section, with the guard moved onto the open floor of the mine
# face and the hero placed around it:
# (1) a lit hero at 250 px is noticed within 5 frames, approached and punched: Hurt(8), Energy -8,
#     hit-stop, one attack slot held while in Attack;
# (2) an unlit hero 280 px in front (> 420 * 0.5) is ignored for 120 frames, at 180 px noticed;
# (3) an unlit hero BEHIND the guard is never noticed; the first light hit from the dark deals
#     5 * 2 = 10 (Hp 20) and makes the guard aware, the second one 5 (Hp 15);
# (4) a jump started the frame Attack begins lifts the Hurtbox out of the punch — no Hurt;
# (5) T-B01: a heavy from behind floors the guard (24 dmg -> Hp 6, Down); while Down both a real
#     light hit and TakeDamage() are ignored (Hp unchanged, no hit-stop) and it gets up on its own;
# (5b) S1 regression: a knockdown on the first Attack frame keeps Visual.rotation at PI/2 through
#     two idle frames and 30 physics frames of Down (the interrupted attack's RESET must not
#     re-apply the upright pose), then the guard stands up;
# (6) Energy 5 -> one punch KOs the hero and LevelBase reloads the current scene ~1 s later with
#     Energy == MaxEnergy and Engine.time_scale == 1.
# The guard's AnimationPlayer carries looping idle/walk that never key Visual:modulate/rotation,
# RESET covers every property anything else writes, and a guard floored while walking stops
# animating for the whole DownDuration (5b) and picks its gait back up after getting up.
# Run: godot --headless --path . -s tests/smoke/enemy_guard.gd
#
# Hit-stop sets Engine.time_scale = 0, so hits are observed on idle frames (`process_frame`) under
# a wall-clock cap and the restore is awaited in real time; everything else is counted in physics
# frames. The level takes ~130 ms to instance and Godot catches up with several physics steps in
# ONE iteration afterwards, so every fresh level gets two idle frames before the first physics step.
# The hero is parked at HERO_START *before* the level enters the tree, so he never crosses
# Checkpoint_Face — a KO in section 6 must reload the level, not cost a soft respawn.

const NAME := "enemy_guard"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s). Counts _process calls;
# headless runs ~150 idle frames per second, so this is about the runner's own limit.
const MAX_FRAMES := 9000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "flashlight"]
const ROOM_PATH := "res://scenes/levels/Level00_Sections.tscn"
const HIT_CAP_MS := 800          # wall-clock cap while waiting for one hit to land
const NO_HIT_WINDOW_MS := 450    # longer than the hero's light animation (0.30 s) — a miss must stay a miss
const RESTORE_CAP_MS := 1000     # wall-clock cap while waiting for hit-stop to lift
const PUNCH_CAP_MS := 1500       # Attack -> hero Hurt: telegraph 0.30 s + hit-stop, generous
const NOTICE_CAP := 5            # physics frames allowed for Idle -> Noticed
const ATTACK_CAP := 150          # physics frames allowed for Approach -> Attack from <= 250 px (140 px/s)
const DARK_IGNORE_FRAMES := 120  # frames an unlit hero at 280 px in front must stay unnoticed
const BEHIND_IGNORE_FRAMES := 60 # frames an unlit hero behind the guard must stay unnoticed
const GETUP_CAP := 75            # frames allowed for Down -> up (DownDuration 1 s = 60)
const KO_CAP_MS := 2000          # wall-clock cap for SetAware -> Attack -> punch -> KnockedOut
const RELOAD_CAP_MS := 2500      # RestartDelay 1 s + 0.5 s (plan) + margin for the ~130 ms room load
const RELOAD_MIN_MS := 900       # the reload must not come before RestartDelay
const GUARD_START := Vector2(2400, 470)   # where the level stands the guard: end of the drift, Facing -1 (looks left)
const HERO_START := Vector2(200, 470)     # the hero's parking spot for a fresh level: clear of Checkpoint_Face (x 49..129)
const RELOADED_POS := Vector2(88.89, 480) # the hero's authored start, restored by a level reload
# The behaviour sections move the guard onto the open floor of the mine face, where there is room
# on both sides of it (walls at x 18 / 2542, the conveyor gate from x ~1638) and no checkpoint.
const GUARD_POS := Vector2(900, 470)
const LIT_POS := Vector2(650, 470)        # 250 px in front: inside the lit range (420)
const DARK_FAR := Vector2(620, 470)       # 280 px in front: outside the dark range (420 * 0.5 = 210)
const DARK_NEAR := Vector2(720, 470)      # 180 px in front: inside the dark range
const BEHIND_FAR := Vector2(1160, 470)    # 260 px behind: inside the dark range but behind -> unseen
const BEHIND_NEAR := Vector2(940, 470)    # 40 px behind: the hero's flipped hitbox reaches the guard
const KO_POS := Vector2(858, 470)         # 42 px in front: inside AttackRange from the first tick
const DOWN_HOLD_FRAMES := 30              # frames the Down pose must survive after a knockdown out of Attack (DownDuration 1 s = 60)
const DOWN_ANIM := &"down"                # the painted guard's floored frame (Guard.SetDown plays the 'down' animation)
const GAIT_ANIMS := ["walk", "idle"]      # what must never run while the guard is floored
# Geometric dodge threshold, derived from the scene shapes (and re-derived at runtime in section 4):
# the hero Hurtbox is 32x64 centred on Visual at (0, -36 - z), so it spans y -68-z .. -4-z relative
# to the feet; the guard Hitbox is 36x40 at Visual (30, 0) with Visual at (0, -36), so it spans
# y -56 .. -16. The punch misses only once the hurtbox bottom clears the hitbox top:
# -4 - z < -56  <=>  z > 52. (The plan's earlier "Height > 20" was not the real threshold.)
const MIN_DODGE_HEIGHT := 52.0

var _started := false
var _frames := 0
var _failures: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

# Time of the first key of `method` on any method track of `anim`, or -1 when it is not called.
func _method_time(anim: Animation, method: String) -> float:
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_METHOD:
			continue
		for k in anim.track_get_key_count(t):
			if String(anim.method_track_get_name(t, k)) == method:
				return anim.track_get_key_time(t, k)
	return -1.0

# Every "<node path>:<property>" a value track of `anim` writes.
func _value_paths(anim: Animation) -> Array:
	var paths: Array = []
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_VALUE:
			paths.append(String(anim.track_get_path(t)))
	return paths

func _process(_delta: float) -> bool:
	# First frame: start the coroutine (no await here). Returning false keeps the main loop
	# running so the awaits inside _run() resume; _run() itself calls quit().
	if not _started:
		_started = true
		_run()
	_frames += 1
	if _frames > MAX_FRAMES:
		print("SMOKE %s FAIL: exceeded %d frames without quit()" % [NAME, MAX_FRAMES])
		quit(1)
	return false

func _step(frames: int) -> void:
	for i in frames:
		await physics_frame

func _release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)

func _finish() -> void:
	_release_all()
	if Engine.time_scale != 1.0:
		_check(false, "Engine.time_scale=%s at the end, expected 1 (reset by the test)" % Engine.time_scale)
		Engine.time_scale = 1.0
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

# Presses `action` for exactly one physics frame.
func _tap(action: String) -> void:
	Input.action_press(action)
	await _step(1)
	Input.action_release(action)

# Watches idle frames until `pred` holds or `cap_ms` of wall time pass; records the lowest
# Engine.time_scale seen (0 = a hit-stop happened) and the elapsed ms.
func _watch_until(pred: Callable, cap_ms: int) -> Dictionary:
	var r := {"ok": false, "min_scale": Engine.time_scale, "elapsed": 0}
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < cap_ms:
		await process_frame
		r["min_scale"] = minf(r["min_scale"], Engine.time_scale)
		if pred.call():
			r["ok"] = true
			break
	r["elapsed"] = Time.get_ticks_msec() - start
	return r

# Waits (idle frames) until Engine.time_scale is back to 1. Returns elapsed ms, or -1 on cap.
func _wait_restored(cap_ms: int) -> int:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < cap_ms:
		if Engine.time_scale == 1.0:
			return Time.get_ticks_msec() - start
		await process_frame
	return -1

# Waits (physics frames) until `actor.CurrentStateName == state`. Returns the frame index
# (0 = already there) or -1 after `cap` frames.
func _wait_state(actor: Node, state: String, cap: int) -> int:
	for i in cap:
		if actor.CurrentStateName == state:
			return i
		await physics_frame
	return -1

# Waits (physics frames) until `events` is non-empty. Returns the frame index or -1 after `cap`.
func _wait_event(events: Array, cap: int) -> int:
	for i in cap:
		await physics_frame
		if not events.is_empty():
			return i + 1
	return -1

# A fresh level with the run reset, the hero parked at HERO_START (set before the level enters the
# tree, so no checkpoint is ever armed), the lamp off and the guard settled in Idle. Returns
# {room, player, guard, director, lamp, gsm} or an empty dictionary (failure already recorded).
func _open_room(scene: PackedScene, gs: Node, label: String) -> Dictionary:
	gs.ResetRun()
	_release_all()
	var room: Node = scene.instantiate()
	var hero: Node2D = room.get_node_or_null("Player")
	if hero != null:
		hero.position = HERO_START
	root.add_child(room)
	await process_frame   # consume the load catch-up iteration (see the header)
	await process_frame
	var player: Node = room.get_node_or_null("Player")
	var guard: Node = room.get_node_or_null("Guard")
	var director: Node = room.get_node_or_null("EnemyDirector")
	if player == null or guard == null or director == null or guard.get("MaxHp") == null:
		_check(false, "%s: Level00_Sections lacks Player/Guard/EnemyDirector or Guard.cs is not attached" % label)
		room.queue_free()
		return {}
	var lamp: Node = player.get_node_or_null("Flashlight")
	var gsm: Node = guard.get_node_or_null("StateMachine")
	if lamp == null or gsm == null:
		_check(false, "%s: Player/Flashlight or Guard/StateMachine missing" % label)
		room.queue_free()
		return {}
	lamp.SetOn(false)
	await _step(2)
	_check(guard.CurrentStateName == "Idle" and not guard.IsAware, "%s: fresh guard state '%s' IsAware=%s, expected Idle/unaware (hero at %s, %.0f px away)" % [label, guard.CurrentStateName, guard.IsAware, player.position, player.position.distance_to(guard.position)])
	_check(player.CurrentStateName == "Idle", "%s: fresh hero state '%s', expected 'Idle'" % [label, player.CurrentStateName])
	_check(Engine.time_scale == 1.0, "%s: Engine.time_scale=%s in a fresh room, expected 1" % [label, Engine.time_scale])
	return {"room": room, "player": player, "guard": guard, "director": director, "lamp": lamp, "gsm": gsm}

func _close_room(r: Dictionary, gs: Node) -> void:
	_release_all()
	if Engine.time_scale != 1.0:
		var restored: int = await _wait_restored(RESTORE_CAP_MS)
		_check(restored >= 0, "close room: Engine.time_scale not restored within %d ms" % RESTORE_CAP_MS)
	if r.has("room") and is_instance_valid(r["room"]):
		r["room"].queue_free()
	gs.ResetRun()
	await _step(1)

func _run() -> void:
	# 0. Preconditions: InputMap actions this script drives, autoloads, scenes.
	for a in ["move_left", "move_right", "jump", "attack", "heavy_attack"]:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)
		if InputMap.has_action(a):
			_check(InputMap.action_get_events(a).size() > 0, "action '%s' has no events" % a)
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	_check(root.get_node_or_null("HitStop") != null, "HitStop autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	# 0a. Guard.tscn standalone: script, collision scheme, state machine, export defaults, idle
	#     without a target.
	var guard_scene: PackedScene = load("res://scenes/actors/Guard.tscn")
	_check(guard_scene != null, "res://scenes/actors/Guard.tscn failed to load")
	if guard_scene != null:
		var g: Node = guard_scene.instantiate()
		root.add_child(g)
		_check(g.get_script() != null and str(g.get_script().resource_path).ends_with("Guard.cs"),
			"Guard.tscn has no Guard.cs attached (did dotnet build run?)")
		if g.get("MaxHp") == null:
			_check(false, "Guard exports missing — Guard.cs not attached, aborting")
			g.queue_free()
			_finish()
			return
		_check(g is CharacterBody2D, "Guard root is %s, expected CharacterBody2D" % g.get_class())
		_check(g.collision_layer == 4 and g.collision_mask == 1, "Guard body layer/mask = %d/%d, expected 4/1 (Enemy / World)" % [g.collision_layer, g.collision_mask])
		_check(g.motion_mode == 1, "Guard motion_mode=%d, expected 1 (Floating)" % g.motion_mode)
		var sprite: Node = g.get_node_or_null("Visual/Sprite")
		_check(sprite is AnimatedSprite2D, "Guard has no 'Visual/Sprite' AnimatedSprite2D (the painted guard)")
		if sprite is AnimatedSprite2D:
			_check(sprite.sprite_frames != null, "Guard Visual/Sprite has no SpriteFrames")
		var hurt: Node = g.get_node_or_null("Visual/Hurtbox")
		var hit: Node = g.get_node_or_null("Visual/Hitbox")
		_check(hurt != null and hurt is Area2D, "Guard has no 'Visual/Hurtbox' Area2D (under Visual so it rises/rotates with it)")
		_check(hit != null and hit is Area2D, "Guard has no 'Visual/Hitbox' Area2D")
		if hurt != null:
			_check(hurt.collision_layer == 4 and hurt.collision_mask == 0, "Guard Hurtbox layer/mask = %d/%d, expected 4/0" % [hurt.collision_layer, hurt.collision_mask])
			_check(hurt.monitorable == true, "Guard Hurtbox is not monitorable")
		if hit != null:
			_check(hit.collision_layer == 16 and hit.collision_mask == 2, "Guard Hitbox layer/mask = %d/%d, expected 16/2 (EnemyHitbox / Player)" % [hit.collision_layer, hit.collision_mask])
			_check(hit.get_script() != null and str(hit.get_script().resource_path).ends_with("Hitbox.cs"), "Guard Hitbox has no Hitbox.cs")
			_check(hit.get("IsActive") == false, "Guard Hitbox active at rest")
		var gsm0: Node = g.get_node_or_null("StateMachine")
		_check(gsm0 != null, "Guard has no StateMachine child")
		if gsm0 != null:
			for s in ["Idle", "Approach", "Attack", "Hurt", "Down", "KO"]:
				_check(gsm0.HasState(s), "Guard StateMachine lacks state '%s'" % s)
		var expected_exports := {"MaxHp": 30.0, "MoveSpeed": 140.0, "AttackRange": 46.0, "DepthTolerance": 12.0,
			"Damage": 8.0, "Knockback": 120.0, "AttackCooldown": 0.8, "TelegraphTime": 0.3,
			"PerceptionRange": 420.0, "DarkPerceptionFactor": 0.5, "DarkFirstHitMultiplier": 2.0,
			"HurtDuration": 0.25, "DownDuration": 1.0, "HoldDistance": 120.0, "SpriteFeetOffset": 36.0}
		for k in expected_exports:
			var v = g.get(k)
			_check(v != null and is_equal_approx(float(v), expected_exports[k]), "Guard.%s default is %s, expected %s" % [k, v, expected_exports[k]])
		_check(g.HitStopFrames == 4, "Guard.HitStopFrames default is %s, expected 4" % g.HitStopFrames)
		_check(g.Facing == 1, "Guard.Facing default is %s, expected 1" % g.Facing)
		var ap: AnimationPlayer = g.get_node_or_null("AnimationPlayer")
		_check(ap != null, "Guard has no AnimationPlayer")
		if ap != null:
			for anim in ["attack", "hurt", "ko", "RESET", "idle", "walk"]:
				_check(ap.has_animation(anim), "Guard AnimationPlayer lacks '%s'" % anim)
			if ap.has_animation("attack"):
				_check(is_equal_approx(ap.get_animation("attack").length, 0.55), "Guard 'attack' length %.2f, expected 0.55" % ap.get_animation("attack").length)
			# Balance is frozen: the punch still opens at TelegraphTime and closes 0.1 s later.
			if ap.has_animation("attack"):
				var atk: Animation = ap.get_animation("attack")
				_check(is_equal_approx(_method_time(atk, "HitboxOn"), 0.3) and is_equal_approx(_method_time(atk, "HitboxOff"), 0.4),
					"Guard 'attack' HitboxOn/HitboxOff at %.3f/%.3f, expected 0.30/0.40 (balance is frozen)" % [_method_time(atk, "HitboxOn"), _method_time(atk, "HitboxOff")])
			if ap.has_animation("hurt") and ap.has_animation("ko"):
				_check(is_equal_approx(ap.get_animation("hurt").length, 0.25), "Guard 'hurt' length %.2f, expected 0.25" % ap.get_animation("hurt").length)
				_check(is_equal_approx(ap.get_animation("ko").length, 0.6), "Guard 'ko' length %.2f, expected 0.60" % ap.get_animation("ko").length)
			# The looping gait animations must not touch what SetDown() / the flash tween own.
			for anim in ["idle", "walk"]:
				if not ap.has_animation(anim):
					continue
				_check(ap.get_animation(anim).loop_mode != Animation.LOOP_NONE, "Guard '%s' must loop" % anim)
				for path in _value_paths(ap.get_animation(anim)):
					_check(path != "Visual:modulate" and path != "Visual:rotation",
						"Guard '%s' keys '%s'; Visual:modulate/rotation belong to hurt/ko, SetDown() and the flash tween" % [anim, path])
			if ap.has_animation("RESET"):
				var reset_paths: Array = _value_paths(ap.get_animation("RESET"))
				for anim in ap.get_animation_list():
					if String(anim) == "RESET":
						continue
					for path in _value_paths(ap.get_animation(anim)):
						_check(path in reset_paths, "Guard RESET does not key '%s', written by '%s'" % [path, anim])
		await _step(2)
		_check(is_equal_approx(g.Hp, 30.0), "standalone Guard.Hp=%s, expected 30" % g.Hp)
		_check(g.CurrentStateName == "Idle", "standalone Guard state '%s', expected 'Idle'" % g.CurrentStateName)
		_check(g.IsAware == false and g.IsKnockedOut == false, "standalone Guard IsAware=%s IsKnockedOut=%s, expected false/false" % [g.IsAware, g.IsKnockedOut])
		_check(g.Target == null, "standalone Guard.Target=%s, expected null (no level set it)" % g.Target)
		g.queue_free()
		await _step(1)

	# 0b. Level wiring: LevelBase exports, director, camera limited to the starting room, the guard
	#     standing at the end of the drift targeting the hero, hero sensor + hurtbox under Visual.
	var scene: PackedScene = load(ROOM_PATH)
	_check(scene != null, "%s failed to load" % ROOM_PATH)
	if scene == null:
		_finish()
		return
	var r: Dictionary = await _open_room(scene, gs, "wiring")
	if r.is_empty():
		_finish()
		return
	var room: Node = r["room"]
	var player: Node = r["player"]
	var guard: Node = r["guard"]
	var director: Node = r["director"]
	var lamp: Node = r["lamp"]
	_check(room.get_script() != null and str(room.get_script().resource_path).ends_with("Level00_Sections.cs"), "Level00_Sections has no Level00_Sections.cs attached")
	_check(room.get("RestartDelay") != null and is_equal_approx(room.RestartDelay, 1.0), "Level00_Sections.RestartDelay=%s, expected 1 (LevelBase export)" % room.get("RestartDelay"))
	_check(room.get("IsRestartPending") == false, "Level00_Sections.IsRestartPending=%s at start, expected false" % room.get("IsRestartPending"))
	_check(director.get_script() != null and str(director.get_script().resource_path).ends_with("EnemyDirector.cs"), "EnemyDirector has no EnemyDirector.cs")
	_check(director.get("MaxAttackers") == 2, "EnemyDirector.MaxAttackers=%s, expected 2" % director.get("MaxAttackers"))
	_check(director.get("ActiveAttackers") == 0, "EnemyDirector.ActiveAttackers=%s at start, expected 0" % director.get("ActiveAttackers"))
	# The starting room's bounds are applied on ready: the camera cannot leave the mine face.
	var start_room: Node = room.get("StartRoom")
	var camera: Camera2D = room.get_node_or_null("Camera2D")
	_check(start_room != null, "Level00_Sections.StartRoom is not wired")
	_check(camera != null, "Level00_Sections has no Camera2D")
	if camera != null and start_room != null:
		var rect: Rect2 = start_room.Rect
		_check(camera.limit_left == roundi(rect.position.x) and camera.limit_top == roundi(rect.position.y)
			and camera.limit_right == roundi(rect.end.x) and camera.limit_bottom == roundi(rect.end.y),
			"Camera2D limits %d/%d/%d/%d, expected the start room's %s" % [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom, rect])
	_check(guard.position == GUARD_START, "Guard at %s, expected %s" % [guard.position, GUARD_START])
	_check(guard.Facing == -1, "Guard.Facing=%s in the level, expected -1 (looks left, back down the drift)" % guard.Facing)
	_check(guard.Target == player, "Guard.Target is not the level's Player (Level00_Sections.SetTarget missing?)")
	_check(guard.Director == director, "Guard.Director is not the level's EnemyDirector")
	var sensor: Node = player.get_node_or_null("LightSensor")
	_check(sensor != null and sensor is Area2D, "Player has no 'LightSensor' Area2D")
	if sensor != null:
		_check(sensor.collision_mask == 64, "Player/LightSensor.collision_mask=%d, expected 64 (LightDark)" % sensor.collision_mask)
	var phurt: Node = player.get_node_or_null("Visual/Hurtbox")
	_check(phurt != null and phurt is Area2D, "Player has no 'Visual/Hurtbox' (must live under Visual so a jump lifts it)")
	if phurt != null:
		_check(phurt.collision_layer == 2, "Player Hurtbox layer=%d, expected 2 (Player)" % phurt.collision_layer)
	_check(player.IsLit == false, "Player.IsLit=%s at start (lamp off, dark floor), expected false" % player.IsLit)
	_check(lamp.IsOn == false, "Flashlight.IsOn=%s at start, expected false" % lamp.IsOn)
	if _failures.size() > 0:
		await _close_room(r, gs)
		_finish()
		return
	await _close_room(r, gs)

	# 1. Lit perception -> Approach -> Attack -> punch: Noticed within 5 frames at 250 px with the
	#    lamp on, Approach (moves left, faces the hero), Attack within 150 frames at |dx| <=
	#    AttackRange holding the only slot, then Hurt(8) with hit-stop and Energy -8. The lamp is
	#    switched off right after the notice and Energy reset, so the delta is the punch alone.
	r = await _open_room(scene, gs, "lit")
	if r.is_empty():
		_finish()
		return
	room = r["room"]
	player = r["player"]
	guard = r["guard"]
	director = r["director"]
	lamp = r["lamp"]
	var noticed: Array = []
	var gstates: Array = []
	var hurt_events: Array = []
	guard.Noticed.connect(func(): noticed.append(true))
	r["gsm"].StateChanged.connect(func(_from: String, to: String): gstates.append(to))
	player.Hurt.connect(func(d: float): hurt_events.append(d))
	guard.position = GUARD_POS
	player.position = LIT_POS
	lamp.SetOn(true)
	_check(lamp.IsOn and player.IsLit, "lit: Flashlight.IsOn=%s Player.IsLit=%s after SetOn(true), expected true/true" % [lamp.IsOn, player.IsLit])
	var notice_after: int = await _wait_event(noticed, NOTICE_CAP)
	_check(notice_after >= 0, "lit: Noticed not emitted within %d frames (hero lit at %.0f px, PerceptionRange %s; state '%s')" % [NOTICE_CAP, GUARD_POS.x - LIT_POS.x, guard.PerceptionRange, guard.CurrentStateName])
	_check(guard.IsAware, "lit: Guard.IsAware=%s after the notice, expected true" % guard.IsAware)
	_check(guard.CurrentStateName == "Approach", "lit: guard state '%s' after the notice, expected 'Approach'" % guard.CurrentStateName)
	lamp.SetOn(false)
	gs.Energy = gs.MaxEnergy
	var gx0: float = guard.position.x
	var attack_after: int = await _wait_state(guard, "Attack", ATTACK_CAP)
	_check(attack_after >= 0, "lit: guard state '%s' %d frames after the notice, expected 'Attack' (x=%.1f, hero x=%.1f)" % [guard.CurrentStateName, ATTACK_CAP, guard.position.x, player.position.x])
	_check(guard.position.x < gx0, "lit: guard x %.1f -> %.1f, expected to walk left towards the hero" % [gx0, guard.position.x])
	_check(guard.Facing == -1 and guard.Visual.scale.x == -1.0, "lit: Guard.Facing=%s Visual.scale=%s while approaching, expected -1 / (-1, 1)" % [guard.Facing, guard.Visual.scale])
	print("enemy_guard: lit — noticed after %d frames, Attack after %d frames at |dx|=%.1f" % [notice_after, attack_after, absf(guard.position.x - player.position.x)])
	if attack_after >= 0:
		_check(absf(guard.position.x - player.position.x) <= guard.AttackRange, "lit: Attack started at |dx|=%.1f, expected <= AttackRange %s" % [absf(guard.position.x - player.position.x), guard.AttackRange])
		_check(absf(guard.position.y - player.position.y) <= guard.DepthTolerance, "lit: Attack started at |dy|=%.1f, expected <= DepthTolerance %s" % [absf(guard.position.y - player.position.y), guard.DepthTolerance])
		_check(director.ActiveAttackers == 1, "lit: EnemyDirector.ActiveAttackers=%s during Attack, expected 1" % director.ActiveAttackers)
		_check(guard.HasAttackSlot == true, "lit: Guard.HasAttackSlot=%s during Attack, expected true" % guard.HasAttackSlot)
		_check(gstates == ["Approach", "Attack"], "lit: guard transitions %s, expected [Approach, Attack]" % [gstates])
		var energy_before: float = gs.Energy
		var punch: Dictionary = await _watch_until(func(): return not hurt_events.is_empty(), PUNCH_CAP_MS)
		_check(punch["ok"], "lit: hero Hurt not emitted within %d ms of Attack (guard state '%s', Energy %s)" % [PUNCH_CAP_MS, guard.CurrentStateName, gs.Energy])
		if punch["ok"]:
			_check(punch["min_scale"] == 0.0, "lit: Engine.time_scale never reached 0 around the punch (min %s), expected a hit-stop" % punch["min_scale"])
			_check(hurt_events == [8.0], "lit: Hurt events %s, expected [8.0] (Guard.Damage)" % [hurt_events])
			_check(is_equal_approx(gs.Energy, energy_before - 8.0), "lit: Energy=%s after the punch, expected %s (-8)" % [gs.Energy, energy_before - 8.0])
			_check(player.CurrentStateName == "Hurt", "lit: hero state '%s' right after the punch, expected 'Hurt'" % player.CurrentStateName)
			_check(director.ActiveAttackers <= 1, "lit: EnemyDirector.ActiveAttackers=%s at the punch, expected <= 1" % director.ActiveAttackers)
			print("enemy_guard: lit — punch %d ms after Attack, Energy %s -> %s, time_scale min %s" % [punch["elapsed"], energy_before, gs.Energy, punch["min_scale"]])
		var restored: int = await _wait_restored(RESTORE_CAP_MS)
		_check(restored >= 0, "lit: Engine.time_scale not restored within %d ms" % RESTORE_CAP_MS)
	await _close_room(r, gs)

	# 2. Unlit in front: 280 px (> 420 * 0.5) is ignored for 120 frames (Idle, unaware, no
	#    Noticed); 180 px in front is noticed within 5 frames.
	r = await _open_room(scene, gs, "dark")
	if r.is_empty():
		_finish()
		return
	player = r["player"]
	guard = r["guard"]
	noticed = []
	guard.Noticed.connect(func(): noticed.append(true))
	guard.position = GUARD_POS
	player.position = DARK_FAR
	var dark_states: Array = []
	for i in DARK_IGNORE_FRAMES:
		await physics_frame
		if guard.CurrentStateName != "Idle" and not dark_states.has(guard.CurrentStateName):
			dark_states.append(guard.CurrentStateName)
	_check(player.IsLit == false, "dark: Player.IsLit=%s at %s with the lamp off, expected false" % [player.IsLit, DARK_FAR])
	_check(noticed.is_empty() and not guard.IsAware, "dark: unlit hero at %.0f px in front noticed (%d Noticed, IsAware=%s), expected unseen beyond %.0f px" % [GUARD_POS.x - DARK_FAR.x, noticed.size(), guard.IsAware, guard.PerceptionRange * guard.DarkPerceptionFactor])
	_check(dark_states.is_empty(), "dark: guard left Idle (%s) while the unlit hero stood at 280 px" % [dark_states])
	_check(guard.position == GUARD_POS, "dark: guard moved to %s while unaware, expected %s" % [guard.position, GUARD_POS])
	player.position = DARK_NEAR
	var dark_notice: int = await _wait_event(noticed, NOTICE_CAP)
	_check(dark_notice >= 0, "dark: unlit hero at %.0f px in front not noticed within %d frames (state '%s')" % [GUARD_POS.x - DARK_NEAR.x, NOTICE_CAP, guard.CurrentStateName])
	_check(guard.CurrentStateName == "Approach", "dark: guard state '%s' after noticing at 180 px, expected 'Approach'" % guard.CurrentStateName)
	print("enemy_guard: dark — ignored at 280 px for %d frames, noticed at 180 px after %d frames" % [DARK_IGNORE_FRAMES, dark_notice])
	await _close_room(r, gs)

	# 3. Unlit BEHIND the guard (it faces left, hero on its right): never noticed; the hero walks
	#    up from behind, faces left and lands a light hit: 5 * DarkFirstHitMultiplier = 10 (Hp 20),
	#    Noticed once, aware; the second light hit deals the plain 5 (Hp 15). Hit-stop on both.
	r = await _open_room(scene, gs, "behind")
	if r.is_empty():
		_finish()
		return
	player = r["player"]
	guard = r["guard"]
	noticed = []
	var damaged: Array = []
	guard.Noticed.connect(func(): noticed.append(true))
	guard.Damaged.connect(func(hp: float): damaged.append(hp))
	guard.position = GUARD_POS
	player.position = BEHIND_FAR
	await _step(BEHIND_IGNORE_FRAMES)
	_check(noticed.is_empty() and guard.CurrentStateName == "Idle", "behind: unlit hero %.0f px behind the guard noticed (%d Noticed, state '%s'), expected unseen" % [BEHIND_FAR.x - GUARD_POS.x, noticed.size(), guard.CurrentStateName])
	player.position = BEHIND_NEAR
	Input.action_press("move_left")
	await _step(2)
	Input.action_release("move_left")
	await _step(2)
	_check(player.Facing == -1, "behind: hero Facing=%s after move_left, expected -1" % player.Facing)
	_check(player.CurrentStateName == "Idle", "behind: hero state '%s' before the attack, expected 'Idle'" % player.CurrentStateName)
	_check(player.position.x > guard.position.x, "behind: hero x=%.1f not behind the guard x=%.1f" % [player.position.x, guard.position.x])
	_check(noticed.is_empty() and not guard.IsAware, "behind: guard noticed the unlit hero 40 px behind it (IsAware=%s), expected unaware until hit" % guard.IsAware)
	await _tap("attack")
	var dark_hit: Dictionary = await _watch_until(func(): return guard.Hp < 30.0, HIT_CAP_MS)
	_check(dark_hit["ok"], "behind: first light hit did not land within %d ms (Hp=%s, hero '%s')" % [HIT_CAP_MS, guard.Hp, player.CurrentStateName])
	if dark_hit["ok"]:
		_check(dark_hit["min_scale"] == 0.0, "behind: no hit-stop on the first hit (time_scale min %s)" % dark_hit["min_scale"])
		_check(is_equal_approx(guard.Hp, 20.0), "behind: Guard.Hp=%s after the first hit from the dark, expected 20 (5 x DarkFirstHitMultiplier %s)" % [guard.Hp, guard.DarkFirstHitMultiplier])
		_check(damaged == [20.0], "behind: Damaged events %s, expected [20.0]" % [damaged])
		_check(guard.IsAware and noticed.size() == 1, "behind: IsAware=%s Noticed x%d after being hit, expected true / 1" % [guard.IsAware, noticed.size()])
		_check(guard.CurrentStateName == "Hurt", "behind: guard state '%s' right after the hit, expected 'Hurt'" % guard.CurrentStateName)
	var r3: int = await _wait_restored(RESTORE_CAP_MS)
	_check(r3 >= 0, "behind: Engine.time_scale not restored within %d ms after the first hit" % RESTORE_CAP_MS)
	var hero_idle: int = await _wait_state(player, "Idle", 30)
	_check(hero_idle >= 0, "behind: hero state '%s' 30 frames after the first hit, expected 'Idle'" % player.CurrentStateName)
	if dark_hit["ok"] and hero_idle >= 0:
		await _tap("attack")
		var second: Dictionary = await _watch_until(func(): return guard.Hp < 20.0, HIT_CAP_MS)
		_check(second["ok"], "behind: second light hit did not land within %d ms (Hp=%s, guard '%s' at x=%.1f, hero x=%.1f)" % [HIT_CAP_MS, guard.Hp, guard.CurrentStateName, guard.position.x, player.position.x])
		if second["ok"]:
			_check(second["min_scale"] == 0.0, "behind: no hit-stop on the second hit (time_scale min %s)" % second["min_scale"])
			_check(is_equal_approx(guard.Hp, 15.0), "behind: Guard.Hp=%s after the second hit, expected 15 (plain 5 once aware)" % guard.Hp)
			_check(damaged == [20.0, 15.0], "behind: Damaged events %s, expected [20.0, 15.0]" % [damaged])
			_check(noticed.size() == 1, "behind: Noticed emitted %d times, expected once" % noticed.size())
		var r3b: int = await _wait_restored(RESTORE_CAP_MS)
		_check(r3b >= 0, "behind: Engine.time_scale not restored within %d ms after the second hit" % RESTORE_CAP_MS)
	print("enemy_guard: behind — Damaged %s, Noticed x%d" % [damaged, noticed.size()])
	await _close_room(r, gs)

	# 4. Jump dodge: unlit hero at 180 px in front is noticed, the guard walks in and attacks; a
	#    jump tapped on the frame Attack is observed lifts the Hurtbox (under Visual) above the
	#    punch — no Hurt, no Hurt state, Energy unchanged (lamp off, so no drain either).
	r = await _open_room(scene, gs, "dodge")
	if r.is_empty():
		_finish()
		return
	player = r["player"]
	guard = r["guard"]
	hurt_events = []
	player.Hurt.connect(func(d: float): hurt_events.append(d))
	guard.position = GUARD_POS
	var ghitbox: Node = guard.get_node("Visual/Hitbox")
	# Re-derive the dodge threshold from the live shapes so a resized hurtbox/hitbox or a moved
	# Visual pivot shows up here instead of silently invalidating MIN_DODGE_HEIGHT.
	var hero_hurt_shape: CollisionShape2D = player.get_node_or_null("Visual/Hurtbox/CollisionShape2D")
	var guard_hit_shape: CollisionShape2D = guard.get_node_or_null("Visual/Hitbox/CollisionShape2D")
	_check(hero_hurt_shape != null and hero_hurt_shape.shape is RectangleShape2D, "dodge: Player Visual/Hurtbox has no RectangleShape2D")
	_check(guard_hit_shape != null and guard_hit_shape.shape is RectangleShape2D, "dodge: Guard Visual/Hitbox has no RectangleShape2D")
	if hero_hurt_shape != null and guard_hit_shape != null and hero_hurt_shape.shape is RectangleShape2D and guard_hit_shape.shape is RectangleShape2D:
		# Both relative to the feet at z = 0: Visual sits at -SpriteFeetOffset.
		var hero_hurt_bottom: float = -player.SpriteFeetOffset + hero_hurt_shape.position.y + hero_hurt_shape.shape.size.y / 2.0
		var guard_hit_top: float = -guard.SpriteFeetOffset + guard_hit_shape.position.y - guard_hit_shape.shape.size.y / 2.0
		var derived_threshold: float = hero_hurt_bottom - guard_hit_top
		_check(is_equal_approx(derived_threshold, MIN_DODGE_HEIGHT), "dodge: threshold derived from the shapes is %.1f (hero hurtbox bottom %.0f, guard hitbox top %.0f), expected MIN_DODGE_HEIGHT %.0f — update the constant and the plan's acceptance line" % [derived_threshold, hero_hurt_bottom, guard_hit_top, MIN_DODGE_HEIGHT])
	player.position = DARK_NEAR
	var dodge_attack: int = await _wait_state(guard, "Attack", ATTACK_CAP + NOTICE_CAP)
	_check(dodge_attack >= 0, "dodge: guard state '%s' after %d frames, expected 'Attack'" % [guard.CurrentStateName, ATTACK_CAP + NOTICE_CAP])
	if dodge_attack >= 0:
		var energy0: float = gs.Energy
		await _tap("jump")
		# The press is polled by the hero's next physics tick, so Jump shows up one frame later.
		var jump_after: int = await _wait_state(player, "Jump", 3)
		_check(jump_after >= 0, "dodge: hero state '%s' 3 frames after the jump tap, expected 'Jump'" % player.CurrentStateName)
		var window_opened := false
		var height_at_open := -1.0
		var hero_hurt_state := false
		for i in 60 - maxi(jump_after, 0):
			await physics_frame
			if ghitbox.IsActive and not window_opened:
				window_opened = true
				height_at_open = player.Height
			if player.CurrentStateName == "Hurt":
				hero_hurt_state = true
		_check(window_opened, "dodge: guard Hitbox never became active within 60 frames of Attack (state '%s')" % guard.CurrentStateName)
		_check(height_at_open > MIN_DODGE_HEIGHT, "dodge: hero Height=%.1f when the punch window opened, expected > %.0f (the hurtbox bottom must clear the hitbox top by the 0.3 s telegraph)" % [height_at_open, MIN_DODGE_HEIGHT])
		_check(hurt_events.is_empty(), "dodge: hero Hurt fired %s while jumping over the punch, expected none" % [hurt_events])
		_check(not hero_hurt_state, "dodge: hero entered 'Hurt' during the jump, expected the punch to miss")
		_check(is_equal_approx(gs.Energy, energy0), "dodge: Energy %s -> %s over the dodged punch, expected unchanged" % [energy0, gs.Energy])
		_check(player.Height == 0.0 and not player.IsAirborne, "dodge: hero Height=%.1f IsAirborne=%s 60 frames after the jump, expected landed" % [player.Height, player.IsAirborne])
		_check(Engine.time_scale == 1.0, "dodge: Engine.time_scale=%s after the miss, expected 1 (no hit-stop)" % Engine.time_scale)
		print("enemy_guard: dodge — Attack after %d frames, Height %.1f when the punch window opened, Hurt events %s" % [dodge_attack, height_at_open, hurt_events])
	await _close_room(r, gs)

	# 5. T-B01 on the Guard: a heavy from behind (unaware -> 12 x 2 = 24) floors it at Hp 6 (Down,
	#    Visual rotated); while Down TakeDamage() returns false and a real light hit that overlaps
	#    the Hurtbox changes nothing (Hp 6, no hit-stop); it gets up on its own within
	#    DownDuration + margin and is upright again.
	r = await _open_room(scene, gs, "down")
	if r.is_empty():
		_finish()
		return
	player = r["player"]
	guard = r["guard"]
	noticed = []
	guard.Noticed.connect(func(): noticed.append(true))
	var phitbox: Node = player.get_node("Visual/Hitbox")
	var ghurtbox: Area2D = guard.get_node("Visual/Hurtbox")
	var gsprite: AnimatedSprite2D = guard.get_node("Visual/Sprite")
	guard.position = GUARD_POS
	player.position = BEHIND_NEAR
	Input.action_press("move_left")
	await _step(2)
	Input.action_release("move_left")
	await _step(2)
	_check(player.Facing == -1 and player.CurrentStateName == "Idle", "down: hero Facing=%s state '%s' before the heavy, expected -1 / Idle" % [player.Facing, player.CurrentStateName])
	_check(not guard.IsAware, "down: guard already aware before the heavy from behind")
	await _tap("heavy_attack")
	var heavy: Dictionary = await _watch_until(func(): return guard.Hp < 30.0, HIT_CAP_MS)
	_check(heavy["ok"], "down: heavy did not land within %d ms (Hp=%s)" % [HIT_CAP_MS, guard.Hp])
	if heavy["ok"]:
		_check(heavy["min_scale"] == 0.0, "down: no hit-stop on the heavy (time_scale min %s)" % heavy["min_scale"])
		_check(is_equal_approx(guard.Hp, 6.0), "down: Guard.Hp=%s after the heavy from the dark, expected 6 (12 x 2)" % guard.Hp)
		_check(guard.CurrentStateName == "Down", "down: guard state '%s' after the heavy, expected 'Down'" % guard.CurrentStateName)
		_check(guard.IsAware and noticed.size() == 1, "down: IsAware=%s Noticed x%d after the heavy, expected true / 1" % [guard.IsAware, noticed.size()])
		_check(guard.IsKnockedOut == false, "down: guard knocked out at 6 HP")
	var r5: int = await _wait_restored(RESTORE_CAP_MS)
	_check(r5 >= 0, "down: Engine.time_scale not restored within %d ms" % RESTORE_CAP_MS)
	if heavy["ok"]:
		await _step(3)
		_check(gsprite.animation == DOWN_ANIM, "down: Guard sprite shows '%s' while Down, expected the floored '%s'" % [gsprite.animation, DOWN_ANIM])
		var api_hit: bool = guard.TakeDamage(5.0, 0.0, false, 0)
		_check(api_hit == false, "T-B01: Guard.TakeDamage while Down returned %s, expected false" % api_hit)
		_check(is_equal_approx(guard.Hp, 6.0), "T-B01: Guard.Hp=%s after TakeDamage while Down, expected 6" % guard.Hp)
		var hero_idle5: int = await _wait_state(player, "Idle", 40)
		_check(hero_idle5 >= 0, "down: hero state '%s' 40 frames after the heavy, expected 'Idle'" % player.CurrentStateName)
		_check(guard.CurrentStateName == "Down", "down: guard state '%s' before the light hit, expected still 'Down' (DownDuration %s s)" % [guard.CurrentStateName, guard.DownDuration])
		await _tap("attack")
		# Lambdas capture locals by value, so the overlap sighting is recorded in an Array.
		var overlaps: Array = []
		var ignored: Dictionary = await _watch_until(func():
			if phitbox.IsActive and phitbox.get_overlapping_areas().has(ghurtbox):
				overlaps.append(true)
			return guard.Hp < 6.0, NO_HIT_WINDOW_MS)
		var overlapped: bool = not overlaps.is_empty()
		_check(overlapped, "T-B01: the hero's light Hitbox never overlapped the Down guard's Hurtbox (hero x=%.1f, guard x=%.1f) — the ignore check did not exercise TakeHit" % [player.position.x, guard.position.x])
		_check(not ignored["ok"], "T-B01: light hit on the Down guard changed Hp to %s, expected ignored" % guard.Hp)
		_check(ignored["min_scale"] == 1.0, "T-B01: Engine.time_scale dropped to %s during the ignored hit, expected no hit-stop" % ignored["min_scale"])
		_check(is_equal_approx(guard.Hp, 6.0), "T-B01: Guard.Hp=%s after the ignored hit, expected 6" % guard.Hp)
		_check(guard.CurrentStateName == "Down", "T-B01: guard state '%s' after the ignored hit, expected still 'Down'" % guard.CurrentStateName)
		var up_after := -1
		for i in GETUP_CAP:
			if guard.CurrentStateName != "Down":
				up_after = i
				break
			await physics_frame
		_check(up_after >= 0, "T-B01: guard still '%s' %d frames after the ignored hit, expected to get up (DownDuration 1 s)" % [guard.CurrentStateName, GETUP_CAP])
		_check(guard.CurrentStateName in ["Approach", "Attack", "Idle"], "T-B01: guard state '%s' after getting up, expected Approach/Attack/Idle" % guard.CurrentStateName)
		_check(gsprite.animation != DOWN_ANIM, "T-B01: Guard sprite still on the floored '%s' frame after getting up" % DOWN_ANIM)
		_check(is_equal_approx(guard.Hp, 6.0), "T-B01: Guard.Hp=%s after getting up, expected 6" % guard.Hp)
		print("enemy_guard: T-B01 — heavy from the dark Hp 30 -> %s, light hit while Down ignored (overlap %s), up %d frames after the no-hit window in '%s'" % [guard.Hp, overlapped, up_after, guard.CurrentStateName])
	await _close_room(r, gs)

	# 5b. Down out of Attack (S1 regression): the guard notices the unlit hero at 180 px, walks in
	#     and starts its punch; on the first physics frame it is seen in 'Attack' a knockdown hit
	#     floors it (Attack.Exit resets the interrupted pose, Down.Enter plays the floored frame).
	#     The sprite must still show 'down' after two idle frames (a still-playing RESET used to snap
	#     it back upright) and 30 physics frames later while Down, with no gait animation stepping
	#     over it; the hitbox never opens, the slot is released, and the guard stands up on its own.
	r = await _open_room(scene, gs, "down-mid-attack")
	if r.is_empty():
		_finish()
		return
	player = r["player"]
	guard = r["guard"]
	director = r["director"]
	hurt_events = []
	player.Hurt.connect(func(d: float): hurt_events.append(d))
	var ghitbox5: Node = guard.get_node("Visual/Hitbox")
	var gsprite5: AnimatedSprite2D = guard.get_node("Visual/Sprite")
	var gap5: AnimationPlayer = guard.get_node("AnimationPlayer")
	guard.position = GUARD_POS
	player.position = DARK_NEAR
	var mid_attack: int = await _wait_state(guard, "Attack", ATTACK_CAP + NOTICE_CAP)
	_check(mid_attack >= 0, "down-mid-attack: guard state '%s' after %d frames, expected 'Attack'" % [guard.CurrentStateName, ATTACK_CAP + NOTICE_CAP])
	if mid_attack >= 0:
		_check(gap5.is_playing() and gap5.current_animation == "attack", "down-mid-attack: AnimationPlayer playing=%s '%s' on the first Attack frame, expected 'attack'" % [gap5.is_playing(), gap5.current_animation])
		_check(director.ActiveAttackers == 1, "down-mid-attack: EnemyDirector.ActiveAttackers=%s during Attack, expected 1" % director.ActiveAttackers)
		var hp_before: float = guard.Hp
		var floored: bool = guard.TakeDamage(12.0, 200.0, true, 0)
		_check(floored == true, "down-mid-attack: TakeDamage(12, 200, knockdown) during the telegraph returned %s, expected true" % floored)
		_check(guard.CurrentStateName == "Down", "down-mid-attack: guard state '%s' right after the knockdown, expected 'Down'" % guard.CurrentStateName)
		_check(is_equal_approx(guard.Hp, hp_before - 12.0), "down-mid-attack: Guard.Hp=%s after the knockdown, expected %s (aware: plain 12)" % [guard.Hp, hp_before - 12.0])
		_check(gsprite5.animation == DOWN_ANIM, "down-mid-attack: sprite shows '%s' the moment Down was entered, expected the floored '%s'" % [gsprite5.animation, DOWN_ANIM])
		_check(ghitbox5.IsActive == false, "down-mid-attack: guard Hitbox still active after the knockdown, expected closed by Attack.Exit")
		_check(director.ActiveAttackers == 0 and guard.HasAttackSlot == false, "down-mid-attack: ActiveAttackers=%s HasAttackSlot=%s after the knockdown, expected 0 / false" % [director.ActiveAttackers, guard.HasAttackSlot])
		_check(gap5.current_animation == DOWN_ANIM, "down-mid-attack: AnimationPlayer on '%s' after the knockdown, expected the floored '%s' (the interrupted attack's RESET must not win)" % [gap5.current_animation, DOWN_ANIM])
		await process_frame
		await process_frame
		_check(guard.CurrentStateName == "Down", "down-mid-attack: guard state '%s' two idle frames after the knockdown, expected 'Down'" % guard.CurrentStateName)
		var pose_idle: StringName = gsprite5.animation
		_check(pose_idle == DOWN_ANIM, "S1: sprite shows '%s' two idle frames after a knockdown out of Attack, expected '%s' (RESET clobbered the Down pose)" % [pose_idle, DOWN_ANIM])
		var gait_while_down := ""
		var pose_lost := ""
		for i in DOWN_HOLD_FRAMES:
			await physics_frame
			if gsprite5.animation != DOWN_ANIM and pose_lost == "":
				pose_lost = "frame %d: '%s'" % [i, gsprite5.animation]
			if gap5.is_playing() and gap5.current_animation in GAIT_ANIMS and gait_while_down == "":
				gait_while_down = "frame %d: '%s'" % [i, gap5.current_animation]
		_check(gait_while_down == "", "S1: the AnimationPlayer ran a gait during Down (%s); walk/idle must be stopped by GuardDown.Enter or the floored guard keeps stepping" % gait_while_down)
		_check(guard.CurrentStateName == "Down", "down-mid-attack: guard state '%s' %d physics frames after the knockdown, expected still 'Down' (DownDuration %s s)" % [guard.CurrentStateName, DOWN_HOLD_FRAMES, guard.DownDuration])
		_check(gsprite5.animation == DOWN_ANIM, "S1: sprite shows '%s' %d physics frames after the knockdown while still Down, expected '%s'" % [gsprite5.animation, DOWN_HOLD_FRAMES, DOWN_ANIM])
		_check(pose_lost == "", "S1: the floored pose was lost during %d Down frames (%s), expected '%s' throughout" % [DOWN_HOLD_FRAMES, pose_lost, DOWN_ANIM])
		_check(hurt_events.is_empty(), "down-mid-attack: hero Hurt fired %s although the punch was interrupted in its telegraph, expected none" % [hurt_events])
		_check(Engine.time_scale == 1.0, "down-mid-attack: Engine.time_scale=%s (TakeDamage with 0 hit-stop frames), expected 1" % Engine.time_scale)
		var stood_after := -1
		for i in GETUP_CAP:
			if guard.CurrentStateName != "Down":
				stood_after = i
				break
			await physics_frame
		_check(stood_after >= 0, "down-mid-attack: guard still '%s' %d frames later, expected to get up" % [guard.CurrentStateName, DOWN_HOLD_FRAMES + GETUP_CAP])
		_check(gsprite5.animation != DOWN_ANIM, "down-mid-attack: sprite still on the floored '%s' frame after getting up" % DOWN_ANIM)
		# Approach re-decides the gait on its first tick, one physics frame after Down released.
		await _step(2)
		_check(gap5.is_playing() and gap5.current_animation in ["walk", "idle", "attack"], "down-mid-attack: AnimationPlayer playing=%s '%s' after getting up, expected the gait (walk/idle) or a new attack" % [gap5.is_playing(), gap5.current_animation])
		_check(guard.CurrentStateName in ["Approach", "Attack"], "down-mid-attack: guard state '%s' after getting up, expected Approach/Attack (aware, hero in reach)" % guard.CurrentStateName)
		print("enemy_guard: down-mid-attack — Attack after %d frames, floored at Hp %s, pose '%s' after 2 idle frames, held over %d Down frames, up after %d more frames in '%s' ('%s')" % [mid_attack, guard.Hp, pose_idle, DOWN_HOLD_FRAMES, stood_after, guard.CurrentStateName, gsprite5.animation])
	await _close_room(r, gs)

	# 6. KO + restart: Energy 5, the aware guard punches once -> KnockedOut, Energy MinEnergy,
	#    restart pending; with no checkpoint armed LevelBase reloads the current scene after
	#    RestartDelay (real time) — a fresh level with Energy == MaxEnergy, Engine.time_scale == 1
	#    and an idle hero back on his authored start.
	r = await _open_room(scene, gs, "ko")
	if r.is_empty():
		_finish()
		return
	room = r["room"]
	player = r["player"]
	guard = r["guard"]
	var ko_events: Array = []
	player.KnockedOut.connect(func(): ko_events.append(true))
	guard.position = GUARD_POS
	player.position = KO_POS
	guard.SetAware()
	gs.Energy = 5.0
	_check(room.get("ArmedCheckpoint") == null, "ko: a checkpoint is armed — the KO would cost a soft respawn instead of the reload this section checks")
	current_scene = room   # LevelBase reloads the tree's current scene; a level added by a test has none by default
	var ko: Dictionary = await _watch_until(func(): return not ko_events.is_empty(), KO_CAP_MS)
	_check(ko["ok"], "ko: KnockedOut not emitted within %d ms (guard '%s' at x=%.1f, Energy %s, hero '%s')" % [KO_CAP_MS, guard.CurrentStateName, guard.position.x, gs.Energy, player.CurrentStateName])
	var new_scene: Node = null
	if ko["ok"]:
		_check(is_equal_approx(gs.Energy, gs.MinEnergy), "ko: Energy=%s after the KO punch, expected MinEnergy %s" % [gs.Energy, gs.MinEnergy])
		_check(player.IsKnockedOut and player.CurrentStateName == "KO", "ko: hero IsKnockedOut=%s state '%s', expected true / KO" % [player.IsKnockedOut, player.CurrentStateName])
		_check(room.IsRestartPending == true, "ko: Level00_Sections.IsRestartPending=%s after the KO, expected true" % room.IsRestartPending)
		var ko_msec: int = Time.get_ticks_msec()
		while Time.get_ticks_msec() - ko_msec < RELOAD_CAP_MS:
			await process_frame
			var cs: Node = current_scene
			if cs != null and (not is_instance_valid(room) or cs != room):
				new_scene = cs
				break
		var reload_ms: int = Time.get_ticks_msec() - ko_msec
		_check(new_scene != null, "ko: current scene not reloaded within %d ms of the KO (RestartDelay %s s)" % [RELOAD_CAP_MS, room.RestartDelay if is_instance_valid(room) else "?"])
		if new_scene != null:
			_check(reload_ms >= RELOAD_MIN_MS, "ko: scene reloaded %d ms after the KO, expected >= %d (RestartDelay 1 s)" % [reload_ms, RELOAD_MIN_MS])
			_check(not is_instance_valid(room), "ko: the old level instance is still alive after the reload")
			_check(new_scene.scene_file_path == ROOM_PATH, "ko: reloaded scene is '%s', expected %s" % [new_scene.scene_file_path, ROOM_PATH])
			await process_frame   # the reloaded level's load catch-up, like a fresh one
			await process_frame
			await _step(2)
			var np: Node = new_scene.get_node_or_null("Player") if is_instance_valid(new_scene) else null
			_check(np != null, "ko: reloaded scene has no 'Player'")
			if np != null:
				_check(np.IsKnockedOut == false and np.CurrentStateName == "Idle", "ko: reloaded hero IsKnockedOut=%s state '%s', expected false / Idle" % [np.IsKnockedOut, np.CurrentStateName])
				_check(np.position.is_equal_approx(RELOADED_POS), "ko: reloaded hero at %s, expected the scene's %s" % [np.position, RELOADED_POS])
			_check(is_equal_approx(gs.Energy, gs.MaxEnergy), "ko: Energy=%s after the reload, expected MaxEnergy %s" % [gs.Energy, gs.MaxEnergy])
			_check(Engine.time_scale == 1.0, "ko: Engine.time_scale=%s after the reload, expected 1" % Engine.time_scale)
			_check(new_scene.get("IsRestartPending") == false, "ko: reloaded room IsRestartPending=%s, expected false" % new_scene.get("IsRestartPending"))
			print("enemy_guard: ko — KnockedOut after %d ms, scene reloaded %d ms after the KO, Energy %s, time_scale %s" % [ko["elapsed"], reload_ms, gs.Energy, Engine.time_scale])
	# Teardown: drop the tree's current scene (either the reloaded room or, on failure, the old one).
	current_scene = null
	if new_scene != null and is_instance_valid(new_scene):
		new_scene.queue_free()
	await _close_room(r, gs)

	print("enemy_guard: idle frames used %d of MAX_FRAMES %d" % [_frames, MAX_FRAMES])
	_finish()
