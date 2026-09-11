extends SceneTree
# Smoke: HUD energy bar (T-04) — HUD.tscn wiring (CanvasLayer 10 + HUD.cs, ProgressBar + Label
# exports, HudTheme.tres whose ProgressBar fill/background styleboxes are the ones the bar
# resolves, no percentage text, mouse ignore), binding to GameState (min/max/value/label after
# ResetRun), synchronous same-frame updates on Energy set / AddEnergy / ResetRun with the
# "ENERGY {0}" label built from Mathf.RoundToInt (banker's rounding: 32.5 -> 32, 33.5 -> 34,
# 0.5 -> 0 — the S1 regression), no label rebuild on a sub-unit change, Unbind()/Bind() API,
# _ExitTree/_EnterTree re-binding when the HUD is removed from and re-added to the tree (S2),
# no dangling EnergyChanged listener after the HUD is freed (an Energy change after the free must
# not throw — the runner fails on ERROR lines; C# `+=` subscribers are invisible to
# get_signal_connection_list, so this behavioural guard is the only one), the HUD instance in
# TestRoom (debug label moved to y=76) and the bar following the flashlight drain over 60 physics
# frames. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/ui_hud.gd

const NAME := "ui_hud"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls; headless
# runs ~2-3 process frames per physics tick, and a green run uses ~70 ticks.
const MAX_FRAMES := 3000
const HUD_LAYER := 10
const MOUSE_FILTER_IGNORE := 2   # Control.MOUSE_FILTER_IGNORE
const DEBUG_LABEL_TOP := 76.0
const DRAIN_FRAMES := 60
const DRAIN_TOL := 0.05

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

