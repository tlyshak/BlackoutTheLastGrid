extends SceneTree
# Smoke: basic combat (T-02b) — attack states + exports, Dummy scene/script, single light attack
# (hit-stop, flash, knockback, Hurt), three-hit light combo, hitbox depth tolerance (miss at
# |dy| = 20, hit at |dy| = DepthTolerance inclusive), heavy knockdown (Down → Idle after
# DownDuration), KO at 0 HP and ignored hits afterwards, hero Hurt/KO states. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/combat_dummy.gd
#
# Hit-stop sets Engine.time_scale = 0, which stops physics frames (awaiting `physics_frame` hangs
# until the restore), so hits are observed on idle frames (`process_frame`, which keep running)
# under a wall-clock cap, and the restore is awaited in real time. Everything else is counted in
# physics frames.

const NAME := "combat_dummy"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls; the
# real-time waits around each hit-stop cost idle frames too, so this is roomier than usual.
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack"]
const HIT_CAP_MS := 800        # wall-clock cap while waiting for one hit to land
const NO_HIT_WINDOW_MS := 450  # longer than the light animation (0.30 s) — a miss must stay a miss
const RESTORE_CAP_MS := 1000   # wall-clock cap while waiting for hit-stop to lift
const DUMMY_START := Vector2(640, 450)
const DUMMY2_START := Vector2(760, 470)
const DIMMED := Color(0.35, 0.35, 0.4)   # Dummy.DimmedColor (KO)

var _started := false
var _frames := 0
var _failures: Array[String] = []
var _transitions: Array = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

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

# Real-time wait that ignores Engine.time_scale (process_always, not physics-bound).
func _real_wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

# Presses `action` for exactly one physics frame.
func _tap(action: String) -> void:
	Input.action_press(action)
	await _step(1)
	Input.action_release(action)

# Watches idle frames until `dummy.Hp` drops or `cap_ms` of wall time pass. The snapshot is taken
# on the first idle frame after the hit, i.e. after TakeHit and the hit-stop trigger ran.
func _watch_hit(dummy: Node, cap_ms: int) -> Dictionary:
	var hp0: float = dummy.Hp
	var visual: Node2D = dummy.Visual
	var r := {"hit": false, "min_scale": Engine.time_scale, "scale": 1.0, "state": "",
		"modulate": Color.WHITE, "hit_msec": 0}
	var deadline: int = Time.get_ticks_msec() + cap_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		r["min_scale"] = minf(r["min_scale"], Engine.time_scale)
		if dummy.Hp < hp0:
			r["hit"] = true
			r["scale"] = Engine.time_scale
			r["state"] = dummy.CurrentStateName
			r["modulate"] = visual.modulate
			r["hit_msec"] = Time.get_ticks_msec()
			break
	return r

# Waits (idle frames) until Engine.time_scale is back to 1. Returns elapsed ms, or -1 on cap.
func _wait_restored(cap_ms: int) -> int:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < cap_ms:
		if Engine.time_scale == 1.0:
			return Time.get_ticks_msec() - start
		await process_frame
	return -1

# One light hit that must connect: tap `attack`, observe the hit, check hit-stop, wait for the
# restore. `label` prefixes failure messages. Returns the hit snapshot.
func _light_hit(dummy: Node, label: String, expected_hp: float, hit_stop_frames: int) -> Dictionary:
	await _tap("attack")
	var h: Dictionary = await _watch_hit(dummy, HIT_CAP_MS)
	_check(h["hit"], "%s: no hit within %d ms (Hp=%s)" % [label, HIT_CAP_MS, dummy.Hp])
	if not h["hit"]:
		return h
	_check(is_equal_approx(dummy.Hp, expected_hp), "%s: Hp=%s after the hit, expected %s" % [label, dummy.Hp, expected_hp])
	_check(h["scale"] == 0.0, "%s: Engine.time_scale=%s right after the hit, expected 0 (hit-stop)" % [label, h["scale"]])
	var elapsed: int = await _wait_restored(RESTORE_CAP_MS)
	_check(elapsed >= 0, "%s: Engine.time_scale not restored to 1 within %d ms" % [label, RESTORE_CAP_MS])
	# Plan: back to 1 within HitStopFrames / physics_ticks + 0.05 s; +0.05 s more for idle-frame granularity.
	var bound_ms: int = int((float(hit_stop_frames) / float(Engine.physics_ticks_per_second) + 0.1) * 1000.0)
	_check(elapsed < 0 or elapsed <= bound_ms, "%s: hit-stop lasted %d ms, expected <= %d ms (%d frames)" % [label, elapsed, bound_ms, hit_stop_frames])
	return h

