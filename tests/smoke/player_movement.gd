extends SceneTree
# Smoke: Player belt-scroll movement (T-02) — InputMap, physics layer names, TestRoom Y-sort,
# Idle/Move/Jump transitions, walk speed, facing flip, floor depth clamp, diagonal input, jump
# height axis (shadow stays on the floor, visual lifts), jump while moving. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/player_movement.gd

const NAME := "player_movement"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls; headless
# runs ~2-3 process frames per physics tick, and a green run uses ~700 of them for ~260 ticks.
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump",
	"attack", "heavy_attack", "special", "interact", "flashlight"]
const MOVE_ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump"]
const LAND_CAP := 180   # frames to wait for a landing (jump lasts ~51 frames at the defaults)

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
	for a in MOVE_ACTIONS:
		Input.action_release(a)

func _finish() -> void:
	_release_all()
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

# Holds `action` from a start Y and asserts the depth clamp to `bound` on every frame.
func _check_depth_clamp(player: Node, action: String, start_y: float, bound: float, above: bool) -> void:
	player.position = Vector2(400.0, start_y)
	Input.action_press(action)
	for i in 30:
		await physics_frame
		var y: float = player.position.y
		if above:
			_check(y >= bound - 0.001, "%s: frame %d Y=%.3f went above FloorTop=%.1f" % [action, i, y, bound])
		else:
			_check(y <= bound + 0.001, "%s: frame %d Y=%.3f went below FloorBottom=%.1f" % [action, i, y, bound])
	Input.action_release(action)
	_check(is_equal_approx(player.position.y, bound),
		"%s: after 30 frames Y=%.3f, expected clamp to %.1f" % [action, player.position.y, bound])
	await _step(2)

# Presses `jump` for one physics frame and tracks the airborne phase. Returns
# {landed, max_height, frames, x_monotonic, state_on_land, state_after_land, first_x, last_x}.
func _do_jump(player: Node, visual: Node2D, shadow: Node2D) -> Dictionary:
	var r := {"landed": false, "max_height": 0.0, "frames": 0, "x_monotonic": true,
		"state_on_land": "", "state_after_land": "", "first_x": player.position.x,
		"last_x": player.position.x, "entered_jump": false}
	Input.action_press("jump")
	await _step(1)
	Input.action_release("jump")

	var prev_x: float = player.position.x
	for i in LAND_CAP:
		var st: String = player.CurrentStateName
		if st == "Jump":
			r["entered_jump"] = true
		var h: float = player.Height
		r["max_height"] = maxf(r["max_height"], h)
		if player.IsAirborne:
			_check(shadow.position == Vector2.ZERO,
				"PH_Shadow left the origin while airborne: %s (frame %d)" % [shadow.position, i])
			if h > 0.0:
				_check(visual.position.y < -player.SpriteFeetOffset,
					"Visual.position.y=%.2f not lifted above -SpriteFeetOffset while Height=%.2f (frame %d)" % [visual.position.y, h, i])
				_check(is_equal_approx(visual.position.y, -(player.SpriteFeetOffset + h)),
					"Visual.position.y=%.2f, expected -(SpriteFeetOffset + Height)=%.2f (frame %d)" % [visual.position.y, -(player.SpriteFeetOffset + h), i])
		if i >= 5 and not r["entered_jump"]:
			break   # never left the ground -> reported by the caller
		if r["entered_jump"] and not player.IsAirborne:
			r["landed"] = true
			r["frames"] = i
			r["state_on_land"] = st
			break
		if player.position.x < prev_x:
			r["x_monotonic"] = false
		prev_x = player.position.x
		await physics_frame
	r["last_x"] = player.position.x
	if r["landed"]:
		await _step(1)
		r["state_after_land"] = player.CurrentStateName
	return r

