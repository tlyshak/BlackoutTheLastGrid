extends SceneTree
# Smoke: the painted section backdrops of the v2 mine rooms (T-V2-01 01c). Headless has no
# renderer, so this asserts the data the picture is made of.
#
# Contract since 2026-09-16: one room is exactly one painting. WorldScale is 1280/680, so the
# 680 px wide mockup is 1280 world px — the camera window at zoom 1.5 — and every
# Backdrop_*.tscn sets SectionX 0, FillFrom 0, RoomWidth = FillTo = 1280 with no fill textures
# and no fill slices. With those values SectionBackdrop.BuildLayer emits no filler slice at all:
# each of Mid and Floor is the one Section sprite and nothing else, and the three rooms sit at
# level x 0 / 1280 / 2560 (scenes/v2/levels/Level00_Prologue.tscn, Rooms/* and Backgrounds/*),
# the mine ending at 3840 where Room_Surface starts. Every number below is derived from
# WORLD_SCALE and the mockup size rather than pasted, so a change of scale moves the
# expectations with it.
#
#   * import — the twelve derivatives of the first three sections and the five frame-sized
#     derivatives of the revised section 1 (level0_section1_mineface_r2, 2026-09-16) import at
#     svg/scale 3 (2040x1320 each), the animated crops at their own sizes; every room draws the
#     one r2 `_back` texture, the premise the far layer's level-wide tile grid rests on, and that
#     texture still tiles seamlessly at the two BackSlice cut columns;
#   * layer content — probed pixels: the mid layer is transparent above the wall and opaque down to
#     the wall base, the floor layer starts exactly at the mockup's floor row;
#   * placement — on each Backdrop_* scene the exports are the one-painting set above, the
#     Mid/Floor sprites carry the derived scale (WorldScale/3) and offset (300 − 280·WorldScale),
#     each layer is exactly one Section sprite spanning FillFrom…FillTo with its region inside the
#     texture, and the drawn floor's far edge (the wall base) lands exactly on the walk band's top
#     (300, RoomBounds.FloorTop) while the floor reaches the band's bottom (600) with no more than
#     a texel of floor below it — a hero on the band's far edge stands on floor ink, not on wall ink
#     (author's playtest 2026-09-12; at the old 380 the far 80 px of the band stood on the wall);
#   * rooms — placed at the level's room x, and the paintings meet edge to edge: each painting
#     starts at its room's left edge, is exactly one room wide, and ends at the level x the next
#     room's painting starts at, so together they cover the three mine rooms 0…3840 with no gap,
#     no overlap and no repeated wall column between them;
#   * far layer — Back is a Parallax2D at the brief's parallax depth, its tiles abut, sit on a grid
#     anchored at level x 0 and cover the camera window for every camera centre from half a window
#     left of the room to half a window right of it (Parallax2D shifts a tile by
#     (centre − viewport px / 2) · (1 − scroll)); the layer is shown only while the camera's limits
#     overlap the room, so the last mine room's sky never follows the camera onto the surface;
#   * depth — z of Back/Mid/Floor per docs/plans/t07i-visual-kit/visual-brief.md;
#   * TestBackdrops.tscn instantiates with the three backdrops at 0/1280/2560, the PH_ walk band
#     over the whole mine, the near lip starting where the drawn floor ends and the v2 camera zoom.
# Run: godot --headless --path . -s tests/smoke/v2_backdrops.gd

const NAME := "v2_backdrops"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s).
const MAX_FRAMES := 600
const ART := "res://assets/art/v2/backgrounds/"
const SECTIONS := ["level0_section1_mineface", "level0_section2_ventilation", "level0_section3_exit"]
const LAYERS := ["", "_back", "_mid", "_floor"]
const R2 := "level0_section1_mineface_r2"   # revised section 1 (tools/derive_section1_r2.py)
const R2_S2 := "level0_section2_ventilation_r2"   # revised section 2 (tools/derive_section2_r2.py)
const IMPORT_SCALE := 3            # svg/scale in the .import sidecars
const MOCKUP_SIZE := Vector2(680.0, 440.0)   # the sections' viewBox, in mockup px
const TEXTURE_SIZE := Vector2i(2040, 1320)   # MOCKUP_SIZE x IMPORT_SCALE
# The r2 derivatives: frame-sized layers and the animated crops (crop size in mockup px x IMPORT_SCALE).
const R2_LAYERS := {"_back": TEXTURE_SIZE, "_mid": TEXTURE_SIZE, "_floor": TEXTURE_SIZE,
	"_mid_fill": TEXTURE_SIZE, "_floor_fill": TEXTURE_SIZE,
	"_alarm": Vector2i(1950, 378), "_worklamp_wall": Vector2i(900, 564),
	"_worklamp_floor": Vector2i(720, 204), "_fan_blades": Vector2i(204, 204)}
