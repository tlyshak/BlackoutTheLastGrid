extends SceneTree
# Smoke: the painted keyframe sprite pipeline — the four generated SpriteFrames in
# scenes/actors/*Frames.tres are exactly what tools/build_spriteframes.gd derives from the
# region maps (assets/art/v2/keyframes/<sheet>.frames.json) and the animation table
# (scenes/actors/sprite_animations.json): the sheets are the derived copies under
# assets/art/v2/sprites/ (tools/derive_sprite_sheets.py: the author's keyframe boards without the
# baked canvas rect, row stripes and labels) and import at svg/scale 2.0 (1360x1600 for the 680x800
# viewBox), every table animation exists with one frame per key (>= 1) and the table's loop
# flag, every frame is an AtlasTexture on the sheet whose region is the pose bbox x2 and lies inside
# the texture, whose margin pads it to the sheet's uniform cell (region.size + margin.size is the
# same for every frame of a sheet), whose feet line and origin x land on the cell's shared feet
# line / origin (no per-pose centring), whose four corner texels are fully transparent (the pose
# bbox is tight to the ink, so an opaque corner means the sheet still carries the board background
# and the actor would draw a dark card), and nothing else is in the resource (no leftover
# "default"). Then the three actor scenes in scenes/actors/: Visual/Sprite carries the right
# SpriteFrames at scale 0.5, never autoplays, and its position puts the cell's feet line on the
# actor origin (Visual.position.y + Sprite.position.y + (feet - cellH/2) * 0.5 == 0 +- 1 px, with
# Visual at -SpriteFeetOffset where the script has that export); PH_Shadow is
# hidden (the poses bake their own shadow). No physics needed.
# Run: godot --headless --path . -s tests/smoke/actors_spriteframes.gd

