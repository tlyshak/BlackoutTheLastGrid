extends SceneTree
# Smoke: WatchZone — a crew's field of view (T-07s-b). The prefab's scene contract and defaults;
# then the zone dropped into a level by the test (the third-revision prologue no longer places one
# — T-B23 — so it is added over the lit drift's first lamp pool): it spans the room's whole walk
# band, so there is no lane to walk past the watchers in depth; with the lamp off the hero crosses
# it at both band edges and nobody reacts; the head lamp opens a warning window that the alert
# light shows and that killing the lamp cancels; standing in a LitZone lamp pool is lit too, and is
# spotted just the same; letting the window run out emits Caught exactly once and knocks the hero
# out (the level's ordinary checkpoint pipeline, not a bespoke punishment); and a retired zone stops
# watching for good. The pool-decal honesty rule is asserted in tests/smoke/level_prologue_patrol.gd.
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
const ZONE_POS := Vector2(6200, 450)       # where the test drops the zone: over lamp pool P1 (700x320 around it)
const WATCH_POS := Vector2(6480, 450)      # inside the zone, in the dark column between pools P1 and P2
const POOL_POS := Vector2(6200, 410)       # inside LitZone_P1 (420x220 around it)
const DARK_BESIDE_POOL := Vector2(6200, 585)  # inside the zone, out of the pool: the near dark stripe
const OUTSIDE_POS := Vector2(5700, 450)    # left of the zone, clear of every lamp pool
const BAND_MARGIN := 20.0      # px inside the band's far and near edge the depth probes stand at
const DARK_FRAMES := 60        # frames in the zone with the lamp off that must stay uneventful
const SPOT_FRAMES := 4         # physics frames the poll needs to see the lamp
const WINDOW := 0.6            # WatchZone.WarningSeconds (the prefab default)
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

	# 2. The zone dropped into a level: the prologue's lit drift, over lamp pool P1, with the patrol
	#    switched off (guards would notice a lit hero, which is not what is measured here).
	var level_scene: PackedScene = load(PROLOGUE_PATH)
	_check(level_scene != null, "%s failed to load" % PROLOGUE_PATH)
	if level_scene == null:
		_finish()
		return
	var level: Node = level_scene.instantiate()
	root.add_child(level)
	await _settle()

	var pool1: Node = level.get_node_or_null("LitZone_P1")
	var player: Node = level.get("Player")
	var lamp: Node = player.get("Flashlight") if player != null else null
	var cutscene: Node = level.get("Cutscene")
	var patrol: Node = level.get("Patrol")
	var room: Node = level.get_node_or_null("Rooms/Room_Patrol")
	for pair in [[pool1, "LitZone_P1"], [player, "Player"], [lamp, "Player.Flashlight"], [cutscene, "Cutscene"], [patrol, "Patrol"], [room, "Rooms/Room_Patrol"]]:
		_check(pair[0] != null, "the prologue has no %s" % pair[1])
	if pool1 == null or player == null or lamp == null or cutscene == null or patrol == null or room == null:
		level.queue_free()
		_finish()
		return
	patrol.process_mode = Node.PROCESS_MODE_DISABLED
	var zone: Node = scene.instantiate()
	zone.Room = room
	zone.position = ZONE_POS   # before it enters the tree: _Ready checks the band against Room
	level.add_child(zone)
	await _step(OVERLAP_FRAMES)
	_check(is_equal_approx(zone.WarningSeconds, WINDOW), "the placed zone's WarningSeconds=%s, expected %s" % [zone.WarningSeconds, WINDOW])
	_check(pool1.collision_layer == LIGHT_DARK_LAYER, "LitZone_P1 collision_layer=%d, expected %d (LightDark)" % [pool1.collision_layer, LIGHT_DARK_LAYER])
	_check(pool1.monitoring == false, "LitZone_P1 monitoring=%s, expected false (the hero's sensor looks, not the pool)" % pool1.monitoring)
	var pool_shape: Node = pool1.get_node_or_null("CollisionShape2D")
	_check(pool_shape != null and pool_shape.disabled == false, "LitZone_P1's shape is off; the work lights should hold the bus at boot")

	# The zone is a gate at every depth: the watched stretch spans the room's whole walk band.
	var box: CollisionShape2D = zone.get_node_or_null("CollisionShape2D")
	_check(box != null and box.shape is RectangleShape2D, "the placed zone has no rectangular shape")
	if box != null and box.shape is RectangleShape2D:
		var top: float = box.global_position.y - box.shape.size.y * 0.5
		var bottom: float = box.global_position.y + box.shape.size.y * 0.5
		_check(top <= room.FloorTop and bottom >= room.FloorBottom,
			"the zone watches Y %.0f..%.0f, expected the whole walk band %.0f..%.0f — the hero could slip past it in depth"
			% [top, bottom, room.FloorTop, room.FloorBottom])

	# Let the hero out of the intro cutscene: he is frozen (and out of the physics space) until then.
	await _play_out(cutscene)
	level.RespawnDelay = SAFE_DELAY
	player.global_position = OUTSIDE_POS
	level.ApplyRoomBounds(room)
	await _step(OVERLAP_FRAMES)
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
			"the hero at %s is not inside the zone — it leaves a lane at that depth" % probe)
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
	_check(player.IsLit == true, "standing in LitZone_P1 at %s the hero is not lit" % POOL_POS)
	_check(spotted.size() == 2, "Spotted fired %d times when the hero stepped into a lamp pool, expected 2 in total" % spotted.size())
	await _place(player, DARK_BESIDE_POOL)
	await _step(SPOT_FRAMES)
	_check(player.IsLit == false, "the hero is still lit in the dark stripe at %s" % DARK_BESIDE_POOL)
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

	# And it stays quiet over the body. Player.Kill() is a no-op while he is knocked out and the head
	# lamp only goes out on the revive, so a zone that kept polling IsLit would re-arm on the next
	# frame, flare its alert light and fire Spotted (and Caught again) throughout RespawnDelay.
	await _step(DARK_FRAMES)
	_check(spotted.size() == 3, "the crew re-armed on a knocked-out hero (Spotted %d times, expected 3)" % spotted.size())
	_check(caught.size() == 1, "the crew caught a hero who was already down (Caught %d times, expected 1)" % caught.size())
	_check(zone.IsWarning == false, "a warning window is running over a knocked-out hero")
	_check(zone.AlertLight.enabled == false, "the alert light is flaring over a knocked-out hero")
	lamp.SetOn(false)

	# 7. A retired zone is inert for good (a level retires a crew that can no longer reach the hero).
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
