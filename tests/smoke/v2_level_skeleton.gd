extends SceneTree
# Smoke: the v2 prologue is the v1 prologue in everything that is not art, up to one known map
# compression (T-V2-01, GAME_DESIGN §6a — «the same story, the same map, the same balance»).
# The v2 mine was compressed so that one room is exactly one painted section: a mine room is
# 1280 px wide where v1 gave it 2880, the surface room keeps its width and only slides left.
# Y is untouched. That transform is written down once in _map_x() below, and the comparison runs
# the v1 positions through it (an object moves on the map but is not squashed: _mapped_x() maps a
# prop's or an actor's own level position and keeps its internal offsets, see there) — so v2 is
# still pinned node for node: anything that moved or resized by something other than the
# compression, or changed in any way that is not art, still fails here.
# scenes/v2/levels/Level00_Prologue.tscn runs on the shared scripts/levels/Level00_Prologue.cs
# under its own uid, and against the v1 scene:
#   * every root [Export] (the 87 of Level00_Prologue.cs plus LevelBase's) compares equal —
#     NodePaths as strings, arrays element-wise, node refs by path, PackedScenes by resource path,
#     Vector2s exact — including the six cutscene line arrays and the 30 Dan*Line strings; the
#     four exports that are level positions (LEVEL_POS_EXPORTS) compare through _map_x();
#   * the gameplay tree compares equal (x through _map_x(), and the x extent of the level's own
#     trigger and blocker shapes — SHAPE_SCALED — through the same 4/9): for every node outside the dressing (Backgrounds,
#     Parallax, Backdrop, Ground, Props, Foreground, Fx_*, PH_* except the physical walls
#     PH_WallLeft/Right/Shaft, decals, arena lamp, landmarks and jam carts), outside the actors'
#     art (Visual/Rig, Visual/Sprite) and outside the HeldGuards figures (compared by name and
#     position only) the path, class, visibility, global position, collision layer/mask and shape
#     rect are the same; the camera is compared by its limits (v2 may zoom) and an actor's
#     Flashlight by its class and balance exports (DrainPerSecond, EnabledAtStart) — its
#     HeadOffset and BeamAngleDeg follow the drawn head, not the rig's.
# The skip list is the contract for steps 01b/01c: they may swap actors and dressing and this
# script must stay green; anything else that drifts fails here. One gameplay difference is
# deliberate and listed by path (V2_OMITTED): the author's playtest of 2026-09-12 took the crate
# row out of the v2 first room. The list is exact — each path must exist in v1 and be absent in
# v2 — so it is an exception, not a loosening of the comparison. Same for V2_ADDED (v2-only
# gameplay nodes, among them the two art-anchored belt props, which are placed off the mockup and
# therefore do not follow _map_x()) and for V2_ACCEPTED_TREE (both values pinned).
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
const PHYSICAL_PH := ["PH_Decals", "PH_ArenaLamp", "PH_JamCarts", "PH_WallLeft", "PH_WallRight", "PH_WallShaft"]
const PHYSICAL_PH_PREFIXES := ["PH_Landmark_"]
const ART_NODES := ["Rig", "Sprite"]    # under an actor's Visual
const ACTOR_LAMP := "Flashlight"        # under an actor's root: compared by class and balance, its offset is art
const LAMP_BALANCE := ["DrainPerSecond", "EnabledAtStart"]   # Flashlight exports that are balance, not art
const V2_OMITTED := ["Crate", "Crate/CollisionShape2D"]   # v2 deliberately without: the crate row (author's playtest 2026-09-12)
# Deliberate v2-only differences, listed with both values so a stale entry fails instead of hiding
# a drift. A path listed here is recorded raw on both sides — _map_x() is not applied to it — so
# each column is simply what its own scene holds; that is the point of an accepted difference.
const V2_ACCEPTED_TREE := {
	# T-V2-05 (the author's r2 concept of the first room, 2026-09-16): the mine rooms' camera limits
	# start 80 px higher so the painted beam, fan and lamps sit in the window, and the right limit
	# followed the compression — a mine room is 1280 px wide now. Camera limits are room bounds, not
	# a node position.
	"Camera2D": ["Camera2D | limits 0 0 2880 1080", "Camera2D | limits 0 -80 1280 1080"],
	# T-V2-06: the guide's gas-edge point moved onto the near side of the v2 belt gate. The shared
	# script leads him there the moment the timber falls, and a point behind a closed gate makes
	# CompanionLead warp him through it. The belt gate is art-anchored — placed off the painted
	# mockup, it did not compress with the map — so this point is hung on the gate's face (1597.65)
	# and deliberately does NOT follow _map_x(); v1 keeps its own 4340.
	"DanRoute/WP_gas_edge": ["Marker2D | visible true | at 4340.0,470.0", "Marker2D | visible true | at 1597.65,470.0"],
	# T-V2-06: the second outlet moved off the belt gate. The map compressed but the gate is
	# art-anchored and did not, so _map_x() put the v1 socket (3700) at 1644.44 — on the gate's face
	# (1637.65). There it stole the lever's interaction prompt from the hero stopped at the belt, and
	# it offered a socket standing behind a closed gate. At 1780 it keeps its v1 order (after the
	# timber, before the gas) and sits on the floor in front of the drawn conveyor, reachable once
	# the belt is stopped. The Area2D and its shape move together; the shape itself is unchanged.
	"Outlet_2": ["Area2D | visible true | at 3700.0,560.0 | layer 32 mask 0",
		"Area2D | visible true | at 1780.0,560.0 | layer 32 mask 0"],
	"Outlet_2/CollisionShape2D": [
		"CollisionShape2D | visible true | at 3700.0,560.0 | shape Rect2(-40, -40, 80, 80) | disabled false",
		"CollisionShape2D | visible true | at 1780.0,560.0 | shape Rect2(-40, -40, 80, 80) | disabled false"],
	# T-V2-06: the cage panel's reach was pulled in. Its radius is 48 and none of it compressed with
	# the room, so the v1 offset of -130 px from the hoist left the prompt reaching well past Dan's
	# cage route point: standing there already raised the panel prompt and it hid his line. The
	# offset is -40 in v2 (hoist at 8500 in v1 → _map_x() 3777.78 in v2), so the prompt starts past
	# the cage point again. The reach is an interaction circle, not level geometry, so it is not in
	# SHAPE_SCALED and its 96 px extent is unchanged on both sides.
	"Hoist/CollisionShape2D": [
		"CollisionShape2D | visible true | at 8370.0,450.0 | shape Rect2(-48, -48, 96, 96) | disabled false",
		"CollisionShape2D | visible true | at 3737.78,450.0 | shape Rect2(-48, -48, 96, 96) | disabled false"],
}
# Gameplay nodes the v2 prologue has and v1 does not: the belt gate of the ventilation room and its
# lever (T-V2-06, the author's r2 concept of section 2). Listed by path so a node that appears by
# accident still fails; every one of them must be absent from v1 and present in v2.
const V2_ADDED := ["ConveyorLine", "ConveyorLine/CollisionShape2D", "ConveyorLine/Belt",
	"ConveyorLine/RunLights", "ConveyorLine/StopLights",
	"ConveyorSwitch", "ConveyorSwitch/CollisionShape2D", "ConveyorSwitch/Lever"]