# The r2 section 2 derivatives: two frame-sized layers, the belt's one-period tile and the crops the
# game animates (T-V2-06). This room keeps section 1's far layer, so it derives none.
const R2_S2_LAYERS := {"_mid": TEXTURE_SIZE, "_floor": TEXTURE_SIZE,
	"_belt_tile": Vector2i(66, 147), "_run_green": Vector2i(978, 120),
	"_run_red": Vector2i(978, 120), "_lever": Vector2i(72, 84), "_sparks": Vector2i(180, 144)}
const SHARED_BACK := ART + R2 + "_back.svg"   # the one far layer every mine room tiles
const BACK_SLICE := Vector2(240, 680)   # SectionBackdrop.BackSlice default: the tiled column of the far layer
const BACK_SEAM_ROWS := 160             # mockup rows of the far layer (the wall covers it from 160)
const BACK_SEAM_TOL := 0.1              # per-channel colour slack at the two cut columns
const BACK_SEAM_MAX_ROWS := 4           # rows allowed to differ (anti-aliased stroke edges)
const SCENE_DIR := "res://scenes/v2/levels/"
const TEST_SCENE := SCENE_DIR + "TestBackdrops.tscn"
# ---- the one-painting geometry, every constant derived from WORLD_SCALE -------------------------
const WORLD_SCALE := 1280.0 / 680.0   # SectionBackdrop.WorldScale of every Backdrop_*: one mockup = one camera window
const ROOM_WIDTH := MOCKUP_SIZE.x * WORLD_SCALE   # 1280: the painting is the whole room
const MINE_END := 3.0 * ROOM_WIDTH                # 3840; Room_Surface starts here
const BAND_TOP := 300.0            # RoomBounds.FloorTop of the mine rooms
const BAND_BOTTOM := 600.0         # RoomBounds.FloorBottom
const DRAWN_FLOOR_ROW := 280.0     # mockup row the drawn floor starts at (SectionBackdrop.DrawnFloorTop)
const DRAWN_FLOOR_TOP := BAND_TOP  # world y of the drawn floor's far edge == the band's top
const EXPECTED_SCALE := WORLD_SCALE / IMPORT_SCALE                    # 0.6275: world px per texture px
const EXPECTED_OFFSET_Y := BAND_TOP - DRAWN_FLOOR_ROW * WORLD_SCALE   # -227.06: every sprite's top edge
const DRAWN_FLOOR_BOTTOM := EXPECTED_OFFSET_Y + MOCKUP_SIZE.y * WORLD_SCALE   # 601.18: where the painting ends
const EDGE_TOL := 1.0              # px of slack on the drawn floor edge (one texel is 0.63 px at EXPECTED_SCALE)
const UNREACHABLE_FLOOR_MAX := 2.0 # px of drawn floor allowed below the band's bottom (601.18 - 600 = 1.18)
const FEET_PROBE_DEPTH := 1.0      # world px into the band the feet probe samples the layers at
const SCALE_EPS := 0.001
const POS_EPS := 0.05              # px: edges meet
const Z_BACK_MIN := -100           # visual brief: parallax background -100…-60
const Z_BACK_MAX := -60
const Z_MID := -40                 # visual brief: room background, walls
const Z_FLOOR := -20               # visual brief: floor, decals
const VIEW_WIDTH := 1280.0         # 1920 / camera zoom 1.5 (Backdrop ViewWidth default) — equal to ROOM_WIDTH now
const VIEWPORT_PX := 1920.0        # display/window/size/viewport_width: Parallax2D scrolls from the camera centre minus half of this
const CAMERA_ZOOM := Vector2(1.5, 1.5)
# Room order, world x in the v2 prologue map (scenes/v2/levels/Level00_Prologue.tscn, Rooms/* and
# Backgrounds/Backdrop_*) and the section each room's Mid/Floor are cut from.
const ROOMS := [["Face", 0.0, R2], ["Drift", ROOM_WIDTH, R2_S2], ["Patrol", 2.0 * ROOM_WIDTH, "level0_section3_exit"]]
# Mockup column clear of props in a section's mid/floor layers: 78 for the first three sections (door
# frame ends 73.5, first power bank starts 79.25); 100 for r2 (through the power bank shelf, whose
# shadow ends at row 258: the wires pass rows 122…127 there, the wall ends exactly at 280 — the
# terminal's ground shadow reaches row 285 at columns 4…56 and the dividers' at 193…209).
# 360 for the r2 section 2 (between the fan housing's right louver and the gauge cabinet: the mid
# layer ends exactly at the wall base there and the floor starts at 280).
const PROBE_COLUMNS := {"level0_section1_mineface": 78, "level0_section2_ventilation": 78, "level0_section3_exit": 78, R2: 100, R2_S2: 360}
const SKY_ROW := 120               # mockup row between the beam (to 113) and the pipes (from 124): mid transparent, back shows through
const WALL_ROW := 170              # mockup row inside the wall band 160…280
const WALL_BASE_ROW := 279         # last wall row
const FLOOR_ROW := 281             # first floor row (floor layer starts at 280)
const LIMIT_SLACK := 0.01          # the camera's LimitLeft/LimitRight sit exactly on room edges; the room test is strict
const ROOM_SURFACE := [MINE_END, MINE_END + 1920.0]   # Room_Surface of the v2 map: no painted backdrop, the mine's sky must be off here

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

