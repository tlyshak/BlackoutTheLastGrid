extends SceneTree
# Smoke: Dan, the escort companion (T-07s-a) — Companion.tscn contract and export defaults, and the
# behaviour that makes him company instead of a puzzle, driven on TestMine: he is on
# collision_layer 0 / mask 1, so the hero walks straight through him and no Checkpoint, CaveIn or
# GasZone (all masking the Player layer) ever sees him; his Follow state closes a 340 px gap and
# then stands still playing `idle`; the three anti-stuck failsafes work — a warp when the follow
# point is past WarpDistance, a warp after StuckSeconds of "wants to walk, is not moving" (wedged
# behind a wall) and the explicit warp a level does on a room change; HoldAt walks him to a
# scripted spot, emits Arrived once and keeps him there while the hero leaves, and Resume() puts
# him back on the hero; the failsafes cover the Wait state too — a level's warp takes the held spot
# with him instead of sending him marching back, and a hold past WarpDistance is a teleport; Say()
# shows a line for BubbleSeconds, a HUD prompt suppresses the bubble without losing the line, and a
# paused tree freezes the countdown. Also checks the level wiring: a gas warning makes TestMine put
# its GasLine in Dan's bubble. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/actors_companion.gd
#
# Nothing is hit here, so Engine.time_scale stays 1 and movement is counted in physics frames; the
# only real-time waits are the bubble countdown (Companion._Process, idle delta) and the pause
# check, both taken with ignore-time-scale timers.

const NAME := "actors_companion"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls.
const MAX_FRAMES := 12000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const SETTLE_CAP := 10         # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05     # process delta (s) below which the loop is back to normal pacing
const WORLD_LAYER := 1         # physics layer 1 "World"
const OVERLAP_FRAMES := 4      # physics frames for Area2D overlaps to refresh after a teleport
const ARRIVE_CAP := 200        # physics frames allowed to walk to a held position
const CATCH_UP_FRAMES := 120   # frames given to close the starting gap (340 px at 300 px/s = 68)
const HERO_RIGHT := Vector2(1300, 450)   # clear stretch 760..1470: no blocker, and no trigger Dan could reach
const DAN_BEHIND := Vector2(904, 460)    # 340 px behind the hero's follow point (1244)
const HOLD_PATH := Vector2(1350, 450)    # a held spot right in the hero's path
const WALK_FRAMES := 20        # frames of move_right measured for the walk-through comparison
const WALK_EPS := 2.0          # px the two walks may differ by
const STILL_FRAMES := 10       # frames the hero stands on top of Dan without moving
const WARP_FROM := Vector2(200, 460)     # > WarpDistance (900) from the hero's follow point at HERO_RIGHT
const HERO_LEFT := Vector2(300, 450)     # hero for the stuck test; his follow point is at x 244
const WEDGE_POS := Vector2(0, 460)       # behind PH_WallLeft (x 20..60, y 250..650): no way around
const STUCK_CAP := 400         # frames the stuck watchdog is given before the test gives up
const STUCK_EARLY := 6         # frames of slack below StuckSeconds (frame alignment)
const STUCK_LATE := 90         # frames of slack above StuckSeconds (the walk before he wedges)
const HOLD_FAR := Vector2(1700, 460)     # a scripted beat on the far side of the level (> WarpDistance from HERO_LEFT)
const WAIT_WARP_CAP := 10      # physics frames the Wait state's warp failsafe is given
const HOLD_NEAR := Vector2(380, 460)     # a held spot clear of the timber pile's blocker (412..468)
const HOLD_KEEP_FRAMES := 40   # frames the hero is away while Dan must stay on the held spot
const HERO_AWAY := Vector2(600, 450)     # where the hero goes while Dan holds
const GAS_POS := Vector2(920, 450)       # centre of the rehearsal pocket
const BUBBLE_SECONDS := 0.3    # BubbleSeconds shortened so the countdown is cheap to observe
const BUBBLE_WAIT := 0.5       # real seconds > BUBBLE_SECONDS
const LINE := "Stay close."
const EXPECTED_STATES := ["Follow", "Wait"]

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

# Real-time wait that ignores Engine.time_scale and the pause (idle-delta countdowns).
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

# Puts Dan on `pos` and holds him there, so a following state cannot walk him off again.
func _pin(dan: Node, pos: Vector2) -> void:
	dan.WarpTo(pos)
	dan.HoldAt(pos)
	await _step(OVERLAP_FRAMES)

