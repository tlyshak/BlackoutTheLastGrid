extends SceneTree
# Smoke: the first half of the rebuilt prologue (T-07s-b), driven end to end through Main.tscn —
# Main instantiates Level00_Prologue and records GameState.CurrentScenePath; the intro cutscene
# plays with the hero frozen and `interact` taps advance it; every player-visible string in the
# level is English; segment 0 (the move hint, the crate that blocks a walk and yields to a jump);
# the blast (CaveIn_Blast fires once, the station lighting dies, the ambient light goes to the
# mine's black, the fresh seal is solid and the hero survives); finding Dan (the checkpoint arms,
# he goes back to following); the head-lamp hint and the first outlet; the timber pile as a gate at
# both edges of the walk band, which opens once and stays open; the room hop into Room_Flood
# (camera limits, FX gating); the work lights already holding the bus without any input
# (StartsPowered); the pump refused by them, naming them in the HUD; and the pump draining the
# flooded drift for good once the lights are off. Ends at Stage.Gas.
# The second half of the level is tests/smoke/level_prologue_escape.gd (one script cannot fit
# 13 440 px under the runner's 60 s timeout).
# Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/level_prologue.gd
#
# Almost everything is counted in physics frames; the level's own SceneTreeTimers (the cave-in
# delay) and the darkness tween are watched with ignore-time-scale timers. Teleports are used
# everywhere except where the walk itself is the assertion.

const NAME := "level_prologue"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s).
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const MAIN_PATH := "res://scenes/Main.tscn"
const PROLOGUE_PATH := "res://scenes/levels/Level00_Prologue.tscn"
const SETTLE_CAP := 20          # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05      # process delta (s) below which the loop is back to normal pacing
const TAP_CAP := 16             # `interact` taps allowed per cutscene (the intro has 7 lines)
const OVERLAP_FRAMES := 4       # physics frames for Area2D overlaps to refresh after a teleport
const ATTEMPT_CAP := 80         # frames for a refused panel attempt to release the hero
# Stage enum values (C# enums come back as int).
const STAGE_INTRO := 0
const STAGE_FACE := 1
const STAGE_BLAST := 2
const STAGE_FLOOD := 3
const STAGE_GAS := 4
const ROOM_FACE_LIMITS := [0, 0, 2880, 1080]
const ROOM_FLOOD_LIMITS := [2880, 0, 4800, 1080]
const LINE_COUNTS := [7, 2, 8, 7, 3, 7]   # intro / blast / farewell / foreman / guard / ending
# Segment 0.
const HERO_START := Vector2(200, 480)
const BEFORE_CRATE := Vector2(700, 450)
const CRATE_X := 820.0
const CRATE_HALF_W := 22.0
const CRATE_BLOCK_MAX_X := 791.0   # 798 (left edge) minus the feet capsule radius
const WALK_FRAMES := 58            # 220 px/s x 0.97 s = 213 px, comfortably past any single obstacle
const JUMP_CAP := 90               # frames for a full jump (~51 at the defaults)
const CRATE_CLEAR_X := 860.0
# Segment 1.
const BLAST_TRIGGER := Vector2(1640, 450)
const AFTER_BLAST := Vector2(1740, 450)
const DELAY_MARGIN := 0.4          # extra real seconds on top of a level timer
const FADE_MARGIN := 0.6           # extra real seconds on top of DarknessFadeSeconds
const COLOR_EPS := 0.02
const CP_BLAST := Vector2(1840, 450)
const FLASH_HINT := Vector2(1980, 450)
const OUTLET_REACH := Vector2(2090, 560)
const OUTLET_ENERGY := 60.0
const OUTLET_AMOUNT := 25.0
const TIMBER_X := 2450.0
const LIGHT_HIT := Vector2(2400, 450)
const BAND_MARGIN := 20.0          # px inside the walk band's far and near edge the probes walk along
const BLOCK_APPROACH := 90.0       # px left of a gate the blocked walk starts from
const BLOCK_MARGIN := 16.0         # px short of the gate's root X the hero must still be
const PASS_MARGIN := 64.0          # px past the gate's root X a cleared gate lets him reach
const BUBBLE_CAP := 30             # frames for Dan to answer a bounced hit
# Segment 2.
const CP_FLOOD := Vector2(2920, 450)
const NEAR_LIGHTS := Vector2(3095, 450)   # inside the work-lights panel's reach (r 44)
const NEAR_PUMP := Vector2(3855, 450)     # inside the pump's reach
const PUMP_SEQUENCE := ["move_up", "attack", "move_down", "jump"]
const OVERLOAD_TEXT := "Not enough power: Work lights is running"
const CP_GAS := Vector2(4840, 450)

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

