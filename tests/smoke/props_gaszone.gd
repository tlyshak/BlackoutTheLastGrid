extends SceneTree
# Smoke: the methane pocket (T-07s-a) — GasZone.tscn scene contract and export defaults, plus the
# whole fairness rule driven on TestMine's two pockets: standing inside with the head lamp OFF is
# safe for as long as you like; switching the lamp ON starts the warning window (WarningStarted,
# the haze flares, the warning light comes on) and the window counts down on physics delta;
# switching the lamp off in time cancels it (WarningStopped, no ignition) and re-arms a fresh full
# window; letting it run out ignites the pocket (hit-stop, Ignited once, Player.Kill -> KnockedOut,
# and Engine.time_scale back to 1 on its own); leaving the pocket makes it deaf to the lamp; and a
# pocket cleared for good (the extractor's Clear()) stops monitoring, fades its haze out, stops the
# motes (which a dangerous pocket really does emit) and can never warn or ignite again; and the
# pocket spans the room's whole walk band, so the lamp is just as lethal along its far and near edge
# as in the middle — there is no depth lane around the gas. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/props_gaszone.gd
#
# The ignition triggers a hit-stop (Engine.time_scale = 0), which stops physics frames, so the
# ignition itself and the restore are observed on idle frames under a wall-clock cap; the warning
# window is measured in physics frames through GasZone.WarningRemaining. The level's restart delay
# is raised so the hero's KO cannot reload anything under the test.

const NAME := "props_gaszone"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls.
const MAX_FRAMES := 12000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const SETTLE_CAP := 10         # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05     # process delta (s) below which the loop is back to normal pacing
const PLAYER_LAYER := 2        # physics layer 2 "Player"
const OVERLAP_FRAMES := 4      # physics frames for Area2D overlaps to refresh after a teleport
const REHEARSAL_POS := Vector2(920, 450)   # centre of the rehearsal pocket (180x320 around it)
const POCKET_POS := Vector2(1340, 450)     # centre of the normal pocket
const SAFE_POS := Vector2(560, 450)        # clear of every pocket, trigger and blocker
const SAFE_FRAMES := 100       # frames the hero stands in the gas with the lamp off (> 1.5 s window)
const HALF_FRAMES := 30        # frames into the window before the countdown is read back
const COUNTDOWN_EPS := 0.05    # s of slack on the countdown (3 physics frames of frame alignment)
const PRE_IGNITION_FRAMES := 80   # frames of a 1.5 s window that must pass with no ignition (1.33 s)
const IGNITE_CAP_MS := 900     # wall-clock cap while waiting for the ignition
const RESTORE_CAP_MS := 1000   # wall-clock cap while waiting for the hit-stop to lift
const BLAST_HIT_STOP := 6      # GasZone.BlastHitStopFrames default
const FADE_MARGIN := 0.4       # extra real seconds on top of HazeFadeSeconds for the tween to end
const SAFE_DELAY := 60.0       # RestartDelay/RespawnDelay pushed out of the way for this test
const COLOR_EPS := 0.01        # tolerance for a colour read back from a .tscn
const BAND_MARGIN := 20.0      # px inside the walk band's far and near edge the depth probes stand at
const REHEARSAL_WINDOW := 1.5
const POCKET_WINDOW := 0.8

var _started := false
var _frames := 0
var _failures: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _color_approx(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) <= COLOR_EPS and absf(a.g - b.g) <= COLOR_EPS \
		and absf(a.b - b.b) <= COLOR_EPS and absf(a.a - b.a) <= COLOR_EPS

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

func _settle() -> void:
	for i in SETTLE_CAP:
		await process_frame
		if root.get_process_delta_time() < SETTLE_DELTA:
			return

func _release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)

# Real-time wait that ignores Engine.time_scale (tweens and idle-delta countdowns).
func _real_wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

