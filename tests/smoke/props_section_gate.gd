extends SceneTree
# Smoke: the section gate (T-V3-04) — the author's rule, «як на 2 секції, так і на цій Go (перехід
# на наступну секцію), тільки якщо всі вороги переможені»: the way out of a section is shut until
# every enemy in it is down, and then the arcade "GO ▶" prompt says he may move on.
#
# The fixture is built here, in code — one Node2D with the hero, a few guards, three gates and a
# HUD — on purpose: Level00_Sections does not carry the prop yet, and a gate is worth testing
# against nothing but the walk band and a body that walks. Checks:
#   * the prop's contract: StaticBody2D on layer 1 (World) with mask 0, one RectangleShape2D, the
#     export defaults (BlockerDepth 300 = the whole mine walk band, no enemies, no indicator);
#   * a gate with enemies standing starts shut, its wall is as deep as BlockerDepth says, and the
#     hero driven right with `move_right` over physics frames is stopped at its face — the test of
#     the rule is that he physically cannot get past, not that a flag is set;
#   * knocking out one of two enemies changes nothing; knocking out the last one opens the gate,
#     emits Opened exactly once, and lets the hero walk through;
#   * an opened gate stays open — freeing the bodies afterwards neither re-closes it nor fires
#     Opened again (a checkpoint respawn must never take the crossing back);
#   * a gate with no enemies is open from the first frame;
#   * an enemy freed from the tree counts as beaten (a body that is gone can never be knocked out,
#     and a gate that waited for it would lock the player in);
#   * the GO indicator follows the gate: hidden while it is shut, shown and blinking once it opens,
#     and the HUD stops processing while it is hidden.
# Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/props_section_gate.gd

const NAME := "props_section_gate"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s). Counts _process calls;
# headless runs ~2-3 process frames per physics tick, and a green run uses ~450 ticks.
const MAX_FRAMES := 4000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]

const GATE_SCENE := "res://scenes/props/SectionGate.tscn"
const GATE_SCRIPT := "res://scripts/props/SectionGate.cs"
const GUARD_SCENE := "res://scenes/actors/Guard.tscn"
const PLAYER_SCENE := "res://scenes/actors/Player.tscn"
const HUD_SCENE := "res://scenes/ui/HUD.tscn"

const WORLD_LAYER := 1             # project.godot 2d_physics/layer_1="World"
const EXPECTED_DEPTH := 300.0      # the mine walk band, RoomBounds.FloorTop 300 … FloorBottom 600
const GATE_HALF_WIDTH := 20.0      # SectionGate.tscn: 40 px of wall along X
const HERO_HALF_WIDTH := 14.0      # Player.tscn's foot capsule, rotated: radius 7, height 28

const BAND_MIDDLE := 450.0         # the gate's origin sits at the middle of the band…
const HERO_Y := 470.0              # …the hero walks a little in front of it
const GATE_X := 900.0
const HERO_START_X := 700.0
const PAST_GATE_X := 980.0         # comfortably beyond the far face (920)
const OFF_BAND_Y := 3000.0         # where the two extra gates stand: nothing can bump into them
const GATE_B_X := 900.0            # the gate with no enemies
const GATE_C_X := 1400.0           # the gate whose only enemy is freed
const GUARD_A_X := 400.0           # the two enemies of the first gate stand well clear of the walk
const GUARD_B_X := 460.0
const GUARD_C_X := 1500.0

const KO_DAMAGE := 200.0           # far above Guard.MaxHp (30): one call floors any guard
const SETTLE := 3                  # physics frames for a deferred shape toggle / a teleport
const BLOCKED_FRAMES := 150        # frames of move_right at 220 px/s: 550 px, far past the gate
const RETRY_FRAMES := 40           # a shorter second push, after the first enemy is down
const CROSS_FRAMES := 200          # frames allowed to walk from HERO_START_X past PAST_GATE_X
const BLINK_FRAMES := 90           # idle frames to watch the GO blink (GoBlinkPeriod 0.7 s)

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

func _release_all() -> void:
	for a in ACTIONS:
		Input.action_release(a)

func _finish() -> void:
	_release_all()
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

# Drives the hero right for `frames` physics frames, stopping early once he is past `stop_x`.
# Returns his x when the push ended.
func _push_right(hero: Node2D, frames: int, stop_x: float) -> float:
	Input.action_press("move_right")
	for i in frames:
		await physics_frame
		if hero.global_position.x > stop_x:
			break
	Input.action_release("move_right")
	await _step(1)
	return hero.global_position.x