func _run() -> void:
	# 1. InputMap: every action the player reads exists and has at least one event.
	for a in ACTIONS:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)
		if InputMap.has_action(a):
			_check(InputMap.action_get_events(a).size() > 0, "action '%s' has no events" % a)

	# 2. Physics layer names recorded in project.godot.
	_check(ProjectSettings.get_setting("layer_names/2d_physics/layer_1") == "World",
		"2d_physics layer_1 is '%s', expected 'World'" % ProjectSettings.get_setting("layer_names/2d_physics/layer_1"))
	_check(ProjectSettings.get_setting("layer_names/2d_physics/layer_2") == "Player",
		"2d_physics layer_2 is '%s', expected 'Player'" % ProjectSettings.get_setting("layer_names/2d_physics/layer_2"))

	# 3. TestRoom loads, is Y-sorted and holds props at distinct depths on the floor band.
	var scene: PackedScene = load("res://scenes/levels/TestRoom.tscn")
	_check(scene != null, "res://scenes/levels/TestRoom.tscn failed to load")
	if scene == null:
		_finish()
		return
	var room: Node = scene.instantiate()
	root.add_child(room)
	_check(room.get("y_sort_enabled") == true, "TestRoom root lacks y_sort_enabled")

	var player: Node = room.get_node_or_null("Player")
	_check(player != null, "TestRoom has no 'Player' child")
	if player == null:
		room.queue_free()
		_finish()
		return
	_check(player.get_script() != null and str(player.get_script().resource_path).ends_with("Player.cs"),
		"Player has no Player.cs attached (did dotnet build run?)")
	if player.get("MoveSpeed") == null:
		_check(false, "Player.MoveSpeed export missing — C# script not attached, aborting")
		room.queue_free()
		_finish()
		return
	_check(is_equal_approx(player.MoveSpeed, 220.0), "MoveSpeed default is %s, expected 220" % player.MoveSpeed)
	_check(player.FloorTop < player.FloorBottom, "FloorTop (%s) must be below FloorBottom (%s)" % [player.FloorTop, player.FloorBottom])

	var crate: Node2D = room.get_node_or_null("PH_Crate")
	var post: Node2D = room.get_node_or_null("PH_Post")
	_check(crate != null, "TestRoom has no 'PH_Crate'")
	_check(post != null, "TestRoom has no 'PH_Post'")
	if crate != null and post != null:
		_check(not is_equal_approx(crate.position.y, post.position.y),
			"PH_Crate and PH_Post share Y=%.1f; need distinct depths" % crate.position.y)
		for prop in [crate, post]:
			_check(prop.position.y >= player.FloorTop and prop.position.y <= player.FloorBottom,
				"%s Y=%.1f outside floor band [%.1f, %.1f]" % [prop.name, prop.position.y, player.FloorTop, player.FloorBottom])

	var sm: Node = player.get_node_or_null("StateMachine")
	_check(sm != null, "Player has no StateMachine child")
	if sm != null:
		for s in ["Idle", "Move", "Jump"]:
			_check(sm.HasState(s), "StateMachine lacks state '%s'" % s)
	var visual: Node2D = player.get_node_or_null("Visual")
	var shadow: Node2D = player.get_node_or_null("PH_Shadow")
	_check(visual != null, "Player has no 'Visual' child")
	_check(shadow != null, "Player has no 'PH_Shadow' child")
	if visual == null or shadow == null:
		room.queue_free()
		_finish()
		return

	# 4. Initial state.
	_release_all()
	await _step(2)
	_check(player.CurrentStateName == "Idle", "initial state is '%s', expected 'Idle'" % player.CurrentStateName)
	_check(is_equal_approx(player.Height, 0.0), "initial Height=%s, expected 0" % player.Height)
	_check(player.IsAirborne == false, "initially airborne")
	_check(player.Facing == 1, "initial Facing=%s, expected 1" % player.Facing)
	_check(is_equal_approx(visual.position.y, -player.SpriteFeetOffset),
		"initial Visual.position.y=%.2f, expected -SpriteFeetOffset=%.2f" % [visual.position.y, -player.SpriteFeetOffset])

	# 5. Walk right for 30 physics frames: Idle -> Move, distance ~ MoveSpeed * 0.5 s, faces right.
	var start_x: float = player.position.x
	Input.action_press("move_right")
	await _step(2)
	_check(player.CurrentStateName == "Move", "after 2 frames of move_right state is '%s', expected 'Move'" % player.CurrentStateName)
	await _step(28)
	var dx: float = player.position.x - start_x
	var expected_dx: float = player.MoveSpeed * 30.0 / float(Engine.physics_ticks_per_second)
	_check(dx >= 0.7 * expected_dx, "move_right 30 frames: dx=%.2f < 0.7 * %.2f" % [dx, expected_dx])
	_check(dx <= 1.1 * expected_dx, "move_right 30 frames: dx=%.2f > 1.1 * %.2f" % [dx, expected_dx])
	_check(player.Facing == 1, "Facing=%s after move_right, expected 1" % player.Facing)
	_check(is_equal_approx(visual.scale.x, 1.0), "Visual.scale.x=%.2f after move_right, expected 1" % visual.scale.x)
	Input.action_release("move_right")
	await _step(2)
	_check(player.CurrentStateName == "Idle", "after releasing move_right state is '%s', expected 'Idle'" % player.CurrentStateName)

	# 6. Walk left: facing flips the visual.
	Input.action_press("move_left")
	await _step(10)
	_check(player.Facing == -1, "Facing=%s after move_left, expected -1" % player.Facing)
	_check(is_equal_approx(visual.scale.x, -1.0), "Visual.scale.x=%.2f after move_left, expected -1" % visual.scale.x)
	Input.action_release("move_left")
	await _step(2)

	# 7. Depth clamp to the floor band, never overshooting.
	await _check_depth_clamp(player, "move_up", player.FloorTop + 5.0, player.FloorTop, true)
	await _check_depth_clamp(player, "move_down", player.FloorBottom - 5.0, player.FloorBottom, false)

	# 8. Diagonal input moves along both axes.
	var mid_y: float = (player.FloorTop + player.FloorBottom) * 0.5
	player.position = Vector2(400.0, mid_y)
	await _step(1)
	var diag_start: Vector2 = player.position
	Input.action_press("move_right")
	Input.action_press("move_up")
	await _step(10)
	Input.action_release("move_right")
	Input.action_release("move_up")
	_check(player.position.x > diag_start.x, "diagonal: X did not increase (%.2f -> %.2f)" % [diag_start.x, player.position.x])
	_check(player.position.y < diag_start.y, "diagonal: Y did not decrease (%.2f -> %.2f)" % [diag_start.y, player.position.y])
	await _step(3)
	_check(player.CurrentStateName == "Idle", "state before jump is '%s', expected 'Idle'" % player.CurrentStateName)

	# 9. Jump from Idle: Jump state, Height rises within 5 frames, shadow stays, visual lifts, lands in Idle.
	var j: Dictionary = await _do_jump(player, visual, shadow)
	_check(j["entered_jump"], "jump from Idle: never entered 'Jump' state (state '%s')" % player.CurrentStateName)
	_check(j["max_height"] > 0.0, "jump from Idle: Height never rose above 0")
	_check(j["landed"], "jump from Idle: still airborne after %d frames (Height=%.2f)" % [LAND_CAP, player.Height])
	if j["landed"]:
		_check(is_equal_approx(player.Height, 0.0), "after landing Height=%.3f, expected 0" % player.Height)
		_check(j["state_on_land"] == "Idle", "state on landing is '%s', expected 'Idle'" % j["state_on_land"])
		_check(j["state_after_land"] == "Idle", "state 1 frame after landing is '%s', expected 'Idle'" % j["state_after_land"])
		_check(is_equal_approx(visual.position.y, -player.SpriteFeetOffset),
			"after landing Visual.position.y=%.2f, expected -SpriteFeetOffset=%.2f" % [visual.position.y, -player.SpriteFeetOffset])
	# Height must be > 0 within 5 frames of the press: the recorded max over the flight covers
	# the whole arc, so check the early frames explicitly with a second short probe.
	await _step(2)
	Input.action_press("jump")
	await _step(1)
	Input.action_release("jump")
	var rose_early := false
	for i in 5:
		if player.Height > 0.0 and player.CurrentStateName == "Jump":
			rose_early = true
			break
		await physics_frame
	_check(rose_early, "jump: Height/Jump state not reached within 5 frames (state '%s', Height=%.2f)" % [player.CurrentStateName, player.Height])
	for i in LAND_CAP:
		if not player.IsAirborne:
			break
		await physics_frame
	_check(not player.IsAirborne, "second jump did not land within %d frames" % LAND_CAP)
	await _step(2)

	# 10. Jump while walking right: horizontal motion continues and landing returns to Move.
	Input.action_press("move_right")
	await _step(2)
	_check(player.CurrentStateName == "Move", "before moving jump state is '%s', expected 'Move'" % player.CurrentStateName)
	var jm: Dictionary = await _do_jump(player, visual, shadow)
	_check(jm["entered_jump"], "moving jump: never entered 'Jump' state (state '%s')" % player.CurrentStateName)
	_check(jm["landed"], "moving jump: still airborne after %d frames" % LAND_CAP)
	_check(jm["last_x"] > jm["first_x"], "moving jump: X did not increase during the jump (%.2f -> %.2f)" % [jm["first_x"], jm["last_x"]])
	_check(jm["x_monotonic"], "moving jump: X decreased on some frame during the jump")
	if jm["landed"]:
		_check(jm["state_on_land"] == "Move" or jm["state_after_land"] == "Move",
			"moving jump: state on landing '%s' / next frame '%s', expected 'Move'" % [jm["state_on_land"], jm["state_after_land"]])
	Input.action_release("move_right")
	await _step(2)

	room.queue_free()
	_finish()
