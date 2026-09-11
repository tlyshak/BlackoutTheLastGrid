extends SceneTree
# Smoke: the refusal branch of PoweredMachine.ForcePower() — the failure path of the only new
# public API T-07s-b added to a T-07s-a class, and the one the prologue's circuit hand-over relies
# on being harmless (Level00_Prologue releases the three machines behind the upper seal *before* it
# forces the floodlight on; if the release ever stopped happening, this is the branch that would
# run instead).
#
# It lives in its own file rather than in props_circuit.gd §14 because ForcePower() on a loaded bus
# ends in GD.PushWarning, and a C# warning raised under a GDScript SceneTree script can crash this
# engine build at shutdown (T-B21). The crash is not caused by the warning alone: it needs a script
# that has already instantiated and freed many scenes. This script instantiates three nodes and
# frees them at the end, which is the minimal repro the reviewer measured as stable (5 runs out of
# 5, exit 0) — so the coverage is back without re-introducing the flake into the big script.
# Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/props_forcepower.gd

const NAME := "props_forcepower"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s).
const MAX_FRAMES := 600
const CIRCUIT_SCRIPT := "res://scripts/core/PowerCircuit.cs"
const MACHINE_PATH := "res://scenes/props/PoweredMachine.tscn"

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

func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

func _run() -> void:
	var circuit_script: Script = load(CIRCUIT_SCRIPT)
	var machine_scene: PackedScene = load(MACHINE_PATH)
	_check(circuit_script != null, "%s failed to load" % CIRCUIT_SCRIPT)
	_check(machine_scene != null, "%s failed to load" % MACHINE_PATH)
	if circuit_script == null or machine_scene == null:
		_finish()
		return

	var room := Node2D.new()
	room.name = "ForcePowerRoom"
	root.add_child(room)

	# The circuit is a plain Node with a script wherever it is used (TestMine, the prologue).
	var circuit := Node.new()
	circuit.set_script(circuit_script)
	circuit.name = "Circuit"
	circuit.Capacity = 1
	room.add_child(circuit)

	# The machine that holds the single unit, and the one that will be refused it.
	var holder: Node = machine_scene.instantiate()
	holder.name = "Holder"
	holder.DisplayName = "Pump"
	holder.Circuit = circuit
	holder.StartsPowered = true
	room.add_child(holder)

	var latecomer: Node = machine_scene.instantiate()
	latecomer.name = "Latecomer"
	latecomer.DisplayName = "Floodlight"
	latecomer.Circuit = circuit
	latecomer.position = Vector2(300, 0)
	var changes: Array = []
	room.add_child(latecomer)
	latecomer.PowerChanged.connect(func(on: bool): changes.append(on))
	await _step(2)

	_check(holder.IsPowered == true, "the holder did not take the bus in its first frame (StartsPowered)")
	_check(circuit.Used == 1 and circuit.FreeCapacity == 0,
		"Circuit.Used=%s FreeCapacity=%s with the holder running, expected 1 / 0" % [circuit.Used, circuit.FreeCapacity])

	# The branch itself: a loaded bus refuses, and the refused machine is left untouched — not
	# powered, not activated, and silent (no PowerChanged for a grant that never happened).
	latecomer.ForcePower()
	await _step(2)
	_check(latecomer.IsPowered == false, "ForcePower started a machine on a bus that was already full")
	_check(latecomer.IsActivated == false, "a refused ForcePower marked the panel activated anyway")
	_check(changes.is_empty(), "a refused ForcePower emitted PowerChanged %s" % [changes])
	_check(circuit.Used == 1, "Circuit.Used=%s after a refused ForcePower, expected 1 (the holder keeps it)" % circuit.Used)
	_check(holder.IsPowered == true, "the refused ForcePower took the bus off the machine that held it")

	# And the refusal is not sticky: release the bus and the same call goes through.
	holder.PowerDown()
	await _step(2)
	_check(circuit.Used == 0, "Circuit.Used=%s after the holder released the bus, expected 0" % circuit.Used)
	latecomer.ForcePower()
	await _step(2)
	_check(latecomer.IsPowered == true, "ForcePower did not start the machine once the bus was free")
	_check(latecomer.IsActivated == true, "a machine started by ForcePower has an unactivated panel")
	_check(changes == [true], "PowerChanged history is %s after the successful ForcePower, expected [true]" % [changes])

	room.queue_free()
	await _step(2)
	_finish()
