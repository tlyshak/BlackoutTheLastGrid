extends SceneTree
# Smoke: the v2 prologue is wired to the v2 art (T-V2-01 integration step, GAME_DESIGN §6a).
# scenes/v2/levels/Level00_Prologue.tscn must
#   * instance the v2 actors: Player, Dan and Patrol/Guard_1..3 come from scenes/v2/actors/*
#     (no Visual/Rig, a null Rig export, a Sprite with SpriteFrames) and GuardWave.EnemyScene is
#     the v2 guard, so the wave does not spawn v1 rigs into the drawn mine;
#   * carry the three painted room backdrops under Backgrounds (not y-sorted) at the room x of the
#     v3 map — Face 0, Drift 2880, Patrol 5760 — each built with its Back/Mid/Floor layers;
#   * have no v1 dressing left in the three mine rooms: the PH_ walls/floors/supports/conveyor/coal/
#     cage shaft, the rock Parallax, the Backdrop/Ground/Props/Foreground decoration (everything
#     under Backdrop and Ground now lies at x >= 8640, every Props child either carries a Blocker
#     collision or stands in Room_Surface), the hidden PH_Wall_Face|Drift|Patrol tones;
#   * keep what is light, decal, collision or Room_Surface: Darkness, Vignette, the hero's lamp,
#     LitZone_*, PH_Decals (after Backgrounds in the tree, z -20), the lamps, landmarks, jam carts,
#     crate stack, Fx_*, the physical walls, the surface room's dressing plus an opaque PH_Sky_Surface
#     above the Patrol far layer, and Foreground/PH_NearLip starting at the drawn floor's bottom edge;
#   * run the camera at zoom 1.5 from y 450: a 1280x720 world window (90…810) inside the limits,
#     the walk band 300…600 and the drawn floor edge 380 inside it;
#   * stage the capture with Sprite2Ds: HeldGuards/Overseer|PH_Guard_A|PH_Guard_B show the guard
#     sheet's `stance` region (assets/art/v2/keyframes/guard_keyframes.frames.json x svg/scale 2) at
#     scale 0.5 with the feet on the node origin, PH_Gun keeps its world size, PH_HeldLamp stays,
#     and the group is exported as HeldGuards and hidden until the Held stage.
# The v1/v2 parity of everything else is v2_level_skeleton.gd; the play-through is v2_level_prologue*.gd.
# Run: godot --headless --path . -s tests/smoke/v2_prologue_integration.gd

const NAME := "v2_prologue_integration"   # must equal the file basename
const MAX_FRAMES := 600
const PROLOGUE_V2 := "res://scenes/v2/levels/Level00_Prologue.tscn"
const PLAYER_V2 := "res://scenes/v2/actors/Player.tscn"
const COMPANION_V2 := "res://scenes/v2/actors/Companion.tscn"
const GUARD_V2 := "res://scenes/v2/actors/Guard.tscn"
const GUARD_SHEET := "res://assets/art/v2/keyframes/guard_keyframes.svg"
const GUARD_FRAMES_JSON := "res://assets/art/v2/keyframes/guard_keyframes.frames.json"
const SHEET_SCALE := 2.0                 # svg/scale of guard_keyframes.svg.import
const HELD_POSE := "stance"
const HELD_SCALE := Vector2(0.5, 0.5)
const HELD_FIGURES := ["Overseer", "PH_Guard_A", "PH_Guard_B"]
const FEET_TOL := 1.0                    # px between the pose origin and the node origin
const INK_BELOW_FEET_MAX := 12.0         # world px of drop shadow the sheet paints under the feet line
const BACKDROPS := [["Backdrop_Face", 0.0, "res://scenes/v2/levels/Backdrop_Face.tscn"],
	["Backdrop_Drift", 2880.0, "res://scenes/v2/levels/Backdrop_Drift.tscn"],
	["Backdrop_Patrol", 5760.0, "res://scenes/v2/levels/Backdrop_Patrol.tscn"]]