func _run() -> void:
	# 0. Preconditions: InputMap actions the attack states read, GameState, TestRoom.
	for a in ["attack", "heavy_attack"]:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)
		if InputMap.has_action(a):
			_check(InputMap.action_get_events(a).size() > 0, "action '%s' has no events" % a)

	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	var scene: PackedScene = load("res://scenes/levels/TestRoom.tscn")
	_check(scene != null, "res://scenes/levels/TestRoom.tscn failed to load")
	if scene == null:
		_finish()
		return
	var room: Node = scene.instantiate()
	root.add_child(room)

	var player: Node = room.get_node_or_null("Player")
	var dummy: Node = room.get_node_or_null("Dummy")
	var dummy2: Node = room.get_node_or_null("Dummy2")
	_check(player != null, "TestRoom has no 'Player' child")
	_check(dummy != null, "TestRoom has no 'Dummy' child")
	_check(dummy2 != null, "TestRoom has no 'Dummy2' child")
	if player == null or dummy == null or dummy2 == null:
		room.queue_free()
		_finish()
		return
	_check(player.get_script() != null and str(player.get_script().resource_path).ends_with("Player.cs"),
		"Player has no Player.cs attached (did dotnet build run?)")
	_check(dummy.get_script() != null and str(dummy.get_script().resource_path).ends_with("Dummy.cs"),
		"Dummy has no Dummy.cs attached (did dotnet build run?)")
	if player.get("DepthTolerance") == null or dummy.get("MaxHp") == null:
		_check(false, "Player.DepthTolerance / Dummy.MaxHp export missing — C# scripts not attached, aborting")
		room.queue_free()
		_finish()
		return
	_check(is_equal_approx(player.DepthTolerance, 12.0), "Player.DepthTolerance default is %s, expected 12" % player.DepthTolerance)
	_check(is_equal_approx(dummy.MaxHp, 30.0), "Dummy.MaxHp default is %s, expected 30" % dummy.MaxHp)
	_check(is_equal_approx(dummy.DownDuration, 1.0), "Dummy.DownDuration default is %s, expected 1" % dummy.DownDuration)
	_check(dummy.position == DUMMY_START, "Dummy at %s, expected %s" % [dummy.position, DUMMY_START])
	_check(dummy2.position == DUMMY2_START, "Dummy2 at %s, expected %s" % [dummy2.position, DUMMY2_START])

	var sm: Node = player.get_node_or_null("StateMachine")
	var dsm: Node = dummy.get_node_or_null("StateMachine")
	var hitbox: Node = player.get_node_or_null("Visual/Hitbox")
	var dvisual: Node2D = dummy.get_node_or_null("Visual")
	var d2visual: Node2D = dummy2.get_node_or_null("Visual")
	_check(sm != null, "Player has no StateMachine child")
	_check(dsm != null, "Dummy has no StateMachine child")
	_check(hitbox != null, "Player has no Visual/Hitbox child")
	_check(dvisual != null, "Dummy has no Visual child")
	_check(d2visual != null, "Dummy2 has no Visual child")
	if sm == null or dsm == null or hitbox == null or dvisual == null or d2visual == null:
		room.queue_free()
		_finish()
		return
	_check(dummy.get_node_or_null("Hurtbox") != null, "Dummy has no 'Hurtbox' Area2D (Hitbox looks it up by name)")
	for s in ["Idle", "LightAttack1", "LightAttack2", "LightAttack3", "HeavyAttack", "Hurt", "KO"]:
		_check(sm.HasState(s), "Player StateMachine lacks state '%s'" % s)
	for s in ["Idle", "Hurt", "Down", "KO"]:
		_check(dsm.HasState(s), "Dummy StateMachine lacks state '%s'" % s)
	# Attack exports as documented in the plan (L1 5 / L2 5 / L3 8 / Heavy 12 knockdown).
	var expected_attacks := {"LightAttack1": [5.0, false, 4], "LightAttack2": [5.0, false, 4],
		"LightAttack3": [8.0, false, 5], "HeavyAttack": [12.0, true, 6]}
	for s in expected_attacks:
		var st: Node = sm.get_node_or_null(s)
		if st == null or st.get("Damage") == null:
			_check(false, "attack state '%s' missing or without PlayerAttack exports" % s)
			continue
		_check(is_equal_approx(st.Damage, expected_attacks[s][0]), "%s.Damage=%s, expected %s" % [s, st.Damage, expected_attacks[s][0]])
		_check(st.Knockdown == expected_attacks[s][1], "%s.Knockdown=%s, expected %s" % [s, st.Knockdown, expected_attacks[s][1]])
		_check(st.HitStopFrames == expected_attacks[s][2], "%s.HitStopFrames=%s, expected %s" % [s, st.HitStopFrames, expected_attacks[s][2]])
	if _failures.size() > 0:
		room.queue_free()
		_finish()
		return
	var l1_frames: int = sm.get_node("LightAttack1").HitStopFrames
	var l2_frames: int = sm.get_node("LightAttack2").HitStopFrames
	var l3_frames: int = sm.get_node("LightAttack3").HitStopFrames
	var heavy_frames: int = sm.get_node("HeavyAttack").HitStopFrames

	sm.StateChanged.connect(func(_from: String, to: String): _transitions.append(to))

	# 1. Initial state: hero idle next to Dummy, both dummies at full HP, no hit-stop.
	_release_all()
	player.position = Vector2(600, 450)
	await _step(2)
	_check(player.CurrentStateName == "Idle", "initial player state is '%s', expected 'Idle'" % player.CurrentStateName)
	_check(player.Facing == 1, "initial Facing=%s, expected 1 (right, towards Dummy)" % player.Facing)
	_check(is_equal_approx(dummy.Hp, 30.0), "initial Dummy.Hp=%s, expected 30" % dummy.Hp)
	_check(is_equal_approx(dummy2.Hp, 30.0), "initial Dummy2.Hp=%s, expected 30" % dummy2.Hp)
	_check(dummy.CurrentStateName == "Idle", "initial Dummy state is '%s', expected 'Idle'" % dummy.CurrentStateName)
	_check(dummy.IsKnockedOut == false, "Dummy initially knocked out")
	_check(hitbox.IsActive == false, "Hitbox active while idle")
	_check(Engine.time_scale == 1.0, "initial Engine.time_scale=%s, expected 1" % Engine.time_scale)
	_check(is_equal_approx(gs.Energy, gs.MaxEnergy), "initial Energy=%s, expected MaxEnergy=%s" % [gs.Energy, gs.MaxEnergy])

	# 2. Single light attack: LightAttack1 within 3 frames, hit-stop + flash + Hurt on the hit,
	#    Dummy2 (20 px deeper) untouched, then back to Idle with exactly [LightAttack1, Idle].
	_transitions.clear()
	Input.action_press("attack")
	var entered_l1 := false
	for i in 3:
		await physics_frame
		if player.CurrentStateName == "LightAttack1":
			entered_l1 = true
			break
	Input.action_release("attack")
	_check(entered_l1, "single attack: state '%s' after 3 frames, expected 'LightAttack1'" % player.CurrentStateName)
	var h1: Dictionary = await _watch_hit(dummy, HIT_CAP_MS)
	_check(h1["hit"], "single attack: Dummy not hit within %d ms (Hp=%s)" % [HIT_CAP_MS, dummy.Hp])
	if h1["hit"]:
		_check(h1["scale"] == 0.0, "single attack: Engine.time_scale=%s right after the hit, expected 0 (hit-stop)" % h1["scale"])
		_check(is_equal_approx(dummy.Hp, 25.0), "single attack: Dummy.Hp=%s, expected 25" % dummy.Hp)
		_check(h1["state"] == "Hurt", "single attack: Dummy state '%s' right after the hit, expected 'Hurt'" % h1["state"])
		_check(not h1["modulate"].is_equal_approx(Color.WHITE), "single attack: Dummy Visual.modulate=%s right after the hit, expected a flash (not white)" % h1["modulate"])
	_check(is_equal_approx(dummy2.Hp, 30.0), "single attack: Dummy2.Hp=%s, expected 30 (20 px deeper)" % dummy2.Hp)
	await _real_wait(0.3)
	_check(Engine.time_scale == 1.0, "single attack: Engine.time_scale=%s 0.3 s after the hit, expected 1" % Engine.time_scale)
	await _step(30)
	_check(player.CurrentStateName == "Idle", "single attack: player state '%s' after 30 frames, expected 'Idle'" % player.CurrentStateName)
	_check(_transitions == ["LightAttack1", "Idle"], "single attack: transitions %s, expected [LightAttack1, Idle]" % [_transitions])
	_check(dummy.CurrentStateName == "Idle", "single attack: Dummy state '%s' after 30 frames, expected 'Idle'" % dummy.CurrentStateName)
	_check(dvisual.modulate.is_equal_approx(Color.WHITE), "single attack: Dummy Visual.modulate=%s after the flash, expected white" % dvisual.modulate)
	_check(dummy.position.x > DUMMY_START.x, "single attack: Dummy.x=%.2f, expected > %.0f (knockback)" % [dummy.position.x, DUMMY_START.x])
	_check(hitbox.IsActive == false, "single attack: Hitbox still active after the attack")

	# 3. Three-hit combo: press inside each combo window; states in order, 25 -> 20 -> 15 -> 7,
	#    hit-stop on every hit and time scale restored at the end.
	_transitions.clear()
	var combo: Array = [[20.0, l1_frames], [15.0, l2_frames], [7.0, l3_frames]]
	for i in combo.size():
		var h: Dictionary = await _light_hit(dummy, "combo hit %d" % (i + 1), combo[i][0], combo[i][1])
		if not h["hit"]:
			break
		await _real_wait(0.15)   # lands inside the combo window (ComboWindowStart 0.1 s) before the animation ends
	await _step(40)
	_check(_transitions == ["LightAttack1", "LightAttack2", "LightAttack3", "Idle"],
		"combo: transitions %s, expected [LightAttack1, LightAttack2, LightAttack3, Idle]" % [_transitions])
	_check(is_equal_approx(dummy.Hp, 7.0), "combo: Dummy.Hp=%s, expected 7 (25-5-5-8)" % dummy.Hp)
	_check(Engine.time_scale == 1.0, "combo: Engine.time_scale=%s at the end, expected 1" % Engine.time_scale)
	_check(player.CurrentStateName == "Idle", "combo: player state '%s' after 40 frames, expected 'Idle'" % player.CurrentStateName)
	_check(dummy.CurrentStateName == "Idle", "combo: Dummy state '%s' after 40 frames, expected 'Idle'" % dummy.CurrentStateName)

	# 4. Depth: hero in front of Dummy2 (X overlap) but 20 px shallower -> no hit, no hit-stop;
	#    at |dy| == DepthTolerance (inclusive) -> hit. Dummy stays at 7 throughout.
	_transitions.clear()
	player.position = Vector2(720, 450)
	await _step(2)
	_check(player.CurrentStateName == "Idle", "depth: player state '%s' before the miss, expected 'Idle'" % player.CurrentStateName)
	await _tap("attack")
	var miss: Dictionary = await _watch_hit(dummy2, NO_HIT_WINDOW_MS)
	_check(not miss["hit"], "depth: Dummy2 hit from dy=20 (Hp=%s), expected a miss (DepthTolerance 12)" % dummy2.Hp)
	_check(miss["min_scale"] == 1.0, "depth: Engine.time_scale dropped to %s on a miss, expected to stay 1" % miss["min_scale"])
	_check(is_equal_approx(dummy2.Hp, 30.0), "depth: Dummy2.Hp=%s after the miss, expected 30" % dummy2.Hp)
	_check(is_equal_approx(dummy.Hp, 7.0), "depth: Dummy.Hp=%s after the miss, expected 7" % dummy.Hp)
	await _step(5)
	_check(_transitions == ["LightAttack1", "Idle"], "depth (miss): transitions %s, expected [LightAttack1, Idle]" % [_transitions])
	player.position = Vector2(720, DUMMY2_START.y - player.DepthTolerance)
	await _step(2)
	var hd: Dictionary = await _light_hit(dummy2, "depth (dy == DepthTolerance)", 25.0, l1_frames)
	_check(is_equal_approx(dummy2.Hp, 25.0), "depth: Dummy2.Hp=%s from dy=%s, expected 25 (inclusive tolerance)" % [dummy2.Hp, player.DepthTolerance])
	_check(is_equal_approx(dummy.Hp, 7.0), "depth: Dummy.Hp=%s after hitting Dummy2, expected 7" % dummy.Hp)
	_check(is_equal_approx(dummy2.position.y, DUMMY2_START.y), "depth: Dummy2.y=%.2f, expected %.0f (knockback is X only)" % [dummy2.position.y, DUMMY2_START.y])
	await _step(30)
	_check(player.CurrentStateName == "Idle", "depth: player state '%s' after the hit, expected 'Idle'" % player.CurrentStateName)
	_check(dummy2.CurrentStateName == "Idle", "depth: Dummy2 state '%s' after 30 frames, expected 'Idle'" % dummy2.CurrentStateName)

	# 5. Heavy on Dummy at 7 HP -> KO (stays down, dimmed, IsKnockedOut); a further light attack
	#    is ignored: HP stays 0, no hit-stop (TakeHit returns false, Hitbox.Hit not emitted).
	_transitions.clear()
	player.position = Vector2(dummy.position.x - 40.0, DUMMY_START.y)
	await _step(2)
	_check(player.CurrentStateName == "Idle", "heavy KO: player state '%s' before the attack, expected 'Idle'" % player.CurrentStateName)
	await _tap("heavy_attack")
	var hk: Dictionary = await _watch_hit(dummy, HIT_CAP_MS)
	_check("HeavyAttack" in _transitions, "heavy KO: no transition into HeavyAttack (transitions %s)" % [_transitions])
	_check(hk["hit"], "heavy KO: Dummy not hit within %d ms (Hp=%s)" % [HIT_CAP_MS, dummy.Hp])
	if hk["hit"]:
		_check(hk["scale"] == 0.0, "heavy KO: Engine.time_scale=%s right after the hit, expected 0" % hk["scale"])
		_check(hk["state"] == "KO", "heavy KO: Dummy state '%s' right after the hit, expected 'KO'" % hk["state"])
	var ko_elapsed: int = await _wait_restored(RESTORE_CAP_MS)
	_check(ko_elapsed >= 0, "heavy KO: Engine.time_scale not restored within %d ms" % RESTORE_CAP_MS)
	await _real_wait(0.2)
	await _step(5)
	_check(is_equal_approx(dummy.Hp, 0.0), "heavy KO: Dummy.Hp=%s, expected 0" % dummy.Hp)
	_check(dummy.CurrentStateName == "KO", "heavy KO: Dummy state '%s', expected 'KO'" % dummy.CurrentStateName)
	_check(dummy.IsKnockedOut == true, "heavy KO: Dummy.IsKnockedOut=%s, expected true" % dummy.IsKnockedOut)
	_check(is_equal_approx(dvisual.rotation, PI / 2.0), "heavy KO: Dummy Visual.rotation=%.3f, expected PI/2" % dvisual.rotation)
	await _step(25)   # the rest of the heavy animation (0.55 s) and the flash fade
	_check(player.CurrentStateName == "Idle", "heavy KO: player state '%s' after the heavy, expected 'Idle'" % player.CurrentStateName)
	_check(dvisual.modulate.is_equal_approx(DIMMED), "heavy KO: Dummy Visual.modulate=%s, expected dimmed %s" % [dvisual.modulate, DIMMED])
	_transitions.clear()
	await _tap("attack")
	var ignored: Dictionary = await _watch_hit(dummy, NO_HIT_WINDOW_MS)
	_check(not ignored["hit"], "KO dummy: Hp changed to %s, expected to stay 0" % dummy.Hp)
	_check(is_equal_approx(dummy.Hp, 0.0), "KO dummy: Hp=%s after a further hit, expected 0" % dummy.Hp)
	_check(ignored["min_scale"] == 1.0, "KO dummy: Engine.time_scale dropped to %s, expected no hit-stop (TakeHit returned false)" % ignored["min_scale"])
	_check(dummy.CurrentStateName == "KO", "KO dummy: state '%s' after a further hit, expected 'KO'" % dummy.CurrentStateName)
	_check(is_equal_approx(dvisual.rotation, PI / 2.0), "KO dummy: Visual.rotation=%.3f after a further hit, expected PI/2 (stays down)" % dvisual.rotation)
	await _step(5)
	_check(player.CurrentStateName == "Idle", "KO dummy: player state '%s' after the swing, expected 'Idle'" % player.CurrentStateName)
	_check(_transitions == ["LightAttack1", "Idle"], "KO dummy: transitions %s, expected [LightAttack1, Idle]" % [_transitions])

	# 6. Heavy knockdown on a healthy target (Dummy2, 25 HP) at the same depth: Down (rotated),
	#    HP 13, pushed right, then Idle and upright after DownDuration.
	_transitions.clear()
	player.position = Vector2(720, DUMMY2_START.y)
	await _step(2)
	var d2_x: float = dummy2.position.x
	await _tap("heavy_attack")
	var hd2: Dictionary = await _watch_hit(dummy2, HIT_CAP_MS)
	_check("HeavyAttack" in _transitions, "heavy down: no transition into HeavyAttack (transitions %s)" % [_transitions])
	_check(hd2["hit"], "heavy down: Dummy2 not hit within %d ms (Hp=%s)" % [HIT_CAP_MS, dummy2.Hp])
	if hd2["hit"]:
		_check(hd2["scale"] == 0.0, "heavy down: Engine.time_scale=%s right after the hit, expected 0" % hd2["scale"])
		_check(hd2["state"] == "Down", "heavy down: Dummy2 state '%s' right after the hit, expected 'Down'" % hd2["state"])
	var down_elapsed: int = await _wait_restored(RESTORE_CAP_MS)
	_check(down_elapsed >= 0, "heavy down: Engine.time_scale not restored within %d ms" % RESTORE_CAP_MS)
	var heavy_bound_ms: int = int((float(heavy_frames) / float(Engine.physics_ticks_per_second) + 0.1) * 1000.0)
	_check(down_elapsed < 0 or down_elapsed <= heavy_bound_ms, "heavy down: hit-stop lasted %d ms, expected <= %d ms (%d frames)" % [down_elapsed, heavy_bound_ms, heavy_frames])
	await _real_wait(0.2)
	await _step(5)
	_check(dummy2.CurrentStateName == "Down", "heavy down: Dummy2 state '%s', expected 'Down'" % dummy2.CurrentStateName)
	_check(is_equal_approx(dummy2.Hp, 13.0), "heavy down: Dummy2.Hp=%s, expected 13" % dummy2.Hp)
	_check(is_equal_approx(d2visual.rotation, PI / 2.0), "heavy down: Dummy2 Visual.rotation=%.3f, expected PI/2" % d2visual.rotation)
	_check(dummy2.position.x > d2_x, "heavy down: Dummy2.x=%.2f, expected > %.2f (pushed right)" % [dummy2.position.x, d2_x])
	_check(dummy2.IsKnockedOut == false, "heavy down: Dummy2 knocked out at 13 HP")
	await _step(75)   # DownDuration 1 s = 60 physics frames
	_check(dummy2.CurrentStateName == "Idle", "heavy down: Dummy2 state '%s' after 75 frames, expected 'Idle' (got up)" % dummy2.CurrentStateName)
	_check(is_equal_approx(d2visual.rotation, 0.0), "heavy down: Dummy2 Visual.rotation=%.3f after getting up, expected 0" % d2visual.rotation)
	_check(d2visual.modulate.is_equal_approx(Color.WHITE), "heavy down: Dummy2 Visual.modulate=%s after getting up, expected white" % d2visual.modulate)
	_check(player.CurrentStateName == "Idle", "heavy down: player state '%s' at the end, expected 'Idle'" % player.CurrentStateName)
	_check(Engine.time_scale == 1.0, "heavy down: Engine.time_scale=%s at the end, expected 1" % Engine.time_scale)

	# 7. Hero Hurt / KO states (dummies never attack; Player.TakeHit needs a C# HitInfo, so only
	#    the states are driven here): Hurt returns to Idle, KO stays. Energy untouched so far.
	_check(is_equal_approx(gs.Energy, gs.MaxEnergy), "hero: Energy=%s after the dummy fights, expected MaxEnergy=%s (dummies never hit)" % [gs.Energy, gs.MaxEnergy])
	_transitions.clear()
	sm.TransitionTo("Hurt")
	await _step(1)
	_check(player.CurrentStateName == "Hurt", "hero: state '%s' after TransitionTo(Hurt), expected 'Hurt'" % player.CurrentStateName)
	await _step(25)   # hurt animation 0.30 s = 18 frames
	_check(player.CurrentStateName == "Idle", "hero: state '%s' 25 frames after Hurt, expected 'Idle'" % player.CurrentStateName)
	_check(_transitions == ["Hurt", "Idle"], "hero: transitions %s, expected [Hurt, Idle]" % [_transitions])
	sm.TransitionTo("KO")
	await _step(1)
	_check(player.CurrentStateName == "KO", "hero: state '%s' after TransitionTo(KO), expected 'KO'" % player.CurrentStateName)
	await _step(20)
	_check(player.CurrentStateName == "KO", "hero: state '%s' 20 frames after KO, expected to stay 'KO'" % player.CurrentStateName)

	# 8. Teardown.
	gs.ResetRun()
	room.queue_free()
	await _step(1)
	_finish()
