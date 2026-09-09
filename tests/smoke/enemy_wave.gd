extends SceneTree
# Smoke: WaveSpawner (T-06) — WaveSpawner.tscn wiring (script, trigger layers, export defaults,
# Guard as EnemyScene, GO label hidden), its TestRoom instance (Count 3, SpawnAware, three
# markers, Player/Director/Camera wired, LockRect), then one full wave: the hero walking into
# the trigger emits WaveStarted, three Guards spawn at the marker positions within
# Count * SpawnInterval, already aware and targeting the hero, the camera limits equal LockRect
# while locked; over 300 physics frames with the hero in their reach at most two guards hold an
# attack slot / stand in Attack at once (EnemyDirector.MaxAttackers 2) while the third settles at
# HoldDistance; knocking all three out emits WaveCleared, shows "GO →", restores the camera limits
# the spawner saved at the trigger, hides GO after GoDuration, and a OneShot wave does not restart
# when the hero walks through again. A second room with SpawnAware = false: the guards spawn
# unaware, Idle and facing the unlit hero, and all notice it within 5 frames of the lamp going on.
# Run: godot --headless --path . -s tests/smoke/enemy_wave.gd
#
# The room takes ~130 ms to instance and Godot catches up with several physics steps in ONE
# iteration afterwards, so the room gets two idle frames before the first physics step. Guard
# punches trigger hit-stops (Engine.time_scale = 0); the sampling loop counts physics frames and
# simply takes longer while frozen. Hits are not observed here beyond a count.

const NAME := "enemy_wave"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s). Counts _process calls;
# headless runs ~150 idle frames per second.
const MAX_FRAMES := 9000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "flashlight"]
const ROOM_PATH := "res://scenes/levels/TestRoom.tscn"
const SPAWNER_PATH := "res://scenes/core/WaveSpawner.tscn"
const TRIGGER_CAP := 120         # physics frames allowed for the walk from x=850 into the trigger (x >= 900)
const SAMPLE_FRAMES := 300       # physics frames sampled for the "max 2 attackers" rule (plan: 5 s)
const CLEAR_CAP := 5             # physics frames allowed for WaveCleared after the last KO (it is synchronous)
const GO_MARGIN := 0.2           # real seconds added to GoDuration before asserting GO hidden
const REFILL_BELOW := 30.0       # keep the hero alive during the sampling (a punch drains 8)
const HOLD_TOLERANCE := 10.0     # |dx| band around HoldDistance that counts as "settled at the hold point"
# The holder is usually the guard that just finished its own punch at AttackRange (45 px) and is
# walking back out to HoldDistance (120) at 140 px/s while the other two swing (0.55 s), so the
# lowest |dx| on a holding frame is AttackRange itself, not HoldDistance - 30. What the hold rule
# guarantees is direction: the holder never closes in below AttackRange and its distance to the
# hold point shrinks on every consecutive holding frame (VelocityTowards converges without
# overshoot; the hero's own knockback moves it <= 2 px per frame, hence the epsilon).
const HOLD_MIN_MARGIN := 5.0     # |dx| on a holding frame must stay >= AttackRange - this
const HOLD_DIVERGE_EPS := 2.5    # allowed growth of |dx - HoldDistance| between two consecutive holding frames, px
const DARK_SPAWN_FRAMES := 30    # frames a SpawnAware=false wave must stay Idle with the unlit hero in front of it
const NOTICE_CAP := 5            # physics frames allowed for lamp on -> Noticed on every spawned guard
const DARK_HOLD_POS := Vector2(1050, 450)  # outside the LitZone (r 160 at (760,520)) and > 420 px from every marker: unseen lit or not
const DARK_LIT_POS := Vector2(1300, 450)   # 200..400 px from the markers: inside PerceptionRange 420 for all three once lit
const WALK_START := Vector2(850, 450)      # 50 px left of the trigger (x 900..1000)
const FIGHT_POS := Vector2(1350, 450)      # between the trigger and the markers: guards arrive within ~1-2.5 s
const MARKERS := [Vector2(1500, 430), Vector2(1600, 500), Vector2(1700, 460)]   # spawner (950,450) + Marker1..3
const SCENE_LOCK := Rect2(0, 0, 1920, 1080)                                     # TestRoom's LockRect
# The scene's LockRect equals the camera's own limits, which would make "released" indistinguishable
# from "locked"; the run below locks to a tighter rect so both transitions are visible.
const TEST_LOCK := Rect2(200, 100, 1500, 800)

