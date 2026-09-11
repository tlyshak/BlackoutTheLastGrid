extends SceneTree
# Smoke: a PowerPanel Sequence action the panel never polls (`interact`) — the S3 regression of
# the T-05 review, formerly step 12 of props_interact.gd. _Ready pushes a WARNING (not fatal for
# the runner), the step can never be answered (tapping `interact` does not advance — CurrentStep
# stays 1, no SequenceFailed either) and the attempt ends by StepTimeout with Finished(false), the
# hero back in Idle and the panel usable again. Every assertion of the old step is here.
#
# It lives in its own file for the T-B21 rule: a C# GD.PushWarning raised under a GDScript
# SceneTree script can crash Godot 4.7.2-mono at exit (GodotObject.Finalize →
# godotsharp_internal_object_get_associated_gchandle / refcounted_disposed after the native side is
# gone) once the run has instantiated and freed many scenes. props_interact.gd is the heaviest
# interact script of the suite and carried this warning on purpose — measured 4/12 clean exits on
# 1805a15 and 0/12 on 1b7ab74 (T-07s-e review, B3). This script instantiates one TestRoom and one
# panel, like props_forcepower.gd was split out of props_circuit.gd. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/props_interact_untracked.gd

const NAME := "props_interact_untracked"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s).
const MAX_FRAMES := 1500
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const SETTLE_CAP := 10         # idle frames allowed for the post-load physics catch-up to end (2-3 in practice)
const SETTLE_DELTA := 0.05     # process delta (s) below which the loop is back to normal pacing (16.7 ms at 60 Hz)
const AWAY_POS := Vector2(400, 450)    # TestRoom spawn: > 76 px from every prop
const REACH := Vector2(-30, 0)         # hero offset next to a prop (area r=36 at (0,-20) vs prop r=44)
const PANEL_POS := Vector2(1500, 450)  # clear of TestRoom's own outlet (300, 560) and panel (1100, 430)
const OVERLAP_FRAMES := 3      # physics frames for Area2D overlaps to refresh after a teleport
const FAIL_MARGIN := 5         # extra frames on top of FailResetDelay for Finished(false) -> Idle
const TIMEOUT_MARGIN := 10     # extra frames on top of StepTimeout for the timeout to trigger
const UNTRACKED_SEQUENCE := ["move_up", "interact"]   # `interact` exists in the InputMap but is never polled
const UNTRACKED_STEP_TIMEOUT := 0.5                   # shorter StepTimeout so the timeout does not cost 120 frames

var _started := false
var _frames := 0
var _failures: Array[String] = []
var _transitions: Array = []

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

# Instantiating TestRoom (~100 ms of C# instancing) makes the next iteration run 6-8 physics
# steps back-to-back; wait until the process delta is normal again (same helper as props_interact.gd).
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

