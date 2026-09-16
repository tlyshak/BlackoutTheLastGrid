extends SceneTree
# Smoke: the torn feed cable of the ventilation room (T-V3-03) — the discharge the room paints at
# the head of the conveyor shocks whoever stands in it. Checks the prop's contract (Area2D on layer
# 0 / mask 2, rectangular area, the author's export defaults), its placement in the level against
# the mockup coordinates of the painted arc, and the behaviour the author asked for: standing in
# the arc costs energy and throws the hero away from the cable, the shock waits ShockInterval before
# it can bite again, crossing the stopped belt along its far half costs energy while the near half
# is clear, and a dead cable shocks nobody. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/props_live_cable.gd

const NAME := "props_live_cable"   # must equal the file basename
const MAX_FRAMES := 6000
const LEVEL := "res://scenes/levels/Level00_Sections.tscn"
const CABLE_SCENE := "res://scenes/props/LiveCable.tscn"
const CABLE_SCRIPT := "res://scripts/props/LiveCable.cs"

# Backdrop_Drift's placement, the same mapping props_conveyor.gd uses.
const ROOM_X := 1280.0
const WORLD_SCALE := 1280.0 / 680.0
const OFFSET_Y := 300.0 - 280.0 * WORLD_SCALE
# The painted discharge, in mockup px (tools/derive_section2_r2.py CROPS["sparks"]).
const ARC_FROM := 190.0            # left edge of the sparks crop
const ARC_TO := 250.0              # …and right edge
# The walk band and the belt's own strip of it (scripts/props/ConveyorLine.cs and the room's art).
const BAND_TOP := 300.0
const BAND_BOTTOM := 600.0
const LANE_TOP := 350.82           # the drawn belt's top edge: where the one way past the belt starts
const LANE_BOTTOM := 443.06        # …and its bottom edge
const HAZARD_BOTTOM := 386.0       # how deep the arc spreads across the belt's strip

const PLAYER_LAYER := 2            # project.godot 2d_physics/layer_2="Player"
const EXPECTED_DAMAGE := 14.0
const EXPECTED_KNOCKBACK := 240.0
const EXPECTED_INTERVAL := 0.9
const EXPECTED_HITSTOP := 4
const EPS := 0.05
const SETTLE := 4                  # physics frames to let a teleport settle
const CROSS_FRAMES := 260          # frames to walk the belt end to end
const SAFE_Y := 420.0              # the near half of the lane: clear of the arc
const SHOCKED_Y := 370.0           # the far half: under the arc

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

func _approx(a: float, b: float, eps: float = EPS) -> bool:
	return absf(a - b) <= eps

func _world_x(mockup_x: float) -> float:
	return ROOM_X + mockup_x * WORLD_SCALE

func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

# Walks the hero from in front of the belt to past it at one depth; returns [energy spent, crossed].
func _cross(state: Node, player: Node2D, face: float, far_edge: float, y: float) -> Array:
	state.Energy = state.MaxEnergy
	player.Revive()
	player.global_position = Vector2(face - 50.0, y)
	await _step(SETTLE)
	Input.action_press("move_right")
	for i in CROSS_FRAMES:
		await physics_frame
		if player.global_position.x > far_edge:
			break
	Input.action_release("move_right")
	await _step(SETTLE)
	return [state.MaxEnergy - state.Energy, player.global_position.x > far_edge]

