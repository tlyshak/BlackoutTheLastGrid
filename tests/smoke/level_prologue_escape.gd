extends SceneTree
# Smoke: segments 2, 4 and 5 of the third-revision prologue (T-07s-e), on a level instantiated
# directly (not through Main) and driven with teleports where the walk itself is not the assertion.
#   * segment 2 — the timber pile is a gate at both edges of the walk band; a light attack bounces
#     with Dan's line; two heavy hits clear it for good and lead Dan to the edge of the gas; there
#     his lamp goes out BEFORE his warning line (the rule is shown before it is said), he faces the
#     gas and does not go on while the hero's lamp is on; switching it off lets him cross the
#     pocket in the dark (his lamp back on on the far side), and the hero crosses it dark too with
#     nothing igniting and nothing powered;
#   * segment 4 — the work lights already hold the bus (StartsPowered); the cage on the same screen
#     refuses, names the lights in the HUD and gets Dan's rule line once (the second refusal a
#     different line); switching the lights off disables the lamp pools, blacks the drift and gets
#     Dan's lamp back; the cage then runs, Dan runs to it;
#   * segment 5 — boarding departs once: the hero, Dan and the guards from behind are placed at
#     fixed spots and the Held cutscene plays with the hero frozen; after it Dan is gone (no shot,
#     no body), the screen goes black for a beat, the surface comes up with its own checkpoint and
#     the Surface cutscene, the energy untouched by the whole scene; a KO up top respawns up top;
#     walking off the surface hands the run to Level01_District. A second instance boards from the
#     far edge with Dan half a screen behind and lands in exactly the same picture.
# The patrol (segment 3) and the gas death are tests/smoke/level_prologue_patrol.gd.
# Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/level_prologue_escape.gd

const NAME := "level_prologue_escape"   # must equal the file basename
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const PROLOGUE_PATH := "res://scenes/levels/Level00_Prologue.tscn"
const LEVEL01_PATH := "res://scenes/levels/Level01_District.tscn"
const SETTLE_CAP := 20
const SETTLE_DELTA := 0.05
const OVERLAP_FRAMES := 4
const CUTSCENE_CAP := 40
const ATTEMPT_CAP := 80
const DELAY_MARGIN := 0.4
const FADE_MARGIN := 0.6
const COLOR_EPS := 0.02
const SPEED := 220.0
const TICKS := 60.0
const WALK_SLACK := 10
const BAND_MARGIN := 20.0
const BLOCK_APPROACH := 90.0
const BLOCK_MARGIN := 16.0
const PASS_MARGIN := 64.0
const GATE_WALK_FRAMES := 58
const BUBBLE_CAP := 60
const DAN_CAP := 400            # frames Dan is given to walk to a route point
const HIT_CAP := 80             # frames one heavy attack is given to land
const SWING_FRAMES := 45        # frames the heavy attack takes before the next one may start
const RESTORE_CAP_MS := 1000    # wall-clock cap while waiting for a hit-stop to lift
# Stage enum values (C# enums come back as int).
const STAGE_DRIFT := 6
const STAGE_GAS := 7
const STAGE_PATROL := 8
const STAGE_CAGE := 9
const STAGE_HELD := 10
const STAGE_SURFACE := 11
const STAGE_DONE := 12
const ROOM_PATROL_LIMITS := [5760, 0, 8640, 1080]
const ROOM_SURFACE_LIMITS := [8640, 0, 10560, 1080]
# Positions.
const CP_DRIFT := Vector2(2900, 450)
const TIMBER_X := 3300.0
const HIT_STAND := Vector2(3236, 450)      # facing right, the heavy hitbox reaches the pile
const GAS_APPROACH := Vector2(4100, 450)   # short of Checkpoint_GasNear and of Dan's reach at WP_gas_edge (4340)
const GAS_REACH := Vector2(4230, 450)      # on the checkpoint, within HeroCloseDistance (160) of WP_gas_edge
const DARK_START := Vector2(4380, 450)
const DARK_END_X := 4820.0
const CP_PAST_GAS := Vector2(5000, 450)
const CP_CAGE := Vector2(7700, 450)
const NEAR_LIGHTS := Vector2(7860, 450)
const NEAR_HOIST := Vector2(8370, 450)     # on the cage panel's reach, short of the boarding strip (8480..8560)
const NEAR_CAGE := Vector2(8200, 450)      # within HeroCloseDistance of WP_cage (8180), out of the cage panel's reach (prompt from x ~ 8286)
const LINE_WALK_MIN := 200.0               # px of walk a route-point line gets before a prop prompt can hide its bubble (~0.9 s)
const BOARD_CAP := 60                      # frames of walking right from the panel into the boarding strip
const OVERLOAD_TEXT := "Not enough power: Work lights is running"
const HERO_FAR_EDGE := Vector2(8300, 320)  # the second boarding: from the far edge of the band
const DAN_BEHIND := Vector2(7900, 470)     # half a screen behind the cage
const BOARD_WALK_CAP := 90
const BEAT_MARGIN := 0.5
const SCENE_CHANGE_CAP_MS := 2000
const EXIT_APPROACH := Vector2(10100, 450)
const EXIT_WALK_CAP := 120

