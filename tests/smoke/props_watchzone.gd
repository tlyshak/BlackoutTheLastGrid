extends SceneTree
# Smoke: WatchZone — the sealing crew's field of view (T-07s-b). The prefab's scene contract and
# defaults; in the prologue the zone spans the room's whole walk band, so there is no lane to walk
# past the crew in depth; with the lamp off the hero crosses it at both band edges and nobody
# reacts; the head lamp opens a warning window that the alert light shows and that killing the lamp
# cancels; standing in one of the crew's own LitZone lamp pools is lit too, and is spotted just the
# same; letting the window run out emits Caught exactly once and knocks the hero out (the level's
# ordinary checkpoint pipeline, not a bespoke punishment); and a retired zone stops watching for good.
# Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/props_watchzone.gd
#
# Player.IsLit has no signal, so the zone polls it; every check here is counted in physics frames
# except the warning window itself, which is a real-time countdown watched under a wall-clock cap.

const NAME := "props_watchzone"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout.
const MAX_FRAMES := 8000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const PROLOGUE_PATH := "res://scenes/levels/Level00_Prologue.tscn"
const WATCH_PATH := "res://scenes/props/WatchZone.tscn"
const SETTLE_CAP := 20         # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05     # process delta (s) below which the loop is back to normal pacing
const PLAYER_LAYER := 2        # physics layer 2 "Player"
const LIGHT_DARK_LAYER := 64   # physics layer 7 "LightDark" — LitZone.LightDarkLayer
const OVERLAP_FRAMES := 4      # physics frames for Area2D overlaps to refresh after a teleport
const CUTSCENE_CAP := 40       # Advance() calls allowed to play one cutscene out
const WATCH_POS := Vector2(7050, 450)      # centre of WatchZone_Crew (700x320 around it)
const POOL_POS := Vector2(6850, 520)       # inside LitZone_Crew1 (220x170 around it)
const DARK_ABOVE_POOL := Vector2(6850, 350)  # inside the zone, out of the pool: the far dark lane
const OUTSIDE_POS := Vector2(6450, 450)    # left of the zone, clear of every lamp pool
const BAND_MARGIN := 20.0      # px inside the band's far and near edge the depth probes stand at
const DARK_FRAMES := 60        # frames in the zone with the lamp off that must stay uneventful
const SPOT_FRAMES := 4         # physics frames the poll needs to see the lamp
const WINDOW := 0.6            # WatchZone.WarningSeconds in the prologue
const CATCH_CAP_MS := 1400     # wall-clock cap while waiting for the window to run out
const SAFE_DELAY := 60.0       # RespawnDelay pushed out of the way so a KO stays observable

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

func _finish() -> void:
	_release_all()
	paused = false
	if Engine.time_scale != 1.0:
		_check(false, "Engine.time_scale=%s at the end, expected 1" % Engine.time_scale)
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

# Plays the cutscene on screen out by hand (the test drives no input).
func _play_out(cutscene: Node) -> void:
	var guard := 0
	while cutscene.IsPlaying and guard < CUTSCENE_CAP:
		cutscene.Advance()
		guard += 1
		await _step(1)
	await _step(3)

func _watch_ms(pred: Callable, cap_ms: int) -> int:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < cap_ms:
		if pred.call():
			return Time.get_ticks_msec() - start
		await process_frame
	return -1