func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

func _alpha(img: Image, column: int, row: int) -> float:
	return img.get_pixel(column * IMPORT_SCALE, row * IMPORT_SCALE).a

func _approx(a: float, b: float, eps: float) -> bool:
	return absf(a - b) <= eps

func _sprites(layer: Node) -> Array:
	var list: Array = []
	for c in layer.get_children():
		if c is Sprite2D:
			list.append(c)
	list.sort_custom(func(a, b): return a.position.x < b.position.x)
	return list

func _world_width(s: Sprite2D) -> float:
	return s.region_rect.size.x * s.scale.x

# Limits the camera to `limits` (level x), waits a frame and asserts each room's far layer is shown or hidden as `expected`.
func _expect_backs(cam: Camera2D, backs: Dictionary, limits: Array, expected: Dictionary, label: String) -> void:
	cam.limit_left = int(limits[0])
	cam.limit_right = int(limits[1])
	await process_frame
	await process_frame
	for room in expected:
		var back: CanvasItem = backs[room]
		if back == null:
			_check(false, "TestBackdrops: Backdrop_%s/Back missing" % room)
			continue
		_check(back.visible == expected[room], "TestBackdrops: Backdrop_%s/Back is %s while the camera is %s (%d…%d); expected %s" % [room, "shown" if back.visible else "hidden", label, limits[0], limits[1], "shown" if expected[room] else "hidden"])