# The scene set under test. A v2 script (tests/smoke/v2_level_prologue_escape.gd) extends this one and overrides
# these three to run the same steps against scenes/v2/ — the v1 constants stay the defaults.
func _name() -> String:
	return NAME

func _prologue_path() -> String:
	return PROLOGUE_PATH

var _started := false
var _frames := 0
var _failures: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _process(_delta: float) -> bool:
	if not _started:
		_started = true
		_run()
	_frames += 1
	if _frames > MAX_FRAMES:
		print("SMOKE %s FAIL: exceeded %d frames without quit()" % [_name(), MAX_FRAMES])
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
		gs.CurrentScenePath = ""
	if _failures.is_empty():
		print("SMOKE %s PASS" % _name())
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [_name(), "; ".join(_failures)])
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

func _walk(player: Node, from: Vector2, distance: float) -> float:
	player.global_position = from
	await _step(2)
	Input.action_press("move_right")
	await _step(int(ceil(distance / SPEED * TICKS)) + WALK_SLACK)
	Input.action_release("move_right")
	await _step(2)
	return player.global_position.x

func _wait_restored(cap_ms: int) -> void:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < cap_ms and Engine.time_scale != 1.0:
		await process_frame

func _limits(camera: Camera2D) -> Array:
	return [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]

