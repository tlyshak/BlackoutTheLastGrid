extends SceneTree
# Smoke: flashlight and darkness (T-03) — `flashlight` action in the InputMap, the CanvasModulate
# that dims Level00_Sections, Flashlight node wiring (PointLight2D + Flashlight.cs, texture,
# exports, off at start), toggle on/off by input with the Toggled signal, energy drain over 60
# physics frames (DrainPerSecond * N / ticks), no drain while off, energy death at MinEnergy (lamp
# turns itself off exactly once and refuses to turn on again), beam rotation follows facing (π when
# left, 0 when right), lamp Y follows the jump height, the SetOn() API, and (T-03r, optional in
# review #1) no drain during a hit-stop freeze: the lamp stays on and Energy is unchanged while
# Engine.time_scale == 0. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/player_flashlight.gd
#
# Sections 1-6 throw no attack, so no hit-stop (Engine.time_scale stays 1) and every physics step
# drains exactly DrainPerSecond / physics_ticks_per_second. Section 7 lands one light hit on the
# level's guard and then walks the hero out of its reach; the freeze is observed on idle frames
# (`process_frame`, which keep running) under a wall-clock cap.

const NAME := "player_flashlight"   # must equal the file basename
const LEVEL_PATH := "res://scenes/levels/Level00_Sections.tscn"
const LAMP_REST := Vector2(0.0, -92.0)   # Player.tscn puts the lamp at the painted hero's head
const SAFE_POS := Vector2(300.0, 470.0)  # back on the mine face, out of the woken guard's reach
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls; headless
# runs ~2-3 process frames per physics tick, and a green run uses ~250 ticks.
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "flashlight", "attack"]
const DARKNESS := Color(0.560784, 0.592157, 0.639216)   # the level's Darkness CanvasModulate (#8f97a3)
const COLOR_TOL := 0.01
const DRAIN_FRAMES := 60
const DRAIN_TOL := 0.05
const IDLE_FRAMES := 30
const DEATH_CAP := 60    # frames allowed for 0.3 energy to drain away (18 at the defaults)
const LAND_CAP := 120    # frames to wait for a landing (jump lasts ~51 frames at the defaults)
const HIT_CAP_MS := 800      # wall-clock cap while waiting for the light hit to freeze time
const RESTORE_CAP_MS := 1000 # wall-clock cap while waiting for the freeze to lift (4 frames = 67 ms)
const FREEZE_TOL := 0.001    # one drained physics tick is DrainPerSecond / 60 = 0.0167, well above this

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
	if Engine.time_scale != 1.0:
		_check(false, "Engine.time_scale=%s at the end, expected 1 (reset by the test)" % Engine.time_scale)
		Engine.time_scale = 1.0
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

	# 1b. The level dims its painted sections with a CanvasModulate, so a lamp reads as a lamp.
	var scene: PackedScene = load(LEVEL_PATH)
	_check(scene != null, "%s failed to load" % LEVEL_PATH)
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
	_check(modulate != null, "Level00_Sections has no CanvasModulate child")
	if modulate != null:
		_check(_color_approx(modulate.color, DARKNESS),
			"CanvasModulate color is %s, expected ~%s (#0a0d14)" % [modulate.color, DARKNESS])

	# 1c. Flashlight node wiring: PointLight2D + Flashlight.cs, texture, exports, off at start.
	var player: Node = room.get_node_or_null("Player")
	_check(player != null, "Level00_Sections has no 'Player' child")
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
	_check(is_equal_approx(lamp.HeadOffset, -LAMP_REST.y), "HeadOffset is %s, expected %s (the painted hero's head)" % [lamp.HeadOffset, -LAMP_REST.y])
	_check(is_zero_approx(lamp.BeamAngleDeg), "BeamAngleDeg default is %s, expected 0" % lamp.BeamAngleDeg)
	_check(lamp.EnabledAtStart == false, "EnabledAtStart default is %s, expected false" % lamp.EnabledAtStart)

	_release_all()
	await _step(2)
	_check(lamp.enabled == false, "Flashlight.enabled is true at start, expected false")
	_check(lamp.IsOn == false, "Flashlight.IsOn is true at start, expected false")
	_check(lamp.position.is_equal_approx(LAMP_REST),
		"initial Flashlight.position=%s, expected %s" % [lamp.position, LAMP_REST])
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
	_check(lamp.position.is_equal_approx(LAMP_REST),
		"Flashlight.position=%s after landing, expected %s" % [lamp.position, LAMP_REST])

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

	# 7. No drain during hit-stop: lamp on, one light hit on the level's guard freezes time
	#    (Engine.time_scale 0 for HitStopFrames); Energy must not move while frozen and the lamp must
	#    stay on. The hero steps up to the guard standing at the end of the drift, punches once and
	#    is moved back to the mine face before the woken guard can punch back.
	var guard: Node = room.get_node_or_null("Guard")
	_check(guard != null and guard.get("Hp") != null, "Level00_Sections has no 'Guard' with Guard.cs (needed for the hit-stop drain check)")
	_check(InputMap.has_action("attack"), "InputMap missing action 'attack'")
	if guard != null and guard.get("Hp") != null and InputMap.has_action("attack"):
		gs.ResetRun()
		Input.action_press("move_right")
		await _step(2)
		Input.action_release("move_right")
		await _step(2)
		player.position = Vector2(guard.position.x - 40.0, guard.position.y)
		await _step(2)
		_check(player.Facing == 1, "hit-stop: Facing=%s, expected 1 (towards the guard)" % player.Facing)
		_check(player.CurrentStateName == "Idle", "hit-stop: player state '%s' before the attack, expected 'Idle'" % player.CurrentStateName)
		lamp.SetOn(true)
		await _step(2)
		_check(lamp.IsOn, "hit-stop: lamp not on before the attack")
		var hs_e0: float = gs.Energy
		var hs_hp0: float = guard.Hp
		Input.action_press("attack")
		await _step(1)
		Input.action_release("attack")
		var hs_froze := false
		var hs_deadline: int = Time.get_ticks_msec() + HIT_CAP_MS
		while Time.get_ticks_msec() < hs_deadline:
			await process_frame
			if Engine.time_scale == 0.0:
				hs_froze = true
				break
		_check(hs_froze, "hit-stop: no freeze within %d ms (Guard.Hp %s -> %s, state '%s')" % [HIT_CAP_MS, hs_hp0, guard.Hp, player.CurrentStateName])
		if hs_froze:
			var hs_e_freeze: float = gs.Energy
			var hs_e_min: float = hs_e_freeze
			var hs_e_max: float = hs_e_freeze
			var hs_idle_frames: int = 0
			var hs_start: int = Time.get_ticks_msec()
			var hs_restored := false
			while Time.get_ticks_msec() - hs_start < RESTORE_CAP_MS:
				await process_frame
				if Engine.time_scale != 0.0:
					hs_restored = true
					break
				hs_idle_frames += 1
				hs_e_min = minf(hs_e_min, gs.Energy)
				hs_e_max = maxf(hs_e_max, gs.Energy)
				_check(lamp.IsOn, "hit-stop: lamp switched off during the freeze (idle frame %d)" % hs_idle_frames)
			var hs_ms: int = Time.get_ticks_msec() - hs_start
			_check(hs_restored, "hit-stop: Engine.time_scale still %s after %d ms, expected the freeze to lift" % [Engine.time_scale, RESTORE_CAP_MS])
			_check(hs_idle_frames >= 1, "hit-stop: the freeze lasted %d idle frames, expected at least 1 to observe" % hs_idle_frames)
			_check(absf(hs_e_max - hs_e_freeze) <= FREEZE_TOL and absf(hs_e_min - hs_e_freeze) <= FREEZE_TOL,
				"hit-stop: Energy moved during the freeze: %.4f at the freeze, range [%.4f, %.4f] over %d idle frames (%d ms) — the lamp drained while time was stopped" % [hs_e_freeze, hs_e_min, hs_e_max, hs_idle_frames, hs_ms])
			_check(hs_e_freeze <= hs_e0 + FREEZE_TOL, "hit-stop: Energy rose from %.4f to %.4f before the freeze" % [hs_e0, hs_e_freeze])
			_check(lamp.IsOn, "hit-stop: lamp off after the freeze (IsOn=%s)" % lamp.IsOn)
			print("player_flashlight: hit-stop Energy %.4f before the attack, %.4f at the freeze, [%.4f, %.4f] during %d idle frames (%d ms), lamp on" % [hs_e0, hs_e_freeze, hs_e_min, hs_e_max, hs_idle_frames, hs_ms])
		_check(guard.Hp < hs_hp0, "hit-stop: Guard.Hp=%s, expected below %s (the light hit must connect)" % [guard.Hp, hs_hp0])
		player.position = SAFE_POS   # the guard is awake now; the rest of the section is about the drain
		await _step(30)   # the rest of light_1, the drain resumes
		_check(player.CurrentStateName == "Idle", "hit-stop: player state '%s' 30 frames after the hit, expected 'Idle'" % player.CurrentStateName)
		_check(Engine.time_scale == 1.0, "hit-stop: Engine.time_scale=%s after the attack, expected 1" % Engine.time_scale)
		lamp.SetOn(false)
		await _step(1)

	# 8. Teardown.
	_release_all()
	gs.ResetRun()
	room.queue_free()
	_finish()