# Real-time wait that ignores Engine.time_scale and the pause (the level's own timers and tweens).
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

# Walks the hero right from `from` for WALK_FRAMES frames and returns the X he ended at.
func _walk_right(player: Node, from: Vector2) -> float:
	player.global_position = from
	await _step(2)
	Input.action_press("move_right")
	await _step(WALK_FRAMES)
	Input.action_release("move_right")
	await _step(2)
	return player.global_position.x

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

# Every string a player can read must be English (GAME_DESIGN §3 "Мова"): the level's own exports
# and those of every prop that puts text on screen.
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

# Taps `interact` until the cutscene emits one more Finished (`finished` is a counter Array fed by
# the signal). Polling IsPlaying would not do: the level starts the next cutscene synchronously
# inside Finished.
func _skip_cutscene(cutscene: Node, finished: Array, label: String) -> void:
	var target: int = finished[0] + 1
	var taps := 0
	while finished[0] < target and taps < TAP_CAP and is_instance_valid(cutscene):
		await _tap("interact")
		taps += 1
		await _step(2)
	if finished[0] < target:
		_check(false, "%s: cutscene not finished after %d interact taps" % [label, taps])

# Drives a panel the way the hero's Interact state does and waits until it let him go again.
func _use_panel(panel: Node, player: Node, sequence: Array) -> void:
	panel.Begin(player)
	await _step(2)
	for action in sequence:
		await _tap(action)
		await _step(2)
	await _wait_until(func(): return not panel.IsActive, ATTEMPT_CAP)
	await _step(2)