# One layer of a room. A room is exactly one painting, so the layer must hold exactly one sprite —
# the Section — spanning FillFrom…FillTo at the derived scale and offset, with its region inside the
# texture. A second sprite here is a filler slice creeping back in (the repeated wall column the
# 1280/680 scale removed), and that fails the test instead of passing silently.
func _check_layer(room: String, layer: Node, from: float, to: float) -> Array:
	var list := _sprites(layer)
	var names: Array = []
	for s: Sprite2D in list:
		names.append(s.name)
	_check(list.size() == 1,
		"%s/%s: %d sprites %s, expected exactly one — a room is one painting, no fill slices" % [room, layer.name, list.size(), names])
	if list.is_empty():
		return list
	_check(list[0].name == "Section",
		"%s/%s: the first sprite is named %s, expected 'Section'" % [room, layer.name, list[0].name])
	_check(_approx(list[0].position.x, from, POS_EPS),
		"%s/%s: first sprite at x=%.2f, expected FillFrom %.2f" % [room, layer.name, list[0].position.x, from])
	var cursor: float = list[0].position.x
	for s: Sprite2D in list:
		_check(_approx(s.position.x, cursor, POS_EPS),
			"%s/%s/%s: x=%.2f, expected %.2f (gap or overlap with the previous sprite)" % [room, layer.name, s.name, s.position.x, cursor])
		cursor = s.position.x + _world_width(s)
		_check(not s.centered and s.region_enabled, "%s/%s/%s: expected centered=false, region_enabled=true" % [room, layer.name, s.name])
		_check(_approx(s.scale.x, EXPECTED_SCALE, SCALE_EPS) and _approx(s.scale.y, EXPECTED_SCALE, SCALE_EPS),
			"%s/%s/%s: scale=%s, expected %.4f (WorldScale / %d)" % [room, layer.name, s.name, s.scale, EXPECTED_SCALE, IMPORT_SCALE])
		_check(_approx(s.position.y, EXPECTED_OFFSET_Y, EDGE_TOL),
			"%s/%s/%s: y=%.2f, expected %.2f (%.0f - %.0f * WorldScale)" % [room, layer.name, s.name, s.position.y, EXPECTED_OFFSET_Y, BAND_TOP, DRAWN_FLOOR_ROW])
		var tex_size: Vector2 = Vector2(s.texture.get_size()) if s.texture != null else Vector2.ZERO
		var r: Rect2 = s.region_rect
		_check(s.texture != null and r.position.x >= -POS_EPS and r.position.y >= -POS_EPS \
			and r.end.x <= tex_size.x + POS_EPS and r.end.y <= tex_size.y + POS_EPS and r.size.x > 0.0,
			"%s/%s/%s: region %s outside texture %s" % [room, layer.name, s.name, r, tex_size])
	_check(_approx(cursor, to, POS_EPS), "%s/%s: last sprite ends at x=%.2f, expected FillTo %.2f" % [room, layer.name, cursor, to])
	return list

