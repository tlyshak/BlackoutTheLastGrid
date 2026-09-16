extends SceneTree
# Smoke: Dan, the escort companion — Companion.tscn's contract and export defaults, and the
# behaviour that makes him company instead of a puzzle, driven on the one surviving level,
# Level00_Sections: he is on collision_layer 0 / mask 1, so the hero walks straight through him and
# no Checkpoint (which masks the Player layer) ever sees him; his Follow state closes a 340 px gap
# and then stands still playing `idle`; the three anti-stuck failsafes work — a warp when the follow
# point is past WarpDistance, a warp after StuckSeconds of "wants to walk, is not moving" (wedged
# behind the level's left wall) and the explicit relocation hook a level calls on a room change;
# HoldAt walks him to a scripted spot, emits Arrived once and keeps him there while the hero leaves,
# and Resume() puts him back on the hero; the failsafes cover the Wait state too — a hold is a world
# position, so the level's relocation hook leaves a holding Dan on his spot (T-07s-e: it no longer
# drags the hold behind the hero) and a hold past WarpDistance is a teleport; Say() shows a line for
# BubbleSeconds, a HUD prompt suppresses the bubble without losing the line, and a paused tree
# freezes the countdown. His art is the painted AnimatedSprite2D under Visual/Sprite (the procedural
# rig is gone), and Companion._Ready copies the headlamp's render bit onto it. Of the Lead state
# (the guide, T-07s-e) only the scene contract is checked here — the Lead node, the export
# defaults, PH_DanLight and the render bit his body and bubble carry. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/actors_companion.gd
#
# Nothing is hit here, so Engine.time_scale stays 1 and movement is counted in physics frames; the
# only real-time waits are the bubble countdown (Companion._Process, idle delta) and the pause
# check, both taken with ignore-time-scale timers.

