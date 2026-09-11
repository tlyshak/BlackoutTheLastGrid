extends SceneTree
# Smoke: the one seal of the third-revision prologue can never land on the hero (T-07s-e).
#
# The blast is scripted, not a walk trigger with a delay: CaveIn_Blast ships with monitoring off
# and the level calls Collapse() itself, only after it has frozen the hero for the Blast cutscene.
# Two things set it off — the hero walking into the trigger past the props, or Dan's HeroReached at
# the props — and both are placed so that a hero who fires them stands clear of the seal's blocker:
# the trigger ≥ 200 px past the seal, the props point farther than HeroCloseDistance plus the
# hero's half-width past the blocker's end. The charge panel's reach ends short of the seal too, so
# the hero can never stand inside the rubble while the roof is still up. A pile with
# HeavyHitsToClear = 0 can never be opened again, so every one of these margins is a soft-lock if
# it slips (review round 1 of T-07s-b, B1).
#
# Both ways in are driven: pass A walks the hero from the motor into the trigger; pass B warps Dan to
# the props and puts the hero in his reach. In both, at the moment Collapsed fires the hero is
# frozen with his left edge past the blocker; afterwards the seal is solid at three depths, the jam
# is open, and walking over CaveIn_Blast from either side before the charge does nothing.
# Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/level_seals.gd

const NAME := "level_seals"   # must equal the file basename
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const PROLOGUE_PATH := "res://scenes/levels/Level00_Prologue.tscn"
const SETTLE_CAP := 20
const SETTLE_DELTA := 0.05
const OVERLAP_FRAMES := 4
const CUTSCENE_CAP := 40
const ATTEMPT_CAP := 80
const BAND_Y := 450.0
const BAND_MARGIN := 20.0
const HERO_HALF_W := 14.0
const WALK_FRAMES := 58
const BLAST_WALK_CAP := 240
const MIN_TRIGGER_MARGIN := 200.0
const NEAR_CHARGE := Vector2(1140, 450)
const CHARGE_SEQUENCE := ["move_up", "attack", "move_down", "jump"]
const CAVEIN_LEFT := Vector2(1290, 450)    # 90 px left of CaveIn_Blast's shape
const CAVEIN_RIGHT := Vector2(1470, 450)
const HERO_IN_REACH := Vector2(1470, 450)  # within HeroCloseDistance (160) of WP_props (1620), outside the trigger
const SEAL_PROBE_X := 1450.0

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

func _wait_until(cond: Callable, cap: int) -> int:
	for i in cap:
		if cond.call():
			return i
		await physics_frame
	return -1

func _play_out(cutscene: Node, label: String) -> void:
	var guard := 0
	while cutscene.IsPlaying and guard < CUTSCENE_CAP:
		cutscene.Advance()
		guard += 1
		await _step(1)
	_check(not cutscene.IsPlaying, "%s: the cutscene never ended after %d advances" % [label, guard])
	await _step(3)

func _use_panel(panel: Node, player: Node, sequence: Array) -> void:
	panel.Begin(player)
	await _step(2)
	for action in sequence:
		await _tap(action)
		await _step(2)
	await _wait_until(func(): return not panel.IsActive, ATTEMPT_CAP)
	await _step(2)

func _blocker_edges(pile: Node) -> Array:
	var box: Shape2D = pile.BlockerShape.shape
	var half := 0.0
	if box is RectangleShape2D:
		half = (box as RectangleShape2D).size.x * 0.5
	return [pile.BlockerShape.global_position.x - half, pile.BlockerShape.global_position.x + half]

func _spans_band(shape: CollisionShape2D, label: String) -> void:
	if shape.shape is RectangleShape2D:
		var top: float = shape.global_position.y - shape.shape.size.y * 0.5
		var bottom: float = shape.global_position.y + shape.shape.size.y * 0.5
		_check(top <= 300.0 and bottom >= 600.0, "%s covers Y %.0f..%.0f, expected the whole walk band 300..600" % [label, top, bottom])
	else:
		_check(false, "%s's shape is not a rectangle" % label)

func _walk(player: Node, from: Vector2, action: String, frames: int) -> float:
	player.global_position = from
	await _step(2)
	Input.action_press(action)
	await _step(frames)
	Input.action_release(action)
	await _step(2)
	return player.global_position.x

func _build_level() -> Node:
	var scene: PackedScene = load(PROLOGUE_PATH)
	_check(scene != null, "%s failed to load" % PROLOGUE_PATH)
	if scene == null:
		return null
	var level: Node = scene.instantiate()
	root.add_child(level)
	current_scene = level
	await _settle()
	return level