func _color_eq(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < COLOR_EPS and absf(a.g - b.g) < COLOR_EPS and absf(a.b - b.b) < COLOR_EPS

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

func _wp(level: Node, key: String) -> Vector2:
	return level.get("DanRoute").get_node("WP_" + key).global_position

func _build_level() -> Node:
	var scene: PackedScene = load(_prologue_path())
	_check(scene != null, "%s failed to load" % _prologue_path())
	if scene == null:
		return null
	var level: Node = scene.instantiate()
	root.add_child(level)
	current_scene = level   # GoToLevel swaps the tree's current scene, exactly as it does under Main
	await _settle()
	return level

# The band-edge gate probe (both edges blocked, the middle skipped: the heavy hits clear it below).
func _check_gate_blocked(player: Node, gate: Node, label: String) -> void:
	var box: Shape2D = gate.BlockerShape.shape
	if box is RectangleShape2D:
		var top: float = gate.BlockerShape.global_position.y - box.size.y * 0.5
		var bottom: float = gate.BlockerShape.global_position.y + box.size.y * 0.5
		_check(top <= player.FloorTop and bottom >= player.FloorBottom,
			"%s blocks Y %.0f..%.0f, expected the whole walk band %.0f..%.0f" % [label, top, bottom, player.FloorTop, player.FloorBottom])
	for depth in [player.FloorTop + BAND_MARGIN, player.FloorBottom - BAND_MARGIN]:
		var reached: float = await _walk(player, Vector2(gate.global_position.x - BLOCK_APPROACH, depth), GATE_WALK_FRAMES / TICKS * SPEED)
		_check(reached <= gate.global_position.x - BLOCK_MARGIN,
			"walking right at Y %.0f the hero reached x %.0f, past %s at x %.0f — the gate can be bypassed in depth" % [depth, reached, label, gate.global_position.x])
	_release_all()

func _check_gate_open(player: Node, gate: Node, label: String) -> void:
	for depth in [player.FloorTop + BAND_MARGIN, player.FloorBottom - BAND_MARGIN]:
		var open: float = await _walk(player, Vector2(gate.global_position.x - BLOCK_APPROACH, depth), GATE_WALK_FRAMES / TICKS * SPEED)
		_check(open >= gate.global_position.x + PASS_MARGIN,
			"with %s cleared the hero only reached x %.0f walking at Y %.0f, expected past x %.0f" % [label, open, depth, gate.global_position.x + PASS_MARGIN])
	_release_all()

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	var level: Node = await _build_level()
	if level == null:
		_finish()
		return
	var player: Node = level.get("Player")
	var lamp: Node = player.get("Flashlight") if player != null else null
	var cutscene: Node = level.get("Cutscene")
	var camera: Camera2D = level.get("Camera")
	var circuit: Node = level.get("Circuit")
	var dan: Node = level.get("Companion")
	var hud: Node = level.get("Hud")
	if player == null or lamp == null or cutscene == null or camera == null or circuit == null or dan == null or hud == null:
		_check(false, "the prologue lacks Player/Flashlight/Cutscene/Camera/Circuit/Companion/Hud")
		_finish()
		return
	var lights: Node = level.get("Lights")
	var cage: Node = level.get("Cage")
	var timber: Node = level.get("TimberPile")
	var patrol: Node = level.get("Patrol")
	var held_guards: Node = level.get("HeldGuards")
	var pockets: Array = Array(level.GasPockets)
	_check(pockets.size() == 2, "Level00_Prologue.GasPockets has %d entries, expected 2" % pockets.size())
	if lights == null or cage == null or timber == null or patrol == null or held_guards == null or pockets.size() != 2:
		_check(false, "the prologue's escape props are not wired")
		_finish()
		return

	var finished: Array = [0]
	cutscene.Finished.connect(func(): finished[0] += 1)
	var stages: Array = []
	level.StageChanged.connect(func(s: String): stages.append(s))
	var lines: Array = []
	var lamp_at_line: Dictionary = {}
	dan.LineShown.connect(func(t: String):
		lines.append(t)
		lamp_at_line[t] = dan.IsLampOn)
	var warnings: Array = []
	var ignitions: Array = []
	for p in pockets:
		p.WarningStarted.connect(func(): warnings.append(true))
		p.Ignited.connect(func(_pl): ignitions.append(true))
	var refused: Array = []
	cage.ActivationRefused.connect(func(): refused.append(true))
	var refusals: Array = []
	circuit.RequestRefused.connect(func(m, b): refusals.append([m, b]))

	await _play_out(cutscene, finished, "intro")
	_check(player.process_mode == Node.PROCESS_MODE_INHERIT, "the hero is still frozen after the intro")
	# The patrol is segment 3's business (level_prologue_patrol.gd); here it must not wander into
	# the cage screen while the refusal and the capture are measured.
	patrol.process_mode = Node.PROCESS_MODE_DISABLED

	# 1. Segment 2: the timber — a gate at both edges, bounced by a punch, cleared by two heavy hits.
	await _place(player, CP_DRIFT)
	_check(level.CurrentStage == STAGE_DRIFT, "at Checkpoint_Drift the stage is %s, expected Drift" % level.CurrentStage)
	_check(dan.LeadTarget == _wp(level, "timber"), "at the drift Dan's point is %s, expected WP_timber" % dan.LeadTarget)
	var arrived: int = await _wait_until(func(): return dan.IsAtLeadTarget, DAN_CAP)
	_check(arrived >= 0, "Dan never reached the timber point")
	_check(timber.HeavyHitsToClear == 2, "the timber pile wants %s heavy hits, expected 2" % timber.HeavyHitsToClear)
	await _check_gate_blocked(player, timber, "DebrisPile_Timber")
	await _place(player, HIT_STAND)
	await _wait_until(func(): return lines.has(level.DanTimberLine), BUBBLE_CAP)
	_check(lines.has(level.DanTimberLine), "Dan did not say the timber line when the hero reached him (%s)" % [lines])
	await _tap("attack")
	await _wait_until(func(): return lines.has(level.DanResistedLine), BUBBLE_CAP)
	_check(lines.has(level.DanResistedLine), "a light attack on the timber did not get Dan's bounce line (%s)" % [lines])
	_check(timber.IsCleared == false and timber.HitsLeft == 2, "a light attack damaged the timber (hits left %d)" % timber.HitsLeft)
	await _step(20)
	await _place(player, HIT_STAND)
	await _tap("heavy_attack")
	var first_hit: int = await _wait_until(func(): return timber.HitsLeft == 1, HIT_CAP)
	_check(first_hit >= 0, "the first heavy attack did not land on the timber (hits left %d)" % timber.HitsLeft)
	await _wait_restored(RESTORE_CAP_MS)
	await _step(SWING_FRAMES)
	await _place(player, HIT_STAND)
	await _tap("heavy_attack")
	var cleared: int = await _wait_until(func(): return timber.IsCleared, HIT_CAP)
	_check(cleared >= 0, "the second heavy attack did not clear the timber")
	await _wait_restored(RESTORE_CAP_MS)
	_release_all()
	await _step(SWING_FRAMES)
	_check(lines.has(level.DanClearedLine), "Dan did not say the cleared line (%s)" % [lines])
	_check(dan.LeadTarget == _wp(level, "gas_edge"), "with the timber down Dan's point is %s, expected WP_gas_edge" % dan.LeadTarget)
	await _check_gate_open(player, timber, "DebrisPile_Timber")

	# 2. The edge of the gas: lamp out first, then the line; he waits for the hero's lamp.
	await _place(player, GAS_APPROACH)
	var at_edge: int = await _wait_until(func(): return dan.IsAtLeadTarget and dan.LeadTarget == _wp(level, "gas_edge"), DAN_CAP)
	_check(at_edge >= 0, "Dan never reached the edge of the gas")
	var warned: int = await _wait_until(func(): return lines.has(level.DanGasWarnLine), BUBBLE_CAP)
	_check(warned >= 0, "Dan did not say the gas warning line at the edge (%s)" % [lines])
	_check(dan.IsLampOn == false, "Dan's lamp is on at the edge of the gas")
	_check(lamp_at_line.get(level.DanGasWarnLine, true) == false, "Dan said the gas line while his lamp was still on — the rule must be shown before it is said")
	_check(dan.IsWarning == true and dan.Facing == 1, "Dan at the gas edge: warning %s / facing %d, expected the warning stance facing the gas" % [dan.IsWarning, dan.Facing])
	for i in pockets.size():
		var shape: CollisionShape2D = pockets[i].get_node_or_null("CollisionShape2D")
		_check(shape != null and shape.shape is RectangleShape2D, "GasPockets[%d] has no rectangular trigger shape" % i)
		if shape != null and shape.shape is RectangleShape2D:
			var top: float = shape.global_position.y - shape.shape.size.y * 0.5
			var bottom: float = shape.global_position.y + shape.shape.size.y * 0.5
			_check(top <= player.FloorTop and bottom >= player.FloorBottom,
				"%s covers Y %.0f..%.0f, expected the whole walk band" % [pockets[i].name, top, bottom])
		_check(is_equal_approx(pockets[i].WarningSeconds, 1.2), "%s's window is %s s, expected 1.2" % [pockets[i].name, pockets[i].WarningSeconds])
	lamp.SetOn(true)
	await _place(player, GAS_REACH)
	_check(level.CurrentStage == STAGE_GAS, "at Checkpoint_GasNear the stage is %s, expected Gas" % level.CurrentStage)
	_check(level.ArmedCheckpoint != null and level.ArmedCheckpoint.Label == "gas_near", "the checkpoint before the gas is %s" % level.ArmedCheckpoint)
	await _step(5)
	_check(dan.LeadTarget == _wp(level, "gas_edge"), "Dan went on into the gas (point %s) while the hero's lamp was on" % dan.LeadTarget)
	lamp.SetOn(false)
	await _step(3)
	_check(dan.LeadTarget == _wp(level, "past_gas"), "after the lamp went off Dan's point is %s, expected WP_past_gas" % dan.LeadTarget)
	_check(dan.LeadLeashed == false, "Dan crosses the pocket with the leash on; he must run it")
	var crossed: int = await _wait_until(func(): return dan.IsAtLeadTarget, DAN_CAP)
	_check(crossed >= 0, "Dan never reached the far side of the gas")
	await _step(2)
	_check(dan.IsLampOn == true, "Dan's lamp is still off on the far side of the gas")
	_check(warnings.is_empty(), "a pocket started a warning while Dan crossed it (%d) — he is scenery to the gas" % warnings.size())

	# 3. The hero crosses dark: nothing ignites, nothing is powered, the checkpoint past the gas arms.
	var reached: float = await _walk(player, DARK_START, DARK_END_X - DARK_START.x)
	_check(reached >= DARK_END_X - 20.0, "the dark walk ended at x %.0f, expected past %.0f" % [reached, DARK_END_X - 20.0])
	_check(warnings.is_empty() and ignitions.is_empty(), "the pocket reacted to a hero with the lamp off")
	_check(player.IsKnockedOut == false, "the hero died crossing the pocket in the dark")
	_check(pockets[0].IsCleared == false and pockets[1].IsCleared == false, "the pocket was cleared; nothing in this level clears the gas")
	await _wait_until(func(): return lines.has(level.DanGasPastLine), BUBBLE_CAP)
	_check(lines.has(level.DanGasPastLine), "Dan did not say the past-gas line when the hero reached him (%s)" % [lines])
	_check(dan.LeadTarget == _wp(level, "drift_exit"), "past the gas Dan's point is %s, expected WP_drift_exit" % dan.LeadTarget)
	await _place(player, CP_PAST_GAS)
	_check(level.ArmedCheckpoint != null and level.ArmedCheckpoint.Label == "past_gas", "there is no checkpoint right after the pocket")
	_check(circuit.Used == 1, "Circuit.Used=%s in the drift, expected 1 (only the work lights, untouched)" % circuit.Used)

	# 4. Segment 4: the lights hold the bus, the cage refuses, the lights go off, the cage runs.
	await _place(player, CP_CAGE)
	_check(level.CurrentStage == STAGE_CAGE, "at Checkpoint_Cage the stage is %s, expected Cage" % level.CurrentStage)
	_check(_limits(camera) == ROOM_PATROL_LIMITS, "camera limits %s at the cage, expected %s" % [_limits(camera), ROOM_PATROL_LIMITS])
	_check(dan.LeadTarget == _wp(level, "cage"), "at the cage checkpoint Dan's point is %s, expected WP_cage" % dan.LeadTarget)
	_check(lights.StartsPowered == true and lights.IsPowered == true and lights.IsActivated == true, "the work lights do not hold the bus at the cage")
	_check(absf(cage.global_position.x - lights.global_position.x) <= 1120.0,
		"the lights panel (x %.0f) and the cage (x %.0f) are not on one screen" % [lights.global_position.x, cage.global_position.x])
	var drift_lamps: Node = lights.get("RunFx")
	_check(drift_lamps != null and drift_lamps.visible == true, "the drift lamps are dark although the work lights hold the bus")
	await _wait_until(func(): return dan.IsAtLeadTarget, DAN_CAP)
	# S3 (v3 review): the cage line must live before the cage panel's prompt can hide its bubble —
	# HeroReached fires HeroCloseDistance short of WP_cage, the prompt where the hero's
	# InteractionArea meets the panel's reach; the walk between the two is the bubble's life.
	var cage_reach: CollisionShape2D = cage.get_node("CollisionShape2D")
	var hero_reach: CollisionShape2D = player.get("InteractionArea").get_node("CollisionShape2D")
	var cage_prompt_x: float = cage.global_position.x + cage_reach.position.x - cage_reach.shape.radius - hero_reach.shape.radius
	var cage_line_x: float = _wp(level, "cage").x - dan.HeroCloseDistance
	_check(cage_prompt_x - cage_line_x >= LINE_WALK_MIN, "the cage line fires at x %.0f and the cage panel's prompt at x %.0f: %.0f px of walk for the bubble, expected >= %.0f (the prompt would hide it the moment it is said)" % [cage_line_x, cage_prompt_x, cage_prompt_x - cage_line_x, LINE_WALK_MIN])
	await _place(player, NEAR_CAGE)
	await _wait_until(func(): return lines.has(level.DanCageLine), BUBBLE_CAP)
	_check(lines.has(level.DanCageLine), "Dan did not say the cage line when the hero reached him (%s)" % [lines])
	await _step(3)
	_check(hud.PromptText == "", "the HUD shows '%s' where the cage line is said — a prompt hides the bubble" % hud.PromptText)
	_check(dan.Bubble.visible == true and dan.Bubble.text == level.DanCageLine, "the cage line is not on screen (bubble visible %s, text '%s') — it must be seen, not only emitted" % [dan.Bubble.visible, dan.Bubble.text])
	# S2 (v3 review): the lights panel's prompt must not name the solution before the cage refused.
	_check(not lights.ActivatedPromptText.to_lower().contains("cut"), "the lights panel's prompt '%s' hands the puzzle its answer" % lights.ActivatedPromptText)
	await _place(player, NEAR_HOIST)
	await _use_panel(cage, player, [])
	_check(refused.size() == 1 and refusals.size() == 1, "the cage was refused %d / %d times, expected once" % [refused.size(), refusals.size()])
	if refusals.size() > 0:
		_check(refusals[0][0] == cage and refusals[0][1] == lights, "the refusal was %s blocked by %s, expected the cage blocked by the work lights" % [refusals[0][0], refusals[0][1]])
	_check(cage.IsPowered == false and cage.CanInteract == true, "the refused cage is powered %s / usable %s" % [cage.IsPowered, cage.CanInteract])
	await _place(player, NEAR_HOIST)
	_check(hud.PromptText.contains(OVERLOAD_TEXT), "the HUD reads '%s', expected it to contain '%s'" % [hud.PromptText, OVERLOAD_TEXT])
	_check(lines.count(level.DanRuleLine) == 1, "Dan said the rule line %d times after one refusal (%s)" % [lines.count(level.DanRuleLine), lines])
	_check(dan.Bubble.visible == false, "Dan's bubble shows under the cage panel's prompt — a bubble loses to a prompt")
	await _place(player, NEAR_CAGE)
	await _step(2)
	_check(hud.PromptText == "" and dan.Bubble.visible == true and dan.Bubble.text == level.DanRuleLine, "a step back from the panel did not bring the rule line back (prompt '%s', bubble visible %s, text '%s')" % [hud.PromptText, dan.Bubble.visible, dan.Bubble.text])
	await _place(player, NEAR_HOIST)
	await _real_wait(3.1)   # the ≥ 3 s gap between two lines
	await _use_panel(cage, player, [])
	_check(refused.size() == 2, "the second attempt was refused %d times in total, expected 2" % refused.size())
	_check(lines.count(level.DanRuleLine) == 1 and lines.has(level.DanRefusedLine), "the second refusal did not get the different line (%s)" % [lines])
	var pool_shapes: Array = []
	for pool in level.PatrolPools:
		pool_shapes.append(pool.get_node("CollisionShape2D"))
	_check(pool_shapes.size() == 3, "PatrolPools holds %d zones, expected 3" % pool_shapes.size())
	for s in pool_shapes:
		_check(s.disabled == false, "a lamp pool is off while the work lights run")
	await _place(player, NEAR_LIGHTS)
	await _use_panel(lights, player, [])
	_check(lights.IsPowered == false and circuit.Used == 0, "the work lights are still running (powered %s, Used %s)" % [lights.IsPowered, circuit.Used])
	await _step(3)
	for s in pool_shapes:
		_check(s.disabled == true, "a lamp pool is still live with the work lights off — an invisible Area2D keeps colliding")
	_check(drift_lamps.visible == false, "the drift lamps are still lit with the work lights off")
	_check(dan.IsLampOn == true, "Dan's lamp did not come back with the drift dark")
	_check(lines.has(level.DanDarkLine), "Dan did not say the dark line (%s)" % [lines])
	await _real_wait(level.DarknessFadeSeconds + FADE_MARGIN)
	_check(_color_eq(level.Darkness.color, level.DarknessMine), "the drift is %s with the lights off, expected DarknessMine" % level.Darkness.color)
	var energy_before: float = gs.Energy
	await _place(player, NEAR_HOIST)
	await _use_panel(cage, player, [])
	_check(cage.IsPowered == true and circuit.Used == 1, "the cage did not start on the freed bus (powered %s, Used %s)" % [cage.IsPowered, circuit.Used])
	_check(cage.HasDeparted == false, "the cage departed under the hand that started it — the panel's reach overlaps the boarding strip")
	_check(lines.has(level.DanBoardLine), "Dan did not say the board line (%s)" % [lines])
	_check(dan.LeadTarget == _wp(level, "board") and dan.LeadLeashed == false, "with the cage running Dan's point is %s (leashed %s), expected a run to WP_board" % [dan.LeadTarget, dan.LeadLeashed])
	Input.action_press("move_right")
	var boarded1: int = await _wait_until(func(): return cage.HasDeparted, BOARD_CAP)
	Input.action_release("move_right")
	_check(boarded1 >= 0, "walking right from the panel never stepped into the running cage")
	await _step(3)

	# 5. Segment 5: the capture — a fixed picture, whatever the player did.
	_check(cage.HasDeparted == true, "the hero stepped into the running cage and it did not depart")
	_check(level.CurrentStage == STAGE_HELD, "after boarding the stage is %s, expected Held" % level.CurrentStage)
	_check(player.global_position == level.HeroHeldAt, "the hero stands at %s for the capture, expected HeroHeldAt %s" % [player.global_position, level.HeroHeldAt])
	_check(dan.global_position == level.DanHeldAt, "Dan stands at %s for the capture, expected DanHeldAt %s" % [dan.global_position, level.DanHeldAt])
	_check(dan.IsWaiting == true, "Dan is in '%s' for the capture, expected the scripted hold" % dan.CurrentStateName)
	_check(held_guards.visible == true, "the guards from behind are not shown for the capture")
	_check(held_guards.global_position.x < cage.global_position.x, "the guards stand at x %.0f, expected behind the cage (x %.0f) — they come up the drift" % [held_guards.global_position.x, cage.global_position.x])
	_check(cutscene.IsPlaying == true and cutscene.LineCount == 8, "the Held cutscene is not playing (%s / %d lines)" % [cutscene.IsPlaying, cutscene.LineCount])
	_check(player.process_mode == Node.PROCESS_MODE_DISABLED, "the hero is not frozen for the capture")
	_check(patrol.process_mode == Node.PROCESS_MODE_DISABLED, "the patrol runs during the capture")
	await _play_out(cutscene, finished, "held")
	_check(dan.IsGone == true and dan.visible == false, "Dan is still in play after the capture (gone %s, visible %s)" % [dan.IsGone, dan.visible])
	_check(level.get("Companion") == null, "the level still holds a Companion reference after the capture")
	_check(held_guards.visible == false, "the guards are still shown after they took Dan away")
	_check(player.process_mode == Node.PROCESS_MODE_DISABLED, "the hero got control during the black beat")
	_check(level.CurrentStage == STAGE_HELD, "the stage moved to %s during the black beat" % level.CurrentStage)
	await _real_wait(level.DarknessFadeSeconds + 0.2)
	_check(_color_eq(level.Darkness.color, level.DarknessBlack), "the screen is %s during the beat, expected black" % level.Darkness.color)
	_check(level.CurrentStage == STAGE_HELD, "the surface came up before the black beat ran out")
	await _real_wait(maxf(level.BlackBeatSeconds - level.DarknessFadeSeconds - 0.2, 0.0) + BEAT_MARGIN)
	await _step(2)
	_check(level.CurrentStage == STAGE_SURFACE, "after the black beat the stage is %s, expected Surface" % level.CurrentStage)
	_check(player.global_position.distance_to(level.SurfaceArrival) <= 2.0, "the surface put the hero at %s, expected %s" % [player.global_position, level.SurfaceArrival])
	_check(_limits(camera) == ROOM_SURFACE_LIMITS, "camera limits %s on the surface, expected %s" % [_limits(camera), ROOM_SURFACE_LIMITS])
	_check(level.ArmedCheckpoint != null and level.ArmedCheckpoint.Label == "surface", "the armed checkpoint on the surface is %s, expected 'surface'" % level.ArmedCheckpoint)
	_check(level.ArmedCheckpoint == null or level.ArmedCheckpoint.Room == level.get("SurfaceRoom"), "the surface checkpoint re-applies a room that is not Room_Surface")
	_check(cutscene.IsPlaying == true and cutscene.LineCount == 5, "the Surface cutscene is not playing (%s / %d lines)" % [cutscene.IsPlaying, cutscene.LineCount])
	_check(is_equal_approx(gs.Energy, energy_before), "the capture changed the energy from %s to %s — Dan's bank is never added (§2)" % [energy_before, gs.Energy])
	await _play_out(cutscene, finished, "surface")
	_check(player.process_mode == Node.PROCESS_MODE_INHERIT, "the hero is still frozen on the surface")
	await _real_wait(level.DarknessFadeSeconds + FADE_MARGIN)
	_check(_color_eq(level.Darkness.color, level.DarknessSurface), "the surface is %s, expected DarknessSurface" % level.Darkness.color)

	# 6. A KO up top respawns up top, never below.
	var level_id: int = level.get_instance_id()
	player.Kill()
	await _real_wait(level.RespawnDelay + DELAY_MARGIN)
	await _step(2)
	_check(is_instance_valid(level) and level.get_instance_id() == level_id, "a KO on the surface reloaded the level")
	_check(player.IsKnockedOut == false and player.global_position.x >= ROOM_SURFACE_LIMITS[0],
		"a KO on the surface put the hero at %s (KO %s), expected back on the surface" % [player.global_position, player.IsKnockedOut])

	# 7. Walking off the surface hands the run to level 1.
	player.global_position = EXIT_APPROACH
	await _step(2)
	Input.action_press("move_right")
	var done: int = await _wait_until(func(): return level.CurrentStage == STAGE_DONE, EXIT_WALK_CAP)
	Input.action_release("move_right")
	_check(done >= 0, "walking east from x %.0f never reached the level exit" % EXIT_APPROACH.x)
	_check(stages == ["Face", "Drift", "Gas", "Cage", "Held", "Surface", "Done"], "the stage sequence was %s" % [stages])
	var deadline: int = Time.get_ticks_msec() + SCENE_CHANGE_CAP_MS
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if current_scene != null and current_scene.scene_file_path == LEVEL01_PATH:
			break
	_check(current_scene != null and current_scene.scene_file_path == LEVEL01_PATH, "after the exit the current scene is %s, expected %s" % [current_scene, LEVEL01_PATH])
	_check(gs.CurrentScenePath == LEVEL01_PATH, "GameState.CurrentScenePath is '%s', expected %s" % [gs.CurrentScenePath, LEVEL01_PATH])
	if current_scene != null:
		current_scene.queue_free()
	current_scene = null
	await _step(2)

	# 8. The capture is the same picture from the far edge with Dan half a screen behind.
	gs.ResetRun()
	var level2: Node = await _build_level()
	if level2 == null:
		_finish()
		return
	var player2: Node = level2.get("Player")
	var cutscene2: Node = level2.get("Cutscene")
	var dan2: Node = level2.get("Companion")
	var cage2: Node = level2.get("Cage")
	var lights2: Node = level2.get("Lights")
	var held2: Node = level2.get("HeldGuards")
	var finished2: Array = [0]
	cutscene2.Finished.connect(func(): finished2[0] += 1)
	var lines2: Array = []
	dan2.LineShown.connect(func(t: String): lines2.append(t))
	await _play_out(cutscene2, finished2, "intro 2")
	level2.get("Patrol").process_mode = Node.PROCESS_MODE_DISABLED
	await _place(player2, CP_CAGE)
	lights2.PowerDown()
	await _step(3)
	dan2.WarpTo(DAN_BEHIND)
	await _step(2)
	await _place(player2, HERO_FAR_EDGE)
	cage2.ForcePower()
	await _step(2)
	_check(cage2.IsPowered == true and cage2.HasDeparted == false, "the cage departed before the hero stepped in (powered %s, departed %s)" % [cage2.IsPowered, cage2.HasDeparted])
	_check(lines2.has(level2.DanBoardLine) and dan2.LeadTarget == _wp(level2, "board"), "second boarding: Dan did not get the board line / the run to the gate (%s, %s)" % [lines2, dan2.LeadTarget])
	Input.action_press("move_right")
	var boarded: int = await _wait_until(func(): return cage2.HasDeparted, BOARD_WALK_CAP)
	Input.action_release("move_right")
	_check(boarded >= 0, "walking into the cage from the far edge never departed it")
	await _step(2)
	_check(level2.CurrentStage == STAGE_HELD, "second boarding: the stage is %s, expected Held" % level2.CurrentStage)
	_check(player2.global_position == level2.HeroHeldAt, "second boarding: the hero stands at %s, expected HeroHeldAt %s — the capture must not depend on where he boarded from" % [player2.global_position, level2.HeroHeldAt])
	_check(dan2.global_position == level2.DanHeldAt, "second boarding: Dan stands at %s, expected DanHeldAt %s — the capture must not depend on where he was" % [dan2.global_position, level2.DanHeldAt])
	_check(dan2.IsWaiting == true and held2.visible == true, "second boarding: Dan %s / guards shown %s" % [dan2.CurrentStateName, held2.visible])
	_check(cutscene2.IsPlaying == true and cutscene2.CurrentLine == 0 and cutscene2.LineCount == 8, "second boarding: the Held cutscene is not at its first screen")
	_check(player2.process_mode == Node.PROCESS_MODE_DISABLED, "second boarding: the hero is not frozen")
	level2.queue_free()
	await _step(2)
	_finish()
