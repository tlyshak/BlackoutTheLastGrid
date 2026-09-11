extends SceneTree
# Smoke: no cave-in in the prologue can seal the hero on the wrong side of the rubble it drops.
#
# The three falls (CaveIn_Blast, CaveIn_Upper, CaveIn_Final) each put a HeavyHitsToClear = 0 pile
# across the drift after CaveIn.Delay, and nothing in the level can ever open such a pile again.
# The trigger therefore has to sit far enough past the pile that the hero cannot walk back behind
# it during the delay — including the case where he turns round the instant the roof starts to go,
# which is exactly what a player does when rock starts falling on his head. A short margin strands
# the run with no exit but the main menu (review round 1, B1: CaveIn_Upper had 60 px and put the
# hero at x 7408, behind the seal, with the only powered machine beyond it).
#
# Every fall is driven the way a player meets it — walk right into the trigger, never teleport onto
# it — and then run in both directions:
#   * "stand": stop dead on the trigger and let the roof come down;
#   * "back" : hold move_left for the whole delay.
# In both passes the hero's body must end up completely clear of the pile's blocker. Each fall is
# one-shot, so the two passes each get their own level instance.
# Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/level_seals.gd

const NAME := "level_seals"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s).
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const PROLOGUE_PATH := "res://scenes/levels/Level00_Prologue.tscn"
const SETTLE_CAP := 20          # idle frames allowed for the post-load physics catch-up to end
const SETTLE_DELTA := 0.05      # process delta (s) below which the loop is back to normal pacing
const OVERLAP_FRAMES := 4       # physics frames for Area2D overlaps to refresh after a teleport
const CUTSCENE_CAP := 40        # Advance() calls allowed to play one cutscene out
const DELAY_MARGIN := 0.35      # extra real seconds on top of CaveIn.Delay
const APPROACH := 150.0         # px left of the trigger the walk into it starts
const TRIGGER_CAP := 120        # physics frames allowed for that walk to reach the trigger
const BAND_Y := 450.0           # centre of the 300..600 walk band, where every gate is cut
const HERO_HALF_W := 14.0       # Player's foot capsule: radius 7, height 28, rotated 90 degrees
# The margin every fall is authored with: trigger half-width (24) + hero half-width (14) + blocker
# half-width (28) + Player.MoveSpeed * Delay (220 * 0.35 = 77) still leaves ~63 px of clearance.
const MIN_MARGIN := 200.0
# Falls, in the order the level drops them: [level export, pile node, label].
const FALLS := [
	["BlastCollapse", "DebrisPile_BlastSeal", "CaveIn_Blast"],
	["UpperCollapse", "DebrisPile_UpperSeal", "CaveIn_Upper"],
	["FinalCollapse", "DebrisPile_Final", "CaveIn_Final"],
]

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

# Real-time wait that ignores Engine.time_scale and the pause (the cave-in's own delay timer).
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

func _wait_until(cond: Callable, cap: int) -> int:
	for i in cap:
		if cond.call():
			return i
		await physics_frame
	return -1

func _play_out(cutscene: Node, label: String) -> void:
	var guard := 0
	while cutscene.IsPlaying and guard < CUTSCENE_CAP:
		cutscene.Advance()
		guard += 1
		await _step(1)
	_check(not cutscene.IsPlaying, "%s: the cutscene never ended after %d advances" % [label, guard])
	await _step(3)

# Right edge of the pile's blocker in world X — the line the hero must stay on the open side of.
func _blocker_right(pile: Node) -> float:
	var box: Shape2D = pile.BlockerShape.shape
	var half := 0.0
	if box is RectangleShape2D:
		half = (box as RectangleShape2D).size.x * 0.5
	return pile.BlockerShape.global_position.x + half

