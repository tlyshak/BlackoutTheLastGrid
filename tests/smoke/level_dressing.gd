extends SceneTree
# Smoke: the prologue's dressing and the combat feedback it brings (T-07i-c). Headless has no
# graphics, so this asserts structure, flags, budgets and lifetimes — never particle counts,
# which the dummy renderer does not simulate.
#   * depth contract — the visual brief's z_index table on the existing background nodes and on
#     the new Parallax / Backdrop / Ground / Props / Fx_<Room> / Foreground groups, Props y-sorted;
#   * parallax — three background Parallax2D layers with distinct scroll_scale ordered by depth,
#     a foreground layer that outruns the camera, nobody ignoring the camera;
#   * bottom coverage — Ground/PH_NearBand spans the level and reaches past the camera's
#     limit_bottom, so no engine clear colour is left on screen;
#   * frame budget — the emitter and light census of the whole level, every light shadowless;
#   * room gating — RoomBounds.Fx: only the active room's emitters run, the rest are stopped and
#     out of the process loop, and the panel sparks (group "fx_manual") are never switched on by
#     the gating because the level itself owns them;
#   * ImpactFx — Play() emits and lights, the node frees itself on its guard timer (the only path
#     headless has), stays alive while the tree is paused and goes right after unpausing, and
#     nothing ever touches Engine.time_scale;
#   * LevelBase.ShakeCamera — offset moves, ends at exactly (0, 0), never touches the limits, and
#     a level freed mid-shake errors on nothing;
#   * camera lookahead — leads the hero in his direction of travel and returns to him on release;
#   * Player.Landed — emitted exactly once, on the step Height returns to 0;
#   * prompt forwarding moved into LevelBase — TestRoom has no prompt code of its own any more.
# Run: godot --headless --path . -s tests/smoke/level_dressing.gd

const NAME := "level_dressing"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s).
const MAX_FRAMES := 6000
const PROLOGUE_PATH := "res://scenes/levels/Level00_Prologue.tscn"
const TESTROOM_PATH := "res://scenes/levels/TestRoom.tscn"
const IMPACT_PATH := "res://scenes/fx/ImpactFx.tscn"
const SETTLE_CAP := 20          # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05      # process delta (s) below which the loop is back to normal pacing
const OVERLAP_FRAMES := 4       # physics frames for Area2D overlaps to refresh after a teleport
# Depth table — docs/plans/t07i-visual-kit/visual-brief.md, "Шари глибини".
const Z_BACKDROP := -40
const Z_GROUND := -20
const Z_FX := 20
const Z_FOREGROUND := 40
const ROOM_NAMES := ["Face", "Flood", "Gas", "Upper", "Cage", "Surface"]
const BACKDROP_NODES := ["PH_Wall_Face", "PH_Wall_Flood", "PH_Wall_Gas", "PH_Wall_Upper", "PH_Wall_Cage", "PH_Wall_Surface", "PH_Ceiling", "Backdrop"]
const GROUND_NODES := ["PH_Floor_Face", "PH_Floor_Flood", "PH_Floor_Gas", "PH_Floor_Upper", "PH_Floor_Cage", "PH_Floor_Surface", "PH_FloorEdge", "PH_Decals", "Ground"]
const FX_GROUPS := ["Fx_Face", "Fx_Flood", "Fx_Gas", "Fx_Upper", "Fx_Cage", "Fx_Surface"]
const PARALLAX_LAYERS := ["Parallax/PxRockFar", "Parallax/PxRockMid", "Parallax/PxStruct"]
const LEVEL_WIDTH := 13440.0    # six rooms of the rebuilt prologue (T-07s-b)
const CAMERA_LIMIT_BOTTOM := 1080.0
# Frame budget (plan, "Performance & frame budget"). The caps that matter are per screen, not per
# level: only one room's ambient FX group runs at a time, and only one room's lights are ever in
# view. The whole-level totals are kept as a ceiling so a runaway census is still caught.
const MAX_EMITTERS := 24        # 6 ambient groups + the one-shot bursts of the piles, pockets and falls
const MAX_FX_EMITTERS := 3      # ambient emitters per room group
const MAX_PARTICLE_AMOUNT := 32
const MAX_LIGHTS := 30
const MAX_ROOM_LIGHTS := 12     # lights standing inside one room's rect — the on-screen peak
const PROCESS_DISABLED := 4     # Node.PROCESS_MODE_DISABLED
const PROCESS_INHERIT := 0
const STAGE_BLAST := 2          # Level00_Prologue.Stage.Blast (C# enums arrive as int)
const MANUAL_FX_GROUP := "fx_manual"
# Shake.
const SHAKE_AMPLITUDE := 10.0
const SHAKE_DURATION := 0.2
const SHAKE_START_FRAMES := 3   # idle frames for the first non-zero offset
const SHAKE_SETTLE_MS := 600    # real ms after which the shake must be exactly zero again
# ImpactFx lifetime, in real ms on top of Lifetime + FreeMargin.
const FREE_MARGIN_MS := 350
# Lookahead.
const LOOKAHEAD_HOLD := 60      # physics frames of holding move_right
const LOOKAHEAD_RELEASE := 110  # physics frames after the release
const LOOKAHEAD_MIN_FRACTION := 0.4
const LOOKAHEAD_REST_TOL := 3.0
# Jump / landing.
const JUMP_CAP := 90            # physics frames for a full jump (~51 at the defaults)
const OUTLET_REACH := Vector2(330, 560)
const AWAY_FROM_PROPS := Vector2(900, 560)
const OUTLET_PROMPT := "E: Charge"

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

