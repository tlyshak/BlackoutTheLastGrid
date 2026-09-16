extends SceneTree
# Smoke: interacting with a prop. The only interactable left in the game is the belt lever
# (ConveyorSwitch), so this is the end-to-end proof of the whole chain on the lever the level owns:
# the ConveyorSwitch/ConveyorLine scenes and their exported defaults, the Interactable scene
# contract (Area2D on the Interactable layer 32, mask 0, passive), the hero's InteractionArea
# (mask = layer 32) and his Interact state, the HUD prompt wiring through LevelBase
# (InteractableChanged -> "E: <PromptText>", PromptChanged -> the text as is once the prop is no
# longer usable), the use itself (one `interact` in reach stops the belt: Switched(false),
# Finished(true), the gate shape disabled, the indicators swapped, the handle turned) and the
# one-way rule (a second `interact` never enters Interact; a direct Begin on the spent lever is
# refused with Finished(false)). Interacting away from every prop does nothing.
#
# The cases that need props the level does not own — a lever wired to nothing, a two-way lever and
# the nearest-of-two re-pick — live in tests/smoke/props_interact_untracked.gd. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/props_interact.gd
#
# No attack lands here, so Engine.time_scale stays 1 and everything is counted in physics frames.

const NAME := "props_interact"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls; headless
# runs ~2-3 process frames per physics tick, and a green run uses well under 200 ticks.
const MAX_FRAMES := 3000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const LEVEL := "res://scenes/levels/Level00_Sections.tscn"
const SWITCH_SCENE := "res://scenes/props/ConveyorSwitch.tscn"
const LINE_SCENE := "res://scenes/props/ConveyorLine.tscn"
const SETTLE_CAP := 10         # idle frames allowed for the post-load physics catch-up to end (2-3 in practice)
const SETTLE_DELTA := 0.05     # process delta (s) below which the loop is back to normal pacing (16.7 ms at 60 Hz)
const INTERACTABLE_LAYER := 32 # physics layer 6 "Interactable"
# The level's own lever: the node sits at the foot of the drawn post and its reach rectangle
# (200x300 centred at (1537.65, 450)) covers the whole walk band 300…600 out to the face of the
# belt gate at x 1637.65.
const SWITCH_POS := Vector2(1527.06, 363.06)
const REACH_POS := Vector2(1520, 450)  # hero in front of the lever, short of the gate (x < 1637.65)
const AWAY_POS := Vector2(400, 480)    # the mine face room: no prop in reach, far outside the guard's perception
const OVERLAP_FRAMES := 3      # physics frames for Area2D overlaps to refresh after a teleport
const INTERACT_CAP := 6        # frames allowed for Idle -> Interact -> Idle on the lever
const EXPECTED_PROMPT := "Stop the belt"
const EXPECTED_STOPPED_PROMPT := "Belt stopped"
const EXPECTED_OFF_ROTATION := -73.74   # ConveyorSwitch.OffRotationDegrees default
const EXPECTED_BLOCKER_DEPTH := 300.0   # ConveyorLine.BlockerDepth default: the whole walk band

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

# Instantiating the level (~100 ms of C# instancing) makes the next iteration run several physics
# steps back-to-back; a physics-frame countdown started right after add_child ends inside that
# burst. Wait until the process delta is normal again.
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

