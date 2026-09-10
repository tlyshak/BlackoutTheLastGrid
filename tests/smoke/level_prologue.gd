extends SceneTree
# Smoke: the prologue level (T-07) driven end to end through Main.tscn — Main instantiates
# Level00_Prologue and records GameState.CurrentScenePath; the intro cutscene plays (hero
# frozen) and `interact` taps advance it without the hero consuming them; the tutorial prompts
# appear with their exported texts (move -> jump over the crate, which blocks a walk and yields
# to a jump -> flashlight, which unlocks Door_1); the outlet charges 60 -> 85; walking into
# Door_1 -> stage Ventilation, camera limits 1920..3840, hero nudged into room 2, door re-locked;
# the panel hint and the fan panel: sequence ↑ J ↓ ␣ ends in FailedNoPower x1 / Activated x0 /
# Finished(false), no stray jump -> NoPower cutscene -> Alarm (Door_2 open, alarm lights on,
# two unaware guards facing left at the markers, hero still frozen) -> Dan's cutscene after
# AlarmToDanDelay -> Escape; Door_2 -> room 3 (limits 3840..5760), the sneak hint; sneaking
# along the dark strip (y 330) with the lamp off past both guards: Noticed 0, IsLit never true,
# guards Idle; control: the lamp on at 390 px is noticed within 8 frames; Exit -> Foreman
# (Energy -FinePenalty, guards frozen) -> Ending -> Done -> Level01_District is the current scene,
# Main is freed, CurrentScenePath updated, time_scale 1. The dead panel refuses a second
# interact and the Escape stage hint outranks its «Обезструмлена». Review regressions: a hero
# teleported into the crate pops out within 6 frames; on a fresh Main the flashlight hint's
# timeout unlocks Door_1 without F; a KO in the prologue reloads Main (a new prologue at Intro,
# Energy full); on the reloaded prologue the flashlight hint auto-completes when the lamp is
# already on.
# Run: godot --headless --path . -s tests/smoke/level_prologue.gd
#
# No hit lands here (the guards never reach the hero), so Engine.time_scale stays 1 and almost
# everything is counted in physics frames; the only real-time waits are the level's own
# SceneTreeTimers (AlarmToDanDelay, RestartDelay) and the deferred scene change, watched on idle
# frames under wall-clock caps. Room hops are teleports inside a room; every door and the exit
# are crossed by walking (the doors report only BodyEntered).

const NAME := "level_prologue"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s). Counts _process calls;
# headless runs ~150 idle frames per second (a green run uses ~2500); 8000 trips at ~55 s.
const MAX_FRAMES := 8000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const MAIN_PATH := "res://scenes/Main.tscn"
const PROLOGUE_PATH := "res://scenes/levels/Level00_Prologue.tscn"
const LEVEL01_PATH := "res://scenes/levels/Level01_District.tscn"
const SETTLE_CAP := 20          # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05      # process delta (s) below which the loop is back to normal pacing
const TAP_CAP := 12             # `interact` taps allowed per cutscene (longest has 3 lines)
const OVERLAP_FRAMES := 3       # physics frames for Area2D overlaps to refresh after a teleport
const STAGES_EXPECTED := ["Tutorial", "Ventilation", "NoPower", "Alarm", "Escape", "Foreman", "Ending", "Done"]
# Stage enum values (C# enums come back as int).
const STAGE_INTRO := 0
const STAGE_TUTORIAL := 1
const STAGE_DONE := 8
# Room 1.
const HERO_START := Vector2(200, 480)
const CRATE_X := 720.0            # JumpableObstacle at x=720, shape 44 wide: the walk stops at ~686
const CRATE_BLOCK_MIN_X := 660.0
const CRATE_BLOCK_MAX_X := 684.5  # review regression: the walk stops at x <= 684 (feet capsule r=7 + safe margin)
const CRATE_HALF_W := 22.0        # half of the crate shape (44 wide)
const CRATE_CLEAR_X := 742.0      # right edge of the crate shape
const POP_OUT_CAP := 6            # frames for a hero teleported inside the crate to be pushed out
const AFTER_CRATE := Vector2(800, 450)
const WALK_TO_CRATE_CAP := 200    # frames for 200 -> 686 at 220 px/s (~133)
const STILL_FRAMES := 3           # consecutive frames without X progress = blocked
const JUMP_CAP := 80              # frames for a full jump (~51 at the defaults)
const FLASH_HINT_X := 1000.0      # FlashlightPrompt centre; box 880..1120
const WALK_TO_HINT_CAP := 120     # frames for ~760 -> 1000
const OUTLET_POS := Vector2(1300, 560)
const REACH := Vector2(-30, 0)
const OUTLET_ENERGY := 60.0
const OUTLET_AMOUNT := 25.0
const INTERACT_CAP := 6
const DOOR1_APPROACH := Vector2(1800, 450)
const DOOR_CAP := 80              # frames to walk ~100 px into a door
const ROOM_VENT_LIMITS := [1920, 0, 3840, 1080]
const ROOM_EXIT_LIMITS := [3840, 0, 5760, 1080]
# Room 2.
const PANEL_HINT_POS := Vector2(2450, 430)   # inside PanelPrompt (2420..2700), out of the panel's reach
const FAN_PANEL_POS := Vector2(2700, 430)
const FAN_PANEL_PROMPT := "Запустити вентилятор"
const SEQUENCE := ["move_up", "attack", "move_down", "jump"]
const FAIL_MARGIN := 8            # frames on top of FailResetDelay for Finished(false)
const SPAWN_CAP := 40             # frames for both guards (first tick + SpawnInterval 0.4 s = 24)
const GUARD_SPAWN := [Vector2(4550, 580), Vector2(5050, 580)]
const DAN_CAP_MS := 3000          # AlarmToDanDelay 1.5 s + margin
const DOOR2_APPROACH := Vector2(3700, 450)
# Room 3.
const SNEAK_Y := 330.0            # dark strip 300..410 above the lit zones (410..600)
const SNEAK_START := Vector2(4100, 330)
const SNEAK_END_X := 5340.0       # past both guards (4550, 5050): 290 px behind the second
const SNEAK_CAP := 420            # frames for 1240 px at 220 px/s (~338)
const CONTROL_POS := Vector2(5350, 330)   # 300 px right / 250 px above guard 2 -> 390 px, inside PerceptionRange 420
const CONTROL_NOTICE_CAP := 8
const EXIT_APPROACH := Vector2(5500, 330) # the Exit area spans x 5560..5640
const EXIT_CAP := 40
const SCENE_CHANGE_CAP_MS := 1500
# KO restart.
const HINT_TIMEOUT := 1.0         # FlashlightPrompt.Timeout used for the timeout regression (default 6 s asserted)
const TIMEOUT_MARGIN := 10        # extra frames on top of the timeout
const RELOAD_CAP_MS := 2500       # RestartDelay 1 s + margin for the reload
const RELOAD_MIN_MS := 900

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

# Instantiating Main + the prologue is heavy; the next iteration runs several physics steps
# back-to-back. Wait until the process delta is normal again (same helper as props_interact.gd).
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
	if Engine.time_scale != 1.0:
		_check(false, "Engine.time_scale=%s at the end, expected 1 (reset by the test)" % Engine.time_scale)
		Engine.time_scale = 1.0
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

# Presses `action` for exactly one physics frame (seen as just-pressed by that frame's callbacks).
func _tap(action: String) -> void:
	Input.action_press(action)
	await _step(1)
	Input.action_release(action)

# Waits (physics frames) until `cond` holds, checking before each frame. Returns the number of
# frames waited, or -1 after `cap` frames.
func _wait_until(cond: Callable, cap: int) -> int:
	for i in cap:
		if cond.call():
			return i
		await physics_frame
	return -1

# Watches idle frames until `pred` holds or `cap_ms` of wall time pass. Returns elapsed ms or -1.
func _watch_ms(pred: Callable, cap_ms: int) -> int:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < cap_ms:
		if pred.call():
			return Time.get_ticks_msec() - start
		await process_frame
	return -1

func _limits(camera: Camera2D) -> Array:
	return [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]

# Taps `interact` (1 frame down, 2 frames pause) until the cutscene emits one more Finished
# (`finished` is a one-element counter Array fed by the signal), at most TAP_CAP times. Returns
# the number of taps it took (-1 if it never finished). Polling IsPlaying would not do: the level
# starts the next cutscene synchronously inside Finished (Foreman -> Ending), and the last one
# frees the whole level (Ending -> Done -> Level01), hence the validity guard.
func _skip_cutscene(cutscene: Node, finished: Array, label: String) -> int:
	var target: int = finished[0] + 1
	var taps := 0
	while finished[0] < target and taps < TAP_CAP and is_instance_valid(cutscene):
		await _tap("interact")
		taps += 1
		await _step(2)
	if finished[0] < target:
		var where: String = "line %d of %d" % [cutscene.CurrentLine, cutscene.LineCount] if is_instance_valid(cutscene) else "cutscene freed"
		_check(false, "%s: cutscene not finished after %d interact taps (%s)" % [label, taps, where])
		return -1
	return taps