# Instantiating a level is heavy; the next iteration runs several physics steps back-to-back.
# Wait until the process delta is normal again (same helper as level_prologue.gd).
func _settle() -> void:
	for i in SETTLE_CAP:
		await process_frame
		if root.get_process_delta_time() < SETTLE_DELTA:
			return

# Real-time wait that a paused tree and a hit-stop cannot stretch.
func _wait_ms(ms: int) -> void:
	await create_timer(ms / 1000.0, true, false, true).timeout

func _release_all() -> void:
	for a in ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "interact", "flashlight"]:
		Input.action_release(a)

func _finish() -> void:
	_release_all()
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

func _collect(node: Node, type_name: StringName, out: Array) -> void:
	if node.is_class(type_name):
		out.append(node)
	for child in node.get_children():
		_collect(child, type_name, out)

func _impact_fx_count(parent: Node) -> int:
	var n := 0
	for child in parent.get_children():
		var script: Variant = child.get_script()
		if script != null and str(script.resource_path).ends_with("ImpactFx.cs"):
			n += 1
	return n

func _emitters_of(group: Node) -> Array:
	var out: Array = []
	_collect(group, &"GPUParticles2D", out)
	return out

func _run() -> void:
	await _check_prologue()
	await _check_impact_fx()
	await _check_test_room()
	_finish()

