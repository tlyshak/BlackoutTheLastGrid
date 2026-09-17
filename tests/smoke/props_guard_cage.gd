extends SceneTree
# Smoke: the lift cage of the third painted section (T-V3-04) — the ambush the author asked for,
# «коли гравець проходить ближче, відкриваються ворота і виходять охоронці»: the cage stands shut
# with two guards inside it and springs when the hero comes near. Checks the prop's contract
# (Area2D on layer 0 / mask 2, monitoring, one rectangular trip wire, the export defaults), the
# geometry of that trip wire against the mockup coordinates of the painted cage, and the behaviour:
# shut and idle while the hero is away; one trigger opens it exactly once, emits Opened, hides the
# painted grate and — after OpenDelay, not before — walks both guards out to their exit markers
# inside the walk band, where each gets the hero as target and the level's EnemyDirector; walking
# back out and in again springs nothing; a guard freed from the tree is skipped and his fellow
# still comes out; a cage with no guards at all still opens.
# The fixture is assembled here from GuardCage.tscn, Guard.tscn and Player.tscn — the level scene
# does not carry the prop yet. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/props_guard_cage.gd

const NAME := "props_guard_cage"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s). Counts idle frames.
const MAX_FRAMES := 9000
const CAGE_SCENE := "res://scenes/props/GuardCage.tscn"
const CAGE_SCRIPT := "res://scripts/props/GuardCage.cs"
const GUARD_SCENE := "res://scenes/actors/Guard.tscn"
const PLAYER_SCENE := "res://scenes/actors/Player.tscn"
const DIRECTOR_SCRIPT := "res://scripts/core/EnemyDirector.cs"

# The third section's placement: backdrop at level x 2560, the r2 mockups are 680 px wide and the
# rooms 1280 (tools/derive_section3_r2.py's mapping, the same one props_live_cable.gd uses for the
# second section).
const SECTION_X := 2560.0
const SECTION_WIDTH := 1280.0
const WORLD_SCALE := 1280.0 / 680.0
const OFFSET_Y := -227.0588
# The painted cage opening, in mockup px of level0_section3_exit_r2.svg.
const OPENING_FROM := 382.0
const OPENING_TO := 602.0
# The two caged guards, feet on the floor of the cage, in mockup px and in world px.
const MOCKUP_FEET := [Vector2(446.0, 288.0), Vector2(544.0, 288.0)]
const GUARD_FEET := [Vector2(3399.5, 315.06), Vector2(3584.0, 315.06)]
# Where each of them comes out to: in front of the cage, inside the band, a step towards the hero.
const EXITS := [Vector2(3380.0, 420.0), Vector2(3560.0, 480.0)]
# The walk band of every room of the mine (RoomBounds.FloorTop / FloorBottom).
const BAND_TOP := 300.0
const BAND_BOTTOM := 600.0
# Where the level places the prop, and the floor its trip wire covers.
const CAGE_POS := Vector2(3240.0, 450.0)
const TRIP_SIZE := Vector2(400.0, 300.0)
const MIN_RUN_UP := 400.0          # px of section the hero must get through before the trap fires

const PLAYER_LAYER := 2            # project.godot 2d_physics/layer_2="Player"
const EXPECTED_DELAY := 0.35
const EXPECTED_ARRIVE := 6.0
const EXPECTED_TIMEOUT := 3.0
const EXPECTED_WALK_ANIM := "walk"
const EPS := 0.05
const SETTLE := 4                  # physics frames to let a teleport settle
const EARLY_SAMPLE := 10           # frames after the trigger, still inside OpenDelay (0.35 s = 21)
const TRIP_FRAMES := 260           # frames allowed for delay + the whole walk out (~120 needed)
const OPEN_FRAMES := 60            # frames allowed for an empty cage to open
const ARRIVE_EPS := 8.0            # ArriveDistance plus a hair, in px
# The hero's two spots: far down the drift, and the near corner of the trip wire — inside the
# trigger, but far enough from the exits that nobody lands a punch before the test is done (a
# hit-stop freezes physics frames, which is what this script counts).
const HERO_AWAY := Vector2(2700.0, 450.0)
const HERO_TRIP := Vector2(3060.0, 590.0)

var _started := false
var _frames := 0
var _failures: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _process(_delta: float) -> bool:
	# First frame: start the coroutine (no await here). Returning false keeps the main loop running
	# so the awaits inside _run() resume; _run() itself calls quit().
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

func _approx(a: float, b: float, eps: float = EPS) -> bool:
	return absf(a - b) <= eps