# Waits (physics frames) until `cond` holds. Returns the frames waited, or -1 after `cap`.
func _wait_until(cond: Callable, cap: int) -> int:
	for i in cap:
		if cond.call():
			return i
		await physics_frame
	return -1

# Walks the hero right for WALK_FRAMES frames from `from` and returns the distance covered.
func _measure_walk(player: Node, from: Vector2) -> float:
	player.global_position = from
	await _step(2)
	var start_x: float = player.global_position.x
	Input.action_press("move_right")
	await _step(WALK_FRAMES)
	Input.action_release("move_right")
	await _step(2)
	return player.global_position.x - start_x

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()
	for a in ["move_right", "flashlight"]:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)
		if InputMap.has_action(a):
			_check(InputMap.action_get_events(a).size() > 0, "action '%s' has no events" % a)

	# 1. Companion.tscn: the contract that makes the whole escort class of bugs impossible.
	var comp_scene: PackedScene = load("res://scenes/actors/Companion.tscn")
	_check(comp_scene != null, "res://scenes/actors/Companion.tscn failed to load")
	if comp_scene == null:
		_finish()
		return
	var proto: Node = comp_scene.instantiate()
	_check(proto is CharacterBody2D, "Companion.tscn root is a %s, expected CharacterBody2D" % proto.get_class())
	_check(proto.get_script() != null and str(proto.get_script().resource_path).ends_with("Companion.cs"),
		"Companion.tscn has no Companion.cs attached (did dotnet build run?)")
	if proto.get("FollowDistance") == null:
		_check(false, "Companion exports missing — C# scripts not attached, aborting")
		proto.free()
		_finish()
		return
	_check(proto.collision_layer == 0, "Companion.tscn collision_layer=%d, expected 0 (he must not push the hero or trip a trigger)" % proto.collision_layer)
	_check(proto.collision_mask == WORLD_LAYER, "Companion.tscn collision_mask=%d, expected %d (walls only)" % [proto.collision_mask, WORLD_LAYER])
	_check(proto.Target == null, "Companion.Target default is %s, expected null (the level wires it)" % proto.Target)
	_check(is_equal_approx(proto.MoveSpeed, 205.0), "Companion.MoveSpeed default is %s, expected 205 (just under the hero's 220)" % proto.MoveSpeed)
	_check(is_equal_approx(proto.CatchUpSpeed, 300.0), "Companion.CatchUpSpeed default is %s, expected 300" % proto.CatchUpSpeed)
	_check(is_equal_approx(proto.FollowDistance, 90.0), "Companion.FollowDistance default is %s, expected 90" % proto.FollowDistance)
	_check(is_equal_approx(proto.CatchUpDistance, 260.0), "Companion.CatchUpDistance default is %s, expected 260" % proto.CatchUpDistance)
	_check(is_equal_approx(proto.WarpDistance, 900.0), "Companion.WarpDistance default is %s, expected 900" % proto.WarpDistance)
	_check(is_equal_approx(proto.StuckSeconds, 2.5), "Companion.StuckSeconds default is %s, expected 2.5" % proto.StuckSeconds)
	_check(is_equal_approx(proto.SideOffset, -56.0), "Companion.SideOffset default is %s, expected -56 (behind the hero)" % proto.SideOffset)
	_check(is_equal_approx(proto.DepthOffset, 10.0), "Companion.DepthOffset default is %s, expected 10 (off the hero's depth line)" % proto.DepthOffset)
	_check(is_equal_approx(proto.ArriveDistance, 12.0), "Companion.ArriveDistance default is %s, expected 12" % proto.ArriveDistance)
	_check(is_equal_approx(proto.BubbleSeconds, 2.6), "Companion.BubbleSeconds default is %s, expected 2.6" % proto.BubbleSeconds)
	_check(proto.Facing == 1, "Companion.Facing default is %s, expected 1" % proto.Facing)
	var psm: Node = proto.get_node_or_null("StateMachine")
	_check(psm != null, "Companion.tscn has no StateMachine child")
	if psm != null:
		_check(proto.get("StateMachine") == psm, "Companion.StateMachine export does not point at the child")
		for s in EXPECTED_STATES:
			_check(psm.get_node_or_null(s) != null, "Companion StateMachine lacks a '%s' state node" % s)
		var initial: Node = psm.get("InitialState")
		_check(initial != null and str(initial.name) == "Follow", "Companion StateMachine InitialState is '%s', expected the Follow node" % initial)
	var pbubble: Node = proto.get_node_or_null("Bubble")
	_check(pbubble is Label, "Companion.tscn has no Bubble Label")
	if pbubble is Label:
		_check(proto.get("Bubble") == pbubble, "Companion.Bubble export does not point at the child")
		_check(pbubble.visible == false, "Companion.tscn ships with a visible Bubble")
	var panim: Node = proto.get_node_or_null("AnimationPlayer")
	_check(panim is AnimationPlayer, "Companion.tscn has no AnimationPlayer")
	if panim is AnimationPlayer:
		for a in ["idle", "walk", "RESET"]:
			_check(panim.has_animation(a), "Companion AnimationPlayer lacks the '%s' animation" % a)
		_check(not panim.has_animation("attack"), "Companion has an 'attack' animation — he never fights")
	_check(proto.get_node_or_null("Visual/Rig") != null, "Companion.tscn has no Visual/Rig CharacterRig")
	proto.free()
	if _failures.size() > 0:
		_finish()
		return

	# 2. TestMine: Dan wired to the hero and following from the first frame.
	var scene: PackedScene = load("res://scenes/levels/TestMine.tscn")
	_check(scene != null, "res://scenes/levels/TestMine.tscn failed to load")
	if scene == null:
		_finish()
		return
	var room: Node = scene.instantiate()
	root.add_child(room)
	await _settle()

	var dan: Node = room.get_node_or_null("Companion")
	var player: Node = room.get_node_or_null("Player")
	var cp_start: Node = room.get_node_or_null("Checkpoints/Checkpoint_Start")
	var cavein: Node = room.get_node_or_null("CaveIn_Mid")
	var gas: Node = room.get_node_or_null("GasZone_Rehearsal")
	for pair in [[dan, "Companion"], [player, "Player"], [cp_start, "Checkpoints/Checkpoint_Start"],
			[cavein, "CaveIn_Mid"], [gas, "GasZone_Rehearsal"]]:
		_check(pair[0] != null, "TestMine has no '%s' child" % pair[1])
	if dan == null or player == null or cp_start == null or cavein == null or gas == null:
		room.queue_free()
		_finish()
		return
	if dan.get("FollowDistance") == null or cp_start.get("Label") == null:
		_check(false, "Companion/Checkpoint exports missing in TestMine — aborting")
		room.queue_free()
		_finish()
		return
	_check(dan.Target == player, "TestMine's Companion.Target is %s, expected the Player" % dan.Target)
	_check(dan.HasTarget == true, "Companion.HasTarget=%s in TestMine, expected true" % dan.HasTarget)
	_check(room.get("Companion") == dan, "TestMine (LevelBase).Companion export does not point at the Companion")
	_check(dan.CurrentStateName == "Follow", "Companion starts in '%s', expected 'Follow'" % dan.CurrentStateName)
	_check(dan.IsWaiting == false, "Companion.IsWaiting=%s at start, expected false" % dan.IsWaiting)
	dan.BubbleSeconds = BUBBLE_SECONDS

	var warps: Array = []
	var arrivals: Array = []
	var lines: Array = []
	dan.Warped.connect(func(): warps.append(true))
	dan.Arrived.connect(func(): arrivals.append(true))
	dan.LineShown.connect(func(t: String): lines.append(t))

	# 3. Following: he closes the gap, then stands still and idles (acceptance 17).
	await _place(player, HERO_RIGHT)
	await _pin(dan, DAN_BEHIND)
	dan.Resume()
	var gap0: float = dan.global_position.distance_to(dan.FollowPoint)
	_check(gap0 > dan.CatchUpDistance, "the test starts with a %.0f px gap, expected more than CatchUpDistance %.0f" % [gap0, dan.CatchUpDistance])
	await _step(CATCH_UP_FRAMES)
	var gap1: float = dan.global_position.distance_to(dan.FollowPoint)
	_check(gap1 <= dan.FollowDistance, "Dan is %.0f px from his follow point after %d frames, expected within FollowDistance %.0f" % [gap1, CATCH_UP_FRAMES, dan.FollowDistance])
	_check(dan.velocity == Vector2.ZERO, "Dan's velocity is %s once he caught up, expected zero" % dan.velocity)
	_check(dan.AnimationPlayer.current_animation == "idle", "Dan plays '%s' while standing still, expected 'idle'" % dan.AnimationPlayer.current_animation)
	_check(dan.CurrentStateName == "Follow", "Dan is in '%s' while following, expected 'Follow'" % dan.CurrentStateName)

	# 4. The hero walks through him, and no Player-masking trigger ever sees him (acceptance 18).
	var arrivals_before: int = arrivals.size()
	await _pin(dan, HOLD_PATH)
	var stand: int = await _wait_until(func(): return dan.velocity == Vector2.ZERO and dan.IsWaiting, ARRIVE_CAP)
	_check(stand >= 0, "Dan did not settle on the held spot %s within %d frames" % [HOLD_PATH, ARRIVE_CAP])
	_check(arrivals.size() == arrivals_before + 1, "Arrived fired %d times for one HoldAt, expected 1" % (arrivals.size() - arrivals_before))
	player.global_position = HOLD_PATH   # standing exactly on top of him
	await _step(2)
	var on_top: Vector2 = player.global_position
	await _step(STILL_FRAMES)
	_check(player.global_position.is_equal_approx(on_top),
		"the hero standing on Dan drifted from %s to %s — he must not push" % [on_top, player.global_position])

	var free_walk: float = await _measure_walk(player, HERO_RIGHT)
	await _pin(dan, HOLD_PATH)
	await _wait_until(func(): return dan.velocity == Vector2.ZERO, ARRIVE_CAP)
	var through_walk: float = await _measure_walk(player, HERO_RIGHT)
	_check(absf(through_walk - free_walk) <= WALK_EPS,
		"the hero covered %.1f px walking into Dan and %.1f px with the way clear, expected within %s px" % [through_walk, free_walk, WALK_EPS])

	var reached: Array = []
	cp_start.Reached.connect(func(c): reached.append(c))
	await _pin(dan, cp_start.global_position)
	_check(not cp_start.get_overlapping_bodies().has(dan), "Checkpoint_Start sees Dan as a body — he is on the wrong collision layer")
	_check(cp_start.IsReached == false, "Checkpoint_Start was armed by Dan standing on it")
	_check(reached.is_empty(), "Checkpoint.Reached fired %d times for Dan" % reached.size())
	await _pin(dan, cavein.global_position)
	_check(not cavein.get_overlapping_bodies().has(dan), "CaveIn_Mid sees Dan as a body")
	_check(cavein.IsTriggered == false, "the cave-in was triggered by Dan walking over it")
	_check(cavein.HasCollapsed == false, "the drift came down because of Dan")
	await _pin(dan, gas.global_position)
	_check(not gas.get_overlapping_bodies().has(dan), "GasZone_Rehearsal sees Dan as a body")
	_check(gas.IsWarning == false, "the gas started counting down because of Dan")

	# 5. Failsafe 1 — too far behind: he appears at the follow point at once (acceptance 19).
	await _place(player, HERO_RIGHT)
	dan.Resume()
	await _step(2)
	dan.WarpTo(WARP_FROM)
	var warps_before: int = warps.size()
	var far: float = dan.global_position.distance_to(dan.FollowPoint)
	_check(far > dan.WarpDistance, "the test starts Dan %.0f px away, expected more than WarpDistance %.0f" % [far, dan.WarpDistance])
	await _step(3)
	_check(warps.size() > warps_before, "Dan %.0f px behind (WarpDistance %.0f) was not warped" % [far, dan.WarpDistance])
	_check(dan.global_position.distance_to(dan.FollowPoint) <= dan.FollowDistance,
		"after the warp Dan is %.0f px from his follow point, expected within FollowDistance %.0f" % [dan.global_position.distance_to(dan.FollowPoint), dan.FollowDistance])

	# 6. Failsafe 2 — wedged behind a wall: a warp after StuckSeconds, not before.
	await _place(player, HERO_LEFT)
	dan.WarpTo(WEDGE_POS)
	dan.Resume()
	await _step(2)
	_check(dan.global_position.distance_to(dan.FollowPoint) > dan.FollowDistance,
		"the wedge test starts inside FollowDistance, so Dan would never try to walk")
	warps_before = warps.size()
	var stuck_at: int = await _wait_until(func(): return warps.size() > warps_before, STUCK_CAP)
	var ticks: int = Engine.physics_ticks_per_second
	var expected_stuck: int = int(dan.StuckSeconds * float(ticks))
	_check(stuck_at >= 0, "Dan wedged behind the wall was never warped within %d frames (IsStuck=%s)" % [STUCK_CAP, dan.IsStuck])
	if stuck_at >= 0:
		_check(stuck_at >= expected_stuck - STUCK_EARLY,
			"Dan was warped after %d frames, expected no earlier than %d (StuckSeconds %.1f s)" % [stuck_at, expected_stuck - STUCK_EARLY, dan.StuckSeconds])
		_check(stuck_at <= expected_stuck + STUCK_LATE,
			"Dan was warped after %d frames, expected within %d (StuckSeconds %.1f s + the walk to the wall)" % [stuck_at, expected_stuck + STUCK_LATE, dan.StuckSeconds])
		_check(dan.global_position.distance_to(dan.FollowPoint) <= dan.FollowDistance,
			"after the stuck warp Dan is %.0f px from his follow point" % dan.global_position.distance_to(dan.FollowPoint))

	# 7. HoldAt / Arrived / Resume: he holds the spot while the hero leaves (acceptance 20).
	arrivals_before = arrivals.size()
	dan.HoldAt(HOLD_NEAR)
	_check(dan.IsWaiting == true, "Companion.IsWaiting=%s right after HoldAt, expected true" % dan.IsWaiting)
	_check(dan.CurrentStateName == "Wait", "Companion is in '%s' after HoldAt, expected 'Wait'" % dan.CurrentStateName)
	var walked: int = await _wait_until(func(): return arrivals.size() > arrivals_before, ARRIVE_CAP)
	_check(walked >= 0, "Dan did not reach the held spot %s within %d frames (he is at %s)" % [HOLD_NEAR, ARRIVE_CAP, dan.global_position])
	_check(arrivals.size() == arrivals_before + 1, "Arrived fired %d times for one HoldAt, expected 1" % (arrivals.size() - arrivals_before))
	_check(dan.global_position.distance_to(HOLD_NEAR) <= dan.ArriveDistance,
		"Dan stopped %.1f px from the held spot, expected within ArriveDistance %.0f" % [dan.global_position.distance_to(HOLD_NEAR), dan.ArriveDistance])
	await _place(player, HERO_AWAY)
	await _step(HOLD_KEEP_FRAMES)
	_check(dan.global_position.distance_to(HOLD_NEAR) <= dan.ArriveDistance,
		"Dan drifted %.1f px off the held spot while the hero walked away" % dan.global_position.distance_to(HOLD_NEAR))
	_check(arrivals.size() == arrivals_before + 1, "Arrived fired again while he was already holding")
	dan.Resume()
	_check(dan.CurrentStateName == "Follow", "Companion is in '%s' after Resume(), expected 'Follow'" % dan.CurrentStateName)
	_check(dan.IsWaiting == false, "Companion.IsWaiting=%s after Resume(), expected false" % dan.IsWaiting)

	# 8. The level makes him speak: a gas warning puts TestMine's GasLine in his bubble.
	var lamp: Node = player.Flashlight
	lines.clear()
	await _place(player, GAS_POS)
	lamp.SetOn(true)
	await _step(2)
	_check(gas.IsWarning == true, "the rehearsal pocket did not start counting down with the lamp on")
	_check(lines.has(room.GasLine), "Dan's lines after the gas warning are %s, expected TestMine.GasLine '%s'" % [lines, room.GasLine])
	lamp.SetOn(false)
	await _step(2)
	_check(gas.IsWarning == false, "the window kept running after the lamp went off")

	# 9. The bubble: shown for BubbleSeconds, hidden by a HUD prompt, frozen by the pause.
	var bubble: Label = dan.Bubble
	_check(bubble != null, "Companion.Bubble export is null in TestMine")
	if bubble == null:
		room.queue_free()
		_finish()
		return
	lines.clear()
	dan.SetBubbleSuppressed(false)
	dan.Say(LINE)
	_check(lines == [LINE], "LineShown history is %s, expected ['%s']" % [lines, LINE])
	_check(dan.CurrentLine == LINE, "Companion.CurrentLine is '%s', expected '%s'" % [dan.CurrentLine, LINE])
	_check(dan.IsSpeaking == true, "Companion.IsSpeaking=%s right after Say(), expected true" % dan.IsSpeaking)
	_check(bubble.text == LINE, "the bubble reads '%s', expected '%s'" % [bubble.text, LINE])
	_check(bubble.visible == true, "the bubble is hidden right after Say()")
	dan.SetBubbleSuppressed(true)
	_check(bubble.visible == false, "the bubble stayed visible while a HUD prompt owns the screen")
	_check(dan.IsSpeaking == true, "suppressing the bubble also dropped the line")
	dan.SetBubbleSuppressed(false)
	_check(bubble.visible == true, "the bubble did not come back when the prompt cleared")
	await _real_wait(BUBBLE_WAIT)
	_check(dan.IsSpeaking == false, "Companion.IsSpeaking=%s %.1f s after a %.1f s line, expected false" % [dan.IsSpeaking, BUBBLE_WAIT, BUBBLE_SECONDS])
	_check(bubble.visible == false, "the bubble is still visible after the line ran out")
	_check(dan.CurrentLine == "", "Companion.CurrentLine is '%s' after the line ran out, expected ''" % dan.CurrentLine)

	dan.Say(LINE)
	paused = true
	await _real_wait(BUBBLE_WAIT)
	_check(dan.IsSpeaking == true, "the bubble countdown kept running while the game was paused")
	paused = false
	await _real_wait(BUBBLE_WAIT)
	_check(dan.IsSpeaking == false, "the bubble countdown did not resume after the pause was lifted")

	# 10. Failsafe 3 — the level warps him on a room change (a door hop, a respawn).
	await _place(player, HERO_RIGHT)
	dan.WarpTo(WARP_FROM)
	warps_before = warps.size()
	room.ApplyRoomBounds(room.StartRoom)
	_check(warps.size() > warps_before, "ApplyRoomBounds did not warp the companion along with the hero")
	_check(dan.global_position.distance_to(dan.FollowPoint) <= dan.FollowDistance,
		"after the room change Dan is %.0f px from his follow point" % dan.global_position.distance_to(dan.FollowPoint))

	# 11. The same failsafes while he holds a scripted spot. A level's warp (a respawn during a beat)
	# must take the hold with him, or he sets off walking back across the mine — possibly into a
	# drift a cave-in has just sealed. And a hold farther away than WarpDistance is taken at once.
	await _place(player, HERO_RIGHT)
	dan.HoldAt(HOLD_FAR)
	_check(dan.IsWaiting == true, "Companion.IsWaiting=%s after HoldAt, expected true" % dan.IsWaiting)
	await _step(2)
	await _place(player, HERO_LEFT)   # the hero died and came back at a checkpoint far from the beat
	warps_before = warps.size()
	room.ApplyRoomBounds(room.StartRoom)
	_check(warps.size() > warps_before, "ApplyRoomBounds did not warp the waiting companion")
	_check(dan.IsWaiting == true, "the level's warp knocked Dan out of the Wait state")
	_check(dan.global_position.distance_to(dan.FollowPoint) <= dan.FollowDistance,
		"after the warp the waiting Dan is %.0f px from the hero" % dan.global_position.distance_to(dan.FollowPoint))
	await _step(HOLD_KEEP_FRAMES)
	_check(dan.global_position.distance_to(dan.FollowPoint) <= dan.CatchUpDistance,
		"the waiting Dan walked %.0f px away from the hero after the warp — the hold did not come with him"
		% dan.global_position.distance_to(dan.FollowPoint))
	# Failsafe 1 in the Wait state: a hold half the level away is a teleport, not a march.
	warps_before = warps.size()
	dan.HoldAt(HOLD_FAR)
	var hold_warp: int = await _wait_until(func(): return warps.size() > warps_before, WAIT_WARP_CAP)
	_check(hold_warp >= 0, "a hold %.0f px away (WarpDistance %.0f) was walked to instead of warped to"
		% [HOLD_FAR.distance_to(dan.FollowPoint), dan.WarpDistance])
	_check(dan.global_position.distance_to(HOLD_FAR) <= dan.ArriveDistance,
		"after the hold warp Dan is %.1f px from the held spot" % dan.global_position.distance_to(HOLD_FAR))
	dan.Resume()

	room.queue_free()
	_finish()