func _run() -> void:
	# 0. Preconditions: the InputMap actions this script drives, and the autoloads.
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

	var main_scene: PackedScene = load(MAIN_PATH)
	_check(main_scene != null, "%s failed to load" % MAIN_PATH)
	if main_scene == null:
		_finish()
		return

	# 1. Boot: Main builds the prologue and records where the run is.
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

	_check(level.name == "Level00_Prologue" and level.scene_file_path == PROLOGUE_PATH,
		"Main.CurrentLevel is '%s' (%s), expected Level00_Prologue" % [level.name, level.scene_file_path])
	_check(gs.CurrentScenePath == PROLOGUE_PATH, "GameState.CurrentScenePath='%s' after boot, expected %s" % [gs.CurrentScenePath, PROLOGUE_PATH])
	_check(level.get("y_sort_enabled") == true, "the prologue root lacks y_sort_enabled (belt-scroll depth sorting)")
	_check(is_equal_approx(level.FinePenalty, 20.0), "Level00_Prologue.FinePenalty=%s, expected 20" % level.FinePenalty)
	_check(level.CutsceneSkippable == true, "Level00_Prologue.CutsceneSkippable=%s, expected true" % level.CutsceneSkippable)
	var counts: Array = [Array(level.IntroLines).size(), Array(level.BlastLines).size(), Array(level.FarewellLines).size(),
		Array(level.ForemanLines).size(), Array(level.GuardLines).size(), Array(level.EndLines).size()]
	_check(counts == LINE_COUNTS, "cutscene line counts are %s, expected %s (intro/blast/farewell/foreman/guard/ending)" % [counts, LINE_COUNTS])
	_check(level.CurrentStage == STAGE_INTRO, "stage %s at boot, expected Intro (%d)" % [level.CurrentStage, STAGE_INTRO])
	_check(cutscene.IsPlaying == true and cutscene.CurrentLine == 0, "intro: Cutscene IsPlaying=%s CurrentLine=%s, expected true / 0" % [cutscene.IsPlaying, cutscene.CurrentLine])
	_check(player.process_mode == Node.PROCESS_MODE_DISABLED, "intro: the hero is not frozen during the cutscene")
	_check(hud.PromptText == "", "intro: HUD prompt '%s' during the cutscene, expected hidden" % hud.PromptText)
	_check(player.position == HERO_START, "hero at %s at boot, expected %s" % [player.position, HERO_START])
	_check(_limits(camera) == ROOM_FACE_LIMITS, "camera limits %s at boot, expected %s (Room_Face)" % [_limits(camera), ROOM_FACE_LIMITS])
	_check(is_equal_approx(player.FloorTop, 300.0) and is_equal_approx(player.FloorBottom, 600.0),
		"the hero's floor band is %s..%s, expected 300..600" % [player.FloorTop, player.FloorBottom])
	_check(_color_eq(level.Darkness.color, level.DarknessLit),
		"the ambient light is %s at boot, expected DarknessLit %s (the station lighting is still on)" % [level.Darkness.color, level.DarknessLit])
	_check(level.WorkLamps != null and level.WorkLamps.visible == true, "the station lighting is not on at boot")
	_check(dan.collision_layer == 0, "Dan's collision_layer is %d, expected 0 — he must never block the hero or trip a trigger" % dan.collision_layer)
	_check(dan.get_node_or_null("Hurtbox") == null, "Dan has a Hurtbox; he must never be hittable")

	# 2. Every string the player can read is English (acceptance 29).
	_check_english(level, "Level00_Prologue")
	for path in ["Lights_Drift", "Pump", "Extractor", "Lights_Cage", "Hoist", "Outlet_1",
			"Tutorial/MovePrompt", "Tutorial/JumpPrompt", "Tutorial/FlashlightPrompt", "Tutorial/HeavyPrompt"]:
		var prop_node: Node = level.get_node_or_null(path)
		_check(prop_node != null, "the prologue has no '%s'" % path)
		if prop_node != null:
			_check_english(prop_node, path)
	# Every pile in the level — the three the player opens and the three seals a cave-in drops —
	# blocks the whole walk band. A pile at the wrong Y re-opens the depth bypass T-07s-a's review
	# had to close, and a seal that can be walked around is not a sealed drift (acceptance 5).
	for pile_name in ["DebrisPile_BlastSeal", "DebrisPile_Timber", "Flood", "DebrisPile_UpperSeal", "DebrisPile_Ramp", "DebrisPile_Final"]:
		var pile: Node = level.get_node_or_null(pile_name)
		_check(pile != null, "the prologue has no '%s'" % pile_name)
		if pile == null:
			continue
		_check(is_equal_approx(pile.BlockerDepth, 320.0),
			"%s.BlockerDepth=%s, expected 320 (the 300 px walk band with a margin)" % [pile_name, pile.BlockerDepth])
		var pbox: Shape2D = pile.BlockerShape.shape
		_check(pbox is RectangleShape2D, "%s's blocker is a %s, expected a RectangleShape2D" % [pile_name, pbox.get_class()])
		if pbox is RectangleShape2D:
			var ptop: float = pile.BlockerShape.global_position.y - pbox.size.y * 0.5
			var pbottom: float = pile.BlockerShape.global_position.y + pbox.size.y * 0.5
			_check(ptop <= 300.0 and pbottom >= 600.0,
				"%s blocks Y %.0f..%.0f, expected to cover the whole walk band 300..600 — it could be walked around in depth"
				% [pile_name, ptop, pbottom])

	# The old story is gone with the alarm, the fan panel and the guards on the horizon.
	for gone in ["Door_1", "Door_2", "FanPanel", "AlarmLights", "Exit", "Fx_Room1", "Fx_Room2", "Fx_Room3"]:
		_check(level.get_node_or_null(gone) == null, "the rebuilt prologue still has '%s' from the alarm story" % gone)
	if _failures.size() > 0:
		main.queue_free()
		_finish()
		return

	var finished: Array = [0]
	cutscene.Finished.connect(func(): finished[0] += 1)
	var stages: Array = []
	level.StageChanged.connect(func(s: String): stages.append(s))

	# 3. The intro plays out and hands the level to the player.
	await _skip_cutscene(cutscene, finished, "intro")
	await _step(3)
	_check(level.CurrentStage == STAGE_FACE, "after the intro the stage is %s, expected Face (%d)" % [level.CurrentStage, STAGE_FACE])
	_check(player.process_mode == Node.PROCESS_MODE_INHERIT, "the hero is still frozen after the intro")
	_check(dan.CurrentStateName == "Follow", "Dan is in '%s' at the start, expected 'Follow'" % dan.CurrentStateName)
	await _step(OVERLAP_FRAMES)
	_check(level.ArmedCheckpoint != null and level.ArmedCheckpoint.Label == "face",
		"the first checkpoint is %s, expected the one labelled 'face'" % level.ArmedCheckpoint)

	# 4. Segment 0: the hints appear, and the crate blocks a walk but yields to a jump.
	var hint: Node = level.get("MovePrompt")
	await _place(player, Vector2(420, 450))
	_check(hint != null and hint.IsShown == true, "the move hint never appeared where the hero walks")
	_check(hint != null and not hint.Text.is_empty(), "the move hint has no text")
	# The crate is a gate like every pile: it must stop the walk at EVERY depth, or the jump lesson
	# is optional and the hero strolls round it along a wall. Its shape is checked first, then the
	# two edges of the band are walked — the same two-edge probe _check_gate() runs on the piles.
	var crate: Node = level.get_node_or_null("Crate")
	_check(crate != null, "the prologue has no 'Crate'")
	if crate != null and crate.Shape != null and crate.Shape.shape is RectangleShape2D:
		var cbox: RectangleShape2D = crate.Shape.shape
		var ctop: float = crate.Shape.global_position.y - cbox.size.y * 0.5
		var cbottom: float = crate.Shape.global_position.y + cbox.size.y * 0.5
		_check(ctop <= player.FloorTop and cbottom >= player.FloorBottom,
			"the crate blocks Y %.0f..%.0f, expected the whole walk band %.0f..%.0f — it could be walked around in depth"
			% [ctop, cbottom, player.FloorTop, player.FloorBottom])
	for crate_depth in [player.FloorTop + BAND_MARGIN, 450.0, player.FloorBottom - BAND_MARGIN]:
		var blocked: float = await _walk_right(player, Vector2(BEFORE_CRATE.x, crate_depth))
		_check(blocked <= CRATE_BLOCK_MAX_X,
			"walking right at Y %.0f the hero reached x %.0f, past the crate at x %.0f" % [crate_depth, blocked, CRATE_X])
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

	# 5. The blast: it fires once, kills the lighting, seals the drift and leaves the hero alive.
	var blast: Node = level.get("BlastCollapse")
	var seal: Node = level.get_node_or_null("DebrisPile_BlastSeal")
	_check(blast != null and seal != null, "the level lacks BlastCollapse / DebrisPile_BlastSeal")
	if blast == null or seal == null:
		main.queue_free()
		_finish()
		return
	_check(seal.IsCleared == true, "the blast seal blocks the drift before the blast")
	await _place(player, BLAST_TRIGGER)
	_check(blast.IsTriggered == true, "crossing CaveIn_Blast did not trigger it")
	_check(level.CurrentStage == STAGE_BLAST, "after the blast the stage is %s, expected Blast (%d)" % [level.CurrentStage, STAGE_BLAST])
	_check(cutscene.IsPlaying == true, "the blast cutscene did not start")
	_check(level.WorkLamps.visible == false, "the station lighting survived the blast")
	await _place(player, AFTER_BLAST)
	await _real_wait(blast.Delay + DELAY_MARGIN)
	await _step(2)
	_check(blast.HasCollapsed == true, "the roof never came down after CaveIn_Blast.Delay")
	_check(seal.IsCleared == false and seal.BlockerShape.disabled == false, "the way back is not sealed after the blast")
	_check(player.IsKnockedOut == false, "the blast killed the hero — a collapse he cannot avoid must never be lethal")
	await _real_wait(level.DarknessFadeSeconds + FADE_MARGIN)
	_check(_color_eq(level.Darkness.color, level.DarknessMine),
		"the ambient light is %s after the blast, expected DarknessMine %s" % [level.Darkness.color, level.DarknessMine])
	await _skip_cutscene(cutscene, finished, "blast")
	await _step(3)

	# 6. Finding Dan: the checkpoint arms and he goes back to following.
	await _place(player, CP_BLAST)
	_check(level.ArmedCheckpoint != null and level.ArmedCheckpoint.Label == "dan",
		"the checkpoint at Dan is %s, expected the one labelled 'dan'" % level.ArmedCheckpoint)
	await _step(4)
	_check(dan.CurrentStateName == "Follow", "Dan is in '%s' after being found, expected 'Follow'" % dan.CurrentStateName)

	# 7. The head lamp and the first outlet.
	await _place(player, FLASH_HINT)
	var flash_hint: Node = level.get("FlashlightPrompt")
	_check(flash_hint != null and flash_hint.IsShown == true, "the head-lamp hint never appeared")
	await _tap("flashlight")
	await _step(2)
	_check(flash_hint.IsCompleted == true, "the head-lamp hint did not complete when F was pressed")
	_check(lamp.IsOn == true, "the head lamp is off after F")
	lamp.SetOn(false)
	gs.Energy = OUTLET_ENERGY
	var outlet: Node = level.get("FirstOutlet")
	await _place(player, OUTLET_REACH)
	outlet.Begin(player)
	await _step(4)
	_check(is_equal_approx(gs.Energy, OUTLET_ENERGY + OUTLET_AMOUNT),
		"the outlet left the energy at %s, expected %s" % [gs.Energy, OUTLET_ENERGY + OUTLET_AMOUNT])

	# 8. The timber pile is a gate at EVERY depth, and it opens for good (acceptance 5).
	var timber: Node = level.get("TimberPile")
	_check(timber != null and timber.HeavyHitsToClear == 2, "the timber pile wants %s heavy hits, expected 2" % (timber.HeavyHitsToClear if timber != null else "-"))
	if timber == null:
		main.queue_free()
		_finish()
		return
	# Dan comments on a hit that bounced — the cue that teaches the verb.
	var lines: Array = []
	dan.LineShown.connect(func(t: String): lines.append(t))
	await _place(player, LIGHT_HIT)
	await _tap("attack")
	await _wait_until(func(): return lines.size() > 0, BUBBLE_CAP)
	_check(lines.size() > 0 and lines[-1] == level.DanTimberLine,
		"a light attack on the timber did not get Dan's line (%s)" % [lines])
	await _check_gate(level, player, timber, "DebrisPile_Timber")

	# 9. Room_Flood: the room hop, and the work lights that already hold the bus.
	await _place(player, CP_FLOOD)
	_check(level.CurrentStage == STAGE_FLOOD, "at Checkpoint_Flood the stage is %s, expected Flood (%d)" % [level.CurrentStage, STAGE_FLOOD])
	_check(_limits(camera) == ROOM_FLOOD_LIMITS, "camera limits %s in Room_Flood, expected %s" % [_limits(camera), ROOM_FLOOD_LIMITS])
	_check(is_equal_approx(player.FloorTop, 300.0) and is_equal_approx(player.FloorBottom, 600.0),
		"the floor band changed between rooms (%s..%s); every gate is cut for 300..600" % [player.FloorTop, player.FloorBottom])
	var lights: Node = level.get("Lights")
	var pump: Node = level.get("Pump")
	var flood: Node = level.get_node_or_null("Flood")
	_check(lights != null and pump != null and flood != null, "the level lacks Lights_Drift / Pump / Flood")
	if lights == null or pump == null or flood == null:
		main.queue_free()
		_finish()
		return
	_check(lights.StartsPowered == true, "Lights_Drift.StartsPowered=%s, expected true" % lights.StartsPowered)
	_check(lights.IsPowered == true, "the work lights are not running at level start (StartsPowered did not apply)")
	_check(lights.IsActivated == true, "the work lights hold the bus but their panel is not activated")
	_check(circuit.Used == 1, "Circuit.Used=%s with only the work lights running, expected 1" % circuit.Used)
	var drift_lamps: Node = level.get_node_or_null("DriftLamps")
	_check(drift_lamps != null and drift_lamps.visible == true, "the drift lamps are dark although the work lights hold the bus")

	# 10. The pump is refused, and the refusal names the machine to switch off (acceptance 9).
	var refusals: Array = []
	circuit.RequestRefused.connect(func(m, b): refusals.append([m, b]))
	await _place(player, NEAR_PUMP)
	await _use_panel(pump, player, PUMP_SEQUENCE)
	_check(refusals.size() == 1, "RequestRefused fired %d times for the pump, expected 1" % refusals.size())
	if refusals.size() > 0:
		_check(refusals[0][0] == pump and refusals[0][1] == lights,
			"the refusal was %s blocked by %s, expected the pump blocked by the work lights" % [refusals[0][0], refusals[0][1]])
	_check(pump.IsPowered == false, "the pump started although the work lights hold the bus")
	_check(pump.CanInteract == true, "the refused pump can no longer be used — a refusal must stay retryable")
	await _place(player, NEAR_PUMP)
	_check(hud.PromptText.contains(OVERLOAD_TEXT), "the HUD reads '%s', expected it to contain '%s'" % [hud.PromptText, OVERLOAD_TEXT])

	# 11. Switch the lights off, start the pump: the drift drains for good (acceptance 10).
	await _place(player, NEAR_LIGHTS)
	await _use_panel(lights, player, [])
	_check(lights.IsPowered == false, "the work lights are still running after the switch-off")
	_check(circuit.Used == 0, "Circuit.Used=%s with nothing running, expected 0" % circuit.Used)
	# A refused attempt costs the repair sequence again: the machine has never really started yet.
	await _place(player, NEAR_PUMP)
	await _use_panel(pump, player, PUMP_SEQUENCE)
	_check(pump.IsPowered == true, "the pump did not start on a free bus")
	_check(flood.IsCleared == true, "the flooded drift is still there with the pump running")
	await _check_gate_open(player, flood, "Flood")
	await _place(player, NEAR_PUMP)
	await _use_panel(pump, player, [])
	_check(pump.IsPowered == false, "the pump could not be switched off again")
	_check(flood.IsCleared == true, "the water came back when the pump was switched off — nothing is ever re-solved")

	# 12. On into the gas room.
	await _place(player, CP_GAS)
	_check(level.CurrentStage == STAGE_GAS, "at Checkpoint_Gas1 the stage is %s, expected Gas (%d)" % [level.CurrentStage, STAGE_GAS])
	_check(stages.slice(0, 4) == ["Face", "Blast", "Flood", "Gas"],
		"the stages so far were %s, expected Face, Blast, Flood, Gas" % [stages])
	_check(player.IsKnockedOut == false, "the hero is knocked out at the end of the first half")

	main.queue_free()
	await _step(2)
	_finish()