func _world_x(mockup_x: float) -> float:
	return SECTION_X + mockup_x * WORLD_SCALE

func _world(mockup: Vector2) -> Vector2:
	return Vector2(_world_x(mockup.x), OFFSET_Y + mockup.y * WORLD_SCALE)

func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

# Builds the fixture the level will build by hand: a hero, a director, a stand-in for the painted
# grate, `count` guards on the cage floor with one exit marker each, and the prop watching the
# floor in front of them.
func _build(count: int) -> Dictionary:
	var stage := Node2D.new()
	stage.name = "Stage"
	stage.y_sort_enabled = true
	root.add_child(stage)

	var director: Node = load(DIRECTOR_SCRIPT).new()
	director.name = "EnemyDirector"
	stage.add_child(director)

	var hero: Node2D = load(PLAYER_SCENE).instantiate()
	stage.add_child(hero)
	hero.global_position = HERO_AWAY

	var gate := Node2D.new()   # stands in for the grate sprite cut out of the section art
	gate.name = "PH_Gate"
	stage.add_child(gate)

	var guards: Array = []
	var exits: Array = []
	for i in count:
		var guard: Node2D = load(GUARD_SCENE).instantiate()
		guard.name = "Guard%d" % i
		guard.Facing = -1
		stage.add_child(guard)
		guard.global_position = GUARD_FEET[i]
		guards.append(guard)
		var marker := Marker2D.new()
		marker.name = "Exit%d" % i
		stage.add_child(marker)
		marker.global_position = EXITS[i]
		exits.append(marker)

	var cage: Node2D = load(CAGE_SCENE).instantiate()
	cage.Caged = guards
	cage.Exits = exits
	cage.Gate = gate
	cage.Player = hero
	cage.Director = director
	stage.add_child(cage)
	cage.global_position = CAGE_POS

	return {"stage": stage, "cage": cage, "hero": hero, "gate": gate, "guards": guards, "director": director}

