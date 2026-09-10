extends SceneTree
# Smoke: project skeleton (T-01) — InputMap actions, GameState autoload, Main.tscn; plus the
# project settings T-07i-a added: the pause / toggle_fullscreen actions, the GameSettings
# autoload, MainMenu as run/main_scene and the fullscreen window mode.
# Run: godot --headless --path . -s tests/smoke/core_gamestate.gd

const NAME := "core_gamestate"
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump",
	"attack", "heavy_attack", "special", "interact", "flashlight"]
# T-07i-a: the shell actions. toggle_fullscreen is keyboard-only by design (F11 + Alt+Enter),
# which still satisfies the ">= 2 events" rule.
const NEW_ACTIONS := ["pause", "toggle_fullscreen"]
const MAIN_MENU_PATH := "res://scenes/ui/MainMenu.tscn"
const WINDOW_MODE_FULLSCREEN := 3   # DisplayServer.WINDOW_MODE_FULLSCREEN

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

	for a in NEW_ACTIONS:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)
		if InputMap.has_action(a):
			_check(InputMap.action_get_events(a).size() >= 2,
				"action '%s' has %d events, expected >= 2" % [a, InputMap.action_get_events(a).size()])

	_check(root.get_node_or_null("GameSettings") != null, "GameSettings autoload not in tree")
	_check(root.get_node_or_null("HitStop") != null, "HitStop autoload not in tree")
	_check(ProjectSettings.get_setting("application/run/main_scene") == MAIN_MENU_PATH,
		"run/main_scene='%s', expected '%s'" % [ProjectSettings.get_setting("application/run/main_scene"), MAIN_MENU_PATH])
	_check(ProjectSettings.get_setting("display/window/size/mode") == WINDOW_MODE_FULLSCREEN,
		"display/window/size/mode=%s, expected %d (the game starts fullscreen)" % [ProjectSettings.get_setting("display/window/size/mode"), WINDOW_MODE_FULLSCREEN])

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
	var menu = load(MAIN_MENU_PATH)
	_check(menu != null, "%s failed to load" % MAIN_MENU_PATH)

	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)
	return true
