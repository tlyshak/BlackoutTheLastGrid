extends SceneTree
# Smoke: the gas death and the patrol of the third-revision prologue (T-07s-e), on levels
# instantiated directly.
#   * the gas death — with the lamp on inside the pocket the warning starts at once and Dan's
#     shout is exactly `LAMP OFF!`; 1.2 s later it ignites into a soft respawn at the checkpoint a
#     few steps back (lamp off, energy ≥ the floor, the level instance intact); Dan says «Told you»
#     and, the hero's lamp being off now, crosses the pocket dark;
#   * the patrol geometry — every lamp pool is a 420 × 220 zone whose decal is the zone grown by
#     the hero's LightSensor radius (what is drawn lit is what makes him lit), no dark stripe decal
#     overlaps a lit rect (what is drawn dark is dark — B1 of the v3 review), and every guard's
#     dark stripe lies farther in depth than its unlit perception reach;
#   * the stealth route — walked with input along the near stripe, up the dark column, along the
#     far stripe, down and along the near stripe again: the hero is never lit, no guard notices,
#     every guard stays Idle, Dan leads it corner by corner with his lamp off and says nothing until
#     the exit («Never looked. Go.»);
#   * the fight route (a second instance) — lit at x 6100 the first guard notices within 30 frames;
#     all three down leave three powerbanks under Patrol and Dan's «Or that»; the lamp pools go off
#     with the work lights (a hero inside one reads unlit) and come back with them; walked along the
#     near edge into pool 2 with the lamp off, the hero reads lit under a pool decal and unlit under
#     a stripe decal on every frame (the drawn/lit agreement).
# Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/level_prologue_patrol.gd

const NAME := "level_prologue_patrol"   # must equal the file basename
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const PROLOGUE_PATH := "res://scenes/levels/Level00_Prologue.tscn"
const SETTLE_CAP := 20
const SETTLE_DELTA := 0.05
const OVERLAP_FRAMES := 4
const CUTSCENE_CAP := 40
const DELAY_MARGIN := 0.4
const FADE_MARGIN := 0.6
const COLOR_EPS := 0.02
const SPEED := 220.0
const DEPTH_SPEED := 165.0      # Player.MoveSpeed x DepthSpeedFactor
const TICKS := 60.0
const WALK_SLACK := 10
const BUBBLE_CAP := 60
const DAN_CAP := 400
const IGNITE_CAP_MS := 1800
const RESTORE_CAP_MS := 1000
const NOTICE_CAP := 30
const DROP_CAP := 8
# Stage enum values.
const STAGE_GAS := 7
const STAGE_PATROL := 8
const ROOM_PATROL_LIMITS := [5760, 0, 8640, 1080]
# Positions.
const GAS_APPROACH := Vector2(4100, 450)
const GAS_REACH := Vector2(4230, 450)      # on Checkpoint_GasNear, within HeroCloseDistance of WP_gas_edge
const POCKET_A := Vector2(4500, 450)
const CP_PATROL := Vector2(5800, 450)
const POOL_SIZE := Vector2(420, 220)
const NEAR_Y := 585.0
const FAR_Y := 315.0
const ROUTE_START := Vector2(5900, NEAR_Y)
const COLUMN1_X := 6440.0
const FAR_END_X := 7000.0
const NEAR_END_X := 7620.0
const AFTER_PATROL := Vector2(7860, 450)
const FIGHT_SPOT := Vector2(6100, 450)
const POOL2_CENTRE := Vector2(6760, 490)
const AGREE_END_X := 6700.0        # the agreement walk: from the first column into pool 2 along the near edge
const AGREE_CAP := 120
const DECAL_INSET_X := 24.0        # judge only frames well inside a decal's x span (the sensor is 8 px wide)

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

func _settle() -> void:
	for i in SETTLE_CAP:
		await process_frame
		if root.get_process_delta_time() < SETTLE_DELTA:
			return

func _release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)

func _real_wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

func _finish() -> void:
	_release_all()
	paused = false
	if Engine.time_scale != 1.0:
		_check(false, "Engine.time_scale=%s at the end, expected 1 (reset by the test)" % Engine.time_scale)
		Engine.time_scale = 1.0
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.ResetRun()
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

func _place(node: Node, pos: Vector2) -> void:
	node.global_position = pos
	await _step(OVERLAP_FRAMES)