var _started := false
var _frames := 0
var _failures: Array[String] = []

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

# Waits (idle frames) until Engine.time_scale is back to 1. Returns elapsed ms, or -1 on cap.
func _wait_restored(cap_ms: int) -> int:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < cap_ms:
		if Engine.time_scale == 1.0:
			return Time.get_ticks_msec() - start
		await process_frame
	return -1

func _limits(camera: Camera2D) -> Array:
	return [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]

func _rect_limits(rect: Rect2) -> Array:
	return [roundi(rect.position.x), roundi(rect.position.y), roundi(rect.end.x), roundi(rect.end.y)]

func _run() -> void:
	# 0. Preconditions: the action the walk uses, autoloads.
	_check(InputMap.has_action("move_right") and InputMap.action_get_events("move_right").size() > 0, "InputMap action 'move_right' missing or without events")
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	_check(root.get_node_or_null("HitStop") != null, "HitStop autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	# 0a. WaveSpawner.tscn standalone (not added to the tree): script, trigger layers, defaults,
	#     Guard as the enemy scene, three markers, GO label hidden in the scene.
	var spawner_scene: PackedScene = load(SPAWNER_PATH)
	_check(spawner_scene != null, "%s failed to load" % SPAWNER_PATH)
	if spawner_scene != null:
		var sp: Node = spawner_scene.instantiate()
		_check(sp.get_script() != null and str(sp.get_script().resource_path).ends_with("WaveSpawner.cs"),
			"WaveSpawner.tscn has no WaveSpawner.cs attached (did dotnet build run?)")
		if sp.get("Count") == null:
			_check(false, "WaveSpawner exports missing — WaveSpawner.cs not attached, aborting")
			sp.free()
			_finish()
			return
		_check(sp is Area2D, "WaveSpawner root is %s, expected Area2D" % sp.get_class())
		_check(sp.collision_layer == 0 and sp.collision_mask == 2, "WaveSpawner trigger layer/mask = %d/%d, expected 0/2 (Player)" % [sp.collision_layer, sp.collision_mask])
		_check(sp.y_sort_enabled == true, "WaveSpawner lacks y_sort_enabled (spawned guards are its children)")
		_check(sp.Count == 3, "WaveSpawner.Count default is %s, expected 3" % sp.Count)
		_check(is_equal_approx(sp.SpawnInterval, 0.4), "WaveSpawner.SpawnInterval default is %s, expected 0.4" % sp.SpawnInterval)
		_check(is_equal_approx(sp.GoDuration, 2.0), "WaveSpawner.GoDuration default is %s, expected 2" % sp.GoDuration)
		_check(sp.OneShot == true, "WaveSpawner.OneShot default is %s, expected true" % sp.OneShot)
		_check(sp.SpawnAware == true, "WaveSpawner.SpawnAware default is %s, expected true" % sp.SpawnAware)
		var es = sp.EnemyScene
		_check(es != null and es is PackedScene and str(es.resource_path).ends_with("Guard.tscn"), "WaveSpawner.EnemyScene is %s, expected Guard.tscn" % es)
		var pts: Node = sp.get_node_or_null("SpawnPoints")
		_check(pts != null, "WaveSpawner has no SpawnPoints child")
		if pts != null:
			var markers := 0
			for c in pts.get_children():
				if c is Marker2D:
					markers += 1
			_check(markers == 3, "WaveSpawner SpawnPoints has %d Marker2D children, expected 3" % markers)
		var go: Node = sp.get_node_or_null("GoOverlay/GoLabel")
		_check(go != null and go is Label, "WaveSpawner has no 'GoOverlay/GoLabel' Label")
		if go != null:
			_check(go.visible == false, "GoLabel visible in the scene, expected hidden")
			_check(go.text.begins_with("GO"), "GoLabel text '%s', expected 'GO →'" % go.text)
		_check(sp.get_node_or_null("CollisionShape2D") != null, "WaveSpawner has no trigger CollisionShape2D")
		sp.free()

	# 0b. TestRoom: spawner instance wiring.
	var scene: PackedScene = load(ROOM_PATH)
	_check(scene != null, "%s failed to load" % ROOM_PATH)
	if scene == null:
		_finish()
		return
	var room: Node = scene.instantiate()
	root.add_child(room)
	await process_frame   # consume the load catch-up iteration (see the header)
	await process_frame
	var player: Node = room.get_node_or_null("Player")
	var spawner: Node = room.get_node_or_null("WaveSpawner")
	var director: Node = room.get_node_or_null("EnemyDirector")
	var camera: Camera2D = room.get_node_or_null("Camera2D")
	var standing: Node = room.get_node_or_null("Guard")
	_check(player != null, "TestRoom has no 'Player' child")
	_check(spawner != null, "TestRoom has no 'WaveSpawner' child")
	_check(director != null, "TestRoom has no 'EnemyDirector' child")
	_check(camera != null, "TestRoom has no 'Camera2D' child")
	if player == null or spawner == null or director == null or camera == null or spawner.get("Count") == null or player.get("MoveSpeed") == null:
		_check(false, "TestRoom wiring incomplete (or C# scripts not attached), aborting")
		room.queue_free()
		_finish()
		return
	var go_label: Label = spawner.GoLabel
	_check(go_label != null and go_label.visible == false, "TestRoom WaveSpawner GoLabel visible at start, expected hidden")
	_check(spawner.Count == 3 and spawner.SpawnAware == true and spawner.OneShot == true, "TestRoom WaveSpawner Count=%s SpawnAware=%s OneShot=%s, expected 3/true/true" % [spawner.Count, spawner.SpawnAware, spawner.OneShot])
	_check(spawner.EnemyScene != null, "TestRoom WaveSpawner.EnemyScene not set")
	_check(spawner.Player == player, "TestRoom WaveSpawner.Player is not the room's Player")
	_check(spawner.Director == director, "TestRoom WaveSpawner.Director is not the room's EnemyDirector")
	_check(spawner.Camera == camera, "TestRoom WaveSpawner.Camera is not the room's Camera2D")
	_check(spawner.LockRect == SCENE_LOCK, "TestRoom WaveSpawner.LockRect=%s, expected %s" % [spawner.LockRect, SCENE_LOCK])
	_check(spawner.position == Vector2(950, 450), "TestRoom WaveSpawner at %s, expected (950, 450)" % spawner.position)
	_check(spawner.IsRunning == false and spawner.IsCleared == false and spawner.Spawned == 0, "TestRoom WaveSpawner IsRunning=%s IsCleared=%s Spawned=%s at start, expected false/false/0" % [spawner.IsRunning, spawner.IsCleared, spawner.Spawned])
	var pts_room: Node = spawner.get_node_or_null("SpawnPoints")
	if pts_room != null:
		var i := 0
		for c in pts_room.get_children():
			if c is Marker2D and i < MARKERS.size():
				_check(c.global_position.is_equal_approx(MARKERS[i]), "Marker%d at %s, expected %s" % [i + 1, c.global_position, MARKERS[i]])
				i += 1
	var original_limits: Array = _limits(camera)
	_check(original_limits == [0, 0, 1920, 1080], "Camera2D limits %s at start, expected [0, 0, 1920, 1080]" % [original_limits])
	_check(director.ActiveAttackers == 0, "EnemyDirector.ActiveAttackers=%s at start, expected 0" % director.ActiveAttackers)
	if _failures.size() > 0:
		room.queue_free()
		_finish()
		return

	var events: Array = []          # "started" / "spawned" / "cleared" in emission order
	var spawned: Array = []         # the enemy nodes, in spawn order
	var spawn_positions: Array = []
	var spawn_aware: Array = []
	spawner.WaveStarted.connect(func(): events.append("started"))
	spawner.EnemySpawned.connect(func(enemy: Node2D):
		events.append("spawned")
		spawned.append(enemy)
		spawn_positions.append(enemy.global_position)
		spawn_aware.append(enemy.get("IsAware")))
	spawner.WaveCleared.connect(func(): events.append("cleared"))
	var hurt_events: Array = []
	player.Hurt.connect(func(d: float): hurt_events.append(d))
	# Park the standing guard out of the fight: it would otherwise join and blur the attacker count.
	if standing != null:
		standing.position = Vector2(1850, 320)

	# 1. Trigger: the hero walks right from x=850 into the trigger (x 900..1000) -> WaveStarted
	#    once, camera limits == LockRect (the tighter test rect) immediately.
	spawner.LockRect = TEST_LOCK
	player.position = WALK_START
	await _step(2)
	_release_all()
	Input.action_press("move_right")
	var trigger_after := -1
	for i in TRIGGER_CAP:
		await physics_frame
		if not events.is_empty():
			trigger_after = i + 1
			break
	Input.action_release("move_right")
	var trigger_x: float = player.position.x
	_check(trigger_after >= 0, "WaveStarted not emitted within %d frames of walking right from x=%.0f (hero x=%.1f)" % [TRIGGER_CAP, WALK_START.x, trigger_x])
	if trigger_after < 0:
		room.queue_free()
		_finish()
		return
	_check(events[0] == "started", "first wave event is '%s', expected 'started'" % events[0])
	_check(trigger_x >= 880.0 and trigger_x <= 1000.0, "hero x=%.1f when the wave started, expected inside/at the trigger 900..1000 (body half-width 14)" % trigger_x)
	_check(spawner.IsRunning == true, "WaveSpawner.IsRunning=%s after the trigger, expected true" % spawner.IsRunning)
	var locked_limits: Array = _limits(camera)
	_check(locked_limits == _rect_limits(TEST_LOCK), "camera limits %s while locked, expected LockRect %s" % [locked_limits, _rect_limits(TEST_LOCK)])
	print("enemy_wave: WaveStarted after %d frames at hero x=%.1f, camera limits %s" % [trigger_after, trigger_x, locked_limits])

	# 2. Spawns: Count guards within Count * SpawnInterval * ticks + 20 frames, at the marker
	#    positions in order, children of the spawner, aware (SpawnAware) and targeting the hero.
	var spawn_cap: int = int(spawner.Count * spawner.SpawnInterval * Engine.physics_ticks_per_second) + 20
	var spawned_after := -1
	for i in spawn_cap:
		await physics_frame
		if spawned.size() >= spawner.Count:
			spawned_after = i + 1
			break
	_check(spawned_after >= 0, "only %d of %d enemies spawned within %d frames" % [spawned.size(), spawner.Count, spawn_cap])
	_check(spawned.size() == spawner.Count, "EnemySpawned fired %d times, expected %d" % [spawned.size(), spawner.Count])
	_check(spawner.Spawned == spawner.Count and spawner.Alive == spawner.Count, "WaveSpawner Spawned=%s Alive=%s after the spawns, expected %s/%s" % [spawner.Spawned, spawner.Alive, spawner.Count, spawner.Count])
	for i in spawned.size():
		var enemy: Node = spawned[i]
		if not is_instance_valid(enemy):
			_check(false, "spawned enemy %d is no longer valid" % i)
			continue
		_check(enemy.get_script() != null and str(enemy.get_script().resource_path).ends_with("Guard.cs"), "spawned enemy %d has no Guard.cs" % i)
		if i < MARKERS.size():
			_check(spawn_positions[i].is_equal_approx(MARKERS[i]), "enemy %d spawned at %s, expected marker %s" % [i, spawn_positions[i], MARKERS[i]])
		_check(enemy.get_parent() == spawner, "enemy %d parent is '%s', expected the WaveSpawner" % [i, enemy.get_parent().name if enemy.get_parent() != null else "null"])
		_check(spawn_aware[i] == true and enemy.get("IsAware") == true, "enemy %d IsAware=%s at spawn / %s now, expected true (SpawnAware)" % [i, spawn_aware[i], enemy.get("IsAware")])
		_check(enemy.get("Target") == player, "enemy %d Target is not the room's Player" % i)
		_check(enemy.get("Director") == director, "enemy %d Director is not the room's EnemyDirector" % i)
	print("enemy_wave: %d spawned after %d frames at %s, aware %s" % [spawned.size(), spawned_after, spawn_positions, spawn_aware])
	if spawned.size() != spawner.Count:
		room.queue_free()
		_finish()
		return

	# 3. Attack slots: hero parked in the guards' reach, every physics frame for 300 frames count
	#    EnemyDirector.ActiveAttackers and guards in 'Attack' — never more than MaxAttackers (2).
	#    On "holding" frames (two in Attack, the third in Approach) the third guard's |dx| to the
	#    hero is recorded: it must reach HoldDistance - HOLD_TOLERANCE at least once (it converges
	#    to the hold point without overshoot) and never drop below HOLD_MIN_DX (see the constants).
	#    Energy is topped up so the hero is never knocked out mid-sample.
	player.position = FIGHT_POS
	var hold_distance: float = spawned[0].HoldDistance
	var max_slots := 0
	var max_attacking := 0
	var frames_two_attacking := 0
	var frames_holding := 0
	var frames_at_hold := 0        # holding frames with |dx| within HoldDistance +/- HOLD_TOLERANCE
	var hold_min_dx := INF
	var hold_max_dx := -1.0
	var diverging_frames := 0      # consecutive holding frames (same holder) on which |dx - HoldDistance| grew by more than HOLD_DIVERGE_EPS
	var max_divergence := 0.0
	var converge_pairs := 0        # consecutive holding-frame pairs compared for convergence
	var prev_holder: Node = null
	var prev_holder_frame := -2
	var prev_hold_error := 0.0
	var refills := 0
	for i in SAMPLE_FRAMES:
		await physics_frame
		var slots: int = director.ActiveAttackers
		var attacking := 0
		var approaching := 0
		var approach_dx := -1.0
		var holder: Node = null
		for enemy in spawned:
			if not is_instance_valid(enemy):
				continue
			var st: String = enemy.CurrentStateName
			if st == "Attack":
				attacking += 1
			elif st == "Approach":
				approaching += 1
				approach_dx = absf(enemy.global_position.x - player.global_position.x)
				holder = enemy
		max_slots = maxi(max_slots, slots)
		max_attacking = maxi(max_attacking, attacking)
		if attacking == 2:
			frames_two_attacking += 1
			if approaching >= 1:
				frames_holding += 1
				hold_min_dx = minf(hold_min_dx, approach_dx)
				hold_max_dx = maxf(hold_max_dx, approach_dx)
				var hold_error: float = absf(approach_dx - hold_distance)
				if hold_error <= HOLD_TOLERANCE:
					frames_at_hold += 1
				if holder == prev_holder and prev_holder_frame == i - 1:
					var growth: float = hold_error - prev_hold_error
					converge_pairs += 1
					max_divergence = maxf(max_divergence, growth)
					if growth > HOLD_DIVERGE_EPS:
						diverging_frames += 1
				prev_holder = holder
				prev_holder_frame = i
				prev_hold_error = hold_error
		if gs.Energy < REFILL_BELOW:
			gs.Energy = gs.MaxEnergy
			refills += 1
	_check(max_slots <= director.MaxAttackers, "EnemyDirector.ActiveAttackers peaked at %d over %d frames, expected <= MaxAttackers %d" % [max_slots, SAMPLE_FRAMES, director.MaxAttackers])
	_check(max_attacking <= director.MaxAttackers, "%d guards in 'Attack' at once over %d frames, expected <= %d" % [max_attacking, SAMPLE_FRAMES, director.MaxAttackers])
	_check(max_attacking >= 1, "no guard entered 'Attack' during %d frames (hero at %s)" % [SAMPLE_FRAMES, FIGHT_POS])
	_check(hurt_events.size() >= 1, "the wave landed no punch on the hero in %d frames (Hurt events %s)" % [SAMPLE_FRAMES, hurt_events])
	_check(not player.IsKnockedOut, "hero knocked out during the sampling (Energy %s)" % gs.Energy)
	_check(frames_holding > 0, "no frame with two guards in 'Attack' and the third in 'Approach' over %d frames (2 attacking on %d frames) — the hold rule was never exercised" % [SAMPLE_FRAMES, frames_two_attacking])
	if frames_holding > 0:
		_check(hold_max_dx >= hold_distance - HOLD_TOLERANCE, "third guard's |dx| to the hero peaked at %.1f over %d holding frames, expected >= HoldDistance %.0f - %.0f at least once" % [hold_max_dx, frames_holding, hold_distance, HOLD_TOLERANCE])
		_check(hold_min_dx >= spawned[0].AttackRange - HOLD_MIN_MARGIN, "third guard's |dx| to the hero dropped to %.1f on a holding frame, expected >= AttackRange %.0f - %.0f (a holder must back off to HoldDistance, never close in)" % [hold_min_dx, spawned[0].AttackRange, HOLD_MIN_MARGIN])
		_check(converge_pairs > 0, "no two consecutive holding frames with the same holder over %d holding frames — the convergence check never ran" % frames_holding)
		_check(diverging_frames == 0, "third guard moved AWAY from the hold point (HoldDistance %.0f) on %d of %d consecutive holding frames (worst growth %.2f px > %.1f), expected it to converge on every frame it holds" % [hold_distance, diverging_frames, converge_pairs, max_divergence, HOLD_DIVERGE_EPS])
	print("enemy_wave: over %d frames max slots %d, max attacking %d, frames with 2 attacking %d (third holding %d, at hold point %d, |dx| %.1f..%.1f, %d converging pairs, worst divergence %.2f px), punches %d, refills %d" % [SAMPLE_FRAMES, max_slots, max_attacking, frames_two_attacking, frames_holding, frames_at_hold, hold_min_dx, hold_max_dx, converge_pairs, max_divergence, hurt_events.size(), refills])
	if Engine.time_scale != 1.0:
		var restored: int = await _wait_restored(1000)
		_check(restored >= 0, "Engine.time_scale not restored within 1000 ms after the sampling")

	# 4. Clear: KO all three via TakeDamage -> WaveCleared once, IsCleared, GO visible, camera
	#    limits back to the values saved at the trigger (the scene's 0/0/1920/1080), no slot held.
	var cleared_before: int = events.count("cleared")
	_check(cleared_before == 0, "WaveCleared already fired %d times before the KOs" % cleared_before)
	var ko_results: Array = []
	for enemy in spawned:
		if is_instance_valid(enemy):
			ko_results.append(enemy.TakeDamage(999.0, 0.0, false, 0))
	_check(ko_results == [true, true, true], "TakeDamage(999) results %s, expected [true, true, true]" % [ko_results])
	var cleared_after := -1
	for i in CLEAR_CAP:
		if events.count("cleared") >= 1:
			cleared_after = i
			break
		await physics_frame
	_check(cleared_after >= 0, "WaveCleared not emitted within %d frames of the last KO (Alive=%s)" % [CLEAR_CAP, spawner.Alive])
	_check(events.count("cleared") == 1, "WaveCleared fired %d times, expected once" % events.count("cleared"))
	_check(events.count("started") == 1, "WaveStarted fired %d times, expected once" % events.count("started"))
	_check(spawner.IsCleared == true and spawner.IsRunning == false and spawner.Alive == 0, "WaveSpawner IsCleared=%s IsRunning=%s Alive=%s after the KOs, expected true/false/0" % [spawner.IsCleared, spawner.IsRunning, spawner.Alive])
	for i in spawned.size():
		var enemy: Node = spawned[i]
		if is_instance_valid(enemy):
			_check(enemy.IsKnockedOut == true and enemy.CurrentStateName == "KO", "enemy %d IsKnockedOut=%s state '%s' after TakeDamage(999), expected true / KO" % [i, enemy.IsKnockedOut, enemy.CurrentStateName])
	_check(go_label.visible == true, "GoLabel hidden right after WaveCleared, expected visible")
	var released_limits: Array = _limits(camera)
	_check(released_limits == original_limits, "camera limits %s after the clear, expected the pre-trigger limits %s restored" % [released_limits, original_limits])
	_check(released_limits != locked_limits, "camera limits %s after the clear still equal the lock rect" % [released_limits])
	_check(director.ActiveAttackers == 0, "EnemyDirector.ActiveAttackers=%s after the KOs, expected 0" % director.ActiveAttackers)
	_check(Engine.time_scale == 1.0, "Engine.time_scale=%s after TakeDamage KOs (0 hit-stop frames), expected 1" % Engine.time_scale)
	print("enemy_wave: cleared %d frames after the KOs, events %s, GO visible %s, limits %s" % [cleared_after, events, go_label.visible, released_limits])

	# 5. GO hint: still visible after 0.5 s, hidden after GoDuration + margin (real time).
	await _real_wait(0.5)
	_check(go_label.visible == true, "GoLabel hidden 0.5 s after the clear, expected visible for GoDuration %s s" % spawner.GoDuration)
	await _real_wait(spawner.GoDuration - 0.5 + GO_MARGIN)
	_check(go_label.visible == false, "GoLabel still visible %.1f s after the clear, expected hidden after GoDuration %s s" % [spawner.GoDuration + GO_MARGIN, spawner.GoDuration])

	# 6. OneShot: walking through the trigger again neither restarts nor respawns.
	player.position = WALK_START
	await _step(2)
	Input.action_press("move_right")
	for i in TRIGGER_CAP:
		await physics_frame
		if player.position.x > 1020.0:
			break
	Input.action_release("move_right")
	await _step(2)
	_check(player.position.x > 1000.0, "hero x=%.1f after the second walk, expected past the trigger (> 1000)" % player.position.x)
	_check(events.count("started") == 1, "WaveStarted fired %d times after walking through again, expected 1 (OneShot)" % events.count("started"))
	_check(spawner.Spawned == 3 and spawner.IsRunning == false and spawner.IsCleared == true, "OneShot: Spawned=%s IsRunning=%s IsCleared=%s after the second walk, expected 3/false/true" % [spawner.Spawned, spawner.IsRunning, spawner.IsCleared])
	_check(spawned.size() == 3, "OneShot: EnemySpawned fired %d times in total, expected 3" % spawned.size())

	# 7. SpawnAware = false (a fresh room): the unlit hero walks into the trigger, the three guards
	#    spawn under the normal perception rules — unaware, Idle and FACING the hero (Facing -1: the
	#    hero is left of the markers; S2 regression) — and stay so for 30 frames; then the hero,
	#    moved within PerceptionRange of all three, switches the lamp on -> every guard emits
	#    Noticed within 5 frames and leaves Idle.
	_release_all()
	gs.ResetRun()
	if Engine.time_scale != 1.0:
		var mid: int = await _wait_restored(1000)
		_check(mid >= 0, "dark wave: Engine.time_scale not restored within 1000 ms before the second room")
	room.queue_free()
	await _step(1)
	var room2: Node = scene.instantiate()
	root.add_child(room2)
	await process_frame   # load catch-up, as for the first room
	await process_frame
	var player2: Node = room2.get_node_or_null("Player")
	var spawner2: Node = room2.get_node_or_null("WaveSpawner")
	var standing2: Node = room2.get_node_or_null("Guard")
	var lamp2: Node = player2.get_node_or_null("Flashlight") if player2 != null else null
	if player2 == null or spawner2 == null or lamp2 == null or spawner2.get("Count") == null:
		_check(false, "dark wave: second TestRoom lacks Player/WaveSpawner/Flashlight (or scripts not attached), aborting")
		if is_instance_valid(room2):
			room2.queue_free()
		_finish()
		return
	if standing2 != null:
		standing2.position = Vector2(1850, 320)
	spawner2.SpawnAware = false          # set on the node BEFORE the trigger
	lamp2.SetOn(false)
	var dark_spawned: Array = []
	var dark_noticed: Array = []          # guard nodes that emitted Noticed
	var dark_started: Array = []
	spawner2.WaveStarted.connect(func(): dark_started.append(true))
	spawner2.EnemySpawned.connect(func(enemy: Node2D):
		dark_spawned.append(enemy)
		enemy.Noticed.connect(func(): dark_noticed.append(enemy)))
	# WALK_START and the trigger lie inside the LitZone (r 160 at (760, 520)), so the hero is zone-lit
	# during the walk; that is harmless here (the markers are > 600 px away, beyond PerceptionRange)
	# and the unlit checks happen from DARK_HOLD_POS, outside the zone.
	player2.position = WALK_START
	await _step(2)
	Input.action_press("move_right")
	var dark_trigger := -1
	for i in TRIGGER_CAP:
		await physics_frame
		if not dark_started.is_empty():
			dark_trigger = i + 1
			break
	Input.action_release("move_right")
	_check(dark_trigger >= 0, "dark wave: WaveStarted not emitted within %d frames (hero x=%.1f)" % [TRIGGER_CAP, player2.position.x])
	if dark_trigger < 0:
		room2.queue_free()
		_finish()
		return
	_check(spawner2.SpawnAware == false, "dark wave: WaveSpawner.SpawnAware=%s after the trigger, expected false" % spawner2.SpawnAware)
	var dark_spawn_cap: int = int(spawner2.Count * spawner2.SpawnInterval * Engine.physics_ticks_per_second) + 20
	for i in dark_spawn_cap:
		await physics_frame
		if dark_spawned.size() >= spawner2.Count:
			break
	_check(dark_spawned.size() == spawner2.Count, "dark wave: %d of %d enemies spawned within %d frames" % [dark_spawned.size(), spawner2.Count, dark_spawn_cap])
	if dark_spawned.size() != spawner2.Count:
		room2.queue_free()
		_finish()
		return
	# Step out of the zone and stand still, unlit, in front of the guards but far (>= 450 px, beyond
	# even the lit range): nobody may notice.
	player2.position = DARK_HOLD_POS
	await _step(DARK_SPAWN_FRAMES)
	var hero_x: float = player2.position.x
	_check(player2.IsLit == false, "dark wave: Player.IsLit=%s at %s with the lamp off (outside the LitZone), expected false" % [player2.IsLit, DARK_HOLD_POS])
	for i in dark_spawned.size():
		var enemy: Node = dark_spawned[i]
		if not is_instance_valid(enemy):
			_check(false, "dark wave: spawned enemy %d is no longer valid" % i)
			continue
		_check(enemy.IsAware == false, "dark wave: enemy %d IsAware=%s %d frames after spawning with SpawnAware=false and the hero unlit at x=%.0f, expected false" % [i, enemy.IsAware, DARK_SPAWN_FRAMES, hero_x])
		_check(enemy.CurrentStateName == "Idle", "dark wave: enemy %d state '%s' after spawning unaware, expected 'Idle'" % [i, enemy.CurrentStateName])
		_check(enemy.Facing == -1 and enemy.Visual.scale.x == -1.0, "dark wave: enemy %d Facing=%s Visual.scale=%s at spawn (hero at x=%.0f, left of marker x=%.0f), expected -1 / (-1, 1) — spawned guards must face the hero" % [i, enemy.Facing, enemy.Visual.scale, hero_x, enemy.global_position.x])
		_check(enemy.global_position.x > hero_x, "dark wave: enemy %d at x=%.0f is not right of the hero x=%.0f" % [i, enemy.global_position.x, hero_x])
	_check(dark_noticed.is_empty(), "dark wave: %d Noticed emitted while the hero stood unlit at the trigger, expected none" % dark_noticed.size())
	# Same frame: step into range of all three (200..400 px) and switch the lamp on.
	player2.position = DARK_LIT_POS
	lamp2.SetOn(true)
	_check(player2.IsLit == true, "dark wave: Player.IsLit=%s after SetOn(true), expected true" % player2.IsLit)
	var lit_notice := -1
	for i in NOTICE_CAP:
		await physics_frame
		if dark_noticed.size() >= dark_spawned.size():
			lit_notice = i + 1
			break
	_check(lit_notice >= 0, "dark wave: only %d of %d guards emitted Noticed within %d frames of the lamp going on at %s" % [dark_noticed.size(), dark_spawned.size(), NOTICE_CAP, DARK_LIT_POS])
	for i in dark_spawned.size():
		var enemy: Node = dark_spawned[i]
		if is_instance_valid(enemy):
			_check(enemy.IsAware == true, "dark wave: enemy %d IsAware=%s after the lamp went on, expected true" % [i, enemy.IsAware])
			_check(enemy.CurrentStateName != "Idle", "dark wave: enemy %d still 'Idle' after noticing the lit hero, expected Approach" % i)
			_check(dark_noticed.count(enemy) == 1, "dark wave: enemy %d emitted Noticed %d times, expected once" % [i, dark_noticed.count(enemy)])
	print("enemy_wave: dark wave — WaveStarted after %d frames, %d spawned unaware/Idle/Facing -1 for %d frames, all Noticed %d frames after the lamp" % [dark_trigger, dark_spawned.size(), DARK_SPAWN_FRAMES, lit_notice])
	lamp2.SetOn(false)

	# 8. Teardown.
	_release_all()
	gs.ResetRun()
	if Engine.time_scale != 1.0:
		var tear: int = await _wait_restored(1000)
		_check(tear >= 0, "teardown: Engine.time_scale not restored within 1000 ms")
	room2.queue_free()
	await _step(1)
	print("enemy_wave: idle frames used %d of MAX_FRAMES %d" % [_frames, MAX_FRAMES])
	_finish()
