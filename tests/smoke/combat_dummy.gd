extends SceneTree
# Smoke: basic combat (T-02b) — attack states + exports, Dummy scene/script, single light attack
# (hit-stop, flash, knockback, Hurt), three-hit light combo, hitbox depth tolerance (miss at
# |dy| = 20, hit at |dy| = DepthTolerance inclusive), heavy knockdown (Down → Idle after
# DownDuration), KO at 0 HP and ignored hits afterwards, hero Hurt/KO states. Needs physics frames.
# Review fix-pass regressions (sections 8+, in a fresh room): HitStop autoload (S4), `attack`
# pressed during the hit-stop chains into LightAttack2 (S2), a Down dummy is invulnerable — a
# second heavy while it lies is ignored and it gets up on the first knockdown's DownDuration
# (T-B01, section 11, replacing the earlier "restart DownDuration" S3 check), a facing-left hit,
# a hit taken mid-jump falls before Idle (S1), and Player.TakeDamage -> Energy / Hurt signal /
# KO / ignored after KO (S6).
# Review #1 fix-pass (T-03r): the combo is chained by AnimationTime / Hitbox.IsActive read from the
# running attack state, never by a wall-clock wait (S4); a second hit 8 frames into the hero's Hurt
# rewinds the stun so Idle comes no earlier than ~18 frames after the second hit (S1).
# Run: godot --headless --path . -s tests/smoke/combat_dummy.gd
#
# Hit-stop sets Engine.time_scale = 0, which stops physics frames (awaiting `physics_frame` hangs
# until the restore), so hits are observed on idle frames (`process_frame`, which keep running)
# under a wall-clock cap, and the restore is awaited in real time. Everything else is counted in
# physics frames.

const NAME := "combat_dummy"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls; the
# real-time waits around each hit-stop cost idle frames too, so this is roomier than usual.
const MAX_FRAMES := 12000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack"]
const HIT_CAP_MS := 800        # wall-clock cap while waiting for one hit to land
const NO_HIT_WINDOW_MS := 450  # longer than the light animation (0.30 s) — a miss must stay a miss
const RESTORE_CAP_MS := 1000   # wall-clock cap while waiting for hit-stop to lift
const COMBO_WINDOW_CAP := 30   # physics frames allowed for an attack's combo window to open (anim 0.30 s = 18)
const HURT_IDLE_CAP := 60      # physics frames allowed for Hurt -> Idle after a hit (anim 0.30 s = 18)
const HURT_RESTART_MIN := 17   # frames the second Hurt must last (18 at 60 Hz; 17 allows frame alignment)
const SETTLE_CAP := 10         # idle frames allowed for the post-load physics catch-up to end (2-3 in practice)
const SETTLE_DELTA := 0.05     # process delta (s) below which the loop is back to normal pacing (16.7 ms at 60 Hz)
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

# Instantiating TestRoom (~100 ms of C# instancing) makes the next iteration run 6-8 physics
# steps back-to-back; a physics-frame countdown started right after add_child ends inside that
# burst, and the burst's process delta (the whole stall) becomes the first step of the idle-mode
# AnimationPlayer and of the Dummy's flash tween. Wait until the process delta is normal again.
func _settle() -> void:
	for i in SETTLE_CAP:
		await process_frame
		if root.get_process_delta_time() < SETTLE_DELTA:
			return

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

