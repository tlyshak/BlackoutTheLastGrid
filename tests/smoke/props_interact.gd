extends SceneTree
# Smoke: interactive props (T-05) — Outlet/PowerPanel scenes + scripts + exports, the hero's
# InteractionArea (mask = Interactable layer 32) and Interact state, HUD prompt wiring through
# TestRoom (InteractableChanged -> "E: <PromptText>", PromptChanged -> text as is), the outlet
# (+Amount capped at MaxEnergy, Charged, Finished, Uses=1 -> spent, unlimited + cooldown variant,
# refusal path), interact away from props (no transition), the panel sequence (SequenceStep 1..4,
# Activated once, PH_Lamp on, no Jump after the closing `jump`, hero frozen while interacting),
# a wrong key (SequenceFailed -> Finished(false) after FailResetDelay, retry succeeds), a hit
# during the sequence (Hurt cancels the panel, no Finished) and the per-step timeout. Review
# regressions: a panel freed or Cancel()ed by the level mid-sequence releases the hero (S1), a
# free outlet (Uses=-1, Cooldown=0) keeps the "E: " prefix after a use (S2), a Sequence action the
# panel never polls warns and cannot advance (S3), the nearest of two props in reach is re-picked
# every physics step while the hero walks or is teleported inside the overlap band (S4), and the
# panel2 retry (panel after the hero in tree order) leaks no Jump. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/props_interact.gd
#
# No attack lands here, so Engine.time_scale stays 1 and everything is counted in physics frames;
# the only real-time wait is the outlet cooldown (Outlet._Process, idle delta) under a wall-clock cap.

const NAME := "props_interact"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls; headless
# runs ~2-3 process frames per physics tick, and a green run uses ~450 ticks.
const MAX_FRAMES := 8000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const SETTLE_CAP := 10         # idle frames allowed for the post-load physics catch-up to end (2-3 in practice)
const SETTLE_DELTA := 0.05     # process delta (s) below which the loop is back to normal pacing (16.7 ms at 60 Hz)
const INTERACTABLE_LAYER := 32 # physics layer 6 "Interactable"
const OUTLET_POS := Vector2(300, 560)
const PANEL_POS := Vector2(1100, 430)
const LAMP_POS := Vector2(1100, 330)
const AWAY_POS := Vector2(400, 450)    # TestRoom spawn: > 76 px from every prop
const REACH := Vector2(-30, 0)         # hero offset next to a prop (area r=36 at (0,-20) vs prop r=40/44)
const OUTLET2_POS := Vector2(1500, 560)
const PANEL2_POS := Vector2(1500, 450)
const PANEL3_POS := Vector2(1700, 450)
const OVERLAP_FRAMES := 3      # physics frames for Area2D overlaps to refresh after a teleport
const INTERACT_CAP := 6        # frames allowed for Idle -> Interact -> Idle on an outlet (plan: 5)
const IDLE_CAP := 4            # frames allowed for the hero to be Idle after the panel finished
const NO_JUMP_FRAMES := 5      # frames Height must stay 0 after the closing `jump` of the sequence
const HURT_IDLE_CAP := 30      # frames for Hurt -> Idle (hurt anim 0.30 s = 18)
const FAIL_MARGIN := 5         # extra frames on top of FailResetDelay for Finished(false) -> Idle
const TIMEOUT_MARGIN := 10     # extra frames on top of StepTimeout for the timeout to trigger
const COOLDOWN_CAP_MS := 1500  # wall-clock cap for a 0.2 s outlet cooldown (idle-delta driven)
const FREE_IDLE_CAP := 3       # frames for Interact -> Idle after the prop is queue_free'd mid-sequence (S1)
const CANCEL_IDLE_CAP := 2     # frames for Interact -> Idle after panel.Cancel() from "the level" (S1)
const BAND_OUTLET_POS := Vector2(1500, 450)   # S4: outlet (r=40) ...
const BAND_PANEL_POS := Vector2(1560, 450)    # ... and panel (r=44) 60 px apart; both in reach for x in ~[1487, 1573]
const BAND_START_POS := Vector2(1480, 450)    # hero start: only the outlet in reach
const BAND_SWITCH_X := 1530.0                 # feet midpoint: the panel is nearer past this x
const BAND_SWITCH_MAX_X := 1540.0             # the switch must show within ~3 frames of the midpoint, well inside the band
const BAND_REPICK_POS := Vector2(1495, 450)   # teleport inside the band (no enter/exit event): outlet nearer again
const BAND_WALK_CAP := 40      # frames of move_right allowed to cross 1480 -> 1530 (220 px/s = 3.7 px/frame -> ~14)
const UNTRACKED_SEQUENCE := ["move_up", "interact"]   # S3: `interact` exists in the InputMap but is never polled
const UNTRACKED_STEP_TIMEOUT := 0.5                   # shorter StepTimeout so the S3 timeout does not cost 120 frames
const EXPECTED_SEQUENCE := ["move_up", "attack", "move_down", "jump"]
const EXPECTED_MARKERS := ["[↑]", "[J]", "[↓]", "[␣]"]   # PowerPanel.ActionGlyphs, current step bracketed

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
# steps back-to-back; a physics-frame countdown started right after add_child ends inside that
# burst. Wait until the process delta is normal again (same helper as combat_dummy.gd).
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

# Checks a prop scene loads with its C# script and returns a free-standing instance (not in the
# tree) or null.
func _load_prop(path: String, script_file: String) -> Node:
	var scene: PackedScene = load(path)
	_check(scene != null, "%s failed to load" % path)
	if scene == null:
		return null
	var inst: Node = scene.instantiate()
	_check(inst is Area2D, "%s root is a %s, expected Area2D" % [path, inst.get_class()])
	_check(inst.get_script() != null and str(inst.get_script().resource_path).ends_with(script_file),
		"%s has no %s attached (did dotnet build run?)" % [path, script_file])
	return inst

# Checks the Interactable scene contract on a prop that is in the tree.
func _check_interactable(node: Node, label: String, radius: float) -> void:
	_check(node is Area2D, "%s is a %s, expected Area2D" % [label, node.get_class()])
	if not (node is Area2D):
		return
	_check(node.collision_layer == INTERACTABLE_LAYER, "%s collision_layer=%d, expected %d (Interactable)" % [label, node.collision_layer, INTERACTABLE_LAYER])
	_check(node.collision_mask == 0, "%s collision_mask=%d, expected 0" % [label, node.collision_mask])
	_check(node.monitoring == false, "%s monitoring=%s, expected false (passive prop)" % [label, node.monitoring])
	_check(node.monitorable == true, "%s monitorable=%s, expected true" % [label, node.monitorable])
	var shape: CollisionShape2D = node.get_node_or_null("CollisionShape2D")
	_check(shape != null and shape.shape is CircleShape2D, "%s has no CollisionShape2D with a CircleShape2D" % label)
	if shape != null and shape.shape is CircleShape2D:
		_check(is_equal_approx(shape.shape.radius, radius), "%s interaction radius=%s, expected %s" % [label, shape.shape.radius, radius])
	_check(node.get("IsActive") == false, "%s IsActive=%s at start, expected false" % [label, node.get("IsActive")])

