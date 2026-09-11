extends SceneTree
# Smoke: Dan's patrol silence ends with the patrol, whatever the route (B2 of the v3 review,
# T-07s-e). Three instances of the prologue, each entering the lit drift the scripted way (the duck
# line at the entrance, then silence), each leaving it on a route that never brings the hero to Dan
# at WP_p3_out and never drops all three guards:
#   * spotted and ran — lit at x 6100, a guard notices, the hero runs on to Checkpoint_Cage;
#   * a partial fight — one guard down (its bank dropped), the hero runs on;
#   * a pass on the far side of Dan — the hero simply reaches Checkpoint_Cage unseen.
# On every route the cage lines must be *heard*: «That's the cage…» when the hero reaches Dan at
# WP_cage (on screen, no prompt over it) and «Won't take both.» on the refusal; «Never looked. Go.»
# is said exactly once on the unseen route and never on the seen one. Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/level_prologue_silence.gd

const NAME := "level_prologue_silence"   # must equal the file basename
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const PROLOGUE_PATH := "res://scenes/levels/Level00_Prologue.tscn"
const SETTLE_CAP := 20
const SETTLE_DELTA := 0.05
const OVERLAP_FRAMES := 4
const CUTSCENE_CAP := 40
const ATTEMPT_CAP := 80
const BUBBLE_CAP := 60
const DAN_CAP := 400
const NOTICE_CAP := 30
const DROP_CAP := 8
const STAGE_CAGE := 9
const ROUTES := ["spotted", "partial", "passed"]
# Positions.
const CP_PATROL := Vector2(5800, 450)
const FIGHT_SPOT := Vector2(6100, 450)
const CP_CAGE := Vector2(7700, 450)
const NEAR_CAGE := Vector2(8200, 450)      # within HeroCloseDistance of WP_cage (8180), out of the cage panel's reach
const NEAR_HOIST := Vector2(8370, 450)     # on the cage panel's reach, short of the boarding strip

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

func _play_out(cutscene: Node, label: String) -> void:
	var guard := 0
	while cutscene.IsPlaying and guard < CUTSCENE_CAP:
		cutscene.Advance()
		guard += 1
		await _step(1)
	_check(not cutscene.IsPlaying, "%s: the cutscene never ended after %d advances" % [label, guard])
	await _step(3)

func _use_panel(panel: Node, player: Node) -> void:
	panel.Begin(player)
	await _step(2)
	await _wait_until(func(): return not panel.IsActive, ATTEMPT_CAP)
	await _step(2)

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

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	for route in ROUTES:
		gs.ResetRun()
		var done: bool = await _route(route)
		if not done:
			_finish()
			return
	_finish()

# One route through the lit drift; returns false when the level could not be built.
func _route(route: String) -> bool:
	var gs: Node = root.get_node("GameState")
	var level: Node = await _build_level()
	if level == null:
		return false
	var player: Node = level.get("Player")
	var lamp: Node = player.get("Flashlight")
	var dan: Node = level.get("Companion")
	var patrol: Node = level.get("Patrol")
	var cage: Node = level.get("Cage")
	var hud: Node = level.get("Hud")
	var guards: Array = _guards_of(patrol)
	_check(guards.size() == 3, "%s: Patrol holds %d guards, expected 3" % [route, guards.size()])
	var lines: Array = []
	dan.LineShown.connect(func(t: String): lines.append(t))
	var noticed: Array = []
	for g in guards:
		g.Noticed.connect(func(): noticed.append(g.name))
	await _play_out(level.get("Cutscene"), route + ": intro")

	# Into the patrol the scripted way: the duck line at the entrance, then silence.
	gs.Energy = 0.0
	await _place(player, CP_PATROL)
	var ducked: int = await _wait_until(func(): return lines.has(level.DanDuckLine), DAN_CAP)
	_check(ducked >= 0, "%s: Dan did not say the duck line at the entrance (%s)" % [route, lines])
	var lines_in: int = lines.size()

	match route:
		"spotted":
			lamp.SetOn(true)
			await _place(player, FIGHT_SPOT)
			var seen: int = await _wait_until(func(): return noticed.size() > 0, NOTICE_CAP)
			_check(seen >= 0, "%s: no guard noticed a lit hero at x %.0f within %d frames" % [route, FIGHT_SPOT.x, NOTICE_CAP])
			lamp.SetOn(false)
		"partial":
			if guards.size() > 0:
				guards[0].TakeDamage(999.0, 0.0, true, 0)
				await _step(DROP_CAP)
				_check(guards[0].IsKnockedOut == true, "%s: %s is not knocked out" % [route, guards[0].name])
		"passed":
			_check(noticed.is_empty(), "%s: a guard noticed the hero at the entrance (%s)" % [route, noticed])
	_check(lines.size() == lines_in, "%s: Dan spoke inside the patrol (%s) — the silence holds until the patrol is behind him" % [route, lines.slice(lines_in)])

	# The guards are left behind (no chase into the cage segment); the hero runs on to the cage.
	patrol.process_mode = Node.PROCESS_MODE_DISABLED
	await _place(player, CP_CAGE)
	_check(level.CurrentStage == STAGE_CAGE, "%s: at Checkpoint_Cage the stage is %s, expected Cage" % [route, level.CurrentStage])
	_check(dan.LeadTarget == _wp(level, "cage"), "%s: at the cage checkpoint Dan's point is %s, expected WP_cage" % [route, dan.LeadTarget])
	if route == "passed":
		_check(lines.slice(lines_in) == [level.DanNeverLookedLine], "%s: leaving the patrol unseen without reaching WP_p3_out, Dan said %s, expected exactly the exit line" % [route, lines.slice(lines_in)])
	else:
		_check(not lines.has(level.DanNeverLookedLine), "%s: Dan said the exit line although the patrol looked (%s)" % [route, lines])

	# The cage lines are heard: the cage line on screen when the hero reaches him, the rule on the refusal.
	await _wait_until(func(): return dan.IsAtLeadTarget, DAN_CAP)
	await _place(player, NEAR_CAGE)
	var cage_said: int = await _wait_until(func(): return lines.has(level.DanCageLine), BUBBLE_CAP)
	_check(cage_said >= 0, "%s: Dan did not say the cage line when the hero reached him — his patrol silence outlived the patrol (%s)" % [route, lines])
	await _step(3)
	_check(hud.PromptText == "" and dan.Bubble.visible == true and dan.Bubble.text == level.DanCageLine,
		"%s: the cage line is not on screen (prompt '%s', bubble visible %s, text '%s')" % [route, hud.PromptText, dan.Bubble.visible, dan.Bubble.text])
	await _place(player, NEAR_HOIST)
	await _use_panel(cage, player)
	_check(cage.IsPowered == false, "%s: the cage started with the work lights on the bus" % route)
	_check(lines.has(level.DanRuleLine), "%s: Dan did not say the rule line on the refusal (%s)" % [route, lines])
	_check(lines.count(level.DanNeverLookedLine) <= 1, "%s: the exit line was said %d times" % [route, lines.count(level.DanNeverLookedLine)])
	print("level_prologue_silence: %s — lines after the entrance: %s" % [route, lines.slice(lines_in)])
	level.queue_free()
	await _step(2)
	return true
