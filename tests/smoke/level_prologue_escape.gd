extends SceneTree
# Smoke: the second half of the rebuilt prologue (T-07s-b) — segments 3 to 7, on a level
# instantiated directly (not through Main) and driven segment by segment with teleports, because
# 13 440 px of walking does not fit under the runner's 60 s timeout.
#   * the gas: the rehearsal pocket's long window can be cancelled by killing the lamp; the real
#     pocket ignites and costs a soft respawn at the checkpoint a few steps back, with the world
#     (and the level instance) intact;
#   * two ways through it: the 360 px pocket crossed in the dark with the pockets untouched, and
#     the same stretch crossed with the lamp on once the extractor has cleared them — the extractor
#     itself being refused while the pump runs;
#   * the crew: the two dark lanes are walkable end to end with the lamp off and nobody reacts;
#   * the upper collapse hands the circuit over — everything behind the seal is switched off, the
#     cage floodlight ahead of it takes the unit, the crew is retired — so the bus can never be
#     stranded behind rubble (the reachability invariant);
#   * the ramp pile is a gate at both edges of the walk band and opens for good;
#   * the cage: refused while the floodlight runs, the last fall armed by switching it off, Dan
#     left on the far side of the rubble and still there seconds later, a respawn point armed on
#     the hero's side so segment 6 can never lock him in;
#   * boarding: Departed once, the surface, the foreman's fine, the fight, the closing cutscene and
#     the hand-over to Level01_District;
#   * and everything from the crew on is played with GameState.Energy forced to 0 — nothing left in
#     the level needs the lamp, so energy can never gate the escape.
# Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/level_prologue_escape.gd

const NAME := "level_prologue_escape"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s).
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const PROLOGUE_PATH := "res://scenes/levels/Level00_Prologue.tscn"
const LEVEL01_PATH := "res://scenes/levels/Level01_District.tscn"
const SETTLE_CAP := 20          # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05      # process delta (s) below which the loop is back to normal pacing
const OVERLAP_FRAMES := 4       # physics frames for Area2D overlaps to refresh after a teleport
const CUTSCENE_CAP := 40        # Advance() calls allowed to play one cutscene out
const ATTEMPT_CAP := 80         # frames for a refused panel attempt to release the hero
const DELAY_MARGIN := 0.4       # extra real seconds on top of a level timer
const FADE_MARGIN := 0.6        # extra real seconds on top of DarknessFadeSeconds
const COLOR_EPS := 0.02
const SPEED := 220.0            # Player.MoveSpeed; used to size a walk
const TICKS := 60.0             # physics ticks per second
const WALK_SLACK := 10          # frames on top of the distance, for the input to be picked up
const BAND_MARGIN := 20.0
const BLOCK_APPROACH := 90.0
const BLOCK_MARGIN := 16.0
const PASS_MARGIN := 64.0
const GATE_WALK_FRAMES := 58
# Stage enum values (C# enums come back as int).
const STAGE_FLOOD := 3
const STAGE_GAS := 4
const STAGE_CREW := 5
const STAGE_UPPER := 6
const STAGE_CAGE := 7
const STAGE_FAREWELL := 8
const STAGE_SURFACE := 9
const STAGE_FIGHT := 10
const STAGE_ENDING := 11
const STAGE_DONE := 12
const EXPECTED_STAGES := ["Face", "Flood", "Gas", "Crew", "Upper", "Cage", "Farewell", "Surface", "Fight", "Ending", "Done"]
const ROOM_GAS_LIMITS := [4800, 0, 7680, 1080]
const ROOM_UPPER_LIMITS := [7680, 0, 9600, 1080]
const ROOM_CAGE_LIMITS := [9600, 0, 11520, 1080]
const ROOM_SURFACE_LIMITS := [11520, 0, 13440, 1080]
# Positions.
const CP_BLAST := Vector2(1840, 450)
const CP_FLOOD := Vector2(2920, 450)
const NEAR_LIGHTS := Vector2(3095, 450)
const NEAR_PUMP := Vector2(3855, 450)
const PUMP_SEQUENCE := ["move_up", "attack", "move_down", "jump"]
const CP_GAS1 := Vector2(4840, 450)
const REHEARSAL := Vector2(5100, 450)
const NEAR_EXTRACTOR := Vector2(5575, 450)
const CP_GAS2 := Vector2(5820, 450)
const POCKET_A := Vector2(6000, 450)
const DARK_START := Vector2(5900, 450)
const DARK_END_X := 6400.0
const CP_PAST := Vector2(6400, 450)
const CREW_LANE1 := Vector2(6650, 360)
const CREW_LANE1_END := 7000.0
const CREW_LANE2 := Vector2(7050, 540)
const CREW_LANE2_END := 7420.0
const CAVEIN_UPPER := Vector2(7760, 450)
const CP_UPPER := Vector2(7720, 450)
const CP_SIGHT := Vector2(8900, 450)
const ROAD_START := Vector2(8800, 450)   # just short of Checkpoint_Sight; the road to the cage is walked, not teleported
const ROAD_END_X := 9720.0              # just past Checkpoint_Cage
const CP_CAGE := Vector2(9640, 450)
const NEAR_FLOODLIGHT := Vector2(10075, 450)
const CAVEIN_FINAL := Vector2(10920, 450)
const NEAR_HOIST := Vector2(11195, 450)
const SURFACE_ARRIVAL := Vector2(11640, 480)
const REHEARSAL_WINDOW := 1.5
const POCKET_WINDOW := 0.8
const IGNITE_CAP_MS := 1400     # wall-clock cap while waiting for a 0.8 s window to run out
const RESTORE_CAP_MS := 1000    # wall-clock cap while waiting for the hit-stop to lift
const DAN_HOLD_SECONDS := 3.5   # > CompanionFollow.StuckSeconds (2.5): the stuck watchdog gets its chance
const SCENE_CHANGE_CAP_MS := 2000
const FINE := 20.0

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