# Runs the panel's sequence (already in Interact): one tap per action, one settle frame to read
# the result, one more frame between presses. Checks SequenceStep after each press and the
# bracketed marker of the next step in the HUD prompt. Returns the prompts seen.
func _play_sequence(panel: Node, hud: Node, steps: Array, label: String) -> Array:
	var seq: Array = Array(panel.Sequence)
	var prompts: Array = []
	var before: int = steps.size()
	for k in seq.size():
		await _tap(seq[k])
		await _step(1)
		_check(steps.size() == before + k + 1, "%s: SequenceStep fired %d times after press %d (%s), expected %d" % [label, steps.size() - before, k + 1, seq[k], k + 1])
		if steps.size() == before + k + 1:
			_check(steps[-1] == [k + 1, seq.size()], "%s: SequenceStep after press %d is %s, expected [%d, %d]" % [label, k + 1, steps[-1], k + 1, seq.size()])
		prompts.append(hud.PromptText)
		if k + 1 < seq.size():
			_check(hud.PromptText.contains(EXPECTED_MARKERS[k + 1]), "%s: prompt '%s' after press %d, expected the marker %s" % [label, hud.PromptText, k + 1, EXPECTED_MARKERS[k + 1]])
			await _step(1)
	return prompts

func _run() -> void:
	# 0. Preconditions: InputMap (interact + every action the panel polls), GameState, TestRoom.
	for a in ["interact", "move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special"]:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)
		if InputMap.has_action(a):
			_check(InputMap.action_get_events(a).size() > 0, "action '%s' has no events" % a)

	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()
	var ticks: float = float(Engine.physics_ticks_per_second)

	# 1a. Prop scenes load with their scripts and documented export defaults.
	var outlet_proto: Node = _load_prop("res://scenes/props/Outlet.tscn", "Outlet.cs")
	var panel_proto: Node = _load_prop("res://scenes/props/PowerPanel.tscn", "PowerPanel.cs")
	if outlet_proto == null or panel_proto == null or outlet_proto.get("Amount") == null or panel_proto.get("Sequence") == null:
		_check(false, "Outlet.Amount / PowerPanel.Sequence export missing — C# scripts not attached, aborting")
		if outlet_proto != null:
			outlet_proto.free()
		if panel_proto != null:
			panel_proto.free()
		_finish()
		return
	_check(is_equal_approx(outlet_proto.Amount, 25.0), "Outlet.Amount default is %s, expected 25" % outlet_proto.Amount)
	_check(is_equal_approx(outlet_proto.Cooldown, 8.0), "Outlet.Cooldown default is %s, expected 8" % outlet_proto.Cooldown)
	_check(outlet_proto.Uses == 1, "Outlet.Uses default is %s, expected 1" % outlet_proto.Uses)
	_check(outlet_proto.PromptText == "Charge", "Outlet.PromptText is '%s', expected 'Charge'" % outlet_proto.PromptText)
	_check(outlet_proto.SpentPromptText == "Drained", "Outlet.SpentPromptText is '%s', expected 'Drained'" % outlet_proto.SpentPromptText)
	_check(outlet_proto.get("SaveId") != null, "Outlet.SaveId export missing (T-09 hook)")
	_check(outlet_proto.get_node_or_null("PH_Body") is Polygon2D and outlet_proto.get_node_or_null("PH_Indicator") is Polygon2D, "Outlet.tscn lacks PH_Body/PH_Indicator Polygon2D placeholders")
	_check(outlet_proto.get("Indicator") == outlet_proto.get_node_or_null("PH_Indicator"), "Outlet.Indicator export does not point at PH_Indicator")
	_check(Array(panel_proto.Sequence) == EXPECTED_SEQUENCE, "PowerPanel.Sequence default is %s, expected %s" % [Array(panel_proto.Sequence), EXPECTED_SEQUENCE])
	_check(is_equal_approx(panel_proto.StepTimeout, 2.0), "PowerPanel.StepTimeout default is %s, expected 2" % panel_proto.StepTimeout)
	_check(is_equal_approx(panel_proto.FailResetDelay, 0.5), "PowerPanel.FailResetDelay default is %s, expected 0.5" % panel_proto.FailResetDelay)
	_check(panel_proto.PromptText == "Repair", "PowerPanel.PromptText is '%s', expected 'Repair'" % panel_proto.PromptText)
	_check(panel_proto.ActivatedPromptText == "Running", "PowerPanel.ActivatedPromptText is '%s', expected 'Running'" % panel_proto.ActivatedPromptText)
	_check(panel_proto.get_node_or_null("PH_Body") is Polygon2D and panel_proto.get_node_or_null("PH_Screen") is Polygon2D, "PowerPanel.tscn lacks PH_Body/PH_Screen Polygon2D placeholders")
	_check(panel_proto.get("Screen") == panel_proto.get_node_or_null("PH_Screen"), "PowerPanel.Screen export does not point at PH_Screen")
	var outlet_scene: PackedScene = load("res://scenes/props/Outlet.tscn")
	var panel_scene: PackedScene = load("res://scenes/props/PowerPanel.tscn")
	outlet_proto.free()
	panel_proto.free()

	# 1b. TestRoom: props, lamp, HUD prompt, hero InteractionArea + Interact state.
	var scene: PackedScene = load("res://scenes/levels/TestRoom.tscn")
	_check(scene != null, "res://scenes/levels/TestRoom.tscn failed to load")
	if scene == null:
		_finish()
		return
	var room: Node = scene.instantiate()
	root.add_child(room)
	await _settle()

	var player: Node = room.get_node_or_null("Player")
	var outlet: Node = room.get_node_or_null("Outlet")
	var panel: Node = room.get_node_or_null("PowerPanel")
	var lamp: Node = room.get_node_or_null("PH_Lamp")
	var lamp_body: Node = room.get_node_or_null("PH_LampBody")
	var hud: Node = room.get_node_or_null("HUD")
	_check(player != null, "TestRoom has no 'Player' child")
	_check(outlet != null, "TestRoom has no 'Outlet' child")
	_check(panel != null, "TestRoom has no 'PowerPanel' child")
	_check(lamp != null, "TestRoom has no 'PH_Lamp' child")
	_check(hud != null, "TestRoom has no 'HUD' child")
	if player == null or outlet == null or panel == null or lamp == null or hud == null:
		room.queue_free()
		_finish()
		return
	if player.get("DepthTolerance") == null or outlet.get("Amount") == null or panel.get("Sequence") == null or hud.get("PromptText") == null:
		_check(false, "Player/Outlet/PowerPanel/HUD exports missing in TestRoom — C# scripts not attached, aborting")
		room.queue_free()
		_finish()
		return
	_check(outlet.get_script() != null and str(outlet.get_script().resource_path).ends_with("Outlet.cs"), "TestRoom/Outlet has no Outlet.cs attached")
	_check(panel.get_script() != null and str(panel.get_script().resource_path).ends_with("PowerPanel.cs"), "TestRoom/PowerPanel has no PowerPanel.cs attached")
	_check_interactable(outlet, "TestRoom/Outlet", 40.0)
	_check_interactable(panel, "TestRoom/PowerPanel", 44.0)
	_check(outlet.position == OUTLET_POS, "Outlet at %s, expected %s" % [outlet.position, OUTLET_POS])
	_check(panel.position == PANEL_POS, "PowerPanel at %s, expected %s" % [panel.position, PANEL_POS])
	_check(room.get("Panel") == panel, "TestRoom.Panel export does not point at PowerPanel")
	_check(room.get("Lamp") == lamp, "TestRoom.Lamp export does not point at PH_Lamp")
	_check(lamp is PointLight2D, "PH_Lamp is a %s, expected PointLight2D" % lamp.get_class())
	if lamp is PointLight2D:
		_check(lamp.enabled == false, "PH_Lamp.enabled=%s at start, expected false" % lamp.enabled)
		_check(lamp.texture != null, "PH_Lamp.texture is null")
		_check(lamp.position == LAMP_POS, "PH_Lamp at %s, expected %s" % [lamp.position, LAMP_POS])
	_check(lamp_body is Polygon2D, "TestRoom has no 'PH_LampBody' Polygon2D")

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
		room.queue_free()
		_finish()
		return
	for s in ["Idle", "Interact", "Hurt", "Jump"]:
		_check(sm.HasState(s), "Player StateMachine lacks state '%s'" % s)
	var interact_state: Node = sm.get_node_or_null("Interact")
	_check(interact_state != null and interact_state.get_script() != null and str(interact_state.get_script().resource_path).ends_with("PlayerInteract.cs"),
		"StateMachine/Interact has no PlayerInteract.cs attached")
	var prompt: Node = hud.get("Prompt")
	_check(prompt is Label, "HUD.Prompt export is not a Label")
	if prompt is Label:
		_check(prompt.visible == false, "HUD prompt visible at start")
	_check(hud.PromptText == "", "HUD.PromptText at start is '%s', expected ''" % hud.PromptText)
	if _failures.size() > 0:
		room.queue_free()
		_finish()
		return

	player.StateChanged.connect(func(_from: String, to: String): _transitions.append(to))
	var changes: Array = []
	player.InteractableChanged.connect(func(cur): changes.append(cur))
	var indicator: Polygon2D = outlet.Indicator
	var screen: Polygon2D = panel.Screen

	# 2. Prompt: away -> null / hidden; next to the outlet -> InteractableChanged(outlet),
	#    "E: Charge"; away again -> InteractableChanged(null), hidden.
	_release_all()
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentStateName == "Idle", "initial player state is '%s', expected 'Idle'" % player.CurrentStateName)
	_check(player.CurrentInteractable == null, "CurrentInteractable=%s away from props, expected null" % player.CurrentInteractable)
	_check(changes.is_empty(), "InteractableChanged fired %s away from props" % [changes])
	_check(hud.PromptText == "", "prompt '%s' away from props, expected hidden" % hud.PromptText)
	_check(indicator != null and indicator.color.is_equal_approx(outlet.ReadyColor), "Outlet indicator colour %s at start, expected ReadyColor %s" % [indicator.color if indicator != null else null, outlet.ReadyColor])
	_check(screen != null and screen.color.is_equal_approx(panel.DeadColor), "Panel screen colour %s at start, expected DeadColor %s" % [screen.color if screen != null else null, panel.DeadColor])
	player.position = OUTLET_POS + REACH
	await _step(OVERLAP_FRAMES)
	_check(changes.size() == 1 and changes[0] == outlet, "InteractableChanged events %s next to the outlet, expected [Outlet]" % [changes])
	_check(player.CurrentInteractable == outlet, "CurrentInteractable=%s next to the outlet, expected Outlet" % player.CurrentInteractable)
	_check(prompt.visible, "prompt hidden next to the outlet")
	_check(hud.PromptText == "E: Charge", "prompt '%s' next to the outlet, expected 'E: Charge'" % hud.PromptText)
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	_check(changes.size() == 2 and changes[1] == null, "InteractableChanged events %s after leaving, expected [Outlet, null]" % [changes])
	_check(player.CurrentInteractable == null, "CurrentInteractable=%s after leaving, expected null" % player.CurrentInteractable)
	_check(prompt.visible == false and hud.PromptText == "", "prompt '%s' still shown after leaving the outlet" % hud.PromptText)

	# 3a. Outlet: Energy 40 -> 65, Charged(25), Finished(true), Idle -> Interact -> Idle within
	#     INTERACT_CAP frames; Uses=1 -> spent, indicator grey, prompt "Drained".
	var charged: Array = []
	var ofinished: Array = []
	outlet.Charged.connect(func(a: float): charged.append(a))
	outlet.Finished.connect(func(ok: bool): ofinished.append(ok))
	player.position = OUTLET_POS + REACH
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == outlet, "outlet: CurrentInteractable=%s, expected Outlet" % player.CurrentInteractable)
	gs.Energy = 40.0
	_transitions.clear()
	await _tap("interact")
	var outlet_frames: int = await _wait_until(func(): return "Interact" in _transitions and player.CurrentStateName == "Idle", INTERACT_CAP)
	_check(outlet_frames >= 0, "outlet: state '%s' with transitions %s %d frames after interact, expected Interact -> Idle" % [player.CurrentStateName, _transitions, INTERACT_CAP])
	_check(_transitions == ["Interact", "Idle"], "outlet: transitions %s, expected [Interact, Idle]" % [_transitions])
	_check(is_equal_approx(gs.Energy, 65.0), "outlet: Energy=%s after interact at 40, expected 65" % gs.Energy)
	_check(charged == [25.0], "outlet: Charged events %s, expected [25.0]" % [charged])
	_check(ofinished == [true], "outlet: Finished events %s, expected [true]" % [ofinished])
	_check(outlet.IsSpent == true, "outlet: IsSpent=%s after the single use (Uses=1), expected true" % outlet.IsSpent)
	_check(outlet.IsCoolingDown == false, "outlet: IsCoolingDown=%s on a spent outlet, expected false (no cooldown once spent)" % outlet.IsCoolingDown)
	_check(outlet.CanInteract == false, "outlet: CanInteract=%s after the single use, expected false" % outlet.CanInteract)
	_check(outlet.IsActive == false, "outlet: IsActive=%s after Finished, expected false" % outlet.IsActive)
	_check(hud.PromptText.begins_with("Drained"), "outlet: prompt '%s' after the use, expected 'Drained…'" % hud.PromptText)
	_check(indicator.color.is_equal_approx(outlet.SpentColor), "outlet: indicator colour %s after the use, expected SpentColor %s" % [indicator.color, outlet.SpentColor])
	print("props_interact: outlet used in %d frames, prompt '%s'" % [outlet_frames + 1, hud.PromptText])

	# 3b. Second interact on the spent outlet: CanInteract is false so the hero never enters
	#     Interact (no transition, Begin not called, no Finished); Energy unchanged. The refusal
	#     path itself (Begin on an unusable prop -> Finished(false)) is exercised directly.
	_transitions.clear()
	var e_spent: float = gs.Energy
	await _tap("interact")
	await _step(INTERACT_CAP)
	_check(gs.Energy == e_spent, "spent outlet: Energy %s -> %s on a second interact, expected unchanged" % [e_spent, gs.Energy])
	_check(_transitions.is_empty(), "spent outlet: transitions %s on a second interact, expected none (CanInteract false)" % [_transitions])
	_check(player.CurrentStateName == "Idle", "spent outlet: state '%s' after a second interact, expected 'Idle'" % player.CurrentStateName)
	_check(ofinished == [true], "spent outlet: Finished events %s after a second interact, expected still [true] (Begin never called)" % [ofinished])
	outlet.Begin(player)
	_check(ofinished == [true, false], "spent outlet: Finished events %s after a direct Begin, expected [true, false]" % [ofinished])
	_check(gs.Energy == e_spent, "spent outlet: Energy %s -> %s on a direct Begin, expected unchanged" % [e_spent, gs.Energy])
	_check(charged == [25.0], "spent outlet: Charged events %s after the refusal, expected still [25.0]" % [charged])
	_check(outlet.IsActive == false, "spent outlet: IsActive=%s after the refusal, expected false" % outlet.IsActive)

	# 3c. Fresh outlet, unlimited uses + 0.2 s cooldown: Energy 95 -> capped at MaxEnergy; cooling
	#     down (CanInteract false, "Drained (1s)", grey); after the cooldown ready again
	#     (prompt back to "E: Charge", green) and a second use adds 25 again.
	var outlet2: Node = outlet_scene.instantiate()
	outlet2.Uses = -1
	outlet2.Cooldown = 0.2
	outlet2.position = OUTLET2_POS
	root.add_child(outlet2)
	var charged2: Array = []
	outlet2.Charged.connect(func(a: float): charged2.append(a))
	player.position = OUTLET2_POS + REACH
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == outlet2, "outlet2: CurrentInteractable=%s, expected the fresh outlet" % player.CurrentInteractable)
	_check(hud.PromptText == "E: Charge", "outlet2: prompt '%s', expected 'E: Charge'" % hud.PromptText)
	gs.Energy = 95.0
	_transitions.clear()
	await _tap("interact")
	var cap_frames: int = await _wait_until(func(): return "Interact" in _transitions and player.CurrentStateName == "Idle", INTERACT_CAP)
	_check(cap_frames >= 0, "outlet2: state '%s' with transitions %s after interact, expected Interact -> Idle" % [player.CurrentStateName, _transitions])
	_check(is_equal_approx(gs.Energy, gs.MaxEnergy), "outlet2: Energy=%s after interact at 95, expected capped at MaxEnergy=%s" % [gs.Energy, gs.MaxEnergy])
	_check(charged2 == [25.0], "outlet2: Charged events %s, expected [25.0]" % [charged2])
	_check(outlet2.IsSpent == false, "outlet2: IsSpent=%s with Uses=-1, expected false" % outlet2.IsSpent)
	_check(outlet2.IsCoolingDown == true, "outlet2: IsCoolingDown=%s right after the use, expected true" % outlet2.IsCoolingDown)
	_check(outlet2.CanInteract == false, "outlet2: CanInteract=%s during the cooldown, expected false" % outlet2.CanInteract)
	var cooldown_prompt: String = outlet2.CooldownPromptFormat.format([ceili(outlet2.Cooldown)])
	_check(hud.PromptText == cooldown_prompt, "outlet2: prompt '%s' during the cooldown, expected '%s'" % [hud.PromptText, cooldown_prompt])
	_check(outlet2.Indicator.color.is_equal_approx(outlet2.SpentColor), "outlet2: indicator colour %s during the cooldown, expected SpentColor" % outlet2.Indicator.color)
	# The cooldown counts idle delta (Outlet._Process), so wait on idle frames under a wall-clock cap.
	var cd_start: int = Time.get_ticks_msec()
	var cd_ready := false
	while Time.get_ticks_msec() - cd_start < COOLDOWN_CAP_MS:
		await process_frame
		if outlet2.CanInteract:
			cd_ready = true
			break
	var cd_ms: int = Time.get_ticks_msec() - cd_start
	_check(cd_ready, "outlet2: still cooling down %d ms after the use (Cooldown=%s s)" % [cd_ms, outlet2.Cooldown])
	_check(outlet2.IsCoolingDown == false, "outlet2: IsCoolingDown=%s after the cooldown, expected false" % outlet2.IsCoolingDown)
	_check(hud.PromptText == "E: Charge", "outlet2: prompt '%s' after the cooldown, expected 'E: Charge' (PromptChanged must refresh the HUD)" % hud.PromptText)
	_check(outlet2.Indicator.color.is_equal_approx(outlet2.ReadyColor), "outlet2: indicator colour %s after the cooldown, expected ReadyColor" % outlet2.Indicator.color)
	gs.Energy = 40.0
	_transitions.clear()
	await _tap("interact")
	await _step(INTERACT_CAP)
	_check(_transitions == ["Interact", "Idle"], "outlet2: transitions %s on the second use, expected [Interact, Idle]" % [_transitions])
	_check(is_equal_approx(gs.Energy, 65.0), "outlet2: Energy=%s after the second use at 40, expected 65" % gs.Energy)
	_check(charged2 == [25.0, 25.0], "outlet2: Charged events %s after two uses, expected [25.0, 25.0]" % [charged2])
	print("props_interact: outlet2 cooldown %s s lifted after %d ms, prompt was '%s'" % [outlet2.Cooldown, cd_ms, cooldown_prompt])
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == null, "outlet2: CurrentInteractable=%s after leaving, expected null" % player.CurrentInteractable)
	outlet2.queue_free()
	await _step(1)

	# 4. Away from any prop: interact does nothing (Idle, no transition, energy unchanged).
	gs.ResetRun()
	_transitions.clear()
	var e_away: float = gs.Energy
	await _tap("interact")
	await _step(INTERACT_CAP)
	_check(player.CurrentStateName == "Idle", "away: state '%s' after interact, expected 'Idle'" % player.CurrentStateName)
	_check(_transitions.is_empty(), "away: transitions %s after interact, expected none" % [_transitions])
	_check(gs.Energy == e_away, "away: Energy %s -> %s after interact, expected unchanged" % [e_away, gs.Energy])

	# 5. Panel success (TestRoom panel): interact -> Interact + sequence prompt; the four taps
	#    emit SequenceStep 1..4, Activated once, PH_Lamp on, hero Idle (and never Jump) after the
	#    closing `jump`, prompt "Running", CanInteract false, a further interact does nothing.
	var steps: Array = []
	var activated: Array = []
	var pfailed: Array = []
	var pfinished: Array = []
	panel.SequenceStep.connect(func(i: int, t: int): steps.append([i, t]))
	panel.Activated.connect(func(): activated.append(true))
	panel.SequenceFailed.connect(func(): pfailed.append(true))
	panel.Finished.connect(func(ok: bool): pfinished.append(ok))
	player.position = PANEL_POS + REACH
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == panel, "panel: CurrentInteractable=%s, expected PowerPanel" % player.CurrentInteractable)
	_check(hud.PromptText == "E: Repair", "panel: prompt '%s', expected 'E: Repair'" % hud.PromptText)
	var hero_pos: Vector2 = player.position
	_transitions.clear()
	await _tap("interact")
	await _step(1)
	_check(player.CurrentStateName == "Interact", "panel: state '%s' after interact, expected 'Interact'" % player.CurrentStateName)
	_check(panel.IsActive == true, "panel: IsActive=%s after interact, expected true" % panel.IsActive)
	_check(hud.PromptText.contains(EXPECTED_MARKERS[0]), "panel: prompt '%s' at the start of the sequence, expected the marker %s" % [hud.PromptText, EXPECTED_MARKERS[0]])
	_check(screen.color.is_equal_approx(panel.BusyColor), "panel: screen colour %s during the sequence, expected BusyColor %s" % [screen.color, panel.BusyColor])
	var seq_prompt0: String = hud.PromptText
	await _step(2)
	var prompts: Array = await _play_sequence(panel, hud, steps, "panel")
	_check(steps == [[1, 4], [2, 4], [3, 4], [4, 4]], "panel: SequenceStep events %s, expected [[1,4],[2,4],[3,4],[4,4]]" % [steps])
	_check(activated == [true], "panel: Activated fired %d times, expected once" % activated.size())
	_check(pfailed.is_empty(), "panel: SequenceFailed fired %d times on the correct sequence" % pfailed.size())
	_check(pfinished == [true], "panel: Finished events %s, expected [true]" % [pfinished])
	_check(panel.IsActivated == true, "panel: IsActivated=%s after the sequence, expected true" % panel.IsActivated)
	_check(panel.IsActive == false, "panel: IsActive=%s after the sequence, expected false" % panel.IsActive)
	_check(panel.CanInteract == false, "panel: CanInteract=%s after activation, expected false" % panel.CanInteract)
	_check(lamp.enabled == true, "panel: PH_Lamp.enabled=%s after Activated, expected true" % lamp.enabled)
	if lamp_body is Polygon2D:
		_check(lamp_body.modulate.is_equal_approx(room.LampLitModulate), "panel: PH_LampBody.modulate=%s after Activated, expected LampLitModulate %s" % [lamp_body.modulate, room.LampLitModulate])
	_check(screen.color.is_equal_approx(panel.ActiveColor), "panel: screen colour %s after activation, expected ActiveColor %s" % [screen.color, panel.ActiveColor])
	var idle_after: int = await _wait_until(func(): return player.CurrentStateName == "Idle", IDLE_CAP)
	_check(idle_after >= 0, "panel: state '%s' %d frames after the last step, expected 'Idle'" % [player.CurrentStateName, IDLE_CAP])
	var jumped := false
	for i in NO_JUMP_FRAMES:
		await physics_frame
		if player.CurrentStateName == "Jump" or player.Height > 0.0 or player.IsAirborne:
			jumped = true
	_check(not jumped, "panel: hero jumped after the closing `jump` of the sequence (state '%s', Height=%.2f) — the key must not leak into Idle" % [player.CurrentStateName, player.Height])
	_check(_transitions == ["Interact", "Idle"], "panel: transitions %s, expected [Interact, Idle] (no Move/LightAttack1/Jump from the sequence keys)" % [_transitions])
	_check(player.position == hero_pos, "panel: hero moved from %s to %s during the sequence, expected to stand still" % [hero_pos, player.position])
	_check(hud.PromptText == panel.ActivatedPromptText, "panel: prompt '%s' after activation, expected '%s'" % [hud.PromptText, panel.ActivatedPromptText])
	print("props_interact: sequence prompts %s -> %s, Idle %d frames after the last step" % [[seq_prompt0], prompts, idle_after])
	_transitions.clear()
	await _tap("interact")
	await _step(INTERACT_CAP)
	_check(_transitions.is_empty(), "activated panel: transitions %s on interact, expected none" % [_transitions])
	_check(activated.size() == 1 and steps.size() == 4, "activated panel: Activated=%d SequenceStep=%d after a further interact, expected 1/4" % [activated.size(), steps.size()])
	_check(player.CurrentStateName == "Idle", "activated panel: state '%s' after interact, expected 'Idle'" % player.CurrentStateName)

	# 6. Panel failure (fresh panel next to the room): move_up then heavy_attack -> SequenceFailed,
	#    screen red, hero still held; Finished(false) and Idle after FailResetDelay; CurrentStep 0,
	#    not activated, prompt back to "E: Repair"; a retry with the full sequence activates.
	var panel2: Node = panel_scene.instantiate()
	panel2.position = PANEL2_POS
	root.add_child(panel2)
	var steps2: Array = []
	var activated2: Array = []
	var failed2: Array = []
	var finished2: Array = []
	panel2.SequenceStep.connect(func(i: int, t: int): steps2.append([i, t]))
	panel2.Activated.connect(func(): activated2.append(true))
	panel2.SequenceFailed.connect(func(): failed2.append(true))
	panel2.Finished.connect(func(ok: bool): finished2.append(ok))
	var fail_frames: int = int(ceil(panel2.FailResetDelay * ticks)) + FAIL_MARGIN
	player.position = PANEL2_POS + REACH
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == panel2, "panel2: CurrentInteractable=%s, expected the fresh panel" % player.CurrentInteractable)
	_check(hud.PromptText == "E: Repair", "panel2: prompt '%s', expected 'E: Repair'" % hud.PromptText)
	_transitions.clear()
	await _tap("interact")
	await _step(1)
	_check(player.CurrentStateName == "Interact", "panel2: state '%s' after interact, expected 'Interact'" % player.CurrentStateName)
	await _step(2)
	await _tap("move_up")
	await _step(1)
	_check(steps2 == [[1, 4]], "panel2: SequenceStep events %s after move_up, expected [[1, 4]]" % [steps2])
	_check(panel2.CurrentStep == 1, "panel2: CurrentStep=%d after move_up, expected 1" % panel2.CurrentStep)
	await _step(1)
	await _tap("heavy_attack")
	await _step(1)
	_check(failed2 == [true], "panel2: SequenceFailed fired %d times after the wrong key, expected once" % failed2.size())
	_check(panel2.Screen.color.is_equal_approx(panel2.FailColor), "panel2: screen colour %s after the wrong key, expected FailColor %s" % [panel2.Screen.color, panel2.FailColor])
	_check(player.CurrentStateName == "Interact", "panel2: state '%s' right after the wrong key, expected still 'Interact' (released after FailResetDelay)" % player.CurrentStateName)
	_check(finished2.is_empty(), "panel2: Finished %s right after the wrong key, expected nothing until FailResetDelay" % [finished2])
	var fail_idle: int = await _wait_until(func(): return player.CurrentStateName == "Idle", fail_frames)
	_check(fail_idle >= 0, "panel2: state '%s' %d frames after the failure, expected 'Idle' (FailResetDelay %s s)" % [player.CurrentStateName, fail_frames, panel2.FailResetDelay])
	_check(finished2 == [false], "panel2: Finished events %s after the failure, expected [false]" % [finished2])
	_check(panel2.IsActivated == false, "panel2: IsActivated=%s after the failure, expected false" % panel2.IsActivated)
	_check(panel2.IsActive == false, "panel2: IsActive=%s after the failure, expected false" % panel2.IsActive)
	_check(panel2.CurrentStep == 0, "panel2: CurrentStep=%d after the failure, expected 0" % panel2.CurrentStep)
	_check(panel2.CanInteract == true, "panel2: CanInteract=%s after the failure, expected true (retry allowed)" % panel2.CanInteract)
	_check(panel2.Screen.color.is_equal_approx(panel2.DeadColor), "panel2: screen colour %s after the failure, expected DeadColor" % panel2.Screen.color)
	_check(hud.PromptText == "E: Repair", "panel2: prompt '%s' after the failure, expected 'E: Repair'" % hud.PromptText)
	_check(_transitions == ["Interact", "Idle"], "panel2: transitions %s over the failed attempt, expected [Interact, Idle] (heavy_attack must not start HeavyAttack)" % [_transitions])
	_check(activated2.is_empty(), "panel2: Activated fired on a failed attempt")
	print("props_interact: panel2 failure released the hero %d frames after the wrong key (FailResetDelay %s s)" % [fail_idle, panel2.FailResetDelay])
	# Retry.
	_transitions.clear()
	steps2.clear()
	await _tap("interact")
	await _step(1)
	_check(player.CurrentStateName == "Interact", "panel2 retry: state '%s' after interact, expected 'Interact'" % player.CurrentStateName)
	await _step(2)
	await _play_sequence(panel2, hud, steps2, "panel2 retry")
	_check(steps2 == [[1, 4], [2, 4], [3, 4], [4, 4]], "panel2 retry: SequenceStep events %s, expected 1..4" % [steps2])
	_check(activated2 == [true], "panel2 retry: Activated fired %d times, expected once" % activated2.size())
	_check(finished2 == [false, true], "panel2 retry: Finished events %s, expected [false, true]" % [finished2])
	_check(panel2.IsActivated == true, "panel2 retry: IsActivated=%s, expected true" % panel2.IsActivated)
	var retry_idle: int = await _wait_until(func(): return player.CurrentStateName == "Idle", IDLE_CAP)
	_check(retry_idle >= 0, "panel2 retry: state '%s' after the sequence, expected 'Idle'" % player.CurrentStateName)
	_check(lamp.enabled == true, "panel2 retry: TestRoom lamp switched off (%s)?" % lamp.enabled)
	# panel2 sits AFTER the hero in tree order (added to root after the room): the closing `jump`
	# must not leak into Idle in this process order either.
	var retry_jumped := false
	for i in NO_JUMP_FRAMES:
		await physics_frame
		if player.CurrentStateName == "Jump" or player.Height != 0.0 or player.IsAirborne:
			retry_jumped = true
	_check(not retry_jumped, "panel2 retry: hero jumped after the closing `jump` (state '%s', Height=%.2f) — panel after the hero in tree order" % [player.CurrentStateName, player.Height])
	_check(_transitions == ["Interact", "Idle"], "panel2 retry: transitions %s, expected [Interact, Idle] (panel after the hero in tree order)" % [_transitions])
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	panel2.queue_free()
	await _step(1)

	# 7. Interrupt: a hit one step into the sequence -> Hurt, the panel is cancelled (IsActive
	#    false, CurrentStep 0, screen dead, no Finished), prompt back to the idle hint, Idle later.
	var panel3: Node = panel_scene.instantiate()
	panel3.position = PANEL3_POS
	root.add_child(panel3)
	var steps3: Array = []
	var failed3: Array = []
	var finished3: Array = []
	var activated3: Array = []
	panel3.SequenceStep.connect(func(i: int, t: int): steps3.append([i, t]))
	panel3.SequenceFailed.connect(func(): failed3.append(true))
	panel3.Finished.connect(func(ok: bool): finished3.append(ok))
	panel3.Activated.connect(func(): activated3.append(true))
	gs.ResetRun()
	player.position = PANEL3_POS + REACH
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == panel3, "panel3: CurrentInteractable=%s, expected the fresh panel" % player.CurrentInteractable)
	_transitions.clear()
	await _tap("interact")
	await _step(1)
	_check(player.CurrentStateName == "Interact", "panel3: state '%s' after interact, expected 'Interact'" % player.CurrentStateName)
	await _step(2)
	await _tap("move_up")
	await _step(1)
	_check(steps3 == [[1, 4]] and panel3.CurrentStep == 1, "panel3: SequenceStep %s / CurrentStep %d after move_up, expected [[1,4]] / 1" % [steps3, panel3.CurrentStep])
	var took: bool = player.TakeDamage(1.0, 0.0, false, 0)
	_check(took == true, "panel3: TakeDamage returned %s, expected true" % took)
	_check(player.CurrentStateName == "Hurt", "panel3: state '%s' right after the hit, expected 'Hurt'" % player.CurrentStateName)
	_check(panel3.IsActive == false, "panel3: IsActive=%s after the hit, expected false (Interact.Exit must Cancel)" % panel3.IsActive)
	_check(panel3.CurrentStep == 0, "panel3: CurrentStep=%d after the cancel, expected 0" % panel3.CurrentStep)
	_check(panel3.IsActivated == false, "panel3: IsActivated=%s after the cancel, expected false" % panel3.IsActivated)
	_check(finished3.is_empty(), "panel3: Finished %s after a cancel, expected none (Cancel emits no Finished)" % [finished3])
	_check(failed3.is_empty(), "panel3: SequenceFailed fired on a cancel")
	_check(panel3.Screen.color.is_equal_approx(panel3.DeadColor), "panel3: screen colour %s after the cancel, expected DeadColor" % panel3.Screen.color)
	_check(hud.PromptText == "E: Repair", "panel3: prompt '%s' after the cancel, expected 'E: Repair'" % hud.PromptText)
	var hurt_idle: int = await _wait_until(func(): return player.CurrentStateName == "Idle", HURT_IDLE_CAP)
	_check(hurt_idle >= 0, "panel3: state '%s' %d frames after the hit, expected 'Idle'" % [player.CurrentStateName, HURT_IDLE_CAP])
	_check(_transitions == ["Interact", "Hurt", "Idle"], "panel3: transitions %s, expected [Interact, Hurt, Idle]" % [_transitions])
	_check(panel3.IsActive == false and panel3.CurrentStep == 0, "panel3: IsActive=%s CurrentStep=%d after Hurt -> Idle, expected false / 0" % [panel3.IsActive, panel3.CurrentStep])
	_check(is_equal_approx(gs.Energy, gs.MaxEnergy - 1.0), "panel3: Energy=%s after a 1-damage hit, expected MaxEnergy-1" % gs.Energy)
	gs.ResetRun()

	# 8. Step timeout on the same (still dead) panel: interact, no key for StepTimeout ->
	#    SequenceFailed no earlier than StepTimeout, Finished(false) + Idle after FailResetDelay.
	var timeout_frames: int = int(ceil(panel3.StepTimeout * ticks))
	_check(is_equal_approx(panel3.StepTimeout, 2.0), "panel3: StepTimeout=%s, expected the 2.0 default" % panel3.StepTimeout)
	_transitions.clear()
	steps3.clear()
	await _tap("interact")
	await _step(1)
	_check(player.CurrentStateName == "Interact", "timeout: state '%s' after interact, expected 'Interact'" % player.CurrentStateName)
	_check(panel3.IsActive == true, "timeout: IsActive=%s after interact, expected true" % panel3.IsActive)
	var failed_at: int = -1
	for i in timeout_frames + TIMEOUT_MARGIN:
		if failed3.size() > 0:
			failed_at = i
			break
		await physics_frame
	_check(failed_at >= 0, "timeout: SequenceFailed not fired within %d frames without a key (StepTimeout %s s)" % [timeout_frames + TIMEOUT_MARGIN, panel3.StepTimeout])
	_check(failed_at < 0 or failed_at >= timeout_frames - 2, "timeout: SequenceFailed after %d frames, expected no earlier than ~%d (StepTimeout %s s)" % [failed_at, timeout_frames, panel3.StepTimeout])
	_check(steps3.is_empty(), "timeout: SequenceStep fired %s without a key" % [steps3])
	var timeout_idle: int = await _wait_until(func(): return player.CurrentStateName == "Idle", fail_frames)
	_check(timeout_idle >= 0, "timeout: state '%s' %d frames after the failure, expected 'Idle'" % [player.CurrentStateName, fail_frames])
	_check(finished3 == [false], "timeout: Finished events %s, expected [false]" % [finished3])
	_check(panel3.IsActive == false and panel3.CurrentStep == 0 and panel3.IsActivated == false, "timeout: IsActive=%s CurrentStep=%d IsActivated=%s after the timeout, expected false / 0 / false" % [panel3.IsActive, panel3.CurrentStep, panel3.IsActivated])
	_check(panel3.CanInteract == true, "timeout: CanInteract=%s after the timeout, expected true" % panel3.CanInteract)
	_check(_transitions == ["Interact", "Idle"], "timeout: transitions %s, expected [Interact, Idle]" % [_transitions])
	_check(activated3.is_empty(), "timeout: Activated fired without a sequence")
	print("props_interact: timeout fired %d frames after interact (StepTimeout %s s = %d frames), Idle %d frames later" % [failed_at, panel3.StepTimeout, timeout_frames, timeout_idle])

	# 9. S1 — the prop vanishes mid-sequence: a standalone panel is queue_free'd one step into its
	#    sequence -> the hero leaves Interact on his own (Idle within FREE_IDLE_CAP frames, no
	#    Finished), CurrentInteractable null, prompt hidden, and he can walk again.
	var panel4: Node = panel_scene.instantiate()
	panel4.position = PANEL2_POS
	root.add_child(panel4)
	var finished4: Array = []
	panel4.Finished.connect(func(ok: bool): finished4.append(ok))
	player.position = PANEL2_POS + REACH
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == panel4, "freed panel: CurrentInteractable=%s, expected the fresh panel" % player.CurrentInteractable)
	_transitions.clear()
	await _tap("interact")
	await _step(1)
	_check(player.CurrentStateName == "Interact", "freed panel: state '%s' after interact, expected 'Interact'" % player.CurrentStateName)
	await _step(2)
	await _tap("move_up")
	await _step(1)
	_check(panel4.CurrentStep == 1, "freed panel: CurrentStep=%d after move_up, expected 1" % panel4.CurrentStep)
	panel4.queue_free()
	await _step(FREE_IDLE_CAP)
	_check(not is_instance_valid(panel4), "freed panel: still a valid instance %d frames after queue_free" % FREE_IDLE_CAP)
	_check(player.CurrentStateName == "Idle", "freed panel: state '%s' %d frames after queue_free, expected 'Idle' (S1: Interact must leave when the prop is gone)" % [player.CurrentStateName, FREE_IDLE_CAP])
	_check(_transitions == ["Interact", "Idle"], "freed panel: transitions %s, expected [Interact, Idle]" % [_transitions])
	_check(finished4.is_empty(), "freed panel: Finished %s, expected none (the panel never finished)" % [finished4])
	_check(player.CurrentInteractable == null, "freed panel: CurrentInteractable=%s after the free, expected null" % player.CurrentInteractable)
	_check(hud.PromptText == "", "freed panel: prompt '%s' after the free, expected hidden" % hud.PromptText)
	var freed_x: float = player.position.x
	Input.action_press("move_right")
	await _step(3)
	Input.action_release("move_right")
	_check(player.position.x > freed_x, "freed panel: hero did not move on move_right after the free (x %.1f -> %.1f) — still soft-locked?" % [freed_x, player.position.x])
	var freed_idle: int = await _wait_until(func(): return player.CurrentStateName == "Idle", IDLE_CAP)
	_check(freed_idle >= 0, "freed panel: state '%s' after releasing move_right, expected 'Idle'" % player.CurrentStateName)
	print("props_interact: freed panel released the hero (state '%s' after %d frames, moved %.1f px)" % [player.CurrentStateName, FREE_IDLE_CAP, player.position.x - freed_x])

	#    S1 — Cancel() from "the level" mid-sequence: no Finished, the hero is back in Idle within
	#    CANCEL_IDLE_CAP frames, the panel is dead again and retry-able, prompt "E: Repair".
	var panel5: Node = panel_scene.instantiate()
	panel5.position = PANEL2_POS
	root.add_child(panel5)
	var finished5: Array = []
	var failed5: Array = []
	panel5.Finished.connect(func(ok: bool): finished5.append(ok))
	panel5.SequenceFailed.connect(func(): failed5.append(true))
	player.position = PANEL2_POS + REACH
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == panel5, "cancelled panel: CurrentInteractable=%s, expected the fresh panel" % player.CurrentInteractable)
	_transitions.clear()
	await _tap("interact")
	await _step(1)
	_check(player.CurrentStateName == "Interact", "cancelled panel: state '%s' after interact, expected 'Interact'" % player.CurrentStateName)
	await _step(2)
	await _tap("move_up")
	await _step(1)
	_check(panel5.CurrentStep == 1 and panel5.IsActive == true, "cancelled panel: CurrentStep=%d IsActive=%s after move_up, expected 1 / true" % [panel5.CurrentStep, panel5.IsActive])
	panel5.Cancel()
	_check(panel5.IsActive == false, "cancelled panel: IsActive=%s right after Cancel(), expected false" % panel5.IsActive)
	var cancel_idle: int = await _wait_until(func(): return player.CurrentStateName == "Idle", CANCEL_IDLE_CAP)
	_check(cancel_idle >= 0, "cancelled panel: state '%s' %d frames after Cancel(), expected 'Idle' (S1: Interact must leave when the prop went inactive)" % [player.CurrentStateName, CANCEL_IDLE_CAP])
	_check(_transitions == ["Interact", "Idle"], "cancelled panel: transitions %s, expected [Interact, Idle]" % [_transitions])
	_check(finished5.is_empty(), "cancelled panel: Finished %s after Cancel(), expected none (Cancel emits no Finished)" % [finished5])
	_check(failed5.is_empty(), "cancelled panel: SequenceFailed fired on Cancel()")
	_check(panel5.CurrentStep == 0 and panel5.IsActivated == false and panel5.CanInteract == true, "cancelled panel: CurrentStep=%d IsActivated=%s CanInteract=%s after Cancel(), expected 0 / false / true" % [panel5.CurrentStep, panel5.IsActivated, panel5.CanInteract])
	_check(panel5.Screen.color.is_equal_approx(panel5.DeadColor), "cancelled panel: screen colour %s after Cancel(), expected DeadColor" % panel5.Screen.color)
	_check(hud.PromptText == "E: Repair", "cancelled panel: prompt '%s' after Cancel(), expected 'E: Repair'" % hud.PromptText)
	print("props_interact: level Cancel() released the hero after %d frames" % cancel_idle)
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	panel5.queue_free()
	await _step(1)

	# 10. S2 — free outlet (Uses=-1, Cooldown=0): after a use the prop is ready at once and the HUD
	#     prompt keeps its key hint "E: Charge" (PromptChanged must be emitted after Finish).
	var outlet3: Node = outlet_scene.instantiate()
	outlet3.Uses = -1
	outlet3.Cooldown = 0.0
	outlet3.position = OUTLET2_POS
	root.add_child(outlet3)
	var charged3: Array = []
	outlet3.Charged.connect(func(a: float): charged3.append(a))
	player.position = OUTLET2_POS + REACH
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == outlet3, "free outlet: CurrentInteractable=%s, expected the fresh outlet" % player.CurrentInteractable)
	_check(hud.PromptText == "E: Charge", "free outlet: prompt '%s' before the use, expected 'E: Charge'" % hud.PromptText)
	gs.Energy = 40.0
	_transitions.clear()
	await _tap("interact")
	var free_frames: int = await _wait_until(func(): return "Interact" in _transitions and player.CurrentStateName == "Idle", INTERACT_CAP)
	_check(free_frames >= 0, "free outlet: state '%s' with transitions %s after interact, expected Interact -> Idle" % [player.CurrentStateName, _transitions])
	_check(is_equal_approx(gs.Energy, 65.0), "free outlet: Energy=%s after interact at 40, expected 65" % gs.Energy)
	_check(charged3 == [25.0], "free outlet: Charged events %s, expected [25.0]" % [charged3])
	_check(outlet3.IsSpent == false and outlet3.IsCoolingDown == false and outlet3.CanInteract == true, "free outlet: IsSpent=%s IsCoolingDown=%s CanInteract=%s after the use, expected false / false / true" % [outlet3.IsSpent, outlet3.IsCoolingDown, outlet3.CanInteract])
	_check(hud.PromptText == "E: Charge", "free outlet: prompt '%s' after the use, expected 'E: Charge' (S2: the prefix must survive a use with no cooldown)" % hud.PromptText)
	_check(outlet3.Indicator.color.is_equal_approx(outlet3.ReadyColor), "free outlet: indicator colour %s after the use, expected ReadyColor" % outlet3.Indicator.color)
	_transitions.clear()
	await _tap("interact")
	await _step(INTERACT_CAP)
	_check(_transitions == ["Interact", "Idle"], "free outlet: transitions %s on the second use, expected [Interact, Idle]" % [_transitions])
	_check(is_equal_approx(gs.Energy, 90.0), "free outlet: Energy=%s after the second use, expected 90" % gs.Energy)
	_check(charged3 == [25.0, 25.0], "free outlet: Charged events %s after two uses, expected [25.0, 25.0]" % [charged3])
	_check(hud.PromptText == "E: Charge", "free outlet: prompt '%s' after the second use, expected 'E: Charge'" % hud.PromptText)
	print("props_interact: free outlet prompt after a use '%s', Energy %s" % [hud.PromptText, gs.Energy])
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	outlet3.queue_free()
	await _step(1)

	# 11. S4 — two props in reach: outlet at BAND_OUTLET_POS and panel 60 px to the right. The hero
	#     enters from the left (outlet only), walks right; the pick and the prompt must switch to
	#     the panel as soon as it is nearer (x > 1530) while the outlet is still in reach
	#     (x <= 1540, band ends at ~1573); a teleport inside the band (no enter/exit) re-picks too.
	var outlet4: Node = outlet_scene.instantiate()
	outlet4.position = BAND_OUTLET_POS
	root.add_child(outlet4)
	var panel6: Node = panel_scene.instantiate()
	panel6.position = BAND_PANEL_POS
	root.add_child(panel6)
	gs.ResetRun()
	changes.clear()
	player.position = BAND_START_POS
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == outlet4, "band: CurrentInteractable=%s at x=%s, expected the outlet (only prop in reach)" % [player.CurrentInteractable, BAND_START_POS.x])
	_check(hud.PromptText == "E: Charge", "band: prompt '%s' at x=%s, expected 'E: Charge'" % [hud.PromptText, BAND_START_POS.x])
	_check(changes == [outlet4], "band: InteractableChanged events %s on entering, expected [outlet]" % [changes])
	var switch_x: float = -1.0
	Input.action_press("move_right")
	for i in BAND_WALK_CAP:
		await physics_frame
		if player.CurrentInteractable == panel6:
			switch_x = player.position.x
			break
		if player.position.x > BAND_SWITCH_MAX_X:
			break
	var switch_prompt: String = hud.PromptText
	Input.action_release("move_right")
	_check(switch_x >= 0.0, "band: CurrentInteractable=%s at x=%.1f, expected the panel once past x=%s (S4: re-pick while both props are in reach)" % [player.CurrentInteractable, player.position.x, BAND_SWITCH_X])
	_check(switch_x < 0.0 or (switch_x > BAND_SWITCH_X and switch_x <= BAND_SWITCH_MAX_X), "band: pick switched to the panel at x=%.1f, expected in (%s, %s] — both props still in reach" % [switch_x, BAND_SWITCH_X, BAND_SWITCH_MAX_X])
	_check(switch_prompt == "E: Repair", "band: prompt '%s' at the switch, expected 'E: Repair'" % switch_prompt)
	_check(changes == [outlet4, panel6], "band: InteractableChanged events %s after the walk, expected [outlet, panel]" % [changes])
	var band_idle: int = await _wait_until(func(): return player.CurrentStateName == "Idle", IDLE_CAP)
	_check(band_idle >= 0, "band: state '%s' after releasing move_right, expected 'Idle'" % player.CurrentStateName)
	_check(player.CurrentInteractable == panel6, "band: CurrentInteractable=%s after stopping at x=%.1f, expected still the panel" % [player.CurrentInteractable, player.position.x])
	player.position = BAND_REPICK_POS
	await _step(2)
	_check(player.CurrentInteractable == outlet4, "band: CurrentInteractable=%s after a teleport to x=%s inside the band, expected the outlet (re-pick without an enter/exit event)" % [player.CurrentInteractable, BAND_REPICK_POS.x])
	_check(hud.PromptText == "E: Charge", "band: prompt '%s' after the teleport back, expected 'E: Charge'" % hud.PromptText)
	_check(changes == [outlet4, panel6, outlet4], "band: InteractableChanged events %s after the teleport back, expected [outlet, panel, outlet]" % [changes])
	print("props_interact: band pick switched to the panel at x=%.1f (midpoint %s), prompt '%s'" % [switch_x, BAND_SWITCH_X, switch_prompt])
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == null, "band: CurrentInteractable=%s after leaving, expected null" % player.CurrentInteractable)
	outlet4.queue_free()
	panel6.queue_free()
	await _step(1)

	# 12. S3 — a Sequence action the panel never polls (`interact`): _Ready pushes a WARNING (not
	#     fatal for the runner) and the step can never be answered: tapping `interact` does not
	#     advance (CurrentStep stays 1, no SequenceFailed either) and the attempt ends by StepTimeout.
	var panel7: Node = panel_scene.instantiate()
	panel7.Sequence = PackedStringArray(UNTRACKED_SEQUENCE)
	panel7.StepTimeout = UNTRACKED_STEP_TIMEOUT
	panel7.position = PANEL2_POS
	root.add_child(panel7)   # _Ready warns here: "Sequence action 'interact' is not polled by the panel" — expected
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
	player.position = PANEL2_POS + REACH
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
	_check(panel7.CurrentStep == 1, "untracked: CurrentStep=%d after tapping `interact`, expected still 1 (S3: the panel does not poll `interact`)" % panel7.CurrentStep)
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
	print("props_interact: untracked sequence %s timed out %d frames after the last press (StepTimeout %s s = %d frames)" % [UNTRACKED_SEQUENCE, untracked_failed_at, panel7.StepTimeout, untracked_timeout_frames])
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	panel7.queue_free()
	await _step(1)

	# 13. Teardown: hero away from the standalone panel, free it, reset the run, free the room.
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == null, "teardown: CurrentInteractable=%s, expected null" % player.CurrentInteractable)
	panel3.queue_free()
	_release_all()
	gs.ResetRun()
	room.queue_free()
	await _step(1)
	print("props_interact: idle frames used %d of MAX_FRAMES %d" % [_frames, MAX_FRAMES])
	_finish()
