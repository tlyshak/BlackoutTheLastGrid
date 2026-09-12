extends SceneTree
# Smoke: the v2 prologue is wired to the v2 art (T-V2-01 integration step, GAME_DESIGN §6a).
# scenes/v2/levels/Level00_Prologue.tscn must
#   * instance the v2 actors: Player, Dan and Patrol/Guard_1..3 come from scenes/v2/actors/*
#     (no Visual/Rig, a null Rig export, a Sprite with SpriteFrames) and GuardWave.EnemyScene is
#     the v2 guard, so the wave does not spawn v1 rigs into the drawn mine;
#   * carry the three painted room backdrops under Backgrounds (not y-sorted) at the x of the
#     level's own Rooms/Room_Face|Drift|Patrol rects, each built with its Back/Mid/Floor layers;
#   * have no v1 dressing left in the three mine rooms: the PH_ walls/floors/supports/conveyor/coal/
#     cage shaft, the Backdrop/Ground/Props/Foreground decoration (everything under Backdrop and
#     Ground now lies at x >= 8640, every Props child either carries a Blocker collision or stands
#     in Room_Surface), the PH_Wall_Face|Drift|Patrol tones (deleted, not hidden) and the
#     PH_Sky_Surface patch (the painted far layer is switched off outside its room instead);
#   * keep what is light, decal, collision or Room_Surface: Darkness, Vignette, the hero's lamp,
#     LitZone_*, PH_Decals (after Backgrounds in the tree, z -20), the lamps, landmarks, jam carts,
#     Fx_*, the physical walls, the surface room's dressing including the v1 rock Parallax (drawn
#     under the painted far layers, so it shows only on the surface), and Foreground/PH_NearLip
#     starting where the drawn floor ends;
#   * have no crate row in the first room (author's playtest 2026-09-12): Crate and PH_Crate_Stack
#     are gone, the jump hint stays;
#   * keep the timber gate readable on the painted floor (author's playtest 2026-09-12 #2, «room 2,
#     nothing happens»): every PH_ polygon of DebrisPile_Timber and the blended PH_HitStrip_Timber
#     sit clearly above the luminance of the drawn floor texel under the pile — the prop's default
#     rocks are that floor's own darkness and vanished on it, leaving an invisible wall;
#   * put the drawn floor on the walk band: Backdrop_Face.FloorFarEdgeY is the band's top (300,
#     RoomBounds.FloorTop) and the drawn floor ends at the band's bottom (600) with at most a texel
#     below it — the hero never stands on the wall and never sees floor he cannot reach;
#   * switch every painted far layer off while the camera is limited to Room_Surface and keep the
#     patrol room's on while it is limited to Room_Patrol (LevelBase.ApplyRoomBounds drives it);
#   * run the camera at zoom 1.5 from y 450: a 1280x720 world window (90…810) inside the limits,
#     the walk band 300…600 inside it with wall showing above the band's top;
#   * stage the capture with Sprite2Ds: HeldGuards/Overseer|PH_Guard_A|PH_Guard_B show the guard
#     sheet's `stance` region (assets/art/v2/keyframes/guard_keyframes.frames.json x svg/scale 2) at
#     scale 0.5 with the feet on the node origin and the region's four corner texels transparent
#     (no card behind the figure), PH_Gun keeps its world size, PH_HeldLamp stays, and the group is
#     exported as HeldGuards and hidden until the Held stage.
# The v1/v2 parity of everything else is v2_level_skeleton.gd; the play-through is v2_level_prologue*.gd.
# Run: godot --headless --path . -s tests/smoke/v2_prologue_integration.gd

const NAME := "v2_prologue_integration"   # must equal the file basename
const MAX_FRAMES := 600
const PROLOGUE_V2 := "res://scenes/v2/levels/Level00_Prologue.tscn"
const PLAYER_V2 := "res://scenes/v2/actors/Player.tscn"
const COMPANION_V2 := "res://scenes/v2/actors/Companion.tscn"
const GUARD_V2 := "res://scenes/v2/actors/Guard.tscn"
const GUARD_SHEET := "res://assets/art/v2/sprites/guard_keyframes.svg"
const GUARD_FRAMES_JSON := "res://assets/art/v2/keyframes/guard_keyframes.frames.json"
const SHEET_SCALE := 2.0                 # svg/scale of sprites/guard_keyframes.svg.import
const HELD_POSE := "stance"
const HELD_SCALE := Vector2(0.5, 0.5)
const HELD_FIGURES := ["Overseer", "PH_Guard_A", "PH_Guard_B"]
const FEET_TOL := 1.0                    # px between the pose origin and the node origin
const INK_BELOW_FEET_MAX := 12.0         # world px of drop shadow the sheet paints under the feet line
const BACKDROPS := [["Backdrop_Face", "Room_Face", "res://scenes/v2/levels/Backdrop_Face.tscn"],
	["Backdrop_Drift", "Room_Drift", "res://scenes/v2/levels/Backdrop_Drift.tscn"],
	["Backdrop_Patrol", "Room_Patrol", "res://scenes/v2/levels/Backdrop_Patrol.tscn"]]
