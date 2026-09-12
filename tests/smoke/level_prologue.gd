extends SceneTree
# Smoke: the first half of the third-revision prologue (T-07s-e), driven end to end through
# Main.tscn — Main instantiates Level00_Prologue and records GameState.CurrentScenePath (no
# exposition on this path); the coalface cutscene plays with the hero frozen and `interact` taps
# advance it; every player-visible string is English; segment 0 (the move hint, the crate that
# blocks a walk at every depth and yields to a jump, the cart-train jam that blocks the drift at
# every depth, Dan holding past the crate through the intro and leading to the motor after it);
# the charge (the one repair sequence of the level → the Charge cutscene, Dan running behind the
# props); the scripted blast (fires from the walk past the props or from Dan's HeroReached, with
# the hero frozen and on the open side of the seal, the jam thrown clear, the lamps dead, the mine
# black); segment 1 (Checkpoint_Dark, the head-lamp hint, the first outlet, the wave of two guards
# lit by their own hand lamp behind the Guards cutscene, the attack and heavy hints, two powerbanks
# dropped, one taken with `E` — Dan's «that's ours now» — the camera lock released, Dan led on to
# the face exit); ends at Stage.Drift with Dan led to the timber. Dan is ahead of the hero at every
# checkpoint. The rest of the level is tests/smoke/level_prologue_escape.gd and
# tests/smoke/level_prologue_patrol.gd (10 560 px do not fit under the runner's 60 s timeout).
# Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/level_prologue.gd

const NAME := "level_prologue"   # must equal the file basename
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const MAIN_PATH := "res://scenes/Main.tscn"
const PROLOGUE_PATH := "res://scenes/levels/Level00_Prologue.tscn"
const SETTLE_CAP := 20
const SETTLE_DELTA := 0.05
const TAP_CAP := 16
const OVERLAP_FRAMES := 4
const ATTEMPT_CAP := 80
# Stage enum values (C# enums come back as int).
const STAGE_INTRO := 0
const STAGE_FACE := 1
const STAGE_CHARGE := 2
const STAGE_BLAST := 3
const STAGE_DARK := 4
const STAGE_FIGHT := 5
const STAGE_DRIFT := 6
const ROOM_FACE_LIMITS := [0, 0, 2880, 1080]
const ROOM_DRIFT_LIMITS := [2880, 0, 5760, 1080]
const WAVE_LOCK_LIMITS := [960, 0, 2880, 1080]
const LINE_COUNTS := [7, 3, 2, 2, 8, 5]   # intro / charge / blast / guards / held / surface
# Segment 0.
const HERO_START := Vector2(200, 480)
const DAN_START := Vector2(960, 470)
const BEFORE_CRATE := Vector2(700, 450)
const CRATE_X := 820.0
const CRATE_BLOCK_MAX_X := 791.0   # 798 (left edge) minus the feet capsule radius
const WALK_FRAMES := 58            # 220 px/s x 0.97 s = 213 px
const JUMP_CAP := 90
const CRATE_CLEAR_X := 860.0
const BAND_MARGIN := 20.0
const JAM_APPROACH := Vector2(1670, 450)   # 90 px short of the jam's root
const JAM_X := 1760.0
const BLOCK_MARGIN := 16.0
const JAM_OPEN_FROM := Vector2(1690, 450)
const JAM_OPEN_FRAMES := 30                # 110 px: past the jam, short of Checkpoint_Dark's trigger
const JAM_PASS_X := 1784.0                 # the blocker's right edge
const NEAR_CHARGE := Vector2(1140, 450)
const CHARGE_SEQUENCE := ["move_up", "attack", "move_down", "jump"]
const SEAL_BLOCKER_END := 1388.0           # DebrisPile_BlastSeal at 1360 + 28
const JAM_BLOCKER_START := 1732.0
const HERO_HALF_W := 14.0
const BLAST_WALK_CAP := 240                # frames of walking right from the panel until the blast
const DELAY_MARGIN := 0.4
const FADE_MARGIN := 0.6
const COLOR_EPS := 0.02
# Segment 1.
const CP_DARK := Vector2(1860, 450)
const FLASH_HINT := Vector2(1980, 450)
const OUTLET_REACH := Vector2(2060, 560)
const OUTLET_ENERGY := 60.0
const OUTLET_AMOUNT := 25.0
const BEFORE_WAVE := Vector2(2100, 450)
const WAVE_CAP := 60
const SPAWN_CAP := 120
const DROP_CAP := 8
const DROP_TOL := 12.0
const PICKUP_ENERGY := 50.0
const PICKUP_AMOUNT := 25.0
const PICKUP_PROMPT := "E: Take the bank"
const BUBBLE_CAP := 30
const DAN_ARRIVE_CAP := 300
const RESPAWN_MARGIN := 0.4          # seconds on top of LevelBase.RespawnDelay for the soft respawn
const LINE_WALK_MIN := 200.0        # px of walk a route-point line gets before a prop prompt can hide its bubble (~0.9 s)
const CP_DRIFT := Vector2(2900, 450)

