extends SceneTree
# Smoke: the pause menu (T-07i-a) — PauseMenu.tscn is a CanvasLayer above the HUD that keeps
# processing while paused, it owns SceneTree.paused (open/resume, PauseToggled both ways, focus on
# «Resume»), it cancels a hit-stop in flight so the menu can never sit over a frozen
# Engine.time_scale, the settings overlay above it eats the first Escape and leaves the game
# paused, «Quit to Main Menu» only emits QuitToMenuRequested (the menu never changes the scene
# itself), and a menu freed while open unpauses the tree. Plus the two invariants around it: a
# paused Cutscene advances no line however often `interact` is pressed, and LevelBase.GoToMainMenu
# — reached through the level's own wiring in TestRoom — lands on the main menu unpaused, at
# time_scale 1 and with a full reserve. All three level scenes carry a PauseMenu instance.
# ConfigPath is redirected first: closing the settings screen saves (risk 4 in the plan).
# Run: godot --headless --path . -s tests/smoke/ui_pause.gd

const NAME := "ui_pause"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. A green run stays well below.
const MAX_FRAMES := 4000
const PAUSE_PATH := "res://scenes/ui/PauseMenu.tscn"
const SETTINGS_PATH := "res://scenes/ui/SettingsMenu.tscn"
const CUTSCENE_PATH := "res://scenes/ui/Cutscene.tscn"
const ROOM_PATH := "res://scenes/levels/TestRoom.tscn"
const MENU_PATH := "res://scenes/ui/MainMenu.tscn"
const LEVEL_SCENES := ["res://scenes/levels/Level00_Prologue.tscn", "res://scenes/levels/Level01_District.tscn", "res://scenes/levels/TestRoom.tscn"]
const PROBE_PATH := "user://settings_pause_smoke.cfg"
const REAL_PATH := "user://settings.cfg"
const PAUSE_LAYER := 25         # above the HUD (10) and the Cutscene overlay (20)
const SETTINGS_LAYER := 30      # above the pause menu
const PROCESS_MODE_ALWAYS := 3  # Node.PROCESS_MODE_ALWAYS
const SETTLE_CAP := 20
const SETTLE_DELTA := 0.05
const SCENE_CHANGE_CAP_MS := 4000
const PAUSED_TAPS := 10         # `interact` + `attack` tap pairs a paused cutscene must ignore
const ACTIONS := ["interact", "attack", "pause"]

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

# One-shot press of `action` as an InputEvent, so _UnhandledInput handlers see it.
func _send_action(action: String) -> void:
	var ev := InputEventAction.new()
	ev.action = action
	ev.pressed = true
	Input.parse_input_event(ev)
	await process_frame
	await _step(1)

# Presses `action` for exactly one physics frame (seen as just-pressed by that frame's callbacks).
func _tap(action: String) -> void:
	Input.action_press(action)
	await physics_frame
	Input.action_release(action)
	await physics_frame

func _release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)

func _finish() -> void:
	_release_all()
	if paused:
		_check(false, "the tree is still paused at the end")
		paused = false
	if Engine.time_scale != 1.0:
		_check(false, "Engine.time_scale=%s at the end, expected 1" % Engine.time_scale)
		Engine.time_scale = 1.0
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

func _stamp() -> int:
	return FileAccess.get_modified_time(REAL_PATH) if FileAccess.file_exists(REAL_PATH) else -1

# True when the packed scene has a direct child node with this name (no instantiation needed).
func _has_child_named(path: String, wanted: String) -> bool:
	var ps: PackedScene = load(path)
	if ps == null:
		return false
	var st: SceneState = ps.get_state()
	for i in st.get_node_count():
		if st.get_node_name(i) == wanted:
			return true
	return false

