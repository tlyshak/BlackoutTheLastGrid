extends SceneTree
# tools/build_spriteframes.gd — headless generator of the v2 SpriteFrames (T-V2-01 01b).
#
# Reads scenes/actors/sprite_animations.json (animation -> pose sequence, one entry per actor)
# and every referenced <sheet>.frames.json (pose regions in viewBox px, feet line, per-pose margin
# to the sheet's uniform cell), loads the imported sheet textures and writes one SpriteFrames
# resource per actor to the table's `output` path. Every frame is an AtlasTexture whose region is
# the pose's bounding box scaled by the import scale and whose margin pads it to the uniform cell,
# so all frames of a sheet have the same size and their feet sit on the same line — the sprite is
# never centred per pose (the poses are asymmetric; the feet line is the anchor).
#
# Run (after `godot --headless --path . --import`):
#     godot --headless --path . -s tools/build_spriteframes.gd
# Exits 0 and prints `CELL <actor> <w> <h> feet=<y> origin_x=<x>` (texture px) plus the
# `Sprite.position.y` an actor scene needs at Sprite.scale 0.5 for feet at SpriteFeetOffset 36;
# exits 1 with a message when a pose referenced by the table is missing from the map, a region
# leaves the texture or a padded frame does not equal the cell.

const TABLE_PATH := "res://scenes/actors/sprite_animations.json"
const SPRITE_SCALE := 0.5        # AnimatedSprite2D.scale in the v2 actor scenes (2x import -> 1:1 viewBox px)
const SPRITE_FEET_OFFSET := 36.0 # Player/Guard/Companion.SpriteFeetOffset: Visual sits 36 px above the feet

var _errors: Array[String] = []

func _init() -> void:
	var table: Variant = _read_json(TABLE_PATH)
	if table == null or not (table is Dictionary) or not table.has("actors"):
		_fail("%s: missing or without an 'actors' object" % TABLE_PATH)
		_finish()
		return
	for actor_name in table["actors"]:
		_build_actor(actor_name, table["actors"][actor_name])
	_finish()

func _fail(msg: String) -> void:
	_errors.append(msg)
	printerr("build_spriteframes: " + msg)

func _finish() -> void:
	if _errors.is_empty():
		print("build_spriteframes: OK")
		quit(0)
	else:
		print("build_spriteframes: FAILED (%d error(s))" % _errors.size())
		quit(1)

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_fail("%s: file not found" % path)
		return null
	var text: String = FileAccess.get_file_as_string(path)
	var json := JSON.new()
	if json.parse(text) != OK:
		_fail("%s: JSON parse error at line %d: %s" % [path, json.get_error_line(), json.get_error_message()])
		return null
	return json.data

func _build_actor(actor_name: String, actor: Dictionary) -> void:
	for key in ["sheet", "map", "output", "animations"]:
		if not actor.has(key):
			_fail("%s: table entry lacks '%s'" % [actor_name, key])
			return
	var map: Variant = _read_json(actor["map"])
	if map == null or not (map is Dictionary) or not map.has("poses") or not map.has("uniform_cell") or not map.has("viewbox"):
		_fail("%s: %s is not a region map (needs poses / uniform_cell / viewbox)" % [actor_name, actor["map"]])
		return
	var tex: Texture2D = load(actor["sheet"])
	if tex == null:
		_fail("%s: sheet %s did not load (run --import first)" % [actor_name, actor["sheet"]])
		return
	var viewbox_w: float = float(map["viewbox"][0])
	var s: float = tex.get_width() / viewbox_w
	if not is_equal_approx(s * float(map["viewbox"][1]), float(tex.get_height())):
		_fail("%s: texture %dx%d is not a uniform scale of the %sx%s viewBox" % [actor_name, tex.get_width(), tex.get_height(), map["viewbox"][0], map["viewbox"][1]])
		return
	var cell: Dictionary = map["uniform_cell"]
	var cell_size := Vector2(float(cell["w"]) * s, float(cell["h"]) * s)
	var feet_y: float = float(cell["feet_from_top"]) * s
	var origin_x: float = float(cell["origin_x_from_left"]) * s
	var poses: Dictionary = map["poses"]
	var feet_per_pose: Dictionary = map.get("feet_y_per_pose", {})

	var frames := SpriteFrames.new()
	frames.remove_animation("default")
	var atlases: Dictionary = {}   # pose id -> AtlasTexture, shared between animations
	var errors_before: int = _errors.size()
	for anim_name in actor["animations"]:
		var anim: Dictionary = actor["animations"][anim_name]
		var keys: Array = anim.get("keys", [])
		if keys.is_empty():
			_fail("%s/%s: no keys" % [actor_name, anim_name])
			continue
		frames.add_animation(anim_name)
		frames.set_animation_loop(anim_name, bool(anim.get("loop", false)))
		frames.set_animation_speed(anim_name, 1.0)   # never played: the AnimationPlayer keys the frame
		for key in keys:
			var pose_id: String = String(key[1])
			if not poses.has(pose_id):
				_fail("%s/%s: pose '%s' is not in %s" % [actor_name, anim_name, pose_id, actor["map"]])
				continue
			if not atlases.has(pose_id):
				var atlas: AtlasTexture = _make_atlas(actor_name, pose_id, poses[pose_id], tex, s, cell_size, feet_y, origin_x, feet_per_pose)
				if atlas == null:
					continue
				atlases[pose_id] = atlas
			frames.add_frame(anim_name, atlases[pose_id], 1.0)
	if _errors.size() != errors_before:
		return
	var previous_uid: String = _header_uid(actor["output"])
	var err: Error = ResourceSaver.save(frames, actor["output"])
	if err != OK:
		_fail("%s: ResourceSaver.save(%s) failed with %s" % [actor_name, actor["output"], error_string(err)])
		return
	_pin_ids(actor["output"], previous_uid)
	var sprite_y: float = SPRITE_FEET_OFFSET - (feet_y - cell_size.y * 0.5) * SPRITE_SCALE
	print("CELL %s %d %d feet=%d origin_x=%d -> Sprite.position.y=%s at scale %s (%d poses, %d animations) -> %s" % [
		actor_name, int(cell_size.x), int(cell_size.y), int(feet_y), int(origin_x), sprite_y, SPRITE_SCALE, atlases.size(), frames.get_animation_names().size(), actor["output"]])