const LAYERS := ["Back", "Mid", "Floor"]
const SURFACE_X := 8640.0
const CAMERA_ZOOM := Vector2(1.5, 1.5)
const CAMERA_Y := 450.0
const BAND_TOP := 300.0
const BAND_BOTTOM := 600.0
const DRAWN_FLOOR_TOP := 380.0
const LIP_TOP_MIN := 681.0               # PH_NearLip may not cover the drawn floor (ends at 680.8)
const LIP_SEAM_MAX := 1.0                # ...and may not leave more than a texel above itself
const DECALS_Z := -20
const DECAL_COUNT := 7                   # three pools, three dark stripes, the timber hit strip
const GONE_ROOT := ["PH_Ceiling", "PH_Floor_Face", "PH_Floor_Drift", "PH_Floor_Patrol", "PH_FloorEdge",
	"PH_Conveyor", "PH_ConveyorEdge", "PH_Coal_1", "PH_Coal_2", "PH_Coal_3", "PH_CageShaft", "PH_CageCable", "Parallax",
	"Backdrop/PH_WallTone_Face", "Backdrop/PH_WallTone_Drift", "Backdrop/PH_WallTone_Patrol", "Backdrop/PH_CeilingRock",
	"Backdrop/PH_PipeLow", "Ground/PH_FloorTone_Face", "Ground/PH_FloorTone_Drift", "Ground/PH_FloorTone_Patrol",
	"Ground/PH_Shaft_1", "Props/ScrapPile_1", "Props/BatteryStack_1", "Props/ExitSign_1",
	"Foreground/PH_NearPost", "Foreground/PH_NearPostRim", "Foreground/PH_NearCable"]
const SUPPORT_COUNT := 22
const OFF_ROOT := ["PH_Wall_Face", "PH_Wall_Drift", "PH_Wall_Patrol"]
const KEPT := ["Darkness", "Vignette", "Player/Flashlight", "LitZone_Arena", "LitZone_P1", "LitZone_P2", "LitZone_P3",
	"PH_Decals", "WorkLamps", "DriftLamps", "PH_ArenaLamp", "PH_Landmark_Face", "PH_Landmark_Drift", "PH_Landmark_PastGas",
	"PH_Landmark_Surface", "PH_JamCarts", "PH_Crate_Stack", "Fx_Face", "Fx_Drift", "Fx_Patrol", "Fx_Surface",
	"PH_WallLeft", "PH_WallRight", "PH_WallShaft", "PH_Wall_Surface", "PH_Floor_Surface", "PH_Sky_Surface",
	"Backdrop/PH_Horizon", "Ground/PH_FloorTone_Surface", "Foreground/PH_NearLip", "Fx_Face/Conveyor/ConveyorAnim"]

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

func _finish() -> void:
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

func _approx(a: float, b: float, eps: float) -> bool:
	return absf(a - b) <= eps

# The leftmost world x a dressing node draws at; INF for nodes that draw nothing themselves.
func _draw_min_x(node: Node) -> float:
	if node is Polygon2D:
		var best := INF
		for p in node.polygon:
			best = minf(best, p.x)
		return node.global_position.x + best
	if node is Line2D:
		var best := INF
		for p in node.points:
			best = minf(best, p.x)
		return node.global_position.x + best
	if node is Control:
		return node.global_position.x
	if node is Sprite2D or node is PointLight2D:
		return node.global_position.x
	return INF

func _check_actor(node: Node, label: String, scene: String) -> void:
	if node == null:
		_check(false, "%s is missing" % label)
		return
	_check(node.scene_file_path == scene, "%s comes from %s, expected %s" % [label, node.scene_file_path, scene])
	_check(node.get_node_or_null("Visual/Rig") == null, "%s still carries Visual/Rig" % label)
	if "Rig" in node:
		_check(node.get("Rig") == null, "%s: Rig export is %s, expected null" % [label, node.get("Rig")])
	var sprite: AnimatedSprite2D = node.get_node_or_null("Visual/Sprite")
	_check(sprite != null and sprite.sprite_frames != null, "%s: Visual/Sprite missing or without SpriteFrames" % label)

