extends SceneTree
# Smoke: the TestMine fixture and the level-side mechanics of the escape (T-07s-a) — the scene
# loads with TestMine.cs and every export wired; DebrisPile.tscn's contract and defaults; a pile is a
# gate at every depth (its blocker spans the whole walk band, and a walk along the far and the near
# edge of the band is stopped by both the timber pile and the flooded drift — the same walk goes
# through once they are cleared); the pile discriminates hands from tools with real attacks (three
# light attacks only get Resisted, a heavy 13 px off the pile's depth line lands nothing at all, at
# 12 px it registers Damaged, and the second qualifying heavy Clears it and opens the way); the
# cave-in fires once, seals the drift behind the hero after its delay and never fires again; a reached
# Checkpoint turns a death into a soft respawn that keeps the whole world (cleared pile, collapsed
# drift, powered machine) and hands the checkpoint's energy back; a respawn never happens behind an
# open pause menu; and a level with no checkpoints (TestRoom) still takes the old reload path,
# unchanged by this task.
# Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/level_mine.gd
#
# A heavy attack that connects triggers a hit-stop (Engine.time_scale = 0), which stops physics
# frames, so every attack is observed on idle frames under a wall-clock cap — that is also how a
# whiff is proven to be a whiff (the time scale never drops). The respawn delays are the level's
# own real-time timers and are awaited with ignore-time-scale timers.

const NAME := "level_mine"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls.
const MAX_FRAMES := 20000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const SETTLE_CAP := 10         # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05     # process delta (s) below which the loop is back to normal pacing
const WORLD_LAYER := 1         # physics layer 1 "World"
const ENEMY_LAYER := 4         # physics layer 3 "Enemy" — "a Hitbox may hit this"
const OVERLAP_FRAMES := 4      # physics frames for Area2D overlaps to refresh after a teleport
const PILE_POS := Vector2(440, 450)
const HIT_POS := Vector2(390, 450)      # in reach of the pile's Hurtbox, clear of its blocker
const MISS_DY := 13.0          # 1 px past the hero's inclusive 12 px DepthTolerance
const HIT_DY := 12.0           # exactly on the tolerance: this one must register
const ATTACK_CAP_MS := 700     # wall-clock cap while waiting for one attack to resolve
const WHIFF_MS := 500          # wall-clock window in which a whiff must stay a whiff (heavy anim < 0.5 s)
const RESTORE_CAP_MS := 1000   # wall-clock cap while waiting for the hit-stop to lift
const IDLE_CAP := 90           # physics frames allowed for the hero to come back to Idle
const NEAR_PUMP := Vector2(555, 450)    # inside the pump's reach
const CP_GAS_POS := Vector2(1080, 450)  # centre of Checkpoint_Gas
const CAVEIN_POS := Vector2(1550, 450)  # centre of the cave-in trigger
const OFF_TRIGGER_POS := Vector2(1660, 450)   # right of the cave-in, clear of the fresh pile
const BLOCK_FRAMES := 50       # frames of move_right: 220 px/s x 0.83 s = 183 px, past any pile
const BLOCK_APPROACH := 90.0   # px left of a pile the blocked walk starts from
const BLOCK_MARGIN := 20.0     # px short of the pile's root X the hero must still be
const PASS_MARGIN := 30.0      # px past the pile's root X a cleared pile lets him reach
const BAND_MARGIN := 20.0      # px inside the walk band's far and near edge the probes walk along
const CHECKPOINT_ENERGY := 55.0
const DELAY_MARGIN := 0.4      # extra real seconds on top of a level timer
const RESPAWN_EPS := 2.0       # px the respawn may miss the checkpoint's respawn point by
const TESTROOM_RESTART := 0.25 # RestartDelay shortened so the old reload path is reached quickly
const EXPECTED_LABELS := ["Start", "Before the gas"]

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

# Real-time wait that ignores Engine.time_scale and the pause (the level's own timers).
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

# Waits (physics frames) until `cond` holds. Returns the frames waited, or -1 after `cap`.
func _wait_until(cond: Callable, cap: int) -> int:
	for i in cap:
		if cond.call():
			return i
		await physics_frame
	return -1