func _wait_until(cond: Callable, cap: int) -> int:
	for i in cap:
		if cond.call():
			return i
		await physics_frame
	return -1

func _watch_ms(flags: Array, cap_ms: int) -> bool:
	var before: int = flags.size()
	var deadline: int = Time.get_ticks_msec() + cap_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if flags.size() > before:
			return true
	return false

func _wait_restored(cap_ms: int) -> void:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < cap_ms and Engine.time_scale != 1.0:
		await process_frame

func _color_eq(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < COLOR_EPS and absf(a.g - b.g) < COLOR_EPS and absf(a.b - b.b) < COLOR_EPS

func _play_out(cutscene: Node, label: String) -> void:
	var guard := 0
	while cutscene.IsPlaying and guard < CUTSCENE_CAP:
		cutscene.Advance()
		guard += 1
		await _step(1)
	_check(not cutscene.IsPlaying, "%s: the cutscene never ended after %d advances" % [label, guard])
	await _step(3)

func _wp(level: Node, key: String) -> Vector2:
	return level.get("DanRoute").get_node("WP_" + key).global_position

func _build_level() -> Node:
	var scene: PackedScene = load(PROLOGUE_PATH)
	_check(scene != null, "%s failed to load" % PROLOGUE_PATH)
	if scene == null:
		return null
	var level: Node = scene.instantiate()
	root.add_child(level)
	current_scene = level
	await _settle()
	return level

func _guards_of(patrol: Node) -> Array:
	var out: Array = []
	for child in patrol.get_children():
		var script: Variant = child.get_script()
		if script != null and str(script.resource_path).ends_with("Guard.cs"):
			out.append(child)
	return out

func _pickups_of(patrol: Node) -> int:
	var n := 0
	for child in patrol.get_children():
		var script: Variant = child.get_script()
		if script != null and str(script.resource_path).ends_with("EnergyPickup.cs"):
			n += 1
	return n

# [name, global rect] of every Polygon2D under PH_Decals whose name starts with `prefix`.
func _decal_rects(level: Node, prefix: String) -> Array:
	var out: Array = []
	var decals: Node = level.get_node_or_null("PH_Decals")
	if decals == null:
		return out
	for d in decals.get_children():
		if d is Polygon2D and d.name.begins_with(prefix):
			out.append([d.name, _poly_rect(d)])
	return out

func _inset_x(r: Rect2) -> Rect2:
	return Rect2(r.position.x + DECAL_INSET_X, r.position.y, r.size.x - 2.0 * DECAL_INSET_X, r.size.y)

func _poly_rect(poly: Polygon2D) -> Rect2:
	var min_v := Vector2(INF, INF)
	var max_v := Vector2(-INF, -INF)
	for p in poly.polygon:
		var g: Vector2 = poly.global_position + p
		min_v = min_v.min(g)
		max_v = max_v.max(g)
	return Rect2(min_v, max_v - min_v)

# Holds `action` until `cond` holds or `cap` frames pass; samples the hero every frame into `lit`
# (true if he was ever lit) and returns the frames spent.
func _hold(player: Node, action: String, cond: Callable, cap: int, lit: Array) -> int:
	Input.action_press(action)
	var spent := -1
	for i in cap:
		await physics_frame
		if player.IsLit:
			lit.append(i)
		if cond.call():
			spent = i
			break
	Input.action_release(action)
	await _step(1)
	return spent

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	var level: Node = await _build_level()
	if level == null:
		_finish()
		return
	var player: Node = level.get("Player")
	var lamp: Node = player.get("Flashlight")
	var cutscene: Node = level.get("Cutscene")
	var camera: Camera2D = level.get("Camera")
	var dan: Node = level.get("Companion")
	var patrol: Node = level.get("Patrol")
	var lights: Node = level.get("Lights")
	var pools: Array = Array(level.PatrolPools)
	var pockets: Array = Array(level.GasPockets)
	if player == null or lamp == null or cutscene == null or camera == null or dan == null or patrol == null or lights == null:
		_check(false, "the prologue lacks Player/Flashlight/Cutscene/Camera/Companion/Patrol/Lights")
		_finish()
		return
	var guards: Array = _guards_of(patrol)
	_check(guards.size() == 3, "Patrol holds %d guards, expected 3" % guards.size())
	_check(pools.size() == 3, "PatrolPools holds %d zones, expected 3" % pools.size())
	if guards.size() != 3 or pools.size() != 3 or pockets.size() != 2:
		_finish()
		return
	var lines: Array = []
	var lamp_at_line: Dictionary = {}
	dan.LineShown.connect(func(t: String):
		lines.append(t)
		lamp_at_line[t] = dan.IsLampOn)
	var warnings: Array = []
	var ignitions: Array = []
	for p in pockets:
		p.WarningStarted.connect(func(): warnings.append(true))
		p.Ignited.connect(func(_pl): ignitions.append(true))
	var noticed: Array = []
	for g in guards:
		g.Noticed.connect(func(): noticed.append(g.name))

	await _play_out(cutscene, "intro")

	# 1. The gas death: the shout, the ignition, the soft respawn, Dan's «Told you», the dark crossing.
	level.get("TimberPile").Clear()   # segment 2 belongs to level_prologue_escape.gd; clearing leads Dan to the gas
	await _place(player, GAS_APPROACH)
	var at_edge: int = await _wait_until(func(): return dan.IsAtLeadTarget and dan.LeadTarget == _wp(level, "gas_edge"), DAN_CAP)
	_check(at_edge >= 0, "Dan never reached the edge of the gas")
	lamp.SetOn(true)
	await _place(player, GAS_REACH)
	_check(level.CurrentStage == STAGE_GAS, "at Checkpoint_GasNear the stage is %s, expected Gas" % level.CurrentStage)
	var armed: Node = level.ArmedCheckpoint
	_check(armed != null and armed.Label == "gas_near", "the checkpoint before the gas is %s" % armed)
	await _step(3)
	_check(dan.LeadTarget == _wp(level, "gas_edge"), "Dan went into the gas ahead of a lit lamp")
	var level_id: int = level.get_instance_id()
	await _place(player, POCKET_A)
	await _step(2)
	_check(warnings.size() == 1, "WarningStarted fired %d times with the lamp on inside the pocket, expected 1" % warnings.size())
	_check(lines.has("LAMP OFF!"), "Dan did not shout exactly 'LAMP OFF!' when the window started (%s)" % [lines])
	var fired: bool = await _watch_ms(ignitions, IGNITE_CAP_MS)
	_check(fired, "the pocket never ignited with the lamp on for %d ms" % IGNITE_CAP_MS)
	await _wait_restored(RESTORE_CAP_MS)
	_check(player.IsKnockedOut == true, "the ignition did not knock the hero out")
	await _real_wait(level.RespawnDelay + DELAY_MARGIN)
	await _step(2)
	_check(is_instance_valid(level) and level.get_instance_id() == level_id, "a death in the gas reloaded the level")
	_check(player.IsKnockedOut == false and player.global_position.distance_to(armed.RespawnPosition) <= 2.0,
		"the hero respawned at %s, expected %s" % [player.global_position, armed.RespawnPosition])
	_check(lamp.IsOn == false, "the hero respawned with the head lamp on next to a gas pocket")
	_check(gs.Energy >= level.MinRespawnEnergy, "the respawn left the energy at %s, below the floor %s" % [gs.Energy, level.MinRespawnEnergy])
	_check(lines.has(level.DanGasAgainLine), "Dan did not say the 'Told you' line after the death (%s)" % [lines])
	_check(dan.IsGone == false and dan.LeadTarget == _wp(level, "past_gas"), "after the death Dan's point is %s, expected WP_past_gas (the revived hero's lamp is off)" % dan.LeadTarget)
	var crossed: int = await _wait_until(func(): return dan.IsAtLeadTarget, DAN_CAP)
	_check(crossed >= 0, "Dan never crossed the pocket after the death")
	await _step(2)
	_check(dan.IsLampOn == true, "Dan's lamp is still off past the gas")
	_check(ignitions.size() == 1, "the pocket ignited %d times, expected 1" % ignitions.size())

	# From here the run is played with an empty battery: nothing left in the level needs the lamp.
	gs.Energy = 0.0
	await _place(player, Vector2(4900, 450))   # the hero reaches Dan past the gas
	await _step(3)
	await _place(player, CP_PATROL)
	_check(level.CurrentStage == STAGE_PATROL, "at Checkpoint_Patrol the stage is %s, expected Patrol" % level.CurrentStage)
	_check(_limits(camera) == ROOM_PATROL_LIMITS, "camera limits %s in the lit drift, expected %s" % [_limits(camera), ROOM_PATROL_LIMITS])
	await _real_wait(level.DarknessFadeSeconds + FADE_MARGIN)
	_check(_color_eq(level.Darkness.color, level.DarknessDrift), "the lit drift is %s, expected DarknessDrift" % level.Darkness.color)
	# The checkpoint on the entrance is within Dan's reach of WP_patrol_in: he arrives there dark,
	# then the hero counts as reached and gets the one line of the segment.
	var ducked: int = await _wait_until(func(): return lines.has(level.DanDuckLine), DAN_CAP)
	_check(ducked >= 0, "Dan did not say the duck line at the entrance (%s)" % [lines])
	_check(lamp_at_line.get(level.DanDuckLine, true) == false, "Dan said the duck line with his lamp still on — the rule must be shown before it is said")
	_check(dan.IsLampOn == false, "Dan's lamp is on in the lit drift")
	_check(dan.LeadTarget == _wp(level, "p1"), "after the duck line Dan's point is %s, expected WP_p1" % dan.LeadTarget)
	var lines_before_stealth: int = lines.size()

	# 2. The geometry: the drawn pool is the pool the physics uses; the stripes are out of reach.
	var sensor: Node = player.get("LightSensor")
	var sensor_shape: CollisionShape2D = sensor.get_node_or_null("CollisionShape2D") if sensor != null else null
	_check(sensor_shape != null and sensor_shape.shape is CircleShape2D, "the hero's LightSensor has no circular shape")
	var radius: float = sensor_shape.shape.radius if sensor_shape != null and sensor_shape.shape is CircleShape2D else 0.0
	for i in pools.size():
		var shape: CollisionShape2D = pools[i].get_node("CollisionShape2D")
		_check(shape.shape is RectangleShape2D and shape.shape.size == POOL_SIZE, "%s's shape is %s, expected %s" % [pools[i].name, shape.shape.size if shape.shape is RectangleShape2D else shape.shape, POOL_SIZE])
		_check(pools[i].collision_layer == 64, "%s is not on the LightDark layer" % pools[i].name)
		var decal: Node = level.get_node_or_null("PH_Decals/PH_PatrolPool_%d" % (i + 1))
		_check(decal is Polygon2D, "PH_Decals/PH_PatrolPool_%d is missing" % (i + 1))
		if decal is Polygon2D and shape.shape is RectangleShape2D:
			var drawn: Rect2 = _poly_rect(decal)
			var lit_rect := Rect2(pools[i].global_position - POOL_SIZE * 0.5 - Vector2(radius, radius), POOL_SIZE + Vector2(2.0 * radius, 2.0 * radius))
			_check(drawn.position.distance_to(lit_rect.position) <= 1.0 and drawn.size.distance_to(lit_rect.size) <= 1.0,
				"%s is drawn %s but the hero is lit over %s (zone %s grown by the %.0f px LightSensor radius) — he would be spotted outside the light he can see"
				% [decal.name, drawn, lit_rect, POOL_SIZE, radius])
	# The dark stripes: a decal drawn black must not overlap any lit rect — what is drawn dark is dark.
	var stripes: Array = _decal_rects(level, "PH_DarkStripe_")
	_check(stripes.size() >= 2, "PH_Decals holds %d PH_DarkStripe_* decals, expected the near and the far lane" % stripes.size())
	for s in stripes:
		for i in pools.size():
			var lit_rect := Rect2(pools[i].global_position - POOL_SIZE * 0.5 - Vector2(radius, radius), POOL_SIZE + Vector2(2.0 * radius, 2.0 * radius))
			_check(not s[1].intersects(lit_rect),
				"%s is drawn dark over %s but %s lights the hero over %s — a lane drawn black is lit there (he would be spotted with no visible cause)"
				% [s[0], s[1], pools[i].name, lit_rect])
	var stripe_of := {"Guard_1": NEAR_Y, "Guard_2": FAR_Y, "Guard_3": NEAR_Y}
	for g in guards:
		var reach: float = g.PerceptionRange * g.DarkPerceptionFactor
		var stripe_y: float = stripe_of.get(g.name, NEAR_Y)
		_check(absf(g.global_position.y - stripe_y) > reach,
			"%s at y %.0f is %.0f px from the stripe at y %.0f, within its unlit reach %.0f — the dark stripe is not honest"
			% [g.name, g.global_position.y, absf(g.global_position.y - stripe_y), stripe_y, reach])
		_check(g.get("DropScene") != null, "%s has no DropScene; the fight route would drop no bank" % g.name)
	for key in ["p1", "c1", "c1b", "p2", "c2", "c2b", "p3", "p3_out"]:
		var pt: Vector2 = _wp(level, key)
		for i in pools.size():
			var lit_rect := Rect2(pools[i].global_position - POOL_SIZE * 0.5 - Vector2(radius, radius), POOL_SIZE + Vector2(2.0 * radius, 2.0 * radius))
			_check(not lit_rect.has_point(pt), "Dan's route point %s (%s) lies inside %s" % [key, pt, pools[i].name])

	# 3. The stealth route, walked: never lit, never noticed, every guard idle, Dan silent and dark.
	_check(lamp.IsOn == false, "the lamp is on going into the stealth route")
	var lit: Array = []
	player.global_position = ROUTE_START
	await _step(2)
	var leg1: int = await _hold(player, "move_right", func(): return player.global_position.x >= COLUMN1_X, 240, lit)
	_check(leg1 >= 0, "the near stripe walk never reached x %.0f (at %s)" % [COLUMN1_X, player.global_position])
	var leg2: int = await _hold(player, "move_up", func(): return player.global_position.y <= FAR_Y + 1.0, 200, lit)
	_check(leg2 >= 0, "the column walk never reached y %.0f (at %s)" % [FAR_Y, player.global_position])
	var leg3: int = await _hold(player, "move_right", func(): return player.global_position.x >= FAR_END_X, 240, lit)
	_check(leg3 >= 0, "the far stripe walk never reached x %.0f (at %s)" % [FAR_END_X, player.global_position])
	var leg4: int = await _hold(player, "move_down", func(): return player.global_position.y >= NEAR_Y - 1.0, 200, lit)
	_check(leg4 >= 0, "the second column walk never reached y %.0f (at %s)" % [NEAR_Y, player.global_position])
	# Before the last leg Dan is still inside the patrol: dark, and silent since the entrance.
	_check(dan.IsLampOn == false, "Dan's lamp came on inside the patrol")
	_check(lines.size() == lines_before_stealth, "Dan spoke during the patrol (%s) — the stealth is deliberate silence" % [lines.slice(lines_before_stealth)])
	_check(dan.LeadTarget == _wp(level, "p3") and dan.IsAtLeadTarget, "before the last stripe Dan's point is %s (at it: %s), expected WP_p3" % [dan.LeadTarget, dan.IsAtLeadTarget])
	var leg5: int = await _hold(player, "move_right", func(): return player.global_position.x >= NEAR_END_X, 240, lit)
	_check(leg5 >= 0, "the last stripe walk never reached x %.0f (at %s)" % [NEAR_END_X, player.global_position])
	_check(lit.is_empty(), "the hero was lit on %d frame(s) of the stealth route (first at frame %s) — the drawn dark is not dark" % [lit.size(), lit[0] if not lit.is_empty() else "-"])
	_check(noticed.is_empty(), "a guard noticed the hero on the stealth route: %s" % [noticed])
	for g in guards:
		_check(g.CurrentStateName == "Idle" and g.IsAware == false, "%s is '%s' / aware %s after the stealth route, expected Idle and unaware" % [g.name, g.CurrentStateName, g.IsAware])
	_check(player.IsKnockedOut == false, "the hero was knocked out on the stealth route")
	# The exit: Dan's lamp back, the one line, and nothing else said since the entrance.
	var exited: int = await _wait_until(func(): return lines.has(level.DanNeverLookedLine), DAN_CAP)
	_check(exited >= 0, "Dan did not say the exit line after an unseen patrol (%s)" % [lines])
	_check(lines.slice(lines_before_stealth) == [level.DanNeverLookedLine], "Dan said %s inside the patrol, expected only the exit line" % [lines.slice(lines_before_stealth)])
	_check(lamp_at_line.get(level.DanNeverLookedLine, false) == true, "Dan said the exit line with his lamp still off")
	_check(dan.IsLampOn == true, "Dan's lamp did not come back at the patrol exit")
	_check(dan.LeadTarget == _wp(level, "cage"), "past the patrol Dan's point is %s, expected WP_cage" % dan.LeadTarget)
	_check(noticed.is_empty(), "a guard noticed the hero at the patrol exit: %s" % [noticed])
	level.queue_free()
	await _step(2)

	# 4. The fight route: lit, noticed at once, three down, three banks; the pools go with the lights.
	gs.ResetRun()
	var level2: Node = await _build_level()
	if level2 == null:
		_finish()
		return
	var player2: Node = level2.get("Player")
	var lamp2: Node = player2.get("Flashlight")
	var dan2: Node = level2.get("Companion")
	var patrol2: Node = level2.get("Patrol")
	var lights2: Node = level2.get("Lights")
	var pools2: Array = Array(level2.PatrolPools)
	var guards2: Array = _guards_of(patrol2)
	var lines2: Array = []
	dan2.LineShown.connect(func(t: String): lines2.append(t))
	var noticed2: Array = []
	for g in guards2:
		g.Noticed.connect(func(): noticed2.append(g.name))
	await _play_out(level2.get("Cutscene"), "intro 2")
	await _place(player2, CP_PATROL)
	lamp2.SetOn(true)
	await _place(player2, FIGHT_SPOT)
	var seen: int = await _wait_until(func(): return noticed2.has("Guard_1"), NOTICE_CAP)
	_check(seen >= 0, "Guard_1 did not notice a lit hero at x %.0f within %d frames" % [FIGHT_SPOT.x, NOTICE_CAP])
	for g in guards2:
		g.TakeDamage(999.0, 0.0, true, 0)
	await _step(DROP_CAP)
	for g in guards2:
		_check(g.IsKnockedOut == true, "%s is not knocked out" % g.name)
	_check(_pickups_of(patrol2) == 3, "the fallen patrol left %d banks under Patrol, expected 3" % _pickups_of(patrol2))
	await _wait_until(func(): return lines2.has(level2.DanFoughtLine), BUBBLE_CAP)
	_check(lines2.has(level2.DanFoughtLine), "Dan did not say the fought line with the patrol down (%s)" % [lines2])
	# The drawn/lit agreement, walked: along the near edge from the first column into pool 2 with
	# the lamp off (the patrol is down, nobody reacts) — on every frame well inside a pool decal the
	# hero must read lit, and well inside a dark stripe decal he must read unlit.
	lamp2.SetOn(false)
	var pool_rects2: Array = _decal_rects(level2, "PH_PatrolPool_")
	var dark_rects2: Array = _decal_rects(level2, "PH_DarkStripe_")
	player2.global_position = Vector2(COLUMN1_X, NEAR_Y)
	await _step(2)
	var disagreements: Array = []
	Input.action_press("move_right")
	for i in AGREE_CAP:
		await physics_frame
		var feet: Vector2 = player2.global_position
		for r in pool_rects2:
			if _inset_x(r[1]).has_point(feet) and not player2.IsLit:
				disagreements.append("%s is drawn lit at %s but the hero is unlit" % [r[0], feet])
		for r in dark_rects2:
			if _inset_x(r[1]).has_point(feet) and player2.IsLit:
				disagreements.append("%s is drawn dark at %s but the hero is lit" % [r[0], feet])
		if feet.x >= AGREE_END_X:
			break
	Input.action_release("move_right")
	await _step(1)
	_check(player2.global_position.x >= AGREE_END_X, "the agreement walk never reached x %.0f (at %s)" % [AGREE_END_X, player2.global_position])
	_check(disagreements.is_empty(), "the drawn light and the lit zones disagree on %d frame(s) of the near edge — first: %s" % [disagreements.size(), disagreements[0] if not disagreements.is_empty() else "-"])
	await _place(player2, POOL2_CENTRE)
	_check(player2.IsLit == true, "a hero standing in a lamp pool with the work lights on is not lit")
	lights2.PowerDown()
	await _step(3)
	for pool in pools2:
		_check(pool.get_node("CollisionShape2D").disabled == true, "%s is still live with the work lights off" % pool.name)
	await _place(player2, POOL2_CENTRE + Vector2(1, 0))
	_check(player2.IsLit == false, "a hero inside a switched-off pool still reads lit")
	lights2.ForcePower()
	await _step(3)
	for pool in pools2:
		_check(pool.get_node("CollisionShape2D").disabled == false, "%s did not come back with the work lights" % pool.name)
	level2.queue_free()
	await _step(2)
	_finish()

func _limits(camera: Camera2D) -> Array:
	return [camera.limit_left, camera.limit_top, camera.limit_right, camera.limit_bottom]