# Checks everything after the roof came down: the frozen hero on the open side, the solid seal, the open jam.
func _check_after(level: Node, player: Node, sample: Array, label: String) -> void:
	var blast: Node = level.get("BlastCollapse")
	var seal: Node = level.get_node("DebrisPile_BlastSeal")
	var jam: Node = level.get("Jam")
	var edges: Array = _blocker_edges(seal)
	_check(blast.HasCollapsed == true, "%s: the roof never came down" % label)
	_check(sample.size() == 1, "%s: Collapsed fired %d times, expected 1" % [label, sample.size()])
	if sample.size() == 1:
		_check(sample[0][0] == Node.PROCESS_MODE_DISABLED, "%s: the roof came down on a hero who was not frozen" % label)
		var left: float = sample[0][1] - HERO_HALF_W
		_check(left > edges[1],
			"%s: at the collapse the hero stood at x %.0f — his left edge %.0f is inside or behind the seal (blocker ends at x %.0f). The pile has HeavyHitsToClear = 0, so the run is locked with no exit but the main menu."
			% [label, sample[0][1], left, edges[1]])
	_check(seal.IsCleared == false, "%s: the drift is still open behind the hero" % label)
	_check(jam.IsCleared == true, "%s: the jam ahead is still closed after the blast" % label)
	_check(player.IsKnockedOut == false, "%s: the collapse killed the hero" % label)
	_check(level.get("BlastTrigger").monitoring == false, "%s: the props trigger is still armed after the blast" % label)
	await _play_out(level.get("Cutscene"), label + " blast")
	for depth in [300.0 + BAND_MARGIN, BAND_Y, 600.0 - BAND_MARGIN]:
		var x: float = await _walk(player, Vector2(SEAL_PROBE_X, depth), "move_left", WALK_FRAMES)
		_check(x - HERO_HALF_W >= edges[1] - 1.0, "%s: walking left at Y %.0f the hero got to x %.0f, into the sealed roof (blocker ends at %.0f)" % [label, depth, x, edges[1]])
	_release_all()

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	# 1. The authored margins, before a single frame is simulated.
	var level: Node = await _build_level()
	if level == null:
		_finish()
		return
	var player: Node = level.get("Player")
	var cutscene: Node = level.get("Cutscene")
	var dan: Node = level.get("Companion")
	var blast: Node = level.get("BlastCollapse")
	var trigger: Node = level.get("BlastTrigger")
	var charge: Node = level.get("Charge")
	var seal: Node = level.get_node_or_null("DebrisPile_BlastSeal")
	var jam: Node = level.get("Jam")
	var route: Node = level.get("DanRoute")
	if player == null or cutscene == null or dan == null or blast == null or trigger == null or charge == null or seal == null or jam == null or route == null:
		_check(false, "the prologue lacks Player/Cutscene/Companion/BlastCollapse/BlastTrigger/Charge/DebrisPile_BlastSeal/Jam/DanRoute")
		_finish()
		return
	var edges: Array = _blocker_edges(seal)
	_check(blast.monitoring == false, "CaveIn_Blast is monitoring — the blast must be scripted only")
	_check(is_equal_approx(blast.Delay, 0.0), "CaveIn_Blast.Delay=%s, expected 0 (nothing may move between the freeze and the rubble)" % blast.Delay)
	_check(blast.get("Blockage") == seal, "CaveIn_Blast.Blockage is not DebrisPile_BlastSeal")
	_check(seal.HeavyHitsToClear == 0 and seal.StartsCleared == true, "the seal is not a HeavyHitsToClear = 0 pile that starts cleared")
	var trigger_shape: CollisionShape2D = trigger.get_node("CollisionShape2D")
	var trigger_left: float = trigger.global_position.x - trigger_shape.shape.size.x * 0.5
	_check(trigger.global_position.x - seal.global_position.x >= MIN_TRIGGER_MARGIN,
		"BlastTrigger sits %.0f px past the seal, expected at least %.0f" % [trigger.global_position.x - seal.global_position.x, MIN_TRIGGER_MARGIN])
	_check(trigger_left - HERO_HALF_W > edges[1], "a hero entering BlastTrigger (from x %.0f) still has his left edge inside the seal (ends %.0f)" % [trigger_left, edges[1]])
	var props: Vector2 = route.get_node("WP_props").global_position
	_check(props.x - dan.HeroCloseDistance - HERO_HALF_W > edges[1],
		"WP_props at x %.0f minus HeroCloseDistance %.0f minus the hero's half-width is not past the seal's blocker end %.0f — Dan's HeroReached could fire the blast on a hero inside the rubble"
		% [props.x, dan.HeroCloseDistance, edges[1]])
	var reach: CollisionShape2D = charge.get_node("CollisionShape2D")
	_check(reach.shape is CircleShape2D and charge.global_position.x + reach.shape.radius + HERO_HALF_W < edges[0],
		"the charge panel's reach ends at x %.0f; a hero using it could stand inside the seal (blocker starts at %.0f)" % [charge.global_position.x + reach.shape.radius + HERO_HALF_W, edges[0]])
	_spans_band(trigger_shape, "BlastTrigger")
	_spans_band(jam.BlockerShape, "DebrisPile_Jam")
	_spans_band(seal.BlockerShape, "DebrisPile_BlastSeal")
	var shaft: Node = level.get_node_or_null("PH_WallShaft")
	_check(shaft is StaticBody2D and shaft.collision_layer == 1, "PH_WallShaft is missing or not a World-layer wall")
	if shaft is StaticBody2D:
		_spans_band(shaft.get_node("CollisionShape2D"), "PH_WallShaft")
	_check(jam.HeavyHitsToClear == 0 and jam.IsCleared == false, "the jam is not a closed HeavyHitsToClear = 0 pile at boot")

	# 2. Pass A: walking over the cave-in before the charge does nothing; then the walk past the props.
	await _play_out(cutscene, "intro A")
	var right: float = await _walk(player, CAVEIN_LEFT, "move_right", WALK_FRAMES)
	_check(right > blast.global_position.x + 60.0, "the hero did not cross CaveIn_Blast walking right (at x %.0f)" % right)
	var left: float = await _walk(player, CAVEIN_RIGHT, "move_left", WALK_FRAMES)
	_check(left < blast.global_position.x - 60.0, "the hero did not cross CaveIn_Blast walking left (at x %.0f)" % left)
	_check(blast.IsTriggered == false and blast.HasCollapsed == false and seal.IsCleared == true,
		"walking over CaveIn_Blast before the charge triggered it (triggered %s, collapsed %s)" % [blast.IsTriggered, blast.HasCollapsed])
	player.global_position = NEAR_CHARGE
	await _step(OVERLAP_FRAMES)
	await _use_panel(charge, player, CHARGE_SEQUENCE)
	_check(charge.IsActivated == true and cutscene.IsPlaying == true, "the charge did not activate / the Charge cutscene did not start")
	await _play_out(cutscene, "charge A")
	var sample_a: Array = []
	blast.Collapsed.connect(func(): sample_a.append([player.process_mode, player.global_position.x]))
	Input.action_press("move_right")
	var walked: int = await _wait_until(func(): return blast.HasCollapsed, BLAST_WALK_CAP)
	Input.action_release("move_right")
	_check(walked >= 0, "pass A: walking right from the motor never set the blast off")
	await _step(2)
	await _check_after(level, player, sample_a, "pass A")
	level.queue_free()
	await _step(2)

	# 3. Pass B: Dan's HeroReached at the props fires it, with the hero in his reach and the trigger untouched.
	gs.ResetRun()
	var level_b: Node = await _build_level()
	if level_b == null:
		_finish()
		return
	var player_b: Node = level_b.get("Player")
	var cutscene_b: Node = level_b.get("Cutscene")
	var dan_b: Node = level_b.get("Companion")
	var blast_b: Node = level_b.get("BlastCollapse")
	var charge_b: Node = level_b.get("Charge")
	var props_b: Vector2 = level_b.get("DanRoute").get_node("WP_props").global_position
	await _play_out(cutscene_b, "intro B")
	player_b.global_position = NEAR_CHARGE
	await _step(OVERLAP_FRAMES)
	await _use_panel(charge_b, player_b, CHARGE_SEQUENCE)
	await _play_out(cutscene_b, "charge B")
	var sample_b: Array = []
	blast_b.Collapsed.connect(func(): sample_b.append([player_b.process_mode, player_b.global_position.x]))
	dan_b.WarpTo(props_b)
	await _step(2)
	_check(dan_b.IsAtLeadTarget == true, "Dan warped to the props is not at his point (%s → %s)" % [dan_b.global_position, dan_b.LeadTarget])
	player_b.global_position = HERO_IN_REACH
	var fired: int = await _wait_until(func(): return blast_b.HasCollapsed, OVERLAP_FRAMES * 3)
	_check(fired >= 0, "pass B: the hero in Dan's reach at the props did not set the blast off")
	await _step(2)
	await _check_after(level_b, player_b, sample_b, "pass B")
	level_b.queue_free()
	await _step(2)
	_finish()