# Walks the hero right from `from` for BLOCK_FRAMES frames and returns the X he ended at.
func _walk_right(player: Node, from: Vector2) -> float:
	player.global_position = from
	await _step(2)
	Input.action_press("move_right")
	await _step(BLOCK_FRAMES)
	Input.action_release("move_right")
	await _step(2)
	return player.global_position.x

# Presses `action` for exactly one physics frame.
func _tap(action: String) -> void:
	Input.action_press(action)
	await _step(1)
	Input.action_release(action)

# Watches idle frames (which keep running under a hit-stop) until `flags` grows or `cap_ms` passes.
# Reports whether it fired, the time scale at that moment and the lowest time scale seen, so a
# whiff can be proven by "the game never froze".
func _watch(flags: Array, cap_ms: int) -> Dictionary:
	var before: int = flags.size()
	var r := {"fired": false, "scale": 1.0, "lowest": Engine.time_scale}
	var deadline: int = Time.get_ticks_msec() + cap_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		r["lowest"] = minf(r["lowest"], Engine.time_scale)
		if flags.size() > before:
			r["fired"] = true
			r["scale"] = Engine.time_scale
			break
	return r

# Waits (idle frames) until Engine.time_scale is back to 1. Returns elapsed ms, or -1 on cap.
func _wait_restored(cap_ms: int) -> int:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < cap_ms:
		if Engine.time_scale == 1.0:
			return Time.get_ticks_msec() - start
		await process_frame
	return -1