# The `uid="uid://..."` of an existing output, or "" for a new file. Headless ResourceSaver has no
# editor UID callback, so the uid is kept across regenerations here and created once by us.
func _header_uid(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var header: String = FileAccess.get_file_as_string(path).get_slice("\n", 0)
	var re := RegEx.create_from_string("uid=\"(uid://[0-9a-z]+)\"")
	var m: RegExMatch = re.search(header)
	return m.get_string(1) if m != null else ""

# Makes the saved text stable: the header carries a uid (the previous one, else a fresh
# ResourceUID id) and the sheet's ext_resource id is "1_sheet" instead of a random suffix, so
# re-running the generator on unchanged inputs produces a byte-identical file.
func _pin_ids(path: String, previous_uid: String) -> void:
	var text: String = FileAccess.get_file_as_string(path)
	var uid: String = previous_uid if previous_uid != "" else ResourceUID.id_to_text(ResourceUID.create_id())
	var header_end: int = text.find("\n")
	var header: String = text.substr(0, header_end)
	if not header.contains("uid="):
		header = header.trim_suffix("]") + " uid=\"%s\"]" % uid
	var re := RegEx.create_from_string("\\[ext_resource [^\\]]*id=\"([0-9]+_[0-9a-z]+)\"")
	var body: String = text.substr(header_end)
	var m: RegExMatch = re.search(body)
	if m != null:
		body = body.replace("\"%s\"" % m.get_string(1), "\"1_sheet\"")
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		_fail("%s: cannot reopen for writing (%s)" % [path, error_string(FileAccess.get_open_error())])
		return
	f.store_string(header + body)
	f.close()

# One AtlasTexture per pose: region = bbox * s, margin = the map's [left, top, right, bottom] * s
# (AtlasTexture.margin.position is the left/top offset, .size the total padding), which pads every
# pose to the sheet's uniform cell with the feet on the cell's feet line and the pose origin on
# the cell's origin_x. Both are re-derived here and checked, so a wrong margin in the map fails
# the build instead of producing a hovering or drifting figure.
func _make_atlas(actor_name: String, pose_id: String, pose: Dictionary, tex: Texture2D, s: float, cell_size: Vector2, feet_y: float, origin_x: float, feet_per_pose: Dictionary) -> AtlasTexture:
	for key in ["x", "y", "w", "h", "margin", "origin"]:
		if not pose.has(key):
			_fail("%s: pose '%s' lacks '%s'" % [actor_name, pose_id, key])
			return null
	var region := Rect2(float(pose["x"]) * s, float(pose["y"]) * s, float(pose["w"]) * s, float(pose["h"]) * s)
	var tex_rect := Rect2(Vector2.ZERO, tex.get_size())
	if not tex_rect.encloses(region):
		_fail("%s: pose '%s' region %s leaves the %s texture" % [actor_name, pose_id, region, tex.get_size()])
		return null
	var m: Array = pose["margin"]
	var margin := Rect2(float(m[0]) * s, float(m[1]) * s, (float(m[0]) + float(m[2])) * s, (float(m[1]) + float(m[3])) * s)
	var padded: Vector2 = region.size + margin.size
	if not padded.is_equal_approx(cell_size):
		_fail("%s: pose '%s' padded to %s, expected the uniform cell %s" % [actor_name, pose_id, padded, cell_size])
		return null
	if feet_per_pose.has(pose_id):
		var pose_feet: float = margin.position.y + (float(feet_per_pose[pose_id]) - float(pose["y"])) * s
		if not is_equal_approx(pose_feet, feet_y):
			_fail("%s: pose '%s' feet land at %s in the cell, expected %s" % [actor_name, pose_id, pose_feet, feet_y])
			return null
	var pose_origin_x: float = margin.position.x + (float(pose["origin"][0]) - float(pose["x"])) * s
	if not is_equal_approx(pose_origin_x, origin_x):
		_fail("%s: pose '%s' origin lands at x=%s in the cell, expected %s" % [actor_name, pose_id, pose_origin_x, origin_x])
		return null
	var atlas := AtlasTexture.new()
	atlas.atlas = tex
	atlas.region = region
	atlas.margin = margin
	atlas.filter_clip = true
	atlas.resource_name = pose_id
	atlas.resource_scene_unique_id = "Atlas_" + pose_id   # deterministic ids: re-running the generator is diff-free
	return atlas