func _run() -> void:
	for a in ["pause", "interact"]:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)
		if InputMap.has_action(a):
			_check(InputMap.action_get_events(a).size() > 0, "action '%s' has no events" % a)
	var gs: Node = root.get_node_or_null("GameState")
	var gset: Node = root.get_node_or_null("GameSettings")
	_check(gs != null, "GameState autoload not in tree")
	_check(gset != null, "GameSettings autoload not in tree")
	_check(root.get_node_or_null("HitStop") != null, "HitStop autoload not in tree")
	if gs == null or gset == null:
		_finish()
		return
	gs.ResetRun()
	var real_before: int = _stamp()
	gset.ConfigPath = PROBE_PATH

	# 0. Every level scene carries a PauseMenu instance (checked on the packed state, no load cost).
	for path in LEVEL_SCENES:
		_check(_has_child_named(path, "PauseMenu"), "%s has no PauseMenu node" % path)

	# 1. Scene wiring: layers, process modes, exports.
	var scene: PackedScene = load(PAUSE_PATH)
	_check(scene != null, "%s failed to load" % PAUSE_PATH)
	if scene == null:
		_finish()
		return
	var pm: Node = scene.instantiate()
	root.add_child(pm)
	await _step(1)
	_check(pm is CanvasLayer, "PauseMenu root is a %s, expected CanvasLayer" % pm.get_class())
	_check(pm.get_script() != null and str(pm.get_script().resource_path).ends_with("PauseMenu.cs"),
		"PauseMenu.tscn has no PauseMenu.cs attached (did dotnet build run?)")
	if pm.get("Root") == null:
		_check(false, "PauseMenu.Root export missing — C# script not attached, aborting")
		pm.queue_free()
		_finish()
		return
	_check(pm.layer == PAUSE_LAYER, "PauseMenu.layer=%d, expected %d (above the HUD and the Cutscene overlay)" % [pm.layer, PAUSE_LAYER])
	_check(pm.process_mode == PROCESS_MODE_ALWAYS, "PauseMenu.process_mode=%d, expected %d (ALWAYS)" % [pm.process_mode, PROCESS_MODE_ALWAYS])
	_check(pm.PauseEnabled == true, "PauseMenu.PauseEnabled=%s, expected true by default" % pm.PauseEnabled)
	_check(pm.IsOpen == false, "PauseMenu is open on instantiation")
	var settings: Node = pm.Settings
	_check(settings != null and settings.get_script() != null and str(settings.get_script().resource_path).ends_with("SettingsMenu.cs"),
		"PauseMenu.Settings is not a SettingsMenu instance")
	if settings != null:
		_check(settings.layer == SETTINGS_LAYER, "SettingsMenu.layer=%d, expected %d (above the pause menu)" % [settings.layer, SETTINGS_LAYER])
		_check(settings.process_mode == PROCESS_MODE_ALWAYS, "SettingsMenu.process_mode=%d, expected %d (ALWAYS)" % [settings.process_mode, PROCESS_MODE_ALWAYS])
	_check(pm.ResumeButton.text == "Resume", "ResumeButton.text='%s'" % pm.ResumeButton.text)
	_check(pm.QuitButton.text == "Quit to Main Menu", "QuitButton.text='%s'" % pm.QuitButton.text)

	# 2. Open/Resume own SceneTree.paused and emit PauseToggled both ways.
	var toggles: Array = []
	pm.PauseToggled.connect(func(v: bool): toggles.append(v))
	pm.Open()
	_check(paused == true, "the tree is not paused after PauseMenu.Open()")
	_check(pm.IsOpen == true and pm.Root.visible == true, "the pause overlay is not visible after Open()")
	_check(pm.ResumeButton.has_focus(), "«Resume» has no focus after Open() — the menu needs no mouse")
	_check(toggles == [true], "PauseToggled fired %s on Open(), expected [true]" % [toggles])
	pm.Resume()
	_check(paused == false, "the tree is still paused after PauseMenu.Resume()")
	_check(pm.IsOpen == false and pm.Root.visible == false, "the pause overlay is still visible after Resume()")
	_check(toggles == [true, false], "PauseToggled fired %s over open+resume, expected [true, false]" % [toggles])

	# 3. A hit-stop in flight is dropped when the player pauses (risk 6 in the plan).
	Engine.time_scale = 0.0
	pm.Open()
	_check(is_equal_approx(Engine.time_scale, 1.0),
		"Engine.time_scale=%s with the pause menu open, expected 1 (HitStop.Cancel in Open())" % Engine.time_scale)
	pm.Resume()

	# 4. The `pause` action toggles the menu; with the settings screen open the first Escape only
	#    closes the settings and the game stays paused (two meanings of one key, risk 7).
	await _send_action("pause")
	_check(paused == true and pm.IsOpen == true, "the `pause` action did not open the menu (paused=%s open=%s)" % [paused, pm.IsOpen])
	pm.SettingsButton.emit_signal("pressed")
	await _step(1)
	_check(settings.IsOpen == true, "«Settings» did not open the settings screen from the pause menu")
	await _send_action("pause")
	_check(settings.IsOpen == false, "the settings screen is still open after Escape")
	_check(paused == true and pm.IsOpen == true, "Escape over the settings screen also resumed the game (paused=%s)" % paused)
	_check(pm.SettingsButton.has_focus(), "focus did not return to «Settings» after the settings screen closed")
	await _send_action("pause")
	_check(paused == false and pm.IsOpen == false, "the second `pause` press did not resume (paused=%s open=%s)" % [paused, pm.IsOpen])

	# 5. «Quit to Main Menu» resumes and asks; it never changes the scene itself.
	var quit_events: Array = []
	pm.QuitToMenuRequested.connect(func(): quit_events.append(1))
	var scene_before: Node = current_scene
	pm.Open()
	pm.QuitButton.emit_signal("pressed")
	await _step(1)
	_check(quit_events.size() == 1, "QuitToMenuRequested fired %d times, expected 1" % quit_events.size())
	_check(paused == false, "the tree is still paused after «Quit to Main Menu»")
	_check(current_scene == scene_before, "the pause menu changed the current scene itself — that is the level's job")

	# 6. A menu freed while open must not leave the tree frozen.
	pm.Open()
	_check(paused == true, "the tree is not paused before the free")
	pm.queue_free()
	await _step(1)
	_check(not is_instance_valid(pm), "the pause menu is still valid one frame after queue_free()")
	_check(paused == false, "the tree stayed paused after an open pause menu was freed")

	# 7. A paused cutscene ignores `interact` and advances no line (the guard in Cutscene.cs).
	var cs_scene: PackedScene = load(CUTSCENE_PATH)
	_check(cs_scene != null, "%s failed to load" % CUTSCENE_PATH)
	if cs_scene != null:
		var cut: Node = cs_scene.instantiate()
		root.add_child(cut)
		await _step(1)
		cut.Play(PackedStringArray(["first line", "second line"]))
		await _step(1)
		_check(cut.IsPlaying == true and cut.CurrentLine == 0, "the cutscene is at line %d, expected 0" % cut.CurrentLine)
		paused = true
		for i in PAUSED_TAPS:
			await _tap("interact")
			await _tap("attack")   # both halves of the same `if` in Cutscene._PhysicsProcess
		_check(cut.CurrentLine == 0, "the paused cutscene advanced to line %d after %d interact+attack taps, expected 0" % [cut.CurrentLine, PAUSED_TAPS])
		_check(cut.IsPlaying == true, "the paused cutscene finished on its own")
		paused = false
		await _step(1)
		await _tap("interact")
		_check(cut.CurrentLine == 1, "the resumed cutscene is at line %d after one tap, expected 1" % cut.CurrentLine)
		cut.queue_free()
		await _step(1)

	# 8. LevelBase: the level's own pause menu is wired, and «Quit to Main Menu» lands on the
	#    main menu unpaused, at time_scale 1 and with a full reserve (acceptance criteria 7 and 13).
	var room_scene: PackedScene = load(ROOM_PATH)
	_check(room_scene != null, "%s failed to load" % ROOM_PATH)
	if room_scene == null:
		_finish()
		return
	var room: Node = room_scene.instantiate()
	root.add_child(room)
	current_scene = room
	await _settle()
	var room_pm: Node = room.get("Pause")
	_check(room_pm != null, "TestRoom.Pause is null — the PauseMenu export is not wired in the scene")
	if room_pm == null:
		room.queue_free()
		_finish()
		return
	_check(room_pm == room.get_node_or_null("PauseMenu"), "TestRoom.Pause does not point at the scene's own PauseMenu")
	gs.Energy = 15.0
	room_pm.Open()
	Engine.time_scale = 0.0   # a hit-stop that started before the quit must not survive it
	_check(paused == true, "the tree is not paused after opening the level's pause menu")
	var room_id: int = room.get_instance_id()
	room_pm.QuitButton.emit_signal("pressed")
	var left: int = await _watch_ms(func():
		var cs: Node = current_scene
		return cs != null and cs.get_instance_id() != room_id, SCENE_CHANGE_CAP_MS)
	_check(left >= 0, "«Quit to Main Menu» did not change the scene within %d ms" % SCENE_CHANGE_CAP_MS)
	if left >= 0:
		await _settle()
		var menu: Node = current_scene
		_check(menu != null and menu.scene_file_path == MENU_PATH,
			"the current scene is %s, expected the main menu from %s" % [menu.scene_file_path if menu != null else "null", MENU_PATH])
		_check(paused == false, "the game is still paused on the main menu — it would come up frozen")
		_check(is_equal_approx(Engine.time_scale, 1.0), "Engine.time_scale=%s on the main menu, expected 1" % Engine.time_scale)
		_check(is_equal_approx(gs.Energy, gs.MaxEnergy), "Energy=%s after quitting to the menu, expected MaxEnergy (ResetRun)" % gs.Energy)
		_check(not is_instance_valid(room), "TestRoom is still alive after the scene change")

	# 9. Teardown.
	var cs_end: Node = current_scene
	current_scene = null
	if cs_end != null and is_instance_valid(cs_end):
		cs_end.queue_free()
	await _step(2)
	DirAccess.remove_absolute(PROBE_PATH)
	gset.ConfigPath = REAL_PATH
	gset.Load()
	_check(_stamp() == real_before, "the smoke run touched the player's own %s" % REAL_PATH)
	gs.ResetRun()
	gs.CurrentScenePath = ""
	_finish()
