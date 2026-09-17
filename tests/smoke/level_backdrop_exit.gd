extends SceneTree
# Smoke: the painted backdrop of the exit hall — the third painted room of the v2 prologue
# (scenes/levels/Backdrop_Exit.tscn, cut from the author's r2 concept of section 3 by
# tools/derive_section3_r2.py). The level does not know about this room yet, so the scene is tested
# on its own: it is instantiated at the origin, which is exactly how SectionBackdrop treats it
# (SectionX 0, everything relative to the node; the level only moves the node to x 2560).
# Headless has no renderer, so this asserts the data the picture is made of:
#
#   * import — the three world layers are the derived files and import at svg/scale 3 (2040x1320),
#     every animated crop is its own texture of crop size x 3 and carries ink (a crop that cut
#     nothing would pass placement checks and draw nothing);
#   * placement — every overlay is re-derived here from the mockup coordinates of its crop through
#     the room's own placement (WorldScale 1280/680, OffsetY = 300 − 280·WorldScale, ImportScale 3)
#     and must sit on the very pixels the painting was cut from, at the layer scale, with no
#     texture offset (crop origin == pivot: these pieces blink, they do not turn);
#   * blinking — the camera lamp, the three locker cell indicators and the two loose power banks are
#     BackdropOverlays in Blink, and the five indicators have **pairwise different periods** and
#     seeds, so they never blink as one row of lamps; the schedule itself is checked through
#     BlinkAlpha (on inside the on phase, BlinkOffAlpha outside it);
#   * the cage gate — Static, named CageGate, drawn over the mid layer: the game opens the cage by
#     hiding or sliding this one sprite, so it must not be baked into the mid layer. The mid layer
#     is probed at the gate's centre mullion (mockup 492,140) and must show the same shaft ink
#     there as next to it;
#   * the guards — the two painted figures of the concept appear in NO derived layer (the game puts
#     two real Guard actors there). Their group transforms and their own two colours are asserted
#     absent from every derived file.
# Run: godot --headless --path . -s tests/smoke/level_backdrop_exit.gd

const NAME := "level_backdrop_exit"   # must equal the file basename
const MAX_FRAMES := 600
const SCENE := "res://scenes/levels/Backdrop_Exit.tscn"
const ART := "res://assets/art/v2/backgrounds/level0_section3_exit_r2_"
# The far layer is one level-wide tiled image, shared by every painted room, so this one is
# section 1's (tests/smoke/level_backdrops.gd asserts the sharing across the whole corridor).
const SHARED_BACK := "res://assets/art/v2/backgrounds/level0_section1_mineface_r2_back.svg"
const OVERLAY_SCRIPT := "res://scripts/levels/BackdropOverlay.cs"
# The one-painting placement of every mine room (see tests/smoke/level_backdrops.gd).
const SECTION_X := 0.0
const WORLD_SCALE := 1280.0 / 680.0
const OFFSET_Y := 300.0 - 280.0 * WORLD_SCALE
const IMPORT_SCALE := 3.0
const LAYER_SCALE := WORLD_SCALE / IMPORT_SCALE
const MOCKUP_SIZE := Vector2(680.0, 440.0)
const TEXTURE_SIZE := Vector2(2040.0, 1320.0)   # MOCKUP_SIZE x IMPORT_SCALE
const Z_MID_FX := -39             # just above the painted mid layer (-40)
const Z_FLOOR_FX := -19           # just above the painted floor layer (-20)
const MOTION_STATIC := 0
const MOTION_BLINK := 1
# Every overlay: name, crop origin in mockup px (tools/derive_section3_r2.py CROPS), crop size in
# mockup px, z, motion. The crop origin is also the pivot — these pieces do not turn.
const OVERLAYS := [
	["CameraLamp", Vector2(82, 148), Vector2(12, 12), Z_MID_FX, MOTION_BLINK],
	["CellA", Vector2(301, 221), Vector2(6, 6), Z_MID_FX, MOTION_BLINK],
	["CellB", Vector2(325, 253), Vector2(6, 6), Z_MID_FX, MOTION_BLINK],
	["CellC", Vector2(313, 237), Vector2(6, 6), Z_MID_FX, MOTION_BLINK],
	["BankA", Vector2(80, 316), Vector2(12, 10), Z_FLOOR_FX, MOTION_BLINK],
	["BankB", Vector2(551, 367), Vector2(16, 12), Z_FLOOR_FX, MOTION_BLINK],
	["CageGate", Vector2(380, 98), Vector2(224, 184), Z_MID_FX, MOTION_STATIC],
]
# The overlay -> derived file, by the suffix of the file it must draw.
const TEXTURES := {"CameraLamp": "camera_lamp", "CellA": "cell_a", "CellB": "cell_b", "CellC": "cell_c",
	"BankA": "bank_a", "BankB": "bank_b", "CageGate": "cage_gate"}