const MAX_REPORTED := 8                 # differences listed before the message is cut
const POS_DECIMALS := 2
# Numbers are written with POS_DECIMALS decimals on both sides and the mapped value carries the
# rounding of 4/9, so one tick of the last decimal is all the slack that is needed. Keep it far
# below the smallest real move a node could make (never raise it past 0.5 px).
const POS_EPS := 0.02
# The v2 map compression (2026-09-16): one v2 mine room is exactly one painted section.
const ROOM_V1 := 2880.0                 # a mine room's width in v1
const ROOM_V2 := 1280.0                 # ... and in v2 = one painted section
const LAST_MINE_ROOM := 2               # mine rooms are 0, 1, 2; everything past them is the surface
const SURFACE_V1 := 8640.0              # 3 * ROOM_V1 — where the surface room starts in v1
const SURFACE_V2 := 3840.0              # 3 * ROOM_V2 — ... and in v2; its width is unchanged
# Root [Export]s that are positions on the level's x axis and therefore move with the compression.
const LEVEL_POS_EXPORTS := ["DanStart", "HeroHeldAt", "DanHeldAt", "SurfaceArrival"]
# Shapes whose x extent is a level distance and therefore compresses with the map (2026-09-16):
# a trigger or a blocker volume authored in the level scene is measured in map units, and left at
# its v1 width it would be 2.25x wider in relative terms in a 1280-wide room — the wave trigger
# swallowed Outlet_1, the blast trigger reached the jam pile and the three patrol pools (420 wide,
# 249 apart) ran into each other. So their x position and x width go through the same 4/9 as a
# distance; y is untouched. Everything else keeps its shape on purpose and is still compared
# exactly: an actor's body and hitboxes, a shared prop scene's own shape (the checkpoints 80, the
# gas pockets 180, the debris piles 56) and every circular interaction reach — an actor must not
# change size. The list is exact in both directions: a path that stops compressing, or a level
# volume that starts to, fails the tree diff, and a path that disappears fails the check below.
# The three PH_Wall* blockers and LevelExit are deliberately NOT here: they are boundaries, not
# gameplay distances, and two of them stand in the surface room, which did not compress at all —
# they keep the authored 40 px thickness of RectangleShape2D_wall in both versions.
const SHAPE_SCALED := [
	"BlastTrigger/CollisionShape2D",
	"GuardWave/CollisionShape2D",           # an override of the shared WaveSpawner shape, declared in the v2 level
	"LitZone_Arena/CollisionShape2D",
	"LitZone_P1/CollisionShape2D", "LitZone_P2/CollisionShape2D", "LitZone_P3/CollisionShape2D",
	"Hoist/BoardingArea/CollisionShape2D",  # likewise overridden in the level, not the prop's own reach
	"Tutorial/MovePrompt/CollisionShape2D", "Tutorial/JumpPrompt/CollisionShape2D",
	"Tutorial/FlashlightPrompt/CollisionShape2D", "Tutorial/AttackPrompt/CollisionShape2D",
	"Tutorial/HeavyPrompt/CollisionShape2D",
]

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