func _run() -> void:
	# 1. The prop on its own: the contract and the author's tuning.
	var packed: PackedScene = load(CAGE_SCENE)
	_check(packed != null, "%s did not load" % CAGE_SCENE)
	if packed == null:
		_finish()
		return
	var proto: Node = packed.instantiate()
	_check(proto is Area2D, "%s root is a %s, expected Area2D" % [CAGE_SCENE, proto.get_class()])
	var script: Script = proto.get_script()
	_check(script != null and script.resource_path == CAGE_SCRIPT,
		"%s runs %s, expected %s" % [CAGE_SCENE, script.resource_path if script else null, CAGE_SCRIPT])
	_check(proto.collision_layer == 0 and proto.collision_mask == PLAYER_LAYER,
		"the cage is layer %d mask %d, expected 0 / %d (it watches the hero and blocks nothing)" % [proto.collision_layer, proto.collision_mask, PLAYER_LAYER])
	_check(proto.monitoring, "the cage is not monitoring; the ambush would never fire")
	_check(not proto.IsOpen, "the cage starts open; the guards must be shut in behind the grate")
	_check(_approx(proto.OpenDelay, EXPECTED_DELAY), "OpenDelay is %s, expected %s" % [proto.OpenDelay, EXPECTED_DELAY])
	_check(_approx(proto.ArriveDistance, EXPECTED_ARRIVE), "ArriveDistance is %s, expected %s" % [proto.ArriveDistance, EXPECTED_ARRIVE])
	_check(_approx(proto.WalkOutTimeout, EXPECTED_TIMEOUT), "WalkOutTimeout is %s, expected %s" % [proto.WalkOutTimeout, EXPECTED_TIMEOUT])
	_check(String(proto.WalkAnimation) == EXPECTED_WALK_ANIM,
		"WalkAnimation is '%s', expected '%s' (the guard's own gait)" % [String(proto.WalkAnimation), EXPECTED_WALK_ANIM])
	_check(proto.Caged.is_empty() and proto.Exits.is_empty(), "the cage ships with guards or exits wired in; the level fills those")
	_check(proto.Gate == null and proto.Player == null and proto.Director == null,
		"the cage ships with a gate, a hero or a director wired in; the level fills those")

	# 2. The trip wire: the last stretch of floor before the painted cage, across the whole band.
	var proto_shape: CollisionShape2D = proto.get_node_or_null("CollisionShape2D")
	_check(proto_shape != null and proto_shape.shape is RectangleShape2D, "the cage has no rectangular trip wire")
	if proto_shape != null and proto_shape.shape is RectangleShape2D:
		var box: RectangleShape2D = proto_shape.shape
		_check(box.size.is_equal_approx(TRIP_SIZE), "the trip wire is %s, expected %s" % [box.size, TRIP_SIZE])
		var left: float = CAGE_POS.x + proto_shape.position.x - box.size.x * 0.5
		var right: float = CAGE_POS.x + proto_shape.position.x + box.size.x * 0.5
		var top: float = CAGE_POS.y + proto_shape.position.y - box.size.y * 0.5
		var bottom: float = CAGE_POS.y + proto_shape.position.y + box.size.y * 0.5
		_check(left >= SECTION_X + MIN_RUN_UP,
			"placed at %s the trap fires at x %.1f, only %.1f px into the section — it must fire near the cage, not at its entrance" % [CAGE_POS, left, left - SECTION_X])
		_check(left < _world_x(OPENING_FROM),
			"the trap fires at x %.1f, past the cage opening (%.1f); the hero would be level with the guards before they move" % [left, _world_x(OPENING_FROM)])
		_check(right > _world_x(OPENING_FROM) and right < SECTION_X + SECTION_WIDTH,
			"the trip wire ends at x %.1f, expected past the cage opening (%.1f) and inside the section (%.1f)" % [right, _world_x(OPENING_FROM), SECTION_X + SECTION_WIDTH])
		_check(_approx(top, BAND_TOP, 0.5) and _approx(bottom, BAND_BOTTOM, 0.5),
			"the trip wire spans y %.1f…%.1f, expected the whole walk band %.0f…%.0f (there must be no way past it)" % [top, bottom, BAND_TOP, BAND_BOTTOM])
	proto.free()

	# 2b. The pair inside and where they come out to, against the same mockup mapping: both stand on
	# the painted cage floor, and both exits are in front of them, inside the cage's own opening and
	# inside the walk band — a marker outside it would send a guard into the back wall.
	for i in GUARD_FEET.size():
		var feet: Vector2 = _world(MOCKUP_FEET[i])
		_check(feet.distance_to(GUARD_FEET[i]) <= 0.5,
			"caged guard %d is stood at %s, but mockup %s maps to %s" % [i, GUARD_FEET[i], MOCKUP_FEET[i], feet])
		_check(EXITS[i].x >= _world_x(OPENING_FROM) and EXITS[i].x <= _world_x(OPENING_TO),
			"exit %d is at x %.1f, outside the painted cage opening %.1f…%.1f" % [i, EXITS[i].x, _world_x(OPENING_FROM), _world_x(OPENING_TO)])
		_check(EXITS[i].y > feet.y and EXITS[i].y >= BAND_TOP and EXITS[i].y <= BAND_BOTTOM,
			"exit %d is at y %.1f, expected in front of the cage floor (%.1f) and inside the walk band %.0f…%.0f" % [i, EXITS[i].y, feet.y, BAND_TOP, BAND_BOTTOM])

	# 3. The ambush itself, with two guards in the cage.
	var fixture: Dictionary = _build(2)
	var cage: Node2D = fixture["cage"]
	var hero: Node2D = fixture["hero"]
	var gate: Node2D = fixture["gate"]
	var guards: Array = fixture["guards"]
	var director: Node = fixture["director"]
	# A GDScript lambda captures locals by value, so the tally has to live in an Array.
	var opened: Array = []
	cage.Opened.connect(func(): opened.append(1))
	await _step(SETTLE + 2)

	# 3a. Shut while the hero is down the drift: nobody wakes, nobody moves, the grate stays.
	await _step(30)
	_check(not cage.IsOpen and opened.is_empty(), "the cage opened with the hero %.0f px away" % (GUARD_FEET[0].x - HERO_AWAY.x))
	_check(gate.visible, "the grate is already gone while the cage is shut")
	for i in guards.size():
		_check(guards[i].Target == null and not guards[i].IsAware,
			"caged guard %d is already hunting the hero" % i)
		_check(guards[i].CurrentStateName == "Idle", "caged guard %d is in %s, expected Idle" % [i, guards[i].CurrentStateName])
		_check(guards[i].global_position.is_equal_approx(GUARD_FEET[i]),
			"caged guard %d drifted from %s to %s while the cage was shut" % [i, GUARD_FEET[i], guards[i].global_position])

	# 3b. The hero comes near: the trap springs and the guards come out to their markers.
	hero.global_position = HERO_TRIP
	var open_frame := -1
	var early: Array = []
	var woke: Dictionary = {}
	for f in TRIP_FRAMES:
		await physics_frame
		if cage.IsOpen and open_frame < 0:
			open_frame = f
		if open_frame >= 0 and f == open_frame + EARLY_SAMPLE:
			for g in guards:
				early.append(g.global_position)
		for i in guards.size():
			if not woke.has(i) and guards[i].Target != null:
				woke[i] = guards[i].global_position
		if woke.size() == guards.size():
			break

	_check(opened.size() == 1, "the trigger fired Opened %d times, expected exactly one" % opened.size())
	_check(cage.IsOpen, "the hero walked into the trip wire and the cage stayed shut")
	_check(not gate.visible, "the cage opened and the painted grate is still drawn over the shaft")
	_check(early.size() == guards.size(),
		"the guards were never sampled inside OpenDelay (the cage did not open in time)")
	for i in early.size():
		_check(early[i].is_equal_approx(GUARD_FEET[i]),
			"guard %d had already left %s for %s %d frames after the trigger — the grate must be seen to open first (OpenDelay %.2f s)" % [i, GUARD_FEET[i], early[i], EARLY_SAMPLE, EXPECTED_DELAY])
	for i in guards.size():
		_check(woke.has(i), "caged guard %d never came out of the cage" % i)
		if not woke.has(i):
			continue
		var at: Vector2 = woke[i]
		_check(at.distance_to(EXITS[i]) <= ARRIVE_EPS,
			"guard %d came out at %s, expected his exit marker %s" % [i, at, EXITS[i]])
		_check(at.y >= BAND_TOP and at.y <= BAND_BOTTOM,
			"guard %d came out at y %.1f, outside the walk band %.0f…%.0f — the hero could never reach him" % [i, at.y, BAND_TOP, BAND_BOTTOM])
		_check(guards[i].Target == hero, "guard %d was released without the hero as target" % i)
		_check(guards[i].Director == director, "guard %d was released without the level's EnemyDirector" % i)
		_check(guards[i].IsAware, "guard %d came out unaware; an ambush must not wait to be seen" % i)
	await _step(2)
	for i in guards.size():
		_check(guards[i].CurrentStateName == "Approach",
			"guard %d is in %s after coming out, expected Approach" % [i, guards[i].CurrentStateName])

	# 3c. Sprung for good: the guards are gone and walking back and forth reopens nothing.
	for guard in guards:
		guard.queue_free()
	await _step(2)
	hero.global_position = HERO_AWAY
	await _step(SETTLE)
	hero.global_position = HERO_TRIP
	await _step(SETTLE + EARLY_SAMPLE)
	_check(opened.size() == 1, "walking back into the trip wire sprung the ambush again (%d times in all)" % opened.size())
	_check(cage.IsOpen and not gate.visible, "the cage closed itself behind the hero")
	fixture["stage"].queue_free()
	await _step(1)

	# 4. A guard freed from the tree is skipped, and his fellow still comes out.
	var second: Dictionary = _build(2)
	var cage2: Node2D = second["cage"]
	var guards2: Array = second["guards"]
	var opened2: Array = []
	cage2.Opened.connect(func(): opened2.append(1))
	guards2[0].queue_free()
	await _step(SETTLE + 2)
	second["hero"].global_position = HERO_TRIP
	var left: Node2D = guards2[1]
	for f in TRIP_FRAMES:
		await physics_frame
		if left.Target != null:
			break
	_check(opened2.size() == 1, "the cage with a freed guard fired Opened %d times, expected one" % opened2.size())
	_check(left.Target != null and left.global_position.distance_to(EXITS[1]) <= ARRIVE_EPS,
		"the surviving guard stopped at %s, expected his exit marker %s" % [left.global_position, EXITS[1]])
	second["stage"].queue_free()
	await _step(1)

	# 5. An empty cage still opens its gate for the hero.
	var empty: Dictionary = _build(0)
	var cage3: Node2D = empty["cage"]
	var gate3: Node2D = empty["gate"]
	var opened3: Array = []
	cage3.Opened.connect(func(): opened3.append(1))
	await _step(SETTLE + 2)
	empty["hero"].global_position = HERO_TRIP
	for f in OPEN_FRAMES:
		await physics_frame
		if cage3.IsOpen:
			break
	_check(opened3.size() == 1 and cage3.IsOpen, "an empty cage did not open (Opened fired %d times)" % opened3.size())
	_check(not gate3.visible, "an empty cage kept its grate drawn")
	empty["stage"].queue_free()
	await _step(1)

	_finish()