# Boots Main.tscn as the tree's current scene and returns {main, level, player, ...} or {} (failure recorded).
func _boot_main(scene: PackedScene, gs: Node, label: String) -> Dictionary:
	_release_all()
	var main: Node = scene.instantiate()
	root.add_child(main)
	current_scene = main   # ReloadCurrentScene / ChangeSceneToPacked act on the tree's current scene
	await _settle()
	var level: Node = main.get("CurrentLevel")
	if level == null:
		_check(false, "%s: Main.CurrentLevel is null after _Ready (Main.cs not attached or StartLevel unset?)" % label)
		return {}
	var player: Node = level.get("Player")
	var cutscene: Node = level.get("Cutscene")
	var hud: Node = level.get("Hud")
	var camera: Camera2D = level.get("Camera")
	if player == null or cutscene == null or hud == null or camera == null or level.get("FinePenalty") == null:
		_check(false, "%s: prologue lacks Player/Cutscene/Hud/Camera or Level00_Prologue.cs is not attached" % label)
		return {}
	var lamp: Node = player.get("Flashlight")
	if lamp == null:
		_check(false, "%s: Player.Flashlight is null" % label)
		return {}
	return {"main": main, "level": level, "player": player, "cutscene": cutscene, "hud": hud, "camera": camera, "lamp": lamp}