const NAME := "actors_companion"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout. Counts _process calls.
const MAX_FRAMES := 12000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const LEVEL_PATH := "res://scenes/levels/Level00_Sections.tscn"
const SETTLE_CAP := 10         # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05     # process delta (s) below which the loop is back to normal pacing
const WORLD_LAYER := 1         # physics layer 1 "World"
const OVERLAP_FRAMES := 4      # physics frames for Area2D overlaps to refresh after a teleport
const ARRIVE_CAP := 200        # physics frames allowed to walk to a held position
const CATCH_UP_FRAMES := 120   # frames given to close the starting gap (340 px at 300 px/s = 68)
# Room_Face runs x 0..1280 with the floor band y 300..600; the only blockers are WallLeft
# (x -2..38) and, far away in the drift, the conveyor (x 1638..2112) and the guard (x 2400).
const HERO_RIGHT := Vector2(1100, 450)   # clear stretch: no blocker, and no trigger Dan could reach
const DAN_BEHIND := Vector2(704, 460)    # 340 px behind the hero's follow point (1044)
const HOLD_PATH := Vector2(1150, 450)    # a held spot right in the hero's path, short of Checkpoint_Drift (x 1258..1338)
const WALK_FRAMES := 20        # frames of move_right measured for the walk-through comparison
const WALK_EPS := 2.0          # px the two walks may differ by
const STILL_FRAMES := 10       # frames the hero stands on top of Dan without moving
const WARP_FROM := Vector2(100, 460)     # > WarpDistance (900) from the hero's follow point at HERO_RIGHT
const HERO_LEFT := Vector2(300, 450)     # hero for the stuck test; his follow point is at x 244
const WEDGE_POS := Vector2(-30, 460)     # behind WallLeft (x -2..38, y 250..650): no way around
const STUCK_CAP := 400         # frames the stuck watchdog is given before the test gives up
const STUCK_EARLY := 6         # frames of slack below StuckSeconds (frame alignment)
const STUCK_LATE := 90         # frames of slack above StuckSeconds (the walk before he wedges)
const HOLD_FAR := Vector2(1500, 460)     # a scripted beat in the second section (> WarpDistance from HOLD_NEAR)
const WAIT_WARP_CAP := 10      # physics frames the Wait state's warp failsafe is given
const HOLD_NEAR := Vector2(380, 460)     # a held spot in the clear stretch of the first section
const HOLD_KEEP_FRAMES := 40   # frames the hero is away while Dan must stay on the held spot
const HERO_AWAY := Vector2(600, 450)     # where the hero goes while Dan holds
const BUBBLE_SECONDS := 0.3    # BubbleSeconds shortened so the countdown is cheap to observe
const BUBBLE_WAIT := 0.5       # real seconds > BUBBLE_SECONDS
const LINE := "Stay close."
const EXPECTED_STATES := ["Follow", "Wait", "Lead"]
const LAMP_BIT := 2            # render bit only Dan's body and bubble carry: what PH_DanLight lights
const RELOCATE_NEAR := Vector2(300, 450)   # hero relocated within WarpDistance of a holding Dan (80 px)

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
	# The guide's exports (T-07s-e); every escort default above is unchanged.
	_check(is_equal_approx(proto.LeadSpeed, 240.0), "Companion.LeadSpeed default is %s, expected 240 (just over the hero's 220)" % proto.LeadSpeed)
	_check(is_equal_approx(proto.RunSpeed, 300.0), "Companion.RunSpeed default is %s, expected 300 (his catch-up speed)" % proto.RunSpeed)
	_check(is_equal_approx(proto.LeadMaxGap, 640.0), "Companion.LeadMaxGap default is %s, expected 640 (a third of a screen)" % proto.LeadMaxGap)
	_check(is_equal_approx(proto.LeadResumeGap, 380.0), "Companion.LeadResumeGap default is %s, expected 380" % proto.LeadResumeGap)
	_check(is_equal_approx(proto.HeroCloseDistance, 160.0), "Companion.HeroCloseDistance default is %s, expected 160" % proto.HeroCloseDistance)
	_check(is_equal_approx(proto.LookBackSeconds, 1.5), "Companion.LookBackSeconds default is %s, expected 1.5" % proto.LookBackSeconds)
	_check(is_equal_approx(proto.CallAfterSeconds, 5.0), "Companion.CallAfterSeconds default is %s, expected 5" % proto.CallAfterSeconds)
	_check(is_equal_approx(proto.CallRepeatSeconds, 10.0), "Companion.CallRepeatSeconds default is %s, expected 10" % proto.CallRepeatSeconds)
	_check(proto.MaxCallsPerStop == 2, "Companion.MaxCallsPerStop default is %s, expected 2 (the anti-nag cap)" % proto.MaxCallsPerStop)
	_check(is_equal_approx(proto.OvertakeDistance, 120.0), "Companion.OvertakeDistance default is %s, expected 120" % proto.OvertakeDistance)
	_check(proto.IsGone == false, "Companion.IsGone is %s on a fresh instance, expected false" % proto.IsGone)
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
	# The painted art: an AnimatedSprite2D with frames, and nothing left of the deleted rig.
	var psprite: Node = proto.get_node_or_null("Visual/Sprite")
	_check(psprite is AnimatedSprite2D and psprite.sprite_frames != null,
		"Companion.tscn has no Visual/Sprite AnimatedSprite2D with SpriteFrames — Dan would draw nothing")
	if psprite is AnimatedSprite2D:
		_check(proto.get("Sprite") == psprite, "Companion.Sprite export does not point at Visual/Sprite")
	_check(proto.get_node_or_null("Visual/Rig") == null, "Companion.tscn still has a Visual/Rig (CharacterRig was deleted)")
	# His own headlamp (T-07s-e): a light that reaches only the items carrying LAMP_BIT — his body
	# and his bubble — so he reads in the dark a third of a screen ahead without lighting the floor.
	var plamp: Node = proto.get_node_or_null("Visual/PH_DanLight")
	_check(plamp is PointLight2D, "Companion.tscn has no Visual/PH_DanLight PointLight2D (Dan's headlamp)")
	if plamp is PointLight2D:
		_check(proto.get("Lamp") == plamp, "Companion.Lamp export does not point at PH_DanLight")
		_check(plamp.enabled == true, "PH_DanLight ships switched off; Dan's lamp is on by default")
		_check(plamp.range_item_cull_mask == LAMP_BIT, "PH_DanLight range_item_cull_mask=%d, expected %d (it must light only Dan and his bubble)" % [plamp.range_item_cull_mask, LAMP_BIT])
		_check(plamp.shadow_enabled == false, "PH_DanLight casts shadows — the cheapest light in any level must not")
		_check(plamp.texture != null, "PH_DanLight has no texture, so it lights nothing")
		_check(plamp.energy > 0.0, "PH_DanLight energy is %s, expected positive" % plamp.energy)
	var pvisual: Node = proto.get_node_or_null("Visual")
	_check(pvisual is Node2D and (pvisual.light_mask & LAMP_BIT) != 0, "Companion Visual light_mask lacks bit %d: his body is not lit by his own lamp" % LAMP_BIT)
	_check(pvisual is Node2D and (pvisual.light_mask & 1) != 0, "Companion Visual light_mask lacks bit 1: the hero's lamp no longer lights him")
	_check(pbubble is Label and (pbubble.light_mask & LAMP_BIT) != 0, "Companion Bubble light_mask lacks bit %d: his line is unreadable in the dark" % LAMP_BIT)
	var pshadow: Node = proto.get_node_or_null("PH_Shadow")
	_check(pshadow is Polygon2D and pshadow.light_mask == 1, "PH_Shadow light_mask is not 1 — the lamp must not light his shadow")
	proto.free()
	if _failures.size() > 0:
		_finish()
		return

	# 2. Level00_Sections: Dan wired to the hero and following from the first frame.
	var scene: PackedScene = load(LEVEL_PATH)
	_check(scene != null, "%s failed to load" % LEVEL_PATH)
	if scene == null:
		_finish()
		return
	var room: Node = scene.instantiate()
	root.add_child(room)
	await _settle()

	var dan: Node = room.get_node_or_null("Dan")
	var player: Node = room.get_node_or_null("Player")
	var cp: Node = room.get_node_or_null("Checkpoints/Checkpoint_Drift")   # still armed: the hero spawns on Checkpoint_Face and never reaches this one here
	for pair in [[dan, "Dan"], [player, "Player"], [cp, "Checkpoints/Checkpoint_Drift"]]:
		_check(pair[0] != null, "Level00_Sections has no '%s' child" % pair[1])
	if dan == null or player == null or cp == null:
		room.queue_free()
		_finish()
		return
	if dan.get("FollowDistance") == null or cp.get("Label") == null:
		_check(false, "Companion/Checkpoint exports missing in Level00_Sections — aborting")
		room.queue_free()
		_finish()
		return
	_check(dan.Target == player, "Level00_Sections' Companion.Target is %s, expected the Player" % dan.Target)
	_check(dan.HasTarget == true, "Companion.HasTarget=%s in Level00_Sections, expected true" % dan.HasTarget)
	_check(room.get("Companion") == dan, "Level00_Sections (LevelBase).Companion export does not point at Dan")
	_check(dan.CurrentStateName == "Follow", "Companion starts in '%s', expected 'Follow'" % dan.CurrentStateName)
	_check(dan.IsWaiting == false, "Companion.IsWaiting=%s at start, expected false" % dan.IsWaiting)
	_check(dan.IsLeading == false, "Companion.IsLeading=%s at start, expected false" % dan.IsLeading)
	_check(dan.IsLampOn == true, "Companion.IsLampOn=%s at start, expected true" % dan.IsLampOn)
	# Godot does not inherit light_mask, so Companion copies Visual's mask onto the drawn children.
	var dsprite: Node = dan.get_node_or_null("Visual/Sprite")
	_check(dsprite is CanvasItem and (dsprite.light_mask & LAMP_BIT) != 0,
		"Visual/Sprite light_mask lacks bit %d after ready — the lamp's render bit did not reach the painted sprite" % LAMP_BIT)
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
	cp.Reached.connect(func(c): reached.append(c))
	await _pin(dan, cp.global_position)
	_check(not cp.get_overlapping_bodies().has(dan), "Checkpoint_Drift sees Dan as a body — he is on the wrong collision layer")
	_check(cp.IsReached == false, "Checkpoint_Drift was armed by Dan standing on it")
	_check(reached.is_empty(), "Checkpoint.Reached fired %d times for Dan" % reached.size())

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

	# 8. The bubble: shown for BubbleSeconds, hidden by a HUD prompt, frozen by the pause.
	var bubble: Label = dan.Bubble
	_check(bubble != null, "Companion.Bubble export is null in Level00_Sections")
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

	# 9. Failsafe 3 — the level's relocation hook on a room change (a door hop, a respawn). A
	# follower has no place of his own, so it warps him behind the hero, as it always did.
	await _place(player, HERO_RIGHT)
	dan.WarpTo(WARP_FROM)
	warps_before = warps.size()
	room.ApplyRoomBounds(room.StartRoom)
	_check(warps.size() > warps_before, "ApplyRoomBounds did not warp the following companion along with the hero")
	_check(dan.CurrentStateName == "Follow", "the room change knocked Dan out of '%s' into '%s'" % ["Follow", dan.CurrentStateName])
	_check(dan.global_position.distance_to(dan.FollowPoint) <= dan.FollowDistance,
		"after the room change Dan is %.0f px from his follow point" % dan.global_position.distance_to(dan.FollowPoint))

	# 10. The same failsafes while he holds a scripted spot — rewritten for T-07s-e. A hold is a
	# world position: the level's relocation hook leaves a holding Dan on his spot whether the hero
	# came back near him or half a level away (before T-07s-e it dragged the hold behind the hero,
	# which would have marched the guide back to the hero he is supposed to lead); a level that
	# wants him elsewhere after a respawn re-issues HoldAt. And a hold farther away than
	# WarpDistance is still taken at once.
	await _place(player, RELOCATE_NEAR)
	await _pin(dan, HOLD_NEAR)
	_check(dan.IsWaiting == true, "Companion.IsWaiting=%s after HoldAt, expected true" % dan.IsWaiting)
	warps_before = warps.size()
	room.ApplyRoomBounds(room.StartRoom)   # the hero came back at a checkpoint 80 px from the beat
	_check(warps.size() == warps_before, "ApplyRoomBounds warped a holding Dan although the hero is only %.0f px away" % dan.global_position.distance_to(player.global_position))
	_check(dan.global_position.distance_to(HOLD_NEAR) <= dan.ArriveDistance,
		"the relocation hook moved a holding Dan %.0f px off his spot with the hero nearby" % dan.global_position.distance_to(HOLD_NEAR))
	await _place(player, HERO_RIGHT)   # the hero died and came back at a checkpoint far from the beat
	room.ApplyRoomBounds(room.StartRoom)
	_check(dan.IsWaiting == true, "the level's relocation hook knocked Dan out of the Wait state")
	_check(dan.HoldPosition == HOLD_NEAR, "HoldPosition moved to %s on the hero's relocation, expected it to stay %s (a hold is a world position)" % [dan.HoldPosition, HOLD_NEAR])
	await _step(HOLD_KEEP_FRAMES)
	_check(dan.global_position.distance_to(HOLD_NEAR) <= dan.ArriveDistance,
		"Dan left his hold after the hero's relocation: he is %.0f px from %s (the hold must not follow the hero)"
		% [dan.global_position.distance_to(HOLD_NEAR), HOLD_NEAR])
	# Failsafe 1 in the Wait state: a hold half the level away is a teleport, not a march.
	await _place(player, HERO_LEFT)
	warps_before = warps.size()
	dan.HoldAt(HOLD_FAR)
	var hold_warp: int = await _wait_until(func(): return warps.size() > warps_before, WAIT_WARP_CAP)
	_check(hold_warp >= 0, "a hold %.0f px away (WarpDistance %.0f) was walked to instead of warped to"
		% [HOLD_FAR.distance_to(HOLD_NEAR), dan.WarpDistance])
	_check(dan.global_position.distance_to(HOLD_FAR) <= dan.ArriveDistance,
		"after the hold warp Dan is %.1f px from the held spot" % dan.global_position.distance_to(HOLD_FAR))
	dan.Resume()

	room.queue_free()
	_finish()
