extends SceneTree
# Smoke: the level — the two painted sections of level 0 and nothing else. The author's rule is
# that the second painting starts exactly where the first one ends, so the room rects have to be
# adjacent to the pixel and each backdrop has to sit on its room's left edge. Also checks the cast
# (Ray, Dan, one guard), the belt gate that closes the drift, the two checkpoints, the side walls
# that hold the hero inside the two paintings, and that the level draws no placeholder art.
# Run: godot --headless --path . -s tests/smoke/level_sections.gd

const NAME := "level_sections"
const LEVEL_PATH := "res://scenes/levels/Level00_Sections.tscn"
const MAIN_PATH := "res://scenes/Main.tscn"
const SECTION_WIDTH := 1280.0        # one painting, in world px
const WALK_TOP := 300.0
const WALK_BOTTOM := 600.0
const EPS := 0.01
# Subtrees that are not level dressing: their own scenes own whatever they draw.
const ACTOR_AND_UI_BRANCHES := ["Player", "Dan", "Guard", "HUD", "PauseMenu"]

var _done := false
var _failures: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _node(level: Node, path: String) -> Node:
	var n: Node = level.get_node_or_null(path)
	_check(n != null, "%s is missing from the level" % path)
	return n

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	var packed: PackedScene = load(LEVEL_PATH)
	_check(packed != null, "%s failed to load" % LEVEL_PATH)
	if packed == null:
		return _finish()

	var level: Node = packed.instantiate()
	root.add_child(level)

	# Main starts this level and nothing else.
	var main: PackedScene = load(MAIN_PATH)
	if main != null:
		var main_node: Node = main.instantiate()
		_check(main_node.StartLevel != null and main_node.StartLevel.resource_path == LEVEL_PATH,
			"Main.StartLevel is '%s', expected '%s'" % [
				main_node.StartLevel.resource_path if main_node.StartLevel else "<null>", LEVEL_PATH])
		main_node.free()

	# The two rooms are one painting wide and adjacent: section 2 begins where section 1 ends.
	var face: Node = _node(level, "Rooms/Room_Face")
	var drift: Node = _node(level, "Rooms/Room_Drift")
	if face != null and drift != null:
		var a: Rect2 = face.Rect
		var b: Rect2 = drift.Rect
		_check(is_equal_approx(a.size.x, SECTION_WIDTH), "Room_Face is %.2f px wide, expected %.2f" % [a.size.x, SECTION_WIDTH])
		_check(is_equal_approx(b.size.x, SECTION_WIDTH), "Room_Drift is %.2f px wide, expected %.2f" % [b.size.x, SECTION_WIDTH])
		_check(absf(a.end.x - b.position.x) <= EPS,
			"section 2 starts at x %.2f but section 1 ends at x %.2f — the paintings must be adjacent" % [b.position.x, a.end.x])
		for room in [face, drift]:
			_check(is_equal_approx(room.FloorTop, WALK_TOP) and is_equal_approx(room.FloorBottom, WALK_BOTTOM),
				"%s walk band %.1f..%.1f, expected %.1f..%.1f" % [room.name, room.FloorTop, room.FloorBottom, WALK_TOP, WALK_BOTTOM])

	# One backdrop per room, each on its room's left edge.
	var backdrops: Node = _node(level, "Backgrounds")
	if backdrops != null:
		_check(backdrops.get_child_count() == 2,
			"Backgrounds holds %d backdrops, expected exactly the two painted sections" % backdrops.get_child_count())
		var bd_face: Node2D = level.get_node_or_null("Backgrounds/Backdrop_Face")
		var bd_drift: Node2D = level.get_node_or_null("Backgrounds/Backdrop_Drift")
		_check(bd_face != null and is_zero_approx(bd_face.position.x), "Backdrop_Face is not at x 0")
		_check(bd_drift != null and is_equal_approx(bd_drift.position.x, SECTION_WIDTH),
			"Backdrop_Drift is at x %s, expected %.1f" % [bd_drift.position.x if bd_drift else "<missing>", SECTION_WIDTH])

	# The cast: Ray in section 1, Dan behind him, one guard at the far end of section 2.
	var player: Node2D = _node(level, "Player")
	var dan: Node2D = _node(level, "Dan")
	var guard: Node2D = _node(level, "Guard")
	if player != null and drift != null:
		_check(player.global_position.x < SECTION_WIDTH, "Ray starts at x %.2f, outside section 1" % player.global_position.x)
		_check(player.global_position.y >= WALK_TOP and player.global_position.y <= WALK_BOTTOM,
			"Ray starts at y %.2f, outside the walk band" % player.global_position.y)
	if dan != null and player != null:
		_check(dan.Target == player, "Dan does not follow Ray")
	if guard != null and drift != null:
		var b2: Rect2 = drift.Rect
		_check(guard.global_position.x > b2.get_center().x and guard.global_position.x < b2.end.x,
			"the guard stands at x %.2f, expected the far half of section 2 (%.0f..%.0f)" % [guard.global_position.x, b2.get_center().x, b2.end.x])
	# The level wakes the guard on ready, so he has the hero as a target and a director.
	_check(level.StandingGuard == guard, "the level's StandingGuard is not the guard in the scene")
	_check(level.Director != null, "the level has no EnemyDirector")
	_check(level.StartRoom == face, "the level does not start in section 1")

	# There is exactly one guard: the section-2 one.
	var guards: int = 0
	for n in _walk(level):
		if n.get_script() != null and str(n.get_script().resource_path).ends_with("/Guard.cs"):
			guards += 1
	_check(guards == 1, "the level holds %d guards, expected exactly one" % guards)

	# The belt gate: it runs at start and its face blocks the drift until the lever is thrown.
	var belt: Node2D = _node(level, "ConveyorLine")
	var lever: Node2D = _node(level, "ConveyorSwitch")
	if belt != null and lever != null:
		_check(belt.Running, "the conveyor is not running at the start, so nothing blocks the drift")
		_check(lever.Line == belt, "the lever is not wired to the conveyor")
		if drift != null:
			var r: Rect2 = drift.Rect
			_check(belt.global_position.x > r.position.x and belt.global_position.x < r.end.x,
				"the conveyor sits at x %.2f, outside section 2" % belt.global_position.x)
			_check(lever.global_position.x < belt.global_position.x,
				"the lever is behind the belt; the hero could never reach it")
		# The author's complaint of 2026-09-16 was a gate he could not get past. The lever's reach
		# rectangle must therefore run right up to the face of the belt: a hero walked into the
		# stopped-dead belt is still inside it and still sees the prompt.
		var reach: CollisionShape2D = lever.get_node_or_null("CollisionShape2D")
		var blocker: CollisionShape2D = belt.BlockerShape
		if reach != null and blocker != null and reach.shape != null and blocker.shape != null:
			var reach_right: float = reach.global_position.x + reach.shape.size.x * 0.5
			var reach_top: float = reach.global_position.y - reach.shape.size.y * 0.5
			var reach_bottom: float = reach.global_position.y + reach.shape.size.y * 0.5
			var belt_face: float = blocker.global_position.x - blocker.shape.size.x * 0.5
			_check(reach_right >= belt_face - EPS,
				"the lever's reach ends at x %.2f but the belt blocks from x %.2f — a hero stopped by the belt loses the prompt" % [reach_right, belt_face])
			_check(reach_top <= WALK_TOP + EPS and reach_bottom >= WALK_BOTTOM - EPS,
				"the lever's reach covers y %.1f..%.1f, not the whole walk band %.1f..%.1f" % [reach_top, reach_bottom, WALK_TOP, WALK_BOTTOM])

	# Both rooms have a checkpoint, each bound to its own room.
	var checkpoints: Node = _node(level, "Checkpoints")
	if checkpoints != null:
		_check(checkpoints.get_child_count() == 2,
			"there are %d checkpoints, expected one per section" % checkpoints.get_child_count())
		var cp_face: Node2D = level.get_node_or_null("Checkpoints/Checkpoint_Face")
		var cp_drift: Node2D = level.get_node_or_null("Checkpoints/Checkpoint_Drift")
		_check(cp_face != null and cp_face.Room == face, "Checkpoint_Face is not bound to Room_Face")
		_check(cp_drift != null and cp_drift.Room == drift, "Checkpoint_Drift is not bound to Room_Drift")

	# The side walls close the two paintings off; there is nothing painted beyond them.
	var left: Node2D = _node(level, "WallLeft")
	var right: Node2D = _node(level, "WallRight")
	if left != null and right != null and face != null and drift != null:
		_check(left.global_position.x < SECTION_WIDTH * 0.5, "WallLeft is not at the start of section 1")
		_check(right.global_position.x > drift.Rect.end.x - 100.0 and right.global_position.x <= drift.Rect.end.x,
			"WallRight is at x %.2f, expected the end of section 2 (%.0f)" % [right.global_position.x, drift.Rect.end.x])

	# Nothing placeholder is drawn in the world. The actors and the menus carry PH_ nodes of their
	# own (Dan's lamp cone, the pause dimmer) and are not part of the painted rooms, so the scan
	# skips their subtrees and covers the level dressing, which is what the author sees.
	for branch in level.get_children():
		if str(branch.name) in ACTOR_AND_UI_BRANCHES:
			continue
		for n in _walk(branch):
			if n is CanvasItem and n.visible and str(n.name).begins_with("PH_"):
				_check(false, "%s draws placeholder art in a painted room" % level.get_path_to(n))

	level.free()
	return _finish()

func _walk(node: Node) -> Array:
	var out: Array = []
	for c in node.get_children():
		out.append(c)
		out.append_array(_walk(c))
	return out

func _finish() -> bool:
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)
	return true