const LAYERS := ["Back", "Mid", "Floor"]
const ROCK_LAYERS := ["PxRockFar", "PxRockMid", "PxStruct"]   # the v1 rock parallax kept for the surface
const SURFACE_X := 8640.0
const CAMERA_ZOOM := Vector2(1.5, 1.5)
const CAMERA_Y := 450.0
const BAND_TOP := 300.0
const BAND_BOTTOM := 600.0
const WALL_ABOVE_BAND_MIN := 80.0        # world px of wall the window must show above the band's top
const UNREACHABLE_FLOOR_MAX := 2.0       # px of drawn floor allowed below the band's bottom (600.8 - 600)
const LIP_SEAM_MAX := 1.0                # PH_NearLip may not leave more than a texel of clear colour above itself
const PLAYTEST_GONE := ["Crate", "PH_Crate_Stack"]   # author's playtest 2026-09-12: no crate row in the v2 first room
const DECALS_Z := -20
const DECAL_COUNT := 7                   # three pools, three dark stripes, the timber hit strip
const TIMBER_PILE := "DebrisPile_Timber"
const TIMBER_RUBBLE := ["PH_RockFar", "PH_RockNear", "PH_Rock", "PH_TimberA", "PH_TimberB"]
const HIT_STRIP := "PH_Decals/PH_HitStrip_Timber"
const RUBBLE_CONTRAST_MIN := 0.15        # luminance every pile polygon must sit above the drawn floor under it
const HIT_STRIP_CONTRAST_MIN := 0.15     # luminance the strip, blended at its alpha, must add over that floor
const GONE_ROOT := ["PH_Ceiling", "PH_Floor_Face", "PH_Floor_Drift", "PH_Floor_Patrol", "PH_FloorEdge",
	"PH_Conveyor", "PH_ConveyorEdge", "PH_Coal_1", "PH_Coal_2", "PH_Coal_3", "PH_CageShaft", "PH_CageCable",
	"PH_Wall_Face", "PH_Wall_Drift", "PH_Wall_Patrol", "PH_Sky_Surface",
	"Backdrop/PH_WallTone_Face", "Backdrop/PH_WallTone_Drift", "Backdrop/PH_WallTone_Patrol", "Backdrop/PH_CeilingRock",
	"Backdrop/PH_PipeLow", "Ground/PH_FloorTone_Face", "Ground/PH_FloorTone_Drift", "Ground/PH_FloorTone_Patrol",
	"Ground/PH_Shaft_1", "Props/ScrapPile_1", "Props/BatteryStack_1", "Props/ExitSign_1",
	"Foreground/PH_NearPost", "Foreground/PH_NearPostRim", "Foreground/PH_NearCable"]
