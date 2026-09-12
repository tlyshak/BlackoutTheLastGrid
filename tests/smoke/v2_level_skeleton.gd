extends SceneTree
# Smoke: the v2 prologue is the v1 prologue in everything that is not art (T-V2-01, GAME_DESIGN
# §6a — «the same story, the same map, the same balance»). scenes/v2/levels/Level00_Prologue.tscn
# runs on the shared scripts/levels/Level00_Prologue.cs under its own uid, and against the v1
# scene:
#   * every root [Export] (the 87 of Level00_Prologue.cs plus LevelBase's) compares equal —
#     NodePaths as strings, arrays element-wise, node refs by path, PackedScenes by resource path,
#     Vector2s exact — including the six cutscene line arrays and the 30 Dan*Line strings;
#   * the gameplay tree compares equal: for every node outside the dressing (Backgrounds,
#     Parallax, Backdrop, Ground, Props, Foreground, Fx_*, PH_* except the walls, decals, arena
#     lamp, landmarks and jam carts that are physical), outside the actors' art (Visual/Rig,
#     Visual/Sprite) and outside the HeldGuards figures (compared by name and position only) the
#     path, class, global position, collision layer/mask and shape rect are the same; the camera
#     is compared by its limits (v2 may zoom) and an actor's Flashlight by its class only (its
#     HeadOffset follows the drawn head, not the rig's).
# The skip list is the contract for steps 01b/01c: they may swap actors and dressing and this
# script must stay green; anything else that drifts fails here.
# Run: godot --headless --path . -s tests/smoke/v2_level_skeleton.gd

const NAME := "v2_level_skeleton"   # must equal the file basename
const MAX_FRAMES := 6000
const PROLOGUE_V1 := "res://scenes/levels/Level00_Prologue.tscn"
const PROLOGUE_V2 := "res://scenes/v2/levels/Level00_Prologue.tscn"
const LEVEL_SCRIPT := "res://scripts/levels/Level00_Prologue.cs"
const MIN_EXPORTS := 87                 # Level00_Prologue.cs alone; LevelBase adds its own on top
const LINE_ARRAYS := ["IntroLines", "ChargeLines", "BlastLines", "GuardsLines", "HeldLines", "EndLines"]
const DAN_LINE_COUNT := 30
const DRESSING_ROOTS := ["Backgrounds", "Parallax", "Backdrop", "Ground", "Props", "Foreground"]
const PHYSICAL_PH := ["PH_Decals", "PH_ArenaLamp", "PH_JamCarts"]
const PHYSICAL_PH_PREFIXES := ["PH_Wall", "PH_Landmark_"]
const ART_NODES := ["Rig", "Sprite"]    # under an actor's Visual
const ACTOR_LAMP := "Flashlight"        # under an actor's root: compared by class, its offset is art
const MAX_REPORTED := 8                 # differences listed before the message is cut
const POS_DECIMALS := 2

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

func _step(frames: int) -> void:
	for i in frames:
		await physics_frame

func _finish() -> void:
	paused = false
	Engine.time_scale = 1.0
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

# One export value as a comparable String, so v1 and v2 can be diffed value by value.
func _describe(level: Node, value: Variant) -> String:
	if value is Node:
		return "node:" + str(level.get_path_to(value))
	if value is Resource:
		return "res:" + value.resource_path
	if value is Array:
		var parts: PackedStringArray = []
		for item in value:
			parts.append(_describe(level, item))
		return "[" + ", ".join(parts) + "]"
	if value is NodePath:
		return "path:" + str(value)
	return var_to_str(value)

func _exports(level: Node) -> Dictionary:
	var out := {}
	for prop in level.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		out[prop.name] = _describe(level, level.get(prop.name))
	return out

func _is_dressing(node: Node) -> bool:
	var n: String = node.name
	if n in DRESSING_ROOTS or n.begins_with("Fx_"):
		return true
	if n.begins_with("PH_"):
		if n in PHYSICAL_PH:
			return false
		for prefix in PHYSICAL_PH_PREFIXES:
			if n.begins_with(prefix):
				return false
		return true
	if n in ART_NODES and node.get_parent() != null and node.get_parent().name == "Visual":
		return true
	return false

func _fmt(v: float) -> String:
	return String.num(v, POS_DECIMALS)

func _record(node: Node) -> String:
	var parts: PackedStringArray = [node.get_class()]
	if node.name == ACTOR_LAMP and node.get_parent() is CharacterBody2D:
		return " | ".join(parts)
	if node is Camera2D:
		parts.append("limits %d %d %d %d" % [node.limit_left, node.limit_top, node.limit_right, node.limit_bottom])
		return " | ".join(parts)
	if node is Node2D:
		parts.append("at %s,%s" % [_fmt(node.global_position.x), _fmt(node.global_position.y)])
	if node is CollisionObject2D:
		parts.append("layer %d mask %d" % [node.collision_layer, node.collision_mask])
	if node is CollisionShape2D:
		var shape: Shape2D = node.shape
		parts.append("shape %s" % (var_to_str(shape.get_rect()) if shape != null else "none"))
		parts.append("disabled %s" % node.disabled)
	return " | ".join(parts)