func _label_text(hud: Node) -> String:
	var label: Label = hud.get("EnergyLabel")
	if label == null:
		return "<no EnergyLabel>"
	return label.text

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	# 1. HUD.tscn wiring: CanvasLayer 10 + HUD.cs, exports, theme, styleboxes, no percentage,
	#    Root ignores the mouse.
	var scene: PackedScene = load("res://scenes/ui/HUD.tscn")
	_check(scene != null, "res://scenes/ui/HUD.tscn failed to load")
	if scene == null:
		_finish()
		return
	var hud: Node = scene.instantiate()
	root.add_child(hud)
	_check(hud is CanvasLayer, "HUD root is a %s, expected CanvasLayer" % hud.get_class())
	_check(hud.get_script() != null and str(hud.get_script().resource_path).ends_with("HUD.cs"),
		"HUD.tscn has no HUD.cs attached (did dotnet build run?)")
	if not (hud is CanvasLayer) or hud.get("EnergyBar") == null:
		_check(false, "HUD.EnergyBar export missing — C# script not attached, aborting")
		hud.queue_free()
		_finish()
		return
	_check(hud.layer == HUD_LAYER, "HUD.layer=%d, expected %d" % [hud.layer, HUD_LAYER])
	var bar_v = hud.get("EnergyBar")
	var label_v = hud.get("EnergyLabel")
	_check(bar_v is ProgressBar, "HUD.EnergyBar is a %s, expected ProgressBar" % (bar_v.get_class() if bar_v != null else "null"))
	_check(label_v is Label, "HUD.EnergyLabel is a %s, expected Label" % (label_v.get_class() if label_v != null else "null"))
	if not (bar_v is ProgressBar) or not (label_v is Label):
		_check(false, "HUD exports not wired — aborting")
		hud.queue_free()
		_finish()
		return
	var bar: ProgressBar = bar_v
	var label: Label = label_v
	_check(hud.LabelFormat == "ENERGY {0}", "HUD.LabelFormat default is '%s', expected 'ENERGY {0}' ({0} is the rounded int)" % hud.LabelFormat)
	_check(bar.show_percentage == false, "EnergyBar.show_percentage=%s, expected false" % bar.show_percentage)

	var root_ctl: Node = hud.get_node_or_null("Root")
	_check(root_ctl != null and root_ctl is Control, "HUD has no 'Root' Control child")
	if root_ctl != null and root_ctl is Control:
		_check(root_ctl.mouse_filter == MOUSE_FILTER_IGNORE,
			"Root.mouse_filter=%d, expected %d (IGNORE)" % [root_ctl.mouse_filter, MOUSE_FILTER_IGNORE])
		var theme: Theme = root_ctl.theme
		_check(theme != null, "Root.theme is null, expected HudTheme.tres")
		if theme != null:
			_check(str(theme.resource_path).ends_with("HudTheme.tres"),
				"Root.theme is '%s', expected .../HudTheme.tres" % theme.resource_path)
			_check(theme.has_stylebox("fill", "ProgressBar"), "HudTheme lacks ProgressBar 'fill' stylebox")
			_check(theme.has_stylebox("background", "ProgressBar"), "HudTheme lacks ProgressBar 'background' stylebox")
			# Identity, not type: Godot's default ProgressBar fill is a StyleBoxFlat too, so only
			# `==` with the theme's own resource proves HudTheme.tres reaches the bar.
			_check(bar.get_theme_stylebox("fill") == theme.get_stylebox("fill", "ProgressBar"),
				"EnergyBar 'fill' stylebox is not the HudTheme ProgressBar 'fill' resource (theme not propagated)")
			_check(bar.get_theme_stylebox("background") == theme.get_stylebox("background", "ProgressBar"),
				"EnergyBar 'background' stylebox is not the HudTheme ProgressBar 'background' resource (theme not propagated)")
			_check(label.get_theme_color("font_color") == theme.get_color("font_color", "Label"),
				"EnergyLabel font_color %s is not the HudTheme Label font_color %s" % [label.get_theme_color("font_color"), theme.get_color("font_color", "Label")])

	# 2. Bound to GameState at 100 after ResetRun + one frame.
	gs.ResetRun()
	await _step(1)
	_check(is_equal_approx(bar.min_value, gs.MinEnergy), "EnergyBar.min_value=%s, expected MinEnergy=%s" % [bar.min_value, gs.MinEnergy])
	_check(is_equal_approx(bar.max_value, gs.MaxEnergy), "EnergyBar.max_value=%s, expected MaxEnergy=%s" % [bar.max_value, gs.MaxEnergy])
	_check(is_equal_approx(bar.value, gs.Energy), "EnergyBar.value=%s after ResetRun, expected Energy=%s" % [bar.value, gs.Energy])
	_check(is_equal_approx(bar.value, 100.0), "EnergyBar.value=%s after ResetRun, expected 100" % bar.value)
	_check(is_equal_approx(hud.DisplayedEnergy, 100.0), "HUD.DisplayedEnergy=%s after ResetRun, expected 100" % hud.DisplayedEnergy)
	_check(label.text == "ENERGY 100", "EnergyLabel.text='%s' after ResetRun, expected 'ENERGY 100'" % label.text)

	# 3. Same-frame updates (no await between the set and the read).
	gs.Energy = 42.4
	_check(is_equal_approx(bar.value, 42.4), "EnergyBar.value=%s right after Energy=42.4, expected 42.4 (same frame)" % bar.value)
	_check(is_equal_approx(hud.DisplayedEnergy, 42.4), "HUD.DisplayedEnergy=%s after Energy=42.4, expected 42.4" % hud.DisplayedEnergy)
	_check(label.text == "ENERGY 42", "EnergyLabel.text='%s' after Energy=42.4, expected 'ENERGY 42'" % label.text)
	gs.AddEnergy(-10.0)
	_check(is_equal_approx(bar.value, 32.4), "EnergyBar.value=%s after AddEnergy(-10), expected 32.4" % bar.value)
	_check(label.text == "ENERGY 32", "EnergyLabel.text='%s' after AddEnergy(-10), expected 'ENERGY 32'" % label.text)
	gs.Energy = 32.6
	_check(is_equal_approx(bar.value, 32.6), "EnergyBar.value=%s after Energy=32.6, expected 32.6" % bar.value)
	_check(label.text == "ENERGY 33", "EnergyLabel.text='%s' after Energy=32.6, expected 'ENERGY 33' (rounding)" % label.text)
	# S1 regression: exact halves. The label is built from Mathf.RoundToInt (banker's rounding to
	# even), the same value that throttles rebuilds — one rule, so the text can never go stale.
	var half_cases: Array = [
		[32.5, "ENERGY 32"],   # 32.5 -> 32 (to even), was "33" with {0:0} and then stuck
		[32.4, "ENERGY 32"],
		[31.5, "ENERGY 32"],   # 31.5 -> 32 (to even)
		[33.5, "ENERGY 34"],   # 33.5 -> 34 (to even)
		[0.5, "ENERGY 0"],     # 0.5 -> 0 (to even), was "1"
		[0.0, "ENERGY 0"],     # lamp dead: still 0, never a stale "1"
		[1.0, "ENERGY 1"],
	]
	var observed: PackedStringArray = []
	for case in half_cases:
		var e: float = case[0]
		var want: String = case[1]
		gs.Energy = e
		_check(is_equal_approx(bar.value, e), "EnergyBar.value=%s after Energy=%s, expected %s" % [bar.value, e, e])
		_check(label.text == want, "EnergyLabel.text='%s' after Energy=%s, expected '%s' (banker's rounding)" % [label.text, e, want])
		observed.append("%s -> '%s'" % [e, label.text])
	print("ui_hud: half-rounding: %s" % ", ".join(observed))
	gs.ResetRun()
	_check(is_equal_approx(bar.value, 100.0), "EnergyBar.value=%s after ResetRun, expected 100" % bar.value)
	_check(label.text == "ENERGY 100", "EnergyLabel.text='%s' after ResetRun, expected 'ENERGY 100'" % label.text)
	# Sub-unit change: the bar follows, the label text is not rebuilt.
	gs.Energy = 32.4
	_check(label.text == "ENERGY 32", "EnergyLabel.text='%s' after Energy=32.4, expected 'ENERGY 32'" % label.text)
	var text_before: String = label.text
	gs.Energy = 32.45
	_check(is_equal_approx(bar.value, 32.45), "EnergyBar.value=%s after Energy=32.45, expected 32.45" % bar.value)
	_check(label.text == text_before, "EnergyLabel.text changed '%s' -> '%s' on a sub-unit change (32.4 -> 32.45)" % [text_before, label.text])

	# 4. Unbind()/Bind(): the bar ignores the state while unbound and catches up on rebind.
	hud.Unbind()
	var v_unbound: float = bar.value
	gs.Energy = 5.0
	_check(is_equal_approx(bar.value, v_unbound), "EnergyBar.value=%s after Unbind() and Energy=5, expected unchanged %s" % [bar.value, v_unbound])
	hud.Bind(gs)
	_check(is_equal_approx(bar.value, 5.0), "EnergyBar.value=%s after Bind(gs), expected 5" % bar.value)
	_check(label.text == "ENERGY 5", "EnergyLabel.text='%s' after Bind(gs), expected 'ENERGY 5'" % label.text)
	gs.Energy = 7.0
	_check(is_equal_approx(bar.value, 7.0), "EnergyBar.value=%s after rebind and Energy=7, expected 7 (bound again)" % bar.value)
	gs.ResetRun()
	_check(is_equal_approx(bar.value, 100.0), "EnergyBar.value=%s after ResetRun, expected 100" % bar.value)

	# 4b. Tree exit / re-entry (S2): _ExitTree unbinds — the bar freezes while the HUD is out of
	#     the tree — and _EnterTree re-binds a node that is already ready (Main re-parenting one HUD
	#     across level swaps), so the bar catches up on add_child and follows again afterwards.
	var v_out: float = bar.value
	root.remove_child(hud)
	gs.Energy = 61.0
	var v_while_out: float = bar.value
	_check(is_equal_approx(v_while_out, v_out),
		"EnergyBar.value=%s after remove_child and Energy=61, expected unchanged %s (_ExitTree must unbind)" % [v_while_out, v_out])
	root.add_child(hud)
	var v_readded: float = bar.value
	var text_readded: String = label.text
	_check(hud.is_inside_tree() and hud.is_node_ready(), "re-added HUD is not inside the tree / not ready")
	_check(is_equal_approx(v_readded, 61.0),
		"EnergyBar.value=%s right after add_child, expected 61 (_EnterTree must re-bind a ready node)" % v_readded)
	_check(text_readded == "ENERGY 61", "EnergyLabel.text='%s' right after add_child, expected 'ENERGY 61'" % text_readded)
	gs.Energy = 62.0
	_check(is_equal_approx(bar.value, 62.0), "EnergyBar.value=%s after re-add and Energy=62, expected 62 (bound again)" % bar.value)
	_check(label.text == "ENERGY 62", "EnergyLabel.text='%s' after re-add and Energy=62, expected 'ENERGY 62'" % label.text)
	print("ui_hud: re-entry: out of tree Energy=61 -> bar %.1f (was %.1f); add_child -> bar %.1f '%s'; Energy=62 -> bar %.1f '%s'" % [v_while_out, v_out, v_readded, text_readded, bar.value, label.text])
	await _step(1)
	_check(is_equal_approx(bar.value, 62.0), "EnergyBar.value=%s one frame after re-add, expected 62" % bar.value)
	gs.ResetRun()
	_check(is_equal_approx(bar.value, 100.0), "EnergyBar.value=%s after ResetRun, expected 100" % bar.value)

	# 5. Freeing the HUD leaves no listener behind. C# `+=` subscribers are managed delegates and
	#    never show up in get_signal_connection_list, so the guard is behavioural: an Energy change
	#    after the free must not throw (a dangling handler on a disposed node raises
	#    ObjectDisposedException, logged as an ERROR line the runner rejects).
	hud.queue_free()
	await _step(1)
	_check(not is_instance_valid(hud), "standalone HUD still valid one frame after queue_free()")
	gs.Energy = 55.0
	gs.ResetRun()
	await _step(1)

	# 6. TestRoom: the HUD instance, debug label at y=76, the bar shows the drain.
	var room_scene: PackedScene = load("res://scenes/levels/TestRoom.tscn")
	_check(room_scene != null, "res://scenes/levels/TestRoom.tscn failed to load")
	if room_scene == null:
		_finish()
		return
	var room: Node = room_scene.instantiate()
	root.add_child(room)
	var room_hud: Node = room.get_node_or_null("HUD")
	_check(room_hud != null, "TestRoom has no 'HUD' child")
	if room_hud == null or room_hud.get("EnergyBar") == null:
		_check(false, "TestRoom/HUD has no HUD.cs / EnergyBar — aborting")
		room.queue_free()
		_finish()
		return
	_check(room_hud.get_script() != null and str(room_hud.get_script().resource_path).ends_with("HUD.cs"),
		"TestRoom/HUD is not the HUD scene (script %s)" % (room_hud.get_script().resource_path if room_hud.get_script() != null else "null"))
	var room_bar_v = room_hud.get("EnergyBar")
	if not (room_bar_v is ProgressBar):
		_check(false, "TestRoom/HUD.EnergyBar is not a ProgressBar — aborting")
		room.queue_free()
		_finish()
		return
	var room_bar: ProgressBar = room_bar_v
	await _step(1)
	_check(is_equal_approx(room_bar.value, gs.Energy), "TestRoom/HUD bar=%s, expected Energy=%s" % [room_bar.value, gs.Energy])
	_check(_label_text(room_hud) == "ENERGY 100", "TestRoom/HUD label='%s', expected 'ENERGY 100'" % _label_text(room_hud))
	var dbg: Node = room.get_node_or_null("UI/DebugLabel")
	_check(dbg != null and dbg is Label, "TestRoom has no 'UI/DebugLabel' Label")
	if dbg != null and dbg is Label:
		_check(is_equal_approx(dbg.offset_top, DEBUG_LABEL_TOP),
			"UI/DebugLabel.offset_top=%s, expected %s (below the energy panel)" % [dbg.offset_top, DEBUG_LABEL_TOP])

	var lamp: Node = room.get_node_or_null("Player/Flashlight")
	_check(lamp != null and lamp.get("DrainPerSecond") != null, "TestRoom has no 'Player/Flashlight' with Flashlight.cs")
	if lamp != null and lamp.get("DrainPerSecond") != null:
		var ticks: float = float(Engine.physics_ticks_per_second)
		lamp.SetOn(true)
		_check(lamp.IsOn == true, "Flashlight.SetOn(true) left IsOn=%s" % lamp.IsOn)
		await _step(1)
		var v0: float = room_bar.value
		await _step(DRAIN_FRAMES)
		var expected_drop: float = DRAIN_FRAMES * lamp.DrainPerSecond / ticks
		var drop: float = v0 - room_bar.value
		_check(absf(drop - expected_drop) <= DRAIN_TOL,
			"HUD bar over %d drain frames: %.4f -> %.4f (drop %.4f), expected drop %.4f ± %.2f" % [DRAIN_FRAMES, v0, room_bar.value, drop, expected_drop, DRAIN_TOL])
		# ProgressBar (Range) snaps `value` to `step` (0.01 by default); the bar must track Energy
		# within that step and the step must stay sub-pixel on a 260 px bar.
		_check(room_bar.step <= 0.01, "EnergyBar.step=%s, expected <= 0.01 (coarser steps make the bar visibly lag Energy)" % room_bar.step)
		_check(absf(room_bar.value - gs.Energy) <= room_bar.step,
			"HUD bar=%.4f after the drain, expected Energy=%.4f within step %s" % [room_bar.value, gs.Energy, room_bar.step])
		_check(_label_text(room_hud) == "ENERGY %d" % roundi(gs.Energy),
			"HUD label='%s' after the drain, expected 'ENERGY %d'" % [_label_text(room_hud), roundi(gs.Energy)])
		print("ui_hud: drain on the bar %.4f -> %.4f over %d frames (drop %.4f, expected %.4f), Energy %.4f, label '%s'" % [v0, room_bar.value, DRAIN_FRAMES, drop, expected_drop, gs.Energy, _label_text(room_hud)])
		lamp.SetOn(false)
		await _step(1)

	# 7. Teardown: reset the state, free the room, a later Energy change must not reach the freed
	#    HUD (same behavioural guard as step 5: no ERROR line).
	gs.ResetRun()
	room.queue_free()
	await _step(1)
	_check(not is_instance_valid(room_hud), "TestRoom/HUD still valid one frame after freeing the room")
	gs.Energy = 55.0
	gs.ResetRun()
	_finish()
