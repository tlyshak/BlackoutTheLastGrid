extends SceneTree
# Smoke: Dan as the guide (T-07s-e) — the Lead state of Companion.tscn, driven on TestMine with
# direct LeadTo / RunTo / SetWarning / Vanish calls on the free stretch 760..1470 (no blocker, no
# trigger he could reach), plus the fixture's own route (DanLeads = true). He walks to the route
# point at LeadSpeed, emits Arrived once, stops facing the way and stays; re-issuing the same point
# is a no-op; HeroReached fires once per point when the hero comes close and is re-armed by the
# next point; the leash stops him LeadMaxGap ahead of the hero, facing him, and lets him go at
# LeadResumeGap; HeroLagging fires after CallAfterSeconds, repeats every CallRepeatSeconds and is
# capped at MaxCallsPerStop, never once the hero reached him and never while warning; the warning
# stance keeps him facing the way; RunTo drops the leash and runs at RunSpeed; the failsafes aim
# FORWARD — wedged at a blocker he is warped onto the route point on its far side, a point (or a
# hero) past WarpDistance along the way is a warp onto the point, and the level's relocation hook
# leaves a leading Dan on his point (a warp there only when the hero is half a level away) —
# never behind the hero; a leading Dan is still walked through and unseen by every trigger; Vanish
# takes him out for good; and with DanLeads the fixture leads him A -> B (pump powered) -> C
# (checkpoint), showing LeadLine on each arrival and CallLine on a call. The Follow state and the
# scene contract are covered by tests/smoke/actors_companion.gd. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/actors_guide.gd
#
# Nothing is hit here, so Engine.time_scale stays 1 and everything is counted in physics frames;
# the lag timers run on physics delta and are shortened to LAG_SECONDS.

const NAME := "actors_guide"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls.
const MAX_FRAMES := 12000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const SETTLE_CAP := 10         # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05     # process delta (s) below which the loop is back to normal pacing
const OVERLAP_FRAMES := 4      # physics frames for Area2D overlaps to refresh after a teleport
const ARRIVE_CAP := 160        # physics frames allowed to walk 540 px at LeadSpeed 240 (135)
const SHORT_CAP := 100         # physics frames allowed to walk 160 px (40)
const LONG_CAP := 300          # physics frames allowed to walk 940 px (235)
const WARP_CAP := 3            # physics frames a distance failsafe is given
const POINT_A := Vector2(800, 460)      # a route point on the free stretch (not the fixture's WP_A)
const POINT_B := Vector2(1300, 460)     # = WP_B
const POINT_C := Vector2(1460, 460)     # = WP_C, short of DebrisPile_Back's blocker (1472..1528)
const DAN_START := Vector2(760, 460)    # where Dan sets off from for the walk to POINT_B
const HERO_START := Vector2(800, 450)   # the hero 40 px ahead of DAN_START
const HERO_NEAR_B := Vector2(1250, 450) # within HeroCloseDistance (160) of POINT_B
const HERO_NEAR_C := Vector2(1400, 450) # within HeroCloseDistance of POINT_C
const HERO_FAR := Vector2(760, 450)     # 540 px behind POINT_B: past LeadResumeGap, lagging
const HERO_MID := Vector2(1000, 450)    # 300 px from POINT_B: no leash, no lag
const LEASH_MAX := 300.0       # LeadMaxGap shortened so the leash engages on the stretch
const LEASH_RESUME := 180.0    # LeadResumeGap to go with it
const LEASH_DAN := Vector2(820, 460)    # Dan sets off 20 px ahead of the hero at HERO_START
const LEASH_SLACK := 8.0       # px past hero.x + LeadMaxGap he may stop (one frame at 240 px/s = 4)
const LEASH_CAP := 120         # frames given to walk 300 px and stop on the leash
const HERO_RELEASE := Vector2(1300, 450)   # the hero catches up: closer than LEASH_RESUME to a leashed Dan
const LAG_SECONDS := 0.3       # CallAfterSeconds / CallRepeatSeconds shortened
const LAG_WAIT := 1.2          # seconds in which MaxCallsPerStop (2) calls at 0.3 s must all have fired
const LOOK_BACK := 0.3         # LookBackSeconds shortened for the warning check
const WARN_DAN := Vector2(1140, 460)    # Dan sets off left of POINT_B so TravelSign is +1 while the hero is behind
const RUN_FRAMES := 30         # frames of RunTo measured (300 px/s x 0.5 s = 150 px)
const RUN_EPS := 0.05          # 5 % tolerance on the run distance
const HERO_LEFT := Vector2(300, 450)    # the hero behind the timber pile for the stuck and warp tests
const WEDGE_POS := Vector2(380, 460)    # short of DebrisPile_Hand's blocker (412..468)
const PAST_PILE := Vector2(520, 460)    # a route point on the far side of the pile
const BLOCKER_RIGHT := 468.0   # x the blocker ends at
const STUCK_CAP := 400         # frames the stuck watchdog is given before the test gives up
const STUCK_EARLY := 6         # frames of slack below StuckSeconds (frame alignment)
const STUCK_LATE := 90         # frames of slack above StuckSeconds (the walk before he wedges)
const FAR_START := Vector2(300, 460)    # 1000 px from POINT_B: past WarpDistance (900)
const HERO_AHEAD := Vector2(1700, 450)  # > WarpDistance ahead of DAN_START, short of the cave-in trigger (1526..1574)
const ON_TOP_FRAMES := 10      # frames the hero stands on Dan's point without moving
const WALK_FRAMES := 20        # frames of move_right measured for the walk-through comparison
const WALK_EPS := 2.0          # px the two walks may differ by
const HERO_RIGHT := Vector2(1300, 450)  # where the walk-through starts
const LEAD_PATH := Vector2(1350, 460)   # a route point right in the hero's walk
const VANISH_FRAMES := 60      # frames a vanished Dan must stay put
const ROUTE_KEYS := ["A", "B", "C"]

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