# S4: waits (physics frames) until the attack `state_name` is the current state AND its combo window
# is open — `Player.AnimationTime >= ComboWindowStart` (read from the state node's export) or the
# Hitbox is active — exactly the condition PlayerAttack buffers a press on. Returns true when the
# next `attack` press is guaranteed to chain; fails explicitly (and returns false) if the hero is
# already back in Idle or the cap passes, naming the observed state and animation time.
func _wait_combo_window(player: Node, sm: Node, hitbox: Node, state_name: String, label: String) -> bool:
	var st: Node = sm.get_node_or_null(state_name)
	if st == null or st.get("ComboWindowStart") == null:
		_check(false, "%s: attack state '%s' missing or without a ComboWindowStart export" % [label, state_name])
		return false
	var window_start: float = st.ComboWindowStart
	for i in COMBO_WINDOW_CAP:
		var cur: String = player.CurrentStateName
		var t: float = player.AnimationTime
		if cur == state_name and (t >= window_start or hitbox.IsActive):
			return true
		if cur == "Idle":
			_check(false, "%s: hero already in 'Idle' %d frames after the restore (AnimationTime=%.3f) — the combo window of '%s' (ComboWindowStart %.2f) was missed" % [label, i, t, state_name, window_start])
			return false
		await physics_frame
	_check(false, "%s: combo window of '%s' not open within %d frames (state '%s', AnimationTime=%.3f, ComboWindowStart %.2f, Hitbox.IsActive=%s)" % [label, state_name, COMBO_WINDOW_CAP, player.CurrentStateName, player.AnimationTime, window_start, hitbox.IsActive])
	return false

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
	await _settle()

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
	_check(dummy.get_node_or_null("Visual/Hurtbox") != null, "Dummy has no 'Visual/Hurtbox' Area2D (Hitbox looks it up by name; it lives under Visual so it rises with a jump)")
	for s in ["Idle", "LightAttack1", "LightAttack2", "LightAttack3", "HeavyAttack", "Hurt", "KO"]:
		_check(sm.HasState(s), "Player StateMachine lacks state '%s'" % s)
	for s in ["Idle", "Hurt", "Down", "KO"]:
		_check(dsm.HasState(s), "Dummy StateMachine lacks state '%s'" % s)
	# Attack exports as documented in the plan (L1 5 / L2 5 / L3 8 / Heavy 12 knockdown); heavy
	# hit-stop 5 frames per GAME_DESIGN §6 (3-5 frames, review S5).
	var expected_attacks := {"LightAttack1": [5.0, false, 4], "LightAttack2": [5.0, false, 4],
		"LightAttack3": [8.0, false, 5], "HeavyAttack": [12.0, true, 5]}
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
	#    hit-stop on every hit and time scale restored at the end. S4 (review #1): the next press
	#    waits for the running attack's combo window (AnimationTime >= ComboWindowStart or Hitbox
	#    active) in physics frames — no wall-clock margin.
	_transitions.clear()
	var combo: Array = [[20.0, l1_frames, "LightAttack1"], [15.0, l2_frames, "LightAttack2"], [7.0, l3_frames, "LightAttack3"]]
	var combo_press_times: Array = []
	for i in combo.size():
		var h: Dictionary = await _light_hit(dummy, "combo hit %d" % (i + 1), combo[i][0], combo[i][1])
		if not h["hit"]:
			break
		if i + 1 < combo.size():
			var open: bool = await _wait_combo_window(player, sm, hitbox, combo[i][2], "combo hit %d -> %d" % [i + 1, i + 2])
			if not open:
				break
			combo_press_times.append("%s@%.3f" % [player.CurrentStateName, player.AnimationTime])
	print("combat_dummy: combo presses at %s" % [combo_press_times])
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

	# 8. Fresh room for the review fix-pass regressions: the old room's hero is KO and its dummies
	#    are spent (Dummy 0 HP, Dummy2 13 HP). Both dummies back at 30 HP, hero Idle, Energy Max.
	room.queue_free()
	gs.ResetRun()
	await _step(1)
	room = scene.instantiate()
	root.add_child(room)
	await _settle()
	player = room.get_node_or_null("Player")
	dummy = room.get_node_or_null("Dummy")
	dummy2 = room.get_node_or_null("Dummy2")
	if player == null or dummy == null or dummy2 == null:
		_check(false, "fresh room: Player/Dummy/Dummy2 missing after re-instantiating TestRoom")
		if room != null:
			room.queue_free()
		_finish()
		return
	sm = player.get_node_or_null("StateMachine")
	hitbox = player.get_node_or_null("Visual/Hitbox")
	dvisual = dummy.get_node_or_null("Visual")
	d2visual = dummy2.get_node_or_null("Visual")
	var pvisual: Node2D = player.get_node_or_null("Visual")
	if sm == null or hitbox == null or dvisual == null or d2visual == null or pvisual == null:
		_check(false, "fresh room: StateMachine/Visual/Hitbox missing on the re-instantiated actors")
		room.queue_free()
		_finish()
		return
	# Player re-emits its StateMachine's transitions (Player.StateChanged); record both and compare.
	_transitions.clear()
	var sm_transitions: Array = []
	player.StateChanged.connect(func(_from: String, to: String): _transitions.append(to))
	sm.StateChanged.connect(func(_from: String, to: String): sm_transitions.append(to))
	var hurt_events: Array = []
	var ko_events: Array = []
	player.Hurt.connect(func(d: float): hurt_events.append(d))
	player.KnockedOut.connect(func(): ko_events.append(true))
	await _step(2)
	_check(player.CurrentStateName == "Idle", "fresh room: player state '%s', expected 'Idle'" % player.CurrentStateName)
	_check(is_equal_approx(dummy.Hp, 30.0) and is_equal_approx(dummy2.Hp, 30.0), "fresh room: Dummy.Hp=%s Dummy2.Hp=%s, expected 30/30" % [dummy.Hp, dummy2.Hp])
	_check(is_equal_approx(gs.Energy, gs.MaxEnergy), "fresh room: Energy=%s, expected MaxEnergy" % gs.Energy)
	_check(Engine.time_scale == 1.0, "fresh room: Engine.time_scale=%s, expected 1" % Engine.time_scale)

	# 9. S4: HitStop is an autoload (project.godot [autoload]), not a self-installed root node.
	_check(root.get_node_or_null("HitStop") != null, "S4: 'HitStop' autoload not in the tree (project.godot [autoload])")

	# 10. S2 regression: `attack` pressed DURING the hit-stop of light_1 must chain into
	#     LightAttack2 (the combo buffer opens with the hit window, not only at ComboWindowStart).
	_transitions.clear()
	player.position = Vector2(600, 450)
	await _step(2)
	_check(player.CurrentStateName == "Idle", "S2: player state '%s' before the attack, expected 'Idle'" % player.CurrentStateName)
	var s2_hp0: float = dummy.Hp
	await _tap("attack")
	var s2_froze := false
	var s2_deadline: int = Time.get_ticks_msec() + HIT_CAP_MS
	while Time.get_ticks_msec() < s2_deadline:
		await process_frame
		if Engine.time_scale == 0.0:
			s2_froze = true
			break
	_check(s2_froze, "S2: no hit-stop within %d ms (Dummy.Hp=%s, state '%s')" % [HIT_CAP_MS, dummy.Hp, player.CurrentStateName])
	if s2_froze:
		_check(player.CurrentStateName == "LightAttack1", "S2: player state '%s' during the freeze, expected 'LightAttack1'" % player.CurrentStateName)
		_check(hitbox.IsActive, "S2: Hitbox not active during the hit-stop of light_1")
		# S4 (review #1): press inside the freeze (verified synchronously — no idle frame in between)
		# and hold it until the first physics frame after the restore, i.e. the frame on which the
		# attack state polls it. No wall-clock margin decides whether the press was seen.
		Input.action_press("attack")
		_check(Engine.time_scale == 0.0, "S2: freeze already lifted at the moment of the press")
		var s2_press_time: float = player.AnimationTime
		await physics_frame
		Input.action_release("attack")
		_check(player.CurrentStateName == "LightAttack1", "S2: player state '%s' on the first physics frame after the freeze, expected still 'LightAttack1' (AnimationTime=%.3f)" % [player.CurrentStateName, player.AnimationTime])
		_check(player.AnimationTime >= s2_press_time, "S2: AnimationTime went backwards over the freeze (%.3f -> %.3f)" % [s2_press_time, player.AnimationTime])
	var s2_elapsed: int = await _wait_restored(RESTORE_CAP_MS)
	_check(s2_elapsed >= 0, "S2: Engine.time_scale not restored within %d ms" % RESTORE_CAP_MS)
	await _step(40)   # rest of light_1 (~13 frames) + light_2 (18 frames) + Idle
	var s2_i1: int = _transitions.find("LightAttack1")
	var s2_i2: int = _transitions.find("LightAttack2")
	_check(s2_i1 >= 0 and s2_i2 > s2_i1, "S2: transitions %s, expected LightAttack2 after LightAttack1 (press during the freeze must chain)" % [_transitions])
	var s2_delta: float = s2_hp0 - dummy.Hp
	print("combat_dummy: S2 Dummy.Hp delta = %s (transitions %s)" % [s2_delta, _transitions])
	_check(s2_delta >= 5.0, "S2: Dummy.Hp delta %s, expected >= 5 (10 when light_2 connects)" % s2_delta)
	_check(player.CurrentStateName == "Idle", "S2: player state '%s' after 40 frames, expected 'Idle'" % player.CurrentStateName)
	_check(Engine.time_scale == 1.0, "S2: Engine.time_scale=%s at the end, expected 1" % Engine.time_scale)
	_check(_transitions == sm_transitions, "Player.StateChanged %s differs from StateMachine.StateChanged %s" % [_transitions, sm_transitions])

	# 11. T-B01 (SoR rule, replaces the S3 "restart DownDuration" check): a Down dummy is
	#     invulnerable. Dummy2 (30 HP): 18 after the first heavy; a second heavy while it lies is
	#     ignored (no Hp change, no hit-stop) and it gets up on the first knockdown's DownDuration.
	_transitions.clear()
	player.position = Vector2(DUMMY2_START.x - 40.0, DUMMY2_START.y)
	await _step(2)
	_check(player.CurrentStateName == "Idle", "S3: player state '%s' before the first heavy, expected 'Idle'" % player.CurrentStateName)
	await _tap("heavy_attack")
	var s3a: Dictionary = await _watch_hit(dummy2, HIT_CAP_MS)
	_check(s3a["hit"], "S3: first heavy did not hit Dummy2 within %d ms (Hp=%s)" % [HIT_CAP_MS, dummy2.Hp])
	if s3a["hit"]:
		_check(s3a["state"] == "Down", "S3: Dummy2 state '%s' after the first heavy, expected 'Down'" % s3a["state"])
	var s3a_restore: int = await _wait_restored(RESTORE_CAP_MS)
	_check(s3a_restore >= 0, "S3: Engine.time_scale not restored after the first heavy within %d ms" % RESTORE_CAP_MS)
	await _step(20)
	_check(dummy2.CurrentStateName == "Down", "S3: Dummy2 state '%s' 20 frames after the first heavy, expected 'Down'" % dummy2.CurrentStateName)
	_check(is_equal_approx(dummy2.Hp, 18.0), "S3: Dummy2.Hp=%s after the first heavy, expected 18" % dummy2.Hp)
	var s3_player_idle := false
	for i in 20:   # the heavy animation (0.55 s) ends ~20 frames after its hit
		if player.CurrentStateName == "Idle":
			s3_player_idle = true
			break
		await physics_frame
	_check(s3_player_idle, "S3: player state '%s' after the first heavy, expected 'Idle' within 40 frames" % player.CurrentStateName)
	# Keep the hero in range for the second heavy (knockback moved Dummy2 right).
	player.position = Vector2(dummy2.position.x - 40.0, dummy2.position.y)
	await _step(2)
	_check(dummy2.position.x - player.position.x <= 60.0, "S3: Dummy2 %.1f px ahead of the hero, expected <= 60 (in range)" % (dummy2.position.x - player.position.x))
	_check(dummy2.CurrentStateName == "Down", "S3: Dummy2 state '%s' right before the second heavy, expected still 'Down'" % dummy2.CurrentStateName)
	await _tap("heavy_attack")
	# The heavy's hit window (0.22-0.36 s) opens ~40 frames after the first knockdown, well inside
	# DownDuration (60 frames): the hit must be ignored — no Hp change, no hit-stop.
	var s3b: Dictionary = await _watch_hit(dummy2, NO_HIT_WINDOW_MS)
	_check(not s3b["hit"], "T-B01: second heavy hit the Down Dummy2 (Hp=%s), expected the hit to be ignored while it lies" % dummy2.Hp)
	_check(s3b["min_scale"] == 1.0, "T-B01: Engine.time_scale dropped to %s during the ignored heavy, expected no hit-stop" % s3b["min_scale"])
	_check(is_equal_approx(dummy2.Hp, 18.0), "T-B01: Dummy2.Hp=%s after the ignored heavy, expected still 18" % dummy2.Hp)
	_check(dummy2.IsKnockedOut == false, "T-B01: Dummy2 knocked out at 18 HP")
	# It gets up on the FIRST knockdown's DownDuration — the ignored hit restarts nothing.
	var s3_getup_cap := 45
	var s3_up_after: int = -1
	for i in s3_getup_cap:
		if dummy2.CurrentStateName == "Idle":
			s3_up_after = i
			break
		await physics_frame
	_check(s3_up_after >= 0, "T-B01: Dummy2 state '%s' %d frames after the ignored heavy, expected 'Idle' (got up on the original DownDuration)" % [dummy2.CurrentStateName, s3_getup_cap])
	_check(is_equal_approx(d2visual.rotation, 0.0), "S3: Dummy2 Visual.rotation=%.3f after getting up, expected 0" % d2visual.rotation)
	_check(is_equal_approx(dummy2.Hp, 18.0), "T-B01: Dummy2.Hp=%s after getting up, expected 18" % dummy2.Hp)
	var s3_player_idle_end := false
	for i in 20:   # the second heavy animation (0.55 s) may still be finishing
		if player.CurrentStateName == "Idle":
			s3_player_idle_end = true
			break
		await physics_frame
	_check(s3_player_idle_end, "S3: player state '%s' at the end, expected 'Idle' within 20 frames" % player.CurrentStateName)
	_check(Engine.time_scale == 1.0, "S3: Engine.time_scale=%s at the end, expected 1" % Engine.time_scale)
	print("combat_dummy: T-B01 second heavy on the Down Dummy2 ignored (Hp %s), up %d frames after the no-hit window" % [dummy2.Hp, s3_up_after])

	# 12. Facing-left hit: hero to the RIGHT of Dummy (healthy, 20 HP after S2), faces left after a
	#     2-frame move_left, the flipped hitbox lands and the knockback pushes the dummy LEFT.
	_transitions.clear()
	var fl_hp0: float = dummy.Hp
	var fl_x0: float = dummy.position.x
	player.position = Vector2(dummy.position.x + 40.0, dummy.position.y)
	await _step(2)
	Input.action_press("move_left")
	await _step(2)
	Input.action_release("move_left")
	await _step(2)
	_check(player.Facing == -1, "facing-left: Facing=%s after move_left, expected -1" % player.Facing)
	_check(pvisual.scale.x == -1.0, "facing-left: Visual.scale=%s, expected (-1, 1)" % pvisual.scale)
	_check(player.CurrentStateName == "Idle", "facing-left: player state '%s' before the attack, expected 'Idle'" % player.CurrentStateName)
	_check(player.position.x > dummy.position.x, "facing-left: hero x=%.1f not to the right of Dummy x=%.1f" % [player.position.x, dummy.position.x])
	var hfl: Dictionary = await _light_hit(dummy, "facing-left", fl_hp0 - 5.0, l1_frames)
	_check(hfl["hit"] and is_equal_approx(dummy.Hp, fl_hp0 - 5.0), "facing-left: Dummy.Hp=%s, expected %s" % [dummy.Hp, fl_hp0 - 5.0])
	await _step(30)
	_check(dummy.position.x < fl_x0, "facing-left: Dummy.x=%.2f, expected < %.2f (pushed left)" % [dummy.position.x, fl_x0])
	_check(dummy.CurrentStateName == "Idle", "facing-left: Dummy state '%s' after 30 frames, expected 'Idle'" % dummy.CurrentStateName)
	_check(player.CurrentStateName == "Idle", "facing-left: player state '%s' after the hit, expected 'Idle'" % player.CurrentStateName)
	_check(_transitions == ["Move", "Idle", "LightAttack1", "Idle"], "facing-left: transitions %s, expected [Move, Idle, LightAttack1, Idle]" % [_transitions])

	# 13. S1 regression: a hit taken mid-jump — Hurt keeps falling, lands, then returns to Idle
	#     with the visual back on the feet (no floating hero). 0 hit-stop frames so physics runs.
	_transitions.clear()
	hurt_events.clear()
	player.position = Vector2(400, 450)
	await _step(2)
	_check(player.CurrentStateName == "Idle", "S1: player state '%s' before the jump, expected 'Idle'" % player.CurrentStateName)
	await _tap("jump")
	await _step(8)
	_check(player.CurrentStateName == "Jump", "S1: player state '%s' 8 frames after jump, expected 'Jump'" % player.CurrentStateName)
	_check(player.Height > 0.0 and player.IsAirborne, "S1: Height=%.2f IsAirborne=%s 8 frames after jump, expected airborne" % [player.Height, player.IsAirborne])
	var s1_height: float = player.Height
	var s1_took: bool = player.TakeDamage(5.0, -80.0, false, 0)
	_check(s1_took == true, "S1: TakeDamage returned %s, expected true" % s1_took)
	_check(player.CurrentStateName == "Hurt", "S1: player state '%s' right after TakeDamage mid-jump, expected 'Hurt'" % player.CurrentStateName)
	_check(hurt_events == [5.0], "S1: Hurt signal events %s, expected [5.0]" % [hurt_events])
	_check(is_equal_approx(gs.Energy, gs.MaxEnergy - 5.0), "S1: Energy=%s, expected MaxEnergy-5=%s" % [gs.Energy, gs.MaxEnergy - 5.0])
	var s1_landed := false
	var s1_fall_frames := 0
	for i in 120:
		await physics_frame
		s1_fall_frames += 1
		if player.Height == 0.0:
			s1_landed = true
			break
	_check(s1_landed, "S1: Height=%.2f (was %.2f at the hit) still > 0 after 120 frames in '%s' — hero hangs in the air" % [player.Height, s1_height, player.CurrentStateName])
	_check(player.IsAirborne == false, "S1: IsAirborne=%s after landing, expected false" % player.IsAirborne)
	var s1_idle_after: int = -1
	for i in 30:
		if player.CurrentStateName == "Idle":
			s1_idle_after = i
			break
		await physics_frame
	_check(s1_idle_after >= 0, "S1: player state '%s' 30 frames after landing, expected 'Idle'" % player.CurrentStateName)
	_check(is_equal_approx(pvisual.position.y, -player.SpriteFeetOffset), "S1: Visual.position.y=%.2f after landing, expected %.2f (-SpriteFeetOffset)" % [pvisual.position.y, -player.SpriteFeetOffset])
	_check(player.Height == 0.0, "S1: Height=%.2f at the end, expected 0" % player.Height)
	_check(_transitions == ["Jump", "Hurt", "Idle"], "S1: transitions %s, expected [Jump, Hurt, Idle]" % [_transitions])
	_check(hurt_events.size() == 1, "S1: Hurt signal fired %d times, expected once" % hurt_events.size())
	print("combat_dummy: S1 hit at Height %.2f, landed %d frames later, Idle %d frames after landing" % [s1_height, s1_fall_frames, s1_idle_after])

	# 14. S1 (review #1) regression: a second hit 8 frames into the hero's Hurt re-enters the state
	#     (TransitionToOrRestart) AND rewinds the `hurt` animation, so Idle comes no earlier than
	#     ~18 frames (0.30 s) after the SECOND hit. Pre-fix Play() kept the position and the hero
	#     was back in Idle 11 frames after the second hit.
	gs.ResetRun()
	hurt_events.clear()
	_transitions.clear()
	await _step(2)
	_check(player.CurrentStateName == "Idle", "hurt restart: player state '%s' before the first hit, expected 'Idle'" % player.CurrentStateName)
	var hr_r1: bool = player.TakeDamage(2.0, 0.0, false, 0)
	_check(hr_r1 == true, "hurt restart: first TakeDamage returned %s, expected true" % hr_r1)
	_check(player.CurrentStateName == "Hurt", "hurt restart: player state '%s' after the first hit, expected 'Hurt'" % player.CurrentStateName)
	await _step(8)
	_check(player.CurrentStateName == "Hurt", "hurt restart: player state '%s' 8 frames into the first Hurt, expected still 'Hurt'" % player.CurrentStateName)
	var hr_t_before: float = player.AnimationTime
	_check(hr_t_before > 0.05, "hurt restart: AnimationTime=%.3f 8 frames into the first Hurt, expected > 0.05 (the hurt animation must be running)" % hr_t_before)
	var hr_r2: bool = player.TakeDamage(2.0, 0.0, false, 0)
	_check(hr_r2 == true, "hurt restart: second TakeDamage returned %s, expected true" % hr_r2)
	_check(player.CurrentStateName == "Hurt", "hurt restart: player state '%s' right after the second hit, expected 'Hurt'" % player.CurrentStateName)
	var hr_t_after: float = player.AnimationTime
	_check(hr_t_after < hr_t_before, "hurt restart: AnimationTime %.3f -> %.3f over the second hit, expected a rewind (Hurt re-entry must restart the stun)" % [hr_t_before, hr_t_after])
	var hr_idle_after: int = -1
	for i in HURT_IDLE_CAP:
		await physics_frame
		if player.CurrentStateName == "Idle":
			hr_idle_after = i + 1
			break
	_check(hr_idle_after >= 0, "hurt restart: player state '%s' %d frames after the second hit, expected 'Idle' within the cap" % [player.CurrentStateName, HURT_IDLE_CAP])
	_check(hr_idle_after < 0 or hr_idle_after >= HURT_RESTART_MIN, "hurt restart: Idle observed %d frames after the second hit, expected >= %d (hurt animation 0.30 s = 18 frames; the second hit must restart it, pre-fix: 11)" % [hr_idle_after, HURT_RESTART_MIN])
	_check(is_equal_approx(gs.Energy, gs.MaxEnergy - 4.0), "hurt restart: Energy=%s after two 2-damage hits, expected MaxEnergy-4=%s" % [gs.Energy, gs.MaxEnergy - 4.0])
	_check(hurt_events == [2.0, 2.0], "hurt restart: Hurt signal events %s, expected [2.0, 2.0]" % [hurt_events])
	_check(_transitions == ["Hurt", "Idle"], "hurt restart: transitions %s, expected [Hurt, Idle] (a restart emits no StateChanged)" % [_transitions])
	print("combat_dummy: hurt restart — AnimationTime %.3f -> %.3f at the second hit, Idle %d frames after it" % [hr_t_before, hr_t_after, hr_idle_after])

	# 15. S6: Player.TakeDamage (Variant-friendly TakeHit) — Energy -10, Hurt facing the hit,
	#     knockback velocity, back to Idle; lethal damage -> KO once (signal, MinEnergy); a further
	#     hit is ignored (false, Energy unchanged, still KO).
	gs.ResetRun()
	hurt_events.clear()
	_transitions.clear()
	await _step(2)
	_check(player.CurrentStateName == "Idle", "S6: player state '%s' before TakeDamage, expected 'Idle'" % player.CurrentStateName)
	_check(ko_events.is_empty(), "S6: KnockedOut already fired %d times before the lethal hit" % ko_events.size())
	var s6_x0: float = player.position.x
	var s6_r1: bool = player.TakeDamage(10.0, 120.0, false, 0)
	_check(s6_r1 == true, "S6: TakeDamage(10, 120) returned %s, expected true" % s6_r1)
	_check(is_equal_approx(gs.Energy, gs.MaxEnergy - 10.0), "S6: Energy=%s after 10 damage, expected MaxEnergy-10=%s" % [gs.Energy, gs.MaxEnergy - 10.0])
	_check(player.CurrentStateName == "Hurt", "S6: player state '%s' after TakeDamage, expected 'Hurt'" % player.CurrentStateName)
	_check(player.Facing == -1, "S6: Facing=%s after a knockback to the right, expected -1 (faces the hit)" % player.Facing)
	_check(pvisual.scale.x == -1.0, "S6: Visual.scale=%s after the hit, expected (-1, 1)" % pvisual.scale)
	await _step(1)
	_check(player.velocity.x > 0.0, "S6: velocity.x=%.1f on the next frame, expected > 0 (knockback to the right)" % player.velocity.x)
	await _step(30)
	_check(player.CurrentStateName == "Idle", "S6: player state '%s' 30 frames after Hurt, expected 'Idle'" % player.CurrentStateName)
	_check(player.position.x > s6_x0, "S6: hero x=%.2f after the knockback, expected > %.2f" % [player.position.x, s6_x0])
	_check(hurt_events == [10.0], "S6: Hurt signal events %s, expected [10.0]" % [hurt_events])
	_check(ko_events.is_empty(), "S6: KnockedOut fired on a non-lethal hit")
	var s6_lethal: float = gs.Energy + 1.0
	var s6_r2: bool = player.TakeDamage(s6_lethal, 0.0, false, 0)
	_check(s6_r2 == true, "S6: lethal TakeDamage(%s) returned %s, expected true" % [s6_lethal, s6_r2])
	_check(player.IsKnockedOut == true, "S6: IsKnockedOut=%s after lethal damage, expected true" % player.IsKnockedOut)
	_check(player.CurrentStateName == "KO", "S6: player state '%s' after lethal damage, expected 'KO'" % player.CurrentStateName)
	_check(ko_events.size() == 1, "S6: KnockedOut fired %d times, expected once" % ko_events.size())
	_check(is_equal_approx(gs.Energy, gs.MinEnergy), "S6: Energy=%s after lethal damage, expected MinEnergy=%s" % [gs.Energy, gs.MinEnergy])
	_check(hurt_events.size() == 2, "S6: Hurt signal fired %d times after the lethal hit, expected 2" % hurt_events.size())
	await _step(20)
	_check(player.CurrentStateName == "KO", "S6: player state '%s' 20 frames after KO, expected still 'KO'" % player.CurrentStateName)
	var s6_energy_ko: float = gs.Energy
	var s6_r3: bool = player.TakeDamage(1.0, 0.0, false, 0)
	_check(s6_r3 == false, "S6: TakeDamage after KO returned %s, expected false" % s6_r3)
	_check(gs.Energy == s6_energy_ko, "S6: Energy=%s after an ignored hit, expected unchanged %s" % [gs.Energy, s6_energy_ko])
	_check(player.CurrentStateName == "KO", "S6: player state '%s' after an ignored hit, expected 'KO'" % player.CurrentStateName)
	_check(hurt_events.size() == 2 and ko_events.size() == 1, "S6: Hurt/KnockedOut fired %d/%d times after the ignored hit, expected 2/1" % [hurt_events.size(), ko_events.size()])
	_check(_transitions == ["Hurt", "Idle", "KO"], "S6: transitions %s, expected [Hurt, Idle, KO]" % [_transitions])

	# 15a. ResetPose() must leave a current animation (AnimationTime readable, no ERROR line)
	#      and return the placeholder fist to its rest position.
	sm.TransitionTo("Idle")
	await _step(2)
	player.ResetPose()
	var t_after_reset: float = player.AnimationTime
	_check(t_after_reset == 0.0, "AnimationTime after ResetPose() = %s, expected 0" % t_after_reset)
	var fist: Node2D = player.get_node("Visual/PH_Fist")
	_check(fist.position.is_equal_approx(Vector2(14, -10)), "PH_Fist after ResetPose() at %s, expected (14, -10)" % fist.position)

	# 16. Teardown: reset the run, make sure no freeze is pending, free the room.
	gs.ResetRun()
	if Engine.time_scale != 1.0:
		var tear_restore: int = await _wait_restored(RESTORE_CAP_MS)
		_check(tear_restore >= 0, "teardown: Engine.time_scale not restored within %d ms" % RESTORE_CAP_MS)
	room.queue_free()
	await _step(1)
	print("combat_dummy: idle frames used %d of MAX_FRAMES %d" % [_frames, MAX_FRAMES])
	_finish()
