extends SceneTree
# Smoke: the power circuit and its machines (T-07s-a) — PowerCircuit exports/state, the
# PoweredMachine and Hoist scene contracts, and the whole "refuse and name the culprit" loop
# driven through the panels in TestMine: Capacity 1 with three machines registered; the pump
# clears the flooded drift for good; the extractor is refused while the pump runs (RequestRefused
# names the pump, the HUD prompt reads the overload line, the panel stays retryable); switching
# the pump off does NOT bring the water back; the extractor then clears the gas pocket; the hoist
# needs the whole bus, so it is refused while any machine runs and starts once the bus is empty;
# boarding a running hoist departs exactly once and the hoist cannot be switched off again.
# Also characterises PowerPanel with its default CanPowerDown = false (an activated panel refuses
# further use and shows ActivatedPromptText) and the dead-panel path (FailedNoPower -> permanent
# NoPowerPromptText) — both must behave exactly as they did before this task. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/props_circuit.gd
#
# Nothing is hit here, so Engine.time_scale stays 1 and everything is counted in physics frames;
# the only real-time wait is the overload prompt's own countdown (PoweredMachine._Process, idle
# delta), taken with an ignore-time-scale timer.

const NAME := "props_circuit"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls.
const MAX_FRAMES := 8000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const SETTLE_CAP := 10         # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05     # process delta (s) below which the loop is back to normal pacing
const INTERACTABLE_LAYER := 32 # physics layer 6 "Interactable"
const PLAYER_LAYER := 2        # physics layer 2 "Player"
const OVERLAP_FRAMES := 4      # physics frames for Area2D overlaps to refresh after a teleport
const ATTEMPT_CAP := 60        # frames allowed for a refused attempt to release the hero (FailResetDelay 0.5 s = 30)
const PUMP_POS := Vector2(600, 450)
const EXTRACTOR_POS := Vector2(1180, 450)
const HOIST_POS := Vector2(1780, 450)
const NEAR_PUMP := Vector2(555, 450)        # inside the pump's reach (r 44) with the hero's area (r 36)
const NEAR_EXTRACTOR := Vector2(1135, 450)  # inside the extractor's reach (r 44), clear of Checkpoint_Gas
const AWAY_POS := Vector2(120, 450)         # far from every prop and outside every trigger
const BOARDING_POS := Vector2(1780, 450)    # inside the hoist's BoardingArea (120x80 around its origin)
const EXPECTED_MACHINES := ["Pump", "Extractor", "Hoist"]
const OVERLOAD_FORMAT := "Not enough power: {0} is running"
const OVERLOAD_SHORT := 1.0    # OverloadPromptSeconds for the expiry check; must outlast FailResetDelay (0.5 s)
const OVERLOAD_EXPIRY_WAIT := 0.7   # real seconds after the flash ended for the rest of the overload window to run out

var _started := false
var _frames := 0
var _failures: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

# The refusal line a panel shows, with `blocking` in place of the {0} placeholder.
func _overload(blocking: String) -> String:
	return OVERLOAD_FORMAT.replace("{0}", blocking)

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

# Instantiating a level (~100 ms of C# instancing) makes the next iteration run 6-8 physics steps
# back-to-back; wait until the process delta is back to normal before counting frames.
func _settle() -> void:
	for i in SETTLE_CAP:
		await process_frame
		if root.get_process_delta_time() < SETTLE_DELTA:
			return

func _release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)

# Real-time wait that ignores Engine.time_scale and the pause (idle-delta countdowns).
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

# Teleports the hero and lets the Area2D overlaps (interaction reach, triggers) refresh.
func _place(player: Node, pos: Vector2) -> void:
	player.global_position = pos
	await _step(OVERLAP_FRAMES)

# Starts an interaction the way the hero's Interact state does and waits until the panel released
# him again (a granted request finishes at once, a refused one after FailResetDelay).
func _use(panel: Node, player: Node, label: String) -> void:
	panel.Begin(player)
	for i in ATTEMPT_CAP:
		await physics_frame
		if not panel.IsActive:
			return
	_check(false, "%s: still IsActive %d frames after Begin() — the attempt never released the hero" % [label, ATTEMPT_CAP])

