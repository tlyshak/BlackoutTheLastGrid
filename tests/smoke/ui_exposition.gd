extends SceneTree
# Smoke: the 2073 exposition (T-07s-e) — Exposition.tscn is the run entry the main menu points
# «New Game» at: it plays its screens through the shared Cutscene overlay (3–5 English lines,
# skippable with `interact`), and when the last one is dismissed the tree's current scene becomes
# Main with Level00_Prologue as its child and GameState.CurrentScenePath set — the Exposition node is
# gone. A KO restart (LevelBase.RestartLevel → ReloadCurrentScene) reloads Main, never the
# exposition: it plays exactly once per New Game. An empty Lines array goes straight to Main.
# Needs frames: the scene changes are deferred.
# Run: godot --headless --path . -s tests/smoke/ui_exposition.gd

const NAME := "ui_exposition"   # must equal the file basename
const MAX_FRAMES := 6000
const MENU_PATH := "res://scenes/ui/MainMenu.tscn"
const EXPOSITION_PATH := "res://scenes/ui/Exposition.tscn"
const MAIN_PATH := "res://scenes/Main.tscn"
const PROLOGUE_PATH := "res://scenes/levels/Level00_Prologue.tscn"
const SETTLE_CAP := 20
const SETTLE_DELTA := 0.05
const SCENE_CHANGE_CAP_MS := 4000
const TAP_CAP := 12
const WATCH_FRAMES := 40        # idle frames the reloaded run is watched for a stray Exposition

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

func _tap(action: String) -> void:
	Input.action_press(action)
	await _step(1)
	Input.action_release(action)

func _finish() -> void:
	Input.action_release("interact")
	paused = false
	if Engine.time_scale != 1.0:
		_check(false, "Engine.time_scale=%s at the end, expected 1" % Engine.time_scale)
		Engine.time_scale = 1.0
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.ResetRun()
		gs.CurrentScenePath = ""
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