func _run() -> void:
	# 0. Preconditions: the attack actions the pile discriminates on, and GameState.
	for a in ["attack", "heavy_attack"]:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)
		if InputMap.has_action(a):
			_check(InputMap.action_get_events(a).size() > 0, "action '%s' has no events" % a)
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	# 1. DebrisPile.tscn: contract and defaults.
	var pile_scene: PackedScene = load("res://scenes/props/DebrisPile.tscn")
	_check(pile_scene != null, "res://scenes/props/DebrisPile.tscn failed to load")
	if pile_scene == null:
		_finish()
		return
	var proto: Node = pile_scene.instantiate()
	_check(proto is StaticBody2D, "DebrisPile.tscn root is a %s, expected StaticBody2D" % proto.get_class())
	_check(proto.get_script() != null and str(proto.get_script().resource_path).ends_with("DebrisPile.cs"),
		"DebrisPile.tscn has no DebrisPile.cs attached (did dotnet build run?)")
	if proto.get("HeavyHitsToClear") == null:
		_check(false, "DebrisPile exports missing — C# scripts not attached, aborting")
		proto.free()
		_finish()
		return
	_check(proto.HeavyHitsToClear == 2, "DebrisPile.HeavyHitsToClear default is %s, expected 2" % proto.HeavyHitsToClear)
	_check(proto.RequiresKnockdown == true, "DebrisPile.RequiresKnockdown default is %s, expected true (only a heavy floors rubble)" % proto.RequiresKnockdown)
	_check(proto.StartsCleared == false, "DebrisPile.StartsCleared default is %s, expected false" % proto.StartsCleared)
	_check(proto.get("SaveId") != null, "DebrisPile.SaveId export missing (T-09 hook)")
	_check(proto.collision_layer == WORLD_LAYER, "DebrisPile.tscn collision_layer=%d, expected %d (World)" % [proto.collision_layer, WORLD_LAYER])
	_check(proto.collision_mask == 0, "DebrisPile.tscn collision_mask=%d, expected 0" % proto.collision_mask)
	_check(proto.get("BlockerShape") == proto.get_node_or_null("CollisionShape2D"), "DebrisPile.BlockerShape does not point at the CollisionShape2D")
	var phurt: Node = proto.get_node_or_null("Hurtbox")
	_check(phurt is Area2D, "DebrisPile.tscn has no Hurtbox Area2D")
	if phurt is Area2D:
		_check(proto.get("Hurtbox") == phurt, "DebrisPile.Hurtbox export does not point at the child")
		_check(phurt.collision_layer == ENEMY_LAYER, "DebrisPile/Hurtbox collision_layer=%d, expected %d (the layer a Hitbox masks)" % [phurt.collision_layer, ENEMY_LAYER])
		_check(phurt.collision_mask == 0, "DebrisPile/Hurtbox collision_mask=%d, expected 0" % phurt.collision_mask)
		_check(phurt.monitoring == false, "DebrisPile/Hurtbox monitoring=%s, expected false (it is hit, it does not look)" % phurt.monitoring)
		_check(phurt.monitorable == true, "DebrisPile/Hurtbox monitorable=%s, expected true" % phurt.monitorable)
	_check(proto.get("Rubble") == proto.get_node_or_null("PH_Rubble"), "DebrisPile.Rubble does not point at PH_Rubble")
	_check(proto.get("Dust") == proto.get_node_or_null("PH_Dust"), "DebrisPile.Dust does not point at PH_Dust")
	proto.free()
	if _failures.size() > 0:
		_finish()
		return

	# 2. TestMine: the fixture loads and everything is wired.
	var scene: PackedScene = load("res://scenes/levels/TestMine.tscn")
	_check(scene != null, "res://scenes/levels/TestMine.tscn failed to load")
	if scene == null:
		_finish()
		return
	var room: Node = scene.instantiate()
	root.add_child(room)
	await _settle()
	_check(str(room.name) == "TestMine", "TestMine.tscn root is named '%s', expected 'TestMine'" % room.name)
	_check(room.get_script() != null and str(room.get_script().resource_path).ends_with("TestMine.cs"),
		"TestMine.tscn has no TestMine.cs attached")
	_check(room.get("y_sort_enabled") == true, "TestMine root lacks y_sort_enabled (belt-scroll depth sorting)")

	var player: Node = room.get_node_or_null("Player")
	var pile: Node = room.get_node_or_null("DebrisPile_Hand")
	var flood: Node = room.get_node_or_null("Flood")
	var back: Node = room.get_node_or_null("DebrisPile_Back")
	var cavein: Node = room.get_node_or_null("CaveIn_Mid")
	var pump: Node = room.get_node_or_null("Pump")
	var circuit: Node = room.get_node_or_null("Circuit")
	var cp_start: Node = room.get_node_or_null("Checkpoints/Checkpoint_Start")
	var cp_gas: Node = room.get_node_or_null("Checkpoints/Checkpoint_Gas")
	for pair in [[player, "Player"], [pile, "DebrisPile_Hand"], [flood, "Flood"], [back, "DebrisPile_Back"], [cavein, "CaveIn_Mid"],
			[pump, "Pump"], [circuit, "Circuit"], [cp_start, "Checkpoints/Checkpoint_Start"], [cp_gas, "Checkpoints/Checkpoint_Gas"]]:
		_check(pair[0] != null, "TestMine has no '%s' child" % pair[1])
	if player == null or pile == null or flood == null or back == null or cavein == null or pump == null or circuit == null or cp_start == null or cp_gas == null:
		room.queue_free()
		_finish()
		return
	if player.get("DepthTolerance") == null or pile.get("HeavyHitsToClear") == null or cavein.get("Delay") == null or cp_gas.get("Label") == null:
		_check(false, "Player/DebrisPile/CaveIn/Checkpoint exports missing in TestMine — aborting")
		room.queue_free()
		_finish()
		return

	_check(room.get("Player") == player, "TestMine.Player export does not point at the Player")
	_check(room.get("Camera") == room.get_node_or_null("Camera2D"), "TestMine.Camera export does not point at Camera2D")
	_check(room.get("Pause") == room.get_node_or_null("PauseMenu"), "TestMine.Pause export does not point at PauseMenu")
	_check(room.get("Hud") == room.get_node_or_null("HUD"), "TestMine.Hud export does not point at HUD")
	_check(room.get("Companion") == room.get_node_or_null("Companion"), "TestMine.Companion export does not point at the Companion")
	_check(room.get("Checkpoints") == room.get_node_or_null("Checkpoints"), "TestMine.Checkpoints export does not point at the Checkpoints container")
	_check(room.get("StartRoom") == room.get_node_or_null("Rooms/Room_Main"), "TestMine.StartRoom export does not point at Room_Main")
	_check(room.get("Circuit") == circuit, "TestMine.Circuit export does not point at the Circuit")
	_check(room.get("Cage") == room.get_node_or_null("Hoist"), "TestMine.Cage export does not point at the Hoist")
	_check(room.get("Collapse") == cavein, "TestMine.Collapse export does not point at CaveIn_Mid")
	_check(room.get("DebugLabel") == room.get_node_or_null("UI/DebugLabel"), "TestMine.DebugLabel export does not point at UI/DebugLabel")
	_check(Array(room.GasPockets).size() == 2, "TestMine.GasPockets has %d entries, expected 2 (the rehearsal pocket and the normal one)" % Array(room.GasPockets).size())
	_check(is_equal_approx(room.RespawnDelay, 0.9), "LevelBase.RespawnDelay default is %s, expected 0.9" % room.RespawnDelay)
	_check(is_equal_approx(room.MinRespawnEnergy, 30.0), "LevelBase.MinRespawnEnergy default is %s, expected 30" % room.MinRespawnEnergy)
	_check(room.ArmedCheckpoint == null, "a checkpoint is armed before the hero reached one")
	# The hero's floor band comes from the room's bounds, applied on ready.
	_check(is_equal_approx(player.FloorTop, 300.0) and is_equal_approx(player.FloorBottom, 600.0),
		"the hero's floor band is %s..%s, expected the room's 300..600 (ApplyRoomBounds did not run)" % [player.FloorTop, player.FloorBottom])

	var labels: Array = []
	for c in room.get_node("Checkpoints").get_children():
		labels.append(str(c.Label))
	_check(labels == EXPECTED_LABELS, "the checkpoint labels are %s, expected %s" % [labels, EXPECTED_LABELS])
	_check(cp_gas.RespawnOffset == Vector2(-32, 0), "Checkpoint_Gas.RespawnOffset is %s, expected (-32, 0)" % cp_gas.RespawnOffset)
	_check(cp_gas.RespawnPosition == cp_gas.global_position + cp_gas.RespawnOffset,
		"Checkpoint_Gas.RespawnPosition is %s, expected position + offset %s" % [cp_gas.RespawnPosition, cp_gas.global_position + cp_gas.RespawnOffset])
	_check(cp_start.IsReached == false and cp_gas.IsReached == false, "a checkpoint is already reached at level start")
	_check(pile.HeavyHitsToClear == 2, "DebrisPile_Hand.HeavyHitsToClear=%s, expected 2" % pile.HeavyHitsToClear)
	_check(pile.IsCleared == false, "DebrisPile_Hand.IsCleared=%s at start, expected false" % pile.IsCleared)
	_check(pile.HitsLeft == 2, "DebrisPile_Hand.HitsLeft=%s at start, expected 2" % pile.HitsLeft)
	_check(pile.position == PILE_POS, "DebrisPile_Hand at %s, expected %s" % [pile.position, PILE_POS])
	_check(room.get_node_or_null("PH_HitStrip") is Polygon2D, "TestMine has no PH_HitStrip decal marking the pile's depth strip")
	# The pile the cave-in drops starts invisible and open.
	_check(back.StartsCleared == true, "DebrisPile_Back.StartsCleared=%s, expected true (it appears on the collapse)" % back.StartsCleared)
	_check(back.IsCleared == true, "DebrisPile_Back.IsCleared=%s at start, expected true" % back.IsCleared)
	_check(back.BlockerShape.disabled == true, "DebrisPile_Back blocks the drift before the collapse")
	_check(back.Rubble != null and back.Rubble.visible == false, "DebrisPile_Back's rubble is visible before the collapse")
	_check(is_equal_approx(cavein.Delay, 0.35), "CaveIn.Delay default is %s, expected 0.35 (the rubble lands behind the hero)" % cavein.Delay)
	_check(cavein.get("Level") == room, "CaveIn_Mid.Level does not point at the level (no camera shake)")
	_check(cavein.get("Blockage") == back, "CaveIn_Mid.Blockage does not point at DebrisPile_Back")
	_check(cavein.IsTriggered == false and cavein.HasCollapsed == false, "the cave-in already fired at level start")
	if _failures.size() > 0:
		room.queue_free()
		_finish()
		return

	# 2b. A pile is a gate at EVERY depth. The blocking shape spans the room's whole walk band, so
	# there is no lane along its far or near edge — without this the timber pile teaches nothing and
	# the flooded drift is not a reason to switch the pump on. Structure first, then the walk.
	var band_top: float = player.FloorTop + BAND_MARGIN
	var band_bottom: float = player.FloorBottom - BAND_MARGIN
	for pair in [[pile, "DebrisPile_Hand"], [flood, "Flood"]]:
		var gate: Node = pair[0]
		var gate_name: String = pair[1]
		_check(is_equal_approx(gate.BlockerDepth, 320.0),
			"%s.BlockerDepth=%s, expected 320 (the 300 px walk band with a margin)" % [gate_name, gate.BlockerDepth])
		var box: Shape2D = gate.BlockerShape.shape
		_check(box is RectangleShape2D, "%s's blocker is a %s, expected a RectangleShape2D" % [gate_name, box.get_class()])
		if box is RectangleShape2D:
			var top: float = gate.BlockerShape.global_position.y - box.size.y * 0.5
			var bottom: float = gate.BlockerShape.global_position.y + box.size.y * 0.5
			_check(top <= player.FloorTop and bottom >= player.FloorBottom,
				"%s blocks Y %.0f..%.0f, expected to cover the whole walk band %.0f..%.0f — the hero could walk around it in depth"
				% [gate_name, top, bottom, player.FloorTop, player.FloorBottom])
		for depth in [band_top, band_bottom]:
			var start: Vector2 = Vector2(gate.global_position.x - BLOCK_APPROACH, depth)
			var reached: float = await _walk_right(player, start)
			_check(reached <= gate.global_position.x - BLOCK_MARGIN,
				"walking right at Y %.0f the hero reached x %.0f, past %s at x %.0f — the pile can be bypassed in depth"
				% [depth, reached, gate_name, gate.global_position.x])
	_release_all()

	var resisted: Array = []
	var damaged: Array = []
	var cleared: Array = []
	pile.Resisted.connect(func(): resisted.append(true))
	pile.Damaged.connect(func(left: int): damaged.append(left))
	pile.Cleared.connect(func(): cleared.append(true))

	# 3. Hands alone do nothing: three light attacks are shrugged off (acceptance 11).
	await _place(player, HIT_POS)
	_check(player.CurrentStateName == "Idle", "the hero is in '%s' before the first attack, expected 'Idle'" % player.CurrentStateName)
	for i in 3:
		await _tap("attack")
		var light: Dictionary = await _watch(resisted, ATTACK_CAP_MS)
		_check(light["fired"], "light attack %d: the pile did not report Resisted within %d ms" % [i + 1, ATTACK_CAP_MS])
		_check(light["lowest"] == 1.0, "light attack %d froze the game (time_scale %s) — a shrugged-off hit must not hit-stop" % [i + 1, light["lowest"]])
		var idle: int = await _wait_until(func(): return player.CurrentStateName == "Idle", IDLE_CAP)
		_check(idle >= 0, "light attack %d: the hero is stuck in '%s'" % [i + 1, player.CurrentStateName])
	_check(resisted.size() == 3, "Resisted fired %d times for three light attacks, expected 3" % resisted.size())
	_check(damaged.is_empty(), "a light attack damaged the pile (Damaged %s)" % [damaged])
	_check(cleared.is_empty(), "a light attack cleared the pile")
	_check(pile.IsCleared == false, "DebrisPile_Hand.IsCleared=%s after three light attacks, expected false" % pile.IsCleared)
	_check(pile.HitsLeft == 2, "DebrisPile_Hand.HitsLeft=%s after three light attacks, expected 2" % pile.HitsLeft)
	_check(pile.BlockerShape.disabled == false, "the pile stopped blocking after light attacks")

	# 4. Depth: a heavy 13 px off the pile's line lands nothing at all (acceptance 12).
	await _place(player, HIT_POS + Vector2(0, MISS_DY))
	_check(absf(player.global_position.y - pile.global_position.y) > player.DepthTolerance,
		"the miss test stands %.1f px off the pile, which is inside DepthTolerance %.1f" % [absf(player.global_position.y - pile.global_position.y), player.DepthTolerance])
	await _tap("heavy_attack")
	var whiff: Dictionary = await _watch(damaged, WHIFF_MS)
	_check(not whiff["fired"], "a heavy attack %.0f px off the pile's depth line damaged it" % MISS_DY)
	_check(whiff["lowest"] == 1.0, "a heavy attack that must miss froze the game (time_scale %s)" % whiff["lowest"])
	_check(resisted.size() == 3, "a heavy attack outside the depth band still reached the pile (Resisted %d times)" % resisted.size())
	if Engine.time_scale != 1.0:
		await _wait_restored(RESTORE_CAP_MS)
	await _wait_until(func(): return player.CurrentStateName == "Idle", IDLE_CAP)

	# 5. Exactly on the 12 px tolerance the same attack registers, and the second one clears it.
	await _place(player, HIT_POS + Vector2(0, HIT_DY))
	await _tap("heavy_attack")
	var first: Dictionary = await _watch(damaged, ATTACK_CAP_MS)
	_check(first["fired"], "a heavy attack exactly on the %.0f px tolerance did not register (Damaged never fired)" % HIT_DY)
	if first["fired"]:
		_check(damaged == [1], "Damaged history is %s, expected [1] (one of two heavy hits left)" % [damaged])
		_check(first["scale"] == 0.0, "Engine.time_scale=%s on a landed heavy, expected 0 (hit-stop)" % first["scale"])
	_check(pile.HitsLeft == 1, "DebrisPile_Hand.HitsLeft=%s after one heavy, expected 1" % pile.HitsLeft)
	_check(cleared.is_empty(), "the pile was cleared by a single heavy attack")
	var restored: int = await _wait_restored(RESTORE_CAP_MS)
	_check(restored >= 0, "the hit-stop of the first heavy never lifted")
	await _wait_until(func(): return player.CurrentStateName == "Idle", IDLE_CAP)

	await _place(player, HIT_POS)
	await _tap("heavy_attack")
	var second: Dictionary = await _watch(cleared, ATTACK_CAP_MS)
	_check(second["fired"], "the second heavy attack did not clear the pile")
	_check(cleared.size() == 1, "Cleared fired %d times, expected 1" % cleared.size())
	_check(damaged == [1], "Damaged history is %s, expected [1] — the clearing hit reports Cleared, not Damaged" % [damaged])
	_check(pile.IsCleared == true, "DebrisPile_Hand.IsCleared=%s after two heavy hits, expected true" % pile.IsCleared)
	_check(pile.HitsLeft == 0, "DebrisPile_Hand.HitsLeft=%s once cleared, expected 0" % pile.HitsLeft)
	await _wait_restored(RESTORE_CAP_MS)
	await _step(2)   # the blocker flags are deferred
	_check(pile.BlockerShape.disabled == true, "the cleared pile still blocks the drift")
	_check(pile.Rubble != null and pile.Rubble.visible == false, "the cleared pile is still visible")
	_check(pile.Hurtbox == null or pile.Hurtbox.monitorable == false, "the cleared pile is still hittable")
	await _wait_until(func(): return player.CurrentStateName == "Idle", IDLE_CAP)
	# The control for §2b: the very walk that was stopped along the far edge of the band now goes
	# straight through, so what stopped it was the pile and not the test.
	var pile_open: float = await _walk_right(player, Vector2(PILE_POS.x - BLOCK_APPROACH, band_top))
	_check(pile_open >= PILE_POS.x + PASS_MARGIN,
		"after two heavy hits the hero only reached x %.0f walking at Y %.0f, expected past x %.0f" % [pile_open, band_top, PILE_POS.x + PASS_MARGIN])
	_release_all()
	await _wait_until(func(): return player.CurrentStateName == "Idle", IDLE_CAP)

	# 6. One powered machine, so the respawn has some world state to preserve.
	await _place(player, NEAR_PUMP)
	pump.Begin(player)
	await _step(4)
	_check(pump.IsPowered == true, "the pump did not start (IsPowered=%s)" % pump.IsPowered)
	_check(circuit.Used == 1, "Circuit.Used=%s with the pump running, expected 1" % circuit.Used)
	# ... and the drained drift stops blocking at every depth, not only at the band's centre.
	_check(flood.IsCleared == true, "Flood.IsCleared=%s with the pump running, expected true" % flood.IsCleared)
	var flood_open: float = await _walk_right(player, Vector2(flood.global_position.x - BLOCK_APPROACH, band_bottom))
	_check(flood_open >= flood.global_position.x + PASS_MARGIN,
		"after the pump the hero only reached x %.0f walking at Y %.0f, expected past x %.0f" % [flood_open, band_bottom, flood.global_position.x + PASS_MARGIN])
	_release_all()
	await _wait_until(func(): return player.CurrentStateName == "Idle", IDLE_CAP)

	# 7. The checkpoint arms once and snapshots the energy the hero has (acceptance 14).
	var armed: Array = []
	var respawns: Array = []
	room.CheckpointArmed.connect(func(c): armed.append(c))
	room.Respawned.connect(func(): respawns.append(true))
	gs.Energy = CHECKPOINT_ENERGY
	await _place(player, CP_GAS_POS)
	_check(cp_gas.IsReached == true, "Checkpoint_Gas was not reached by the hero standing on it")
	_check(armed.size() == 1 and armed[0] == cp_gas, "CheckpointArmed fired %s, expected once with Checkpoint_Gas" % [armed])
	_check(room.ArmedCheckpoint == cp_gas, "LevelBase.ArmedCheckpoint is %s, expected Checkpoint_Gas" % room.ArmedCheckpoint)
	await _place(player, CP_GAS_POS)
	_check(armed.size() == 1, "CheckpointArmed fired %d times, expected 1 (a checkpoint arms once)" % armed.size())

	# 8. The cave-in: one shot, delayed, and it seals the drift behind the hero (acceptance 13).
	var triggered: Array = []
	var collapsed: Array = []
	cavein.Triggered.connect(func(): triggered.append(true))
	cavein.Collapsed.connect(func(): collapsed.append(true))
	await _place(player, CAVEIN_POS)
	_check(triggered.size() == 1, "CaveIn.Triggered fired %d times when the hero crossed it, expected 1" % triggered.size())
	_check(collapsed.is_empty(), "the roof came down in the same frame as the trigger — the rubble must land behind the hero")
	await _real_wait(cavein.Delay + DELAY_MARGIN)
	_check(collapsed.size() == 1, "CaveIn.Collapsed fired %d times, expected 1 after the delay" % collapsed.size())
	_check(cavein.HasCollapsed == true, "CaveIn.HasCollapsed=%s after the collapse, expected true" % cavein.HasCollapsed)
	await _step(2)   # the blocker flags are deferred
	_check(back.IsCleared == false, "DebrisPile_Back.IsCleared=%s after the collapse, expected false (the way back is shut)" % back.IsCleared)
	_check(back.BlockerShape.disabled == false, "the fresh rubble does not block the drift")
	_check(back.Rubble.visible == true, "the fresh rubble is invisible")
	_check(player.IsKnockedOut == false, "the cave-in killed the hero — a collapse the player cannot avoid must never be lethal")
	await _place(player, OFF_TRIGGER_POS)
	await _place(player, CAVEIN_POS)
	_check(triggered.size() == 1, "CaveIn.Triggered fired %d times after crossing it twice, expected 1" % triggered.size())
	_check(collapsed.size() == 1, "CaveIn.Collapsed fired %d times after crossing it twice, expected 1" % collapsed.size())

	# 9. A death now costs seconds, not the level: the world survives the respawn (acceptance 14).
	var kos: Array = []
	player.KnockedOut.connect(func(): kos.append(true))
	var instance_id: int = room.get_instance_id()
	player.Kill()
	_check(kos.size() == 1, "Player.KnockedOut fired %d times for one Kill(), expected 1" % kos.size())
	_check(room.IsRestartPending == true, "LevelBase.IsRestartPending=%s after the KO, expected true" % room.IsRestartPending)
	await _real_wait(room.RespawnDelay + DELAY_MARGIN)
	_check(respawns.size() == 1, "Respawned fired %d times, expected 1" % respawns.size())
	_check(is_instance_valid(room) and room.get_instance_id() == instance_id and room.is_inside_tree(),
		"the level instance was replaced — a checkpoint respawn must not reload the scene")
	_check(player.global_position.distance_to(cp_gas.RespawnPosition) <= RESPAWN_EPS,
		"the hero respawned at %s, expected %s (± %s px)" % [player.global_position, cp_gas.RespawnPosition, RESPAWN_EPS])
	_check(player.IsKnockedOut == false, "the hero is still knocked out after the respawn")
	_check(player.CurrentStateName == "Idle", "the hero respawned in '%s', expected 'Idle'" % player.CurrentStateName)
	_check(player.Flashlight.IsOn == false, "the hero respawned with the head lamp on next to a gas pocket")
	_check(is_equal_approx(gs.Energy, CHECKPOINT_ENERGY),
		"energy after the respawn is %s, expected the checkpoint's %s (never below MinRespawnEnergy %s)" % [gs.Energy, CHECKPOINT_ENERGY, room.MinRespawnEnergy])
	_check(pile.IsCleared == true, "the cleared pile came back after the respawn — the puzzle must not be re-solved")
	_check(cavein.HasCollapsed == true and back.IsCleared == false, "the collapse was undone by the respawn")
	_check(circuit.Used == 1 and pump.IsPowered == true, "the powered pump was reset by the respawn (Used=%s)" % circuit.Used)
	_check(room.ArmedCheckpoint == cp_gas, "the armed checkpoint was lost by the respawn")

	# 10. Nothing respawns behind an open pause menu (acceptance 16).
	paused = true
	player.Kill()
	_check(player.IsKnockedOut == true, "Kill() did not knock the hero out while the game was paused")
	await _real_wait(room.RespawnDelay + DELAY_MARGIN)
	_check(respawns.size() == 1, "the hero respawned (%d times) while the game was paused" % respawns.size())
	_check(player.IsKnockedOut == true, "the hero got up while the game was paused")
	paused = false
	await _real_wait(room.RespawnDelay + DELAY_MARGIN)
	_check(respawns.size() == 2, "Respawned fired %d times after the pause was lifted, expected 2" % respawns.size())
	_check(player.IsKnockedOut == false, "the hero is still down after the pause was lifted")
	room.queue_free()
	await _step(2)

	# 11. A level with no checkpoints keeps the old rule: a KO reloads it (acceptance 15).
	gs.ResetRun()
	var room_scene: PackedScene = load("res://scenes/levels/TestRoom.tscn")
	_check(room_scene != null, "res://scenes/levels/TestRoom.tscn failed to load")
	if room_scene == null:
		_finish()
		return
	var testroom: Node = room_scene.instantiate()
	root.add_child(testroom)
	await _settle()
	_check(testroom.get("Checkpoints") == null, "TestRoom has a Checkpoints container — its KO behaviour would change")
	_check(testroom.ArmedCheckpoint == null, "TestRoom has an armed checkpoint")
	testroom.RestartDelay = TESTROOM_RESTART
	var room_respawns: Array = []
	testroom.Respawned.connect(func(): room_respawns.append(true))
	var hero: Node = testroom.get_node_or_null("Player")
	_check(hero != null, "TestRoom has no Player child")
	if hero == null:
		testroom.queue_free()
		_finish()
		return
	gs.Energy = 42.0
	hero.Kill()
	_check(testroom.IsRestartPending == true, "TestRoom.IsRestartPending=%s after the KO, expected true" % testroom.IsRestartPending)
	await _real_wait(TESTROOM_RESTART + DELAY_MARGIN)
	# No current scene under a test, so RestartLevel() warns instead of reloading; what matters is
	# that the checkpoint path was not taken and the hero was not quietly revived in place.
	_check(room_respawns.is_empty(), "TestRoom took the checkpoint respawn path (%d times) with no checkpoint armed" % room_respawns.size())
	_check(hero.IsKnockedOut == true, "TestRoom revived the hero instead of reloading the level")
	# RestartLevel() resets the run before reloading; RespawnAtCheckpoint() never touches it.
	_check(is_equal_approx(gs.Energy, gs.MaxEnergy),
		"energy after the TestRoom KO is %s, expected the full %s (RestartLevel resets the run)" % [gs.Energy, gs.MaxEnergy])
	testroom.queue_free()

	_finish()