func _walk(level: Node, node: Node, out: Dictionary) -> void:
	for child in node.get_children():
		if _is_dressing(child):
			continue
		var path: String = str(level.get_path_to(child))
		if node.name == "HeldGuards" and child is Node2D:
			# The held figures are rigs in v1 and sprites in v2: name and position are the contract.
			out[path] = "held at %s,%s" % [_fmt(child.global_position.x), _fmt(child.global_position.y)]
			continue
		out[path] = _record(child)
		if child is Camera2D:
			continue
		_walk(level, child, out)

func _snapshot(scene: PackedScene) -> Dictionary:
	var level: Node = scene.instantiate()
	root.add_child(level)
	await _step(1)
	var snap := {"script": str(level.get_script().resource_path) if level.get_script() != null else "", "exports": _exports(level), "tree": {}}
	_walk(level, level, snap.tree)
	level.queue_free()
	await _step(2)
	return snap

func _diff(label: String, a: Dictionary, b: Dictionary) -> void:
	var diffs: PackedStringArray = []
	for key in a:
		if not b.has(key):
			diffs.append("%s missing in v2" % key)
		elif a[key] != b[key]:
			diffs.append("%s: v1 %s / v2 %s" % [key, a[key], b[key]])
	for key in b:
		if not a.has(key):
			diffs.append("%s only in v2" % key)
	if diffs.is_empty():
		return
	var shown: PackedStringArray = diffs.slice(0, MAX_REPORTED)
	var more: String = " (+%d more)" % (diffs.size() - MAX_REPORTED) if diffs.size() > MAX_REPORTED else ""
	_check(false, "%s drifted between v1 and v2 - %d difference(s): %s%s" % [label, diffs.size(), ", ".join(shown), more])

func _run() -> void:
	var v1: PackedScene = load(PROLOGUE_V1)
	var v2: PackedScene = load(PROLOGUE_V2)
	_check(v1 != null, "%s failed to load" % PROLOGUE_V1)
	_check(v2 != null, "%s failed to load" % PROLOGUE_V2)
	if v1 == null or v2 == null:
		_finish()
		return
	var uid1: int = ResourceLoader.get_resource_uid(PROLOGUE_V1)
	var uid2: int = ResourceLoader.get_resource_uid(PROLOGUE_V2)
	_check(uid1 != ResourceUID.INVALID_ID and uid2 != ResourceUID.INVALID_ID and uid1 != uid2,
		"the v1 and v2 prologues must carry distinct valid uids (v1 %s, v2 %s)" % [ResourceUID.id_to_text(uid1), ResourceUID.id_to_text(uid2)])

	var s1: Dictionary = await _snapshot(v1)
	var s2: Dictionary = await _snapshot(v2)
	_check(s1.script == LEVEL_SCRIPT, "the v1 prologue runs %s, expected %s" % [s1.script, LEVEL_SCRIPT])
	_check(s2.script == LEVEL_SCRIPT, "the v2 prologue runs %s, expected the shared %s (no scripts/v2/)" % [s2.script, LEVEL_SCRIPT])
	if s2.exports.is_empty():
		_check(false, "the v2 prologue exposes no script exports — Level00_Prologue.cs not attached (did dotnet build run?)")
		_finish()
		return

	# 1. Exports: count, the story arrays and Dan's lines present, every value equal.
	_check(s1.exports.size() >= MIN_EXPORTS, "the v1 prologue exposes %d exports, expected at least %d" % [s1.exports.size(), MIN_EXPORTS])
	_check(s2.exports.size() == s1.exports.size(), "the v2 prologue exposes %d exports, v1 %d" % [s2.exports.size(), s1.exports.size()])
	for key in LINE_ARRAYS:
		_check(s2.exports.has(key), "the v2 prologue has no %s export" % key)
	var dan_lines := 0
	for key in s2.exports:
		if key.begins_with("Dan") and key.ends_with("Line"):
			dan_lines += 1
	_check(dan_lines == DAN_LINE_COUNT, "the v2 prologue carries %d Dan*Line exports, expected %d" % [dan_lines, DAN_LINE_COUNT])
	_diff("root exports", s1.exports, s2.exports)

	# 2. The gameplay tree.
	_check(s1.tree.size() > 0 and s2.tree.size() > 0, "the tree walk recorded nothing (v1 %d, v2 %d nodes)" % [s1.tree.size(), s2.tree.size()])
	_diff("gameplay tree", s1.tree, s2.tree)
	print("v2_level_skeleton: %d exports and %d gameplay nodes compared" % [s2.exports.size(), s2.tree.size()])
	_finish()
