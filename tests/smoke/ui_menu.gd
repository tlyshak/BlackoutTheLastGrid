extends SceneTree
# Smoke: the main menu (T-07i-a) — MainMenu.tscn is a Control with MainMenu.cs and the shared
# HudTheme, the §8 logo is built procedurally (one Label per character of TitleText, exactly one
# of them lit and carrying an additive `Glow` TextureRect behind it at GlowLetterIndex), the three
# English buttons exist with «New Game» focused for keyboard/gamepad, NewGameScenePath points at
# Main and it really loads, the nested SettingsMenu opens from the menu and gives focus back on
# close, and — the contract T-07i-a must not break — «New Game» makes Main the tree's *current
# scene* (not a child of the menu) with a full energy reserve, booted into the two painted sections
# of level 0, so a level restart reloads Main into a fresh copy of them.
# Needs frames: the scene changes are deferred.
# The settings screen saves on close, so ConfigPath is redirected to a throwaway file first and
# the player's own user://settings.cfg is asserted untouched (risk 4 in the plan).
# Run: godot --headless --path . -s tests/smoke/ui_menu.gd

const NAME := "ui_menu"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Booting Main + the level
# twice is the slow part; a green run uses well under 6000 idle frames.
const MAX_FRAMES := 6000
const MENU_PATH := "res://scenes/ui/MainMenu.tscn"
const MAIN_PATH := "res://scenes/Main.tscn"
const LEVEL_PATH := "res://scenes/levels/Level00_Sections.tscn"
const PROBE_PATH := "user://settings_menu_smoke.cfg"
const REAL_PATH := "user://settings.cfg"
const SETTLE_CAP := 20          # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05      # process delta (s) below which the loop is back to normal pacing
const SCENE_CHANGE_CAP_MS := 4000
const MOUSE_FILTER_IGNORE := 2  # Control.MOUSE_FILTER_IGNORE
const BLEND_MODE_ADD := 1       # CanvasItemMaterial.BLEND_MODE_ADD
const PULSE_FRAMES := 20        # physics frames the halo Tween must visibly move over
const ALPHA_TOL := 0.01
const VOLUME_TEST := 0.5        # slider position the value label must render as "50 %"
const DB_TOL := 0.01
const START_ENERGY := 12.0      # leftover energy of an abandoned run; «New Game» must reset it

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

# Instantiating Main + the level is heavy; the next iteration runs several physics steps
# back-to-back. Wait until the process delta is normal again.
func _settle() -> void:
	for i in SETTLE_CAP:
		await process_frame
		if root.get_process_delta_time() < SETTLE_DELTA:
			return

