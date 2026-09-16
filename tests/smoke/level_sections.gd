extends SceneTree
# Smoke: the level — the two painted sections of level 0 and nothing else. The author's rule is
# that the second painting starts exactly where the first one ends, so the two backdrops have to
# be adjacent to the pixel. The two of them are one corridor, not two arenas: a single RoomBounds
# spans both, so the camera pans across the seam instead of stopping at the end of the first
# painting (his playtest of 2026-09-16 — the camera did not follow him out of section 1). Also
# checks the cast (Ray, Dan, one guard), the belt gate that closes the drift, the two checkpoints,
# the side walls that hold the hero inside the two paintings, and that nothing placeholder is
# drawn.
# Run: godot --headless --path . -s tests/smoke/level_sections.gd

const NAME := "level_sections"
const LEVEL_PATH := "res://scenes/levels/Level00_Sections.tscn"
const MAIN_PATH := "res://scenes/Main.tscn"
const SECTION_WIDTH := 1280.0        # one painting, in world px
const CORRIDOR_WIDTH := 2560.0       # both paintings: the playable span and the camera span
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

	# One room spanning both paintings: the hero walks out of the first into the second and the
	# camera goes with him. A room per painting stops the camera dead at the seam.
	var rooms: Node = _node(level, "Rooms")
	if rooms != null:
		_check(rooms.get_child_count() == 1,
			"the level has %d RoomBounds; the two paintings are one corridor and need exactly one, or the camera stops at the seam" % rooms.get_child_count())
	var mine: Node = _node(level, "Rooms/Room_Mine")
	if mine != null:
		var r: Rect2 = mine.Rect
		_check(is_zero_approx(r.position.x), "the corridor starts at x %.2f, expected 0" % r.position.x)
		_check(is_equal_approx(r.size.x, CORRIDOR_WIDTH),
			"the corridor is %.2f px wide, expected both paintings (%.0f)" % [r.size.x, CORRIDOR_WIDTH])
		_check(is_equal_approx(mine.FloorTop, WALK_TOP) and is_equal_approx(mine.FloorBottom, WALK_BOTTOM),
			"walk band %.1f..%.1f, expected %.1f..%.1f" % [mine.FloorTop, mine.FloorBottom, WALK_TOP, WALK_BOTTOM])

	# The two paintings, adjacent to the pixel: the second begins exactly where the first ends.
	var backdrops: Node = _node(level, "Backgrounds")
	if backdrops != null:
		_check(backdrops.get_child_count() == 2,
			"Backgrounds holds %d backdrops, expected exactly the two painted sections" % backdrops.get_child_count())
	var bd_face: Node2D = level.get_node_or_null("Backgrounds/Backdrop_Face")
	var bd_drift: Node2D = level.get_node_or_null("Backgrounds/Backdrop_Drift")
	_check(bd_face != null and is_zero_approx(bd_face.position.x), "Backdrop_Face is not at x 0")
	if bd_face != null and bd_drift != null:
		_check(absf(bd_drift.position.x - (bd_face.position.x + SECTION_WIDTH)) <= EPS,
			"section 2 is painted from x %.2f but section 1 ends at x %.2f — the paintings must be adjacent" % [bd_drift.position.x, bd_face.position.x + SECTION_WIDTH])

	# The camera may pan the whole corridor, not just the painting the hero started on.
	var cam: Camera2D = level.get_node_or_null("Camera2D")
	if cam != null and mine != null:
		_check(cam.limit_left == int(mine.Rect.position.x) and cam.limit_right == int(mine.Rect.end.x),
			"camera limits %d…%d, expected the whole corridor %d…%d — otherwise it stops at the seam" % [cam.limit_left, cam.limit_right, int(mine.Rect.position.x), int(mine.Rect.end.x)])

	# The cast: Ray in section 1, Dan behind him, one guard at the far end of section 2.
	var player: Node2D = _node(level, "Player")
	var dan: Node2D = _node(level, "Dan")
	var guard: Node2D = _node(level, "Guard")
	if player != null:
		_check(player.global_position.x < SECTION_WIDTH, "Ray starts at x %.2f, outside section 1" % player.global_position.x)
		_check(player.global_position.y >= WALK_TOP and player.global_position.y <= WALK_BOTTOM,
			"Ray starts at y %.2f, outside the walk band" % player.global_position.y)
	if dan != null and player != null:
		_check(dan.Target == player, "Dan does not follow Ray")
	if guard != null:
		_check(guard.global_position.x > SECTION_WIDTH * 1.5 and guard.global_position.x < CORRIDOR_WIDTH,
			"the guard stands at x %.2f, expected the far half of section 2 (%.0f..%.0f)" % [guard.global_position.x, SECTION_WIDTH * 1.5, CORRIDOR_WIDTH])
	# The level wakes the guard on ready, so he has the hero as a target and a director.
	_check(level.StandingGuard == guard, "the level's StandingGuard is not the guard in the scene")
	_check(level.Director != null, "the level has no EnemyDirector")
	_check(level.StartRoom == mine, "the level does not apply the corridor bounds on ready")

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
		_check(belt.global_position.x > SECTION_WIDTH and belt.global_position.x < CORRIDOR_WIDTH,
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
		for cp_name in ["Checkpoint_Face", "Checkpoint_Drift"]:
			var cp: Node2D = level.get_node_or_null("Checkpoints/" + cp_name)
			_check(cp != null and cp.Room == mine,
				"%s does not carry the corridor bounds; a respawn there would trap the camera in one painting" % cp_name)

	# The side walls close the two paintings off; there is nothing painted beyond them.
	var left: Node2D = _node(level, "WallLeft")
	var right: Node2D = _node(level, "WallRight")
	if left != null and right != null:
		_check(left.global_position.x < SECTION_WIDTH * 0.5, "WallLeft is not at the start of section 1")
		_check(right.global_position.x > CORRIDOR_WIDTH - 100.0 and right.global_position.x <= CORRIDOR_WIDTH,
			"WallRight is at x %.2f, expected the end of section 2 (%.0f)" % [right.global_position.x, CORRIDOR_WIDTH])

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