# A v1 x in v2's compressed map. It exists so this script can keep comparing v2 node for node
# after the v2 mine was squeezed to one painted section per room: it encodes exactly that squeeze
# and nothing else. Each of the three mine rooms keeps its index and its offset inside the room is
# scaled by ROOM_V2 / ROOM_V1 (4/9); the surface room past SURFACE_V1 keeps its width and is only
# slid left by the 4800 px the mine lost. Y is not touched. Applied to the v1 side, so a v2 node
# that sits anywhere else than at _map_x(its v1 x) is still a failure.
func _map_x(x: float) -> float:
	if x >= SURFACE_V1:
		return SURFACE_V2 + (x - SURFACE_V1)
	var k: float = clampf(floorf(x / ROOM_V1), 0.0, float(LAST_MINE_ROOM))
	return k * ROOM_V2 + (x - k * ROOM_V1) * (ROOM_V2 / ROOM_V1)

# Equal as strings, or equal field by field with numbers within POS_EPS — the mapped v1 value and
# the value written into the v2 scene may differ in the last printed decimal. Non-numeric fields,
# field count and field order must match exactly, so this is a rounding tolerance, not a skip.
func _equivalent(a: String, b: String) -> bool:
	if a == b:
		return true
	var ta: PackedStringArray = a.replace(",", " ").replace("(", " ").replace(")", " ").split(" ", false)
	var tb: PackedStringArray = b.replace(",", " ").replace("(", " ").replace(")", " ").split(" ", false)
	if ta.size() != tb.size():
		return false
	for i in ta.size():
		if ta[i] == tb[i]:
			continue
		if not (ta[i].is_valid_float() and tb[i].is_valid_float()):
			return false
		if absf(ta[i].to_float() - tb[i].to_float()) > POS_EPS:
			return false
	return true

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