func _run() -> void:
	var packed: PackedScene = load(PROLOGUE_V2)
	_check(packed != null, "%s failed to load" % PROLOGUE_V2)
	if packed == null:
		_finish()
		return
	var level: Node2D = packed.instantiate()
	root.add_child(level)
	await process_frame
	await process_frame

	# 1. Actors.
	_check_actor(level.get_node_or_null("Player"), "Player", PLAYER_V2)
	_check_actor(level.get_node_or_null("Dan"), "Dan", COMPANION_V2)
	for i in range(1, 4):
		_check_actor(level.get_node_or_null("Patrol/Guard_%d" % i), "Patrol/Guard_%d" % i, GUARD_V2)
	var wave: Node = level.get_node_or_null("GuardWave")
	var enemy_scene: PackedScene = wave.get("EnemyScene") if wave != null else null
	_check(enemy_scene != null and enemy_scene.resource_path == GUARD_V2,
		"GuardWave.EnemyScene is %s, expected %s (the wave would spawn v1 rigs)" % [enemy_scene.resource_path if enemy_scene else null, GUARD_V2])

	# 2. Backdrops.
	var backgrounds: Node2D = level.get_node_or_null("Backgrounds")
	_check(backgrounds != null and not backgrounds.y_sort_enabled, "Backgrounds missing or y-sorted")
	if backgrounds != null:
		var names: PackedStringArray = []
		for c in backgrounds.get_children():
			names.append(c.name)
		_check(names.size() == BACKDROPS.size(), "Backgrounds has %s, expected exactly the three room backdrops" % [names])
		for entry in BACKDROPS:
			var bd: Node2D = backgrounds.get_node_or_null(entry[0])
			if bd == null:
				_check(false, "Backgrounds/%s is missing" % entry[0])
				continue
			_check(bd.scene_file_path == entry[2], "%s comes from %s, expected %s" % [entry[0], bd.scene_file_path, entry[2]])
			_check(bd.position == Vector2(entry[1], 0.0), "%s at %s, expected (%s, 0)" % [entry[0], bd.position, entry[1]])
			for layer in LAYERS:
				var l: Node = bd.get_node_or_null(layer)
				_check(l != null and l.get_child_count() > 0, "%s/%s missing or empty (SectionBackdrop did not build)" % [entry[0], layer])

	# 3. v1 dressing gone from the mine rooms.
	for path in GONE_ROOT:
		_check(level.get_node_or_null(path) == null, "v1 dressing '%s' is still in the v2 prologue" % path)
	for i in range(1, SUPPORT_COUNT + 1):
		_check(level.get_node_or_null("PH_Support_%d" % i) == null, "PH_Support_%d is still in the v2 prologue" % i)
	for path in OFF_ROOT:
		var n: CanvasItem = level.get_node_or_null(path)
		_check(n == null or not n.visible, "'%s' is still visible over the painted wall" % path)
	for group in ["Backdrop", "Ground"]:
		var g: Node = level.get_node_or_null(group)
		if g == null:
			continue
		for c in g.get_children():
			var x: float = _draw_min_x(c)
			_check(x >= SURFACE_X, "%s/%s draws from x=%.1f, expected only Room_Surface dressing (x >= %.0f) left" % [group, c.name, x, SURFACE_X])
			if c is Control:
				_check(c.size.x + c.global_position.x >= SURFACE_X, "%s/%s ends before the surface room" % [group, c.name])
	var props: Node = level.get_node_or_null("Props")
	if props != null:
		for c in props.get_children():
			var physical: bool = c.get_node_or_null("Blocker") is StaticBody2D
			_check(physical or (c is Node2D and c.position.x >= SURFACE_X),
				"Props/%s is neither a blocker nor in Room_Surface — v1 dressing left in a painted room" % c.name)

	# 4. Kept.
	for path in KEPT:
		_check(level.get_node_or_null(path) != null, "'%s' was removed with the dressing" % path)
	var decals: Node2D = level.get_node_or_null("PH_Decals")
	if decals != null and backgrounds != null:
		_check(decals.z_index == DECALS_Z, "PH_Decals z_index=%d, expected %d" % [decals.z_index, DECALS_Z])
		_check(decals.get_index() > backgrounds.get_index(), "PH_Decals precedes Backgrounds in the tree; the light pools would draw under the floor")
		_check(decals.get_child_count() == DECAL_COUNT, "PH_Decals has %d children, expected %d" % [decals.get_child_count(), DECAL_COUNT])
	var sky: ColorRect = level.get_node_or_null("PH_Sky_Surface")
	if sky != null and backgrounds != null:
		var patrol_back: Node = level.get_node_or_null("Backgrounds/Backdrop_Patrol/Back")
		var back_z: int = backgrounds.z_index + (patrol_back.z_index if patrol_back != null else 0)
		_check(sky.z_index > back_z, "PH_Sky_Surface z_index=%d does not cover the Patrol far layer (effective z %d)" % [sky.z_index, back_z])
		_check(sky.color.a == 1.0 and sky.offset_left == SURFACE_X and sky.offset_right >= 10560.0 and sky.offset_top <= 0.0 and sky.offset_bottom >= BAND_TOP,
			"PH_Sky_Surface must be opaque over x %.0f…10560, y 0…%.0f (got %s..%s x %s..%s, alpha %s)" % [SURFACE_X, BAND_TOP, sky.offset_left, sky.offset_right, sky.offset_top, sky.offset_bottom, sky.color.a])
	var lip: Polygon2D = level.get_node_or_null("Foreground/PH_NearLip")
	var floor_section: Sprite2D = level.get_node_or_null("Backgrounds/Backdrop_Face/Floor/Section")
	if lip != null and floor_section != null and floor_section.texture != null:
		var top := INF
		var bottom := -INF
		for p in lip.polygon:
			top = minf(top, p.y)
			bottom = maxf(bottom, p.y)
		var floor_bottom: float = floor_section.position.y + floor_section.texture.get_height() * floor_section.scale.y
		_check(top >= LIP_TOP_MIN, "PH_NearLip starts at y=%.1f, expected >= %.0f (it would cover the drawn floor)" % [top, LIP_TOP_MIN])
		_check(top - floor_bottom <= LIP_SEAM_MAX, "PH_NearLip starts at y=%.1f but the drawn floor ends at %.1f — a strip of clear colour shows between them" % [top, floor_bottom])
		_check(bottom >= CAMERA_Y + 360.0, "PH_NearLip ends at y=%.1f, expected to reach the window bottom %.0f" % [bottom, CAMERA_Y + 360.0])

	# 5. Camera.
	var camera: Camera2D = level.get_node_or_null("Camera2D")
	if camera != null:
		_check(camera.zoom == CAMERA_ZOOM, "Camera2D.zoom=%s, expected %s" % [camera.zoom, CAMERA_ZOOM])
		_check(camera.position.y == CAMERA_Y, "Camera2D.position.y=%s, expected %s" % [camera.position.y, CAMERA_Y])
		var view: Vector2 = Vector2(ProjectSettings.get_setting("display/window/size/viewport_width"),
			ProjectSettings.get_setting("display/window/size/viewport_height")) / camera.zoom
		var top: float = camera.position.y - view.y / 2.0
		var bottom: float = camera.position.y + view.y / 2.0
		_check(top >= camera.limit_top and bottom <= camera.limit_bottom,
			"the %sx%s world window %.0f…%.0f leaves the camera limits %d…%d" % [view.x, view.y, top, bottom, camera.limit_top, camera.limit_bottom])
		_check(top <= DRAWN_FLOOR_TOP - 80.0 and top <= BAND_TOP and bottom >= BAND_BOTTOM,
			"the world window %.0f…%.0f does not hold the walk band %.0f…%.0f with the wall base above it" % [top, bottom, BAND_TOP, BAND_BOTTOM])

	# 6. The capture staging.
	var held: Node2D = level.get_node_or_null("HeldGuards")
	_check(held != null and level.get("HeldGuards") == held, "HeldGuards missing or not exported to Level00_Prologue.cs")
	if held != null:
		_check(not held.visible, "HeldGuards is visible before the Held stage")
		var json_text: String = FileAccess.get_file_as_string(GUARD_FRAMES_JSON)
		var frames: Variant = JSON.parse_string(json_text)
		var pose: Dictionary = frames.poses[HELD_POSE] if frames is Dictionary and frames.has("poses") else {}
		_check(not pose.is_empty(), "%s has no '%s' pose" % [GUARD_FRAMES_JSON, HELD_POSE])
		for figure in HELD_FIGURES:
			var s: Sprite2D = held.get_node_or_null(figure)
			if s == null:
				_check(false, "HeldGuards/%s missing or not a Sprite2D" % figure)
				continue
			_check(s.texture != null and s.texture.resource_path == GUARD_SHEET, "HeldGuards/%s draws %s, expected %s" % [figure, s.texture.resource_path if s.texture else null, GUARD_SHEET])
			_check(s.region_enabled and s.scale == HELD_SCALE, "HeldGuards/%s: region_enabled=%s scale=%s, expected true / %s" % [figure, s.region_enabled, s.scale, HELD_SCALE])
			if pose.is_empty():
				continue
			var expected := Rect2(pose.x * SHEET_SCALE, pose.y * SHEET_SCALE, pose.w * SHEET_SCALE, pose.h * SHEET_SCALE)
			_check(s.region_rect == expected, "HeldGuards/%s region %s, expected the '%s' pose %s" % [figure, s.region_rect, HELD_POSE, expected])
			# Feet on the origin: the pose origin (region-relative, mockup px) lands on the node position.
			var origin := Vector2(pose.origin[0], pose.origin[1]) * SHEET_SCALE
			var feet_local: Vector2 = s.offset - s.region_rect.size / 2.0 + origin
			_check(feet_local.length() <= FEET_TOL, "HeldGuards/%s: the feet sit %s texture px from the node origin (offset %s)" % [figure, feet_local, s.offset])
			var ink_bottom: float = (s.offset.y + s.region_rect.size.y / 2.0) * s.scale.y
			_check(ink_bottom >= 0.0 and ink_bottom <= INK_BELOW_FEET_MAX, "HeldGuards/%s: the sprite ends %.1f px below the node origin, expected 0…%.0f (shadow only)" % [figure, ink_bottom, INK_BELOW_FEET_MAX])
		var gun: Line2D = held.get_node_or_null("Overseer/PH_Gun")
		_check(gun != null and gun.global_scale.is_equal_approx(Vector2.ONE), "Overseer/PH_Gun missing or drawn at world scale %s, expected 1" % (gun.global_scale if gun else null))
		_check(held.get_node_or_null("PH_HeldLamp") is PointLight2D, "HeldGuards/PH_HeldLamp is gone")

	level.queue_free()
	await process_frame
	_finish()