func _finish() -> void:
	_release_all()
	if Engine.time_scale != 1.0:
		_check(false, "Engine.time_scale=%s at the end, expected 1 (reset by the test)" % Engine.time_scale)
		Engine.time_scale = 1.0
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.ResetRun()
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

# Teleports the hero and lets the Area2D overlaps refresh (a teleport crosses no trigger on the way).
func _place(player: Node, pos: Vector2) -> void:
	player.global_position = pos
	await _step(OVERLAP_FRAMES)

# Watches idle frames until `flags` grew (the ignition) or `cap_ms` of wall time passed.
func _watch_ignition(flags: Array, cap_ms: int) -> Dictionary:
	var before: int = flags.size()
	var r := {"fired": false, "scale": 1.0}
	var deadline: int = Time.get_ticks_msec() + cap_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if flags.size() > before:
			r["fired"] = true
			r["scale"] = Engine.time_scale
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

func _run() -> void:
	# 0. Preconditions: the lamp action the whole mechanic inverts, and GameState.
	_check(InputMap.has_action("flashlight"), "InputMap missing action 'flashlight'")
	if InputMap.has_action("flashlight"):
		_check(InputMap.action_get_events("flashlight").size() > 0, "action 'flashlight' has no events")
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	# 1. GasZone.tscn: scene contract and export defaults.
	var gas_scene: PackedScene = load("res://scenes/props/GasZone.tscn")
	_check(gas_scene != null, "res://scenes/props/GasZone.tscn failed to load")
	if gas_scene == null:
		_finish()
		return
	var proto: Node = gas_scene.instantiate()
	_check(proto is Area2D, "GasZone.tscn root is a %s, expected Area2D" % proto.get_class())
	_check(proto.get_script() != null and str(proto.get_script().resource_path).ends_with("GasZone.cs"),
		"GasZone.tscn has no GasZone.cs attached (did dotnet build run?)")
	if proto.get("WarningSeconds") == null:
		_check(false, "GasZone exports missing — C# scripts not attached, aborting")
		proto.free()
		_finish()
		return
	_check(is_equal_approx(proto.WarningSeconds, POCKET_WINDOW), "GasZone.WarningSeconds default is %s, expected %s" % [proto.WarningSeconds, POCKET_WINDOW])
	_check(proto.Lethal == true, "GasZone.Lethal default is %s, expected true" % proto.Lethal)
	_check(is_equal_approx(proto.BlastDamage, 25.0), "GasZone.BlastDamage default is %s, expected 25" % proto.BlastDamage)
	_check(is_equal_approx(proto.BlastKnockback, 220.0), "GasZone.BlastKnockback default is %s, expected 220" % proto.BlastKnockback)
	_check(proto.BlastHitStopFrames == BLAST_HIT_STOP, "GasZone.BlastHitStopFrames default is %s, expected %d" % [proto.BlastHitStopFrames, BLAST_HIT_STOP])
	_check(is_equal_approx(proto.HazeFadeSeconds, 0.9), "GasZone.HazeFadeSeconds default is %s, expected 0.9" % proto.HazeFadeSeconds)
	_check(proto.IsCleared == false, "GasZone.IsCleared is %s on a fresh pocket, expected false" % proto.IsCleared)
	_check(proto.collision_layer == 0, "GasZone.tscn collision_layer=%d, expected 0 (a trigger, never a body)" % proto.collision_layer)
	_check(proto.collision_mask == PLAYER_LAYER, "GasZone.tscn collision_mask=%d, expected %d (Player)" % [proto.collision_mask, PLAYER_LAYER])
	_check(proto.monitoring == true, "GasZone.tscn monitoring=%s, expected true" % proto.monitoring)
	_check(proto.monitorable == false, "GasZone.tscn monitorable=%s, expected false" % proto.monitorable)
	var pshape: CollisionShape2D = proto.get_node_or_null("CollisionShape2D")
	_check(pshape != null and pshape.shape is RectangleShape2D, "GasZone.tscn has no CollisionShape2D with a RectangleShape2D")
	var phaze: Node = proto.get_node_or_null("PH_Haze")
	_check(phaze is Polygon2D, "GasZone.tscn has no PH_Haze Polygon2D placeholder")
	_check(proto.get("Haze") == phaze, "GasZone.Haze export does not point at PH_Haze")
	_check(proto.get("WarningLight") == proto.get_node_or_null("PH_HazeGlow"), "GasZone.WarningLight does not point at PH_HazeGlow")
	_check(proto.get("Motes") == proto.get_node_or_null("PH_Motes"), "GasZone.Motes does not point at PH_Motes")
	if phaze is Polygon2D:
		_check(_color_approx(phaze.color, proto.HazeColor), "PH_Haze colour %s does not match HazeColor %s (the air must read as wrong before it can hurt)" % [phaze.color, proto.HazeColor])
		_check(phaze.color.a > 0.0, "PH_Haze is fully transparent; the pocket would be invisible")
	_check(proto.HazeWarningColor.a > proto.HazeColor.a, "HazeWarningColor alpha %s must exceed HazeColor alpha %s (the haze flares on the warning)" % [proto.HazeWarningColor.a, proto.HazeColor.a])
	proto.free()
	if _failures.size() > 0:
		_finish()
		return

	# 2. TestMine: the rehearsal pocket (long window) and the normal one.
	var scene: PackedScene = load("res://scenes/levels/TestMine.tscn")
	_check(scene != null, "res://scenes/levels/TestMine.tscn failed to load")
	if scene == null:
		_finish()
		return
	var room: Node = scene.instantiate()
	root.add_child(room)
	await _settle()

	var rehearsal: Node = room.get_node_or_null("GasZone_Rehearsal")
	var pocket: Node = room.get_node_or_null("GasZone_Pocket")
	var player: Node = room.get_node_or_null("Player")
	for pair in [[rehearsal, "GasZone_Rehearsal"], [pocket, "GasZone_Pocket"], [player, "Player"]]:
		_check(pair[0] != null, "TestMine has no '%s' child" % pair[1])
	if rehearsal == null or pocket == null or player == null:
		room.queue_free()
		_finish()
		return
	if rehearsal.get("WarningSeconds") == null or player.get("DepthTolerance") == null:
		_check(false, "GasZone/Player exports missing in TestMine — aborting")
		room.queue_free()
		_finish()
		return
	_check(is_equal_approx(rehearsal.WarningSeconds, REHEARSAL_WINDOW),
		"GasZone_Rehearsal.WarningSeconds=%s, expected %s (the first contact is a scare, not a corpse)" % [rehearsal.WarningSeconds, REHEARSAL_WINDOW])
	_check(is_equal_approx(pocket.WarningSeconds, POCKET_WINDOW), "GasZone_Pocket.WarningSeconds=%s, expected %s" % [pocket.WarningSeconds, POCKET_WINDOW])
	# Both pockets know their room, so the _Ready check "does the trigger span the walk band" runs.
	var main_room: Node = room.get_node_or_null("Rooms/Room_Main")
	_check(rehearsal.get("Room") == main_room, "GasZone_Rehearsal.Room does not point at Room_Main — the walk-band check would never run")
	_check(pocket.get("Room") == main_room, "GasZone_Pocket.Room does not point at Room_Main — the walk-band check would never run")
	# Nothing in this test may reload or respawn: the hero's KO is the point, not its aftermath.
	room.RestartDelay = SAFE_DELAY
	room.RespawnDelay = SAFE_DELAY

	var lamp: Node = player.Flashlight
	_check(lamp != null, "Player.Flashlight export is null")
	if lamp == null:
		room.queue_free()
		_finish()
		return
	_check(lamp.IsOn == false, "the head lamp is on at level start")

	var started: Array = []
	var stopped: Array = []
	var ignited: Array = []
	var kos: Array = []
	rehearsal.WarningStarted.connect(func(): started.append(true))
	rehearsal.WarningStopped.connect(func(): stopped.append(true))
	rehearsal.Ignited.connect(func(p): ignited.append(p))
	player.KnockedOut.connect(func(): kos.append(true))
	var haze: Polygon2D = rehearsal.Haze
	var warning_light: Node = rehearsal.WarningLight

	# 3. Inside the gas with the lamp OFF: safe for as long as you like (acceptance 6).
	await _place(player, REHEARSAL_POS)
	_check(rehearsal.get_overlapping_bodies().has(player), "the hero at %s is not inside GasZone_Rehearsal" % REHEARSAL_POS)
	await _step(SAFE_FRAMES)
	_check(started.is_empty(), "WarningStarted fired %d times with the lamp off — the dark is supposed to be safe" % started.size())
	_check(ignited.is_empty(), "the pocket ignited with the lamp off")
	_check(rehearsal.IsWarning == false, "IsWarning=%s with the lamp off, expected false" % rehearsal.IsWarning)
	_check(player.IsKnockedOut == false, "the hero was knocked out by gas with the lamp off")

	# 4. Lamp ON inside the gas: the window starts at once and counts down on physics delta.
	lamp.SetOn(true)
	_check(started.size() == 1, "WarningStarted fired %d times when the lamp came on, expected 1" % started.size())
	_check(rehearsal.IsWarning == true, "IsWarning=%s with the lamp on inside the gas, expected true" % rehearsal.IsWarning)
	_check(is_equal_approx(rehearsal.WarningRemaining, REHEARSAL_WINDOW),
		"WarningRemaining=%s at the start of the window, expected %s" % [rehearsal.WarningRemaining, REHEARSAL_WINDOW])
	_check(haze != null and _color_approx(haze.color, rehearsal.HazeWarningColor),
		"the haze did not flare: colour %s, expected HazeWarningColor %s" % [haze.color if haze != null else Color.BLACK, rehearsal.HazeWarningColor])
	_check(warning_light != null and warning_light.enabled == true, "the pocket's WarningLight is off while the window counts down")
	await _step(HALF_FRAMES)
	var expected_left: float = REHEARSAL_WINDOW - float(HALF_FRAMES) / float(Engine.physics_ticks_per_second)
	_check(absf(rehearsal.WarningRemaining - expected_left) <= COUNTDOWN_EPS,
		"WarningRemaining=%s after %d physics frames, expected %s ± %s" % [rehearsal.WarningRemaining, HALF_FRAMES, expected_left, COUNTDOWN_EPS])
	_check(ignited.is_empty(), "the pocket ignited %d frames into a %s s window" % [HALF_FRAMES, REHEARSAL_WINDOW])

	# 5. Lamp OFF in time: the window is cancelled and re-arms full (acceptance 8).
	lamp.SetOn(false)
	_check(stopped.size() == 1, "WarningStopped fired %d times when the lamp went off, expected 1" % stopped.size())
	_check(rehearsal.IsWarning == false, "IsWarning=%s after the lamp went off, expected false" % rehearsal.IsWarning)
	_check(is_equal_approx(rehearsal.WarningRemaining, 0.0), "WarningRemaining=%s with no window running, expected 0" % rehearsal.WarningRemaining)
	_check(ignited.is_empty(), "the pocket ignited although the lamp went off in time")
	_check(haze != null and _color_approx(haze.color, rehearsal.HazeColor),
		"the haze stayed flared after the cancel: colour %s, expected HazeColor %s" % [haze.color if haze != null else Color.BLACK, rehearsal.HazeColor])
	_check(warning_light.enabled == false, "the pocket's WarningLight stayed on after the cancel")
	await _step(SAFE_FRAMES)
	_check(ignited.is_empty(), "the pocket ignited %d frames after a cancelled window" % SAFE_FRAMES)
	lamp.SetOn(true)
	_check(started.size() == 2, "WarningStarted fired %d times in total, expected 2 (the window re-arms)" % started.size())
	_check(is_equal_approx(rehearsal.WarningRemaining, REHEARSAL_WINDOW),
		"WarningRemaining=%s on the re-armed window, expected a fresh %s" % [rehearsal.WarningRemaining, REHEARSAL_WINDOW])

	# 6. Letting the window run out: hit-stop, Ignited once, the hero dies (acceptance 7, 9).
	await _step(PRE_IGNITION_FRAMES)
	_check(ignited.is_empty(), "the pocket ignited after %d frames of a %s s window (%.2f s), too early"
		% [PRE_IGNITION_FRAMES, REHEARSAL_WINDOW, float(PRE_IGNITION_FRAMES) / float(Engine.physics_ticks_per_second)])
	var blast: Dictionary = await _watch_ignition(ignited, IGNITE_CAP_MS)
	_check(blast["fired"], "the pocket did not ignite within %d ms of the window running out" % IGNITE_CAP_MS)
	if blast["fired"]:
		_check(ignited.size() == 1, "Ignited fired %d times, expected 1" % ignited.size())
		_check(ignited[0] == player, "Ignited carried %s, expected the hero" % ignited[0])
		_check(blast["scale"] == 0.0, "Engine.time_scale=%s right after the ignition, expected 0 (the blast's hit-stop)" % blast["scale"])
		_check(player.IsKnockedOut == true, "Player.IsKnockedOut=%s after a lethal ignition, expected true" % player.IsKnockedOut)
		_check(kos.size() == 1, "Player.KnockedOut fired %d times, expected 1" % kos.size())
		_check(player.CurrentStateName == "KO", "the hero is in '%s' after the blast, expected 'KO'" % player.CurrentStateName)
		var elapsed: int = await _wait_restored(RESTORE_CAP_MS)
		_check(elapsed >= 0, "Engine.time_scale not restored to 1 within %d ms — the blast's hit-stop stuck" % RESTORE_CAP_MS)
		var bound_ms: int = int((float(BLAST_HIT_STOP) / float(Engine.physics_ticks_per_second) + 0.15) * 1000.0)
		_check(elapsed < 0 or elapsed <= bound_ms, "the blast's hit-stop lasted %d ms, expected <= %d ms (%d frames)" % [elapsed, bound_ms, BLAST_HIT_STOP])
	_check(rehearsal.IsWarning == false, "IsWarning=%s after the ignition, expected false (nothing re-arms by itself)" % rehearsal.IsWarning)

	# 7. Out of the pocket, the lamp is none of its business any more.
	player.Revive()
	_check(lamp.IsOn == false, "Player.Revive() left the head lamp on next to a gas pocket")
	await _place(player, SAFE_POS)
	_check(not rehearsal.get_overlapping_bodies().has(player), "the hero at %s is still inside GasZone_Rehearsal" % SAFE_POS)
	var started_before: int = started.size()
	lamp.SetOn(true)
	await _step(SAFE_FRAMES)
	_check(started.size() == started_before, "WarningStarted fired %d more times with the hero outside the pocket" % (started.size() - started_before))
	_check(ignited.size() == 1, "the pocket ignited again with the hero outside it")
	lamp.SetOn(false)

	# 8. A pocket cleared for good is inert: no monitoring, the haze fades, the motes stop.
	var pocket_cleared: Array = []
	var pocket_started: Array = []
	var pocket_ignited: Array = []
	pocket.Cleared.connect(func(): pocket_cleared.append(true))
	pocket.WarningStarted.connect(func(): pocket_started.append(true))
	pocket.Ignited.connect(func(p): pocket_ignited.append(p))
	var pocket_haze: Polygon2D = pocket.Haze
	_check(pocket_haze != null and pocket_haze.color.a > 0.0, "GasZone_Pocket haze is invisible before it is cleared")
	_check(pocket.monitoring == true, "GasZone_Pocket does not monitor bodies before it is cleared")
	# The motes are read, never written: headless does not simulate particles, but the flag proves
	# the emitter was switched on for a dangerous pocket instead of shipping dead.
	_check(pocket.Motes != null and pocket.Motes.emitting == true,
		"the motes of a dangerous pocket are not emitting — the 'no draught here' cue is dead")
	pocket.Clear()
	_check(pocket.IsCleared == true, "GasZone_Pocket.IsCleared=%s after Clear(), expected true" % pocket.IsCleared)
	_check(pocket_cleared.size() == 1, "GasZone_Pocket.Cleared fired %d times, expected 1" % pocket_cleared.size())
	pocket.Clear()
	_check(pocket_cleared.size() == 1, "Clear() is not idempotent: Cleared fired %d times" % pocket_cleared.size())
	_check(pocket.Motes == null or pocket.Motes.emitting == false, "the motes keep emitting in a cleared pocket")
	await _step(2)   # Monitoring is written deferred (Clear() is safe from a physics callback)
	_check(pocket.monitoring == false, "a cleared pocket still monitors bodies")
	await _real_wait(pocket.HazeFadeSeconds + FADE_MARGIN)
	_check(pocket_haze != null and pocket_haze.color.a <= 0.01,
		"the haze of a cleared pocket has alpha %s after %.2f s, expected 0" % [pocket_haze.color.a if pocket_haze != null else -1.0, pocket.HazeFadeSeconds + FADE_MARGIN])
	await _place(player, POCKET_POS)
	lamp.SetOn(true)
	await _step(SAFE_FRAMES)
	_check(pocket_started.is_empty(), "a cleared pocket started a warning (%d times) with the lamp on inside it" % pocket_started.size())
	_check(pocket_ignited.is_empty(), "a cleared pocket ignited")
	_check(player.IsKnockedOut == false, "the hero died in a cleared gas pocket")
	lamp.SetOn(false)

	# 9. The pocket is a gate at EVERY depth: the trigger spans the room's whole walk band, so there
	# is no lane along its far or near edge where the lamp costs nothing. Without this the choice
	# "power the extractor or cross in the dark" is optional and the whole mechanic is decoration.
	var band: CollisionShape2D = rehearsal.get_node_or_null("CollisionShape2D")
	_check(band != null and band.shape is RectangleShape2D, "GasZone_Rehearsal has no rectangular trigger shape")
	if band != null and band.shape is RectangleShape2D:
		var top: float = band.global_position.y - band.shape.size.y * 0.5
		var bottom: float = band.global_position.y + band.shape.size.y * 0.5
		_check(top <= player.FloorTop and bottom >= player.FloorBottom,
			"the pocket covers Y %.0f..%.0f, expected the whole walk band %.0f..%.0f — the hero could walk around the gas in depth"
			% [top, bottom, player.FloorTop, player.FloorBottom])
	for depth in [player.FloorTop + BAND_MARGIN, player.FloorBottom - BAND_MARGIN]:
		var probe: Vector2 = Vector2(REHEARSAL_POS.x, depth)
		await _place(player, probe)
		_check(rehearsal.get_overlapping_bodies().has(player),
			"the hero at %s is not inside GasZone_Rehearsal — the pocket leaves a lane at that depth" % probe)
		started_before = started.size()
		lamp.SetOn(true)
		await _step(2)
		_check(started.size() > started_before,
			"the lamp came on inside the pocket at Y %.0f and no warning started — that depth is a free pass" % depth)
		_check(rehearsal.IsWarning == true, "IsWarning=%s at Y %.0f with the lamp on inside the gas" % [rehearsal.IsWarning, depth])
		lamp.SetOn(false)
		await _step(2)
		_check(rehearsal.IsWarning == false, "the window kept running at Y %.0f after the lamp went off" % depth)
	_check(ignited.size() == 1, "the pocket ignited again during the depth probes (%d times in total)" % ignited.size())
	_check(player.IsKnockedOut == false, "the hero died during the depth probes")

	room.queue_free()
	_finish()
