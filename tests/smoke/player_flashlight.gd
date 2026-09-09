extends SceneTree
# Smoke: flashlight and darkness (T-03) — `flashlight` action in the InputMap, CanvasModulate base
# darkness in TestRoom, Flashlight node wiring (PointLight2D + Flashlight.cs, texture, exports,
# off at start), toggle on/off by input with the Toggled signal, energy drain over 60 physics
# frames (DrainPerSecond * N / ticks), no drain while off, energy death at MinEnergy (lamp turns
# itself off exactly once and refuses to turn on again), beam rotation follows facing (π when
# left, 0 when right), lamp Y follows the jump height, and the SetOn() API. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/player_flashlight.gd
#
# No attack is thrown here, so no hit-stop (Engine.time_scale stays 1) and every physics step
# drains exactly DrainPerSecond / physics_ticks_per_second.

const NAME := "player_flashlight"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls; headless
# runs ~2-3 process frames per physics tick, and a green run uses ~250 ticks.
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "flashlight"]
const DARKNESS := Color(0.0392, 0.0510, 0.0784)   # #0a0d14 (plan: CanvasModulate base darkness)
const COLOR_TOL := 0.01
const DRAIN_FRAMES := 60
const DRAIN_TOL := 0.05
const IDLE_FRAMES := 30
const DEATH_CAP := 60    # frames allowed for 0.3 energy to drain away (18 at the defaults)
const LAND_CAP := 120    # frames to wait for a landing (jump lasts ~51 frames at the defaults)

var _started := false
var _frames := 0
var _failures: Array[String] = []
var _events: Array = []   # every Toggled(bool) emission, in order

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
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

# Presses `action` for one physics frame (seen by Input.IsActionJustPressed in _PhysicsProcess),
# releases it and lets two more frames settle.
func _tap(action: String) -> void:
	Input.action_press(action)
	await _step(1)
	Input.action_release(action)
	await _step(2)