# Watches idle frames until `pred` holds or `cap_ms` of wall time pass. Returns elapsed ms or -1.
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

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	var gset: Node = root.get_node_or_null("GameSettings")
	_check(gs != null, "GameState autoload not in tree")
	_check(gset != null, "GameSettings autoload not in tree")
	if gs == null or gset == null:
		_finish()
		return
	gs.ResetRun()
	var real_before: int = _stamp()
	gset.ConfigPath = PROBE_PATH   # closing the settings screen saves; never into the player's file

	# 1. The scene loads with its script and the shared theme.
	var scene: PackedScene = load(MENU_PATH)
	_check(scene != null, "%s failed to load" % MENU_PATH)
	if scene == null:
		_finish()
		return
	var menu: Node = scene.instantiate()
	root.add_child(menu)
	current_scene = menu
	await _step(1)
	_check(menu is Control, "MainMenu root is a %s, expected Control" % menu.get_class())
	_check(menu.get_script() != null and str(menu.get_script().resource_path).ends_with("MainMenu.cs"),
		"MainMenu.tscn has no MainMenu.cs attached (did dotnet build run?)")
	if menu.get("TitleText") == null:
		_check(false, "MainMenu.TitleText export missing — C# script not attached, aborting")
		menu.queue_free()
		_finish()
		return
	var theme: Theme = menu.theme
	_check(theme != null and str(theme.resource_path).ends_with("HudTheme.tres"),
		"MainMenu.theme is '%s', expected .../HudTheme.tres" % (theme.resource_path if theme != null else "null"))
	if theme != null:
		_check(theme.has_stylebox("normal", "Button"), "HudTheme lacks a Button 'normal' stylebox (the menus would not match the HUD)")

	# 2. The §8 logo: one Label per character, exactly one lit letter with a pulsing additive halo.
	var row: Node = menu.LogoRow
	_check(row != null and row is HBoxContainer, "MainMenu.LogoRow is %s, expected an HBoxContainer" % (row.get_class() if row != null else "null"))
	var title: String = menu.TitleText
	_check(title == "BLACKOUT", "MainMenu.TitleText='%s', expected 'BLACKOUT'" % title)
	if row != null:
		_check(row.get_child_count() == title.length(),
			"LogoRow has %d children, expected %d (one Label per character)" % [row.get_child_count(), title.length()])
		var built: String = ""
		var glow_holders: Array[int] = []
		for i in row.get_child_count():
			var letter: Node = row.get_child(i)
			if letter is Label:
				built += letter.text
			else:
				_check(false, "LogoRow child %d is a %s, expected Label" % [i, letter.get_class()])
			if letter.get_node_or_null("Glow") != null:
				glow_holders.append(i)
		_check(built == title, "the logo letters spell '%s', expected '%s'" % [built, title])
		_check(glow_holders.size() == 1, "%d letters carry a Glow child, expected exactly 1" % glow_holders.size())
		if glow_holders.size() == 1:
			_check(glow_holders[0] == menu.GlowLetterIndex,
				"the lit letter is index %d, expected GlowLetterIndex %d" % [glow_holders[0], menu.GlowLetterIndex])
			var lit: Node = row.get_child(glow_holders[0])
			_check(menu.GlowLetter == lit, "MainMenu.GlowLetter is not the letter carrying the halo")
			_check(lit.get_theme_color("font_color") == menu.GlowLetterColor,
				"the lit letter font_color is %s, expected GlowLetterColor %s" % [lit.get_theme_color("font_color"), menu.GlowLetterColor])
			var glow: Node = lit.get_node("Glow")
			_check(glow is TextureRect, "the Glow node is a %s, expected TextureRect" % glow.get_class())
			_check(glow.texture != null, "the Glow TextureRect has no texture (GlowTexture unset in the scene)")
			_check(glow.show_behind_parent == true, "Glow.show_behind_parent=%s, expected true" % glow.show_behind_parent)
			_check(glow.mouse_filter == MOUSE_FILTER_IGNORE, "Glow.mouse_filter=%d, expected %d (IGNORE)" % [glow.mouse_filter, MOUSE_FILTER_IGNORE])
			var mat: Material = glow.material
			_check(mat != null and mat.blend_mode == BLEND_MODE_ADD,
				"the Glow material is %s, expected an additive CanvasItemMaterial" % ("blend_mode %d" % mat.blend_mode if mat != null else "missing"))
			# The pulse is a looping Tween on modulate:a — sample it instead of trusting the setup.
			var a0: float = glow.modulate.a
			await _step(PULSE_FRAMES)
			_check(not is_equal_approx(glow.modulate.a, a0),
				"the halo alpha stayed at %.3f over %d frames — the pulse Tween is not running" % [a0, PULSE_FRAMES])
			_check(glow.modulate.a >= menu.GlowMinAlpha - ALPHA_TOL and glow.modulate.a <= menu.GlowMaxAlpha + ALPHA_TOL,
				"the halo alpha %.3f left [%s, %s]" % [glow.modulate.a, menu.GlowMinAlpha, menu.GlowMaxAlpha])

	# 3. Buttons: exact texts, «New Game» focused, the run entry point really exists.
	var button_texts: Dictionary = {"NewGameButton": "New Game", "SettingsButton": "Settings", "QuitButton": "Quit"}
	for export_name in button_texts:
		var b: Node = menu.get(export_name)
		_check(b != null and b is Button, "MainMenu.%s is %s, expected a Button" % [export_name, b.get_class() if b != null else "null"])
		if b != null and b is Button:
			_check(b.text == button_texts[export_name], "%s.text='%s', expected '%s'" % [export_name, b.text, button_texts[export_name]])
	_check(menu.NewGameButton.has_focus(), "«New Game» does not have focus — the menu is not usable without a mouse")
	_check(menu.NewGameScenePath == MAIN_PATH, "MainMenu.NewGameScenePath='%s', expected '%s'" % [menu.NewGameScenePath, MAIN_PATH])
	_check(load(menu.NewGameScenePath) != null, "MainMenu.NewGameScenePath '%s' does not load" % menu.NewGameScenePath)

	# 4. The nested settings screen: opened by the button, synced to the autoload, focus back on close.
	var settings: Node = menu.Settings
	_check(settings != null and settings.get_script() != null and str(settings.get_script().resource_path).ends_with("SettingsMenu.cs"),
		"MainMenu.Settings is not a SettingsMenu instance")
	if settings != null and settings.get("Root") != null:
		_check(settings.IsOpen == false, "the settings screen is open on a fresh menu")
		menu.SettingsButton.emit_signal("pressed")
		await _step(1)
		_check(settings.IsOpen == true, "«Settings» did not open the settings screen")
		_check(settings.BackButton.has_focus(), "«Back» does not have focus while the settings screen is open")
		_check(settings.FullscreenCheck.button_pressed == gset.Fullscreen,
			"the fullscreen checkbox is %s while GameSettings.Fullscreen=%s" % [settings.FullscreenCheck.button_pressed, gset.Fullscreen])
		_check(is_equal_approx(settings.VolumeSlider.value, gset.MasterVolume),
			"the volume slider is %s while GameSettings.MasterVolume=%s" % [settings.VolumeSlider.value, gset.MasterVolume])
		# The hotkey path into an open screen: F11 must move the checkbox, and the widget update
		# must not emit a second change back (acceptance criterion 8).
		var fs_before: bool = gset.Fullscreen
		var fs_events: Array = []
		gset.FullscreenChanged.connect(func(v: bool): fs_events.append(v))
		gset.ToggleFullscreen()
		await _step(1)
		_check(gset.Fullscreen != fs_before, "ToggleFullscreen() did not flip GameSettings.Fullscreen")
		_check(settings.FullscreenCheck.button_pressed == gset.Fullscreen,
			"the checkbox is %s after the hotkey while GameSettings.Fullscreen=%s" % [settings.FullscreenCheck.button_pressed, gset.Fullscreen])
		_check(fs_events.size() == 1, "FullscreenChanged fired %d times for one hotkey press, expected 1 (the widget update must not emit back)" % fs_events.size())
		gset.ToggleFullscreen()
		await _step(1)
		_check(settings.FullscreenCheck.button_pressed == fs_before, "the checkbox did not follow the second hotkey press")
		_check(fs_events.size() == 2, "FullscreenChanged fired %d times for two hotkey presses, expected 2" % fs_events.size())

		# The slider path: widget -> GameSettings -> master bus, and the value label
		# (acceptance criterion 9).
		var vol_before: float = gset.MasterVolume
		settings.VolumeSlider.value = VOLUME_TEST
		await _step(1)
		_check(is_equal_approx(gset.MasterVolume, VOLUME_TEST),
			"GameSettings.MasterVolume=%s after the slider moved to %s" % [gset.MasterVolume, VOLUME_TEST])
		_check(settings.VolumeValue.text == "50 %", "the volume label reads '%s', expected '50 %%'" % settings.VolumeValue.text)
		_check(absf(AudioServer.get_bus_volume_db(0) - linear_to_db(VOLUME_TEST)) <= DB_TOL,
			"the master bus is %.4f dB at slider %s, expected %.4f" % [AudioServer.get_bus_volume_db(0), VOLUME_TEST, linear_to_db(VOLUME_TEST)])
		settings.VolumeSlider.value = 0.0
		await _step(1)
		_check(AudioServer.is_bus_mute(0) == true, "the master bus is not muted with the slider at 0")
		_check(settings.VolumeValue.text == "0 %", "the volume label reads '%s' at 0, expected '0 %%'" % settings.VolumeValue.text)
		settings.VolumeSlider.value = vol_before
		await _step(1)
		_check(AudioServer.is_bus_mute(0) == false, "the master bus stayed muted after the slider came back to %s" % vol_before)

		settings.Close()
		await _step(1)
		_check(settings.IsOpen == false, "Close() left the settings screen open")
		_check(menu.SettingsButton.has_focus(), "focus did not return to «Settings» after the settings screen closed")

	# 5. «New Game»: Main becomes the current scene (not a child of the menu) with a full reserve,
	#    booted into the two painted sections.
	var menu_id: int = menu.get_instance_id()
	gs.Energy = START_ENERGY
	menu.NewGameButton.emit_signal("pressed")
	_check(is_equal_approx(gs.Energy, gs.MaxEnergy),
		"Energy=%s right after «New Game», expected MaxEnergy=%s (ResetRun)" % [gs.Energy, gs.MaxEnergy])
	var switched: int = await _watch_ms(func():
		var cs: Node = current_scene
		return cs != null and cs.get_instance_id() != menu_id, SCENE_CHANGE_CAP_MS)
	_check(switched >= 0, "the current scene did not change away from the menu within %d ms" % SCENE_CHANGE_CAP_MS)
	if switched < 0:
		_finish()
		return
	await _settle()
	var main: Node = current_scene
	_check(not is_instance_valid(menu), "the main menu is still alive after «New Game»")
	_check(main != null and main.name == "Main" and main.scene_file_path == MAIN_PATH,
		"after «New Game» the current scene is '%s', expected Main from %s" % [main.scene_file_path if main != null else "null", MAIN_PATH])
	if main == null:
		_finish()
		return
	_check(main.get_parent() == root, "Main is not a child of root — «New Game» must change the scene, not add a child")
	_check(main.get_script() != null and str(main.get_script().resource_path).ends_with("Main.cs"), "the new current scene has no Main.cs")
	var level: Node = main.get("CurrentLevel")
	_check(level != null and level.scene_file_path == LEVEL_PATH,
		"Main.CurrentLevel is %s, expected the two painted sections from %s" % [level.scene_file_path if level != null else "null", LEVEL_PATH])
	_check(is_equal_approx(gs.Energy, gs.MaxEnergy), "Energy=%s in the fresh run, expected MaxEnergy" % gs.Energy)

	# 6. The T-07 restart contract survives the menu: a restart reloads Main into a fresh level.
	if level != null:
		var main_id: int = main.get_instance_id()
		var level_id: int = level.get_instance_id()
		level.RestartLevel()
		var reloaded: int = await _watch_ms(func():
			var cs: Node = current_scene
			return cs != null and cs.get_instance_id() != main_id, SCENE_CHANGE_CAP_MS)
		_check(reloaded >= 0, "RestartLevel() did not reload Main within %d ms" % SCENE_CHANGE_CAP_MS)
		if reloaded >= 0:
			await _settle()
			var main2: Node = current_scene
			_check(main2 != null and main2.name == "Main" and main2.scene_file_path == MAIN_PATH,
				"after the restart the current scene is '%s', expected Main again" % (main2.name if main2 != null else "null"))
			if main2 != null:
				var level2: Node = main2.get("CurrentLevel")
				_check(level2 != null and level2.get_instance_id() != level_id and level2.scene_file_path == LEVEL_PATH,
					"after the restart the level is %s, expected a fresh Level00_Sections" % (level2.scene_file_path if level2 != null else "null"))
			_check(is_equal_approx(gs.Energy, gs.MaxEnergy), "Energy=%s after the restart, expected MaxEnergy" % gs.Energy)

	# 7. Teardown: nothing left running, the state reset, the player's own settings untouched.
	var cs_end: Node = current_scene
	current_scene = null
	if cs_end != null and is_instance_valid(cs_end):
		cs_end.queue_free()
	await _step(2)
	DirAccess.remove_absolute(PROBE_PATH)
	gset.ConfigPath = REAL_PATH
	gset.Load()
	var real_after: int = _stamp()
	_check(real_after == real_before, "the smoke run touched the player's own %s (modified %s -> %s)" % [REAL_PATH, real_before, real_after])
	gs.ResetRun()
	gs.CurrentScenePath = ""
	print("ui_menu: menu -> Main -> restart done in %d idle frames" % _frames)
	_finish()