# Presses `action` for exactly one physics frame: the press is seen as just-pressed by the node
# callbacks of the next physics frame (frame M); the coroutine resumes at the start of M, before
# those callbacks, and releases. Callers `await _step(1)` before reading what frame M did.
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
	# 0. Preconditions: the InputMap actions the test drives and the GameState autoload.
	for a in ["interact", "move_left", "move_right"]:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)
		if InputMap.has_action(a):
			_check(InputMap.action_get_events(a).size() > 0, "action '%s' has no events" % a)
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	# 1a. The prop scenes load with their C# scripts and the documented export defaults.
	var switch_scene: PackedScene = load(SWITCH_SCENE)
	var line_scene: PackedScene = load(LINE_SCENE)
	_check(switch_scene != null, "%s failed to load" % SWITCH_SCENE)
	_check(line_scene != null, "%s failed to load" % LINE_SCENE)
	if switch_scene == null or line_scene == null:
		_finish()
		return
	var sw_proto: Node = switch_scene.instantiate()
	var line_proto: Node = line_scene.instantiate()
	if sw_proto.get("OffRotationDegrees") == null or line_proto.get("BlockerDepth") == null:
		_check(false, "ConveyorSwitch/ConveyorLine exports missing — C# scripts not attached (did dotnet build run?), aborting")
		sw_proto.free()
		line_proto.free()
		_finish()
		return
	_check(sw_proto is Area2D, "%s root is a %s, expected Area2D (the Interactable contract)" % [SWITCH_SCENE, sw_proto.get_class()])
	_check(sw_proto.get_script() != null and str(sw_proto.get_script().resource_path).ends_with("ConveyorSwitch.cs"),
		"%s has no ConveyorSwitch.cs attached" % SWITCH_SCENE)
	# The line is an Area2D, not a wall: the hero may step onto the belt and the running band carries
	# him back out (the author's playtest of 2026-09-16).
	_check(line_proto is Area2D, "%s root is a %s, expected Area2D" % [LINE_SCENE, line_proto.get_class()])
	_check(line_proto.get_script() != null and str(line_proto.get_script().resource_path).ends_with("ConveyorLine.cs"),
		"%s has no ConveyorLine.cs attached" % LINE_SCENE)
	_check(sw_proto.PromptText == EXPECTED_PROMPT, "ConveyorSwitch.PromptText is '%s', expected '%s'" % [sw_proto.PromptText, EXPECTED_PROMPT])
	_check(sw_proto.StoppedPromptText == EXPECTED_STOPPED_PROMPT, "ConveyorSwitch.StoppedPromptText is '%s', expected '%s'" % [sw_proto.StoppedPromptText, EXPECTED_STOPPED_PROMPT])
	_check(sw_proto.OneWay == true, "ConveyorSwitch.OneWay default is %s, expected true (a hero who respawns past the belt must never be shut in)" % sw_proto.OneWay)
	_check(is_equal_approx(sw_proto.OffRotationDegrees, EXPECTED_OFF_ROTATION), "ConveyorSwitch.OffRotationDegrees is %s, expected %s" % [sw_proto.OffRotationDegrees, EXPECTED_OFF_ROTATION])
	_check(sw_proto.get("SaveId") != null, "ConveyorSwitch.SaveId export missing (T-09 hook)")
	_check(sw_proto.Lever == sw_proto.get_node_or_null("Lever"), "ConveyorSwitch.Lever export does not point at the Lever sprite")
	_check(sw_proto.Line == null, "ConveyorSwitch.Line is set inside the prop scene, expected the owning level to wire it")
	# A lever wired to nothing refuses every use and says so instead of offering the key hint.
	_check(sw_proto.CanInteract == false, "ConveyorSwitch with no Line: CanInteract=%s, expected false" % sw_proto.CanInteract)
	_check(sw_proto.CurrentPrompt == EXPECTED_STOPPED_PROMPT, "ConveyorSwitch with no Line: CurrentPrompt '%s', expected StoppedPromptText" % sw_proto.CurrentPrompt)
	_check(line_proto.Running == true, "ConveyorLine.Running default is %s, expected true (the belt runs until the lever is thrown)" % line_proto.Running)
	_check(is_equal_approx(line_proto.BlockerDepth, EXPECTED_BLOCKER_DEPTH), "ConveyorLine.BlockerDepth default is %s, expected %s (the walk band)" % [line_proto.BlockerDepth, EXPECTED_BLOCKER_DEPTH])
	_check(line_proto.BlockerShape == line_proto.get_node_or_null("CollisionShape2D"), "ConveyorLine.BlockerShape export does not point at the CollisionShape2D")
	_check(line_proto.Belt == line_proto.get_node_or_null("Belt"), "ConveyorLine.Belt export does not point at the Belt sprite")
	_check(line_proto.RunIndicators == line_proto.get_node_or_null("RunLights"), "ConveyorLine.RunIndicators export does not point at RunLights")
	_check(line_proto.StopIndicators == line_proto.get_node_or_null("StopLights"), "ConveyorLine.StopIndicators export does not point at StopLights")
	sw_proto.free()
	line_proto.free()

	# 1b. The level: the lever, the belt, the hero's interaction area and the HUD prompt.
	var packed: PackedScene = load(LEVEL)
	_check(packed != null, "%s failed to load" % LEVEL)
	if packed == null:
		_finish()
		return
	var level: Node = packed.instantiate()
	root.add_child(level)
	current_scene = level
	await _settle()

	var player: Node = level.get_node_or_null("Player")
	var sw: Node = level.get_node_or_null("ConveyorSwitch")
	var line: Node = level.get_node_or_null("ConveyorLine")
	var hud: Node = level.get_node_or_null("HUD")
	_check(player != null, "the level has no 'Player' child")
	_check(sw != null, "the level has no 'ConveyorSwitch' child")
	_check(line != null, "the level has no 'ConveyorLine' child")
	_check(hud != null, "the level has no 'HUD' child")
	if player == null or sw == null or line == null or hud == null:
		level.queue_free()
		_finish()
		return
	if player.get("DepthTolerance") == null or hud.get("PromptText") == null:
		_check(false, "Player/HUD exports missing in the level — C# scripts not attached, aborting")
		level.queue_free()
		_finish()
		return

	# The Interactable scene contract on the lever, and the level's wiring.
	_check(sw is Area2D, "ConveyorSwitch is a %s, expected Area2D" % sw.get_class())
	_check(sw.collision_layer == INTERACTABLE_LAYER, "ConveyorSwitch collision_layer=%d, expected %d (Interactable)" % [sw.collision_layer, INTERACTABLE_LAYER])
	_check(sw.collision_mask == 0, "ConveyorSwitch collision_mask=%d, expected 0" % sw.collision_mask)
	_check(sw.monitoring == false, "ConveyorSwitch monitoring=%s, expected false (passive prop)" % sw.monitoring)
	_check(sw.monitorable == true, "ConveyorSwitch monitorable=%s, expected true" % sw.monitorable)
	_check(sw.get_node_or_null("CollisionShape2D") is CollisionShape2D, "ConveyorSwitch has no CollisionShape2D for its reach")
	_check(sw.IsActive == false, "ConveyorSwitch IsActive=%s at start, expected false" % sw.IsActive)
	_check(sw.position == SWITCH_POS, "ConveyorSwitch at %s, expected %s" % [sw.position, SWITCH_POS])
	_check(sw.Line == line, "ConveyorSwitch.Line points at %s, expected the level's ConveyorLine" % sw.Line)
	_check(sw.SaveId == "belt_switch", "ConveyorSwitch.SaveId is '%s', expected 'belt_switch' (T-09 hook)" % sw.SaveId)
	_check(line.Running == true, "the belt is not running at the start of the level")

	var area: Node = player.get_node_or_null("InteractionArea")
	_check(area is Area2D, "Player has no 'InteractionArea' Area2D child")
	if area is Area2D:
		_check(area.collision_mask == INTERACTABLE_LAYER, "InteractionArea collision_mask=%d, expected %d" % [area.collision_mask, INTERACTABLE_LAYER])
		_check(area.collision_layer == 0, "InteractionArea collision_layer=%d, expected 0" % area.collision_layer)
		_check(area.monitoring == true, "InteractionArea monitoring=%s, expected true" % area.monitoring)
		_check(player.get("InteractionArea") == area, "Player.InteractionArea export does not point at the child")
		var ashape: CollisionShape2D = area.get_node_or_null("CollisionShape2D")
		_check(ashape != null and ashape.shape is CircleShape2D and is_equal_approx(ashape.shape.radius, 36.0), "InteractionArea shape must be a CircleShape2D r=36")
		if ashape != null:
			_check(ashape.position.is_equal_approx(Vector2(0, -20)), "InteractionArea shape at %s, expected (0, -20)" % ashape.position)
	var sm: Node = player.get_node_or_null("StateMachine")
	_check(sm != null, "Player has no StateMachine child")
	if sm == null:
		level.queue_free()
		_finish()
		return
	for s in ["Idle", "Move", "Interact", "Hurt"]:
		_check(sm.HasState(s), "Player StateMachine lacks state '%s'" % s)
	var interact_state: Node = sm.get_node_or_null("Interact")
	_check(interact_state != null and interact_state.get_script() != null and str(interact_state.get_script().resource_path).ends_with("PlayerInteract.cs"),
		"StateMachine/Interact has no PlayerInteract.cs attached")
	var prompt: Node = hud.get("Prompt")
	_check(prompt is Label, "HUD.Prompt export is not a Label")
	if _failures.size() > 0:
		level.queue_free()
		_finish()
		return

	player.StateChanged.connect(func(_from: String, to: String): _transitions.append(to))
	var changes: Array = []
	player.InteractableChanged.connect(func(cur): changes.append(cur))
	var switched: Array = []
	var finished: Array = []
	sw.Switched.connect(func(running: bool): switched.append(running))
	sw.Finished.connect(func(ok: bool): finished.append(ok))
	var blocker: CollisionShape2D = line.BlockerShape

	# 2. Prompt: away -> null / hidden; in reach of the lever -> InteractableChanged(lever) and
	#    "E: Stop the belt"; away again -> InteractableChanged(null), hidden.
	_release_all()
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentStateName == "Idle", "initial player state is '%s', expected 'Idle'" % player.CurrentStateName)
	_check(player.CurrentInteractable == null, "CurrentInteractable=%s away from the lever, expected null" % player.CurrentInteractable)
	_check(changes.is_empty(), "InteractableChanged fired %s away from the lever" % [changes])
	_check(hud.PromptText == "", "prompt '%s' away from the lever, expected hidden" % hud.PromptText)
	player.position = REACH_POS
	await _step(OVERLAP_FRAMES)
	_check(changes.size() == 1 and changes[0] == sw, "InteractableChanged events %s in reach of the lever, expected [ConveyorSwitch]" % [changes])
	_check(player.CurrentInteractable == sw, "CurrentInteractable=%s in reach of the lever, expected ConveyorSwitch" % player.CurrentInteractable)
	_check(prompt.visible, "prompt hidden in reach of the lever")
	_check(hud.PromptText == "E: " + EXPECTED_PROMPT, "prompt '%s' in reach of the lever, expected 'E: %s'" % [hud.PromptText, EXPECTED_PROMPT])
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	_check(changes.size() == 2 and changes[1] == null, "InteractableChanged events %s after leaving, expected [ConveyorSwitch, null]" % [changes])
	_check(player.CurrentInteractable == null, "CurrentInteractable=%s after leaving, expected null" % player.CurrentInteractable)
	_check(prompt.visible == false and hud.PromptText == "", "prompt '%s' still shown after leaving the lever" % hud.PromptText)

	# 3. Away from every prop: `interact` does nothing (no transition, the belt keeps running).
	_transitions.clear()
	await _tap("interact")
	await _step(INTERACT_CAP)
	_check(player.CurrentStateName == "Idle", "away: state '%s' after interact, expected 'Idle'" % player.CurrentStateName)
	_check(_transitions.is_empty(), "away: transitions %s after interact, expected none" % [_transitions])
	_check(line.Running == true, "away: the belt stopped without anyone touching the lever")

	# 4. The use: one `interact` in reach stops the belt. Idle -> Interact -> Idle inside
	#    INTERACT_CAP frames (the lever finishes synchronously), Switched(false) and Finished(true)
	#    once each, the gate shape disabled, the indicators swapped, the handle turned to
	#    OffRotationDegrees, and the prompt is the spent text with no key hint.
	player.position = REACH_POS
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == sw, "lever: CurrentInteractable=%s, expected ConveyorSwitch" % player.CurrentInteractable)
	_check(blocker != null and not blocker.disabled, "lever: the belt gate is already disabled while the belt runs")
	_transitions.clear()
	await _tap("interact")
	var used_frames: int = await _wait_until(func(): return "Interact" in _transitions and player.CurrentStateName == "Idle", INTERACT_CAP)
	await _step(1)   # the blocker is disabled with SetDeferred
	_check(used_frames >= 0, "lever: state '%s' with transitions %s %d frames after interact, expected Interact -> Idle" % [player.CurrentStateName, _transitions, INTERACT_CAP])
	_check(_transitions == ["Interact", "Idle"], "lever: transitions %s, expected [Interact, Idle]" % [_transitions])
	_check(line.Running == false, "lever: the belt is still running after the interact")
	_check(switched == [false], "lever: Switched events %s, expected [false]" % [switched])
	_check(finished == [true], "lever: Finished events %s, expected [true]" % [finished])
	_check(sw.IsActive == false, "lever: IsActive=%s after Finished, expected false" % sw.IsActive)
	_check(blocker != null and blocker.disabled, "lever: the belt is stopped but its gate still blocks the band")
	_check(line.RunIndicators != null and not line.RunIndicators.visible, "lever: the green indicators are still shown with the belt stopped")
	_check(line.StopIndicators != null and line.StopIndicators.visible, "lever: the red indicators did not light when the belt stopped")
	_check(sw.Lever != null and is_equal_approx(sw.Lever.rotation_degrees, sw.OffRotationDegrees),
		"lever: the handle is at %.2f°, expected OffRotationDegrees %.2f" % [sw.Lever.rotation_degrees if sw.Lever != null else 0.0, sw.OffRotationDegrees])
	_check(sw.CurrentPrompt == EXPECTED_STOPPED_PROMPT, "lever: CurrentPrompt '%s' after the use, expected '%s'" % [sw.CurrentPrompt, EXPECTED_STOPPED_PROMPT])
	_check(hud.PromptText == EXPECTED_STOPPED_PROMPT, "lever: prompt '%s' after the use, expected '%s' with no key hint (PromptChanged must refresh the HUD)" % [hud.PromptText, EXPECTED_STOPPED_PROMPT])
	print("props_interact: the lever stopped the belt in %d frames, prompt '%s'" % [used_frames + 1, hud.PromptText])

	# 5. One-way: a second `interact` is refused before the hero ever enters Interact (CanInteract
	#    is false, so nothing is begun and nothing is emitted); a direct Begin is the refusal path
	#    and answers with Finished(false) without restarting the belt.
	_check(sw.CanInteract == false, "spent lever: CanInteract=%s, expected false (OneWay)" % sw.CanInteract)
	_transitions.clear()
	await _tap("interact")
	await _step(INTERACT_CAP)
	_check(_transitions.is_empty(), "spent lever: transitions %s on a second interact, expected none (CanInteract false)" % [_transitions])
	_check(player.CurrentStateName == "Idle", "spent lever: state '%s' after a second interact, expected 'Idle'" % player.CurrentStateName)
	_check(line.Running == false, "spent lever: the belt started again on a second interact")
	_check(switched == [false] and finished == [true], "spent lever: Switched=%s Finished=%s after a second interact, expected still [false] / [true] (Begin never called)" % [switched, finished])
	sw.Begin(player)
	_check(finished == [true, false], "spent lever: Finished events %s after a direct Begin, expected [true, false]" % [finished])
	_check(switched == [false], "spent lever: Switched events %s after the refusal, expected still [false]" % [switched])
	_check(line.Running == false, "spent lever: a direct Begin restarted the belt")
	_check(sw.IsActive == false, "spent lever: IsActive=%s after the refusal, expected false" % sw.IsActive)
	_check(blocker != null and blocker.disabled, "spent lever: the gate blocks the band again after the refusal")
	_check(hud.PromptText == EXPECTED_STOPPED_PROMPT, "spent lever: prompt '%s' after the refusal, expected '%s'" % [hud.PromptText, EXPECTED_STOPPED_PROMPT])

	# 6. Teardown.
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == null, "teardown: CurrentInteractable=%s, expected null" % player.CurrentInteractable)
	_release_all()
	gs.ResetRun()
	level.queue_free()
	await _step(1)
	print("props_interact: idle frames used %d of MAX_FRAMES %d" % [_frames, MAX_FRAMES])
	_finish()
