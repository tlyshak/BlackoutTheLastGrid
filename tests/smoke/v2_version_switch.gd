extends SceneTree
# Smoke: the game-version switch of the v2 line (T-V2-01 step 01a, GAME_DESIGN §6a) —
# GameSettings.GameVersion is a V1/V2 enum defaulting to V1, persisted as `[game] version` in the
# ConfigFile (round-trip, an unknown number falls back to the default), GameVersionChanged fires
# once per real change; the SettingsMenu «Game version» OptionButton has the items v1 (id 0) /
# v2 (id 1), shows the autoload's value on Open(), writes the picked item back, Close() persists
# it, and a change from elsewhere re-selects the item without emitting item_selected; the
# exposition is the one branch point — with V2 it hands over to scenes/v2/Main.tscn with the v2
# prologue as Main.CurrentLevel and GameState.CurrentScenePath, a KO restart reloads the v2 Main
# (never the v1 one, never the exposition), flipping the setting mid-run changes nothing, the v2
# prologue's NextLevel is the shared Level01_District, and with V1 the exposition still goes to
# scenes/Main.tscn. Needs frames: the scene changes are deferred.
# ConfigPath is redirected to a throwaway file first; the player's own user://settings.cfg is
# asserted untouched and the real GameVersion is restored on teardown.
# Run: godot --headless --path . -s tests/smoke/v2_version_switch.gd

const NAME := "v2_version_switch"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Booting a prologue three times
# (v2, v2 restart, v1) is the slow part; a green run uses well under 6000 idle frames.
const MAX_FRAMES := 6000
const SETTINGS_PATH := "res://scenes/ui/SettingsMenu.tscn"
const EXPOSITION_PATH := "res://scenes/ui/Exposition.tscn"
const MAIN_V1 := "res://scenes/Main.tscn"
const MAIN_V2 := "res://scenes/v2/Main.tscn"
const PROLOGUE_V1 := "res://scenes/levels/Level00_Prologue.tscn"
const PROLOGUE_V2 := "res://scenes/v2/levels/Level00_Prologue.tscn"
const NEXT_LEVEL := "res://scenes/levels/Level01_District.tscn"
const PROBE_PATH := "user://settings_v2_smoke.cfg"
const REAL_PATH := "user://settings.cfg"
const VERSION_V1 := 0             # GameVersion.V1 (C# enums come back as int)
const VERSION_V2 := 1             # GameVersion.V2
const VERSION_UNKNOWN := 7        # not in the enum: Load() must fall back to the default
const EXPOSITION_CAP := 12        # Advance() calls allowed to play the exposition out
const SETTLE_CAP := 20            # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05        # process delta (s) below which the loop is back to normal pacing
const SCENE_CHANGE_CAP_MS := 4000
const NO_CHANGE_FRAMES := 30      # idle frames a mid-run flip is watched for a stray scene change

var _started := false
var _frames := 0
var _failures: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _process(_delta: float) -> bool:
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

func _watch_ms(pred: Callable, cap_ms: int) -> int:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < cap_ms:
		if pred.call():
			return Time.get_ticks_msec() - start
		await process_frame
	return -1

func _finish() -> void:
	if Engine.time_scale != 1.0:
		_check(false, "Engine.time_scale=%s at the end, expected 1" % Engine.time_scale)
		Engine.time_scale = 1.0
	if paused:
		_check(false, "the tree is still paused at the end")
		paused = false
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

func _stamp() -> int:
	return FileAccess.get_modified_time(REAL_PATH) if FileAccess.file_exists(REAL_PATH) else -1

func _drop_current_scene() -> void:
	var cs: Node = current_scene
	current_scene = null
	if cs != null and is_instance_valid(cs):
		cs.queue_free()
	await _step(2)