func _exports(level: Node, map_x: bool) -> Dictionary:
	var out := {}
	for prop in level.get_property_list():
		if prop.usage & PROPERTY_USAGE_SCRIPT_VARIABLE == 0:
			continue
		var value: Variant = level.get(prop.name)
		if map_x and prop.name in LEVEL_POS_EXPORTS and value is Vector2:
			value = Vector2(_map_x(value.x), value.y)
		out[prop.name] = _describe(level, value)
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

# Where a v1 node sits on the compressed map. The compression moves objects around the map, it
# does not squash them: a prop or an actor keeps its own geometry, so a guard's hitbox stays 30 px
# from his feet and a hoist's shape stays where it is on the hoist. The mapping is therefore
# applied once, to the object's level position — the outermost instanced sub-scene root on the way
# down from the level root, or the node itself when it is authored directly in the level — and
# everything inside that object keeps its unscaled local offset.
func _mapped_x(level: Node, node: Node2D) -> float:
	var anchor: Node2D = node
	var walk: Node = node.get_parent()
	while walk != null and walk != level:
		if walk is Node2D and walk.scene_file_path != "":
			anchor = walk
		walk = walk.get_parent()
	return _map_x(anchor.global_position.x) + (node.global_position.x - anchor.global_position.x)

# A Node2D's global position as recorded; on the v1 side the x goes through the compression first.
func _pos(level: Node, node: Node2D, map_x: bool) -> String:
	var x: float = _mapped_x(level, node) if map_x else node.global_position.x
	return "%s,%s" % [_fmt(x), _fmt(node.global_position.y)]

# scale_shape: this node's shape is level geometry, so its x extent compresses like a distance.
func _record(level: Node, node: Node, map_x: bool, scale_shape: bool) -> String:
	var parts: PackedStringArray = [node.get_class()]
	if node.name == ACTOR_LAMP and node.get_parent() is CharacterBody2D:
		for key in LAMP_BALANCE:
			parts.append("%s %s" % [key, var_to_str(node.get(key))])
		return " | ".join(parts)
	if node is Camera2D:
		# Camera limits are the room bounds, not a node position: compared raw and pinned as a
		# deliberate v2 difference in V2_ACCEPTED_TREE.
		parts.append("limits %d %d %d %d" % [node.limit_left, node.limit_top, node.limit_right, node.limit_bottom])
		return " | ".join(parts)
	if node is CanvasItem:
		parts.append("visible %s" % node.visible)
	if node is Node2D:
		parts.append("at %s" % _pos(level, node, map_x))
	if node is CollisionObject2D:
		parts.append("layer %d mask %d" % [node.collision_layer, node.collision_mask])
	if node is CollisionShape2D:
		var shape: Shape2D = node.shape
		var rect: String = "none"
		if shape != null:
			var r: Rect2 = shape.get_rect()
			if scale_shape:
				var k: float = ROOM_V2 / ROOM_V1
				r = Rect2(r.position.x * k, r.position.y, r.size.x * k, r.size.y)
			rect = var_to_str(r)
		parts.append("shape %s" % rect)
		parts.append("disabled %s" % node.disabled)
	return " | ".join(parts)

func _walk(level: Node, node: Node, out: Dictionary, map_x: bool) -> void:
	for child in node.get_children():
		if _is_dressing(child):
			continue
		var path: String = str(level.get_path_to(child))
		# An accepted difference pins both scenes' own values, so it is never mapped.
		var mapped: bool = map_x and not V2_ACCEPTED_TREE.has(path)
		if node.name == "HeldGuards" and child is Node2D:
			# The held figures are rigs in v1 and sprites in v2: name and position are the contract.
			out[path] = "held at %s" % _pos(level, child, mapped)
			continue
		out[path] = _record(level, child, mapped, mapped and path in SHAPE_SCALED)
		if child is Camera2D:
			continue
		_walk(level, child, out, map_x)