func _run() -> void:
	# 0. Preconditions.
	_check(InputMap.has_action("flashlight"), "InputMap missing action 'flashlight'")
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	# 1. WatchZone.tscn: the scene contract and the export defaults.
	var scene: PackedScene = load(WATCH_PATH)
	_check(scene != null, "%s failed to load" % WATCH_PATH)
	if scene == null:
		_finish()
		return
	var proto: Node = scene.instantiate()
	_check(proto is Area2D, "WatchZone.tscn root is a %s, expected Area2D" % proto.get_class())
	_check(proto.get_script() != null and str(proto.get_script().resource_path).ends_with("WatchZone.cs"),
		"WatchZone.tscn has no WatchZone.cs attached (did dotnet build run?)")
	if proto.get("WarningSeconds") == null:
		_check(false, "WatchZone exports missing — C# scripts not attached, aborting")
		proto.free()
		_finish()
		return
	_check(is_equal_approx(proto.WarningSeconds, 0.6), "WatchZone.WarningSeconds default is %s, expected 0.6" % proto.WarningSeconds)
	_check(proto.Disabled == false, "WatchZone.Disabled default is %s, expected false" % proto.Disabled)
	_check(proto.get("Room") == null, "WatchZone.Room default is %s, expected null (the level wires it)" % proto.get("Room"))
	_check(proto.IsWarning == false, "WatchZone.IsWarning is %s before _Ready, expected false" % proto.IsWarning)
	_check(proto.collision_layer == 0, "WatchZone.tscn collision_layer=%d, expected 0 (it watches, it is not seen)" % proto.collision_layer)
	_check(proto.collision_mask == PLAYER_LAYER, "WatchZone.tscn collision_mask=%d, expected %d (Player)" % [proto.collision_mask, PLAYER_LAYER])
	_check(proto.monitorable == false, "WatchZone.tscn monitorable=%s, expected false" % proto.monitorable)
	_check(proto.monitoring == true, "WatchZone.tscn monitoring=%s, expected true" % proto.monitoring)
	var pshape: Node = proto.get_node_or_null("CollisionShape2D")
	_check(pshape is CollisionShape2D and pshape.shape is RectangleShape2D, "WatchZone.tscn has no rectangular CollisionShape2D")
	if pshape != null and pshape.shape is RectangleShape2D:
		_check(pshape.shape.size == Vector2(700, 320),
			"WatchZone.tscn shape is %s, expected 700x320 (a stretch of drift across the whole band)" % pshape.shape.size)
	var palert: Node = proto.get_node_or_null("PH_Alert")
	_check(palert is PointLight2D, "WatchZone.tscn has no PH_Alert PointLight2D")
	if palert is PointLight2D:
		_check(proto.get("AlertLight") == palert, "WatchZone.AlertLight export does not point at PH_Alert")
		_check(palert.enabled == false, "WatchZone/PH_Alert is lit before anything was spotted")
		_check(palert.shadow_enabled == false, "WatchZone/PH_Alert casts shadows; shadowed lights are out of budget")
	proto.free()
	if _failures.size() > 0:
		_finish()
		return

	# 2. The zone as it is placed in the prologue.
	var level_scene: PackedScene = load(PROLOGUE_PATH)
	_check(level_scene != null, "%s failed to load" % PROLOGUE_PATH)
	if level_scene == null:
		_finish()
		return
	var level: Node = level_scene.instantiate()
	root.add_child(level)
	await _settle()

	var zone: Node = level.get_node_or_null("WatchZone_Crew")
	var pool1: Node = level.get_node_or_null("LitZone_Crew1")
	var pool2: Node = level.get_node_or_null("LitZone_Crew2")
	var player: Node = level.get("Player")
	var lamp: Node = player.get("Flashlight") if player != null else null
	var cutscene: Node = level.get("Cutscene")
	for pair in [[zone, "WatchZone_Crew"], [pool1, "LitZone_Crew1"], [pool2, "LitZone_Crew2"], [player, "Player"], [lamp, "Player.Flashlight"], [cutscene, "Cutscene"]]:
		_check(pair[0] != null, "the prologue has no %s" % pair[1])
	if zone == null or pool1 == null or pool2 == null or player == null or lamp == null or cutscene == null:
		level.queue_free()
		_finish()
		return

	_check(level.get("Crew") == zone, "Level00_Prologue.Crew export does not point at WatchZone_Crew")
	_check(is_equal_approx(zone.WarningSeconds, WINDOW), "WatchZone_Crew.WarningSeconds=%s, expected %s" % [zone.WarningSeconds, WINDOW])
	_check(zone.get("Room") == level.get_node_or_null("Rooms/Room_Gas"), "WatchZone_Crew.Room does not point at Room_Gas")
	for pair in [[pool1, "LitZone_Crew1"], [pool2, "LitZone_Crew2"]]:
		var pool: Node = pair[0]
		_check(pool.collision_layer == LIGHT_DARK_LAYER, "%s collision_layer=%d, expected %d (LightDark)" % [pair[1], pool.collision_layer, LIGHT_DARK_LAYER])
		_check(pool.monitoring == false, "%s monitoring=%s, expected false (the hero's sensor looks, not the pool)" % [pair[1], pool.monitoring])

	# The zone is a gate at every depth: the watched stretch spans the room's whole walk band.
	var box: CollisionShape2D = zone.get_node_or_null("CollisionShape2D")
	_check(box != null and box.shape is RectangleShape2D, "WatchZone_Crew has no rectangular shape")
	if box != null and box.shape is RectangleShape2D:
		var top: float = box.global_position.y - box.shape.size.y * 0.5
		var bottom: float = box.global_position.y + box.shape.size.y * 0.5
		_check(top <= player.FloorTop and bottom >= player.FloorBottom,
			"the crew watches Y %.0f..%.0f, expected the whole walk band %.0f..%.0f — the hero could slip past them in depth"
			% [top, bottom, player.FloorTop, player.FloorBottom])

	# The lamp pools must be exactly the rectangles the floor decals draw, or being lit reads as random.
	var decals: Node = level.get_node_or_null("PH_Decals")
	_check(decals != null, "the level has no PH_Decals group for the crew's lamp pools")
	if decals != null:
		for i in [1, 2]:
			var decal: Node = decals.get_node_or_null("PH_CrewPool_%d" % i)
			var pool2d: Node = level.get_node_or_null("LitZone_Crew%d" % i)
			_check(decal is Polygon2D, "PH_Decals/PH_CrewPool_%d is missing; the pool the player sees must be the pool the physics uses" % i)
			if decal is Polygon2D and pool2d != null:
				_check(decal.global_position == pool2d.global_position,
					"PH_CrewPool_%d sits at %s but LitZone_Crew%d is at %s" % [i, decal.global_position, i, pool2d.global_position])
				var shape: Node = pool2d.get_node_or_null("CollisionShape2D")
				if shape != null and shape.shape is RectangleShape2D:
					var poly: PackedVector2Array = (decal as Polygon2D).polygon
					var w := 0.0
					var h := 0.0
					for p in poly:
						w = maxf(w, absf(p.x) * 2.0)
						h = maxf(h, absf(p.y) * 2.0)
					_check(is_equal_approx(w, shape.shape.size.x) and is_equal_approx(h, shape.shape.size.y),
						"PH_CrewPool_%d is %sx%s but the LitZone is %s" % [i, w, h, shape.shape.size])

	# Let the hero out of the intro cutscene: he is frozen (and out of the physics space) until then.
	await _play_out(cutscene)
	level.RespawnDelay = SAFE_DELAY
	_check(player.process_mode != Node.PROCESS_MODE_DISABLED, "the hero is still frozen after the intro cutscene")

	var spotted: Array = []
	var lost: Array = []
	var caught: Array = []
	zone.Spotted.connect(func(): spotted.append(true))
	zone.LostSight.connect(func(): lost.append(true))
	zone.Caught.connect(func(p): caught.append(p))

	# 3. Lamp off, at both edges of the band: the crew never reacts (acceptance 18).
	for depth in [player.FloorTop + BAND_MARGIN, player.FloorBottom - BAND_MARGIN]:
		var probe := Vector2(WATCH_POS.x, depth)
		await _place(player, probe)
		_check(zone.get_overlapping_bodies().has(player),
			"the hero at %s is not inside WatchZone_Crew — the zone leaves a lane at that depth" % probe)
		_check(player.IsLit == false, "the hero is lit at %s with the lamp off (a lamp pool reaches the dark lane?)" % probe)
		await _step(DARK_FRAMES)
		_check(spotted.is_empty(), "the crew spotted the hero in the dark at Y %.0f" % depth)
		_check(zone.IsWarning == false, "a warning is running at Y %.0f with the lamp off" % depth)
	await _place(player, OUTSIDE_POS)

	# 4. Lamp on inside the zone: seen at once, and killing the lamp in time saves him (acceptance 20).
	await _place(player, WATCH_POS)
	lamp.SetOn(true)
	await _step(SPOT_FRAMES)
	_check(spotted.size() == 1, "Spotted fired %d times when the lamp came on inside the zone, expected 1" % spotted.size())
	_check(zone.IsWarning == true, "IsWarning=%s with the lamp on inside the zone" % zone.IsWarning)
	_check(zone.AlertLight != null and zone.AlertLight.enabled == true, "the alert light stayed dark while the crew was looking")
	_check(zone.WarningRemaining > 0.0 and zone.WarningRemaining <= WINDOW,
		"WarningRemaining=%s, expected a value inside (0, %s]" % [zone.WarningRemaining, WINDOW])
	lamp.SetOn(false)
	await _step(SPOT_FRAMES)
	_check(lost.size() == 1, "LostSight fired %d times after the lamp went out in time, expected 1" % lost.size())
	_check(zone.IsWarning == false, "the window kept running after the lamp went out")
	_check(zone.AlertLight.enabled == false, "the alert light stayed on after the crew lost him")
	_check(caught.is_empty(), "the hero was caught although he went dark in time")
	_check(player.IsKnockedOut == false, "the hero was knocked out although he went dark in time")

	# 5. A lamp pool lights him just as well as his own lamp (acceptance 19).
	await _place(player, POOL_POS)
	await _step(SPOT_FRAMES)
	_check(player.IsLit == true, "standing in LitZone_Crew1 at %s the hero is not lit" % POOL_POS)
	_check(spotted.size() == 2, "Spotted fired %d times when the hero stepped into a lamp pool, expected 2 in total" % spotted.size())
	await _place(player, DARK_ABOVE_POOL)
	await _step(SPOT_FRAMES)
	_check(player.IsLit == false, "the hero is still lit in the dark lane at %s" % DARK_ABOVE_POOL)
	_check(lost.size() == 2, "LostSight fired %d times after he left the pool, expected 2 in total" % lost.size())
	_check(player.IsKnockedOut == false, "the hero was knocked out while weaving through the dark lanes")

	# 6. Letting the window run out: Caught exactly once, and the ordinary KO follows.
	lamp.SetOn(true)
	await _step(SPOT_FRAMES)
	_check(spotted.size() == 3, "Spotted fired %d times, expected 3 in total" % spotted.size())
	var elapsed: int = await _watch_ms(func(): return caught.size() > 0, CATCH_CAP_MS)
	_check(elapsed >= 0, "the window never ran out: Caught was not emitted within %d ms" % CATCH_CAP_MS)
	_check(caught.size() == 1, "Caught fired %d times, expected exactly 1" % caught.size())
	if caught.size() > 0:
		_check(caught[0] == player, "Caught named %s, expected the hero" % caught[0])
	_check(player.IsKnockedOut == true, "the hero is not knocked out after the crew took him")
	_check(zone.IsWarning == false, "the window is still running after the catch")
	_check(zone.AlertLight.enabled == false, "the alert light is still on after the catch")
	_check(level.IsRestartPending == true, "the KO did not enter the level's respawn pipeline")
	lamp.SetOn(false)

	# 7. A retired zone is inert for good (the crew is sealed away by the upper collapse).
	zone.Disabled = true
	await _step(OVERLAP_FRAMES)
	_check(zone.monitoring == false, "a disabled WatchZone is still monitoring")
	player.Revive()
	await _place(player, WATCH_POS)
	lamp.SetOn(true)
	await _step(SPOT_FRAMES + DARK_FRAMES)
	_check(spotted.size() == 3, "a retired zone spotted the hero again (Spotted %d times)" % spotted.size())
	_check(caught.size() == 1, "a retired zone caught the hero again (Caught %d times)" % caught.size())
	lamp.SetOn(false)

	level.queue_free()
	await _step(2)
	_finish()