const NAME := "actors_spriteframes"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s).
const MAX_FRAMES := 600
const TABLE_PATH := "res://scenes/actors/sprite_animations.json"
const IMPORT_SCALE := 2.0       # svg/scale in the sprites/*.svg.import sidecars
const SHEET_DIR := "res://assets/art/v2/sprites/"   # the derived sheets; keyframes/ still has the board chrome
const SPRITE_SCALE := Vector2(0.5, 0.5)
const FEET_TOL := 1.0           # px the feet line may miss the actor origin by
# actor id in the table -> the v2 scene that must carry its frames
const ACTOR_SCENES := {
	"RayUnarmed": "res://scenes/actors/Player.tscn",
	"Guard": "res://scenes/actors/Guard.tscn",
	"Dan": "res://scenes/actors/Companion.tscn",
}
const EXPECTED_ACTORS := ["RayUnarmed", "RayCrowbar", "Dan", "Guard"]

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

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_check(false, "%s: file not found" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		_check(false, "%s: JSON parse error at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data

func _run() -> void:
	var table: Variant = _read_json(TABLE_PATH)
	if table == null or not (table is Dictionary) or not table.has("actors"):
		_check(false, "%s: missing or without 'actors'" % TABLE_PATH)
		_finish()
		return
	var actors: Dictionary = table["actors"]
	for id in EXPECTED_ACTORS:
		_check(actors.has(id), "table lacks actor '%s'" % id)
	for id in actors:
		_check_actor(id, actors[id])
	_finish()

# One actor: texture size, resource vs. table+map, and (when it has one) the actor scene.
func _check_actor(id: String, actor: Dictionary) -> void:
	var map: Variant = _read_json(actor.get("map", ""))
	if map == null or not (map is Dictionary) or not map.has("poses") or not map.has("uniform_cell"):
		_check(false, "%s: region map %s unusable" % [id, actor.get("map", "")])
		return
	_check(String(actor["sheet"]).begins_with(SHEET_DIR), "%s: table sheet %s is not under %s (the keyframe boards carry a baked background)" % [id, actor["sheet"], SHEET_DIR])
	var tex: Texture2D = load(actor["sheet"])
	_check(tex != null, "%s: sheet %s did not load" % [id, actor["sheet"]])
	if tex == null:
		return
	var texels: Image = tex.get_image()
	_check(texels != null, "%s: sheet %s has no readable image (cannot check the region corners)" % [id, actor["sheet"]])
	var expected_size := Vector2(float(map["viewbox"][0]), float(map["viewbox"][1])) * IMPORT_SCALE
	_check(tex.get_size() == expected_size, "%s: sheet imports at %s, expected %s (svg/scale=%s in the .import sidecar)" % [id, tex.get_size(), expected_size, IMPORT_SCALE])
	var s: float = IMPORT_SCALE
	var cell: Dictionary = map["uniform_cell"]
	var cell_size := Vector2(float(cell["w"]), float(cell["h"])) * s
	var feet_y: float = float(cell["feet_from_top"]) * s
	var origin_x: float = float(cell["origin_x_from_left"]) * s
	var poses: Dictionary = map["poses"]
	var feet_per_pose: Dictionary = map.get("feet_y_per_pose", {})

	var frames: SpriteFrames = load(actor["output"])
	_check(frames != null, "%s: %s did not load as SpriteFrames" % [id, actor["output"]])
	if frames == null:
		return
	var anims: Dictionary = actor["animations"]
	var names: Array = []
	for n in frames.get_animation_names():
		names.append(String(n))
	for n in names:
		_check(anims.has(n), "%s: resource has animation '%s' that is not in the table" % [id, n])
	for anim_name in anims:
		_check(frames.has_animation(anim_name), "%s: animation '%s' missing from %s" % [id, anim_name, actor["output"]])
		if not frames.has_animation(anim_name):
			continue
		var keys: Array = anims[anim_name]["keys"]
		var count: int = frames.get_frame_count(anim_name)
		_check(count >= 1, "%s/%s: %d frames, expected >= 1" % [id, anim_name, count])
		_check(count == keys.size(), "%s/%s: %d frames, expected %d (one per table key)" % [id, anim_name, count, keys.size()])
		_check(frames.get_animation_loop(anim_name) == bool(anims[anim_name].get("loop", false)), "%s/%s: loop=%s, expected %s" % [id, anim_name, frames.get_animation_loop(anim_name), anims[anim_name].get("loop", false)])
		_check(is_equal_approx(frames.get_animation_speed(anim_name), 1.0), "%s/%s: speed=%s, expected 1.0 (never played)" % [id, anim_name, frames.get_animation_speed(anim_name)])
		for i in mini(count, keys.size()):
			_check_frame(id, anim_name, i, String(keys[i][1]), frames.get_frame_texture(anim_name, i), tex, texels, poses, feet_per_pose, s, cell_size, feet_y, origin_x)

	if ACTOR_SCENES.has(id):
		_check_scene(id, ACTOR_SCENES[id], actor["output"], cell_size, feet_y)

func _check_frame(id: String, anim_name: String, i: int, pose_id: String, texture: Texture2D, sheet: Texture2D, texels: Image, poses: Dictionary, feet_per_pose: Dictionary, s: float, cell_size: Vector2, feet_y: float, origin_x: float) -> void:
	var label := "%s/%s[%d]=%s" % [id, anim_name, i, pose_id]
	_check(poses.has(pose_id), "%s: pose not in the region map" % label)
	if not poses.has(pose_id):
		return
	_check(texture is AtlasTexture, "%s: frame texture is %s, expected AtlasTexture" % [label, texture])
	if not (texture is AtlasTexture):
		return
	var atlas := texture as AtlasTexture
	_check(atlas.atlas != null and atlas.atlas.resource_path == sheet.resource_path, "%s: atlas is %s, expected the sheet %s" % [label, atlas.atlas.resource_path if atlas.atlas else "null", sheet.resource_path])
	var pose: Dictionary = poses[pose_id]
	var expected_region := Rect2(float(pose["x"]), float(pose["y"]), float(pose["w"]), float(pose["h"]))
	expected_region = Rect2(expected_region.position * s, expected_region.size * s)
	_check(atlas.region.is_equal_approx(expected_region), "%s: region %s, expected %s (bbox x %s)" % [label, atlas.region, expected_region, s])
	_check(Rect2(Vector2.ZERO, sheet.get_size()).encloses(atlas.region), "%s: region %s leaves the %s texture" % [label, atlas.region, sheet.get_size()])
	var m: Array = pose["margin"]
	var expected_margin := Rect2(float(m[0]) * s, float(m[1]) * s, (float(m[0]) + float(m[2])) * s, (float(m[1]) + float(m[3])) * s)
	_check(atlas.margin.is_equal_approx(expected_margin), "%s: margin %s, expected %s" % [label, atlas.margin, expected_margin])
	var padded: Vector2 = atlas.region.size + atlas.margin.size
	_check(padded.is_equal_approx(cell_size), "%s: padded frame %s, expected the uniform cell %s" % [label, padded, cell_size])
	if feet_per_pose.has(pose_id):
		var feet: float = atlas.margin.position.y + (float(feet_per_pose[pose_id]) - float(pose["y"])) * s
		_check(is_equal_approx(feet, feet_y), "%s: feet line at %s in the cell, expected the shared %s" % [label, feet, feet_y])
	var ox: float = atlas.margin.position.x + (float(pose["origin"][0]) - float(pose["x"])) * s
	_check(is_equal_approx(ox, origin_x), "%s: origin x at %s in the cell, expected the shared %s" % [label, ox, origin_x])
	if texels != null:
		_check_region_corners(label, texels, atlas.region)

# The "no card" check: the pose bbox is tight to the ink and no figure fills its corners, so the four
# corner texels of the region must be fully transparent. An opaque corner means the texture still
# carries the sheet's board background (the keyframes/ original) and the actor draws a dark card.
func _check_region_corners(label: String, texels: Image, region: Rect2) -> void:
	var r := Rect2i(region)
	var size: Vector2i = texels.get_size()
	for corner in [r.position, Vector2i(r.end.x - 1, r.position.y), Vector2i(r.position.x, r.end.y - 1), r.end - Vector2i.ONE]:
		if not Rect2i(Vector2i.ZERO, size).has_point(corner):
			continue
		var a: float = texels.get_pixelv(corner).a
		_check(is_zero_approx(a), "%s: corner texel %s of the region is opaque (alpha %.2f) - the sheet still carries the board background, so the actor draws a dark card; derive it with tools/derive_sprite_sheets.py and point the table at assets/art/v2/sprites/" % [label, corner, a])

# The actor scene wiring: the right SpriteFrames, scale 0.5, no autoplay, feet on the origin.
func _check_scene(id: String, scene_path: String, frames_path: String, cell_size: Vector2, feet_y: float) -> void:
	var scene: PackedScene = load(scene_path)
	_check(scene != null, "%s: %s failed to load" % [id, scene_path])
	if scene == null:
		return
	var actor: Node = scene.instantiate()
	var sprite: AnimatedSprite2D = actor.get_node_or_null("Visual/Sprite")
	var visual: Node2D = actor.get_node_or_null("Visual")
	var shadow: CanvasItem = actor.get_node_or_null("PH_Shadow")
	_check(sprite != null, "%s: no Visual/Sprite AnimatedSprite2D" % scene_path)
	_check(visual != null, "%s: no Visual" % scene_path)
	_check(shadow != null and not shadow.visible, "%s: PH_Shadow missing or visible (the poses bake their own shadow)" % scene_path)
	if sprite == null or visual == null:
		actor.free()
		return
	_check(sprite.sprite_frames != null and sprite.sprite_frames.resource_path == frames_path, "%s: Visual/Sprite.sprite_frames is %s, expected %s" % [scene_path, sprite.sprite_frames.resource_path if sprite.sprite_frames else "null", frames_path])
	_check(sprite.scale == SPRITE_SCALE, "%s: Visual/Sprite.scale %s, expected %s" % [scene_path, sprite.scale, SPRITE_SCALE])
	_check(sprite.centered, "%s: Visual/Sprite.centered is false, the feet arithmetic assumes a centred sprite" % scene_path)
	_check(String(sprite.autoplay) == "", "%s: Visual/Sprite.autoplay '%s', expected '' (the AnimationPlayer is the only clock)" % [scene_path, sprite.autoplay])
	_check(is_zero_approx(sprite.position.x), "%s: Visual/Sprite.position.x %s, expected 0 (the cell's origin x is its centre)" % [scene_path, sprite.position.x])
	# Player/Guard re-place Visual at -SpriteFeetOffset on ready; the scene value must already be it.
	var feet_offset: Variant = actor.get("SpriteFeetOffset")
	if feet_offset != null:
		_check(is_equal_approx(visual.position.y, -float(feet_offset)), "%s: Visual.position.y %s, expected -SpriteFeetOffset (%s)" % [scene_path, visual.position.y, -float(feet_offset)])
	var feet_world: float = visual.position.y + sprite.position.y + (feet_y - cell_size.y * 0.5) * sprite.scale.y
	_check(absf(feet_world) <= FEET_TOL, "%s: the cell's feet line lands %.1f px from the actor origin (Visual.position.y %s, Sprite.position.y %s, feet %s, cell h %s), expected 0 +- %s" % [scene_path, feet_world, visual.position.y, sprite.position.y, feet_y, cell_size.y, FEET_TOL])
	actor.free()