# map_x: record this tree's x positions in v2's compressed map (true for the v1 scene only), so
# the diff below stays a plain string comparison.
func _snapshot(scene: PackedScene, map_x: bool) -> Dictionary:
	var level: Node = scene.instantiate()
	root.add_child(level)
	await _step(1)
	var snap := {"script": str(level.get_script().resource_path) if level.get_script() != null else "", "exports": _exports(level, map_x), "tree": {}}
	_walk(level, level, snap.tree, map_x)
	level.queue_free()
	await _step(2)
	return snap

# Keys of `accepted` (key → [v1 value, v2 value]) verified on both snapshots and returned for _diff to skip.
func _accept(label: String, a: Dictionary, b: Dictionary, accepted: Dictionary) -> Array:
	var keys: Array = []
	for key in accepted:
		var pair: Array = accepted[key]
		_check(_equivalent(str(a.get(key, "")), pair[0]), "%s: v1 %s is %s, expected %s — the accepted v2 difference is stale" % [label, key, a.get(key), pair[0]])
		_check(_equivalent(str(b.get(key, "")), pair[1]), "%s: v2 %s is %s, expected the deliberate %s" % [label, key, b.get(key), pair[1]])
		keys.append(key)
	return keys

func _diff(label: String, a: Dictionary, b: Dictionary, omitted: Array = []) -> void:
	var diffs: PackedStringArray = []
	for key in a:
		if key in omitted:
			continue
		if not b.has(key):
			diffs.append("%s missing in v2" % key)
		elif not _equivalent(str(a[key]), str(b[key])):
			diffs.append("%s: v1 (mapped) %s / v2 %s" % [key, a[key], b[key]])
	for key in b:
		if key in omitted:
			continue
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

	var s1: Dictionary = await _snapshot(v1, true)    # v1 recorded in v2's compressed map
	var s2: Dictionary = await _snapshot(v2, false)
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
	for key in LEVEL_POS_EXPORTS:
		# Otherwise a renamed export would quietly stop being mapped and compare raw against raw.
		_check(s1.exports.has(key), "no %s export to map — LEVEL_POS_EXPORTS is stale" % key)
	var dan_lines := 0
	for key in s2.exports:
		if key.begins_with("Dan") and key.ends_with("Line"):
			dan_lines += 1
	_check(dan_lines == DAN_LINE_COUNT, "the v2 prologue carries %d Dan*Line exports, expected %d" % [dan_lines, DAN_LINE_COUNT])
	_diff("root exports", s1.exports, s2.exports)

	# 2. The gameplay tree.
	_check(s1.tree.size() > 0 and s2.tree.size() > 0, "the tree walk recorded nothing (v1 %d, v2 %d nodes)" % [s1.tree.size(), s2.tree.size()])
	for path in V2_OMITTED:
		_check(s1.tree.has(path), "v1 has no gameplay node '%s' — the V2_OMITTED exception is stale" % path)
		_check(not s2.tree.has(path), "v2 still carries '%s', listed in V2_OMITTED as deliberately absent" % path)
	for path in SHAPE_SCALED:
		_check(s1.tree.has(path) and s2.tree.has(path), "no shape '%s' in v1 and v2 — SHAPE_SCALED is stale" % path)
	for path in V2_ADDED:
		_check(not s1.tree.has(path), "v1 already has '%s' — the V2_ADDED exception is stale" % path)
		_check(s2.tree.has(path), "v2 has no gameplay node '%s', listed in V2_ADDED as deliberately added" % path)
	_diff("gameplay tree", s1.tree, s2.tree, V2_OMITTED + V2_ADDED + _accept("gameplay tree", s1.tree, s2.tree, V2_ACCEPTED_TREE))
	print("v2_level_skeleton: %d exports and %d gameplay nodes compared" % [s2.exports.size(), s2.tree.size()])
	_finish()