# Plays the exposition out through the overlay and returns the Main it handed over to (or null).
func _run_exposition(expo_scene: PackedScene, lines: Variant) -> Node:
	var expo: Node = expo_scene.instantiate()
	if lines != null:
		expo.Lines = lines
	var expo_id: int = expo.get_instance_id()   # taken before _Ready: an empty Lines hands over at once
	root.add_child(expo)
	current_scene = expo
	await _step(1)
	var cutscene: Node = expo.get("Cutscene") if is_instance_valid(expo) else null
	var advances := 0
	while is_instance_valid(expo) and cutscene != null and cutscene.IsPlaying and advances < EXPOSITION_CAP:
		cutscene.Advance()
		advances += 1
		await _step(1)
	var handed: int = await _watch_ms(func():
		var cs: Node = current_scene
		return cs != null and cs.get_instance_id() != expo_id, SCENE_CHANGE_CAP_MS)
	if handed < 0:
		_check(false, "the exposition did not hand over within %d ms" % SCENE_CHANGE_CAP_MS)
		return null
	await _settle()
	return current_scene

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	var gset: Node = root.get_node_or_null("GameSettings")
	_check(gs != null, "GameState autoload not in tree")
	_check(gset != null, "GameSettings autoload not in tree")
	if gs == null or gset == null:
		_finish()
		return
	if gset.get("GameVersion") == null or gset.get("DefaultGameVersion") == null:
		_check(false, "GameSettings has no GameVersion / DefaultGameVersion export — GameSettings.cs not rebuilt?")
		_finish()
		return
	gs.ResetRun()
	gs.CurrentScenePath = ""
	var real_before: int = _stamp()
	var real_version: int = gset.GameVersion
	gset.ConfigPath = PROBE_PATH
	DirAccess.remove_absolute(PROBE_PATH)

	# 1. The enum and its persistence: default V1, round-trip, unknown -> default, signal once.
	_check(gset.DefaultGameVersion == VERSION_V1, "GameSettings.DefaultGameVersion=%s, expected %d (V1)" % [gset.DefaultGameVersion, VERSION_V1])
	gset.Load()
	_check(gset.GameVersion == VERSION_V1, "Load() with no file gave GameVersion=%s, expected the default %d" % [gset.GameVersion, VERSION_V1])
	var events: Array = []
	gset.GameVersionChanged.connect(func(v: int): events.append(v))
	gset.GameVersion = VERSION_V2
	gset.GameVersion = VERSION_V2
	_check(events == [VERSION_V2], "GameVersionChanged fired %s for V1->V2->V2, expected [%d]" % [events, VERSION_V2])
	gset.Save()
	var written := ConfigFile.new()
	_check(written.load(PROBE_PATH) == OK and written.get_value("game", "version", -1) == VERSION_V2,
		"Save() did not write [game] version=%d to %s (got %s)" % [VERSION_V2, PROBE_PATH, written.get_value("game", "version", "nothing")])
	_check(written.get_value("display", "fullscreen", null) != null, "Save() dropped the [display] section while adding [game]")
	gset.GameVersion = VERSION_V1
	gset.Load()
	_check(gset.GameVersion == VERSION_V2, "Load() after Save(V2) gave GameVersion=%s, expected %d" % [gset.GameVersion, VERSION_V2])
	_check(events == [VERSION_V2, VERSION_V1, VERSION_V2], "GameVersionChanged fired %s across the round-trip, expected [1, 0, 1]" % [events])
	written.set_value("game", "version", VERSION_UNKNOWN)
	written.save(PROBE_PATH)
	gset.Load()
	_check(gset.GameVersion == VERSION_V1, "Load() with [game] version=%d gave GameVersion=%s, expected the default %d" % [VERSION_UNKNOWN, gset.GameVersion, VERSION_V1])

	# 2. The settings screen: the dropdown mirrors the autoload both ways and Close() persists.
	var settings_scene: PackedScene = load(SETTINGS_PATH)
	_check(settings_scene != null, "%s failed to load" % SETTINGS_PATH)
	if settings_scene != null:
		var settings: Node = settings_scene.instantiate()
		root.add_child(settings)
		await _step(1)
		var option: Node = settings.get("VersionOption")
		_check(option != null and option is OptionButton, "SettingsMenu.VersionOption is %s, expected an OptionButton" % (option.get_class() if option != null else "null"))
		if option != null and option is OptionButton:
			_check(option.item_count == 2, "VersionOption has %d items, expected 2 (v1, v2)" % option.item_count)
			_check(option.get_item_index(VERSION_V1) >= 0 and option.get_item_index(VERSION_V2) >= 0,
				"VersionOption items do not carry the ids %d and %d" % [VERSION_V1, VERSION_V2])
			if option.get_item_index(VERSION_V1) >= 0 and option.get_item_index(VERSION_V2) >= 0:
				_check(option.get_item_text(option.get_item_index(VERSION_V1)) == "v1" and option.get_item_text(option.get_item_index(VERSION_V2)) == "v2",
					"VersionOption item texts are '%s' / '%s', expected 'v1' / 'v2'" % [option.get_item_text(option.get_item_index(VERSION_V1)), option.get_item_text(option.get_item_index(VERSION_V2))])
			var note: Node = settings.get_node_or_null("Root/Panel/Margin/VBox/VersionNote")
			_check(note != null and note is Label and note.text.begins_with("Applies to New Game"),
				"SettingsMenu has no VersionNote label telling the player the switch applies to New Game")
			var row_label: Node = settings.get_node_or_null("Root/Panel/Margin/VBox/VersionRow/Label")
			_check(row_label != null and row_label.text == "Game version", "the version row label reads '%s', expected 'Game version'" % (row_label.text if row_label != null else "null"))

			gset.GameVersion = VERSION_V2
			settings.Open()
			await _step(1)
			_check(option.get_selected_id() == VERSION_V2, "Open() with GameVersion=V2 selected item id %d, expected %d" % [option.get_selected_id(), VERSION_V2])
			# The user picks v1: OptionButton emits item_selected(index) after selecting the item.
			var v1_index: int = option.get_item_index(VERSION_V1)
			option.select(v1_index)
			option.item_selected.emit(v1_index)
			await _step(1)
			_check(gset.GameVersion == VERSION_V1, "picking «v1» left GameSettings.GameVersion=%s, expected %d" % [gset.GameVersion, VERSION_V1])
			# A change from elsewhere re-selects the item without writing back.
			var selected_events := 0
			option.item_selected.connect(func(_i: int): selected_events += 1)
			gset.GameVersion = VERSION_V2
			await _step(1)
			_check(option.get_selected_id() == VERSION_V2, "the dropdown shows id %d after GameVersion=V2 from elsewhere, expected %d" % [option.get_selected_id(), VERSION_V2])
			_check(selected_events == 0, "the dropdown emitted item_selected %d times while syncing from the autoload, expected 0" % selected_events)
			DirAccess.remove_absolute(PROBE_PATH)
			settings.Close()
			await _step(1)
			var saved := ConfigFile.new()
			_check(saved.load(PROBE_PATH) == OK and saved.get_value("game", "version", -1) == VERSION_V2,
				"Close() did not persist [game] version=%d (got %s)" % [VERSION_V2, saved.get_value("game", "version", "nothing") if saved.load(PROBE_PATH) == OK else "no file"])
		settings.queue_free()
		await _step(1)

	# 3. Routing with V2: the exposition hands over to v2/Main with the v2 prologue.
	var expo_scene: PackedScene = load(EXPOSITION_PATH)
	_check(expo_scene != null, "%s failed to load" % EXPOSITION_PATH)
	if expo_scene == null:
		_finish()
		return
	var probe: Node = expo_scene.instantiate()
	_check(probe.get("NextScenePathV2") == MAIN_V2, "Exposition.NextScenePathV2='%s', expected %s" % [probe.get("NextScenePathV2"), MAIN_V2])
	_check(probe.get("NextScenePath") == MAIN_V1, "Exposition.NextScenePath='%s', expected %s (v1 untouched)" % [probe.get("NextScenePath"), MAIN_V1])
	probe.free()
	gset.GameVersion = VERSION_V2
	gs.CurrentScenePath = ""
	var main_v2: Node = await _run_exposition(expo_scene, null)
	_check(main_v2 != null and main_v2.scene_file_path == MAIN_V2,
		"with GameVersion=V2 the exposition handed over to %s, expected %s" % [main_v2.scene_file_path if main_v2 != null else "null", MAIN_V2])
	var level_v2: Node = main_v2.get("CurrentLevel") if main_v2 != null else null
	_check(level_v2 != null and level_v2.scene_file_path == PROLOGUE_V2,
		"v2 Main.CurrentLevel is %s, expected %s" % [level_v2.scene_file_path if level_v2 != null else "null", PROLOGUE_V2])
	_check(gs.CurrentScenePath == PROLOGUE_V2, "GameState.CurrentScenePath='%s' in the v2 run, expected %s" % [gs.CurrentScenePath, PROLOGUE_V2])
	if level_v2 != null:
		var next: PackedScene = level_v2.get("NextLevel")
		_check(next != null and next.resource_path == NEXT_LEVEL,
			"the v2 prologue's NextLevel is %s, expected the shared %s" % [next.resource_path if next != null else "null", NEXT_LEVEL])
		# Flipping the setting mid-run changes nothing: the level instance stays.
		var level_id: int = level_v2.get_instance_id()
		var main_id: int = main_v2.get_instance_id()
		gset.GameVersion = VERSION_V1
		for i in NO_CHANGE_FRAMES:
			await process_frame
		_check(current_scene != null and current_scene.get_instance_id() == main_id and is_instance_valid(level_v2) and level_v2.get_instance_id() == level_id,
			"flipping GameVersion mid-run changed the scene — the current run must keep its version")
		gset.GameVersion = VERSION_V2

		# 4. A KO restart reloads the v2 Main: still v2, never the v1 one, never the exposition.
		level_v2.RestartLevel()
		var reloaded: int = await _watch_ms(func():
			var cs: Node = current_scene
			return cs != null and cs.get_instance_id() != main_id, SCENE_CHANGE_CAP_MS)
		_check(reloaded >= 0, "RestartLevel() did not reload the v2 Main within %d ms" % SCENE_CHANGE_CAP_MS)
		if reloaded >= 0:
			await _settle()
			var main2: Node = current_scene
			_check(main2 != null and main2.scene_file_path == MAIN_V2,
				"after the v2 KO restart the current scene is %s, expected %s again" % [main2.scene_file_path if main2 != null else "null", MAIN_V2])
			if main2 != null:
				var level2: Node = main2.get("CurrentLevel")
				_check(level2 != null and level2.get_instance_id() != level_id and level2.scene_file_path == PROLOGUE_V2,
					"after the v2 KO restart the level is %s, expected a fresh %s" % [level2.scene_file_path if level2 != null else "null", PROLOGUE_V2])
			_check(gs.CurrentScenePath == PROLOGUE_V2, "GameState.CurrentScenePath='%s' after the v2 restart, expected %s" % [gs.CurrentScenePath, PROLOGUE_V2])
	await _drop_current_scene()

	# 5. Routing with V1: the exposition still goes to the v1 Main (an empty Lines goes straight on).
	gset.GameVersion = VERSION_V1
	gs.CurrentScenePath = ""
	var main_v1: Node = await _run_exposition(expo_scene, PackedStringArray())
	_check(main_v1 != null and main_v1.scene_file_path == MAIN_V1,
		"with GameVersion=V1 the exposition handed over to %s, expected %s" % [main_v1.scene_file_path if main_v1 != null else "null", MAIN_V1])
	var level_v1: Node = main_v1.get("CurrentLevel") if main_v1 != null else null
	_check(level_v1 != null and level_v1.scene_file_path == PROLOGUE_V1,
		"v1 Main.CurrentLevel is %s, expected %s" % [level_v1.scene_file_path if level_v1 != null else "null", PROLOGUE_V1])
	_check(gs.CurrentScenePath == PROLOGUE_V1, "GameState.CurrentScenePath='%s' in the v1 run, expected %s" % [gs.CurrentScenePath, PROLOGUE_V1])
	await _drop_current_scene()

	# 6. Teardown: probe gone, the player's own settings untouched, the real version back.
	DirAccess.remove_absolute(PROBE_PATH)
	_check(not FileAccess.file_exists(PROBE_PATH), "%s survived the teardown" % PROBE_PATH)
	gset.ConfigPath = REAL_PATH
	gset.Load()
	_check(gset.GameVersion == real_version, "GameVersion=%s after the teardown Load(), expected the machine's own %s" % [gset.GameVersion, real_version])
	_check(_stamp() == real_before, "the smoke run touched the player's own %s (modified %s -> %s)" % [REAL_PATH, real_before, _stamp()])
	gs.ResetRun()
	gs.CurrentScenePath = ""
	print("v2_version_switch: settings -> v2 run -> restart -> v1 run done in %d idle frames" % _frames)
	_finish()