# The five indicators the room blinks; their periods must differ from one another.
const INDICATORS := ["CellA", "CellB", "CellC", "BankA", "BankB"]
# The two painted guards of the concept: their group transforms and the two colours only they use.
const GUARD_MARKS := ["translate(-156,-96)", "translate(-58,-96)", "#d8a878", "#20242e"]
# The concept's <pattern> fills: ThorVG draws none of them, so no derivative may still reference one
# (gradients it does draw, and those keep their url(#…) references).
const PATTERNS := ["hatch", "dots", "stripes", "grate", "grate2", "grain2", "floorgrain", "gravel", "steel"]
const DERIVED := ["mid", "floor", "camera_lamp", "cell_a", "cell_b", "cell_c", "bank_a", "bank_b", "cage_gate"]
# The cage's centre mullion and a column of bare shaft next to it, in mockup px: with the gate cut
# out of the mid layer these two columns show the same ink (the gate is a separate sprite).
const MULLION := Vector2i(492, 140)
const BARE_SHAFT := Vector2i(470, 140)
const INK_TOL := 0.04             # per-channel colour slack between the two shaft probes
const EPS := 0.05                 # world px: a .tscn stores positions rounded to two decimals
const SCALE_EPS := 0.001

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
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

func _approx(a: float, b: float, eps: float = EPS) -> bool:
	return absf(a - b) <= eps

func _at(got: Vector2, want: Vector2) -> bool:
	return absf(got.x - want.x) <= EPS and absf(got.y - want.y) <= EPS

# World point of a mockup point of this room's section (relative to the backdrop node).
func _world(mockup: Vector2) -> Vector2:
	return Vector2(SECTION_X + mockup.x * WORLD_SCALE, OFFSET_Y + mockup.y * WORLD_SCALE)

func _sprites(layer: Node) -> Array:
	var list: Array = []
	for c in layer.get_children():
		if c is Sprite2D:
			list.append(c)
	return list