# ---------------------------------------------------------------- the dressed prologue
func _check_prologue() -> void:
	var scene: PackedScene = load(PROLOGUE_PATH)
	_check(scene != null, "%s failed to load" % PROLOGUE_PATH)
	if scene == null:
		return
	var level: Node2D = scene.instantiate()
	root.add_child(level)
	await _settle()

	# 1. Depth contract (acceptance criteria 1-2).
	for path in BACKDROP_NODES:
		var n: Node = level.get_node_or_null(path)
		_check(n != null and n.get("z_index") == Z_BACKDROP,
			"%s z_index is %s, expected %d" % [path, n.get("z_index") if n != null else "missing", Z_BACKDROP])
	for path in GROUND_NODES:
		var n2: Node = level.get_node_or_null(path)
		_check(n2 != null and n2.get("z_index") == Z_GROUND,
			"%s z_index is %s, expected %d" % [path, n2.get("z_index") if n2 != null else "missing", Z_GROUND])
	for path in FX_GROUPS:
		var n3: Node = level.get_node_or_null(path)
		_check(n3 != null and n3.get("z_index") == Z_FX,
			"%s z_index is %s, expected %d" % [path, n3.get("z_index") if n3 != null else "missing", Z_FX])
	var props: Node = level.get_node_or_null("Props")
	_check(props != null, "the level has no Props group")
	if props != null:
		_check(props.get("z_index") == 0, "Props z_index is %s, expected 0 (the gameplay plane)" % props.get("z_index"))
		# A non-y-sorted group would be drawn as one unit at its own Y and would repeat the
		# PH_LitFloor bug fixed in the T-07 review (S4).
		_check(props.get("y_sort_enabled") == true, "Props.y_sort_enabled is false; the props would sort as one block")
		var solid := 0
		for child in props.get_children():
			if child.get_node_or_null("Blocker") != null:
				solid += 1
		_check(props.get_child_count() >= 12, "Props holds %d props, expected at least 12" % props.get_child_count())
		_check(solid >= 1, "no prop carries a Blocker; a cart standing on the walk band must not be walkable through")

	# 2. Parallax (acceptance criterion 1).
	var scales: Array[float] = []
	var depths: Array[int] = []
	for path in PARALLAX_LAYERS:
		var layer: Node = level.get_node_or_null(path)
		_check(layer != null and layer.is_class("Parallax2D"), "%s is %s, expected a Parallax2D" % [path, layer])
		if layer == null or not layer.is_class("Parallax2D"):
			continue
		var z: int = layer.z_index
		var sx: float = layer.scroll_scale.x
		_check(z <= -60 and z >= -100, "%s z_index %d, expected between -100 and -60" % [path, z])
		_check(sx > 0.0 and sx < 1.0, "%s scroll_scale.x %s, expected strictly inside (0, 1)" % [path, sx])
		_check(layer.ignore_camera_scroll == false, "%s ignores the camera scroll" % path)
		scales.append(sx)
		depths.append(z)
	_check(scales.size() == PARALLAX_LAYERS.size(), "only %d of %d parallax layers are usable" % [scales.size(), PARALLAX_LAYERS.size()])
	for i in range(1, scales.size()):
		_check(depths[i] > depths[i - 1] and scales[i] > scales[i - 1],
			"parallax layer %d (z %d, scale %s) does not sit in front of layer %d (z %d, scale %s)"
				% [i, depths[i], scales[i], i - 1, depths[i - 1], scales[i - 1]])
	var fg: Node = level.get_node_or_null("Foreground")
	_check(fg != null and fg.is_class("Parallax2D"), "Foreground is %s, expected a Parallax2D" % fg)
	if fg != null and fg.is_class("Parallax2D"):
		_check(fg.z_index == Z_FOREGROUND, "Foreground z_index %d, expected %d" % [fg.z_index, Z_FOREGROUND])
		_check(fg.scroll_scale.x > 1.0, "Foreground scroll_scale.x %s, expected > 1 (it must outrun the camera)" % fg.scroll_scale.x)
		_check(fg.ignore_camera_scroll == false, "Foreground ignores the camera scroll")

	# 3. Bottom of the screen is covered (acceptance criterion 3).
	var band: Node2D = level.get_node_or_null("Ground/PH_NearBand")
	_check(band is Polygon2D, "Ground/PH_NearBand is %s, expected a Polygon2D" % band)
	if band is Polygon2D:
		var poly: PackedVector2Array = (band as Polygon2D).polygon
		var min_x := INF
		var max_x := -INF
		var min_y := INF
		var max_y := -INF
		for p in poly:
			var g: Vector2 = band.global_position + p
			min_x = minf(min_x, g.x)
			max_x = maxf(max_x, g.x)
			min_y = minf(min_y, g.y)
			max_y = maxf(max_y, g.y)
		_check(min_x <= 0.0 and max_x >= LEVEL_WIDTH, "PH_NearBand spans x %s..%s, expected 0..%s" % [min_x, max_x, LEVEL_WIDTH])
		_check(min_y <= 604.0, "PH_NearBand starts at y %s, expected the floor edge at 604 or above" % min_y)
		_check(max_y >= CAMERA_LIMIT_BOTTOM, "PH_NearBand ends at y %s, expected at least the camera's limit_bottom %s" % [max_y, CAMERA_LIMIT_BOTTOM])

	# 4. Frame budget (acceptance criterion 5). The level is six rooms wide now, so the budget that
	#    decides the frame is per room: at most MAX_FX_EMITTERS ambient emitters in the one group
	#    that runs, and at most MAX_ROOM_LIGHTS lights standing inside one room's rect.
	var emitters: Array = _emitters_of(level)
	_check(emitters.size() <= MAX_EMITTERS, "the level holds %d GPUParticles2D, budget is %d" % [emitters.size(), MAX_EMITTERS])
	for e in emitters:
		_check(e.amount <= MAX_PARTICLE_AMOUNT, "%s emits %d particles, budget is %d per emitter" % [e.name, e.amount, MAX_PARTICLE_AMOUNT])
	for path in FX_GROUPS:
		var group: Node = level.get_node_or_null(path)
		if group != null:
			var own: Array = _emitters_of(group)
			_check(own.size() <= MAX_FX_EMITTERS, "%s runs %d ambient emitters, budget is %d per room" % [path, own.size(), MAX_FX_EMITTERS])
	var lights: Array = []
	_collect(level, &"Light2D", lights)
	_check(lights.size() <= MAX_LIGHTS, "the level holds %d Light2D, budget is %d" % [lights.size(), MAX_LIGHTS])
	for l in lights:
		_check(l.shadow_enabled == false, "%s has shadows enabled; shadowed lights are out of budget" % l.name)
	for room_name in ROOM_NAMES:
		var room: Node = level.get_node_or_null("Rooms/Room_" + room_name)
		_check(room != null, "the level has no Rooms/Room_%s" % room_name)
		if room == null:
			continue
		# Uniform walk band: every gate in the level is cut 320 px deep for 300..600, so a room that
		# moved its band would re-open the depth bypass T-07s-a's review had to close.
		_check(is_equal_approx(room.FloorTop, 300.0) and is_equal_approx(room.FloorBottom, 600.0),
			"Room_%s's walk band is %s..%s, expected 300..600 in every room" % [room_name, room.FloorTop, room.FloorBottom])
		var rect: Rect2 = room.Rect
		var here := 0
		for l2 in lights:
			var x: float = l2.global_position.x
			if x >= rect.position.x and x < rect.end.x:
				here += 1
		_check(here <= MAX_ROOM_LIGHTS, "Room_%s holds %d Light2D, the on-screen budget is %d" % [room_name, here, MAX_ROOM_LIGHTS])

	# 5. Vignette (acceptance criterion 12).
	var vignette: Node = level.get_node_or_null("Vignette")
	_check(vignette is CanvasLayer, "the level has no Vignette CanvasLayer")
	if vignette is CanvasLayer:
		var lay: int = (vignette as CanvasLayer).layer
		_check(lay > 0 and lay < 10, "Vignette.layer %d, expected between 1 and 9 (below the HUD at 10)" % lay)
		var rect: Node = vignette.get_node_or_null("PH_Vignette")
		_check(rect is TextureRect and (rect as TextureRect).mouse_filter == Control.MOUSE_FILTER_IGNORE,
			"Vignette/PH_Vignette is %s / mouse_filter %s, expected a mouse-transparent TextureRect" % [rect, rect.get("mouse_filter") if rect != null else null])
		_check(rect != null and rect.get("texture") != null, "Vignette/PH_Vignette has no texture")

	# 6. Per-room FX gating (acceptance criterion 4). Six rooms, six groups, one active at a time —
	#    ApplyRoomBounds is exactly what crossing a Checkpoint ends in (Level00_Prologue's room
	#    transitions), so the gating is exercised without replaying the flow; level_prologue.gd
	#    already covers the walk itself.
	var groups: Array = []
	var wired := true
	for i in ROOM_NAMES.size():
		var group: Node = level.get_node_or_null("Fx_" + ROOM_NAMES[i])
		var room: Node = level.get_node_or_null("Rooms/Room_" + ROOM_NAMES[i])
		_check(group != null and room != null, "the level lacks Fx_%s / Rooms/Room_%s" % [ROOM_NAMES[i], ROOM_NAMES[i]])
		if group == null or room == null:
			wired = false
			break
		_check(room.get("Fx") == group, "Room_%s.Fx does not point at Fx_%s — two rooms sharing one group would strand its emitters" % [ROOM_NAMES[i], ROOM_NAMES[i]])
		groups.append(group)
	if wired:
		# No two rooms may look at the same group (the rename trap the plan calls out).
		for i in groups.size():
			for j in range(i + 1, groups.size()):
				_check(groups[i] != groups[j], "Room_%s and Room_%s share one Fx group" % [ROOM_NAMES[i], ROOM_NAMES[j]])
		for i in groups.size():
			_check_fx_state(groups[i], i == 0, "%s at start" % ROOM_NAMES[i])
		for target in [1, 2, 5, 0]:
			level.ApplyRoomBounds(level.get_node("Rooms/Room_" + ROOM_NAMES[target]))
			await _step(1)
			for i in groups.size():
				_check_fx_state(groups[i], i == target, "%s while the hero is in %s" % [ROOM_NAMES[i], ROOM_NAMES[target]])
		# The blast sparks belong to the level, not to the gating: they stay off until the roof
		# comes down, and the gating must never switch them on with the rest of room 1.
		var sparks: Node = level.get_node_or_null("Fx_Face/BlastSparks")
		_check(sparks != null and sparks.is_in_group(MANUAL_FX_GROUP), "Fx_Face/BlastSparks is not in the '%s' group" % MANUAL_FX_GROUP)
		_check(sparks != null and sparks.emitting == false, "BlastSparks started emitting when Room_Face became active")
		_check(level.get("BlastSparks") == sparks, "Level00_Prologue.BlastSparks export does not point at Fx_Face/BlastSparks")
		var spark_light: Node = level.get_node_or_null("Fx_Face/BlastSparkLight")
		_check(spark_light != null and spark_light.enabled == false, "BlastSparkLight is on before the blast")
		_check(level.get("BlastSparkLight") == spark_light, "Level00_Prologue.BlastSparkLight export does not point at Fx_Face/BlastSparkLight")
		# A disabled FX group must never take a body out of the physics space.
		var bodies: Array = []
		for g in groups:
			_collect(g, &"CollisionObject2D", bodies)
		_check(bodies.is_empty(), "an Fx group holds %d CollisionObject2D; disabling the group would remove them from physics" % bodies.size())

		# The level, not the gating, ignites them: CaveIn.Triggered is exactly what crossing the
		# blast trigger emits, and the station lighting dies in the same handler.
		var blast: Node = level.get("BlastCollapse")
		var lamps: Node = level.get("WorkLamps")
		_check(blast != null and lamps != null, "the level lacks BlastCollapse / WorkLamps")
		if blast != null and lamps != null and sparks != null and spark_light != null:
			_check(lamps.visible == true, "the station lighting is already out before the blast")
			blast.emit_signal("Triggered")
			await _step(1)
			_check(level.CurrentStage == STAGE_BLAST,
				"after CaveIn_Blast.Triggered the stage is %s, expected Blast (%d)" % [level.CurrentStage, STAGE_BLAST])
			_check(sparks.emitting == true, "the torn cable does not spark after the blast")
			_check(spark_light.enabled == true, "the blast sparks have no light")
			_check(lamps.visible == false, "the station lighting survived the blast")

	# 7. Camera shake (acceptance criterion 7).
	var camera: Camera2D = level.get_node_or_null("Camera2D")
	_check(camera != null, "the prologue has no Camera2D")
	if camera != null:
		var limits := [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]
		level.ShakeCamera(SHAKE_AMPLITUDE, SHAKE_DURATION)
		var moved := false
		for i in SHAKE_START_FRAMES:
			await process_frame
			if camera.offset != Vector2.ZERO:
				moved = true
		_check(moved, "Camera.offset stayed (0, 0) after ShakeCamera(%s, %s)" % [SHAKE_AMPLITUDE, SHAKE_DURATION])
		_check([camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom] == limits,
			"the shake changed the camera limits (a WaveSpawner lock would break)")
		await _wait_ms(SHAKE_SETTLE_MS)
		await process_frame
		_check(camera.offset == Vector2.ZERO, "Camera.offset is %s after the shake ran out, expected exactly (0, 0)" % camera.offset)
		# Freeing the level while a shake is running must not error (the runner fails on ERROR:).
		level.ShakeCamera(SHAKE_AMPLITUDE, SHAKE_DURATION)
		await process_frame

	level.queue_free()
	await _step(2)