const SUPPORT_COUNT := 22
const KEPT := ["Darkness", "Vignette", "Player/Flashlight", "LitZone_Arena", "LitZone_P1", "LitZone_P2", "LitZone_P3",
	"PH_Decals", "WorkLamps", "DriftLamps", "PH_ArenaLamp", "PH_Landmark_Face", "PH_Landmark_Drift", "PH_Landmark_PastGas",
	"PH_Landmark_Surface", "PH_JamCarts", "Tutorial/JumpPrompt", "Fx_Face", "Fx_Drift", "Fx_Patrol", "Fx_Surface",
	"PH_WallLeft", "PH_WallRight", "PH_WallShaft", "PH_Wall_Surface", "PH_Floor_Surface",
	"Parallax/PxRockFar/PH_FarMassif", "Parallax/PxRockMid/PH_MidWall", "Parallax/PxStruct/PH_Trestle_1",
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

func _lum(c: Color) -> float:
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b

# The drawn floor's colour at world (x, y): the texel of the floor-layer sprite of `backdrop` that
# covers the point; a negative red channel when no sprite does.
func _floor_color(backdrop: Node2D, x: float, y: float) -> Color:
	var floor_layer: Node = backdrop.get_node_or_null("Floor")
	if floor_layer == null:
		return Color(-1.0, 0.0, 0.0)
	for s in floor_layer.get_children():
		if not (s is Sprite2D) or s.texture == null:
			continue
		var origin: Vector2 = s.global_position
		var size: Vector2 = s.region_rect.size * s.scale
		if x < origin.x or x >= origin.x + size.x or y < origin.y or y >= origin.y + size.y:
			continue
		var texel: Vector2 = s.region_rect.position + (Vector2(x, y) - origin) / s.scale
		return s.texture.get_image().get_pixel(int(texel.x), int(texel.y))
	return Color(-1.0, 0.0, 0.0)

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
			var room: Node = level.get_node_or_null("Rooms/" + entry[1])
			var room_rect: Rect2 = room.get("Rect") if room != null else Rect2()
			_check(room != null and bd.position == Vector2(room_rect.position.x, 0.0) and bd.get("RoomWidth") == room_rect.size.x,
				"%s at %s, RoomWidth %s, expected the level's %s rect %s" % [entry[0], bd.position, bd.get("RoomWidth"), entry[1], room_rect])
			for layer in LAYERS:
				var l: Node = bd.get_node_or_null(layer)
				_check(l != null and l.get_child_count() > 0, "%s/%s missing or empty (SectionBackdrop did not build)" % [entry[0], layer])

	# 3. v1 dressing gone from the mine rooms.
	for path in GONE_ROOT:
		_check(level.get_node_or_null(path) == null, "v1 dressing '%s' is still in the v2 prologue" % path)
	for i in range(1, SUPPORT_COUNT + 1):
		_check(level.get_node_or_null("PH_Support_%d" % i) == null, "PH_Support_%d is still in the v2 prologue" % i)
	for path in PLAYTEST_GONE:
		_check(level.get_node_or_null(path) == null, "'%s' is still in the v2 prologue — the author asked for the first room without the crate stack" % path)
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
	# The timber gate reads on the painted floor (author's playtest 2026-09-12 #2).
	var pile: Node2D = level.get_node_or_null(TIMBER_PILE)
	var drift_bd: Node2D = level.get_node_or_null("Backgrounds/Backdrop_Drift")
	if pile != null and drift_bd != null:
		var floor_c: Color = _floor_color(drift_bd, pile.global_position.x, pile.global_position.y)
		_check(floor_c.r >= 0.0, "no drawn floor texel under %s at %s" % [TIMBER_PILE, pile.global_position])
		var floor_lum: float = _lum(floor_c)
		for name in TIMBER_RUBBLE:
			var poly: Polygon2D = pile.get_node_or_null("PH_Rubble/" + name)
			if poly == null:
				_check(false, "%s/PH_Rubble/%s is missing" % [TIMBER_PILE, name])
				continue
			_check(_lum(poly.color) - floor_lum >= RUBBLE_CONTRAST_MIN,
				"%s/PH_Rubble/%s (luminance %.2f) sits %.2f above the drawn floor under the pile (%.2f), expected >= %.2f — the pile vanishes on the painted floor" % [TIMBER_PILE, name, _lum(poly.color), _lum(poly.color) - floor_lum, floor_lum, RUBBLE_CONTRAST_MIN])
		var strip: Polygon2D = level.get_node_or_null(HIT_STRIP)
		if strip != null:
			var blended: Color = floor_c.lerp(Color(strip.color, 1.0), strip.color.a)
			_check(_lum(blended) - floor_lum >= HIT_STRIP_CONTRAST_MIN,
				"%s blended at alpha %.2f adds %.2f luminance over the drawn floor (%.2f), expected >= %.2f — the strip the heavy hit is thrown from is invisible" % [HIT_STRIP, strip.color.a, _lum(blended) - floor_lum, floor_lum, HIT_STRIP_CONTRAST_MIN])
		else:
			_check(false, "%s is missing" % HIT_STRIP)
	else:
		_check(false, "%s or Backgrounds/Backdrop_Drift is missing" % TIMBER_PILE)
	# The v1 rock parallax is back for the surface, strictly under every painted far layer.
	var rock: Node2D = level.get_node_or_null("Parallax")
	var patrol_back: Node = level.get_node_or_null("Backgrounds/Backdrop_Patrol/Back")
	if rock != null and backgrounds != null and patrol_back != null:
		var painted_z: int = backgrounds.z_index + patrol_back.z_index
		for name in ROCK_LAYERS:
			var layer: Parallax2D = rock.get_node_or_null(name)
			if layer == null:
				_check(false, "Parallax/%s is missing — the surface lost its v1 rock parallax" % name)
				continue
			var z: int = rock.z_index + layer.z_index
			_check(z < painted_z, "Parallax/%s draws at effective z %d, expected below the painted far layers (%d) so it shows only on the surface" % [name, z, painted_z])
	else:
		_check(rock != null, "Parallax is gone — the surface has no far layer at all")
	# The painted far layers follow the camera limits LevelBase.ApplyRoomBounds sets: all off on the surface.
	var surface_room: Node = level.get_node_or_null("Rooms/Room_Surface")
	var patrol_room: Node = level.get_node_or_null("Rooms/Room_Patrol")
	if backgrounds != null and surface_room != null and patrol_room != null:
		level.ApplyRoomBounds(surface_room)
		await process_frame
		await process_frame
		for entry in BACKDROPS:
			var back: CanvasItem = backgrounds.get_node_or_null(entry[0] + "/Back")
			_check(back != null and not back.visible, "%s/Back is shown while the camera is limited to Room_Surface — the mine's sky follows the camera onto the surface" % entry[0])
		level.ApplyRoomBounds(patrol_room)
		await process_frame
		await process_frame
		var patrol: CanvasItem = backgrounds.get_node_or_null("Backdrop_Patrol/Back")
		var face: CanvasItem = backgrounds.get_node_or_null("Backdrop_Face/Back")
		_check(patrol != null and patrol.visible, "Backdrop_Patrol/Back is hidden while the camera is limited to Room_Patrol")
		_check(face != null and not face.visible, "Backdrop_Face/Back is shown while the camera is limited to Room_Patrol")
	# The drawn floor is the walk band: far edge on its top, near edge at its bottom, the lip right after.
	var lip: Polygon2D = level.get_node_or_null("Foreground/PH_NearLip")
	var face_bd: Node2D = level.get_node_or_null("Backgrounds/Backdrop_Face")
	var floor_section: Sprite2D = level.get_node_or_null("Backgrounds/Backdrop_Face/Floor/Section")
	if lip != null and face_bd != null and floor_section != null and floor_section.texture != null:
		var far_edge: float = face_bd.FloorFarEdgeY
		_check(far_edge == BAND_TOP, "Backdrop_Face.FloorFarEdgeY=%.1f, expected the band's top %.0f — a hero on the far edge of the band would stand on the wall" % [far_edge, BAND_TOP])
		var floor_bottom: float = floor_section.position.y + floor_section.texture.get_height() * floor_section.scale.y
		_check(floor_bottom >= BAND_BOTTOM, "the drawn floor ends at y=%.1f, short of the band's bottom %.0f" % [floor_bottom, BAND_BOTTOM])
		_check(floor_bottom - BAND_BOTTOM <= UNREACHABLE_FLOOR_MAX, "the drawn floor reaches y=%.1f, %.1f px below the band's bottom %.0f the hero can never step on" % [floor_bottom, floor_bottom - BAND_BOTTOM, BAND_BOTTOM])
		var top := INF
		var bottom := -INF
		for p in lip.polygon:
			top = minf(top, p.y)
			bottom = maxf(bottom, p.y)
		_check(top >= floor_bottom, "PH_NearLip starts at y=%.1f, above the drawn floor's end %.1f (it would cover the floor)" % [top, floor_bottom])
		_check(top - floor_bottom <= LIP_SEAM_MAX, "PH_NearLip starts at y=%.1f but the drawn floor ends at %.1f — a strip of clear colour shows between them" % [top, floor_bottom])
		_check(bottom >= CAMERA_Y + 360.0, "PH_NearLip ends at y=%.1f, expected to reach the window bottom %.0f" % [bottom, CAMERA_Y + 360.0])
	else:
		_check(false, "Foreground/PH_NearLip, Backgrounds/Backdrop_Face or its Floor/Section is missing")

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
		_check(top <= BAND_TOP - WALL_ABOVE_BAND_MIN and bottom >= BAND_BOTTOM,
			"the world window %.0f…%.0f does not hold the walk band %.0f…%.0f with %.0f px of wall above it" % [top, bottom, BAND_TOP, BAND_BOTTOM, WALL_ABOVE_BAND_MIN])

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
			# No card behind the figure: the region's four corner texels are transparent on the sheet.
			if s.texture != null:
				var sheet: Image = s.texture.get_image()
				var r: Rect2i = Rect2i(s.region_rect)
				for corner in [r.position, Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]:
					var a: float = sheet.get_pixelv(corner).a
					_check(is_zero_approx(a), "HeldGuards/%s: corner texel %s of the region is opaque (alpha %.2f) — the figure stands on a card" % [figure, corner, a])
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