func _settle() -> void:
	for i in SETTLE_CAP:
		await process_frame
		if root.get_process_delta_time() < SETTLE_DELTA:
			return

func _release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)

func _real_wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

func _finish() -> void:
	_release_all()
	paused = false
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

func _tap(action: String) -> void:
	Input.action_press(action)
	await _step(1)
	Input.action_release(action)

func _place(node: Node, pos: Vector2) -> void:
	node.global_position = pos
	await _step(OVERLAP_FRAMES)

func _wait_until(cond: Callable, cap: int) -> int:
	for i in cap:
		if cond.call():
			return i
		await physics_frame
	return -1

# Watches idle frames (which keep running under a hit-stop) until `flags` grows or `cap_ms` passes.
func _watch_ms(flags: Array, cap_ms: int) -> bool:
	var before: int = flags.size()
	var deadline: int = Time.get_ticks_msec() + cap_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if flags.size() > before:
			return true
	return false

func _wait_restored(cap_ms: int) -> void:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < cap_ms and Engine.time_scale != 1.0:
		await process_frame

# Walks the hero right from `from` far enough to cover `distance` px, and returns where he ended.
func _walk(player: Node, from: Vector2, distance: float) -> float:
	player.global_position = from
	await _step(2)
	Input.action_press("move_right")
	await _step(int(ceil(distance / SPEED * TICKS)) + WALK_SLACK)
	Input.action_release("move_right")
	await _step(2)
	return player.global_position.x

func _limits(camera: Camera2D) -> Array:
	return [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]