func _has_cyrillic(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x0400 and code <= 0x04FF:
			return true
	return false

func _is_exposition(node: Node) -> bool:
	var script: Variant = node.get_script()
	return script != null and str(script.resource_path).ends_with("Exposition.cs")

func _expositions_in_tree() -> int:
	var n := 0
	for child in root.get_children():
		if _is_exposition(child):
			n += 1
	return n

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()
	gs.CurrentScenePath = ""
	var gset: Node = root.get_node_or_null("GameSettings")
	_check(gset != null, "GameSettings autoload not in tree")
	if gset != null:
		gset.GameVersion = 0   # pin v1: a persisted «v2» on this machine would route the exposition to v2/Main (T-V2-01)

	# 1. The menu's New Game path is the exposition, and it loads.
	var menu_scene: PackedScene = load(MENU_PATH)
	_check(menu_scene != null, "%s failed to load" % MENU_PATH)
	if menu_scene != null:
		var menu: Node = menu_scene.instantiate()
		_check(menu.get("NewGameScenePath") == EXPOSITION_PATH,
			"MainMenu.NewGameScenePath='%s', expected %s" % [menu.get("NewGameScenePath"), EXPOSITION_PATH])
		menu.free()
	var scene: PackedScene = load(EXPOSITION_PATH)
	_check(scene != null, "%s failed to load" % EXPOSITION_PATH)
	if scene == null:
		_finish()
		return

	# 2. The exposition plays: 3–5 English screens, first one up, skippable, no GameState writes.
	var expo: Node = scene.instantiate()
	root.add_child(expo)
	current_scene = expo
	await _step(2)
	_check(_is_exposition(expo), "Exposition.tscn has no Exposition.cs attached (did dotnet build run?)")
	if expo.get("Lines") == null:
		_check(false, "Exposition.Lines export missing — C# script not attached, aborting")
		_finish()
		return
	var cutscene: Node = expo.get("Cutscene")
	_check(cutscene != null and cutscene.get("IsPlaying") != null, "Exposition.Cutscene is not a Cutscene overlay")
	if cutscene == null:
		_finish()
		return
	var lines: Array = Array(expo.Lines)
	_check(lines.size() >= 3 and lines.size() <= 5, "the exposition has %d screens, expected 3 to 5" % lines.size())
	for line in lines:
		_check(not line.is_empty() and not _has_cyrillic(line) and line.length() <= 120,
			"exposition screen '%s' is empty, not English or longer than 120 characters" % line)
	_check(expo.NextScenePath == MAIN_PATH, "Exposition.NextScenePath='%s', expected %s" % [expo.NextScenePath, MAIN_PATH])
	_check(cutscene.IsPlaying == true and cutscene.CurrentLine == 0,
		"Cutscene IsPlaying=%s CurrentLine=%s at start, expected true / 0" % [cutscene.IsPlaying, cutscene.CurrentLine])
	_check(cutscene.LineCount == lines.size(), "Cutscene.LineCount=%d, expected the %d screens of Lines" % [cutscene.LineCount, lines.size()])
	_check(cutscene.Skippable == expo.Skippable, "Cutscene.Skippable=%s is not the exposition's Skippable=%s" % [cutscene.Skippable, expo.Skippable])
	_check(gs.CurrentScenePath == "", "the exposition wrote GameState.CurrentScenePath='%s'; a resume must never land on it" % gs.CurrentScenePath)

	# 3. `interact` through it: Main becomes the current scene, the prologue is its child, the
	#    exposition is gone.
	var expo_id: int = expo.get_instance_id()
	var taps := 0
	while is_instance_valid(expo) and cutscene.IsPlaying and taps < TAP_CAP:
		await _tap("interact")
		await _step(2)
		taps += 1
	_check(taps == lines.size(), "the exposition ended after %d interact taps, expected %d (one per screen)" % [taps, lines.size()])
	var switched: int = await _watch_ms(func():
		var cs: Node = current_scene
		return cs != null and cs.get_instance_id() != expo_id, SCENE_CHANGE_CAP_MS)
	_check(switched >= 0, "the current scene did not change away from the exposition within %d ms" % SCENE_CHANGE_CAP_MS)
	if switched < 0:
		_finish()
		return
	await _settle()
	var main: Node = current_scene
	_check(not is_instance_valid(expo), "the Exposition node is still alive after its last screen")
	_check(_expositions_in_tree() == 0, "an Exposition node is still under root after the scene change")
	_check(main != null and main.name == "Main" and main.scene_file_path == MAIN_PATH,
		"the current scene is '%s', expected Main from %s" % [main.name if main != null else "null", MAIN_PATH])
	if main == null:
		_finish()
		return
	var level: Node = main.get("CurrentLevel")
	_check(level != null and level.scene_file_path == PROLOGUE_PATH,
		"Main.CurrentLevel is %s, expected the prologue from %s" % [level.scene_file_path if level != null else "null", PROLOGUE_PATH])
	_check(gs.CurrentScenePath == PROLOGUE_PATH, "GameState.CurrentScenePath='%s' after the exposition, expected %s" % [gs.CurrentScenePath, PROLOGUE_PATH])

	# 4. A KO restart reloads Main — the exposition never comes back.
	if level != null:
		var main_id: int = main.get_instance_id()
		level.RestartLevel()
		var seen_exposition := false
		var reloaded: int = await _watch_ms(func():
			if _expositions_in_tree() > 0:
				seen_exposition = true
			var cs: Node = current_scene
			return cs != null and cs.get_instance_id() != main_id, SCENE_CHANGE_CAP_MS)
		_check(reloaded >= 0, "RestartLevel() did not reload Main within %d ms" % SCENE_CHANGE_CAP_MS)
		for i in WATCH_FRAMES:
			await process_frame
			if _expositions_in_tree() > 0:
				seen_exposition = true
		var main2: Node = current_scene
		_check(main2 != null and main2.name == "Main" and main2.scene_file_path == MAIN_PATH,
			"after the restart the current scene is '%s' (%s), expected Main — a KO restart must never show the exposition"
			% [main2.name if main2 != null else "null", main2.scene_file_path if main2 != null else ""])
		_check(not seen_exposition, "an Exposition node appeared after the KO restart — it must play once per New Game only")
		if main2 != null:
			var level2: Node = main2.get("CurrentLevel")
			_check(level2 != null and level2.scene_file_path == PROLOGUE_PATH, "after the restart the level is %s, expected a fresh prologue" % level2)

	# 5. An empty Lines array goes straight to Main.
	var cs_end: Node = current_scene
	current_scene = null
	if cs_end != null and is_instance_valid(cs_end):
		cs_end.queue_free()
	await _step(2)
	var blank: Node = scene.instantiate()
	blank.Lines = PackedStringArray()
	root.add_child(blank)
	current_scene = blank
	var blank_id: int = blank.get_instance_id()
	var straight: int = await _watch_ms(func():
		var cs: Node = current_scene
		return cs != null and cs.get_instance_id() != blank_id, SCENE_CHANGE_CAP_MS)
	_check(straight >= 0, "an exposition with no lines did not hand over to Main within %d ms" % SCENE_CHANGE_CAP_MS)
	await _settle()
	var main3: Node = current_scene
	_check(main3 != null and main3.scene_file_path == MAIN_PATH, "after an empty exposition the current scene is %s, expected Main" % main3)

	# 6. Teardown.
	var last: Node = current_scene
	current_scene = null
	if last != null and is_instance_valid(last):
		last.queue_free()
	await _step(2)
	_finish()