func _color_approx(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= COLOR_TOL and absf(a.g - b.g) <= COLOR_TOL and absf(a.b - b.b) <= COLOR_TOL

func _rot_is(rot: float, expected: float) -> bool:
	return is_zero_approx(absf(angle_difference(rot, expected)))

func _events_str() -> String:
	return str(_events)

func _run() -> void:
	# 1a. InputMap: the action the lamp polls exists and has at least one event.
	_check(InputMap.has_action("flashlight"), "InputMap missing action 'flashlight'")
	if InputMap.has_action("flashlight"):
		_check(InputMap.action_get_events("flashlight").size() > 0, "action 'flashlight' has no events")

	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	# 1b. TestRoom: base darkness via a CanvasModulate child with #0a0d14.
	var scene: PackedScene = load("res://scenes/levels/TestRoom.tscn")
	_check(scene != null, "res://scenes/levels/TestRoom.tscn failed to load")
	if scene == null:
		_finish()
		return
	var room: Node = scene.instantiate()
	root.add_child(room)

	var modulate: CanvasModulate = null
	for child in room.get_children():
		if child is CanvasModulate:
			modulate = child
			break
	_check(modulate != null, "TestRoom root has no CanvasModulate child")
	if modulate != null:
		_check(_color_approx(modulate.color, DARKNESS),
			"CanvasModulate color is %s, expected ~%s (#0a0d14)" % [modulate.color, DARKNESS])

	# 1c. Flashlight node wiring: PointLight2D + Flashlight.cs, texture, exports, off at start.
	var player: Node = room.get_node_or_null("Player")
	_check(player != null, "TestRoom has no 'Player' child")
	if player == null:
		room.queue_free()
		_finish()
		return
	if player.get("MoveSpeed") == null:
		_check(false, "Player.MoveSpeed export missing — C# script not attached (did dotnet build run?), aborting")
		room.queue_free()
		_finish()
		return
	var lamp: Node = player.get_node_or_null("Flashlight")
	_check(lamp != null, "Player has no 'Flashlight' child")
	if lamp == null:
		room.queue_free()
		_finish()
		return
	_check(lamp is PointLight2D, "Flashlight is a %s, expected PointLight2D" % lamp.get_class())
	_check(lamp.get_script() != null and str(lamp.get_script().resource_path).ends_with("Flashlight.cs"),
		"Flashlight has no Flashlight.cs attached (did dotnet build run?)")
	if not (lamp is PointLight2D) or lamp.get("DrainPerSecond") == null:
		_check(false, "Flashlight.DrainPerSecond export missing — aborting")
		room.queue_free()
		_finish()
		return
	_check(player.get("Flashlight") == lamp, "Player.Flashlight export does not point at the 'Flashlight' child")
	_check(lamp.texture != null, "Flashlight.texture is null (cone needs a GradientTexture2D)")
	if lamp.texture != null and lamp.texture is GradientTexture2D:
		_check(lamp.texture.width == 512 and lamp.texture.height == 256, "beam texture must be 512x256 (soft half-ellipse), got %dx%d" % [lamp.texture.width, lamp.texture.height])
		_check(lamp.texture.fill_to.is_equal_approx(Vector2(0.5, 0.5)), "beam gradient must reach alpha 0 at the texture edges (fill_to 0.5,0.5), got %s" % lamp.texture.fill_to)
	_check(is_equal_approx(lamp.DrainPerSecond, 1.0), "DrainPerSecond default is %s, expected 1.0" % lamp.DrainPerSecond)
	_check(is_equal_approx(lamp.HeadOffset, 60.0), "HeadOffset default is %s, expected 60" % lamp.HeadOffset)
	_check(is_zero_approx(lamp.BeamAngleDeg), "BeamAngleDeg default is %s, expected 0" % lamp.BeamAngleDeg)
	_check(lamp.EnabledAtStart == false, "EnabledAtStart default is %s, expected false" % lamp.EnabledAtStart)

	_release_all()
	await _step(2)
	_check(lamp.enabled == false, "Flashlight.enabled is true at start, expected false")
	_check(lamp.IsOn == false, "Flashlight.IsOn is true at start, expected false")
	_check(lamp.position.is_equal_approx(Vector2(0, -60)),
		"initial Flashlight.position=%s, expected (0, -60)" % lamp.position)
	_check(_rot_is(lamp.rotation, 0.0), "initial Flashlight.rotation=%.4f, expected 0" % lamp.rotation)
	_check(is_equal_approx(gs.Energy, gs.MaxEnergy),
		"Energy=%.3f before the lamp was ever on, expected MaxEnergy=%.1f (lamp off must not drain)" % [gs.Energy, gs.MaxEnergy])

	lamp.Toggled.connect(func(on: bool): _events.append(on))
	var ticks: float = float(Engine.physics_ticks_per_second)

	# 2. Tap `flashlight`: on, enabled, Toggled(true); 60 frames later Energy dropped by
	#    DrainPerSecond * 60 / ticks (= 1.0 at the defaults).
	await _tap("flashlight")
	_check(lamp.IsOn == true, "after tapping flashlight IsOn=%s, expected true" % lamp.IsOn)
	_check(lamp.enabled == true, "after tapping flashlight enabled=%s, expected true" % lamp.enabled)
	_check(_events == [true], "Toggled events after turning on: %s, expected [true]" % _events_str())
	_check(Engine.time_scale == 1.0, "Engine.time_scale=%s during the drain window, expected 1" % Engine.time_scale)
	var e0: float = gs.Energy
	await _step(DRAIN_FRAMES)
	var expected_drop: float = DRAIN_FRAMES * lamp.DrainPerSecond / ticks
	var drop: float = e0 - gs.Energy
	_check(absf(drop - expected_drop) <= DRAIN_TOL,
		"drain over %d frames: %.4f -> %.4f (drop %.4f), expected drop %.4f ± %.2f" % [DRAIN_FRAMES, e0, gs.Energy, drop, expected_drop, DRAIN_TOL])
	_check(lamp.IsOn == true, "lamp switched off by itself during the drain window (Energy=%.3f)" % gs.Energy)

	# 3. Tap again: off, disabled, Toggled(false); energy stays put while off.
	await _tap("flashlight")
	_check(lamp.IsOn == false, "after second tap IsOn=%s, expected false" % lamp.IsOn)
	_check(lamp.enabled == false, "after second tap enabled=%s, expected false" % lamp.enabled)
	_check(_events == [true, false], "Toggled events after turning off: %s, expected [true, false]" % _events_str())
	var e_off: float = gs.Energy
	await _step(IDLE_FRAMES)
	_check(is_equal_approx(gs.Energy, e_off),
		"Energy changed while the lamp was off: %.4f -> %.4f over %d frames" % [e_off, gs.Energy, IDLE_FRAMES])

	# 4. Energy death: with 0.3 energy the lamp dies on its own (one Toggled(false)), Energy hits
	#    MinEnergy, and a new tap leaves it off without a signal.
	gs.Energy = gs.MinEnergy + 0.3
	var events_before: int = _events.size()
	await _tap("flashlight")
	_check(lamp.IsOn == true, "lamp did not turn on with Energy=%.2f (IsOn=%s)" % [gs.MinEnergy + 0.3, lamp.IsOn])
	_check(_events.size() == events_before + 1 and _events[-1] == true,
		"Toggled events after turning on at low energy: %s, expected one extra 'true'" % _events_str())
	var died_at := -1
	for i in DEATH_CAP:
		if not lamp.IsOn:
			died_at = i
			break
		await physics_frame
	_check(died_at >= 0, "lamp still on after %d frames from 0.3 energy (Energy=%.4f)" % [DEATH_CAP, gs.Energy])
	_check(is_equal_approx(gs.Energy, gs.MinEnergy),
		"Energy after the lamp died is %.4f, expected MinEnergy=%.1f" % [gs.Energy, gs.MinEnergy])
	_check(lamp.enabled == false, "lamp died (IsOn=false) but enabled=%s" % lamp.enabled)
	_check(_events.size() == events_before + 2 and _events[-1] == false,
		"Toggled events after energy death: %s, expected exactly one extra 'false'" % _events_str())
	var events_dead: int = _events.size()
	await _tap("flashlight")
	_check(lamp.IsOn == false, "lamp turned on at MinEnergy (IsOn=%s), expected to stay off" % lamp.IsOn)
	_check(lamp.enabled == false, "lamp enabled at MinEnergy (enabled=%s), expected false" % lamp.enabled)
	_check(_events.size() == events_dead,
		"Toggled emitted when refusing to turn on at MinEnergy: %s" % _events_str())
	gs.ResetRun()
	await _step(1)

	# 5. Facing and height: the beam turns with facing and rises with the jump.
	Input.action_press("move_left")
	await _step(3)
	Input.action_release("move_left")
	await _step(2)
	_check(player.Facing == -1, "Facing=%s after move_left, expected -1" % player.Facing)
	_check(_rot_is(lamp.rotation, PI),
		"Flashlight.rotation=%.4f while facing left, expected π (beam points -X)" % lamp.rotation)
	Input.action_press("move_right")
	await _step(3)
	Input.action_release("move_right")
	await _step(2)
	_check(player.Facing == 1, "Facing=%s after move_right, expected 1" % player.Facing)
	_check(_rot_is(lamp.rotation, 0.0),
		"Flashlight.rotation=%.4f while facing right, expected 0" % lamp.rotation)

	Input.action_press("jump")
	await _step(1)
	Input.action_release("jump")
	await _step(8)
	var h: float = player.Height
	_check(h > 0.0, "Height=%.2f 8 frames after jump, expected > 0 (state '%s')" % [h, player.CurrentStateName])
	_check(is_equal_approx(lamp.position.y, -(lamp.HeadOffset + h)),
		"Flashlight.position.y=%.2f mid-jump, expected -(HeadOffset + Height)=%.2f" % [lamp.position.y, -(lamp.HeadOffset + h)])
	_check(is_zero_approx(lamp.position.x), "Flashlight.position.x=%.2f mid-jump, expected 0" % lamp.position.x)
	var landed := false
	for i in LAND_CAP:
		if not player.IsAirborne:
			landed = true
			break
		await physics_frame
	_check(landed, "still airborne %d frames after the jump (Height=%.2f)" % [LAND_CAP, player.Height])
	await _step(1)
	_check(lamp.position.is_equal_approx(Vector2(0, -60)),
		"Flashlight.position=%s after landing, expected (0, -60)" % lamp.position)

	# 6. SetOn() API: idempotent, emits only on a change.
	var events_api: int = _events.size()
	lamp.SetOn(true)
	_check(lamp.IsOn == true and lamp.enabled == true, "SetOn(true): IsOn=%s enabled=%s, expected true/true" % [lamp.IsOn, lamp.enabled])
	_check(_events.size() == events_api + 1 and _events[-1] == true,
		"Toggled events after SetOn(true): %s, expected one extra 'true'" % _events_str())
	lamp.SetOn(true)
	_check(_events.size() == events_api + 1, "SetOn(true) twice emitted Toggled again: %s" % _events_str())
	lamp.SetOn(false)
	_check(lamp.IsOn == false and lamp.enabled == false, "SetOn(false): IsOn=%s enabled=%s, expected false/false" % [lamp.IsOn, lamp.enabled])
	_check(_events.size() == events_api + 2 and _events[-1] == false,
		"Toggled events after SetOn(false): %s, expected one extra 'false'" % _events_str())
	lamp.SetOn(false)
	_check(_events.size() == events_api + 2, "SetOn(false) twice emitted Toggled again: %s" % _events_str())
	await _step(1)

	# 7. Teardown.
	_release_all()
	gs.ResetRun()
	room.queue_free()
	_finish()