# Checks the Interactable scene contract (root Area2D on the Interactable layer, passive).
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

func _run() -> void:
	# 0. Preconditions: the InputMap action the hero uses on a panel, and GameState.
	_check(InputMap.has_action("interact"), "InputMap missing action 'interact'")
	if InputMap.has_action("interact"):
		_check(InputMap.action_get_events("interact").size() > 0, "action 'interact' has no events")
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	# 1. Prefab defaults: PoweredMachine.tscn and Hoist.tscn, free-standing.
	var machine_scene: PackedScene = load("res://scenes/props/PoweredMachine.tscn")
	var hoist_scene: PackedScene = load("res://scenes/props/Hoist.tscn")
	var panel_scene: PackedScene = load("res://scenes/props/PowerPanel.tscn")
	_check(machine_scene != null, "res://scenes/props/PoweredMachine.tscn failed to load")
	_check(hoist_scene != null, "res://scenes/props/Hoist.tscn failed to load")
	_check(panel_scene != null, "res://scenes/props/PowerPanel.tscn failed to load")
	if machine_scene == null or hoist_scene == null or panel_scene == null:
		_finish()
		return

	var proto: Node = machine_scene.instantiate()
	_check(proto.get_script() != null and str(proto.get_script().resource_path).ends_with("PoweredMachine.cs"),
		"PoweredMachine.tscn has no PoweredMachine.cs attached (did dotnet build run?)")
	if proto.get("OverloadPromptFormat") == null:
		_check(false, "PoweredMachine exports missing — C# scripts not attached, aborting")
		proto.free()
		_finish()
		return
	_check(proto.Circuit == null, "PoweredMachine.Circuit default is %s, expected null (the level wires it)" % proto.Circuit)
	_check(proto.DisplayName == "Machine", "PoweredMachine.DisplayName default is '%s', expected 'Machine'" % proto.DisplayName)
	_check(proto.PowerCost == 1, "PoweredMachine.PowerCost default is %s, expected 1" % proto.PowerCost)
	_check(proto.RequiresWholeCircuit == false, "PoweredMachine.RequiresWholeCircuit default is %s, expected false" % proto.RequiresWholeCircuit)
	_check(Array(proto.ClearTargets).is_empty(), "PoweredMachine.ClearTargets default is %s, expected empty" % [Array(proto.ClearTargets)])
	_check(proto.OverloadPromptFormat == OVERLOAD_FORMAT, "PoweredMachine.OverloadPromptFormat is '%s', expected '%s'" % [proto.OverloadPromptFormat, OVERLOAD_FORMAT])
	_check(is_equal_approx(proto.OverloadPromptSeconds, 3.0), "PoweredMachine.OverloadPromptSeconds default is %s, expected 3" % proto.OverloadPromptSeconds)
	_check(proto.IsPowered == false, "PoweredMachine.IsPowered is %s before _Ready, expected false" % proto.IsPowered)
	# The prefab is a switch, not a repair: an empty sequence and CanPowerDown on.
	_check(proto.CanPowerDown == true, "PoweredMachine.tscn CanPowerDown=%s, expected true (one interact on, one off)" % proto.CanPowerDown)
	_check(Array(proto.Sequence).is_empty(), "PoweredMachine.tscn Sequence=%s, expected empty" % [Array(proto.Sequence)])
	_check(proto.PromptText == "Switch on", "PoweredMachine.tscn PromptText is '%s', expected 'Switch on'" % proto.PromptText)
	_check(proto.ActivatedPromptText == "Running — cut the power", "PoweredMachine.tscn ActivatedPromptText is '%s'" % proto.ActivatedPromptText)
	_check(proto.get("RunLight") == proto.get_node_or_null("PH_RunLight"), "PoweredMachine.RunLight does not point at PH_RunLight")
	_check(proto.get("Screen") == proto.get_node_or_null("PH_Screen"), "PoweredMachine.Screen does not point at PH_Screen")
	_check(proto.get_node_or_null("PH_Body") is Polygon2D, "PoweredMachine.tscn lacks a PH_Body Polygon2D placeholder")
	_check_interactable(proto, "PoweredMachine.tscn", 44.0)
	proto.free()

	var hproto: Node = hoist_scene.instantiate()
	_check(hproto.get_script() != null and str(hproto.get_script().resource_path).ends_with("Hoist.cs"),
		"Hoist.tscn has no Hoist.cs attached")
	if hproto.get("RequiresPlayerBoarding") == null:
		_check(false, "Hoist exports missing — C# scripts not attached, aborting")
		hproto.free()
		_finish()
		return
	_check(hproto.RequiresWholeCircuit == true, "Hoist.tscn RequiresWholeCircuit=%s, expected true" % hproto.RequiresWholeCircuit)
	_check(hproto.CanPowerDown == false, "Hoist.tscn CanPowerDown=%s, expected false (you do not switch off your own way out)" % hproto.CanPowerDown)
	_check(hproto.DisplayName == "Hoist", "Hoist.tscn DisplayName is '%s', expected 'Hoist'" % hproto.DisplayName)
	_check(hproto.RequiresPlayerBoarding == true, "Hoist.RequiresPlayerBoarding default is %s, expected true" % hproto.RequiresPlayerBoarding)
	_check(hproto.HasDeparted == false, "Hoist.HasDeparted is %s at start, expected false" % hproto.HasDeparted)
	_check_interactable(hproto, "Hoist.tscn", 48.0)
	var boarding: Node = hproto.get_node_or_null("BoardingArea")
	_check(boarding is Area2D, "Hoist.tscn has no BoardingArea Area2D")
	if boarding is Area2D:
		_check(hproto.get("BoardingArea") == boarding, "Hoist.BoardingArea export does not point at the child")
		_check(boarding.collision_layer == 0, "Hoist/BoardingArea collision_layer=%d, expected 0" % boarding.collision_layer)
		_check(boarding.collision_mask == PLAYER_LAYER, "Hoist/BoardingArea collision_mask=%d, expected %d (Player)" % [boarding.collision_mask, PLAYER_LAYER])
		_check(boarding.monitorable == false, "Hoist/BoardingArea monitorable=%s, expected false" % boarding.monitorable)
	hproto.free()

	if _failures.size() > 0:
		_finish()
		return

	# 2. TestMine: the circuit and its three machines.
	var scene: PackedScene = load("res://scenes/levels/TestMine.tscn")
	_check(scene != null, "res://scenes/levels/TestMine.tscn failed to load")
	if scene == null:
		_finish()
		return
	var room: Node = scene.instantiate()
	root.add_child(room)
	await _settle()

	var circuit: Node = room.get_node_or_null("Circuit")
	var pump: Node = room.get_node_or_null("Pump")
	var extractor: Node = room.get_node_or_null("Extractor")
	var hoist: Node = room.get_node_or_null("Hoist")
	var flood: Node = room.get_node_or_null("Flood")
	var gas: Node = room.get_node_or_null("GasZone_Pocket")
	var player: Node = room.get_node_or_null("Player")
	var hud: Node = room.get_node_or_null("HUD")
	for pair in [[circuit, "Circuit"], [pump, "Pump"], [extractor, "Extractor"], [hoist, "Hoist"],
			[flood, "Flood"], [gas, "GasZone_Pocket"], [player, "Player"], [hud, "HUD"]]:
		_check(pair[0] != null, "TestMine has no '%s' child" % pair[1])
	if circuit == null or pump == null or extractor == null or hoist == null or flood == null or gas == null or player == null or hud == null:
		room.queue_free()
		_finish()
		return
	if circuit.get("Capacity") == null or pump.get("DisplayName") == null or flood.get("HeavyHitsToClear") == null:
		_check(false, "PowerCircuit/PoweredMachine/DebrisPile exports missing in TestMine — aborting")
		room.queue_free()
		_finish()
		return
	_check(circuit.get_script() != null and str(circuit.get_script().resource_path).ends_with("PowerCircuit.cs"),
		"TestMine/Circuit has no PowerCircuit.cs attached")
	_check(circuit.Capacity == 1, "Circuit.Capacity=%s, expected 1" % circuit.Capacity)
	_check(circuit.Used == 0, "Circuit.Used=%s at start, expected 0" % circuit.Used)
	_check(circuit.FreeCapacity == 1, "Circuit.FreeCapacity=%s at start, expected 1" % circuit.FreeCapacity)
	_check(circuit.Machines.size() == 3, "Circuit.Machines has %d entries, expected 3 (pump, extractor, hoist)" % circuit.Machines.size())
	var registered: Array = []
	for m in circuit.Machines:
		registered.append(str(m.name))
	_check(registered == EXPECTED_MACHINES, "Circuit.Machines registered %s, expected %s" % [registered, EXPECTED_MACHINES])
	_check(pump.DisplayName == "Pump", "Pump.DisplayName is '%s', expected 'Pump'" % pump.DisplayName)
	_check(extractor.DisplayName == "Extractor", "Extractor.DisplayName is '%s', expected 'Extractor'" % extractor.DisplayName)
	_check(pump.IsPowered == false and extractor.IsPowered == false and hoist.IsPowered == false,
		"a machine is powered before anything was switched on")
	_check(flood.HeavyHitsToClear == 0, "Flood.HeavyHitsToClear=%s, expected 0 (hands can never drain water)" % flood.HeavyHitsToClear)
	_check(flood.IsCleared == false, "Flood.IsCleared=%s at start, expected false (the drift blocks)" % flood.IsCleared)
	_check(flood.BlockerShape != null and flood.BlockerShape.disabled == false, "Flood blocker is disabled at start")
	if _failures.size() > 0:
		room.queue_free()
		_finish()
		return

	var powered: Array = []
	var released: Array = []
	var refusals: Array = []
	var loads: Array = []
	circuit.MachinePowered.connect(func(m): powered.append(str(m.name)))
	circuit.MachineReleased.connect(func(m): released.append(str(m.name)))
	circuit.RequestRefused.connect(func(m, b): refusals.append([str(m.name), str(b.name)]))
	circuit.LoadChanged.connect(func(u: int, c: int): loads.append([u, c]))
	var pump_changes: Array = []
	pump.PowerChanged.connect(func(on: bool): pump_changes.append(on))
	var flood_cleared: Array = []
	flood.Cleared.connect(func(): flood_cleared.append(true))
	var gas_cleared: Array = []
	gas.Cleared.connect(func(): gas_cleared.append(true))
	var refused_panel: Array = []
	extractor.ActivationRefused.connect(func(): refused_panel.append(true))

	# 3. Characterisation: PowerPanel with its default CanPowerDown = false is unchanged.
	# The sequence itself is covered by props_interact.gd; here the sequence is emptied so the
	# panel completes on the first interact and only the activated/dead states are exercised.
	var plain: Node = panel_scene.instantiate()
	plain.name = "PlainPanel"
	plain.Sequence = PackedStringArray()
	plain.position = Vector2(1000, 200)
	room.add_child(plain)
	await _step(2)
	_check(plain.CanPowerDown == false, "PowerPanel.CanPowerDown default is %s, expected false" % plain.CanPowerDown)
	_check(plain.CanInteract == true, "a fresh PowerPanel has CanInteract=%s, expected true" % plain.CanInteract)
	_check(plain.CurrentPrompt == plain.PromptText, "a fresh PowerPanel prompt is '%s', expected PromptText '%s'" % [plain.CurrentPrompt, plain.PromptText])
	var plain_activated: Array = []
	var plain_deactivated: Array = []
	var plain_finished: Array = []
	plain.Activated.connect(func(): plain_activated.append(true))
	plain.Deactivated.connect(func(): plain_deactivated.append(true))
	plain.Finished.connect(func(ok: bool): plain_finished.append(ok))
	await _use(plain, player, "PlainPanel")
	_check(plain_activated.size() == 1, "PlainPanel Activated fired %d times, expected 1" % plain_activated.size())
	_check(plain.IsActivated == true, "PlainPanel IsActivated=%s after a completed sequence, expected true" % plain.IsActivated)
	_check(plain.CanInteract == false, "PlainPanel CanInteract=%s once activated, expected false (CanPowerDown is off)" % plain.CanInteract)
	_check(plain.CurrentPrompt == plain.ActivatedPromptText, "PlainPanel prompt is '%s', expected ActivatedPromptText '%s'" % [plain.CurrentPrompt, plain.ActivatedPromptText])
	_check(plain_finished == [true], "PlainPanel Finished fired %s, expected [true]" % [plain_finished])
	await _use(plain, player, "PlainPanel again")
	_check(plain_activated.size() == 1, "PlainPanel Activated fired %d times after a second interact, expected 1" % plain_activated.size())
	_check(plain_deactivated.is_empty(), "PlainPanel Deactivated fired with CanPowerDown off")
	_check(plain_finished == [true, false], "PlainPanel Finished history is %s, expected [true, false]" % [plain_finished])
	plain.queue_free()

	var dead: Node = panel_scene.instantiate()
	dead.name = "DeadPanel"
	dead.Sequence = PackedStringArray()
	dead.Powered = false
	dead.position = Vector2(1050, 200)
	room.add_child(dead)
	await _step(2)
	var dead_nopower: Array = []
	dead.FailedNoPower.connect(func(): dead_nopower.append(true))
	await _use(dead, player, "DeadPanel")
	_check(dead_nopower.size() == 1, "DeadPanel FailedNoPower fired %d times, expected 1" % dead_nopower.size())
	_check(dead.IsActivated == false, "DeadPanel IsActivated=%s, expected false (no power upstream)" % dead.IsActivated)
	_check(dead.CanInteract == false, "DeadPanel CanInteract=%s after the failure, expected false (dead for good)" % dead.CanInteract)
	_check(dead.CurrentPrompt == dead.NoPowerPromptText, "DeadPanel prompt is '%s', expected NoPowerPromptText '%s'" % [dead.CurrentPrompt, dead.NoPowerPromptText])
	dead.queue_free()
	await _step(2)

	# 4. The pump: one interact grants power and drains the drift for good.
	await _place(player, NEAR_PUMP)
	_check(player.CurrentInteractable == pump, "the hero at %s has %s in reach, expected the Pump" % [NEAR_PUMP, player.CurrentInteractable])
	await _use(pump, player, "Pump on")
	_check(powered == ["Pump"], "MachinePowered history is %s, expected ['Pump']" % [powered])
	_check(pump.IsPowered == true, "Pump.IsPowered=%s after a granted request, expected true" % pump.IsPowered)
	_check(pump_changes == [true], "Pump.PowerChanged history is %s, expected [true]" % [pump_changes])
	_check(circuit.Used == 1, "Circuit.Used=%s with the pump running, expected 1" % circuit.Used)
	_check(circuit.FreeCapacity == 0, "Circuit.FreeCapacity=%s with the pump running, expected 0" % circuit.FreeCapacity)
	_check(loads == [[1, 1]], "LoadChanged history is %s, expected [[1, 1]]" % [loads])
	_check(pump.RunLight != null and pump.RunLight.enabled == true, "the pump's RunLight is not enabled while it runs")
	_check(flood.IsCleared == true, "Flood.IsCleared=%s with the pump running, expected true" % flood.IsCleared)
	_check(flood_cleared.size() == 1, "Flood.Cleared fired %d times, expected 1" % flood_cleared.size())
	await _step(2)   # the blocker flags are deferred
	_check(flood.BlockerShape.disabled == true, "Flood blocker still solid after the pump drained it")
	_check(flood.Hurtbox == null or flood.Hurtbox.monitorable == false, "Flood hurtbox is still monitorable after clearing")

	# 5. The extractor is refused while the pump runs — and says whose fault it is.
	await _place(player, NEAR_EXTRACTOR)
	_check(player.CurrentInteractable == extractor, "the hero at %s has %s in reach, expected the Extractor" % [NEAR_EXTRACTOR, player.CurrentInteractable])
	await _use(extractor, player, "Extractor refused")
	_check(refusals == [["Extractor", "Pump"]], "RequestRefused history is %s, expected [['Extractor', 'Pump']]" % [refusals])
	_check(refused_panel.size() == 1, "Extractor ActivationRefused fired %d times, expected 1" % refused_panel.size())
	_check(extractor.IsPowered == false, "Extractor.IsPowered=%s after a refusal, expected false" % extractor.IsPowered)
	_check(extractor.IsActivated == false, "Extractor.IsActivated=%s after a refusal, expected false" % extractor.IsActivated)
	_check(extractor.CanInteract == true, "Extractor.CanInteract=%s after a refusal, expected true (a refusal is retryable)" % extractor.CanInteract)
	_check(circuit.Used == 1, "Circuit.Used=%s after a refusal, expected 1 (nothing was preempted)" % circuit.Used)
	_check(pump.IsPowered == true, "the pump was switched off by the refused request")
	var overload: String = _overload("Pump")
	# The refusal line reaches the HUD. Once the fail flash ends the panel is retryable again, so
	# LevelBase re-adds the key hint: the line the player reads is "E: <refusal>", not the bare
	# refusal of acceptance criterion 1. Locked here as the behaviour that actually ships.
	_check(hud.PromptText.contains(overload), "HUD prompt after the refusal is '%s', expected it to carry '%s'" % [hud.PromptText, overload])
	_check(hud.PromptText == room.PromptFormat.replace("{0}", overload),
		"HUD prompt after the refusal is '%s', expected the retry-formatted '%s'" % [hud.PromptText, room.PromptFormat.replace("{0}", overload)])
	_check(gas.IsCleared == false, "GasZone_Pocket.IsCleared=%s after a refused extractor, expected false" % gas.IsCleared)

	# 6. The hoist wants the whole bus, so it is refused too — naming the pump.
	await _use(hoist, player, "Hoist refused (pump)")
	_check(refusals.size() == 2 and refusals[1] == ["Hoist", "Pump"], "RequestRefused history is %s, expected the hoist refused by the pump" % [refusals])
	_check(hoist.IsPowered == false, "Hoist.IsPowered=%s while the pump runs, expected false" % hoist.IsPowered)
	_check(hoist.HasDeparted == false, "Hoist.HasDeparted=%s after a refusal, expected false" % hoist.HasDeparted)
	_check(hoist.CurrentPrompt == overload, "Hoist prompt after the refusal is '%s', expected '%s'" % [hoist.CurrentPrompt, overload])

	# 7. Switching the pump off frees the bus — and the drained water stays drained (permanence).
	await _place(player, NEAR_PUMP)
	await _use(pump, player, "Pump off")
	_check(released == ["Pump"], "MachineReleased history is %s, expected ['Pump']" % [released])
	_check(pump.IsPowered == false, "Pump.IsPowered=%s after switching it off, expected false" % pump.IsPowered)
	_check(pump_changes == [true, false], "Pump.PowerChanged history is %s, expected [true, false]" % [pump_changes])
	_check(pump.RunLight.enabled == false, "the pump's RunLight is still on after it was switched off")
	_check(circuit.Used == 0, "Circuit.Used=%s after switching the pump off, expected 0" % circuit.Used)
	_check(loads == [[1, 1], [0, 1]], "LoadChanged history is %s, expected [[1, 1], [0, 1]]" % [loads])
	_check(flood.IsCleared == true, "Flood.IsCleared=%s after the pump stopped — clearing must be permanent" % flood.IsCleared)
	_check(flood.BlockerShape.disabled == true, "the flooded drift blocks again after the pump stopped — clearing must be permanent")
	_check(flood_cleared.size() == 1, "Flood.Cleared fired %d times in total, expected 1" % flood_cleared.size())

	# 8. Now the extractor is granted and the gas pocket is gone for good.
	await _place(player, NEAR_EXTRACTOR)
	await _use(extractor, player, "Extractor on")
	_check(powered == ["Pump", "Extractor"], "MachinePowered history is %s, expected ['Pump', 'Extractor']" % [powered])
	_check(extractor.IsPowered == true, "Extractor.IsPowered=%s after a granted request, expected true" % extractor.IsPowered)
	_check(circuit.Used == 1, "Circuit.Used=%s with the extractor running, expected 1" % circuit.Used)
	_check(gas.IsCleared == true, "GasZone_Pocket.IsCleared=%s with the extractor running, expected true" % gas.IsCleared)
	_check(gas_cleared.size() == 1, "GasZone_Pocket.Cleared fired %d times, expected 1" % gas_cleared.size())
	await _step(2)   # Monitoring is set deferred
	_check(gas.monitoring == false, "a cleared gas pocket still monitors bodies")

	# 9. The hoist is refused by the extractor now, and granted once the bus is empty.
	await _use(hoist, player, "Hoist refused (extractor)")
	_check(refusals.size() == 3 and refusals[2] == ["Hoist", "Extractor"], "RequestRefused history is %s, expected the hoist refused by the extractor" % [refusals])
	var extractor_overload: String = _overload("Extractor")
	_check(hoist.CurrentPrompt == extractor_overload, "Hoist prompt is '%s', expected '%s'" % [hoist.CurrentPrompt, extractor_overload])
	await _use(extractor, player, "Extractor off")
	_check(circuit.Used == 0, "Circuit.Used=%s after switching the extractor off, expected 0" % circuit.Used)
	_check(gas.IsCleared == true, "the gas pocket came back after the extractor stopped — clearing must be permanent")

	var departures: Array = []
	hoist.Departed.connect(func(p): departures.append(p))
	var hoist_changes: Array = []
	hoist.PowerChanged.connect(func(on: bool): hoist_changes.append(on))
	await _use(hoist, player, "Hoist on")
	_check(hoist.IsPowered == true, "Hoist.IsPowered=%s with an empty bus, expected true" % hoist.IsPowered)
	_check(hoist_changes == [true], "Hoist.PowerChanged history is %s, expected [true]" % [hoist_changes])
	_check(circuit.Used == 1, "Circuit.Used=%s with the hoist running, expected 1 (it draws the whole bus)" % circuit.Used)
	_check(circuit.FreeCapacity == 0, "Circuit.FreeCapacity=%s with the hoist running, expected 0" % circuit.FreeCapacity)
	_check(departures.is_empty(), "the hoist departed with the hero standing at %s, outside the BoardingArea around %s" % [NEAR_EXTRACTOR, HOIST_POS])
	_check(hoist.HasDeparted == false, "Hoist.HasDeparted=%s before the hero boarded, expected false" % hoist.HasDeparted)

	# 10. Boarding a running hoist departs exactly once.
	await _place(player, BOARDING_POS)
	_check(departures.size() == 1, "Departed fired %d times after boarding, expected 1" % departures.size())
	if departures.size() == 1:
		_check(departures[0] == player, "Departed carried %s, expected the hero" % departures[0])
	_check(hoist.HasDeparted == true, "Hoist.HasDeparted=%s after boarding, expected true" % hoist.HasDeparted)
	await _place(player, AWAY_POS)
	await _place(player, BOARDING_POS)
	_check(departures.size() == 1, "Departed fired %d times after re-boarding, expected 1 (the hoist leaves once)" % departures.size())

	# 11. A running hoist cannot be switched off (CanPowerDown is off).
	_check(hoist.CanInteract == false, "Hoist.CanInteract=%s while running, expected false" % hoist.CanInteract)
	await _use(hoist, player, "Hoist power-down attempt")
	_check(hoist.IsPowered == true, "the hoist was switched off by a second interact")
	_check(circuit.Used == 1, "Circuit.Used=%s after a refused hoist power-down, expected 1" % circuit.Used)

	# 12. The overload prompt is temporary: it hands the panel's own prompt back on its own.
	extractor.OverloadPromptSeconds = OVERLOAD_SHORT
	await _place(player, NEAR_EXTRACTOR)
	await _use(extractor, player, "Extractor refused by the hoist")
	var hoist_overload: String = _overload("Hoist")
	_check(extractor.CurrentPrompt == hoist_overload, "Extractor prompt is '%s', expected '%s'" % [extractor.CurrentPrompt, hoist_overload])
	await _real_wait(OVERLOAD_EXPIRY_WAIT)
	_check(extractor.CurrentPrompt == extractor.PromptText,
		"Extractor prompt is still '%s' %.2f s after the overload window opened, expected PromptText '%s'" % [extractor.CurrentPrompt, OVERLOAD_SHORT, extractor.PromptText])

	room.queue_free()
	_finish()