func _check_fx_state(group: Node, active: bool, label: String) -> void:
	var expected_mode: int = PROCESS_INHERIT if active else PROCESS_DISABLED
	_check(group.process_mode == expected_mode,
		"%s: %s.process_mode is %s, expected %s" % [label, group.name, group.process_mode, expected_mode])
	for e in _emitters_of(group):
		if e.is_in_group(MANUAL_FX_GROUP):
			continue   # driven by the level itself, never by the gating
		_check(e.emitting == active, "%s: %s.emitting is %s, expected %s" % [label, e.name, e.emitting, active])

# ---------------------------------------------------------------- impact effect lifetime
func _check_impact_fx() -> void:
	var scene: PackedScene = load(IMPACT_PATH)
	_check(scene != null, "%s failed to load" % IMPACT_PATH)
	if scene == null:
		return

	var fx: Node2D = scene.instantiate()
	root.add_child(fx)
	await process_frame
	_check(fx.get_script() != null and str(fx.get_script().resource_path).ends_with("ImpactFx.cs"),
		"ImpactFx.tscn has no ImpactFx.cs attached (did dotnet build run?)")
	_check(fx.z_index == Z_FX, "ImpactFx z_index %d, expected %d" % [fx.z_index, Z_FX])
	var sparks: Node = fx.get("Sparks")
	var flash: Node = fx.get("Flash")
	_check(sparks is GPUParticles2D and flash is PointLight2D, "ImpactFx exports Sparks/Flash are %s / %s" % [sparks, flash])
	if sparks == null or flash == null:
		fx.queue_free()
		return
	_check(sparks.one_shot == true, "ImpactFx/Sparks is not one_shot; the burst would never end")
	_check(flash.shadow_enabled == false, "ImpactFx/Flash casts shadows")
	_check(flash.enabled == false, "ImpactFx/Flash is lit before Play()")

	var life: float = fx.get("Lifetime")
	var margin: float = fx.get("FreeMargin")
	fx.Play(12, 1.0)
	await process_frame
	_check(sparks.emitting == true, "ImpactFx.Play() did not start the burst")
	_check(flash.enabled == true, "ImpactFx.Play() did not light the flash")
	_check(sparks.amount == 12, "ImpactFx.Play(12, 1) set amount %d, expected 12" % sparks.amount)
	await _wait_ms(int((life + margin) * 1000.0) + FREE_MARGIN_MS)
	await process_frame
	_check(not is_instance_valid(fx), "ImpactFx survived %.2f s; the guard timer must free it (headless never emits Finished)" % (life + margin))

	# Paused: the effect must hold, not leak and not vanish.
	var fx2: Node2D = scene.instantiate()
	root.add_child(fx2)
	await process_frame
	paused = true
	fx2.Play(12, 1.0)
	await _wait_ms(int((life + margin) * 1000.0) + FREE_MARGIN_MS)
	_check(is_instance_valid(fx2), "ImpactFx freed itself while the game was paused")
	paused = false
	await _wait_ms(int((life + margin) * 1000.0) + FREE_MARGIN_MS)
	await process_frame
	_check(not is_instance_valid(fx2), "ImpactFx did not free itself after the pause was lifted")
	_check(Engine.time_scale == 1.0, "Engine.time_scale is %s after the impact effects, expected 1" % Engine.time_scale)