# Builds one gate: instances the scene, hands it its enemies and its indicator BEFORE it enters the
# tree (SectionGate subscribes in _Ready, the way a level's [Export]s reach it), then adds it.
func _make_gate(packed: PackedScene, parent: Node, at: Vector2, enemies: Array, indicator: Node) -> Node2D:
	var gate: Node2D = packed.instantiate()
	gate.position = at
	gate.Enemies = enemies
	if indicator != null:
		gate.GoIndicator = indicator
	parent.add_child(gate)
	return gate

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()
	_release_all()

	var gate_scene: PackedScene = load(GATE_SCENE)
	var guard_scene: PackedScene = load(GUARD_SCENE)
	var player_scene: PackedScene = load(PLAYER_SCENE)
	var hud_scene: PackedScene = load(HUD_SCENE)
	_check(gate_scene != null, "%s did not load" % GATE_SCENE)
	_check(guard_scene != null, "%s did not load" % GUARD_SCENE)
	_check(player_scene != null, "%s did not load" % PLAYER_SCENE)
	_check(hud_scene != null, "%s did not load" % HUD_SCENE)
	if gate_scene == null or guard_scene == null or player_scene == null or hud_scene == null:
		_finish()
		return

	# 1. The prop on its own: the scene contract and the export defaults.
	var proto: Node = gate_scene.instantiate()
	_check(proto is StaticBody2D, "%s root is a %s, expected StaticBody2D (it stops bodies, it does not watch for them)" % [GATE_SCENE, proto.get_class()])
	var script: Script = proto.get_script()
	_check(script != null and script.resource_path == GATE_SCRIPT,
		"%s runs %s, expected %s (did dotnet build run?)" % [GATE_SCENE, script.resource_path if script != null else null, GATE_SCRIPT])
	if script == null or proto.get("BlockerDepth") == null:
		_check(false, "SectionGate.cs is not attached to the scene — aborting")
		proto.free()
		_finish()
		return
	_check(proto.collision_layer == WORLD_LAYER and proto.collision_mask == 0,
		"the gate is layer %d mask %d, expected %d / 0 (World, looking for nothing)" % [proto.collision_layer, proto.collision_mask, WORLD_LAYER])
	var proto_shape: CollisionShape2D = proto.get_node_or_null("CollisionShape2D")
	_check(proto_shape != null and proto_shape.shape is RectangleShape2D, "the gate has no rectangular blocker")
	_check(proto.BlockerShape == proto_shape, "SectionGate.BlockerShape does not point at the scene's own CollisionShape2D")
	_check(is_equal_approx(proto.BlockerDepth, EXPECTED_DEPTH),
		"SectionGate.BlockerDepth default is %s, expected %s (the whole mine walk band)" % [proto.BlockerDepth, EXPECTED_DEPTH])
	_check(proto.Enemies.size() == 0, "SectionGate.Enemies default holds %d entries, expected none" % proto.Enemies.size())
	_check(proto.GoIndicator == null, "SectionGate.GoIndicator default is %s, expected null (optional)" % proto.GoIndicator)
	proto.free()

	# 2. The fixture: the hero, the enemies of the first gate, the gates and a HUD.
	var world := Node2D.new()
	world.name = "GateFixture"
	root.add_child(world)
	current_scene = world

	var hud: Node = hud_scene.instantiate()
	world.add_child(hud)
	if hud.get("Go") == null:
		_check(false, "HUD.Go is not wired — the GO prompt is missing from HUD.tscn, aborting")
		world.queue_free()
		_finish()
		return
	var go: Control = hud.Go
	_check(go is Control, "HUD.Go is a %s, expected a Control holding the word and the arrow" % go.get_class())
	_check(not go.visible, "the GO prompt is visible on a fresh HUD; it must stay hidden until a section is cleared")
	_check(hud.GoVisible == false, "HUD.GoVisible is %s on a fresh HUD, expected false" % hud.GoVisible)
	_check(not hud.is_processing(), "a HUD with the GO prompt hidden is still processing every frame")
	_check(is_equal_approx(hud.GoAlpha(0.0), 1.0), "HUD.GoAlpha(0) is %s, expected 1 (a prompt appears lit)" % hud.GoAlpha(0.0))
	_check(is_equal_approx(hud.GoAlpha(hud.GoBlinkPeriod * 0.99), hud.GoBlinkOffAlpha),
		"HUD.GoAlpha at the end of the cycle is %s, expected GoBlinkOffAlpha %s" % [hud.GoAlpha(hud.GoBlinkPeriod * 0.99), hud.GoBlinkOffAlpha])

	var hero: Node2D = player_scene.instantiate()
	hero.position = Vector2(HERO_START_X, HERO_Y)
	world.add_child(hero)

	var guard_a: Node2D = guard_scene.instantiate()
	guard_a.position = Vector2(GUARD_A_X, HERO_Y)
	world.add_child(guard_a)
	var guard_b: Node2D = guard_scene.instantiate()
	guard_b.position = Vector2(GUARD_B_X, HERO_Y)
	world.add_child(guard_b)
	var guard_c: Node2D = guard_scene.instantiate()
	guard_c.position = Vector2(GUARD_C_X, OFF_BAND_Y)
	world.add_child(guard_c)

	var gate: Node2D = _make_gate(gate_scene, world, Vector2(GATE_X, BAND_MIDDLE), [guard_a, guard_b], hud)
	var empty_gate: Node2D = _make_gate(gate_scene, world, Vector2(GATE_B_X, OFF_BAND_Y), [], null)
	var lone_gate: Node2D = _make_gate(gate_scene, world, Vector2(GATE_C_X, OFF_BAND_Y), [guard_c], null)

	var opened: Array = []
	var opened_lone: Array = []
	gate.Opened.connect(func(): opened.append(1))
	lone_gate.Opened.connect(func(): opened_lone.append(1))
	await _step(SETTLE)

	# 3. Shut while its enemies stand, and as deep as the band.
	var shape: CollisionShape2D = gate.BlockerShape
	_check(gate.IsOpen == false, "the gate is open with %d enemies standing" % gate.RemainingEnemies)
	_check(gate.RemainingEnemies == 2, "the gate counts %d enemies still standing, expected 2" % gate.RemainingEnemies)
	_check(not shape.disabled, "the gate's wall is disabled while its enemies are up")
	var box: RectangleShape2D = shape.shape
	_check(is_equal_approx(box.size.y, EXPECTED_DEPTH),
		"the gate's wall is %.1f px deep, expected BlockerDepth %.0f — a shallower one leaves a lane along the edge of the band" % [box.size.y, EXPECTED_DEPTH])
	_check(hud.GoVisible == false, "the GO prompt is up while the section still has enemies in it")

	# 4. The hero cannot walk past it. This is the rule, not the flag.
	var blocked_x: float = await _push_right(hero, BLOCKED_FRAMES, GATE_X + GATE_HALF_WIDTH)
	_check(blocked_x > HERO_START_X, "the hero did not move at all under move_right (x %.1f)" % blocked_x)
	_check(blocked_x < GATE_X - GATE_HALF_WIDTH,
		"the hero reached x %.1f, past the shut gate's face at %.1f — the section can be left with its enemies still up" % [blocked_x, GATE_X - GATE_HALF_WIDTH])
	_check(blocked_x > GATE_X - GATE_HALF_WIDTH - HERO_HALF_WIDTH - 2.0,
		"the hero stopped at x %.1f, well short of the gate's face — something other than the gate is in the way" % blocked_x)

	print("%s: shut gate at x %.0f stopped the hero at x %.1f (face %.1f)" % [NAME, GATE_X, blocked_x, GATE_X - GATE_HALF_WIDTH])

	# 5. One of two down changes nothing: the gate waits for the last of them.
	guard_a.TakeDamage(KO_DAMAGE, 0.0, false, 0)
	await _step(SETTLE)
	_check(guard_a.IsKnockedOut, "the first guard did not go down under %.0f damage" % KO_DAMAGE)
	_check(gate.IsOpen == false, "the gate opened with one of its two enemies still standing")
	_check(gate.RemainingEnemies == 1, "the gate counts %d enemies left after one knockout, expected 1" % gate.RemainingEnemies)
	_check(opened.is_empty(), "Opened fired %d time(s) with an enemy still up" % opened.size())
	_check(hud.GoVisible == false, "the GO prompt is up with one enemy still standing")
	var still_blocked_x: float = await _push_right(hero, RETRY_FRAMES, GATE_X + GATE_HALF_WIDTH)
	_check(still_blocked_x < GATE_X - GATE_HALF_WIDTH,
		"the hero got to x %.1f past the gate after only one of two knockouts" % still_blocked_x)

	# 6. The last one down opens it — once.
	guard_b.TakeDamage(KO_DAMAGE, 0.0, false, 0)
	await _step(SETTLE)
	_check(guard_b.IsKnockedOut, "the second guard did not go down under %.0f damage" % KO_DAMAGE)
	_check(gate.IsOpen, "the gate is still shut with both of its enemies knocked out")
	_check(gate.RemainingEnemies == 0, "the gate counts %d enemies left after both knockouts, expected 0" % gate.RemainingEnemies)
	_check(opened.size() == 1, "Opened fired %d time(s) on the last knockout, expected exactly one" % opened.size())
	_check(shape.disabled, "the gate's wall is still solid after it opened")
	_check(hud.GoVisible and go.visible, "the GO prompt did not come up when the section was cleared")
	_check(hud.is_processing(), "the HUD is not processing while the GO prompt blinks")

	# 7. …and now he walks through.
	hero.position = Vector2(HERO_START_X, HERO_Y)
	await _step(SETTLE)
	var crossed_x: float = await _push_right(hero, CROSS_FRAMES, PAST_GATE_X)
	_check(crossed_x > PAST_GATE_X,
		"the hero got to x %.1f in %d frames with the gate open, expected past %.0f" % [crossed_x, CROSS_FRAMES, PAST_GATE_X])

	print("%s: last knockout -> IsOpen %s, Opened x%d, wall disabled %s, GO up %s; the hero crossed to x %.1f" % [NAME, gate.IsOpen, opened.size(), shape.disabled, hud.GoVisible, crossed_x])

	# 8. An opened gate stays open: the bodies being cleared away must not re-close it or fire again.
	guard_a.queue_free()
	guard_b.queue_free()
	await _step(SETTLE)
	_check(gate.IsOpen, "the gate closed again after its knocked-out enemies were freed")
	_check(shape.disabled, "the gate's wall came back after its knocked-out enemies were freed")
	_check(opened.size() == 1, "Opened fired %d time(s) in total, expected exactly one" % opened.size())

	# 9. A section with nothing to fight never stops anybody.
	_check(empty_gate.IsOpen, "a gate with no enemies starts shut")
	_check(empty_gate.RemainingEnemies == 0, "a gate with no enemies counts %d of them" % empty_gate.RemainingEnemies)
	_check(empty_gate.BlockerShape.disabled, "a gate with no enemies still has its wall up")

	# 10. An enemy freed from the tree counts as beaten — it can never be knocked out again.
	_check(lone_gate.IsOpen == false, "the third gate is open with its only enemy standing")
	guard_c.queue_free()
	await _step(SETTLE)
	_check(lone_gate.IsOpen, "the gate stayed shut after its only enemy was freed from the tree — the way on would be locked for good")
	_check(opened_lone.size() == 1, "the third gate fired Opened %d time(s), expected exactly one" % opened_lone.size())

	# 11. The blink, and switching the prompt back off.
	var min_alpha: float = 1.0
	for i in BLINK_FRAMES:
		await process_frame
		min_alpha = minf(min_alpha, go.modulate.a)
	_check(min_alpha < 1.0 - 0.001,
		"the GO prompt held alpha %.3f over %d frames; it must blink" % [min_alpha, BLINK_FRAMES])
	_check(min_alpha >= hud.GoBlinkOffAlpha - 0.001,
		"the GO prompt dimmed to %.3f, below GoBlinkOffAlpha %s" % [min_alpha, hud.GoBlinkOffAlpha])
	print("%s: GO blink over %d idle frames dipped to alpha %.3f (GoBlinkOffAlpha %s, period %s s)" % [NAME, BLINK_FRAMES, min_alpha, hud.GoBlinkOffAlpha, hud.GoBlinkPeriod])
	hud.HideGo()
	await _step(1)
	_check(hud.GoVisible == false and not go.visible, "HUD.HideGo() left the prompt on screen")
	_check(not hud.is_processing(), "the HUD keeps processing after the GO prompt was hidden")

	world.queue_free()
	await _step(1)
	_finish()