# A pile is a gate at EVERY depth: the blocker spans the room's whole walk band and a walk along
# the far and the near edge is stopped by it. Then it is cleared and the same walk goes through —
# the control that proves the test itself was not what stopped him.
func _check_gate(level: Node, player: Node, gate: Node, label: String) -> void:
	var box: Shape2D = gate.BlockerShape.shape
	_check(box is RectangleShape2D, "%s's blocker is a %s, expected a RectangleShape2D" % [label, box.get_class()])
	if box is RectangleShape2D:
		var top: float = gate.BlockerShape.global_position.y - box.size.y * 0.5
		var bottom: float = gate.BlockerShape.global_position.y + box.size.y * 0.5
		_check(top <= player.FloorTop and bottom >= player.FloorBottom,
			"%s blocks Y %.0f..%.0f, expected the whole walk band %.0f..%.0f — the hero could walk around it in depth"
			% [label, top, bottom, player.FloorTop, player.FloorBottom])
	for depth in [player.FloorTop + BAND_MARGIN, player.FloorBottom - BAND_MARGIN]:
		var reached: float = await _walk_right(player, Vector2(gate.global_position.x - BLOCK_APPROACH, depth))
		_check(reached <= gate.global_position.x - BLOCK_MARGIN,
			"walking right at Y %.0f the hero reached x %.0f, past %s at x %.0f — the gate can be bypassed in depth"
			% [depth, reached, label, gate.global_position.x])
	_release_all()
	gate.Clear()
	await _step(3)
	await _check_gate_open(player, gate, label)

func _check_gate_open(player: Node, gate: Node, label: String) -> void:
	for depth in [player.FloorTop + BAND_MARGIN, player.FloorBottom - BAND_MARGIN]:
		var reached: float = await _walk_right(player, Vector2(gate.global_position.x - BLOCK_APPROACH, depth))
		_check(reached >= gate.global_position.x + PASS_MARGIN,
			"with %s cleared the hero only reached x %.0f walking at Y %.0f, expected past x %.0f"
			% [label, reached, depth, gate.global_position.x + PASS_MARGIN])
	_release_all()