func _color_eq(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < COLOR_EPS and absf(a.g - b.g) < COLOR_EPS and absf(a.b - b.b) < COLOR_EPS

# Plays exactly one cutscene out by hand (this script drives no cutscene input). Counting Finished
# rather than polling IsPlaying matters: the level starts the next cutscene synchronously inside
# the handler (the foreman's is followed by the guard's without a frame in between).
func _play_out(cutscene: Node, finished: Array, label: String) -> void:
	var target: int = finished[0] + 1
	var guard := 0
	while finished[0] < target and guard < CUTSCENE_CAP and is_instance_valid(cutscene):
		cutscene.Advance()
		guard += 1
		await _step(1)
	if finished[0] < target:
		_check(false, "%s: the cutscene never ended after %d advances" % [label, guard])
	await _step(3)

func _use_panel(panel: Node, player: Node, sequence: Array) -> void:
	panel.Begin(player)
	await _step(2)
	for action in sequence:
		await _tap(action)
		await _step(2)
	await _wait_until(func(): return not panel.IsActive, ATTEMPT_CAP)
	await _step(2)

func _check_gate(player: Node, gate: Node, label: String) -> void:
	var box: Shape2D = gate.BlockerShape.shape
	_check(box is RectangleShape2D, "%s's blocker is a %s, expected a RectangleShape2D" % [label, box.get_class()])
	if box is RectangleShape2D:
		var top: float = gate.BlockerShape.global_position.y - box.size.y * 0.5
		var bottom: float = gate.BlockerShape.global_position.y + box.size.y * 0.5
		_check(top <= player.FloorTop and bottom >= player.FloorBottom,
			"%s blocks Y %.0f..%.0f, expected the whole walk band %.0f..%.0f — the hero could walk around it in depth"
			% [label, top, bottom, player.FloorTop, player.FloorBottom])
	for depth in [player.FloorTop + BAND_MARGIN, player.FloorBottom - BAND_MARGIN]:
		var reached: float = await _walk(player, Vector2(gate.global_position.x - BLOCK_APPROACH, depth), GATE_WALK_FRAMES / TICKS * SPEED)
		_check(reached <= gate.global_position.x - BLOCK_MARGIN,
			"walking right at Y %.0f the hero reached x %.0f, past %s at x %.0f — the gate can be bypassed in depth"
			% [depth, reached, label, gate.global_position.x])
	_release_all()
	gate.Clear()
	await _step(3)
	for depth2 in [player.FloorTop + BAND_MARGIN, player.FloorBottom - BAND_MARGIN]:
		var open: float = await _walk(player, Vector2(gate.global_position.x - BLOCK_APPROACH, depth2), GATE_WALK_FRAMES / TICKS * SPEED)
		_check(open >= gate.global_position.x + PASS_MARGIN,
			"with %s cleared the hero only reached x %.0f walking at Y %.0f, expected past x %.0f"
			% [label, open, depth2, gate.global_position.x + PASS_MARGIN])
	_release_all()

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	var scene: PackedScene = load(PROLOGUE_PATH)
	_check(scene != null, "%s failed to load" % PROLOGUE_PATH)
	if scene == null:
		_finish()
		return
	var level: Node = scene.instantiate()
	root.add_child(level)
	current_scene = level   # GoToLevel swaps the tree's current scene, exactly as it does under Main
	await _settle()

	var player: Node = level.get("Player")
	var lamp: Node = player.get("Flashlight") if player != null else null
	var cutscene: Node = level.get("Cutscene")
	var camera: Camera2D = level.get("Camera")
	var circuit: Node = level.get("Circuit")
	var dan: Node = level.get("Companion")
	if player == null or lamp == null or cutscene == null or camera == null or circuit == null or dan == null:
		_check(false, "the prologue lacks Player/Flashlight/Cutscene/Camera/Circuit/Companion")
		_finish()
		return
	var lights: Node = level.get("Lights")
	var pump: Node = level.get("Pump")
	var extractor: Node = level.get("Extractor")
	var floodlight: Node = level.get("Floodlight")
	var cage: Node = level.get("Cage")
	var crew: Node = level.get("Crew")
	var upper: Node = level.get("UpperCollapse")
	var final_fall: Node = level.get("FinalCollapse")
	var timber: Node = level.get("TimberPile")
	var pockets: Array = Array(level.GasPockets)
	_check(pockets.size() == 3, "Level00_Prologue.GasPockets has %d entries, expected 3" % pockets.size())
	if lights == null or pump == null or extractor == null or floodlight == null or cage == null or upper == null or final_fall == null or timber == null or pockets.size() != 3:
		_check(false, "the prologue's escape props are not wired")
		_finish()
		return
	var rehearsal: Node = pockets[0]
	var pocket_a: Node = pockets[1]
	var pocket_b: Node = pockets[2]
	var ramp: Node = level.get_node_or_null("DebrisPile_Ramp")
	var final_pile: Node = level.get_node_or_null("DebrisPile_Final")
	var upper_seal: Node = level.get_node_or_null("DebrisPile_UpperSeal")
	_check(ramp != null and final_pile != null and upper_seal != null, "the level lacks DebrisPile_Ramp / _Final / _UpperSeal")
	if ramp == null or final_pile == null or upper_seal == null:
		_finish()
		return

	var finished: Array = [0]
	cutscene.Finished.connect(func(): finished[0] += 1)
	var stages: Array = []
	level.StageChanged.connect(func(s: String): stages.append(s))
	var refusals: Array = []
	circuit.RequestRefused.connect(func(m, b): refusals.append([m, b]))
	var ignitions: Array = []
	for p in pockets:
		p.Ignited.connect(func(_pl): ignitions.append(true))
	var warnings: Array = []
	for p in pockets:
		p.WarningStarted.connect(func(): warnings.append(true))
	var spotted: Array = []
	if crew != null:
		crew.Spotted.connect(func(): spotted.append(true))

	await _play_out(cutscene, finished, "intro")
	_check(player.process_mode == Node.PROCESS_MODE_INHERIT, "the hero is still frozen after the intro")
	_check(final_fall.monitoring == false,
		"CaveIn_Final is monitoring from the start — the last fall would come down on the hero's first pass")
	timber.Clear()   # the hero got through segment 1; this is the world state a respawn must keep
	# Cross the checkpoint where Dan is found, so the run starts from the state segment 1 leaves
	# behind: he is on his feet and following (a respawn before that deliberately puts him back down).
	await _place(player, CP_BLAST)
	await _step(4)
	_check(dan.CurrentStateName == "Follow", "Dan is in '%s' after being found, expected 'Follow'" % dan.CurrentStateName)

	# 1. Segment 2 in brief: the lights off, the pump on, the drift drained (level_prologue.gd owns
	#    the refusal itself). The pump keeps running, so it can refuse the extractor in a moment.
	await _place(player, CP_FLOOD)
	_check(level.CurrentStage == STAGE_FLOOD, "at Checkpoint_Flood the stage is %s, expected Flood" % level.CurrentStage)
	await _place(player, NEAR_LIGHTS)
	await _use_panel(lights, player, [])
	await _place(player, NEAR_PUMP)
	await _use_panel(pump, player, PUMP_SEQUENCE)
	_check(pump.IsPowered == true, "the pump did not start with the bus free")

	# 2. The rehearsal pocket: a long window that killing the lamp cancels (acceptance 15).
	await _place(player, CP_GAS1)
	_check(level.CurrentStage == STAGE_GAS, "at Checkpoint_Gas1 the stage is %s, expected Gas" % level.CurrentStage)
	_check(_limits(camera) == ROOM_GAS_LIMITS, "camera limits %s in Room_Gas, expected %s" % [_limits(camera), ROOM_GAS_LIMITS])
	_check(is_equal_approx(rehearsal.WarningSeconds, REHEARSAL_WINDOW),
		"the rehearsal pocket's window is %s s, expected %s" % [rehearsal.WarningSeconds, REHEARSAL_WINDOW])
	# Every pocket is a gate at every depth, or "power the extractor or cross in the dark" is an
	# optional detour and the whole mechanic is decoration (acceptance 6).
	for i in pockets.size():
		var shape: CollisionShape2D = pockets[i].get_node_or_null("CollisionShape2D")
		_check(shape != null and shape.shape is RectangleShape2D, "GasPockets[%d] has no rectangular trigger shape" % i)
		if shape != null and shape.shape is RectangleShape2D:
			var top: float = shape.global_position.y - shape.shape.size.y * 0.5
			var bottom: float = shape.global_position.y + shape.shape.size.y * 0.5
			_check(top <= player.FloorTop and bottom >= player.FloorBottom,
				"%s covers Y %.0f..%.0f, expected the whole walk band %.0f..%.0f — the gas can be walked around in depth"
				% [pockets[i].name, top, bottom, player.FloorTop, player.FloorBottom])
	await _place(player, REHEARSAL)
	lamp.SetOn(true)
	await _step(3)
	_check(warnings.size() == 1, "WarningStarted fired %d times when the lamp came on in the rehearsal pocket, expected 1" % warnings.size())
	_check(rehearsal.IsWarning == true, "the rehearsal pocket is not counting down with the lamp on")
	lamp.SetOn(false)
	await _step(3)
	_check(rehearsal.IsWarning == false, "the window kept running after the lamp went out")
	_check(ignitions.is_empty(), "the rehearsal pocket ignited although the lamp went out in time")
	_check(player.IsKnockedOut == false, "the hero died in the rehearsal pocket with the lamp off in time")

	# 3. The real pocket: 0.8 s, and a death costs seconds, not the puzzle (acceptance 16).
	await _place(player, CP_GAS2)
	_check(level.ArmedCheckpoint != null and level.ArmedCheckpoint.Label == "gas_pocket",
		"the checkpoint before the pocket is %s, expected 'gas_pocket'" % level.ArmedCheckpoint)
	var armed: Node = level.ArmedCheckpoint
	var level_id: int = level.get_instance_id()
	_check(is_equal_approx(pocket_a.WarningSeconds, POCKET_WINDOW), "the pocket's window is %s s, expected %s" % [pocket_a.WarningSeconds, POCKET_WINDOW])
	await _place(player, POCKET_A)
	lamp.SetOn(true)
	var fired: bool = await _watch_ms(ignitions, IGNITE_CAP_MS)
	_check(fired, "the pocket never ignited with the lamp on for %d ms" % IGNITE_CAP_MS)
	await _wait_restored(RESTORE_CAP_MS)
	_check(player.IsKnockedOut == true, "the ignition did not knock the hero out")
	await _real_wait(level.RespawnDelay + DELAY_MARGIN)
	_check(is_instance_valid(level) and level.get_instance_id() == level_id,
		"the level was reloaded by a death in the gas — a checkpoint respawn must keep the world")
	_check(player.global_position.distance_to(armed.RespawnPosition) <= 2.0,
		"the hero respawned at %s, expected %s" % [player.global_position, armed.RespawnPosition])
	_check(lamp.IsOn == false, "the hero respawned with the head lamp on next to a gas pocket")
	_check(timber.IsCleared == true, "the cleared timber pile came back with the respawn")
	_check(pump.IsPowered == true, "the running pump was reset by the respawn")

	# 4. Route one: across the pocket in the dark, with nothing cleared (acceptance 17).
	var before_dark: int = ignitions.size()
	var reached: float = await _walk(player, DARK_START, DARK_END_X - DARK_START.x)
	_check(reached >= DARK_END_X - 20.0, "the dark walk ended at x %.0f, expected past %.0f" % [reached, DARK_END_X - 20.0])
	_check(ignitions.size() == before_dark, "the pocket ignited during a walk with the lamp off")
	_check(player.IsKnockedOut == false, "the hero died crossing the pocket in the dark")
	_check(pocket_a.IsCleared == false and pocket_b.IsCleared == false, "the pockets were cleared without the extractor")
	await _place(player, CP_PAST)
	_check(level.ArmedCheckpoint != null and level.ArmedCheckpoint.Label == "past_pocket",
		"there is no checkpoint right after the pocket (a death there would cost the whole segment)")

	# 5. Route two: the extractor, refused by the pump first (acceptance 11).
	refusals.clear()
	await _place(player, NEAR_EXTRACTOR)
	await _use_panel(extractor, player, [])
	_check(refusals.size() == 1, "RequestRefused fired %d times for the extractor, expected 1" % refusals.size())
	if refusals.size() > 0:
		_check(refusals[0][0] == extractor and refusals[0][1] == pump,
			"the refusal was %s blocked by %s, expected the extractor blocked by the pump" % [refusals[0][0], refusals[0][1]])
	_check(extractor.IsPowered == false, "the extractor started although the pump holds the bus")
	await _place(player, NEAR_PUMP)
	await _use_panel(pump, player, [])
	_check(pump.IsPowered == false, "the pump could not be switched off")
	await _place(player, NEAR_EXTRACTOR)
	await _use_panel(extractor, player, [])
	_check(extractor.IsPowered == true, "the extractor did not start on a free bus")
	_check(pocket_a.IsCleared == true and pocket_b.IsCleared == true, "the extractor left the pocket in place")
	var before_lit: int = ignitions.size()
	lamp.SetOn(true)
	var lit_reach: float = await _walk(player, DARK_START, DARK_END_X - DARK_START.x)
	_check(lit_reach >= DARK_END_X - 20.0, "the lit walk ended at x %.0f, expected past %.0f" % [lit_reach, DARK_END_X - 20.0])
	_check(ignitions.size() == before_lit, "the cleared pocket ignited with the lamp on — a cleared hazard must be inert")
	lamp.SetOn(false)
	await _step(2)

	# From here the run is played with an empty battery: nothing left in the level needs the lamp,
	# so energy can never gate the escape (acceptance 27).
	gs.Energy = 0.0

	# 6. The crew: both dark lanes are walkable end to end and nobody reacts (acceptance 18).
	_check(spotted.is_empty(), "the crew spotted the hero before the stealth segment even started")
	await _place(player, Vector2(6560, 450))
	var lane1: float = await _walk(player, CREW_LANE1, CREW_LANE1_END - CREW_LANE1.x)
	_check(lane1 >= CREW_LANE1_END - 20.0, "the far dark lane ended at x %.0f, expected past %.0f" % [lane1, CREW_LANE1_END - 20.0])
	var lane2: float = await _walk(player, CREW_LANE2, CREW_LANE2_END - CREW_LANE2.x)
	_check(lane2 >= CREW_LANE2_END - 20.0, "the near dark lane ended at x %.0f, expected past %.0f" % [lane2, CREW_LANE2_END - 20.0])
	_check(spotted.is_empty(), "the crew spotted the hero walking the dark lanes with the lamp off (%d times)" % spotted.size())
	_check(player.IsKnockedOut == false, "the hero was taken while weaving through the dark lanes")
	_check(level.CurrentStage == STAGE_CREW, "after the crew checkpoint the stage is %s, expected Crew" % level.CurrentStage)

	# 7. The upper collapse: the circuit hand-over that makes a soft-lock impossible (acceptance 12, 14).
	_check(extractor.IsPowered == true, "the extractor is not running going into the upper collapse — the hand-over would prove nothing")
	await _place(player, CAVEIN_UPPER)
	_check(upper.IsTriggered == true, "crossing CaveIn_Upper did not trigger it")
	await _real_wait(upper.Delay + DELAY_MARGIN)
	await _step(2)
	_check(upper.HasCollapsed == true, "the upper collapse never came down")
	_check(upper_seal.IsCleared == false, "the lower horizon is not sealed after the upper collapse")
	_check(lights.IsPowered == false and pump.IsPowered == false and extractor.IsPowered == false,
		"a machine behind the seal is still running (lights %s / pump %s / extractor %s) — the bus would be stranded"
		% [lights.IsPowered, pump.IsPowered, extractor.IsPowered])
	_check(floodlight.IsPowered == true, "the cage floodlight did not take the freed power unit")
	_check(circuit.Used == 1 and circuit.FreeCapacity == 0, "Circuit.Used=%s FreeCapacity=%s after the hand-over, expected 1 / 0" % [circuit.Used, circuit.FreeCapacity])
	if crew != null:
		_check(crew.Disabled == true, "the sealing crew is still watching although they are behind the seal")

	# 8. Segment 4: the ramp is a gate at every depth and opens for good (acceptance 5).
	await _place(player, CP_UPPER)
	_check(level.CurrentStage == STAGE_UPPER, "at Checkpoint_Upper the stage is %s, expected Upper" % level.CurrentStage)
	_check(_limits(camera) == ROOM_UPPER_LIMITS, "camera limits %s in Room_Upper, expected %s" % [_limits(camera), ROOM_UPPER_LIMITS])
	_check(is_equal_approx(player.FloorTop, 300.0) and is_equal_approx(player.FloorBottom, 600.0),
		"the floor band changed in Room_Upper (%s..%s)" % [player.FloorTop, player.FloorBottom])
	await _check_gate(player, ramp, "DebrisPile_Ramp")

	# 8b. Dan's five segment-4 lines, in the order script-en.md requires: fact -> future -> mother,
	#     immediately before the fall. They hang off positions, not off a cumulative timer chain,
	#     because the road from the first sight of the cage to the cage itself is 740 px — 3.4 s of
	#     walking — and a timed chain let the hero outrun it and hear the Mum line second, 0.6 s
	#     before the next one overwrote it. Walked, never teleported: the order is the assertion.
	var road: Array = []
	dan.LineShown.connect(func(t: String): road.append(t))
	var expected_road: Array = [level.DanCageSeenLine, level.DanCagePowerLine, level.DanPayLine,
		level.DanDaysOffLine, level.DanMumLine]
	await _walk(player, ROAD_START, ROAD_END_X - ROAD_START.x)
	_check(road == expected_road, "walking the road to the cage Dan said %s, expected %s" % [road, expected_road])

	# 9. Segment 5: the cage refuses while the floodlight runs (acceptance 13).
	_check(level.CurrentStage == STAGE_CAGE, "at Checkpoint_Cage the stage is %s, expected Cage" % level.CurrentStage)
	_check(_limits(camera) == ROOM_CAGE_LIMITS, "camera limits %s in Room_Cage, expected %s" % [_limits(camera), ROOM_CAGE_LIMITS])
	# Nothing in this level ever waits for Dan: half a level away, the beat still happens — and his
	# own failsafe brings him back without anybody asking (acceptance 22, 23).
	dan.WarpTo(Vector2(maxf(player.global_position.x - 4000.0, 220.0), 470.0))
	await _step(2)
	refusals.clear()
	await _place(player, NEAR_HOIST)
	await _use_panel(cage, player, [])
	_check(refusals.size() == 1, "RequestRefused fired %d times for the cage, expected 1" % refusals.size())
	var caught_up: int = await _wait_until(
		func(): return dan.global_position.distance_to(player.global_position) <= dan.WarpDistance, 200)
	_check(caught_up >= 0, "Dan never came back after being left 4 000 px behind")
	_check(dan.CurrentStateName == "Follow", "Dan is in '%s' after catching up, expected 'Follow'" % dan.CurrentStateName)
	if refusals.size() > 0:
		_check(refusals[0][0] == cage and refusals[0][1] == floodlight,
			"the refusal was %s blocked by %s, expected the cage blocked by the floodlight" % [refusals[0][0], refusals[0][1]])
	_check(cage.IsPowered == false, "the cage started although the floodlight holds the bus")
	_check(final_fall.monitoring == false, "the last fall is armed before the floodlight was switched off")

	# 10. Segment 6: switching the floodlight off arms the last fall; Dan stays behind it.
	await _place(player, NEAR_FLOODLIGHT)
	await _use_panel(floodlight, player, [])
	_check(floodlight.IsPowered == false, "the floodlight is still running after the switch-off")
	await _step(3)
	_check(final_fall.monitoring == true, "the last fall was not armed by switching the floodlight off")
	# The adversarial case: the fall is armed, and the player switches the floodlight back ON before
	# walking into it. Without the hand-over in the Collapsed handler the last power unit would end
	# up behind the rubble with the cage still asking for the whole bus — the one soft-lock this
	# level could have.
	await _use_panel(floodlight, player, [])
	_check(floodlight.IsPowered == true, "the floodlight could not be switched back on before the last fall")
	await _place(player, CAVEIN_FINAL)
	_check(final_fall.IsTriggered == true, "crossing CaveIn_Final did not trigger it")
	await _real_wait(final_fall.Delay + DELAY_MARGIN)
	await _step(2)
	_check(final_fall.HasCollapsed == true, "the last fall never came down")
	_check(level.CurrentStage == STAGE_FAREWELL, "after the last fall the stage is %s, expected Farewell" % level.CurrentStage)
	_check(final_pile.IsCleared == false, "the last fall left the drift open")
	_check(floodlight.IsPowered == false and circuit.Used == 0,
		"the last fall left the floodlight running behind the rubble (powered %s, Used %s) — the cage could never start"
		% [floodlight.IsPowered, circuit.Used])
	_check(dan.IsWaiting == true, "Dan is in '%s' after the last fall, expected the scripted hold" % dan.CurrentStateName)
	_check(dan.global_position.x < final_pile.global_position.x,
		"Dan is at x %.0f, on the hero's side of the rubble at x %.0f" % [dan.global_position.x, final_pile.global_position.x])
	_check(level.get("Companion") == null,
		"the level still holds a Companion reference after the farewell; a room change or a respawn would warp him through the rubble")
	_check(level.ArmedCheckpoint != null and level.ArmedCheckpoint.Label == "farewell",
		"no respawn point was armed on the hero's side of the last fall — a death in segment 6 would lock the run")
	_check(level.ArmedCheckpoint == null or level.ArmedCheckpoint.global_position.x > final_pile.global_position.x,
		"the armed checkpoint sits behind the rubble")
	var dan_x: float = dan.global_position.x
	await _real_wait(DAN_HOLD_SECONDS)
	_check(absf(dan.global_position.x - dan_x) < 40.0 and dan.global_position.x < final_pile.global_position.x,
		"Dan moved to x %.0f after %.1f s — a follower failsafe warped him through the rubble" % [dan.global_position.x, DAN_HOLD_SECONDS])
	await _play_out(cutscene, finished, "farewell")

	# 11. Boarding, and the surface.
	await _place(player, NEAR_HOIST)
	await _use_panel(cage, player, [])
	_check(cage.IsPowered == true, "the cage did not start on the freed bus")
	await _step(4)
	_check(cage.HasDeparted == true, "the hero boarded a running cage and it did not depart")
	_check(level.CurrentStage == STAGE_SURFACE, "after the cage the stage is %s, expected Surface" % level.CurrentStage)
	_check(player.global_position.distance_to(SURFACE_ARRIVAL) <= 2.0,
		"the cage put the hero down at %s, expected %s" % [player.global_position, SURFACE_ARRIVAL])
	# The cage puts him down a few px short of Checkpoint_Surface's own trigger, so the level has to
	# arm it by hand: until he walks those px, a KO in the first seconds of the surface fight would
	# respawn him at the farewell checkpoint — inside the sealed mine, under a cage that has gone.
	_check(level.ArmedCheckpoint != null and level.ArmedCheckpoint.Label == "surface",
		"the armed checkpoint on arrival is %s, expected the one labelled 'surface'"
		% [level.ArmedCheckpoint.Label if level.ArmedCheckpoint != null else "none"])
	_check(level.ArmedCheckpoint == null or level.ArmedCheckpoint.Room == level.get("SurfaceRoom"),
		"the checkpoint armed on the surface re-applies a room that is not Room_Surface")
	_check(_limits(camera) == ROOM_SURFACE_LIMITS, "camera limits %s on the surface, expected %s" % [_limits(camera), ROOM_SURFACE_LIMITS])
	_check(cutscene.IsPlaying == true, "the foreman's cutscene did not start when the cage arrived")
	await _real_wait(level.DarknessFadeSeconds + FADE_MARGIN)
	_check(_color_eq(level.Darkness.color, level.DarknessSurface),
		"the ambient light is %s on the surface, expected DarknessSurface %s" % [level.Darkness.color, level.DarknessSurface])

	# 12. The fine, the fight, the ending, and the hand-over to level 1.
	gs.Energy = 100.0
	await _play_out(cutscene, finished, "foreman")
	_check(is_equal_approx(gs.Energy, 100.0 - FINE), "the foreman's fine left the energy at %s, expected %s" % [gs.Energy, 100.0 - FINE])
	_check(cutscene.IsPlaying == true, "the guard's cutscene did not follow the foreman's")
	await _play_out(cutscene, finished, "guard")
	_check(level.CurrentStage == STAGE_FIGHT, "after the guard's cutscene the stage is %s, expected Fight" % level.CurrentStage)
	var spawner: Node = level.get("GuardSpawner")
	_check(spawner != null and spawner.IsRunning == true, "the surface fight did not start")
	if spawner != null:
		_check(spawner.Count == 1, "the surface fight spawns %d enemies, expected 1 (short and motivated)" % spawner.Count)
		spawner.emit_signal("WaveCleared")
	await _step(2)
	_check(level.CurrentStage == STAGE_ENDING, "after the wave the stage is %s, expected Ending" % level.CurrentStage)
	await _play_out(cutscene, finished, "ending")
	_check(stages == EXPECTED_STAGES, "the stage sequence was %s, expected %s" % [stages, EXPECTED_STAGES])

	var deadline: int = Time.get_ticks_msec() + SCENE_CHANGE_CAP_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == LEVEL01_PATH:
			break
	_check(current_scene != null and current_scene.scene_file_path == LEVEL01_PATH,
		"after the closing cutscene the current scene is %s, expected %s" % [current_scene, LEVEL01_PATH])
	_check(root.get_node_or_null("GameState").CurrentScenePath == LEVEL01_PATH,
		"GameState.CurrentScenePath is '%s', expected %s" % [root.get_node_or_null("GameState").CurrentScenePath, LEVEL01_PATH])
	if current_scene != null:
		current_scene.queue_free()
	await _step(2)
	_finish()