# Walks the hero into `fall` from the left, then either stands still or runs back for the whole
# delay, and reports where the rubble left him.
func _run_fall(player: Node, fall: Node, pile: Node, label: String, back: bool) -> void:
	var pass_name: String = "back" if back else "stand"
	player.global_position = Vector2(fall.global_position.x - APPROACH, BAND_Y)
	await _step(2)
	Input.action_press("move_right")
	var frames: int = await _wait_until(func(): return fall.IsTriggered, TRIGGER_CAP)
	Input.action_release("move_right")
	if frames < 0:
		_check(false, "%s/%s: walking right from %.0f px away never tripped the trigger at x %.0f"
			% [label, pass_name, APPROACH, fall.global_position.x])
		_release_all()
		return
	var trigger_x: float = player.global_position.x
	if back:
		Input.action_press("move_left")
	await _real_wait(fall.Delay + DELAY_MARGIN)
	_release_all()
	await _step(2)
	_check(fall.HasCollapsed == true, "%s/%s: the roof never came down after Delay" % [label, pass_name])
	_check(pile.IsCleared == false, "%s/%s: the drift is still open after the collapse" % [label, pass_name])
	_check(player.IsKnockedOut == false, "%s/%s: the collapse killed the hero - a fall he cannot avoid must never be lethal" % [label, pass_name])
	var edge: float = _blocker_right(pile)
	var hero_left: float = player.global_position.x - HERO_HALF_W
	_check(hero_left > edge,
		"%s/%s: the hero tripped the trigger at x %.0f and the rubble left him at x %.0f - his left edge %.0f is behind the seal (blocker ends at x %.0f). The pile has HeavyHitsToClear = 0, so the run is locked with no exit but the main menu."
		% [label, pass_name, trigger_x, player.global_position.x, hero_left, edge])

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

func _run_pass(back: bool) -> void:
	var level: Node = await _build_level()
	if level == null:
		return
	var player: Node = level.get("Player")
	var cutscene: Node = level.get("Cutscene")
	if player == null or cutscene == null:
		_check(false, "the prologue lacks Player / Cutscene")
		level.queue_free()
		return

	# The intro freezes the hero; play it out so he can walk into the first fall himself.
	await _play_out(cutscene, "intro")

	for entry in FALLS:
		var fall: Node = level.get(entry[0])
		var pile: Node = level.get_node_or_null(entry[1])
		if fall == null or pile == null:
			_check(false, "the prologue lacks %s / %s" % [entry[0], entry[1]])
			continue
		# The last fall is armed by the level when the floodlight goes out; this script only
		# cares about the geometry, so it arms the trigger directly.
		if not fall.monitoring:
			fall.set_deferred("monitoring", true)
			await _step(OVERLAP_FRAMES)
		await _run_fall(player, fall, pile, entry[2], back)
		# The blast and the last fall each start a cutscene that freezes the hero; the next fall
		# needs him walking again.
		if cutscene.IsPlaying:
			await _play_out(cutscene, entry[2])

	level.queue_free()
	await _step(2)

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()
	for a in ["move_left", "move_right", "interact"]:
		_check(InputMap.has_action(a), "InputMap missing action '%s'" % a)

	# 1. The authored margin, before a single frame is simulated: the number a future node move
	#    would quietly break, checked where it is easy to read.
	var scene: PackedScene = load(PROLOGUE_PATH)
	if scene == null:
		_check(false, "%s failed to load" % PROLOGUE_PATH)
		_finish()
		return
	var probe: Node = scene.instantiate()
	root.add_child(probe)
	await _settle()
	for entry in FALLS:
		var fall: Node = probe.get(entry[0])
		var pile: Node = probe.get_node_or_null(entry[1])
		if fall == null or pile == null:
			_check(false, "the prologue lacks %s / %s" % [entry[0], entry[1]])
			continue
		var margin: float = fall.global_position.x - pile.global_position.x
		_check(margin >= MIN_MARGIN,
			"%s sits %.0f px past %s, expected at least %.0f - the hero covers %.0f px during Delay=%.2f and would end up behind the seal"
			% [entry[2], margin, entry[1], MIN_MARGIN, 220.0 * fall.Delay, fall.Delay])
	probe.queue_free()
	await _step(2)

	# 2. Standing on the trigger: the rubble lands behind him.
	await _run_pass(false)
	# 3. Running back the instant it starts: it still lands behind him.
	gs.ResetRun()
	await _run_pass(true)

	_finish()