# The scene set under test. A v2 script (tests/smoke/v2_level_prologue.gd) extends this one and overrides
# these three to run the same steps against scenes/v2/ — the v1 constants stay the defaults.
func _name() -> String:
	return NAME

func _main_path() -> String:
	return MAIN_PATH

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

func _walk_right_frames(player: Node, from: Vector2, frames: int) -> float:
	player.global_position = from
	await _step(2)
	Input.action_press("move_right")
	await _step(frames)
	Input.action_release("move_right")
	await _step(2)
	return player.global_position.x

func _walk_right(player: Node, from: Vector2) -> float:
	return await _walk_right_frames(player, from, WALK_FRAMES)

func _limits(camera: Camera2D) -> Array:
	return [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]

func _color_eq(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < COLOR_EPS and absf(a.g - b.g) < COLOR_EPS and absf(a.b - b.b) < COLOR_EPS

func _has_cyrillic(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x0400 and code <= 0x04FF:
			return true
	return false

func _check_english(node: Node, label: String) -> void:
	for prop in node.get_property_list():
		var pname: String = prop["name"]
		if pname == "script" or pname.contains("/"):
			continue
		var value: Variant = node.get(pname)
		if value is String:
			_check(not _has_cyrillic(value), "%s.%s is not English: '%s'" % [label, pname, value])
		elif value is PackedStringArray:
			for line in value:
				_check(not _has_cyrillic(line), "%s.%s is not English: '%s'" % [label, pname, line])

func _skip_cutscene(cutscene: Node, finished: Array, label: String) -> void:
	var target: int = finished[0] + 1
	var taps := 0
	while finished[0] < target and taps < TAP_CAP and is_instance_valid(cutscene):
		await _tap("interact")
		taps += 1
		await _step(2)
	if finished[0] < target:
		_check(false, "%s: cutscene not finished after %d interact taps" % [label, taps])

func _use_panel(panel: Node, player: Node, sequence: Array) -> void:
	panel.Begin(player)
	await _step(2)
	for action in sequence:
		await _tap(action)
		await _step(2)
	await _wait_until(func(): return not panel.IsActive, ATTEMPT_CAP)
	await _step(2)

func _is_script(node: Node, file: String) -> bool:
	var script: Variant = node.get_script()
	return script != null and str(script.resource_path).ends_with(file)

func _children_with(parent: Node, file: String) -> Array:
	var out: Array = []
	for child in parent.get_children():
		if _is_script(child, file):
			out.append(child)
	return out

func _check_pile_band(level: Node, pile_name: String, player: Node) -> void:
	var pile: Node = level.get_node_or_null(pile_name)
	_check(pile != null, "the prologue has no '%s'" % pile_name)
	if pile == null:
		return
	_check(is_equal_approx(pile.BlockerDepth, 320.0), "%s.BlockerDepth=%s, expected 320" % [pile_name, pile.BlockerDepth])
	var pbox: Shape2D = pile.BlockerShape.shape
	if pbox is RectangleShape2D:
		var ptop: float = pile.BlockerShape.global_position.y - pbox.size.y * 0.5
		var pbottom: float = pile.BlockerShape.global_position.y + pbox.size.y * 0.5
		_check(ptop <= player.FloorTop and pbottom >= player.FloorBottom,
			"%s blocks Y %.0f..%.0f, expected the whole walk band %.0f..%.0f — it could be walked around in depth"
			% [pile_name, ptop, pbottom, player.FloorTop, player.FloorBottom])

func _run() -> void:
	for a in ["move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "interact", "flashlight"]:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	_check(root.get_node_or_null("HitStop") != null, "HitStop autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()
	gs.CurrentScenePath = ""

	var main_scene: PackedScene = load(_main_path())
	_check(main_scene != null, "%s failed to load" % _main_path())
	if main_scene == null:
		_finish()
		return

	# 1. Boot: Main builds the prologue directly (the exposition sits on the menu's New Game path only).
	var main: Node = main_scene.instantiate()
	root.add_child(main)
	current_scene = main
	await _settle()
	var level: Node = main.get("CurrentLevel")
	if level == null:
		_check(false, "Main.CurrentLevel is null after _Ready (Main.cs not attached or StartLevel unset?)")
		_finish()
		return
	var player: Node = level.get("Player")
	var cutscene: Node = level.get("Cutscene")
	var hud: Node = level.get("Hud")
	var camera: Camera2D = level.get("Camera")
	var dan: Node = level.get("Companion")
	var circuit: Node = level.get("Circuit")
	if player == null or cutscene == null or hud == null or camera == null or dan == null or circuit == null:
		_check(false, "the prologue lacks Player/Cutscene/Hud/Camera/Companion/Circuit or Level00_Prologue.cs is not attached")
		_finish()
		return
	var lamp: Node = player.get("Flashlight")
	var route: Node = level.get("DanRoute")
	var charge: Node = level.get("Charge")
	var jam: Node = level.get("Jam")
	var blast: Node = level.get("BlastCollapse")
	var trigger: Node = level.get("BlastTrigger")
	var seal: Node = level.get_node_or_null("DebrisPile_BlastSeal")
	var spawner: Node = level.get("GuardWave")
	var arena: Node = level.get("ArenaZone")
	var arena_lamp: Node = level.get("ArenaLamp")
	if route == null or charge == null or jam == null or blast == null or trigger == null or seal == null or spawner == null or arena == null or arena_lamp == null:
		_check(false, "the prologue's segment 0-1 props are not wired (DanRoute/Charge/Jam/BlastCollapse/BlastTrigger/DebrisPile_BlastSeal/GuardWave/ArenaZone/ArenaLamp)")
		_finish()
		return
	for child in root.get_children():
		_check(not _is_script(child, "Exposition.cs"), "an Exposition node is in the tree when the run boots through Main")

	_check(level.name == "Level00_Prologue" and level.scene_file_path == _prologue_path(),
		"Main.CurrentLevel is '%s' (%s), expected Level00_Prologue" % [level.name, level.scene_file_path])
	_check(gs.CurrentScenePath == _prologue_path(), "GameState.CurrentScenePath='%s' after boot, expected %s" % [gs.CurrentScenePath, _prologue_path()])
	_check(level.get("y_sort_enabled") == true, "the prologue root lacks y_sort_enabled")
	_check(level.CutsceneSkippable == true, "Level00_Prologue.CutsceneSkippable=%s, expected true" % level.CutsceneSkippable)
	var counts: Array = [Array(level.IntroLines).size(), Array(level.ChargeLines).size(), Array(level.BlastLines).size(),
		Array(level.GuardsLines).size(), Array(level.HeldLines).size(), Array(level.EndLines).size()]
	_check(counts == LINE_COUNTS, "cutscene line counts are %s, expected %s (intro/charge/blast/guards/held/surface)" % [counts, LINE_COUNTS])
	_check(level.DanGasLine == "LAMP OFF!", "the gas shout is '%s', expected exactly 'LAMP OFF!'" % level.DanGasLine)
	_check(level.CurrentStage == STAGE_INTRO, "stage %s at boot, expected Intro (%d)" % [level.CurrentStage, STAGE_INTRO])
	_check(cutscene.IsPlaying == true and cutscene.CurrentLine == 0, "intro: Cutscene IsPlaying=%s CurrentLine=%s, expected true / 0" % [cutscene.IsPlaying, cutscene.CurrentLine])
	_check(player.process_mode == Node.PROCESS_MODE_DISABLED, "intro: the hero is not frozen during the cutscene")
	_check(hud.PromptText == "", "intro: HUD prompt '%s' during the cutscene, expected hidden" % hud.PromptText)
	_check(player.position == HERO_START, "hero at %s at boot, expected %s" % [player.position, HERO_START])
	_check(_limits(camera) == ROOM_FACE_LIMITS, "camera limits %s at boot, expected %s (Room_Face)" % [_limits(camera), ROOM_FACE_LIMITS])
	_check(is_equal_approx(player.FloorTop, 300.0) and is_equal_approx(player.FloorBottom, 600.0),
		"the hero's floor band is %s..%s, expected 300..600" % [player.FloorTop, player.FloorBottom])
	_check(_color_eq(level.Darkness.color, level.DarknessLit),
		"the ambient light is %s at boot, expected DarknessLit %s" % [level.Darkness.color, level.DarknessLit])
	_check(level.WorkLamps != null and level.WorkLamps.visible == true, "the station lighting is not on at boot")
	_check(dan.collision_layer == 0, "Dan's collision_layer is %d, expected 0" % dan.collision_layer)
	_check(dan.get_node_or_null("Hurtbox") == null, "Dan has a Hurtbox; he must never be hittable")
	_check(dan.global_position.distance_to(DAN_START) <= 2.0 and dan.global_position.x > CRATE_X,
		"Dan is at %s during the intro, expected %s — past the crate he cannot jump" % [dan.global_position, DAN_START])
	_check(dan.CurrentStateName == "Wait", "Dan is in '%s' during the intro, expected 'Wait'" % dan.CurrentStateName)
	_check(blast.monitoring == false, "CaveIn_Blast is monitoring; the blast must be scripted only")
	_check(blast.IsTriggered == false and blast.HasCollapsed == false, "the blast fired at boot")
	_check(seal.IsCleared == true, "the blast seal blocks the drift before the blast")
	_check(jam.IsCleared == false, "the cart-train jam is open before the blast")
	_check(spawner.Count == 2, "the first wave spawns %d guards, expected 2 (author decision 3)" % spawner.Count)
	_check(spawner.SpawnAware == true, "the first wave spawns unaware guards; they must charge in")
	_check(arena_lamp.visible == false, "the arena lamp is on before the guards bring it")
	var arena_shape: Node = arena.get_node_or_null("CollisionShape2D")
	_check(arena_shape != null and arena_shape.disabled == true, "LitZone_Arena is live before the wave")

	# 2. English everywhere; the gates span the band; the old story is gone.
	_check_english(level, "Level00_Prologue")
	for path in ["Charge", "Lights_Drift", "Hoist", "Outlet_1", "Outlet_2", "Outlet_3", "Tutorial/MovePrompt", "Tutorial/JumpPrompt",
			"Tutorial/FlashlightPrompt", "Tutorial/AttackPrompt", "Tutorial/HeavyPrompt"]:
		var prop_node: Node = level.get_node_or_null(path)
		_check(prop_node != null, "the prologue has no '%s'" % path)
		if prop_node != null:
			_check_english(prop_node, path)
	for pile_name in ["DebrisPile_BlastSeal", "DebrisPile_Jam", "DebrisPile_Timber"]:
		_check_pile_band(level, pile_name, player)
	for gone in ["Pump", "Extractor", "Lights_Cage", "WatchZone_Crew", "CaveIn_Upper", "CaveIn_Final", "PH_Foreman", "GuardSpawner",
			"Checkpoints/Checkpoint_Farewell", "PH_DanDown", "Overseer", "PH_MuzzleFlash"]:
		_check(level.get_node_or_null(gone) == null, "the rebuilt prologue still has '%s'" % gone)
	for prop_gone in ["FinePenalty", "ForemanLines", "GuardLines", "FarewellLines", "OverseerLines", "DeathLines"]:
		_check(level.get(prop_gone) == null, "Level00_Prologue still exports '%s'" % prop_gone)
	if _failures.size() > 0:
		main.queue_free()
		_finish()
		return

	var finished: Array = [0]
	cutscene.Finished.connect(func(): finished[0] += 1)
	var stages: Array = []
	level.StageChanged.connect(func(s: String): stages.append(s))
	var lines: Array = []
	dan.LineShown.connect(func(t: String): lines.append(t))
	# Dan is ahead of the hero (within OvertakeDistance) whenever a checkpoint arms — GAME_DESIGN §3
	# «Дан завжди попереду».
	var ahead: Array = []
	level.CheckpointArmed.connect(func(cp: Node): ahead.append([cp.Label, dan.global_position.x, player.global_position.x]))

	# 3. The intro plays out; Dan leads to the motor.
	await _skip_cutscene(cutscene, finished, "intro")
	await _step(3)
	_check(level.CurrentStage == STAGE_FACE, "after the intro the stage is %s, expected Face (%d)" % [level.CurrentStage, STAGE_FACE])
	_check(player.process_mode == Node.PROCESS_MODE_INHERIT, "the hero is still frozen after the intro")
	_check(dan.CurrentStateName == "Lead", "Dan is in '%s' after the intro, expected 'Lead'" % dan.CurrentStateName)
	_check(dan.LeadTarget == route.get_node("WP_charge").global_position, "Dan's route point after the intro is %s, expected WP_charge" % dan.LeadTarget)
	_check(level.CurrentRouteKey == "charge", "the level's route key is '%s', expected 'charge'" % level.CurrentRouteKey)
	await _step(OVERLAP_FRAMES)
	_check(level.ArmedCheckpoint != null and level.ArmedCheckpoint.Label == "face", "the first checkpoint is %s, expected 'face'" % level.ArmedCheckpoint)

	# 4. Segment 0: the hints, the crate at three depths, the jump.
	var hint: Node = level.get("MovePrompt")
	await _place(player, Vector2(420, 450))
	_check(hint != null and hint.IsShown == true, "the move hint never appeared where the hero walks")
	await _wait_until(func(): return lines.has(level.DanMoveLine), BUBBLE_CAP)
	_check(lines.has(level.DanMoveLine), "Dan did not say the move line (%s)" % [lines])
	var crate: Node = level.get_node_or_null("Crate")
	_check(crate != null, "the prologue has no 'Crate'")
	if crate != null and crate.Shape != null and crate.Shape.shape is RectangleShape2D:
		var cbox: RectangleShape2D = crate.Shape.shape
		var ctop: float = crate.Shape.global_position.y - cbox.size.y * 0.5
		var cbottom: float = crate.Shape.global_position.y + cbox.size.y * 0.5
		_check(ctop <= player.FloorTop and cbottom >= player.FloorBottom,
			"the crate blocks Y %.0f..%.0f, expected the whole walk band" % [ctop, cbottom])
	for crate_depth in [player.FloorTop + BAND_MARGIN, 450.0, player.FloorBottom - BAND_MARGIN]:
		var blocked: float = await _walk_right(player, Vector2(BEFORE_CRATE.x, crate_depth))
		_check(blocked <= CRATE_BLOCK_MAX_X, "walking right at Y %.0f the hero reached x %.0f, past the crate at x %.0f" % [crate_depth, blocked, CRATE_X])
	_release_all()
	player.global_position = BEFORE_CRATE
	await _step(2)
	Input.action_press("move_right")
	await _tap("jump")
	await _step(JUMP_CAP)
	Input.action_release("move_right")
	await _step(2)
	_check(player.global_position.x >= CRATE_CLEAR_X, "jumping the crate the hero only reached x %.0f, expected past %.0f" % [player.global_position.x, CRATE_CLEAR_X])
	_release_all()

	# 5. The jam blocks the drift at every depth before the blast; the charge panel is reachable.
	for depth in [player.FloorTop + BAND_MARGIN, 450.0, player.FloorBottom - BAND_MARGIN]:
		var reached: float = await _walk_right(player, Vector2(JAM_APPROACH.x, depth))
		_check(reached <= JAM_X - BLOCK_MARGIN, "walking right at Y %.0f the hero reached x %.0f, past the jam at x %.0f — the drift is open before the blast" % [depth, reached, JAM_X])
	_release_all()
	_check(blast.IsTriggered == false and level.CurrentStage == STAGE_FACE, "walking up to the jam set the blast off (stage %s)" % level.CurrentStage)
	await _wait_until(func(): return dan.IsAtLeadTarget, DAN_ARRIVE_CAP)
	await _place(player, NEAR_CHARGE)
	_check(hud.PromptText == "E: " + charge.PromptText, "at the motor the HUD reads '%s', expected 'E: %s'" % [hud.PromptText, charge.PromptText])
	await _wait_until(func(): return lines.has(level.DanChargeLine), BUBBLE_CAP)
	_check(lines.has(level.DanChargeLine), "Dan did not say the motor line when the hero reached him (%s)" % [lines])

	# 6. The charge: the one sequence of the level, then the Charge cutscene with the hero frozen.
	var activated: Array = []
	charge.Activated.connect(func(): activated.append(true))
	await _use_panel(charge, player, CHARGE_SEQUENCE)
	_check(activated.size() == 1, "Charge.Activated fired %d times, expected 1" % activated.size())
	_check(charge.IsActivated == true, "the charge panel is not activated after the sequence")
	_check(level.CurrentStage == STAGE_CHARGE, "after the charge the stage is %s, expected Charge (%d)" % [level.CurrentStage, STAGE_CHARGE])
	_check(cutscene.IsPlaying == true and cutscene.LineCount == LINE_COUNTS[1], "the Charge cutscene is not playing (%s / %d lines)" % [cutscene.IsPlaying, cutscene.LineCount])
	_check(player.process_mode == Node.PROCESS_MODE_DISABLED, "the hero is not frozen for the Charge cutscene")
	_check(blast.HasCollapsed == false and seal.IsCleared == true, "the roof came down with the charge itself; it must wait for the props")
	await _skip_cutscene(cutscene, finished, "charge")
	await _step(3)
	_check(player.process_mode == Node.PROCESS_MODE_INHERIT, "the hero is still frozen after the Charge cutscene")
	_check(dan.IsLeading and dan.LeadLeashed == false and dan.LeadTarget == route.get_node("WP_props").global_position,
		"after the charge Dan is %s / leashed %s / target %s, expected running (leash off) to WP_props" % [dan.CurrentStateName, dan.LeadLeashed, dan.LeadTarget])
	_check(level.CurrentStage == STAGE_CHARGE, "the stage moved to %s before the blast" % level.CurrentStage)

	# 7. The blast: scripted, with the hero frozen on the open side of the seal.
	var collapse_sample: Array = []
	blast.Collapsed.connect(func(): collapse_sample.append([player.process_mode, player.global_position.x]))
	var before_seal: float = player.global_position.x
	Input.action_press("move_right")
	var walked: int = await _wait_until(func(): return blast.HasCollapsed, BLAST_WALK_CAP)
	Input.action_release("move_right")
	_check(walked >= 0, "walking right from the motor for %d frames never set the blast off" % BLAST_WALK_CAP)
	await _step(2)
	_check(collapse_sample.size() == 1, "Collapsed fired %d times, expected 1" % collapse_sample.size())
	if collapse_sample.size() == 1:
		_check(collapse_sample[0][0] == Node.PROCESS_MODE_DISABLED, "the roof came down on a hero who was not frozen")
		var left_edge: float = collapse_sample[0][1] - HERO_HALF_W
		_check(left_edge > SEAL_BLOCKER_END and collapse_sample[0][1] + HERO_HALF_W < JAM_BLOCKER_START,
			"at the collapse the hero stood at x %.0f (left edge %.0f); expected clear of the seal (ends %.0f) and short of the jam (%.0f)"
			% [collapse_sample[0][1], left_edge, SEAL_BLOCKER_END, JAM_BLOCKER_START])
	_check(blast.IsTriggered == true and blast.monitoring == false, "the blast ran through a walk trigger (monitoring %s)" % blast.monitoring)
	_check(trigger.monitoring == false, "the props trigger is still armed after the blast")
	_check(level.CurrentStage == STAGE_BLAST, "after the blast the stage is %s, expected Blast (%d)" % [level.CurrentStage, STAGE_BLAST])
	_check(cutscene.IsPlaying == true and cutscene.LineCount == LINE_COUNTS[2], "the Blast cutscene is not playing")
	_check(seal.IsCleared == false and seal.BlockerShape.disabled == false, "the way back is not sealed after the blast")
	_check(jam.IsCleared == true, "the cart train is still wedged across the drift after the blast")
	_check(level.WorkLamps.visible == false, "the station lighting survived the blast")
	_check(level.BlastSparks != null and level.BlastSparks.emitting == true, "the torn cable does not spark after the blast")
	_check(level.ConveyorAnimation != null and level.ConveyorAnimation.is_playing() == false, "the belt is still running with the motor gone")
	_check(player.IsKnockedOut == false, "the blast killed the hero")
	_check(player.global_position.x >= before_seal, "the blast pushed the hero back to x %.0f" % player.global_position.x)
	await _real_wait(level.DarknessFadeSeconds + FADE_MARGIN)
	_check(_color_eq(level.Darkness.color, level.DarknessMine),
		"the ambient light is %s after the blast, expected DarknessMine %s" % [level.Darkness.color, level.DarknessMine])
	await _skip_cutscene(cutscene, finished, "blast")
	await _step(3)
	_check(dan.LeadTarget == route.get_node("WP_dark").global_position, "after the blast Dan's point is %s, expected WP_dark" % dan.LeadTarget)
	await _step(10)
	_check(dan.global_position.x > player.global_position.x, "Dan (x %.0f) is behind the hero (x %.0f) after the blast" % [dan.global_position.x, player.global_position.x])
	# The seal is solid at every depth; the jam is open.
	for depth in [player.FloorTop + BAND_MARGIN, 450.0, player.FloorBottom - BAND_MARGIN]:
		player.global_position = Vector2(1450, depth)
		await _step(2)
		Input.action_press("move_left")
		await _step(WALK_FRAMES)
		Input.action_release("move_left")
		await _step(2)
		_check(player.global_position.x - HERO_HALF_W >= SEAL_BLOCKER_END - 1.0,
			"walking left at Y %.0f the hero got to x %.0f, into the sealed roof (blocker ends at %.0f)" % [depth, player.global_position.x, SEAL_BLOCKER_END])
	for depth in [player.FloorTop + BAND_MARGIN, player.FloorBottom - BAND_MARGIN]:
		var open: float = await _walk_right_frames(player, Vector2(JAM_OPEN_FROM.x, depth), JAM_OPEN_FRAMES)
		_check(open >= JAM_PASS_X, "with the jam cleared the hero only reached x %.0f at Y %.0f, expected past %.0f" % [open, depth, JAM_PASS_X])
	_release_all()

	# 8. Segment 1: the dark checkpoint, the head lamp, the first outlet.
	await _place(player, CP_DARK)
	_check(level.ArmedCheckpoint != null and level.ArmedCheckpoint.Label == "dark", "the checkpoint past the jam is %s, expected 'dark'" % level.ArmedCheckpoint)
	_check(level.CurrentStage == STAGE_DARK, "at Checkpoint_Dark the stage is %s, expected Dark (%d)" % [level.CurrentStage, STAGE_DARK])
	await _place(player, FLASH_HINT)
	var flash_hint: Node = level.get("FlashlightPrompt")
	_check(flash_hint != null and flash_hint.IsShown == true, "the head-lamp hint never appeared")
	await _wait_until(func(): return lines.has(level.DanLampLine), BUBBLE_CAP)
	_check(lines.has(level.DanLampLine), "Dan did not say the lamp line (%s)" % [lines])
	await _tap("flashlight")
	await _step(2)
	_check(flash_hint.IsCompleted == true, "the head-lamp hint did not complete when F was pressed")
	_check(lamp.IsOn == true, "the head lamp is off after F")
	lamp.SetOn(false)
	gs.Energy = OUTLET_ENERGY
	var outlet: Node = level.get_node("Outlet_1")
	await _place(player, OUTLET_REACH)
	outlet.Begin(player)
	await _step(4)
	_check(is_equal_approx(gs.Energy, OUTLET_ENERGY + OUTLET_AMOUNT), "the outlet left the energy at %s, expected %s" % [gs.Energy, OUTLET_ENERGY + OUTLET_AMOUNT])
	_check(lines.has(level.DanOutletLine), "Dan did not comment on the first outlet (%s)" % [lines])

	# 9. The wave: two guards behind the Guards cutscene, lit by their own hand lamp.
	var started: Array = []
	spawner.WaveStarted.connect(func(): started.append(true))
	player.global_position = BEFORE_WAVE
	await _step(2)
	Input.action_press("move_right")
	var hit_wave: int = await _wait_until(func(): return started.size() > 0, WAVE_CAP)
	Input.action_release("move_right")
	_check(hit_wave >= 0, "walking right from x %.0f never started the wave" % BEFORE_WAVE.x)
	await _step(3)
	_check(level.CurrentStage == STAGE_FIGHT, "when the wave starts the stage is %s, expected Fight (%d)" % [level.CurrentStage, STAGE_FIGHT])
	_check(cutscene.IsPlaying == true and cutscene.LineCount == LINE_COUNTS[3], "the Guards cutscene is not playing")
	_check(player.process_mode == Node.PROCESS_MODE_DISABLED, "the hero is not frozen for the Guards cutscene")
	_check(_limits(camera) == WAVE_LOCK_LIMITS, "camera limits %s during the wave, expected the lock %s" % [_limits(camera), WAVE_LOCK_LIMITS])
	_check(arena_lamp.visible == true, "the guards' hand lamp did not come on with the wave")
	_check(arena_shape.disabled == false, "LitZone_Arena's shape is still off with the wave running")
	_check(dan.IsWarning == true, "Dan is not in the warning stance while the guards come")
	await _skip_cutscene(cutscene, finished, "guards")
	await _step(3)
	var attack_hint: Node = level.get("AttackPrompt")
	var heavy_hint: Node = level.get("HeavyPrompt")
	_check(attack_hint.IsShown == true, "the attack hint did not show after the Guards cutscene")
	_check(heavy_hint.IsShown == false, "the heavy hint showed before the first hit landed")
	_check(lines.has(level.DanAttackLine), "Dan did not say the attack line (%s)" % [lines])
	var spawned: int = await _wait_until(func(): return spawner.Spawned >= 2, SPAWN_CAP)
	_check(spawned >= 0, "the wave spawned %d guards in %d frames, expected 2" % [spawner.Spawned, SPAWN_CAP])
	var guards: Array = _children_with(spawner, "Guard.cs")
	_check(guards.size() == 2, "the wave holds %d guards, expected 2" % guards.size())
	for g in guards:
		_check(g.IsAware == true, "%s spawned unaware" % g.name)
		_check(g.get("DropScene") != null, "%s has no DropScene; it would drop no powerbank" % g.name)
	if guards.size() != 2:
		main.queue_free()
		_finish()
		return
	# 9b. S1 (v3 review): a KO in the wave. The soft respawn at Checkpoint_Dark re-issues Dan's
	#     current point, which must be a true no-op — he keeps the warning stance (faces the fight,
	#     no calls at the player) with the wave still running.
	var said_before_ko: int = lines.size()
	player.Kill()
	await _step(2)
	_check(player.IsKnockedOut == true, "Kill() did not knock the hero out in the wave")
	await _real_wait(level.RespawnDelay + RESPAWN_MARGIN)
	_check(player.IsKnockedOut == false, "the hero did not respawn %.1f s after the KO in the wave" % (level.RespawnDelay + RESPAWN_MARGIN))
	_check(level.CurrentStage == STAGE_FIGHT and spawner.IsCleared == false, "the wave did not survive the respawn (stage %s, cleared %s)" % [level.CurrentStage, spawner.IsCleared])
	_check(dan.IsWarning == true, "Dan dropped the warning stance on the respawn in the wave — re-issuing his point must not clear it")
	_check(dan.LeadTarget == route.get_node("WP_dark").global_position, "after the respawn Dan's point is %s, expected still WP_dark" % dan.LeadTarget)
	for call in [level.DanCallLine, level.DanCallAgainLine, level.DanCountingLine]:
		_check(not lines.slice(said_before_ko).has(call), "Dan called '%s' at the player mid-fight after the respawn (%s)" % [call, lines.slice(said_before_ko)])
	var charge_prompt_x: float = charge.global_position.x + charge.get_node("CollisionShape2D").position.x - charge.get_node("CollisionShape2D").shape.radius - player.get("InteractionArea").get_node("CollisionShape2D").shape.radius
	var charge_line_x: float = route.get_node("WP_charge").global_position.x - dan.HeroCloseDistance
	_check(charge_prompt_x - charge_line_x >= LINE_WALK_MIN, "the motor line fires at x %.0f and the charge panel's prompt at x %.0f: %.0f px of walk for the bubble, expected >= %.0f (the prompt would hide it the moment it is said)" % [charge_line_x, charge_prompt_x, charge_prompt_x - charge_line_x, LINE_WALK_MIN])

	guards[0].TakeDamage(5.0, 0.0, false, 0)
	await _step(3)
	_check(heavy_hint.IsShown == true, "the heavy hint did not show after the first hit")
	await _wait_until(func(): return lines.has(level.DanHeavyLine), BUBBLE_CAP)
	_check(lines.has(level.DanHeavyLine), "Dan did not say the heavy line (%s)" % [lines])
	var guard_pos: Array = []
	for g in guards:
		guard_pos.append(g.global_position)
		g.TakeDamage(999.0, 0.0, true, 0)
	await _step(DROP_CAP)
	var drops: Array = _children_with(spawner, "EnergyPickup.cs")
	_check(drops.size() == 2, "the fallen guards left %d powerbanks under the wave, expected 2" % drops.size())
	for d in drops:
		var near := false
		for i in guards.size():
			if d.global_position.distance_to(guard_pos[i] + guards[i].DropOffset) <= DROP_TOL:
				near = true
		_check(near, "a powerbank lies at %s, not within %d px of a fallen guard" % [d.global_position, DROP_TOL])
	_check(spawner.IsCleared == true, "the wave is not cleared with both guards down")
	_check(_limits(camera) == ROOM_FACE_LIMITS, "camera limits %s after the wave, expected %s restored" % [_limits(camera), ROOM_FACE_LIMITS])
	_check(dan.IsWarning == false, "Dan is still in the warning stance after the wave")
	_check(dan.LeadTarget == route.get_node("WP_face_exit").global_position, "after the wave Dan's point is %s, expected WP_face_exit" % dan.LeadTarget)
	_check(lines.has(level.DanBanksLine), "Dan did not say the banks line (%s)" % [lines])

	# 10. Taking a bank with E: +25, the node gone, Dan's line once.
	if drops.size() >= 1:
		gs.Energy = PICKUP_ENERGY
		var first: Node = drops[0]
		var collected: Array = []
		first.Collected.connect(func(a: float): collected.append(a))
		await _place(player, first.global_position + Vector2(0, -20))
		_check(hud.PromptText == PICKUP_PROMPT, "next to the bank the HUD reads '%s', expected '%s'" % [hud.PromptText, PICKUP_PROMPT])
		await _tap("interact")
		await _step(4)
		_check(is_equal_approx(gs.Energy, PICKUP_ENERGY + PICKUP_AMOUNT), "taking the bank left the energy at %s, expected %s" % [gs.Energy, PICKUP_ENERGY + PICKUP_AMOUNT])
		_check(collected.size() == 1 and is_equal_approx(collected[0], PICKUP_AMOUNT), "Collected fired %s, expected [%s]" % [collected, PICKUP_AMOUNT])
		_check(not is_instance_valid(first), "the taken bank is still in the tree")
		_check(hud.PromptText != PICKUP_PROMPT, "the HUD still offers the taken bank ('%s')" % hud.PromptText)
		_check(lines.count(level.DanOursLine) == 1, "Dan said the ours line %d times after the first bank, expected 1 (%s)" % [lines.count(level.DanOursLine), lines])
		if drops.size() == 2 and is_instance_valid(drops[1]):
			await _place(player, drops[1].global_position + Vector2(0, -20))
			drops[1].Begin(player)
			await _step(4)
			_check(is_equal_approx(gs.Energy, PICKUP_ENERGY + 2.0 * PICKUP_AMOUNT), "the second bank left the energy at %s" % gs.Energy)
			_check(lines.count(level.DanOursLine) == 1, "Dan repeated the ours line on the second bank")

	# 11. On into the drift: Dan is led at least to the timber.
	await _wait_until(func(): return dan.IsAtLeadTarget, DAN_ARRIVE_CAP)
	await _place(player, CP_DRIFT)
	_check(level.CurrentStage == STAGE_DRIFT, "at Checkpoint_Drift the stage is %s, expected Drift (%d)" % [level.CurrentStage, STAGE_DRIFT])
	_check(_limits(camera) == ROOM_DRIFT_LIMITS, "camera limits %s in Room_Drift, expected %s" % [_limits(camera), ROOM_DRIFT_LIMITS])
	_check(dan.LeadTarget == route.get_node("WP_timber").global_position, "in the drift Dan's point is %s, expected WP_timber" % dan.LeadTarget)
	_check(stages == ["Face", "Charge", "Blast", "Dark", "Fight", "Drift"], "the stages so far were %s" % [stages])
	_check(player.IsKnockedOut == false, "the hero is knocked out at the end of the first half")
	for entry in ahead:
		_check(entry[1] >= entry[2] - dan.OvertakeDistance,
			"at checkpoint '%s' Dan was at x %.0f, behind the hero at x %.0f by more than OvertakeDistance %.0f" % [entry[0], entry[1], entry[2], dan.OvertakeDistance])
	_check(ahead.size() >= 3, "only %d checkpoints armed in the first half, expected face, dark and drift" % ahead.size())

	main.queue_free()
	await _step(2)
	_finish()