# Presses `action` for exactly one physics frame (see props_interact.gd).
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

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()
	var ticks: float = float(Engine.physics_ticks_per_second)

	var panel_scene: PackedScene = load("res://scenes/props/PowerPanel.tscn")
	var scene: PackedScene = load("res://scenes/levels/TestRoom.tscn")
	_check(panel_scene != null, "res://scenes/props/PowerPanel.tscn failed to load")
	_check(scene != null, "res://scenes/levels/TestRoom.tscn failed to load")
	if panel_scene == null or scene == null:
		_finish()
		return
	var room: Node = scene.instantiate()
	root.add_child(room)
	await _settle()

	var player: Node = room.get_node_or_null("Player")
	var hud: Node = room.get_node_or_null("HUD")
	_check(player != null, "TestRoom has no 'Player' child")
	_check(hud != null, "TestRoom has no 'HUD' child")
	if player == null or hud == null or player.get("DepthTolerance") == null or hud.get("PromptText") == null:
		_check(false, "Player/HUD exports missing in TestRoom — C# scripts not attached (did dotnet build run?), aborting")
		room.queue_free()
		_finish()
		return
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	player.StateChanged.connect(func(_from: String, to: String): _transitions.append(to))

	# The unpolled step: _Ready warns on add_child ("Sequence action 'interact' is not polled by
	# the panel") — expected — and the attempt can only end by StepTimeout.
	var panel7: Node = panel_scene.instantiate()
	panel7.Sequence = PackedStringArray(UNTRACKED_SEQUENCE)
	panel7.StepTimeout = UNTRACKED_STEP_TIMEOUT
	panel7.position = PANEL_POS
	root.add_child(panel7)
	_check(Array(panel7.Sequence) == UNTRACKED_SEQUENCE, "untracked: Sequence read back as %s, expected %s" % [Array(panel7.Sequence), UNTRACKED_SEQUENCE])
	var steps7: Array = []
	var failed7: Array = []
	var finished7: Array = []
	var activated7: Array = []
	panel7.SequenceStep.connect(func(i: int, t: int): steps7.append([i, t]))
	panel7.SequenceFailed.connect(func(): failed7.append(true))
	panel7.Finished.connect(func(ok: bool): finished7.append(ok))
	panel7.Activated.connect(func(): activated7.append(true))
	var untracked_timeout_frames: int = int(ceil(panel7.StepTimeout * ticks))
	var fail_frames: int = int(ceil(panel7.FailResetDelay * ticks)) + FAIL_MARGIN
	player.position = PANEL_POS + REACH
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == panel7, "untracked: CurrentInteractable=%s, expected the fresh panel" % player.CurrentInteractable)
	_transitions.clear()
	await _tap("interact")
	await _step(1)
	_check(player.CurrentStateName == "Interact", "untracked: state '%s' after interact, expected 'Interact'" % player.CurrentStateName)
	await _step(2)
	await _tap("move_up")
	await _step(1)
	_check(steps7 == [[1, 2]] and panel7.CurrentStep == 1, "untracked: SequenceStep %s / CurrentStep %d after move_up, expected [[1,2]] / 1" % [steps7, panel7.CurrentStep])
	_check(hud.PromptText == "↑ [interact]", "untracked: prompt '%s' after move_up, expected '↑ [interact]' (no glyph -> action name)" % hud.PromptText)
	await _step(1)
	await _tap("interact")
	await _step(1)
	_check(panel7.CurrentStep == 1, "untracked: CurrentStep=%d after tapping `interact`, expected still 1 (the panel does not poll `interact`)" % panel7.CurrentStep)
	_check(steps7 == [[1, 2]], "untracked: SequenceStep events %s after tapping `interact`, expected still [[1,2]]" % [steps7])
	_check(failed7.is_empty(), "untracked: SequenceFailed %s right after tapping `interact`, expected none yet (unanswered, not wrong)" % [failed7])
	_check(activated7.is_empty(), "untracked: Activated fired on an unpolled action")
	_check(player.CurrentStateName == "Interact", "untracked: state '%s' after tapping `interact`, expected still 'Interact'" % player.CurrentStateName)
	var untracked_failed_at: int = -1
	for i in untracked_timeout_frames + TIMEOUT_MARGIN:
		if failed7.size() > 0:
			untracked_failed_at = i
			break
		await physics_frame
	_check(untracked_failed_at >= 0, "untracked: SequenceFailed not fired within %d frames (StepTimeout %s s) — the unpolled step must time out" % [untracked_timeout_frames + TIMEOUT_MARGIN, panel7.StepTimeout])
	var untracked_idle: int = await _wait_until(func(): return player.CurrentStateName == "Idle", fail_frames)
	_check(untracked_idle >= 0, "untracked: state '%s' %d frames after the timeout, expected 'Idle'" % [player.CurrentStateName, fail_frames])
	_check(finished7 == [false], "untracked: Finished events %s, expected [false]" % [finished7])
	_check(panel7.IsActivated == false and panel7.CurrentStep == 0 and panel7.CanInteract == true, "untracked: IsActivated=%s CurrentStep=%d CanInteract=%s after the timeout, expected false / 0 / true" % [panel7.IsActivated, panel7.CurrentStep, panel7.CanInteract])
	_check(_transitions == ["Interact", "Idle"], "untracked: transitions %s, expected [Interact, Idle]" % [_transitions])
	print("props_interact_untracked: untracked sequence %s timed out %d frames after the last press (StepTimeout %s s = %d frames)" % [UNTRACKED_SEQUENCE, untracked_failed_at, panel7.StepTimeout, untracked_timeout_frames])
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == null, "teardown: CurrentInteractable=%s, expected null" % player.CurrentInteractable)
	panel7.queue_free()
	await _step(1)

	_release_all()
	gs.ResetRun()
	room.queue_free()
	await _step(1)
	_finish()
