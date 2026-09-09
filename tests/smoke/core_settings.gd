extends SceneTree
# Smoke: the GameSettings autoload (T-07i-a) — the autoload is in the tree and processes while
# paused, the project settings the feature depends on (fullscreen window mode, unchanged stretch
# mode, MainMenu as run/main_scene, both new InputMap actions), the ConfigFile round-trip on a
# throwaway path (missing file -> defaults, Save -> Load gives the values back), FullscreenChanged
# / MasterVolumeChanged emitted once per real change and never for a repeat, ToggleFullscreen, and
# the linear->dB volume mapping with mute at 0. Under --headless the window is never touched
# (DisplayServer guard): the properties still change and the runner rejects any ERROR line, so a
# stray DisplayServer call would fail this script. The player's own user://settings.cfg must come
# out untouched — the script redirects ConfigPath before anything can Save().
# Run: godot --headless --path . -s tests/smoke/core_settings.gd

const NAME := "core_settings"   # must equal the file basename
const PROBE_PATH := "user://settings_smoke.cfg"
const REAL_PATH := "user://settings.cfg"
const MAIN_SCENE := "res://scenes/ui/MainMenu.tscn"
const WINDOW_MODE_FULLSCREEN := 3   # DisplayServer.WINDOW_MODE_FULLSCREEN
const PROCESS_MODE_ALWAYS := 3      # Node.PROCESS_MODE_ALWAYS
const NEW_ACTIONS := ["pause", "toggle_fullscreen"]
const PROBE_VOLUME := 0.35
const DB_TOL := 0.01

var _done := false
var _failures: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

func _real_stamp() -> int:
	return FileAccess.get_modified_time(REAL_PATH) if FileAccess.file_exists(REAL_PATH) else -1

func _process(_delta: float) -> bool:
	# Autoloads are added after _init(), so all checks run on the first frame.
	if _done:
		return true
	_done = true
	_run()
	_finish()
	return true