func _run() -> void:
	# 0. Preconditions: InputMap actions this script drives, autoloads, scenes.
	for a in ["move_right", "move_up", "move_down", "jump", "attack", "interact", "flashlight"]:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)
		if InputMap.has_action(a):
			_check(InputMap.action_get_events(a).size() > 0, "action '%s' has no events" % a)
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	_check(root.get_node_or_null("HitStop") != null, "HitStop autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()
	gs.CurrentScenePath = ""
	var ticks: float = float(Engine.physics_ticks_per_second)

	var main_scene: PackedScene = load(MAIN_PATH)
	_check(main_scene != null, "%s failed to load" % MAIN_PATH)
	if main_scene == null:
		_finish()
		return

	# 1. Boot: Main builds the prologue, records CurrentScenePath; the level starts at Intro with
	#    the intro cutscene on its first line, the hero frozen (ProcessMode Disabled), no prompt.
	var t0: int = Time.get_ticks_msec()
	var r: Dictionary = await _boot_main(main_scene, gs, "boot")
	if r.is_empty():
		_finish()
		return
	var main: Node = r["main"]
	var level: Node = r["level"]
	var player: Node = r["player"]
	var cutscene: Node = r["cutscene"]
	var hud: Node = r["hud"]
	var camera: Camera2D = r["camera"]
	var lamp: Node = r["lamp"]
	var main_id: int = main.get_instance_id()
	_check(main.get_script() != null and str(main.get_script().resource_path).ends_with("Main.cs"), "Main.tscn has no Main.cs attached (did dotnet build run?)")
	_check(level.get_script() != null and str(level.get_script().resource_path).ends_with("Level00_Prologue.cs"), "Main.CurrentLevel has no Level00_Prologue.cs attached")
	_check(level.name == "Level00_Prologue" and level.scene_file_path == PROLOGUE_PATH, "Main.CurrentLevel is '%s' (%s), expected Level00_Prologue from %s" % [level.name, level.scene_file_path, PROLOGUE_PATH])
	_check(level.get_parent() == main, "the prologue is not a child of Main")
	_check(gs.CurrentScenePath == PROLOGUE_PATH, "GameState.CurrentScenePath='%s' after boot, expected %s" % [gs.CurrentScenePath, PROLOGUE_PATH])
	_check(is_equal_approx(level.FinePenalty, 20.0), "Level00_Prologue.FinePenalty=%s, expected 20" % level.FinePenalty)
	_check(is_equal_approx(level.AlarmBlinkPeriod, 0.5), "Level00_Prologue.AlarmBlinkPeriod=%s, expected 0.5" % level.AlarmBlinkPeriod)
	_check(level.CutsceneSkippable == true, "Level00_Prologue.CutsceneSkippable=%s, expected true" % level.CutsceneSkippable)
	_check(is_equal_approx(level.RestartDelay, 1.0), "Level00_Prologue.RestartDelay=%s, expected 1 (LevelBase export)" % level.RestartDelay)
	var intro_lines: Array = Array(level.IntroLines)
	var nopower_lines: Array = Array(level.NoPowerLines)
	var dan_lines: Array = Array(level.DanLines)
	var foreman_lines: Array = Array(level.ForemanLines)
	var end_lines: Array = Array(level.EndLines)
	_check(intro_lines.size() == 3 and nopower_lines.size() == 2 and dan_lines.size() == 2 and foreman_lines.size() == 2 and end_lines.size() == 3,
		"cutscene line counts intro/nopower/dan/foreman/end = %d/%d/%d/%d/%d, expected 3/2/2/2/3" % [intro_lines.size(), nopower_lines.size(), dan_lines.size(), foreman_lines.size(), end_lines.size()])
	_check(level.CurrentStage == STAGE_INTRO, "stage %s at boot, expected Intro (%d)" % [level.CurrentStage, STAGE_INTRO])
	_check(cutscene.IsPlaying == true and cutscene.CurrentLine == 0, "intro: Cutscene IsPlaying=%s CurrentLine=%s at boot, expected true / 0" % [cutscene.IsPlaying, cutscene.CurrentLine])
	_check(cutscene.Skippable == true, "intro: Cutscene.Skippable=%s, expected true (level export)" % cutscene.Skippable)
	if intro_lines.size() > 0:
		_check(cutscene.TextLabel.text == intro_lines[0], "intro: cutscene text '%s', expected IntroLines[0]" % cutscene.TextLabel.text)
	_check(cutscene.Root.visible == true, "intro: cutscene overlay hidden while playing")
	_check(player.process_mode == Node.PROCESS_MODE_DISABLED, "intro: Player.process_mode=%s during the cutscene, expected Disabled (%d)" % [player.process_mode, Node.PROCESS_MODE_DISABLED])
	_check(level.Tutorial.process_mode == Node.PROCESS_MODE_DISABLED, "intro: Tutorial.process_mode=%s during the cutscene, expected Disabled" % level.Tutorial.process_mode)
	_check(hud.PromptText == "", "intro: HUD prompt '%s' during the cutscene, expected hidden" % hud.PromptText)
	_check(player.position == HERO_START, "hero at %s at boot, expected %s" % [player.position, HERO_START])
	_check(lamp.IsOn == false, "lamp IsOn=%s at boot, expected false" % lamp.IsOn)
	_check(_limits(camera) == [0, 0, 1920, 1080], "camera limits %s at boot, expected [0, 0, 1920, 1080] (Room_Zaboi)" % [_limits(camera)])
	var door1: Node = level.get("Door1")
	var door2: Node = level.get("Door2")
	var fan_panel: Node = level.get("FanPanel")
	var spawner: Node = level.get("GuardSpawner")
	var alarm_lights: Node = level.get("AlarmLights")
	var flash_prompt: Node = level.get("FlashlightPrompt")
	var move_prompt: Node = level.get_node_or_null("Tutorial/MovePrompt")
	var jump_prompt: Node = level.get_node_or_null("Tutorial/JumpPrompt")
	var panel_prompt: Node = level.get_node_or_null("Tutorial/PanelPrompt")
	var sneak_prompt: Node = level.get_node_or_null("Tutorial/SneakPrompt")
	var outlet: Node = level.get_node_or_null("Outlet_1")
	var crate: Node = level.get_node_or_null("Crate")
	var exit_area: Node = level.get("Exit")
	var dan_figure: Node = level.get("DanFigure")
	if door1 == null or door2 == null or fan_panel == null or spawner == null or alarm_lights == null or flash_prompt == null \
		or move_prompt == null or jump_prompt == null or panel_prompt == null or sneak_prompt == null or outlet == null or crate == null or exit_area == null:
		_check(false, "prologue lacks one of Door1/Door2/FanPanel/GuardSpawner/AlarmLights/FlashlightPrompt/Tutorial hints/Outlet_1/Crate/Exit")
		main.queue_free()
		current_scene = null
		_finish()
		return
	_check(door1.Locked == true and door2.Locked == true, "doors Locked=%s/%s at boot, expected both locked" % [door1.Locked, door2.Locked])
	_check(door1.Gate != null and door1.Gate.color.is_equal_approx(door1.LockedColor), "Door_1 gate colour %s at boot, expected LockedColor" % (door1.Gate.color if door1.Gate != null else null))
	_check(fan_panel.Powered == false, "FanPanel.Powered=%s, expected false" % fan_panel.Powered)
	_check(fan_panel.PromptText == FAN_PANEL_PROMPT, "FanPanel.PromptText='%s', expected '%s'" % [fan_panel.PromptText, FAN_PANEL_PROMPT])
	_check(Array(fan_panel.Sequence) == SEQUENCE, "FanPanel.Sequence=%s, expected %s" % [Array(fan_panel.Sequence), SEQUENCE])
	_check(spawner.Count == 2 and spawner.SpawnAware == false and spawner.Spawned == 0, "GuardSpawner Count=%s SpawnAware=%s Spawned=%s, expected 2 / false / 0" % [spawner.Count, spawner.SpawnAware, spawner.Spawned])
	var lights: Array = []
	for c in alarm_lights.get_children():
		if c is PointLight2D:
			lights.append(c)
	_check(lights.size() == 3, "AlarmLights has %d PointLight2D children, expected 3" % lights.size())
	for l in lights:
		_check(l.enabled == false, "alarm light %s enabled at boot" % l.name)
	_check(dan_figure != null and dan_figure.visible == true, "Dan hidden before the intro")
	_check(dan_figure != null and String(dan_figure.name) == "Dan", "DanFigure is '%s', expected the 'Dan' node (T-07i-b replaced the PH_Dan rectangle)" % [dan_figure.name if dan_figure != null else null])
	_check(dan_figure != null and dan_figure.get_node_or_null("Rig") != null, "Dan has no CharacterRig — he must read as a second person, not a rectangle")
	_check(dan_figure != null and dan_figure.get_node_or_null("PH_Shadow") is Polygon2D, "Dan has no PH_Shadow decal — a silhouette must not float")
	_check(level.get_node_or_null("PH_Dan") == null, "the prologue still carries the old PH_Dan rectangle")
	_check(crate.get("ClearHeight") != null and is_equal_approx(crate.ClearHeight, 20.0), "Crate.ClearHeight=%s, expected 20 (JumpableObstacle)" % crate.get("ClearHeight"))
	if _failures.size() > 0:
		main.queue_free()
		current_scene = null
		_finish()
		return

	var stages: Array = []
	level.StageChanged.connect(func(s: String): stages.append(s))
	var finished: Array = [0]
	cutscene.Finished.connect(func(): finished[0] += 1)
	var transitions: Array = []
	player.StateChanged.connect(func(_from: String, to: String): transitions.append(to))

	# 2. Intro: three interact taps end the cutscene; the hero stays Idle (no Interact/attack
	#    from the taps), Tutorial -> the move hint over the start position, Dan gone below.
	var intro_taps: int = await _skip_cutscene(cutscene, finished, "intro")
	_check(intro_taps == intro_lines.size(), "intro: finished after %d taps, expected %d (one per line)" % [intro_taps, intro_lines.size()])
	await _step(OVERLAP_FRAMES)
	_check(level.CurrentStage == STAGE_TUTORIAL and stages == ["Tutorial"], "after the intro: stage %s, StageChanged %s, expected Tutorial" % [level.CurrentStage, stages])
	_check(player.process_mode == Node.PROCESS_MODE_INHERIT, "after the intro: Player.process_mode=%s, expected Inherit (resumed)" % player.process_mode)
	_check(player.CurrentStateName == "Idle" and transitions.is_empty(), "after the intro: hero state '%s' transitions %s, expected Idle with none (the taps must not reach the hero)" % [player.CurrentStateName, transitions])
	_check(move_prompt.IsShowing and hud.PromptText == move_prompt.Text, "after the intro: HUD prompt '%s' (MovePrompt showing=%s), expected '%s'" % [hud.PromptText, move_prompt.IsShowing, move_prompt.Text])
	_check(dan_figure.visible == false, "after the intro: Dan still visible")
	_check(cutscene.Root.visible == false, "after the intro: cutscene overlay still visible")
	print("level_prologue: intro skipped with %d taps, prompt '%s'" % [intro_taps, hud.PromptText])

	# 3. Walk right: the move hint completes on move_right; the jump hint shows on the way; the
	#    crate stops the walk at ~686; a jump (move_right held) clears it and completes the hint.
	var last_x: float = player.position.x
	var still := 0
	var blocked_after := -1
	Input.action_press("move_right")
	for i in WALK_TO_CRATE_CAP:
		await physics_frame
		if absf(player.position.x - last_x) < 0.01:
			still += 1
			if still >= STILL_FRAMES:
				blocked_after = i
				break
		else:
			still = 0
		last_x = player.position.x
	_check(blocked_after >= 0, "crate: hero still moving after %d frames of move_right (x=%.1f), expected to be stopped by the crate" % [WALK_TO_CRATE_CAP, player.position.x])
	var block_x: float = player.position.x
	_check(block_x >= CRATE_BLOCK_MIN_X and block_x <= CRATE_BLOCK_MAX_X, "crate: hero stopped at x=%.1f, expected in [%s, %s] (crate at %s, shape 44 wide)" % [block_x, CRATE_BLOCK_MIN_X, CRATE_BLOCK_MAX_X, CRATE_X])
	_check(move_prompt.IsCompleted, "crate: MovePrompt not completed by move_right")
	_check(jump_prompt.IsShowing and hud.PromptText == jump_prompt.Text, "crate: HUD prompt '%s' (JumpPrompt showing=%s), expected '%s'" % [hud.PromptText, jump_prompt.IsShowing, jump_prompt.Text])
	_check(player.CurrentStateName == "Move", "crate: hero state '%s' while pushing the crate, expected 'Move'" % player.CurrentStateName)
	_check(crate.Shape.disabled == false, "crate: shape disabled while the hero is grounded")
	await _tap("jump")
	var airborne_after: int = await _wait_until(func(): return player.IsAirborne, 3)
	_check(airborne_after >= 0, "crate: hero not airborne within 3 frames of the jump tap (state '%s')" % player.CurrentStateName)
	var shape_opened := false
	var landed_after := -1
	for i in JUMP_CAP:
		await physics_frame
		if crate.Shape.disabled:
			shape_opened = true
		if not player.IsAirborne and player.Height == 0.0:
			landed_after = i
			break
	Input.action_release("move_right")
	_check(landed_after >= 0, "crate: hero still airborne %d frames after the jump (Height %.1f)" % [JUMP_CAP, player.Height])
	_check(shape_opened, "crate: JumpableObstacle shape never disabled during the jump (ClearHeight %s)" % crate.ClearHeight)
	_check(player.position.x > CRATE_CLEAR_X, "crate: hero landed at x=%.1f, expected past the crate (> %s)" % [player.position.x, CRATE_CLEAR_X])
	_check(jump_prompt.IsCompleted, "crate: JumpPrompt not completed by the jump")
	_check(crate.Shape.disabled == false, "crate: shape still disabled after landing")
	print("level_prologue: crate blocked the walk at x=%.1f after %d frames; jump landed at x=%.1f after %d frames" % [block_x, blocked_after, player.position.x, landed_after])

	# 3b. Review regression: a hero teleported inside the crate is pushed out sideways within a
	#     few frames (thin obstacle, depenetration), never stuck in it.
	var idle_after_jump: int = await _wait_until(func(): return player.CurrentStateName == "Idle", 6)
	_check(idle_after_jump >= 0, "pop-out: hero state '%s' after the jump, expected 'Idle'" % player.CurrentStateName)
	player.position = Vector2(CRATE_X, 450)
	var popped_after: int = await _wait_until(func(): return absf(player.position.x - CRATE_X) >= CRATE_HALF_W, POP_OUT_CAP + 1)
	_check(popped_after >= 0, "pop-out: hero still inside the crate (x=%.1f) %d frames after a teleport to x=%s, expected pushed out past |dx| >= %s" % [player.position.x, POP_OUT_CAP, CRATE_X, CRATE_HALF_W])
	_check(player.Height == 0.0 and not player.IsAirborne, "pop-out: hero Height=%.1f IsAirborne=%s, expected grounded" % [player.Height, player.IsAirborne])
	print("level_prologue: teleport into the crate popped out to x=%.1f after %d frames" % [player.position.x, popped_after])
	player.position = AFTER_CRATE
	await _step(OVERLAP_FRAMES)

	# 4. Flashlight hint at x~1000: walk in, the hint shows; a flashlight tap completes it, the lamp
	#    is on and Door_1 unlocks (gate green, blocker off); a second tap switches the lamp off.
	var idle_after_walk: int = await _wait_until(func(): return player.CurrentStateName == "Idle", 6)
	_check(idle_after_walk >= 0, "flashlight: hero state '%s' after releasing move_right, expected 'Idle'" % player.CurrentStateName)
	Input.action_press("move_right")
	var reached_hint: int = await _wait_until(func(): return player.position.x >= FLASH_HINT_X, WALK_TO_HINT_CAP)
	Input.action_release("move_right")
	_check(reached_hint >= 0, "flashlight: hero at x=%.1f after %d frames, expected >= %s" % [player.position.x, WALK_TO_HINT_CAP, FLASH_HINT_X])
	await _step(OVERLAP_FRAMES)
	_check(flash_prompt.IsShowing and hud.PromptText == flash_prompt.Text, "flashlight: HUD prompt '%s' (FlashlightPrompt showing=%s), expected '%s'" % [hud.PromptText, flash_prompt.IsShowing, flash_prompt.Text])
	_check(door1.Locked == true, "flashlight: Door_1 unlocked before the hint completed")
	await _tap("flashlight")
	await _step(1)
	_check(lamp.IsOn == true and player.IsLit == true, "flashlight: IsOn=%s IsLit=%s after the tap, expected true/true" % [lamp.IsOn, player.IsLit])
	_check(flash_prompt.IsCompleted, "flashlight: FlashlightPrompt not completed by the flashlight tap")
	_check(door1.Locked == false, "flashlight: Door_1.Locked=%s after the hint, expected false" % door1.Locked)
	_check(door1.Gate.color.is_equal_approx(door1.OpenColor), "flashlight: Door_1 gate colour %s after the unlock, expected OpenColor %s" % [door1.Gate.color, door1.OpenColor])
	_check(door1.BlockerShape != null and door1.BlockerShape.disabled == true, "flashlight: Door_1 blocker still solid after the unlock")
	_check(hud.PromptText == "", "flashlight: HUD prompt '%s' after the hint completed, expected hidden" % hud.PromptText)
	await _tap("flashlight")
	await _step(1)
	_check(lamp.IsOn == false and player.IsLit == false, "flashlight: IsOn=%s IsLit=%s after the second tap, expected false/false" % [lamp.IsOn, player.IsLit])
	print("level_prologue: flashlight hint at x=%.1f, Door_1 unlocked, lamp back off" % player.position.x)

	# 5. Outlet_1: next to it the prompt reads "E: Зарядити"; interact at Energy 60 -> 85 and the
	#    outlet is spent.
	var charged: Array = []
	outlet.Charged.connect(func(a: float): charged.append(a))
	player.position = OUTLET_POS + REACH
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == outlet, "outlet: CurrentInteractable=%s next to Outlet_1, expected Outlet_1" % player.CurrentInteractable)
	_check(hud.PromptText == "E: " + outlet.PromptText, "outlet: HUD prompt '%s', expected 'E: %s'" % [hud.PromptText, outlet.PromptText])
	gs.Energy = OUTLET_ENERGY
	transitions.clear()
	await _tap("interact")
	var outlet_frames: int = await _wait_until(func(): return "Interact" in transitions and player.CurrentStateName == "Idle", INTERACT_CAP)
	_check(outlet_frames >= 0, "outlet: state '%s' transitions %s after interact, expected Interact -> Idle" % [player.CurrentStateName, transitions])
	_check(is_equal_approx(gs.Energy, OUTLET_ENERGY + OUTLET_AMOUNT), "outlet: Energy=%s after the charge at %s, expected %s" % [gs.Energy, OUTLET_ENERGY, OUTLET_ENERGY + OUTLET_AMOUNT])
	_check(charged == [OUTLET_AMOUNT], "outlet: Charged events %s, expected [%s]" % [charged, OUTLET_AMOUNT])
	_check(outlet.IsSpent == true, "outlet: IsSpent=%s after the use, expected true" % outlet.IsSpent)
	print("level_prologue: outlet %s -> %s" % [OUTLET_ENERGY, gs.Energy])

	# 6. Door_1 by walking: stage Ventilation, Room_Vent camera limits, hero moved past the door
	#    (ArrivalOffset), door locked again behind (gate red, blocker on).
	player.position = DOOR1_APPROACH
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == null, "door 1: CurrentInteractable=%s away from props, expected null" % player.CurrentInteractable)
	Input.action_press("move_right")
	var door1_after: int = await _wait_until(func(): return level.CurrentStage != STAGE_TUTORIAL, DOOR_CAP)
	Input.action_release("move_right")
	_check(door1_after >= 0, "door 1: stage still %s after %d frames of walking from %s (hero x=%.1f)" % [level.CurrentStage, DOOR_CAP, DOOR1_APPROACH, player.position.x])
	await _step(2)
	_check(stages == ["Tutorial", "Ventilation"], "door 1: StageChanged %s, expected [Tutorial, Ventilation]" % [stages])
	_check(_limits(camera) == ROOM_VENT_LIMITS, "door 1: camera limits %s, expected %s (Room_Vent)" % [_limits(camera), ROOM_VENT_LIMITS])
	_check(player.position.x >= door1.position.x + door1.ArrivalOffset.x - 40.0, "door 1: hero x=%.1f after the door, expected nudged past x=%s by ArrivalOffset %s" % [player.position.x, door1.position.x, door1.ArrivalOffset])
	_check(is_equal_approx(player.FloorTop, 300.0) and is_equal_approx(player.FloorBottom, 600.0), "door 1: hero floor band %s..%s, expected 300..600 (Room_Vent)" % [player.FloorTop, player.FloorBottom])
	_check(door1.Locked == true and door1.Gate.color.is_equal_approx(door1.LockedColor), "door 1: Locked=%s gate %s after passing, expected re-locked / LockedColor" % [door1.Locked, door1.Gate.color])
	_check(door1.BlockerShape.disabled == false, "door 1: blocker still off after the door re-locked")
	print("level_prologue: Door_1 crossed after %d frames, hero at x=%.1f, limits %s" % [door1_after, player.position.x, _limits(camera)])

	# 7. Panel hint, then the fan panel: "E: Запустити вентилятор"; interact enters Interact and
	#    completes the hint; ↑ J ↓ ␣ -> FailedNoPower x1, Activated x0, screen red, then
	#    Finished(false) after FailResetDelay -> stage NoPower with its cutscene; the closing
	#    `jump` never leaks (Height 0, no Jump state).
	var idle_in_vent: int = await _wait_until(func(): return player.CurrentStateName == "Idle", 6)
	_check(idle_in_vent >= 0, "vent: hero state '%s' after the door, expected 'Idle'" % player.CurrentStateName)
	player.position = PANEL_HINT_POS
	await _step(OVERLAP_FRAMES)
	_check(panel_prompt.IsShowing and hud.PromptText == panel_prompt.Text, "vent: HUD prompt '%s' (PanelPrompt showing=%s), expected '%s'" % [hud.PromptText, panel_prompt.IsShowing, panel_prompt.Text])
	player.position = FAN_PANEL_POS + REACH
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == fan_panel, "panel: CurrentInteractable=%s next to FanPanel, expected FanPanel" % player.CurrentInteractable)
	_check(hud.PromptText == "E: " + FAN_PANEL_PROMPT, "panel: HUD prompt '%s', expected 'E: %s' (the prop outranks the hint)" % [hud.PromptText, FAN_PANEL_PROMPT])
	var steps: Array = []
	var activated: Array = []
	var no_power: Array = []
	var seq_failed: Array = []
	var pfinished: Array = []
	fan_panel.SequenceStep.connect(func(i: int, t: int): steps.append([i, t]))
	fan_panel.Activated.connect(func(): activated.append(true))
	fan_panel.FailedNoPower.connect(func(): no_power.append(true))
	fan_panel.SequenceFailed.connect(func(): seq_failed.append(true))
	fan_panel.Finished.connect(func(ok: bool): pfinished.append(ok))
	transitions.clear()
	await _tap("interact")
	await _step(1)
	_check(player.CurrentStateName == "Interact", "panel: hero state '%s' after interact, expected 'Interact'" % player.CurrentStateName)
	_check(fan_panel.IsActive == true, "panel: IsActive=%s after interact, expected true" % fan_panel.IsActive)
	_check(panel_prompt.IsCompleted, "panel: PanelPrompt not completed by the interact press")
	await _step(2)
	for k in SEQUENCE.size():
		await _tap(SEQUENCE[k])
		await _step(1)
		_check(steps.size() == k + 1 and steps[-1] == [k + 1, SEQUENCE.size()], "panel: SequenceStep %s after press %d (%s), expected [%d, %d] appended" % [steps, k + 1, SEQUENCE[k], k + 1, SEQUENCE.size()])
		if k + 1 < SEQUENCE.size():
			await _step(1)
	_check(no_power == [true], "panel: FailedNoPower fired %d times after the full sequence, expected once" % no_power.size())
	_check(activated.is_empty(), "panel: Activated fired %d times on an unpowered panel, expected 0" % activated.size())
	_check(seq_failed.is_empty(), "panel: SequenceFailed fired %d times on the correct sequence, expected 0" % seq_failed.size())
	_check(fan_panel.IsActivated == false, "panel: IsActivated=%s, expected false (no power)" % fan_panel.IsActivated)
	_check(fan_panel.Screen != null and fan_panel.Screen.color.is_equal_approx(fan_panel.FailColor), "panel: screen colour %s right after the sequence, expected FailColor (red flash)" % (fan_panel.Screen.color if fan_panel.Screen != null else null))
	_check(pfinished.is_empty(), "panel: Finished %s right after the sequence, expected nothing until FailResetDelay" % [pfinished])
	_check(level.CurrentStage != STAGE_DONE and stages.size() == 2, "panel: StageChanged %s before Finished, expected still [Tutorial, Ventilation]" % [stages])
	var fail_frames: int = int(ceil(fan_panel.FailResetDelay * ticks)) + FAIL_MARGIN
	var jumped := false
	var finished_after := -1
	for i in fail_frames:
		await physics_frame
		if player.CurrentStateName == "Jump" or player.Height > 0.0 or player.IsAirborne:
			jumped = true
		if not pfinished.is_empty() and finished_after < 0:
			finished_after = i
	_check(finished_after >= 0, "panel: Finished not emitted within %d frames after the sequence (FailResetDelay %s s)" % [fail_frames, fan_panel.FailResetDelay])
	_check(pfinished == [false], "panel: Finished events %s, expected [false]" % [pfinished])
	_check(not jumped, "panel: hero jumped after the closing `jump` of the sequence (state '%s')" % player.CurrentStateName)
	_check(not ("Jump" in transitions), "panel: hero transitions %s contain Jump" % [transitions])
	_check(stages == ["Tutorial", "Ventilation", "NoPower"], "panel: StageChanged %s after Finished(false), expected [..., NoPower]" % [stages])
	_check(cutscene.IsPlaying == true and cutscene.CurrentLine == 0, "no-power: Cutscene IsPlaying=%s CurrentLine=%s, expected true / 0" % [cutscene.IsPlaying, cutscene.CurrentLine])
	if nopower_lines.size() > 0:
		_check(cutscene.TextLabel.text == nopower_lines[0], "no-power: cutscene text '%s', expected NoPowerLines[0]" % cutscene.TextLabel.text)
	_check(player.process_mode == Node.PROCESS_MODE_DISABLED, "no-power: Player.process_mode=%s during the cutscene, expected Disabled" % player.process_mode)
	_check(hud.PromptText == "", "no-power: HUD prompt '%s' during the cutscene, expected hidden" % hud.PromptText)
	_check(fan_panel.IsActive == false and fan_panel.CanInteract == false, "no-power: FanPanel IsActive=%s CanInteract=%s, expected false / false (dead after FailedNoPower)" % [fan_panel.IsActive, fan_panel.CanInteract])
	_check(fan_panel.CurrentPrompt == fan_panel.NoPowerPromptText, "no-power: FanPanel.CurrentPrompt '%s', expected NoPowerPromptText '%s'" % [fan_panel.CurrentPrompt, fan_panel.NoPowerPromptText])
	print("level_prologue: panel sequence -> FailedNoPower x%d, Activated x%d, Finished %s after %d frames" % [no_power.size(), activated.size(), pfinished, finished_after])

	# 8. NoPower cutscene -> Alarm: Door_2 unlocked, the three alarm lights enabled, the darkness
	#    tinting, the alarm hint, two guards spawned unaware at the markers facing the hero (-1),
	#    the hero still frozen; after AlarmToDanDelay Dan's cutscene starts.
	var spawned: Array = []
	spawner.EnemySpawned.connect(func(e: Node2D): spawned.append(e))
	var darkness_before: Color = level.Darkness.color
	var nopower_taps: int = await _skip_cutscene(cutscene, finished, "no-power")
	var alarm_msec: int = Time.get_ticks_msec()   # the alarm (and its Dan timer) started with the last tap
	_check(nopower_taps == nopower_lines.size(), "no-power: finished after %d taps, expected %d" % [nopower_taps, nopower_lines.size()])
	_check(stages == ["Tutorial", "Ventilation", "NoPower", "Alarm"], "alarm: StageChanged %s, expected [..., Alarm]" % [stages])
	_check(door2.Locked == false and door2.Gate != null and door2.Gate.color.is_equal_approx(door2.OpenColor), "alarm: Door_2 Locked=%s gate %s, expected unlocked / OpenColor" % [door2.Locked, door2.Gate.color if door2.Gate != null else null])
	for l in lights:
		_check(l.enabled == true, "alarm: alarm light %s enabled=%s, expected true" % [l.name, l.enabled])
	_check(player.process_mode == Node.PROCESS_MODE_DISABLED, "alarm: Player.process_mode=%s, expected still Disabled until Dan's cutscene ends" % player.process_mode)
	_check(hud.PromptText == level.AlarmPromptText, "alarm: HUD prompt '%s', expected AlarmPromptText '%s'" % [hud.PromptText, level.AlarmPromptText])
	_check(spawner.IsRunning == true, "alarm: GuardSpawner.IsRunning=%s, expected true (StartWave)" % spawner.IsRunning)
	var spawn_after: int = await _wait_until(func(): return spawned.size() >= 2, SPAWN_CAP)
	_check(spawn_after >= 0, "alarm: %d guards spawned within %d frames, expected 2" % [spawned.size(), SPAWN_CAP])
	await _step(2)
	_check(spawner.Spawned == 2 and spawner.Alive == 2, "alarm: GuardSpawner Spawned=%s Alive=%s, expected 2 / 2" % [spawner.Spawned, spawner.Alive])
	var guards: Array = []
	for g in spawned:
		if is_instance_valid(g) and g.get("MaxHp") != null:
			guards.append(g)
	_check(guards.size() == 2, "alarm: %d valid Guards among the spawned %d" % [guards.size(), spawned.size()])
	for gi in guards.size():
		var g: Node = guards[gi]
		_check(g.global_position == GUARD_SPAWN[gi], "alarm: guard %d at %s, expected %s" % [gi + 1, g.global_position, GUARD_SPAWN[gi]])
		_check(g.IsAware == false and g.CurrentStateName == "Idle", "alarm: guard %d IsAware=%s state '%s', expected unaware / Idle (SpawnAware false)" % [gi + 1, g.IsAware, g.CurrentStateName])
		_check(g.Facing == -1, "alarm: guard %d Facing=%s, expected -1 (towards the hero)" % [gi + 1, g.Facing])
		_check(g.Target == player, "alarm: guard %d Target is not the hero" % (gi + 1))
	# Lambdas capture locals by value, so the light peak is recorded in an Array.
	var light_peak: Array = [0.0]
	var seen_dan: int = await _watch_ms(func():
		for l in lights:
			light_peak[0] = maxf(light_peak[0], l.energy)
		return cutscene.IsPlaying, DAN_CAP_MS)
	var dan_ms: int = Time.get_ticks_msec() - alarm_msec
	_check(seen_dan >= 0, "alarm: Dan's cutscene did not start within %d ms (AlarmToDanDelay %s s)" % [DAN_CAP_MS, level.AlarmToDanDelay])
	_check(seen_dan < 0 or dan_ms >= int(level.AlarmToDanDelay * 1000.0) - 100, "alarm: Dan's cutscene started %d ms after the alarm, expected >= AlarmToDanDelay %s s" % [dan_ms, level.AlarmToDanDelay])
	var alarm_light_max: float = light_peak[0]
	_check(alarm_light_max > 0.0, "alarm: alarm light energy never rose above 0 while waiting for Dan (blink tween not running)")
	_check(not level.Darkness.color.is_equal_approx(darkness_before), "alarm: Darkness colour %s unchanged since the alarm, expected tinting towards AlarmDarkness" % level.Darkness.color)
	_check(level.CurrentStage != STAGE_DONE and stages.size() == 4, "dan: StageChanged %s when Dan's cutscene started, expected still ending with Alarm" % [stages])
	if dan_lines.size() > 0 and cutscene.IsPlaying:
		_check(cutscene.TextLabel.text == dan_lines[0], "dan: cutscene text '%s', expected DanLines[0]" % cutscene.TextLabel.text)
	_check(hud.PromptText == "", "dan: HUD prompt '%s' during the cutscene, expected hidden" % hud.PromptText)
	for gi in guards.size():
		_check(guards[gi].IsAware == false, "dan: guard %d became aware while the hero stood in room 2" % (gi + 1))
	print("level_prologue: alarm — guards spawned after %d frames, Dan's cutscene %d ms after the alarm, light peak %.2f" % [spawn_after, dan_ms, alarm_light_max])

	# 9. Dan's cutscene -> Escape: hero resumed next to the dead panel — the stage hint outranks
	#    the dead prop's text, an interact tap on it does nothing; the hint stays once away.
	var dan_taps: int = await _skip_cutscene(cutscene, finished, "dan")
	_check(dan_taps == dan_lines.size(), "dan: finished after %d taps, expected %d" % [dan_taps, dan_lines.size()])
	await _step(OVERLAP_FRAMES)
	_check(stages == ["Tutorial", "Ventilation", "NoPower", "Alarm", "Escape"], "escape: StageChanged %s, expected [..., Escape]" % [stages])
	_check(player.process_mode == Node.PROCESS_MODE_INHERIT, "escape: Player.process_mode=%s, expected Inherit (resumed)" % player.process_mode)
	_check(player.CurrentStateName == "Idle", "escape: hero state '%s' after Dan's cutscene, expected 'Idle'" % player.CurrentStateName)
	_check(player.CurrentInteractable == fan_panel, "escape: CurrentInteractable=%s next to the dead panel, expected FanPanel" % player.CurrentInteractable)
	_check(hud.PromptText == level.EscapePromptText, "escape: HUD prompt '%s' next to the dead panel, expected EscapePromptText '%s' (stage hint outranks a dead prop)" % [hud.PromptText, level.EscapePromptText])
	transitions.clear()
	var e_dead: float = gs.Energy
	await _tap("interact")
	await _step(INTERACT_CAP)
	_check(transitions.is_empty() and player.CurrentStateName == "Idle", "dead panel: transitions %s state '%s' after interact, expected none / Idle (CanInteract false)" % [transitions, player.CurrentStateName])
	_check(no_power.size() == 1 and pfinished == [false] and steps.size() == 4, "dead panel: FailedNoPower x%d Finished %s SequenceStep x%d after a second interact, expected unchanged 1 / [false] / 4" % [no_power.size(), pfinished, steps.size()])
	_check(gs.Energy == e_dead, "dead panel: Energy %s -> %s on the second interact, expected unchanged" % [e_dead, gs.Energy])
	player.position = DOOR2_APPROACH
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == null, "escape: CurrentInteractable=%s away from the panel, expected null" % player.CurrentInteractable)
	_check(hud.PromptText == level.EscapePromptText, "escape: HUD prompt '%s' away from the panel, expected EscapePromptText '%s'" % [hud.PromptText, level.EscapePromptText])

	# 10. Door_2 by walking: Room_Exit limits, hero past the door, door re-locked, the stage hint
	#     gone and the sneak hint showing; the lamp is off.
	Input.action_press("move_right")
	var door2_after: int = await _wait_until(func(): return _limits(camera) == ROOM_EXIT_LIMITS, DOOR_CAP)
	Input.action_release("move_right")
	_check(door2_after >= 0, "door 2: camera limits %s after %d frames of walking from %s (hero x=%.1f), expected %s" % [_limits(camera), DOOR_CAP, DOOR2_APPROACH, player.position.x, ROOM_EXIT_LIMITS])
	await _step(OVERLAP_FRAMES)
	_check(player.position.x >= door2.position.x + door2.ArrivalOffset.x - 40.0, "door 2: hero x=%.1f, expected nudged past x=%s" % [player.position.x, door2.position.x])
	_check(door2.Locked == true and door2.Gate.color.is_equal_approx(door2.LockedColor), "door 2: Locked=%s gate %s after passing, expected re-locked / LockedColor" % [door2.Locked, door2.Gate.color])
	_check(level.CurrentStage != STAGE_DONE and stages.size() == 5, "door 2: StageChanged %s, expected no new stage (still Escape)" % [stages])
	_check(sneak_prompt.IsShowing and hud.PromptText == sneak_prompt.Text, "door 2: HUD prompt '%s' (SneakPrompt showing=%s), expected '%s'" % [hud.PromptText, sneak_prompt.IsShowing, sneak_prompt.Text])
	_check(lamp.IsOn == false, "door 2: lamp IsOn=%s before the sneak, expected false" % lamp.IsOn)
	print("level_prologue: Door_2 crossed after %d frames, hero at x=%.1f" % [door2_after, player.position.x])

	# 11. Sneak: along y=330 (dark strip, above the lit zones) from x=4100 to x>=5340 with the lamp
	#     off, sampled every physics frame: no Noticed, IsLit never true, both guards stay Idle
	#     and unaware, no hit on the hero.
	var noticed: Array = []
	var hurt: Array = []
	for gi in guards.size():
		guards[gi].Noticed.connect(func(): noticed.append(gi + 1))
	player.Hurt.connect(func(d: float): hurt.append(d))
	var idle_before_sneak: int = await _wait_until(func(): return player.CurrentStateName == "Idle", 6)
	_check(idle_before_sneak >= 0, "sneak: hero state '%s' before the sneak, expected 'Idle'" % player.CurrentStateName)
	player.position = SNEAK_START
	await _step(OVERLAP_FRAMES)
	_check(player.position.y == SNEAK_Y, "sneak: hero y=%.1f at the start, expected %s (inside the floor band 300..600)" % [player.position.y, SNEAK_Y])
	_check(player.IsLit == false, "sneak: IsLit=%s at %s with the lamp off, expected false" % [player.IsLit, SNEAK_START])
	var lit_frames := 0
	var guard_states: Array = []
	var min_dist: float = INF
	var sneak_after := -1
	Input.action_press("move_right")
	for i in SNEAK_CAP:
		await physics_frame
		if player.IsLit:
			lit_frames += 1
		for g in guards:
			min_dist = minf(min_dist, g.global_position.distance_to(player.global_position))
			if g.CurrentStateName != "Idle" and not guard_states.has(g.CurrentStateName):
				guard_states.append(g.CurrentStateName)
		if player.position.x >= SNEAK_END_X:
			sneak_after = i
			break
	Input.action_release("move_right")
	_check(sneak_after >= 0, "sneak: hero at x=%.1f after %d frames, expected >= %s" % [player.position.x, SNEAK_CAP, SNEAK_END_X])
	_check(noticed.is_empty(), "sneak: Noticed fired by guards %s while sneaking unlit along y=%s, expected none" % [noticed, SNEAK_Y])
	_check(lit_frames == 0, "sneak: IsLit was true on %d frames along the dark strip, expected 0" % lit_frames)
	_check(guard_states.is_empty(), "sneak: guards left Idle (%s) during the sneak" % [guard_states])
	for gi in guards.size():
		_check(guards[gi].IsAware == false and guards[gi].global_position == GUARD_SPAWN[gi], "sneak: guard %d IsAware=%s at %s after the sneak, expected unaware at %s" % [gi + 1, guards[gi].IsAware, guards[gi].global_position, GUARD_SPAWN[gi]])
	_check(hurt.is_empty(), "sneak: hero Hurt %s during the sneak, expected none" % [hurt])
	_check(is_equal_approx(player.position.y, SNEAK_Y), "sneak: hero drifted to y=%.1f, expected %s" % [player.position.y, SNEAK_Y])
	_check(min_dist > 210.0, "sneak: closest approach %.1f px, expected > 210 (PerceptionRange 420 x DarkPerceptionFactor 0.5)" % min_dist)
	print("level_prologue: sneak from x=%s to x=%.1f in %d frames, closest guard %.1f px, Noticed %s, lit frames %d" % [SNEAK_START.x, player.position.x, sneak_after, min_dist, noticed, lit_frames])

	# 12. Control: at 390 px from guard 2 (behind it, so unseen unlit) the lamp on is noticed
	#     within 8 frames; the lamp off again before the exit.
	var idle_before_control: int = await _wait_until(func(): return player.CurrentStateName == "Idle", 6)
	_check(idle_before_control >= 0, "control: hero state '%s', expected 'Idle'" % player.CurrentStateName)
	player.position = CONTROL_POS
	await _step(5)
	var control_dist: float = guards[1].global_position.distance_to(player.global_position) if guards.size() > 1 else -1.0
	_check(noticed.is_empty(), "control: guard noticed the unlit hero at %.0f px behind it (%s), expected unseen" % [control_dist, noticed])
	await _tap("flashlight")
	var control_after: int = await _wait_until(func(): return not noticed.is_empty(), CONTROL_NOTICE_CAP)
	_check(lamp.IsOn == true, "control: lamp IsOn=%s after the tap, expected true" % lamp.IsOn)
	_check(control_after >= 0, "control: lit hero at %.0f px not noticed within %d frames (guard 2 state '%s')" % [control_dist, CONTROL_NOTICE_CAP, guards[1].CurrentStateName if guards.size() > 1 else "?"])
	_check(noticed == [2], "control: Noticed by guards %s, expected [2] (guard 2 at %s)" % [noticed, GUARD_SPAWN[1]])
	if guards.size() > 1:
		_check(guards[1].IsAware == true, "control: guard 2 IsAware=%s after the notice, expected true" % guards[1].IsAware)
	await _tap("flashlight")
	await _step(1)
	_check(lamp.IsOn == false and player.IsLit == false, "control: IsOn=%s IsLit=%s after switching off, expected false/false" % [lamp.IsOn, player.IsLit])
	print("level_prologue: control — lamp on at %.0f px noticed after %d frames by guards %s" % [control_dist, control_after, noticed])

	# 13. Exit by walking: stage Foreman, Energy -FinePenalty, the guard spawner (and its guards)
	#     disabled, the foreman cutscene; then Ending -> Done -> Level01_District is the current
	#     scene, Main freed, CurrentScenePath updated, time_scale 1.
	var idle_before_exit: int = await _wait_until(func(): return player.CurrentStateName == "Idle", 6)
	_check(idle_before_exit >= 0, "exit: hero state '%s', expected 'Idle'" % player.CurrentStateName)
	player.position = EXIT_APPROACH
	await _step(OVERLAP_FRAMES)
	var energy_before_exit: float = gs.Energy
	Input.action_press("move_right")
	var exit_after: int = await _wait_until(func(): return stages.size() >= 6, EXIT_CAP)
	Input.action_release("move_right")
	_check(exit_after >= 0, "exit: no stage change within %d frames of walking from %s (hero x=%.1f, stages %s)" % [EXIT_CAP, EXIT_APPROACH, player.position.x, stages])
	await _step(2)
	_check(stages == ["Tutorial", "Ventilation", "NoPower", "Alarm", "Escape", "Foreman"], "exit: StageChanged %s, expected [..., Foreman]" % [stages])
	_check(is_equal_approx(gs.Energy, energy_before_exit - level.FinePenalty), "foreman: Energy %s -> %s, expected -FinePenalty %s" % [energy_before_exit, gs.Energy, level.FinePenalty])
	_check(spawner.process_mode == Node.PROCESS_MODE_DISABLED, "foreman: GuardSpawner.process_mode=%s, expected Disabled (guards frozen)" % spawner.process_mode)
	_check(cutscene.IsPlaying == true and cutscene.CurrentLine == 0, "foreman: Cutscene IsPlaying=%s CurrentLine=%s, expected true / 0" % [cutscene.IsPlaying, cutscene.CurrentLine])
	if foreman_lines.size() > 0:
		_check(cutscene.TextLabel.text == foreman_lines[0], "foreman: cutscene text '%s', expected ForemanLines[0]" % cutscene.TextLabel.text)
	_check(player.process_mode == Node.PROCESS_MODE_DISABLED, "foreman: Player.process_mode=%s during the cutscene, expected Disabled" % player.process_mode)
	_check(hurt.is_empty(), "foreman: hero Hurt %s before the exit, expected none (the aware guard must not reach the hero)" % [hurt])
	var energy_at_foreman: float = gs.Energy
	var foreman_taps: int = await _skip_cutscene(cutscene, finished, "foreman")
	_check(foreman_taps == foreman_lines.size(), "foreman: finished after %d taps, expected %d" % [foreman_taps, foreman_lines.size()])
	_check(stages.size() == 7 and stages[-1] == "Ending", "ending: StageChanged %s, expected [..., Ending]" % [stages])
	_check(cutscene.IsPlaying == true and cutscene.CurrentLine == 0, "ending: Cutscene IsPlaying=%s CurrentLine=%s, expected true / 0" % [cutscene.IsPlaying, cutscene.CurrentLine])
	if end_lines.size() > 0:
		_check(cutscene.TextLabel.text == end_lines[0], "ending: cutscene text '%s', expected EndLines[0]" % cutscene.TextLabel.text)
	var end_taps: int = await _skip_cutscene(cutscene, finished, "ending")
	_check(end_taps == end_lines.size(), "ending: finished after %d taps, expected %d" % [end_taps, end_lines.size()])
	_check(stages == STAGES_EXPECTED, "done: StageChanged %s, expected %s" % [stages, STAGES_EXPECTED])
	_check(finished[0] == 5, "done: Cutscene.Finished fired %d times over the flow, expected 5 (intro, no-power, Dan, foreman, ending)" % finished[0])
	_check(gs.CurrentScenePath == LEVEL01_PATH, "done: GameState.CurrentScenePath='%s' after GoToLevel, expected %s" % [gs.CurrentScenePath, LEVEL01_PATH])
	# The lambda must not capture `main` (freed by the change, and Godot reports a freed capture);
	# main_id was taken at boot because Main is already gone by now.
	var switched: int = await _watch_ms(func():
		var cs: Node = current_scene
		return cs != null and cs.get_instance_id() != main_id, SCENE_CHANGE_CAP_MS)
	_check(switched >= 0, "done: current scene not switched away from Main within %d ms" % SCENE_CHANGE_CAP_MS)
	var level01: Node = current_scene
	if switched >= 0 and level01 != null:
		await _settle()
		_check(level01.name == "Level01_District" and level01.scene_file_path == LEVEL01_PATH, "done: current scene is '%s' (%s), expected Level01_District from %s" % [level01.name, level01.scene_file_path, LEVEL01_PATH])
		_check(level01.get_script() != null and str(level01.get_script().resource_path).ends_with("Level01_District.cs"), "done: Level01_District has no Level01_District.cs attached")
		_check(level01.get_parent() == root, "done: Level01_District is not a child of root")
		_check(not is_instance_valid(main), "done: Main is still alive after the level change")
		_check(is_equal_approx(gs.Energy, energy_at_foreman), "done: Energy %s -> %s across the level change, expected unchanged" % [energy_at_foreman, gs.Energy])
		var p01: Node = level01.get("Player")
		_check(p01 != null and p01.get("CurrentStateName") != null and p01.CurrentStateName == "Idle", "done: Level01 hero missing or not Idle")
		_check(level01.get_node_or_null("UI/Title") is Label, "done: Level01_District has no UI/Title placeholder label")
	_check(Engine.time_scale == 1.0, "done: Engine.time_scale=%s after the level change, expected 1" % Engine.time_scale)
	var t_flow: int = Time.get_ticks_msec() - t0
	print("level_prologue: full flow in %d ms — stages %s, Energy %s, current scene %s" % [t_flow, stages, gs.Energy, current_scene.name if current_scene != null else null])
	if level01 != null and is_instance_valid(level01):
		level01.queue_free()
	current_scene = null
	_release_all()
	await _step(2)

	# 14. KO restart: a fresh Main, the intro skipped, TakeDamage(999) -> KnockedOut, Energy at
	#     MinEnergy; after RestartDelay the tree reloads Main -> a new prologue instance at Intro
	#     with Energy == MaxEnergy and time_scale 1.
	gs.ResetRun()
	var r2: Dictionary = await _boot_main(main_scene, gs, "ko")
	if r2.is_empty():
		gs.ResetRun()
		_finish()
		return
	var main2: Node = r2["main"]
	var level2: Node = r2["level"]
	var player2: Node = r2["player"]
	var cutscene2: Node = r2["cutscene"]
	var main2_id: int = main2.get_instance_id()   # the lambda below must not capture the node: it is freed by the reload
	_check(level2.CurrentStage == STAGE_INTRO and cutscene2.IsPlaying, "ko: fresh prologue stage %s IsPlaying=%s, expected Intro / true" % [level2.CurrentStage, cutscene2.IsPlaying])
	var finished2: Array = [0]
	cutscene2.Finished.connect(func(): finished2[0] += 1)
	var ko_intro_taps: int = await _skip_cutscene(cutscene2, finished2, "ko intro")
	_check(ko_intro_taps == intro_lines.size(), "ko: intro finished after %d taps, expected %d" % [ko_intro_taps, intro_lines.size()])
	await _step(OVERLAP_FRAMES)

	# 14a. Review regression: the flashlight hint's timeout unlocks Door_1 without F. The export
	#      default (6 s) is asserted, then shortened to HINT_TIMEOUT on this instance so the wait
	#      stays cheap; the lamp stays off throughout.
	var lamp2: Node = r2["lamp"]
	var hud2: Node = r2["hud"]
	var flash2: Node = level2.get("FlashlightPrompt")
	var door1_2: Node = level2.get("Door1")
	if flash2 == null or door1_2 == null:
		_check(false, "timeout: fresh prologue lacks FlashlightPrompt/Door1")
		main2.queue_free()
		current_scene = null
		gs.ResetRun()
		_finish()
		return
	_check(is_equal_approx(flash2.Timeout, 6.0), "timeout: FlashlightPrompt.Timeout=%s in the scene, expected 6" % flash2.Timeout)
	flash2.Timeout = HINT_TIMEOUT
	var timeout_frames: int = int(ceil(HINT_TIMEOUT * ticks))
	_check(lamp2.IsOn == false and door1_2.Locked == true, "timeout: lamp IsOn=%s Door_1.Locked=%s before the hint, expected off / locked" % [lamp2.IsOn, door1_2.Locked])
	player2.position = Vector2(FLASH_HINT_X, 450)
	await _step(OVERLAP_FRAMES)
	_check(flash2.IsShowing and hud2.PromptText == flash2.Text, "timeout: HUD prompt '%s' (showing=%s), expected '%s'" % [hud2.PromptText, flash2.IsShowing, flash2.Text])
	var timed_out_after: int = await _wait_until(func(): return flash2.IsCompleted, timeout_frames + TIMEOUT_MARGIN)
	_check(timed_out_after >= 0, "timeout: FlashlightPrompt not completed within %d frames without F (Timeout %s s)" % [timeout_frames + TIMEOUT_MARGIN, HINT_TIMEOUT])
	_check(timed_out_after < 0 or timed_out_after >= timeout_frames - OVERLAP_FRAMES - 2, "timeout: hint completed after %d frames, expected no earlier than ~%d (Timeout %s s)" % [timed_out_after, timeout_frames, HINT_TIMEOUT])
	_check(lamp2.IsOn == false, "timeout: lamp IsOn=%s after the timeout, expected still off (no F pressed)" % lamp2.IsOn)
	_check(door1_2.Locked == false and door1_2.Gate != null and door1_2.Gate.color.is_equal_approx(door1_2.OpenColor), "timeout: Door_1 Locked=%s after the hint timed out, expected unlocked / OpenColor" % door1_2.Locked)
	_check(hud2.PromptText == "", "timeout: HUD prompt '%s' after the timeout, expected hidden" % hud2.PromptText)
	print("level_prologue: flashlight hint timed out after %d frames (Timeout %s s), Door_1 unlocked without F" % [timed_out_after, HINT_TIMEOUT])
	var ko_events: Array = []
	player2.KnockedOut.connect(func(): ko_events.append(true))
	_check(level2.IsRestartPending == false, "ko: IsRestartPending=%s before the KO, expected false" % level2.IsRestartPending)
	var took: bool = player2.TakeDamage(999.0, 0.0, false, 0)
	_check(took == true, "ko: TakeDamage returned %s, expected true" % took)
	_check(ko_events == [true], "ko: KnockedOut fired %d times, expected once" % ko_events.size())
	_check(player2.IsKnockedOut and player2.CurrentStateName == "KO", "ko: hero IsKnockedOut=%s state '%s', expected true / KO" % [player2.IsKnockedOut, player2.CurrentStateName])
	_check(is_equal_approx(gs.Energy, gs.MinEnergy), "ko: Energy=%s after the KO, expected MinEnergy %s" % [gs.Energy, gs.MinEnergy])
	_check(level2.IsRestartPending == true, "ko: IsRestartPending=%s after the KO, expected true" % level2.IsRestartPending)
	var ko_msec: int = Time.get_ticks_msec()
	var reloaded: int = await _watch_ms(func():
		var cs: Node = current_scene
		return cs != null and cs.get_instance_id() != main2_id, RELOAD_CAP_MS)
	var main3: Node = current_scene
	_check(reloaded >= 0, "ko: Main not reloaded within %d ms of the KO (RestartDelay 1 s)" % RELOAD_CAP_MS)
	if reloaded >= 0 and main3 != null:
		_check(reloaded >= RELOAD_MIN_MS, "ko: reloaded %d ms after the KO, expected >= %d" % [reloaded, RELOAD_MIN_MS])
		await _settle()
		_check(not is_instance_valid(main2), "ko: the old Main is still alive after the reload")
		_check(main3.scene_file_path == MAIN_PATH and main3.name == "Main", "ko: reloaded scene is '%s' (%s), expected Main from %s" % [main3.name, main3.scene_file_path, MAIN_PATH])
		var level3: Node = main3.get("CurrentLevel")
		_check(level3 != null, "ko: reloaded Main has no CurrentLevel")
		if level3 != null:
			_check(level3 != level2 and level3.scene_file_path == PROLOGUE_PATH, "ko: reloaded level is %s, expected a fresh Level00_Prologue" % level3.scene_file_path)
			_check(level3.CurrentStage == STAGE_INTRO, "ko: reloaded prologue stage %s, expected Intro" % level3.CurrentStage)
			var cs3: Node = level3.get("Cutscene")
			_check(cs3 != null and cs3.IsPlaying and cs3.CurrentLine == 0, "ko: reloaded prologue intro cutscene not playing from line 0")
			var p3: Node = level3.get("Player")
			_check(p3 != null and p3.IsKnockedOut == false and p3.position == HERO_START, "ko: reloaded hero IsKnockedOut=%s at %s, expected false at %s" % [p3.IsKnockedOut if p3 != null else null, p3.position if p3 != null else null, HERO_START])
			_check(level3.IsRestartPending == false, "ko: reloaded prologue IsRestartPending=%s, expected false" % level3.IsRestartPending)
		_check(is_equal_approx(gs.Energy, gs.MaxEnergy), "ko: Energy=%s after the reload, expected MaxEnergy %s" % [gs.Energy, gs.MaxEnergy])
		_check(gs.CurrentScenePath == PROLOGUE_PATH, "ko: CurrentScenePath='%s' after the reload, expected %s" % [gs.CurrentScenePath, PROLOGUE_PATH])
	_check(Engine.time_scale == 1.0, "ko: Engine.time_scale=%s after the reload, expected 1" % Engine.time_scale)
	print("level_prologue: ko — reloaded %d ms after the KO, Energy %s, current scene %s" % [reloaded, gs.Energy, main3.name if main3 != null else null])

	# 15. On the reloaded prologue: the flashlight hint with the lamp already on completes at once
	#     (no hint on the HUD — F would only switch the lamp off), the lamp stays on, Door_1 unlocks.
	var level3b: Node = main3.get("CurrentLevel") if main3 != null and is_instance_valid(main3) else null
	if level3b != null:
		var p3b: Node = level3b.get("Player")
		var cs3b: Node = level3b.get("Cutscene")
		var hud3: Node = level3b.get("Hud")
		var flash3: Node = level3b.get("FlashlightPrompt")
		var door1_3: Node = level3b.get("Door1")
		var lamp3: Node = p3b.get("Flashlight") if p3b != null else null
		if p3b != null and cs3b != null and hud3 != null and flash3 != null and door1_3 != null and lamp3 != null:
			var finished3: Array = [0]
			cs3b.Finished.connect(func(): finished3[0] += 1)
			var taps3: int = await _skip_cutscene(cs3b, finished3, "reloaded intro")
			_check(taps3 == intro_lines.size(), "lit hint: reloaded intro finished after %d taps, expected %d" % [taps3, intro_lines.size()])
			await _step(OVERLAP_FRAMES)
			lamp3.SetOn(true)
			_check(lamp3.IsOn == true and door1_3.Locked == true, "lit hint: lamp IsOn=%s Door_1.Locked=%s before the hint, expected on / locked" % [lamp3.IsOn, door1_3.Locked])
			p3b.position = Vector2(FLASH_HINT_X, 450)
			await _step(OVERLAP_FRAMES)
			_check(flash3.IsShown and flash3.IsCompleted and not flash3.IsShowing, "lit hint: FlashlightPrompt IsShown=%s IsCompleted=%s with the lamp on, expected shown and completed at once" % [flash3.IsShown, flash3.IsCompleted])
			_check(hud3.PromptText != flash3.Text, "lit hint: HUD shows the flashlight hint '%s' although the lamp is already on" % hud3.PromptText)
			_check(lamp3.IsOn == true, "lit hint: lamp IsOn=%s after the auto-completed hint, expected still on" % lamp3.IsOn)
			_check(door1_3.Locked == false, "lit hint: Door_1.Locked=%s after the auto-completed hint, expected false" % door1_3.Locked)
			lamp3.SetOn(false)
			print("level_prologue: lit hint auto-completed (HUD '%s'), Door_1 unlocked" % hud3.PromptText)
		else:
			_check(false, "lit hint: reloaded prologue lacks Player/Cutscene/Hud/FlashlightPrompt/Door1")

	# 16. Teardown.
	current_scene = null
	if main3 != null and is_instance_valid(main3):
		main3.queue_free()
	if is_instance_valid(main2):
		main2.queue_free()
	_release_all()
	gs.ResetRun()
	gs.CurrentScenePath = ""
	await _step(2)
	print("level_prologue: idle frames used %d of MAX_FRAMES %d, wall %d ms" % [_frames, MAX_FRAMES, Time.get_ticks_msec() - t0])
	_finish()
