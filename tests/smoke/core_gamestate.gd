extends SceneTree
# Smoke: project skeleton (T-01) — InputMap actions, GameState autoload, Main.tscn.
# Run: godot --headless --path . -s tests/smoke/core_gamestate.gd

const NAME := "core_gamestate"
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump",
	"attack", "heavy_attack", "special", "interact", "flashlight"]

var _done := false
var _failures: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _process(_delta: float) -> bool:
	# Autoloads are added after _init(), so all checks run on the first frame.
	if _done:
		return true
	_done = true

	for a in ACTIONS:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)
		if InputMap.has_action(a):
			_check(InputMap.action_get_events(a).size() >= 2,
				"action '%s' needs keyboard + gamepad events" % a)

	var gs = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs != null:
		var got: Array = []
		gs.EnergyChanged.connect(func(e): got.append(e))
		gs.Energy = gs.MaxEnergy + 50.0   # clamped to Max -> no change, no signal
		gs.Energy = 30.0
		gs.AddEnergy(-100.0)              # clamped to Min
		_check(got == [30.0, gs.MinEnergy], "EnergyChanged sequence %s, expected [30, %s]" % [got, gs.MinEnergy])
		_check(gs.Energy == gs.MinEnergy, "Energy not clamped to MinEnergy")
		gs.ResetRun()
		_check(gs.Energy == gs.MaxEnergy, "ResetRun did not restore MaxEnergy")
		_check(gs.Route == 0, "ResetRun did not reset Route to None")

	var main = load("res://scenes/Main.tscn")
	_check(main != null, "res://scenes/Main.tscn failed to load")

	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)
	return true