# ---------------------------------------------------------------- LevelBase in TestRoom
func _check_test_room() -> void:
	var scene: PackedScene = load(TESTROOM_PATH)
	_check(scene != null, "%s failed to load" % TESTROOM_PATH)
	if scene == null:
		return
	var room: Node2D = scene.instantiate()
	root.add_child(room)
	await _settle()

	var player: Node2D = room.get_node_or_null("Player")
	var camera: Camera2D = room.get_node_or_null("Camera2D")
	var hud: Node = room.get_node_or_null("HUD")
	var level_fx: Node = room.get_node_or_null("LevelFx")
	_check(player != null and camera != null and hud != null, "TestRoom lacks Player / Camera2D / HUD")
	_check(level_fx != null and str(level_fx.get_script().resource_path).ends_with("LevelFx.cs"),
		"TestRoom has no LevelFx node — combat feedback cannot be exercised in the combat scene")
	if level_fx != null:
		_check(level_fx.get("Level") == room and level_fx.get("Player") == player, "LevelFx is not wired to the room and the hero")
		_check(level_fx.get("ImpactFxScene") != null, "LevelFx has no ImpactFxScene")
	if player == null or camera == null or hud == null:
		room.queue_free()
		return

	# The prompt format really moved to LevelBase and is still reachable from the scene.
	_check(room.get("PromptFormat") == "E: {0}", "TestRoom.PromptFormat is %s, expected the inherited 'E: {0}'" % room.get("PromptFormat"))
	_check(room.get("CameraLookahead") != null and room.get("CameraLookaheadSpeed") != null, "LevelBase lookahead exports missing")

	# The enemies (and the wave the hero would trigger by walking east) knock him about
	# mid-measurement; this part of the test is about the camera and the jump, not about combat.
	for enemy_name in ["Guard", "Dummy", "Dummy2", "WaveSpawner"]:
		var e: Node = room.get_node_or_null(enemy_name)
		if e != null:
			e.process_mode = PROCESS_DISABLED

	# 1. Prompt forwarding, now owned by LevelBase (acceptance criterion 10).
	player.global_position = OUTLET_REACH
	await _step(OVERLAP_FRAMES)
	_check(hud.PromptText == OUTLET_PROMPT, "next to the outlet the HUD shows '%s', expected '%s'" % [hud.PromptText, OUTLET_PROMPT])
	player.global_position = AWAY_FROM_PROPS
	await _step(OVERLAP_FRAMES)
	_check(hud.PromptText == "", "away from every prop the HUD still shows '%s'" % hud.PromptText)

	# 2. Camera lookahead (acceptance criterion 8).
	var lookahead: float = room.get("CameraLookahead")
	await _step(2)
	Input.action_press("move_right")
	await _step(LOOKAHEAD_HOLD)
	var lead: float = camera.global_position.x - player.global_position.x
	Input.action_release("move_right")
	_check(lead > lookahead * LOOKAHEAD_MIN_FRACTION and lead <= lookahead + 1.0,
		"walking right the camera leads the hero by %.1f px, expected between %.1f and %.1f"
			% [lead, lookahead * LOOKAHEAD_MIN_FRACTION, lookahead + 1.0])
	await _step(LOOKAHEAD_RELEASE)
	var rest: float = camera.global_position.x - player.global_position.x
	_check(absf(rest) <= LOOKAHEAD_REST_TOL, "standing still the camera is %.1f px off the hero, expected within %.1f" % [rest, LOOKAHEAD_REST_TOL])

	# 3. Player.Landed (acceptance criterion 9).
	var landings: Array = []
	var heights: Array = []
	var spawned: Array = []
	# LevelFx connected in its own _Ready, so its handler has already run when this one does:
	# the landing dust puff must be in the tree by now (acceptance criterion 5 / M5).
	player.Landed.connect(func(): landings.append(1); heights.append(player.Height); spawned.append(_impact_fx_count(room)))
	_check(_impact_fx_count(room) == 0, "an ImpactFx is in the room before anything happened")
	await _step(2)
	Input.action_press("jump")
	await _step(2)
	Input.action_release("jump")
	var airborne_seen := false
	for i in JUMP_CAP:
		await physics_frame
		if player.Height > 0.0:
			airborne_seen = true
		elif airborne_seen:
			break
	await _step(3)
	_check(airborne_seen, "the hero never left the ground — the landing check would pass vacuously")
	_check(landings.size() == 1, "Player.Landed fired %d times for one jump, expected exactly 1" % landings.size())
	if not heights.is_empty():
		_check(is_equal_approx(heights[0], 0.0), "Player.Landed fired at Height %s, expected 0" % heights[0])
	if not spawned.is_empty():
		_check(spawned[0] >= 1, "LevelFx spawned no ImpactFx on landing — the dust puff is not wired")
	else:
		_check(false, "no landing was observed, so the LevelFx spawn could not be checked")

	_release_all()
	room.queue_free()
	await _step(2)