func _run() -> void:
	# 1. Import: every frame-sized derivative is a 2040x1320 texture, every r2 crop its own size.
	var images := {}
	var expected := {}
	for section in SECTIONS:
		for layer in LAYERS:
			expected[section + layer] = TEXTURE_SIZE
	for layer in R2_LAYERS:
		expected[R2 + layer] = R2_LAYERS[layer]
	for layer in R2_S2_LAYERS:
		expected[R2_S2 + layer] = R2_S2_LAYERS[layer]
	for name in expected:
		var path: String = ART + name + ".svg"
		var tex: Texture2D = load(path)
		_check(tex != null, "%s did not load" % path)
		if tex == null:
			continue
		_check(tex.get_size() == Vector2(expected[name]),
			"%s is %s, expected %s (svg/scale=%d)" % [path, tex.get_size(), expected[name], IMPORT_SCALE])
		images[name] = tex.get_image()

	# 1b. The shared far layer tiles seamlessly: the two cut columns of BackSlice (240 and 679) show
	#     the same colour on (almost) every row — the derivation bends the gallery rail and the far
	#     cables to one height at both cuts; a few rows of anti-aliasing slack are allowed. The far
	#     layer is the only layer that still tiles: it is a level-wide grid, not a room-wide fill.
	var back_img: Image = images.get(R2 + "_back")
	if back_img != null:
		var differing: Array = []
		for row in range(0, BACK_SEAM_ROWS):
			var left: Color = back_img.get_pixel(int(BACK_SLICE.x) * IMPORT_SCALE, row * IMPORT_SCALE)
			var right: Color = back_img.get_pixel(int(BACK_SLICE.y) * IMPORT_SCALE - 1, row * IMPORT_SCALE)
			if absf(left.r - right.r) > BACK_SEAM_TOL or absf(left.g - right.g) > BACK_SEAM_TOL or absf(left.b - right.b) > BACK_SEAM_TOL:
				differing.append(row)
		_check(differing.size() <= BACK_SEAM_MAX_ROWS,
			"%s_back: columns %d and %d differ on %d rows %s — the far layer would show a step at every tile seam (allowed %d)" % [R2, int(BACK_SLICE.x), int(BACK_SLICE.y) - 1, differing.size(), differing.slice(0, 12), BACK_SEAM_MAX_ROWS])

	# 2. Layer content: mid transparent above the wall, opaque to the wall base; floor starts at row 280.
	for section in PROBE_COLUMNS:
		var col: int = PROBE_COLUMNS[section]
		var mid: Image = images.get(section + "_mid")
		var floor: Image = images.get(section + "_floor")
		if mid == null or floor == null:
			continue
		_check(_alpha(mid, col, SKY_ROW) == 0.0, "%s_mid: opaque above the wall at row %d" % [section, SKY_ROW])
		_check(_alpha(mid, col, WALL_ROW) == 1.0, "%s_mid: not opaque inside the wall at row %d" % [section, WALL_ROW])
		_check(_alpha(mid, col, WALL_BASE_ROW) == 1.0, "%s_mid: not opaque at the wall base row %d" % [section, WALL_BASE_ROW])
		_check(_alpha(floor, col, WALL_BASE_ROW) == 0.0, "%s_floor: opaque above the floor at row %d" % [section, WALL_BASE_ROW])
		_check(_alpha(floor, col, FLOOR_ROW) == 1.0, "%s_floor: not opaque at the first floor row %d" % [section, FLOOR_ROW])

	# 3. Room scenes at their level x.
	var edges: Array = []      # [level FillFrom, level FillTo] per room, in order
	var paintings: Array = []  # [level x of the Section sprite's left edge, of its right edge] per room
	for entry in ROOMS:
		var room: String = entry[0]
		var room_x: float = entry[1]
		var probe_column: int = PROBE_COLUMNS[entry[2]]
		var packed: PackedScene = load(SCENE_DIR + "Backdrop_%s.tscn" % room)
		_check(packed != null, "Backdrop_%s.tscn did not load" % room)
		if packed == null:
			continue
		var bd: Node2D = packed.instantiate()
		bd.position = Vector2(room_x, 0)
		root.add_child(bd)
		await process_frame

		# The one-painting exports: a 680 px mockup is exactly the 1280 px room, drawn from x 0.
		_check(_approx(bd.WorldScale, WORLD_SCALE, SCALE_EPS),
			"%s: WorldScale=%.6f, expected %.6f (1280 / 680: one mockup is exactly the camera window)" % [room, bd.WorldScale, WORLD_SCALE])
		_check(_approx(bd.RoomWidth, ROOM_WIDTH, POS_EPS), "%s: RoomWidth=%.2f, expected %.2f" % [room, bd.RoomWidth, ROOM_WIDTH])
		_check(_approx(bd.SectionX, 0.0, POS_EPS), "%s: SectionX=%.2f, expected 0 (the painting starts at the room's left edge)" % [room, bd.SectionX])
		_check(_approx(bd.FillFrom, 0.0, POS_EPS) and _approx(bd.FillTo, ROOM_WIDTH, POS_EPS),
			"%s: FillFrom/FillTo = %.2f/%.2f, expected 0/%.2f (the painting is the whole room)" % [room, bd.FillFrom, bd.FillTo, ROOM_WIDTH])

		var back: Node = bd.get_node_or_null("Back")
		var mid: Node = bd.get_node_or_null("Mid")
		var floor: Node = bd.get_node_or_null("Floor")
		_check(back is Parallax2D, "%s: Back missing or not a Parallax2D" % room)
		_check(mid is Node2D and not (mid is Parallax2D), "%s: Mid missing or not a plain Node2D" % room)
		_check(floor is Node2D and not (floor is Parallax2D), "%s: Floor missing or not a plain Node2D" % room)
		if back == null or mid == null or floor == null:
			bd.queue_free()
			continue
		_check(back.z_index >= Z_BACK_MIN and back.z_index <= Z_BACK_MAX,
			"%s: Back z_index=%d, expected %d…%d (brief: parallax background)" % [room, back.z_index, Z_BACK_MIN, Z_BACK_MAX])
		_check(mid.z_index == Z_MID, "%s: Mid z_index=%d, expected %d (brief: room background)" % [room, mid.z_index, Z_MID])
		_check(floor.z_index == Z_FLOOR, "%s: Floor z_index=%d, expected %d (brief: floor)" % [room, floor.z_index, Z_FLOOR])
		_check(back.scroll_scale == Vector2(bd.BackScrollScale, 1.0),
			"%s: Back.scroll_scale=%s, expected (%s, 1)" % [room, back.scroll_scale, bd.BackScrollScale])
		var back_tex: Texture2D = bd.BackTexture
		_check(back_tex != null and back_tex.resource_path == SHARED_BACK,
			"%s: BackTexture is %s, expected the shared far layer %s (the level-wide tile grid needs one image in every room)" % [room, back_tex.resource_path if back_tex else null, SHARED_BACK])

		var fill_from: float = bd.FillFrom
		var fill_to: float = bd.FillTo
		var mids := _check_layer(room, mid, fill_from, fill_to)
		_check_layer(room, floor, fill_from, fill_to)
		edges.append([room_x + fill_from, room_x + fill_to])
		# The painting's own edges in level space; compared room to room in step 4.
		if not mids.is_empty():
			var painting: Sprite2D = mids[0]
			paintings.append([room_x + painting.position.x, room_x + painting.position.x + _world_width(painting)])

		# The Section sprite sits at SectionX (cropped to FillFrom); the drawn floor covers the band.
		var section: Node = mid.get_node_or_null("Section")
		_check(section is Sprite2D and _approx(section.position.x, maxf(bd.SectionX, fill_from), POS_EPS),
			"%s: Mid/Section at %s, expected x=%.2f" % [room, section.position if section else null, maxf(bd.SectionX, fill_from)])
		var floor_section: Sprite2D = floor.get_node_or_null("Section")
		if floor_section != null and floor_section.texture != null:
			var img: Image = floor_section.texture.get_image()
			var first_row := -1
			for row in img.get_height():
				if img.get_pixel(probe_column * IMPORT_SCALE, row).a > 0.0:
					first_row = row
					break
			var far_edge: float = floor_section.position.y + first_row * floor_section.scale.y
			var near_edge: float = floor_section.position.y + img.get_height() * floor_section.scale.y
			_check(first_row >= 0 and _approx(far_edge, DRAWN_FLOOR_TOP, EDGE_TOL),
				"%s: drawn floor far edge at world y=%.1f (texture row %d), expected the band's top %.0f — a hero on the far edge of the band would stand on the wall" % [room, far_edge, first_row, DRAWN_FLOOR_TOP])
			_check(_approx(near_edge, DRAWN_FLOOR_BOTTOM, EDGE_TOL),
				"%s: drawn floor ends at y=%.2f, expected %.2f (%.2f + %.0f * WorldScale)" % [room, near_edge, DRAWN_FLOOR_BOTTOM, EXPECTED_OFFSET_Y, MOCKUP_SIZE.y])
			_check(near_edge >= BAND_BOTTOM,
				"%s: drawn floor ends at y=%.1f, short of the band's bottom %.0f — the near part of the band has no floor under it" % [room, near_edge, BAND_BOTTOM])
			_check(near_edge - BAND_BOTTOM <= UNREACHABLE_FLOOR_MAX,
				"%s: drawn floor reaches y=%.1f, %.1f px below the band's bottom %.0f the hero can never step on" % [room, near_edge, near_edge - BAND_BOTTOM, BAND_BOTTOM])
		var mid_section: Sprite2D = mid.get_node_or_null("Section")
		if mid_section != null and mid_section.texture != null:
			var img: Image = mid_section.texture.get_image()
			var last_row := -1
			for row in img.get_height():
				if img.get_pixel(probe_column * IMPORT_SCALE, row).a > 0.0:
					last_row = row
			var wall_base: float = mid_section.position.y + (last_row + 1) * mid_section.scale.y
			_check(last_row >= 0 and _approx(wall_base, BAND_TOP, EDGE_TOL),
				"%s: wall base at world y=%.1f, expected the band's top %.0f (the wall ends where the walk band starts)" % [room, wall_base, BAND_TOP])
		# Under the feet of a hero on the band's far edge: floor ink, no wall ink.
		if mid_section != null and floor_section != null and mid_section.texture != null and floor_section.texture != null:
			var feet_y: float = BAND_TOP + FEET_PROBE_DEPTH
			var floor_row: int = int(floor((feet_y - floor_section.position.y) / floor_section.scale.y))
			var wall_row: int = int(floor((feet_y - mid_section.position.y) / mid_section.scale.y))
			var floor_a: float = floor_section.texture.get_image().get_pixel(probe_column * IMPORT_SCALE, floor_row).a
			var wall_a: float = mid_section.texture.get_image().get_pixel(probe_column * IMPORT_SCALE, wall_row).a
			_check(floor_a == 1.0 and wall_a == 0.0,
				"%s: at world y %.0f (the band's far edge) the hero stands on floor alpha %.2f / wall alpha %.2f (texture row %d), expected floor 1 / wall 0" % [room, feet_y, floor_a, wall_a, floor_row])

		# Far layer: tiles abut, sit on the level-wide grid, cover the window for every camera x.
		var tiles := _sprites(back)
		_check(tiles.size() >= 2, "%s: Back has %d tiles" % [room, tiles.size()])
		if not tiles.is_empty():
			var period: float = (bd.BackSlice.y - bd.BackSlice.x) * bd.WorldScale
			var cursor: float = tiles[0].position.x
			for t: Sprite2D in tiles:
				_check(_approx(t.position.x, cursor, POS_EPS), "%s/Back/%s: x=%.2f, expected %.2f (gap)" % [room, t.name, t.position.x, cursor])
				cursor = t.position.x + _world_width(t)
				var level_x: float = room_x + t.position.x
				var phase: float = fposmod(level_x, period)
				_check(phase < POS_EPS or period - phase < POS_EPS,
					"%s/Back/%s: level x=%.2f is not on the %.2f grid (phase %.2f)" % [room, t.name, level_x, period, phase])
			var slide: float = 1.0 - bd.BackScrollScale
			var first_x: float = room_x + tiles[0].position.x
			var last_x: float = room_x + cursor
			# The camera centres the far layer must cover. The camera is limited to the room and the
			# room is now exactly one window wide, so in play the centre settles on
			# room_x + ROOM_WIDTH/2; the sweep runs from half a window left of the room's left edge to
			# half a window right of its right edge — where the camera stands while the limits switch
			# to this room and it slides in, and the same range SectionBackdrop.BuildBack sizes its
			# tile span from. With ROOM_WIDTH == VIEW_WIDTH == 1280 the five samples below are the
			# centres room_x-640, room_x, room_x+640 (the settled one), room_x+1280 and room_x+1920.
			for f in [0.0, 0.25, 0.5, 0.75, 1.0]:
				var c: float = room_x - VIEW_WIDTH / 2.0 + f * (ROOM_WIDTH + VIEW_WIDTH)
				var shown_from: float = first_x + (c - VIEWPORT_PX / 2.0) * slide
				var shown_to: float = last_x + (c - VIEWPORT_PX / 2.0) * slide
				_check(shown_from <= c - VIEW_WIDTH / 2.0 and shown_to >= c + VIEW_WIDTH / 2.0,
					"%s: far layer shows %.0f…%.0f at camera centre %.0f, window %.0f…%.0f uncovered" % [room, shown_from, shown_to, c, c - VIEW_WIDTH / 2.0, c + VIEW_WIDTH / 2.0])
		bd.queue_free()

	# 4. The rooms tile the mine edge to edge: one painting per room, each beginning where the
	#    previous one ends. No fill column continues across a cut any more — there is nothing between
	#    two paintings at all, so a seam is simply "Face's right edge is Drift's left edge".
	if edges.size() == ROOMS.size():
		_check(_approx(edges[0][0], 0.0, POS_EPS), "Face starts at level x=%.2f, expected 0" % edges[0][0])
		for i in range(1, edges.size()):
			_check(_approx(edges[i - 1][1], edges[i][0], POS_EPS),
				"%s ends at %.2f but %s starts at %.2f (seam gap or double draw)" % [ROOMS[i - 1][0], edges[i - 1][1], ROOMS[i][0], edges[i][0]])
		_check(_approx(edges[edges.size() - 1][1], MINE_END, POS_EPS),
			"Patrol ends at level x=%.2f, expected the mine's end %.0f" % [edges[edges.size() - 1][1], MINE_END])
	if paintings.size() == ROOMS.size():
		for i in paintings.size():
			var room_x: float = ROOMS[i][1]
			_check(_approx(paintings[i][0], room_x, POS_EPS),
				"%s: the painting starts at level x=%.2f, expected the room's left edge %.0f" % [ROOMS[i][0], paintings[i][0], room_x])
			_check(_approx(paintings[i][1] - paintings[i][0], ROOM_WIDTH, POS_EPS),
				"%s: the painting is %.2f px wide, expected exactly one room (%.0f) — a %.0f px mockup at WorldScale %.6f" % [ROOMS[i][0], paintings[i][1] - paintings[i][0], ROOM_WIDTH, MOCKUP_SIZE.x, WORLD_SCALE])
		for i in range(1, paintings.size()):
			_check(_approx(paintings[i - 1][1], paintings[i][0], POS_EPS),
				"%s|%s seam: the %s painting ends at level x=%.2f but the %s painting begins at %.2f — the two rooms no longer meet at the room edge" % [ROOMS[i - 1][0], ROOMS[i][0], ROOMS[i - 1][0], paintings[i - 1][1], ROOMS[i][0], paintings[i][0]])
		_check(_approx(paintings[paintings.size() - 1][1], MINE_END, POS_EPS),
			"the last painting ends at level x=%.2f, expected the mine's end %.0f" % [paintings[paintings.size() - 1][1], MINE_END])

	# 5. The F6 scene: three backdrops, the walk band placeholder, the v2 camera zoom.
	var test_packed: PackedScene = load(TEST_SCENE)
	_check(test_packed != null, "%s did not load" % TEST_SCENE)
	if test_packed != null:
		var test_scene: Node = test_packed.instantiate()
		root.add_child(test_scene)
		await process_frame
		for entry in ROOMS:
			var node: Node2D = test_scene.get_node_or_null("Backdrop_%s" % entry[0])
			_check(node != null and _approx(node.position.x, entry[1], POS_EPS), "TestBackdrops: Backdrop_%s missing or not at x=%s" % [entry[0], entry[1]])
		var band: ColorRect = test_scene.get_node_or_null("PH_WalkBand")
		_check(band != null and band.offset_top == BAND_TOP and band.offset_bottom == BAND_BOTTOM,
			"TestBackdrops: PH_WalkBand missing or not %.0f…%.0f" % [BAND_TOP, BAND_BOTTOM])
		_check(band != null and _approx(band.offset_right - band.offset_left, MINE_END, POS_EPS),
			"TestBackdrops: PH_WalkBand spans %.0f px, expected the whole mine %.0f" % [(band.offset_right - band.offset_left) if band != null else 0.0, MINE_END])
		var lip: ColorRect = test_scene.get_node_or_null("PH_NearLip")
		var face_floor: Sprite2D = test_scene.get_node_or_null("Backdrop_Face/Floor/Section")
		if lip != null and face_floor != null and face_floor.texture != null:
			var floor_bottom: float = face_floor.position.y + face_floor.texture.get_height() * face_floor.scale.y
			_check(_approx(floor_bottom, DRAWN_FLOOR_BOTTOM, EDGE_TOL),
				"TestBackdrops: the drawn floor ends at y=%.2f, expected %.2f" % [floor_bottom, DRAWN_FLOOR_BOTTOM])
			_check(lip.offset_top >= floor_bottom - POS_EPS and lip.offset_top - floor_bottom <= EDGE_TOL,
				"TestBackdrops: PH_NearLip starts at y=%.2f but the drawn floor ends at %.2f" % [lip.offset_top, floor_bottom])
		else:
			_check(false, "TestBackdrops: PH_NearLip or Backdrop_Face/Floor/Section missing")
		var cam: Camera2D = test_scene.get_node_or_null("Camera2D")
		_check(cam != null and cam.zoom == CAMERA_ZOOM, "TestBackdrops: Camera2D missing or zoom != %s" % CAMERA_ZOOM)
		_check(cam != null and _approx(cam.limit_left, 0.0, LIMIT_SLACK) and _approx(cam.limit_right, MINE_END, LIMIT_SLACK),
			"TestBackdrops: Camera2D limits %d…%d, expected 0…%.0f (the three painted rooms)" % [cam.limit_left if cam != null else 0, cam.limit_right if cam != null else 0, MINE_END])
		# The far layer follows the camera limits: on while the limits overlap the room, off otherwise.
		if cam != null:
			var backs := {}
			for entry in ROOMS:
				backs[entry[0]] = test_scene.get_node_or_null("Backdrop_%s/Back" % entry[0])
			await _expect_backs(cam, backs, [0.0, MINE_END], {"Face": true, "Drift": true, "Patrol": true}, "limited to the whole mine")
			var patrol_x: float = ROOMS[2][1]
			await _expect_backs(cam, backs, [patrol_x, patrol_x + ROOM_WIDTH], {"Face": false, "Drift": false, "Patrol": true}, "limited to the patrol room")
			await _expect_backs(cam, backs, ROOM_SURFACE, {"Face": false, "Drift": false, "Patrol": false}, "limited to the surface room")
			await _expect_backs(cam, backs, [0.0, ROOM_WIDTH], {"Face": true, "Drift": false, "Patrol": false}, "limited to the face room")
		test_scene.queue_free()
		await process_frame

	_finish()