func _run() -> void:
	# 1. The prop on its own: the contract and the author's tuning.
	var packed_cable: PackedScene = load(CABLE_SCENE)
	_check(packed_cable != null, "%s did not load" % CABLE_SCENE)
	if packed_cable != null:
		var proto: Node = packed_cable.instantiate()
		_check(proto is Area2D, "%s root is a %s, expected Area2D" % [CABLE_SCENE, proto.get_class()])
		var script: Script = proto.get_script()
		_check(script != null and script.resource_path == CABLE_SCRIPT,
			"%s runs %s, expected %s" % [CABLE_SCENE, script.resource_path if script else null, CABLE_SCRIPT])
		_check(proto.collision_layer == 0 and proto.collision_mask == PLAYER_LAYER,
			"the cable is layer %d mask %d, expected 0 / %d (it watches the hero and blocks nothing)" % [proto.collision_layer, proto.collision_mask, PLAYER_LAYER])
		_check(proto.monitoring, "the cable is not monitoring; it would never notice the hero")
		_check(_approx(proto.Damage, EXPECTED_DAMAGE) and _approx(proto.Knockback, EXPECTED_KNOCKBACK),
			"the cable does %s damage with %s knockback, expected %s / %s" % [proto.Damage, proto.Knockback, EXPECTED_DAMAGE, EXPECTED_KNOCKBACK])
		_check(_approx(proto.ShockInterval, EXPECTED_INTERVAL) and proto.HitStopFrames == EXPECTED_HITSTOP,
			"the cable waits %s s with %d hit-stop frames, expected %s / %d" % [proto.ShockInterval, proto.HitStopFrames, EXPECTED_INTERVAL, EXPECTED_HITSTOP])
		_check(proto.Live, "the cable starts dead; nothing in the level switches it on")
		var proto_shape: CollisionShape2D = proto.get_node_or_null("CollisionShape2D")
		_check(proto_shape != null and proto_shape.shape is RectangleShape2D, "the cable has no rectangular area")
		proto.free()

	# 2. In the level: placed on the painted arc, reaching into the belt's strip of the band.
	var packed: PackedScene = load(LEVEL)
	_check(packed != null, "%s did not load" % LEVEL)
	if packed == null:
		_finish()
		return
	var level: Node = packed.instantiate()
	root.add_child(level)
	current_scene = level
	await _step(SETTLE + 2)

	var cable: Node2D = level.get_node_or_null("LiveCable")
	var line: Node2D = level.get_node_or_null("ConveyorLine")
	var player: Node2D = level.get_node_or_null("Player")
	_check(cable != null and line != null and player != null, "LiveCable, ConveyorLine or Player is missing from the level")
	if cable == null or line == null or player == null:
		level.queue_free()
		_finish()
		return

	# The guard stands a perception range past the belt and would join in; this test is about the cable.
	var guard: Node = level.get_node_or_null("Guard")
	if guard != null:
		guard.queue_free()
		await _step(1)

	var shape: CollisionShape2D = cable.get_node_or_null("CollisionShape2D")
	_check(shape != null and shape.shape is RectangleShape2D, "the level's cable has no rectangular area")
	if shape != null and shape.shape is RectangleShape2D:
		var box: RectangleShape2D = shape.shape
		var left: float = shape.global_position.x - box.size.x * 0.5
		var right: float = shape.global_position.x + box.size.x * 0.5
		var top: float = shape.global_position.y - box.size.y * 0.5
		var bottom: float = shape.global_position.y + box.size.y * 0.5
		_check(_approx(left, _world_x(ARC_FROM), 0.5) and _approx(right, _world_x(ARC_TO), 0.5),
			"the arc spans x %.2f…%.2f, expected the painted discharge %.2f…%.2f" % [left, right, _world_x(ARC_FROM), _world_x(ARC_TO)])
		_check(_approx(top, BAND_TOP, 0.5),
			"the arc starts at y %.2f, expected the top of the walk band %.0f" % [top, BAND_TOP])
		_check(_approx(bottom, HAZARD_BOTTOM, 0.5),
			"the arc reaches y %.2f, expected %.0f" % [bottom, HAZARD_BOTTOM])
		# It has to bite inside the one lane past the belt, and leave a way through on the near side.
		_check(bottom > LANE_TOP,
			"the arc stops at y %.2f, above the belt's strip (%.2f); the hero could never touch it, because the band above the belt is walled off" % [bottom, LANE_TOP])
		_check(bottom < LANE_BOTTOM - 40.0,
			"the arc reaches y %.2f of the belt's strip %.2f…%.2f, leaving no way past it" % [bottom, LANE_TOP, LANE_BOTTOM])

	# 3. One shock: it costs energy, throws the hero away from the cable, and then waits.
	var state: Node = root.get_node_or_null("GameState")
	_check(state != null, "GameState autoload is missing")
	if state != null and shape != null:
		var shocks: Array = []
		cable.Shocked.connect(func(d): shocks.append(d))
		state.Energy = state.MaxEnergy
		player.Revive()
		player.global_position = Vector2(cable.global_position.x - 10.0, SHOCKED_Y)
		await _step(SETTLE)
		_check(shocks.size() == 1, "standing in the arc fired %d shocks, expected one" % shocks.size())
		_check(_approx(state.MaxEnergy - state.Energy, EXPECTED_DAMAGE, 0.01),
			"one shock cost %.2f energy, expected %.2f" % [state.MaxEnergy - state.Energy, EXPECTED_DAMAGE])
		_check(player.velocity.x < 0.0,
			"the hero stood left of the cable and was thrown at %.1f px/s, expected away from it (negative)" % player.velocity.x)
		# The throw carries him clear of the discharge, so one step in costs one shock, not a stream.
		await _step(30)
		_check(player.global_position.x < _world_x(ARC_FROM),
			"after the shock the hero sits at x %.1f, still inside the arc (%.1f…%.1f) — it would bite him again and again" % [player.global_position.x, _world_x(ARC_FROM), _world_x(ARC_TO)])
		_check(shocks.size() == 1, "the cable fired %d more times while the hero was being thrown clear" % [shocks.size() - 1])

		# It does bite again once the wait has run out and he steps back in.
		await _step(int(EXPECTED_INTERVAL * 60.0) + 8)
		_check(cable.IsArmed, "the cable is still waiting %.2f s after the shock" % EXPECTED_INTERVAL)
		player.Revive()
		player.global_position = Vector2(cable.global_position.x - 10.0, SHOCKED_Y)
		await _step(SETTLE)
		_check(shocks.size() >= 2, "the cable never bit again when the hero stepped back into it")

	# 4. The way through: the belt's far half costs energy, the near half does not.
	var foot: CollisionShape2D = line.BlockerShape
	if foot != null and foot.shape is RectangleShape2D and state != null:
		var fbox: RectangleShape2D = foot.shape
		var face: float = foot.global_position.x - fbox.size.x * 0.5
		var far_edge: float = foot.global_position.x + fbox.size.x * 0.5
		level.get_node("ConveyorSwitch").Begin(player)
		await _step(SETTLE + 4)
		_check(not line.Running, "the lever did not stop the belt")

		var burnt: Array = await _cross(state, player, face, far_edge, SHOCKED_Y)
		_check(bool(burnt[1]), "the hero could not cross the stopped belt at all at depth %.0f" % SHOCKED_Y)
		_check(float(burnt[0]) >= EXPECTED_DAMAGE,
			"walking the belt under the arc cost %.1f energy, expected at least one shock (%.0f)" % [burnt[0], EXPECTED_DAMAGE])

		var clear: Array = await _cross(state, player, face, far_edge, SAFE_Y)
		_check(bool(clear[1]), "the hero could not cross the stopped belt along its near half")
		_check(is_zero_approx(float(clear[0])),
			"crossing along the near half cost %.1f energy; the arc must leave a way through" % clear[0])

	# 5. A dead cable bites nobody and stops drawing its arc.
	if state != null:
		cable.Live = false
		await _step(2)
		var arc: CanvasItem = cable.Arc
		_check(arc != null and not arc.visible, "a dead cable still draws its discharge")
		state.Energy = state.MaxEnergy
		player.Revive()
		player.global_position = Vector2(cable.global_position.x, SHOCKED_Y)
		await _step(20)
		_check(_approx(state.Energy, state.MaxEnergy, 0.01),
			"a dead cable still cost %.1f energy" % (state.MaxEnergy - state.Energy))

	level.queue_free()
	await _step(1)
	_finish()