func _run() -> void:
	# 1. The derived files: the guards are in none of them, and the layers import at svg/scale 3.
	for name in DERIVED:
		var path: String = ART + name + ".svg"
		var f := FileAccess.open(path, FileAccess.READ)
		_check(f != null, "%s is missing — run python tools/derive_section3_r2.py" % path)
		if f == null:
			continue
		var text: String = f.get_as_text()
		for mark in GUARD_MARKS:
			_check(not text.contains(mark),
				"%s still holds the painted guard (%s) — the game puts two real Guard actors there, a painted duplicate next to a real one is what the author rejected" % [path, mark])
		_check(not text.contains("<text"), "%s holds <text>, which ThorVG never draws" % path)
		for pattern in PATTERNS:
			_check(not text.contains("url(#%s)" % pattern),
				"%s still fills with <pattern> %s, which ThorVG never draws — it must be flattened to its average coverage" % [path, pattern])

	for name in ["back", "mid", "floor"]:
		var tex: Texture2D = load(ART + name + ".svg")
		_check(tex != null, "%s_%s.svg did not load" % [ART, name])
		if tex != null:
			_check(tex.get_size() == TEXTURE_SIZE,
				"%s%s.svg is %s, expected %s (svg/scale=%d)" % [ART, name, tex.get_size(), TEXTURE_SIZE, int(IMPORT_SCALE)])

	# 2. The scene: the one-painting exports and the three layers of the derivation.
	var packed: PackedScene = load(SCENE)
	_check(packed != null, "%s did not load" % SCENE)
	if packed == null:
		_finish()
		return
	var bd: Node2D = packed.instantiate()
	root.add_child(bd)
	await process_frame

	_check(_approx(bd.WorldScale, WORLD_SCALE, SCALE_EPS),
		"WorldScale=%.6f, expected %.6f (1280 / 680: one mockup is exactly the camera window)" % [bd.WorldScale, WORLD_SCALE])
	_check(_approx(bd.SectionX, SECTION_X) and _approx(bd.FillFrom, 0.0) and _approx(bd.FillTo, 1280.0) and _approx(bd.RoomWidth, 1280.0),
		"SectionX/FillFrom/FillTo/RoomWidth = %.2f/%.2f/%.2f/%.2f, expected 0/0/1280/1280 (the painting is the whole room)" % [bd.SectionX, bd.FillFrom, bd.FillTo, bd.RoomWidth])
	_check(_approx(bd.OffsetY, OFFSET_Y, EPS), "OffsetY=%.4f, expected %.4f (300 − 280 · WorldScale)" % [bd.OffsetY, OFFSET_Y])

	# The far layer is one level-wide tiled image shared by every painted room, so Back draws
	# section 1's; only Mid and Floor are this section's own.
	for entry in [["Back", SHARED_BACK], ["Mid", ART + "mid.svg"], ["Floor", ART + "floor.svg"]]:
		var layer: Node = bd.get_node_or_null(String(entry[0]))
		_check(layer != null, "the backdrop has no %s layer" % entry[0])
		if layer == null:
			continue
		var list := _sprites(layer)
		_check(not list.is_empty(), "%s holds no sprite" % entry[0])
		var want: String = String(entry[1])
		for s: Sprite2D in list:
			var path: String = s.texture.resource_path if s.texture != null else ""
			_check(path == want, "%s/%s draws %s, expected the derived %s" % [entry[0], s.name, path, want])
			_check(not s.centered and _approx(s.scale.x, LAYER_SCALE, SCALE_EPS) and _approx(s.scale.y, LAYER_SCALE, SCALE_EPS),
				"%s/%s: expected centered=false and scale %.4f, got %s" % [entry[0], s.name, LAYER_SCALE, s.scale])
			_check(_approx(s.position.y, OFFSET_Y, 1.0),
				"%s/%s: y=%.2f, expected %.2f" % [entry[0], s.name, s.position.y, OFFSET_Y])
		# One room is one painting: Mid and Floor are the section sprite alone, no filler slices.
		# (Back is the far-layer Parallax2D: it tiles one column of the back texture across the room.)
		if entry[0] != "Back":
			_check(list.size() == 1 and list[0].name == "Section",
				"%s holds %d sprites, expected exactly the Section (a room is one painting)" % [entry[0], list.size()])

	# 3. The overlays: each on the pixels its crop was cut from, at its own crop size, with ink.
	for entry in OVERLAYS:
		var node_name: String = entry[0]
		var crop: Vector2 = entry[1]
		var size: Vector2 = entry[2]
		var node: Sprite2D = bd.get_node_or_null(node_name)
		_check(node != null, "the backdrop has no %s overlay" % node_name)
		if node == null:
			continue
		var script: Script = node.get_script()
		_check(script != null and script.resource_path == OVERLAY_SCRIPT,
			"%s runs %s, expected %s" % [node_name, script.resource_path if script != null else "no script", OVERLAY_SCRIPT])
		var want_path: String = ART + String(TEXTURES[node_name]) + ".svg"
		var tex_path: String = node.texture.resource_path if node.texture != null else ""
		_check(tex_path == want_path, "%s draws %s, expected %s" % [node_name, tex_path, want_path])
		if node.texture != null:
			_check(node.texture.get_size() == size * IMPORT_SCALE,
				"%s texture is %s, expected the crop %s x %d" % [node_name, node.texture.get_size(), size, int(IMPORT_SCALE)])
			var img: Image = node.texture.get_image()
			var ink := 0
			for y in range(0, img.get_height()):
				for x in range(0, img.get_width()):
					if img.get_pixel(x, y).a > 0.3:
						ink += 1
			_check(ink > 0, "%s cut nothing: its crop is empty" % node_name)
		_check(_at(node.global_position, _world(crop)),
			"%s at %s, expected the mockup point %s = %s" % [node_name, node.global_position, crop, _world(crop)])
		_check(node.offset.is_equal_approx(Vector2.ZERO),
			"%s offset %s, expected zero (crop origin == pivot)" % [node_name, node.offset])
		_check(not node.centered and _approx(node.scale.x, LAYER_SCALE, SCALE_EPS) and _approx(node.scale.y, LAYER_SCALE, SCALE_EPS),
			"%s: expected centered=false and scale %.4f, got %s" % [node_name, LAYER_SCALE, node.scale])
		_check(node.z_index == int(entry[3]), "%s z_index=%d, expected %d" % [node_name, node.z_index, int(entry[3])])
		_check(int(node.Motion) == int(entry[4]), "%s.Motion=%s, expected %d" % [node_name, node.Motion, int(entry[4])])
		if int(entry[4]) == MOTION_BLINK:
			_check(node.BlinkPeriod > 0.0, "%s.BlinkPeriod=%.2f, expected a positive period" % [node_name, node.BlinkPeriod])
			_check(_approx(node.BlinkAlpha(node.BlinkPeriod * node.BlinkOnFraction * 0.5), 1.0),
				"%s: BlinkAlpha inside the on phase is not 1" % node_name)
			_check(_approx(node.BlinkAlpha(node.BlinkPeriod * (node.BlinkOnFraction + 1.0) * 0.5), node.BlinkOffAlpha),
				"%s: BlinkAlpha inside the off phase is not BlinkOffAlpha" % node_name)

	# 3b. The camera lamp keeps blinking through a blackout (it is the station's own eye).
	var lamp: Sprite2D = bd.get_node_or_null("CameraLamp")
	if lamp != null:
		_check(not lamp.NeedsPower, "CameraLamp.NeedsPower is on — a surveillance blink must survive the blackout")

	# 4. The five indicators are out of sync: pairwise different periods and seeds.
	for i in range(0, INDICATORS.size()):
		for j in range(i + 1, INDICATORS.size()):
			var a: Sprite2D = bd.get_node_or_null(String(INDICATORS[i]))
			var b: Sprite2D = bd.get_node_or_null(String(INDICATORS[j]))
			if a == null or b == null:
				continue
			_check(not _approx(a.BlinkPeriod, b.BlinkPeriod, 0.01),
				"%s and %s both blink every %.2f s — the indicators would pulse as one row" % [INDICATORS[i], INDICATORS[j], a.BlinkPeriod])
			_check(a.Seed != b.Seed,
				"%s and %s share Seed %d" % [INDICATORS[i], INDICATORS[j], a.Seed])

	# 5. The cage gate is a sprite, not ink in the mid layer: the mid layer shows bare shaft where
	#    the gate's centre mullion is drawn, and the gate crop draws that mullion itself.
	var mid_tex: Texture2D = load(ART + "mid.svg")
	if mid_tex != null:
		var mid: Image = mid_tex.get_image()
		var at_mullion: Color = mid.get_pixel(int(MULLION.x * IMPORT_SCALE), int(MULLION.y * IMPORT_SCALE))
		var at_shaft: Color = mid.get_pixel(int(BARE_SHAFT.x * IMPORT_SCALE), int(BARE_SHAFT.y * IMPORT_SCALE))
		_check(absf(at_mullion.r - at_shaft.r) <= INK_TOL and absf(at_mullion.g - at_shaft.g) <= INK_TOL and absf(at_mullion.b - at_shaft.b) <= INK_TOL,
			"the mid layer differs at the gate's mullion (%s) from the bare shaft next to it (%s) — the gate is still baked into the mid layer and hiding the sprite would not open the cage" % [at_mullion, at_shaft])
	var gate_tex: Texture2D = load(ART + "cage_gate.svg")
	if gate_tex != null:
		var gate: Image = gate_tex.get_image()
		var local: Vector2i = MULLION - Vector2i(380, 98)
		_check(gate.get_pixel(int(local.x * IMPORT_SCALE), int(local.y * IMPORT_SCALE)).a > 0.9,
			"the cage gate crop is transparent at its own centre mullion (mockup %s)" % MULLION)

	bd.queue_free()
	_finish()