# Puts Dan on `pos` and holds him there (Wait), so no state walks him off before the next call.
func _pin(dan: Node, pos: Vector2) -> void:
	dan.WarpTo(pos)
	dan.HoldAt(pos)
	await _step(OVERLAP_FRAMES)

# Puts Dan on `pos` as a route point he has already reached (Lead).
func _lead_pin(dan: Node, pos: Vector2) -> void:
	dan.WarpTo(pos)
	dan.LeadTo(pos)
	await _step(OVERLAP_FRAMES)

# Waits (physics frames) until `cond` holds. Returns the frames waited, or -1 after `cap`.
func _wait_until(cond: Callable, cap: int) -> int:
	for i in cap:
		if cond.call():
			return i
		await physics_frame
	return -1

func _frames_of(seconds: float) -> int:
	return int(ceil(seconds * float(Engine.physics_ticks_per_second)))

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

func _count(lines: Array, line: String) -> int:
	var n := 0
	for l in lines:
		if l == line:
			n += 1
	return n

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()
	_check(InputMap.has_action("move_right"), "InputMap missing action 'move_right'")

	# 1. TestMine as shipped: DanLeads off, Dan following; the route markers exist in order.
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
	var route: Node = room.get_node_or_null("DanRoute")
	var cp_start: Node = room.get_node_or_null("Checkpoints/Checkpoint_Start")
	var cavein: Node = room.get_node_or_null("CaveIn_Mid")
	var gas: Node = room.get_node_or_null("GasZone_Rehearsal")
	for pair in [[dan, "Companion"], [player, "Player"], [route, "DanRoute"], [cp_start, "Checkpoints/Checkpoint_Start"],
			[cavein, "CaveIn_Mid"], [gas, "GasZone_Rehearsal"]]:
		_check(pair[0] != null, "TestMine has no '%s' child" % pair[1])
	if dan == null or player == null or route == null or cp_start == null or cavein == null or gas == null:
		room.queue_free()
		_finish()
		return
	if dan.get("LeadSpeed") == null or room.get("DanLeads") == null:
		_check(false, "Companion/TestMine exports missing — C# scripts not attached (did dotnet build run?), aborting")
		room.queue_free()
		_finish()
		return
	_check(room.DanLeads == false, "TestMine.DanLeads is %s in the scene, expected false" % room.DanLeads)
	_check(room.get("DanRoute") == route, "TestMine.DanRoute export does not point at the DanRoute container")
	_check(dan.CurrentStateName == "Follow", "with DanLeads off Dan starts in '%s', expected 'Follow'" % dan.CurrentStateName)
	_check(dan.IsLeading == false, "Companion.IsLeading=%s with DanLeads off, expected false" % dan.IsLeading)
	var markers: Array = []
	for key in ROUTE_KEYS:
		var m: Node = route.get_node_or_null("WP_" + key)
		_check(m is Marker2D, "DanRoute has no Marker2D 'WP_%s'" % key)
		markers.append(m)
	if markers.any(func(m): return m == null):
		room.queue_free()
		_finish()
		return
	_check(markers[1].global_position == POINT_B and markers[2].global_position == POINT_C,
		"WP_B/WP_C are at %s / %s, expected %s / %s (the free stretch the tests rely on)" % [markers[1].global_position, markers[2].global_position, POINT_B, POINT_C])
	_check(markers[0].global_position.x < markers[1].global_position.x and markers[1].global_position.x < markers[2].global_position.x,
		"the route markers are not in left-to-right order")

	var warps: Array = []
	var arrivals: Array = []
	var reached: Array = []
	var lagging: Array = []
	dan.Warped.connect(func(): warps.append(true))
	dan.Arrived.connect(func(): arrivals.append(true))
	dan.HeroReached.connect(func(): reached.append(true))
	dan.HeroLagging.connect(func(): lagging.append(true))

	# 2. LeadTo: he walks to the point, arrives once, stops facing the way; the same point again is a no-op.
	await _place(player, HERO_START)
	await _pin(dan, DAN_START)
	var arrivals_before: int = arrivals.size()
	dan.LeadTo(POINT_B)
	_check(dan.IsLeading == true, "Companion.IsLeading=%s right after LeadTo, expected true" % dan.IsLeading)
	_check(dan.CurrentStateName == "Lead", "Companion is in '%s' after LeadTo, expected 'Lead'" % dan.CurrentStateName)
	_check(dan.LeadTarget == POINT_B, "Companion.LeadTarget is %s, expected %s" % [dan.LeadTarget, POINT_B])
	_check(dan.TravelSign == 1, "Companion.TravelSign is %d for a point to his right, expected 1" % dan.TravelSign)
	_check(dan.IsAtLeadTarget == false, "Companion.IsAtLeadTarget=%s before he set off, expected false" % dan.IsAtLeadTarget)
	_check(dan.LeadLeashed == true, "Companion.LeadLeashed=%s after LeadTo, expected true" % dan.LeadLeashed)
	await _step(2)
	_check(dan.velocity.x > 0.0, "Dan's velocity is %s two frames into LeadTo, expected him walking right" % dan.velocity)
	_check(dan.AnimationPlayer.current_animation == "walk", "Dan plays '%s' while leading, expected 'walk'" % dan.AnimationPlayer.current_animation)
	var walked: int = await _wait_until(func(): return arrivals.size() > arrivals_before, ARRIVE_CAP)
	_check(walked >= 0, "Dan did not reach %s within %d frames (he is at %s)" % [POINT_B, ARRIVE_CAP, dan.global_position])
	_check(arrivals.size() == arrivals_before + 1, "Arrived fired %d times for one LeadTo, expected 1" % (arrivals.size() - arrivals_before))
	_check(dan.global_position.distance_to(POINT_B) <= dan.ArriveDistance,
		"Dan stopped %.1f px from the route point, expected within ArriveDistance %.0f" % [dan.global_position.distance_to(POINT_B), dan.ArriveDistance])
	_check(dan.IsAtLeadTarget == true, "Companion.IsAtLeadTarget=%s after Arrived, expected true" % dan.IsAtLeadTarget)
	_check(dan.Facing == 1, "Dan faces %d at the point, expected 1 (showing the way, not looking back yet)" % dan.Facing)
	_check(dan.velocity == Vector2.ZERO, "Dan's velocity is %s at the point, expected zero" % dan.velocity)
	await _step(2)
	_check(dan.AnimationPlayer.current_animation == "idle", "Dan plays '%s' at the point, expected 'idle'" % dan.AnimationPlayer.current_animation)
	var at_point: Vector2 = dan.global_position
	dan.LeadTo(POINT_B)
	await _step(5)
	_check(arrivals.size() == arrivals_before + 1, "LeadTo to the same point fired Arrived again (%d in total)" % (arrivals.size() - arrivals_before))
	_check(dan.global_position == at_point, "LeadTo to the same point moved Dan from %s to %s" % [at_point, dan.global_position])
	_check(dan.IsAtLeadTarget == true, "LeadTo to the same point reset IsAtLeadTarget")

	# 3. HeroReached: once per point when the hero comes close; re-armed by the next point.
	var reached_before: int = reached.size()
	await _place(player, HERO_NEAR_B)
	_check(reached.size() == reached_before + 1, "HeroReached fired %d times with the hero %.0f px from the point, expected 1" % [reached.size() - reached_before, HERO_NEAR_B.distance_to(POINT_B)])
	await _place(player, HERO_START)
	await _place(player, HERO_NEAR_B)
	_check(reached.size() == reached_before + 1, "HeroReached fired again for the same point when the hero came back (%d in total)" % (reached.size() - reached_before))
	arrivals_before = arrivals.size()
	dan.LeadTo(POINT_C)
	_check(dan.IsAtLeadTarget == false, "IsAtLeadTarget stayed true after a LeadTo to another point")
	walked = await _wait_until(func(): return arrivals.size() > arrivals_before, SHORT_CAP)
	_check(walked >= 0, "Dan did not reach %s within %d frames (he is at %s)" % [POINT_C, SHORT_CAP, dan.global_position])
	_check(reached.size() == reached_before + 1, "HeroReached fired for the new point with the hero %.0f px away (HeroCloseDistance %.0f)" % [HERO_NEAR_B.distance_to(POINT_C), dan.HeroCloseDistance])
	await _place(player, HERO_NEAR_C)
	_check(reached.size() == reached_before + 2, "HeroReached was not re-armed by the next point (fired %d times in total)" % (reached.size() - reached_before))

	# 4. The leash: LeadMaxGap ahead of the hero he stops and turns to him; LeadResumeGap lets him go.
	dan.LeadMaxGap = LEASH_MAX
	dan.LeadResumeGap = LEASH_RESUME
	await _place(player, HERO_START)
	await _pin(dan, LEASH_DAN)
	arrivals_before = arrivals.size()
	dan.LeadTo(POINT_C)
	var leashed_at: int = await _wait_until(func(): return dan.IsLeashed, LEASH_CAP)
	_check(leashed_at >= 0, "Dan never stopped on the leash within %d frames (LeadMaxGap %.0f, he is at %s)" % [LEASH_CAP, LEASH_MAX, dan.global_position])
	await _step(2)
	_check(dan.global_position.x <= HERO_START.x + LEASH_MAX + LEASH_SLACK,
		"Dan stopped at x %.0f, expected no further than %.0f (hero %.0f + LeadMaxGap %.0f + %.0f)" % [dan.global_position.x, HERO_START.x + LEASH_MAX + LEASH_SLACK, HERO_START.x, LEASH_MAX, LEASH_SLACK])
	_check(dan.velocity == Vector2.ZERO, "a leashed Dan still has velocity %s" % dan.velocity)
	_check(dan.Facing == -1, "a leashed Dan faces %d, expected -1 (turned to the hero)" % dan.Facing)
	_check(dan.IsAtLeadTarget == false, "a leashed Dan reports IsAtLeadTarget")
	_check(arrivals.size() == arrivals_before, "Arrived fired while Dan was held by the leash")
	var leashed_x: float = dan.global_position.x
	player.global_position = HERO_RELEASE
	var released_at: int = await _wait_until(func(): return not dan.IsLeashed, WARP_CAP)
	_check(released_at >= 0, "Dan stayed on the leash %d frames after the hero came within %.0f px" % [WARP_CAP, LEASH_RESUME])
	walked = await _wait_until(func(): return arrivals.size() > arrivals_before, ARRIVE_CAP)
	_check(walked >= 0, "Dan did not reach %s after the leash released (he is at %s)" % [POINT_C, dan.global_position])
	_check(dan.global_position.x > leashed_x, "Dan did not move on after the leash released")
	dan.LeadMaxGap = 640.0
	dan.LeadResumeGap = 380.0

	# 5. HeroLagging: after CallAfterSeconds, every CallRepeatSeconds, MaxCallsPerStop times — and
	# never again at a point the hero has reached.
	dan.CallAfterSeconds = LAG_SECONDS
	dan.CallRepeatSeconds = LAG_SECONDS
	await _place(player, HERO_FAR)
	arrivals_before = arrivals.size()
	dan.LeadTo(POINT_B)   # from POINT_C: a fresh point, the hero 540 px behind it
	walked = await _wait_until(func(): return arrivals.size() > arrivals_before, SHORT_CAP)
	_check(walked >= 0, "Dan did not reach %s for the lag test (he is at %s)" % [POINT_B, dan.global_position])
	var lag_before: int = lagging.size()
	await _step(_frames_of(LAG_WAIT))
	_check(lagging.size() == lag_before + dan.MaxCallsPerStop,
		"HeroLagging fired %d times in %.1f s with the hero %.0f px away, expected MaxCallsPerStop %d" % [lagging.size() - lag_before, LAG_WAIT, HERO_FAR.distance_to(POINT_B), dan.MaxCallsPerStop])
	await _step(_frames_of(LAG_SECONDS * 2.0))
	_check(lagging.size() == lag_before + dan.MaxCallsPerStop, "HeroLagging kept firing past MaxCallsPerStop (%d in total)" % (lagging.size() - lag_before))
	arrivals_before = arrivals.size()
	dan.LeadTo(POINT_C)
	player.global_position = HERO_NEAR_C
	walked = await _wait_until(func(): return arrivals.size() > arrivals_before, SHORT_CAP)
	_check(walked >= 0, "Dan did not reach %s for the reached-then-lag test (he is at %s)" % [POINT_C, dan.global_position])
	await _step(OVERLAP_FRAMES)
	_check(reached.size() > reached_before + 2, "HeroReached did not fire with the hero waiting %.0f px from the point" % HERO_NEAR_C.distance_to(POINT_C))
	lag_before = lagging.size()
	await _place(player, HERO_FAR)
	await _step(_frames_of(LAG_WAIT))
	_check(lagging.size() == lag_before, "HeroLagging fired %d times after the hero had already reached this point — he nags" % (lagging.size() - lag_before))

	# 6. The warning stance: no calls, no look-back — he faces the way, not the hero; the next LeadTo clears it.
	dan.LookBackSeconds = LOOK_BACK
	await _place(player, HERO_FAR)
	await _pin(dan, WARN_DAN)
	arrivals_before = arrivals.size()
	dan.LeadTo(POINT_B)
	dan.SetWarning(true)
	_check(dan.IsWarning == true, "Companion.IsWarning=%s after SetWarning(true), expected true" % dan.IsWarning)
	_check(dan.TravelSign == 1, "TravelSign is %d for the warning test, expected 1" % dan.TravelSign)
	walked = await _wait_until(func(): return arrivals.size() > arrivals_before, SHORT_CAP)
	_check(walked >= 0, "Dan did not reach %s for the warning test (he is at %s)" % [POINT_B, dan.global_position])
	lag_before = lagging.size()
	await _step(_frames_of(LAG_WAIT))
	_check(lagging.size() == lag_before, "HeroLagging fired %d times while warning, expected none" % (lagging.size() - lag_before))
	_check(dan.Facing == dan.TravelSign, "a warning Dan faces %d after %.1f s, expected TravelSign %d (eyes on the danger, not on the hero)" % [dan.Facing, LAG_WAIT, dan.TravelSign])
	dan.LeadTo(POINT_C)
	_check(dan.IsWarning == false, "Companion.IsWarning=%s after the next LeadTo, expected false" % dan.IsWarning)
	await _pin(dan, WARN_DAN)
	arrivals_before = arrivals.size()
	dan.LeadTo(POINT_B)   # the same setup without the warning: he looks back at the hero
	walked = await _wait_until(func(): return arrivals.size() > arrivals_before, SHORT_CAP)
	await _step(_frames_of(LOOK_BACK) + 2)
	_check(dan.Facing == -1, "a Dan who is not warning faces %d after LookBackSeconds, expected -1 (looking back at the hero)" % dan.Facing)
	dan.LookBackSeconds = 1.5
	dan.CallAfterSeconds = 5.0
	dan.CallRepeatSeconds = 10.0

	# 7. RunTo: no leash, RunSpeed. The hero starts 500 px behind, so LeadTo would leash him at once.
	dan.LeadMaxGap = LEASH_MAX
	await _place(player, HERO_LEFT)
	await _pin(dan, POINT_A)
	dan.RunTo(POINT_C)
	_check(dan.IsLeading == true, "Companion.IsLeading=%s after RunTo, expected true" % dan.IsLeading)
	_check(dan.LeadLeashed == false, "Companion.LeadLeashed=%s after RunTo, expected false" % dan.LeadLeashed)
	_check(is_equal_approx(dan.LeadMoveSpeed, dan.RunSpeed), "Companion.LeadMoveSpeed is %s after RunTo, expected RunSpeed %s" % [dan.LeadMoveSpeed, dan.RunSpeed])
	var run_x0: float = dan.global_position.x
	var ever_leashed := false
	for i in RUN_FRAMES:
		await physics_frame
		if dan.IsLeashed:
			ever_leashed = true
	_check(not ever_leashed, "RunTo put Dan on the leash (LeadMaxGap %.0f) — a run has no leash" % LEASH_MAX)
	var run_expected: float = dan.RunSpeed * float(RUN_FRAMES) / float(Engine.physics_ticks_per_second)
	var run_dx: float = dan.global_position.x - run_x0
	_check(absf(run_dx - run_expected) <= run_expected * RUN_EPS,
		"RunTo covered %.1f px in %d frames, expected %.1f +/- %.0f %% (RunSpeed %.0f)" % [run_dx, RUN_FRAMES, run_expected, RUN_EPS * 100.0, dan.RunSpeed])
	dan.LeadMaxGap = 640.0

	# 8. Failsafe 2 aimed forward: wedged at the timber pile he is warped onto the route point on the
	# far side of it — never behind the hero.
	await _place(player, HERO_LEFT)
	await _pin(dan, WEDGE_POS)
	var warps_before: int = warps.size()
	dan.LeadTo(PAST_PILE)
	var stuck_at: int = await _wait_until(func(): return warps.size() > warps_before, STUCK_CAP)
	var expected_stuck: int = int(dan.StuckSeconds * float(Engine.physics_ticks_per_second))
	_check(stuck_at >= 0, "Dan wedged at the pile was never warped within %d frames (IsStuck=%s, at %s)" % [STUCK_CAP, dan.IsStuck, dan.global_position])
	if stuck_at >= 0:
		_check(stuck_at >= expected_stuck - STUCK_EARLY,
			"Dan was warped after %d frames, expected no earlier than %d (StuckSeconds %.1f s)" % [stuck_at, expected_stuck - STUCK_EARLY, dan.StuckSeconds])
		_check(stuck_at <= expected_stuck + STUCK_LATE,
			"Dan was warped after %d frames, expected within %d (StuckSeconds %.1f s + the walk to the pile)" % [stuck_at, expected_stuck + STUCK_LATE, dan.StuckSeconds])
		_check(dan.global_position.distance_to(PAST_PILE) <= dan.ArriveDistance,
			"after the stuck warp Dan is at %s, expected the route point %s (the far side of the pile)" % [dan.global_position, PAST_PILE])
		_check(dan.global_position.x > BLOCKER_RIGHT and dan.global_position.x > player.global_position.x,
			"the stuck warp put Dan at x %.0f — behind the pile (%.0f) or behind the hero (%.0f), never forward" % [dan.global_position.x, BLOCKER_RIGHT, player.global_position.x])

	# 9. Failsafe 1 aimed forward: a point past WarpDistance is taken at once; a hero past
	# WarpDistance ahead of him along the way puts him on the point at once.
	await _pin(dan, FAR_START)
	warps_before = warps.size()
	dan.LeadTo(POINT_B)
	var far_warp: int = await _wait_until(func(): return warps.size() > warps_before, WARP_CAP)
	_check(far_warp >= 0, "a route point %.0f px away (WarpDistance %.0f) was walked to instead of warped to" % [FAR_START.distance_to(POINT_B), dan.WarpDistance])
	_check(dan.global_position.distance_to(POINT_B) <= dan.ArriveDistance, "after the far-point warp Dan is at %s, expected %s" % [dan.global_position, POINT_B])
	await _place(player, HERO_START)
	await _pin(dan, DAN_START)
	dan.LeadTo(POINT_B)
	await _step(2)
	_check(dan.global_position.distance_to(POINT_B) > dan.ArriveDistance, "the overtake test starts with Dan already at the point")
	warps_before = warps.size()
	player.global_position = HERO_AHEAD
	var ahead_warp: int = await _wait_until(func(): return warps.size() > warps_before, WARP_CAP)
	_check(ahead_warp >= 0, "the hero %.0f px ahead of Dan (WarpDistance %.0f) did not warp him onto his point" % [HERO_AHEAD.x - DAN_START.x, dan.WarpDistance])
	_check(dan.global_position.distance_to(POINT_B) <= dan.ArriveDistance, "after the overtake warp Dan is at %s, expected the route point %s (never behind the hero)" % [dan.global_position, POINT_B])
	_check(cavein.IsTriggered == false, "the cave-in was triggered by the hero placed at %s — move HERO_AHEAD" % HERO_AHEAD)

	# 10. Failsafe 3 aimed forward: the level's relocation hook leaves a leading Dan on his point,
	# and puts him there (not behind the hero) when the hero is relocated half a level away.
	await _place(player, HERO_MID)
	warps_before = warps.size()
	var before_hook: Vector2 = dan.global_position
	room.ApplyRoomBounds(room.StartRoom)
	_check(warps.size() == warps_before, "ApplyRoomBounds warped a leading Dan although the hero is only %.0f px away" % HERO_MID.distance_to(POINT_B))
	_check(dan.global_position == before_hook, "ApplyRoomBounds moved a leading Dan from %s to %s with the hero nearby" % [before_hook, dan.global_position])
	_check(dan.IsLeading == true, "ApplyRoomBounds knocked Dan out of the Lead state")
	await _place(player, HERO_LEFT)
	room.ApplyRoomBounds(room.StartRoom)
	_check(warps.size() == warps_before + 1, "ApplyRoomBounds with the hero %.0f px away fired Warped %d times, expected 1" % [HERO_LEFT.distance_to(POINT_B), warps.size() - warps_before])
	_check(dan.global_position.distance_to(POINT_B) <= dan.ArriveDistance and dan.global_position.x > player.global_position.x,
		"after the relocation hook a leading Dan is at %s, expected his point %s (never behind the hero at %s)" % [dan.global_position, POINT_B, player.global_position])
	_check(dan.IsLeading == true and dan.IsAtLeadTarget == true, "after the relocation hook Dan is in '%s' (IsAtLeadTarget=%s), expected Lead at his point" % [dan.CurrentStateName, dan.IsAtLeadTarget])

	# 11. A leading Dan is still company, not a puzzle: no push, walked through, unseen by triggers.
	player.global_position = POINT_B   # standing exactly on top of him at his point
	await _step(2)
	var on_top: Vector2 = player.global_position
	await _step(ON_TOP_FRAMES)
	_check(player.global_position.is_equal_approx(on_top), "the hero standing on a leading Dan drifted from %s to %s — he must not push" % [on_top, player.global_position])
	await _lead_pin(dan, POINT_A)
	var free_walk: float = await _measure_walk(player, HERO_RIGHT)
	await _lead_pin(dan, LEAD_PATH)
	var through_walk: float = await _measure_walk(player, HERO_RIGHT)
	_check(absf(through_walk - free_walk) <= WALK_EPS,
		"the hero covered %.1f px walking into a leading Dan and %.1f px with the way clear, expected within %s px" % [through_walk, free_walk, WALK_EPS])
	await _lead_pin(dan, cp_start.global_position)
	_check(not cp_start.get_overlapping_bodies().has(dan), "Checkpoint_Start sees a leading Dan as a body")
	_check(cp_start.IsReached == false, "Checkpoint_Start was armed by a leading Dan standing on it")
	await _lead_pin(dan, cavein.global_position)
	_check(not cavein.get_overlapping_bodies().has(dan), "CaveIn_Mid sees a leading Dan as a body")
	_check(cavein.IsTriggered == false, "the cave-in was triggered by a leading Dan")
	await _lead_pin(dan, gas.global_position)
	_check(not gas.get_overlapping_bodies().has(dan), "GasZone_Rehearsal sees a leading Dan as a body")
	_check(gas.IsWarning == false, "the gas started counting down because of a leading Dan")

	# 12. Vanish: gone for good; a later LeadTo is ignored.
	await _lead_pin(dan, POINT_B)
	dan.Say("Go.")
	dan.Vanish()
	_check(dan.IsGone == true, "Companion.IsGone=%s after Vanish, expected true" % dan.IsGone)
	_check(dan.visible == false, "a vanished Dan is still visible")
	_check(dan.process_mode == Node.PROCESS_MODE_DISABLED, "a vanished Dan has process_mode %d, expected PROCESS_MODE_DISABLED" % dan.process_mode)
	_check(dan.velocity == Vector2.ZERO, "a vanished Dan has velocity %s" % dan.velocity)
	_check(dan.IsSpeaking == false, "a vanished Dan is still speaking")
	var gone_at: Vector2 = dan.global_position
	await _step(VANISH_FRAMES)
	_check(dan.global_position == gone_at, "a vanished Dan moved from %s to %s" % [gone_at, dan.global_position])
	dan.LeadTo(POINT_C)
	await _step(ON_TOP_FRAMES)
	_check(dan.global_position == gone_at, "LeadTo moved a vanished Dan to %s" % dan.global_position)
	_check(dan.LeadTarget == POINT_B, "LeadTo changed a vanished Dan's LeadTarget to %s" % dan.LeadTarget)
	room.queue_free()
	await process_frame

	# 13. The fixture's own route with DanLeads on: A on ready, B when the pump runs, C at the gas
	# checkpoint; LeadLine on every arrival, CallLine on a call.
	var room2: Node = scene.instantiate()
	room2.DanLeads = true
	root.add_child(room2)
	await _settle()
	var dan2: Node = room2.get_node("Companion")
	var player2: Node = room2.get_node("Player")
	var pump: Node = room2.get_node("Pump")
	var cp_start2: Node = room2.get_node("Checkpoints/Checkpoint_Start")
	var cp_gas2: Node = room2.get_node("Checkpoints/Checkpoint_Gas")
	var route2: Node = room2.get_node("DanRoute")
	var lines2: Array = []
	dan2.LineShown.connect(func(t: String): lines2.append(t))
	_check(dan2.CurrentStateName == "Lead", "with DanLeads on Dan starts in '%s', expected 'Lead'" % dan2.CurrentStateName)
	_check(dan2.LeadTarget == route2.get_node("WP_A").global_position, "with DanLeads on LeadTarget is %s, expected WP_A %s" % [dan2.LeadTarget, route2.get_node("WP_A").global_position])
	_check(room2.CurrentRouteKey == "A", "TestMine.CurrentRouteKey is '%s' on ready, expected 'A'" % room2.CurrentRouteKey)
	await _place(player2, cp_start2.global_position)
	_check(cp_start2.IsReached == true, "the hero placed on Checkpoint_Start did not arm it")
	_check(room2.CurrentRouteKey == "A", "Checkpoint_Start led Dan to '%s', expected him to stay on 'A' (never back, and A is where he is)" % room2.CurrentRouteKey)
	walked = await _wait_until(func(): return _count(lines2, room2.LeadLine) >= 1, ARRIVE_CAP)
	_check(walked >= 0, "Dan did not reach WP_A within %d frames (he is at %s, lines %s)" % [ARRIVE_CAP, dan2.global_position, lines2])
	_check(dan2.global_position.distance_to(route2.get_node("WP_A").global_position) <= dan2.ArriveDistance,
		"Dan showed LeadLine at %s, expected him at WP_A %s" % [dan2.global_position, route2.get_node("WP_A").global_position])
	room2.get_node("DebrisPile_Hand").Clear()   # what the hero does with two heavy hits: the way on is open
	pump.ForcePower()
	await _step(2)
	_check(room2.CurrentRouteKey == "B", "powering the pump led Dan to '%s', expected 'B'" % room2.CurrentRouteKey)
	_check(dan2.LeadTarget == route2.get_node("WP_B").global_position, "LeadTarget is %s after the pump, expected WP_B" % dan2.LeadTarget)
	await _place(player2, HERO_MID)
	walked = await _wait_until(func(): return _count(lines2, room2.LeadLine) >= 2, LONG_CAP)
	_check(walked >= 0, "Dan did not reach WP_B within %d frames (he is at %s, lines %s)" % [LONG_CAP, dan2.global_position, lines2])
	dan2.CallAfterSeconds = LAG_SECONDS
	await _place(player2, cp_gas2.global_position)
	_check(room2.CurrentRouteKey == "C", "Checkpoint_Gas led Dan to '%s', expected 'C'" % room2.CurrentRouteKey)
	_check(dan2.LeadTarget == route2.get_node("WP_C").global_position, "LeadTarget is %s after Checkpoint_Gas, expected WP_C" % dan2.LeadTarget)
	await _place(player2, HERO_MID)
	walked = await _wait_until(func(): return _count(lines2, room2.LeadLine) >= 3, SHORT_CAP)
	_check(walked >= 0, "Dan did not reach WP_C within %d frames (he is at %s, lines %s)" % [SHORT_CAP, dan2.global_position, lines2])
	_check(_count(lines2, room2.LeadLine) == 3, "LeadLine was shown %d times for three route points, expected 3" % _count(lines2, room2.LeadLine))
	walked = await _wait_until(func(): return lines2.has(room2.CallLine), _frames_of(LAG_WAIT))
	_check(walked >= 0, "Dan at WP_C never showed CallLine '%s' with the hero %.0f px behind (lines %s)" % [room2.CallLine, HERO_MID.distance_to(POINT_C), lines2])
	room2.LeadAtLeast("A")   # what an earlier checkpoint would ask for: never behind the hero's progress
	_check(room2.CurrentRouteKey == "C", "LeadAtLeast('A') sent Dan back to '%s' from 'C' — it must never go back" % room2.CurrentRouteKey)
	_check(dan2.LeadTarget == route2.get_node("WP_C").global_position, "LeadAtLeast('A') changed LeadTarget to %s, expected WP_C" % dan2.LeadTarget)
	room2.queue_free()
	_finish()