func _run() -> void:
	# 1. Project settings this feature is built on (mandatory for a project.godot change).
	_check(ProjectSettings.get_setting("display/window/size/mode") == WINDOW_MODE_FULLSCREEN,
		"display/window/size/mode=%s, expected %d (fullscreen at start)" % [ProjectSettings.get_setting("display/window/size/mode"), WINDOW_MODE_FULLSCREEN])
	_check(ProjectSettings.get_setting("display/window/stretch/mode") == "canvas_items",
		"display/window/stretch/mode='%s', expected 'canvas_items' (unchanged by T-07i-a)" % ProjectSettings.get_setting("display/window/stretch/mode"))
	_check(ProjectSettings.get_setting("application/run/main_scene") == MAIN_SCENE,
		"run/main_scene='%s', expected '%s'" % [ProjectSettings.get_setting("application/run/main_scene"), MAIN_SCENE])
	for a in NEW_ACTIONS:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)
		if InputMap.has_action(a):
			_check(InputMap.action_get_events(a).size() >= 2,
				"action '%s' has %d events, expected >= 2" % [a, InputMap.action_get_events(a).size()])

	var gset: Node = root.get_node_or_null("GameSettings")
	_check(gset != null, "GameSettings autoload not in tree")
	if gset == null:
		return
	_check(gset.process_mode == PROCESS_MODE_ALWAYS,
		"GameSettings.process_mode=%d, expected %d (ALWAYS: the hotkey must work while paused)" % [gset.process_mode, PROCESS_MODE_ALWAYS])
	if gset.get("ConfigPath") == null:
		_check(false, "GameSettings has no ConfigPath export — GameSettings.cs not attached?")
		return
	_check(gset.ConfigPath == REAL_PATH, "GameSettings.ConfigPath='%s', expected '%s'" % [gset.ConfigPath, REAL_PATH])
	_check(gset.DefaultFullscreen == true, "GameSettings.DefaultFullscreen=%s, expected true" % gset.DefaultFullscreen)
	_check(is_equal_approx(gset.DefaultMasterVolume, 0.8), "GameSettings.DefaultMasterVolume=%s, expected 0.8" % gset.DefaultMasterVolume)

	# The player's own preferences must survive the smoke run: everything below writes the probe
	# file only (risk 4 in the plan).
	var real_before: int = _real_stamp()
	gset.ConfigPath = PROBE_PATH
	DirAccess.remove_absolute(PROBE_PATH)

	# 2. A missing file is normal (first launch): defaults, no ERROR line.
	gset.Load()
	_check(gset.Fullscreen == gset.DefaultFullscreen,
		"Load() with no file gave Fullscreen=%s, expected DefaultFullscreen=%s" % [gset.Fullscreen, gset.DefaultFullscreen])
	_check(is_equal_approx(gset.MasterVolume, gset.DefaultMasterVolume),
		"Load() with no file gave MasterVolume=%s, expected DefaultMasterVolume=%s" % [gset.MasterVolume, gset.DefaultMasterVolume])

	# 3. Save -> Load round-trip through the ConfigFile.
	gset.Fullscreen = false
	gset.MasterVolume = PROBE_VOLUME
	gset.Save()
	_check(FileAccess.file_exists(PROBE_PATH), "Save() did not create %s" % PROBE_PATH)
	gset.Fullscreen = true
	gset.MasterVolume = 1.0
	gset.Load()
	_check(gset.Fullscreen == false, "Load() after Save(false) gave Fullscreen=%s, expected false" % gset.Fullscreen)
	_check(is_equal_approx(gset.MasterVolume, PROBE_VOLUME),
		"Load() after Save(%s) gave MasterVolume=%s" % [PROBE_VOLUME, gset.MasterVolume])

	# 4. Signals: once per real change, never for a repeat; ToggleFullscreen flips and emits once.
	var fs_events: Array = []
	var vol_events: Array = []
	gset.FullscreenChanged.connect(func(v: bool): fs_events.append(v))
	gset.MasterVolumeChanged.connect(func(v: float): vol_events.append(v))
	gset.Fullscreen = true
	gset.Fullscreen = true
	_check(fs_events == [true], "FullscreenChanged fired %s for false->true->true, expected [true]" % [fs_events])
	gset.ToggleFullscreen()
	_check(gset.Fullscreen == false, "ToggleFullscreen() left Fullscreen=%s, expected false" % gset.Fullscreen)
	_check(fs_events.size() == 2, "ToggleFullscreen() emitted %d changes in total, expected 2" % fs_events.size())
	gset.MasterVolume = 0.5
	gset.MasterVolume = 0.5
	_check(vol_events.size() == 1, "MasterVolumeChanged fired %d times for 0.35->0.5->0.5, expected 1" % vol_events.size())

	# 5. Volume mapping on the master bus (bus 0 exists under the dummy audio driver too).
	_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(0.5)) <= DB_TOL,
		"master bus at MasterVolume=0.5 is %.4f dB, expected %.4f" % [AudioServer.get_bus_volume_db(0), linear_to_db(0.5)])
	_check(AudioServer.is_bus_mute(0) == false, "master bus muted at MasterVolume=0.5")
	gset.MasterVolume = 0.0
	_check(AudioServer.is_bus_mute(0) == true, "master bus not muted at MasterVolume=0 (would be -inf dB instead)")
	gset.MasterVolume = 1.5
	_check(is_equal_approx(gset.MasterVolume, 1.0), "MasterVolume=%s after setting 1.5, expected the clamp to 1" % gset.MasterVolume)

	# 6. Teardown: no probe file left behind, the player's own settings untouched, the autoload
	#    back on its real path and its real values.
	DirAccess.remove_absolute(PROBE_PATH)
	_check(not FileAccess.file_exists(PROBE_PATH), "%s survived the teardown" % PROBE_PATH)
	gset.ConfigPath = REAL_PATH
	gset.Load()
	_check(_real_stamp() == real_before,
		"the smoke run touched the player's own %s (modified %s -> %s)" % [REAL_PATH, real_before, _real_stamp()])
