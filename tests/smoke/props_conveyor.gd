extends SceneTree
# Smoke: the belt line of the ventilation drift — the second painted room of Level00_Sections
# (T-V2-06 — the author's r2 concept of section 2: the green button blinks, the belt moves, the
# current arcs; a running belt is a gate the lever stops). Headless has no renderer, so this
# asserts the data, the motion and the mechanic:
#   * placement — every moving piece sits on the very pixels the painted room draws it at. The test
#     recomputes each one from the mockup coordinates through the room's own placement. One room is
#     one painted section, so the ventilation mockup is shown whole and unfilled: Backdrop_Drift
#     sits at level x 1280 with SectionX 0, WorldScale 1280/680 (a 680 px mockup is exactly the
#     1280 world px of the camera window at zoom 1.5) and the derived
#     OffsetY = 300 - 280 * WorldScale, ImportScale 3. Every number below is derived from those: the belt's
#     chevron tile over the drawn belt surface (mockup 202,307 … 430,356), the running/stopped
#     indicator crops at their crop origin, the lever's hinge on the switch node's origin, and the
#     sparks overlay of Backdrop_Drift on the live cable's discharge;
#   * the belt — the carried footprint is as wide as the drawn conveyor (mockup x 190…442) and spans the whole
#     walk band (300…600, RoomBounds), so a running belt cannot be walked around in depth; it is
#     enabled while the belt runs and disabled once it is stopped; the guide is in PassThrough, so
#     the gate is the hero's alone and nothing ever warps through it;
#   * motion — the chevrons advance every frame while the belt runs, wrap at one tile period (the
#     texture width, so the tiling never jumps) and stand still once it is stopped;
#   * indicators — the green crop is a blinking BackdropOverlay shown only while the belt runs, the
#     red crop is shown only once it is stopped;
#   * the lever — one interact stops the belt, turns the handle to OffRotationDegrees about its
#     hinge and swaps the indicators; the switch is one-way (it refuses a second use, so a hero who
#     respawns at a checkpoint past the belt can never be shut in) and its prompt says so;
#   * reach — the switch's area covers the whole walk band and runs out to the face of the gate, so
#     a hero stopped against the running belt still has the prompt (tests/smoke/props_interact.gd
#     presses `interact` there and checks CurrentInteractable, which is the end-to-end proof).
# Run: godot --headless --path . -s tests/smoke/props_conveyor.gd

const NAME := "props_conveyor"   # must equal the file basename
const MAX_FRAMES := 900
const LEVEL := "res://scenes/levels/Level00_Sections.tscn"
const ART := "res://assets/art/v2/backgrounds/level0_section2_ventilation_r2_"
const OVERLAY_SCRIPT := "res://scripts/levels/BackdropOverlay.cs"
# Backdrop_Drift's placement (scenes/levels/Backdrop_Drift.tscn and its node in the level):
# one room = one painted section, so the room is the mockup's own width and nothing is filled.
const ROOM_X := 1280.0            # the level x of Backgrounds/Backdrop_Drift = Room_Drift.Rect.x
const SECTION_X := 0.0            # the section starts at the room's left edge
const WORLD_SCALE := 1280.0 / 680.0    # 680 mockup px = 1280 world px = the window at zoom 1.5
const OFFSET_Y := 300.0 - 280.0 * WORLD_SCALE   # SectionBackdrop.OffsetY: mockup y 280 on the band's top
const IMPORT_SCALE := 3.0
const LAYER_SCALE := WORLD_SCALE / IMPORT_SCALE
# The drawn conveyor, in mockup px (level0_section2_ventilation_r2.svg).
const FRAME_FROM := 190.0         # the conveyor's outer shadow, left edge
const FRAME_TO := 442.0           # …and right edge
const BELT_FROM := Vector2(202, 307)   # the belt surface's top-left
const BELT_SIZE := Vector2(228, 49)
const TILE_SIZE := Vector2(22, 49)     # one chevron period
const LIGHTS_CROP := Vector2(116, 272)
const LEVER_CROP := Vector2(126, 284)
const LEVER_HINGE := Vector2(131.25, 306)
const SWITCH_FOOT := Vector2(131.25, 313.5)
const SPARKS_CROP := Vector2(190, 256)
const PLAYER_LAYER := 2            # project.godot 2d_physics/layer_2="Player": what the belt watches for
const HERO_SPEED := 220.0          # Player.MoveSpeed: the carry has to beat it
const CARRY_FRAMES := 90           # physics frames the hero is given to force his way across a running belt
const CROSS_FRAMES := 240          # frames to walk the stopped belt end to end (474 px at 220 px/s)
const BELT_WALK_Y := 450.0         # middle of the walk band, where the hero meets the belt
const ON_BELT_MARGIN := 40.0       # px past the face that prove he walks onto the belt instead of bumping a wall
const MAX_ONTO_BELT := 200.0       # px onto the belt he must never beat; free walking would make ~330 in CARRY_FRAMES
const BAND_TOP := 300.0
const BAND_BOTTOM := 600.0
const Z_FX := -19                 # just above the painted floor layer (-20)
const MOTION_BLINK := 1
const MOTION_FLICKER := 2
const EPS := 0.05
# Placements are compared with an absolute sub-pixel tolerance, not Vector2.is_equal_approx: a
# .tscn stores positions rounded to two decimals, and is_equal_approx is a *relative* epsilon
# (1e-5 * |value|) that is tighter than that rounding once the coordinates are level-space px.
const SCROLL_FRAMES := 20
const SETTLE_FRAMES := 4

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

func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

func _step(frames: int) -> void:
	for i in frames:
		await physics_frame

func _approx(a: float, b: float, eps: float = EPS) -> bool:
	return absf(a - b) <= eps

# Same, for a placement: both axes within EPS world px of the point the painting draws at.
func _at(got: Vector2, want: Vector2, eps: float = EPS) -> bool:
	return absf(got.x - want.x) <= eps and absf(got.y - want.y) <= eps

# World point of a mockup point of the drift room's section.
func _world(mockup: Vector2) -> Vector2:
	return Vector2(ROOM_X + SECTION_X + mockup.x * WORLD_SCALE, OFFSET_Y + mockup.y * WORLD_SCALE)

func _run() -> void:
	var packed: PackedScene = load(LEVEL)
	_check(packed != null, "%s did not load" % LEVEL)
	if packed == null:
		_finish()
		return
	var level: Node = packed.instantiate()
	root.add_child(level)
	current_scene = level
	await _step(SETTLE_FRAMES)

	var line: Node2D = level.get_node_or_null("ConveyorLine")
	var sw: Node2D = level.get_node_or_null("ConveyorSwitch")
	var player: Node = level.get_node_or_null("Player")
	_check(line != null, "ConveyorLine is missing from the level")
	_check(sw != null, "ConveyorSwitch is missing from the level")
	_check(player != null, "Player is missing from the level")
	if line == null or sw == null or player == null:
		level.queue_free()
		_finish()
		return

	# 1. The gate: as wide as the drawn conveyor, as deep as the walk band, on the drawn belt.
	var shape: CollisionShape2D = line.BlockerShape
	_check(shape != null and shape.shape is RectangleShape2D, "ConveyorLine has no rectangular blocker")
	if shape != null and shape.shape is RectangleShape2D:
		var box: RectangleShape2D = shape.shape
		var left: float = shape.global_position.x - box.size.x * 0.5
		var right: float = shape.global_position.x + box.size.x * 0.5
		var top: float = shape.global_position.y - box.size.y * 0.5
		var bottom: float = shape.global_position.y + box.size.y * 0.5
		_check(_approx(left, _world(Vector2(FRAME_FROM, 0)).x) and _approx(right, _world(Vector2(FRAME_TO, 0)).x),
			"the belt gate spans x %.2f…%.2f, expected the drawn conveyor %.2f…%.2f" % [left, right, _world(Vector2(FRAME_FROM, 0)).x, _world(Vector2(FRAME_TO, 0)).x])
		_check(top <= BAND_TOP and bottom >= BAND_BOTTOM,
			"the belt gate blocks Y %.0f…%.0f, expected the whole walk band %.0f…%.0f — a running belt could be walked around" % [top, bottom, BAND_TOP, BAND_BOTTOM])
		_check(line.collision_layer == 0 and line.collision_mask == PLAYER_LAYER,
			"ConveyorLine is on layer %d mask %d, expected layer 0 mask %d (Player) — it carries the hero, it does not block him" % [line.collision_layer, line.collision_mask, PLAYER_LAYER])
		_check(line.CarrySpeed > HERO_SPEED,
			"the belt carries at %.0f px/s but the hero walks at %.0f — he would simply walk across a running belt and the lever would mean nothing" % [line.CarrySpeed, HERO_SPEED])
		_check(not shape.disabled, "the belt gate is disabled while the belt still runs")
	var companion: Node = level.get("Companion")
	_check(line.PassThrough.size() == 1 and companion != null and line.PassThrough[0] == companion,
		"ConveyorLine.PassThrough is %s, expected the guide alone: his route runs in front of the drawn belt, and a gate that stops him makes CompanionLead warp him through it" % [line.PassThrough])

	# 2. The moving belt: the chevron tile over the drawn belt surface.
	var belt: Sprite2D = line.Belt
	_check(belt != null, "ConveyorLine has no Belt sprite")
	if belt != null:
		var want: Vector2 = _world(BELT_FROM)
		_check(_at(belt.global_position, want), "Belt at %s, expected the drawn belt's top-left %s" % [belt.global_position, want])
		_check(not belt.centered and belt.region_enabled, "Belt: expected centered=false, region_enabled=true")
		_check(belt.texture_repeat == CanvasItem.TEXTURE_REPEAT_ENABLED, "Belt.texture_repeat=%s, expected ENABLED — the one-period tile would not repeat" % belt.texture_repeat)
		_check(_approx(belt.scale.x, LAYER_SCALE, 0.001) and _approx(belt.scale.y, LAYER_SCALE, 0.001), "Belt scale=%s, expected %.4f" % [belt.scale, LAYER_SCALE])
		_check(belt.z_index == Z_FX, "Belt z_index=%d, expected %d (just above the painted floor)" % [belt.z_index, Z_FX])
		var tex_path: String = belt.texture.resource_path if belt.texture != null else ""
		_check(tex_path == ART + "belt_tile.svg", "Belt texture %s, expected %s" % [tex_path, ART + "belt_tile.svg"])
		if belt.texture != null:
			_check(belt.texture.get_size() == TILE_SIZE * IMPORT_SCALE, "the belt tile is %s, expected one chevron period %s" % [belt.texture.get_size(), TILE_SIZE * IMPORT_SCALE])
			_check(_approx(line.Period, TILE_SIZE.x * IMPORT_SCALE), "ConveyorLine.Period=%.2f, expected the tile width %.2f" % [line.Period, TILE_SIZE.x * IMPORT_SCALE])
		var drawn: Vector2 = belt.region_rect.size * belt.scale
		_check(_at(drawn, BELT_SIZE * WORLD_SCALE), "the belt region draws %s, expected the drawn belt surface %s" % [drawn, BELT_SIZE * WORLD_SCALE])

	# 3. Indicators: the green crop blinks while the belt runs, the red one is hidden.
	var green: Sprite2D = line.RunIndicators
	var red: Sprite2D = line.StopIndicators
	var lights_at: Vector2 = _world(LIGHTS_CROP)
	for entry in [["RunLights", green, ART + "run_green.svg"], ["StopLights", red, ART + "run_red.svg"]]:
		var node: Sprite2D = entry[1]
		_check(node != null, "ConveyorLine has no %s sprite" % entry[0])
		if node == null:
			continue
		_check(_at(node.global_position, lights_at), "%s at %s, expected the crop's world origin %s" % [entry[0], node.global_position, lights_at])
		_check(not node.centered and _approx(node.scale.x, LAYER_SCALE, 0.001), "%s: expected centered=false and scale %.4f" % [entry[0], LAYER_SCALE])
		_check(node.z_index == Z_FX, "%s z_index=%d, expected %d" % [entry[0], node.z_index, Z_FX])
		var path: String = node.texture.resource_path if node.texture != null else ""
		_check(path == entry[2], "%s texture %s, expected %s" % [entry[0], path, entry[2]])
	if green != null:
		var script: Script = green.get_script()
		_check(script != null and script.resource_path == OVERLAY_SCRIPT, "RunLights runs %s, expected %s (it must blink)" % [script.resource_path if script else null, OVERLAY_SCRIPT])
		_check(int(green.Motion) == MOTION_BLINK, "RunLights.Motion=%s, expected Blink (%d)" % [green.Motion, MOTION_BLINK])
		_check(not green.NeedsPower, "RunLights.NeedsPower is on — the belt's own indicator must not follow the room's lamp string")
		_check(_approx(green.BlinkAlpha(green.BlinkPeriod * green.BlinkOnFraction * 0.5), 1.0), "RunLights: BlinkAlpha inside the on phase is not 1")
		_check(_approx(green.BlinkAlpha(green.BlinkPeriod * (green.BlinkOnFraction + 1.0) * 0.5), green.BlinkOffAlpha), "RunLights: BlinkAlpha inside the off phase is not BlinkOffAlpha")
		_check(green.visible, "RunLights is hidden while the belt runs")
	if red != null:
		_check(not red.visible, "StopLights is shown while the belt still runs")

	# 4. The lever: its hinge on the switch's origin, upright while the belt runs.
	var lever: Sprite2D = sw.Lever
	_check(_at(sw.global_position, _world(SWITCH_FOOT)), "ConveyorSwitch at %s, expected the drawn post's foot %s" % [sw.global_position, _world(SWITCH_FOOT)])
	_check(sw.collision_layer == 32 and sw.collision_mask == 0 and not sw.monitoring,
		"ConveyorSwitch is layer %d mask %d monitoring %s, expected the Interactable contract (32 / 0 / false)" % [sw.collision_layer, sw.collision_mask, sw.monitoring])
	_check(lever != null, "ConveyorSwitch has no Lever sprite")
	if lever != null:
		_check(_at(lever.global_position, _world(LEVER_HINGE)), "Lever at %s, expected the drawn hinge %s" % [lever.global_position, _world(LEVER_HINGE)])
		var want_offset: Vector2 = (LEVER_CROP - LEVER_HINGE) * IMPORT_SCALE
		_check(lever.offset.is_equal_approx(want_offset), "Lever offset %s, expected (crop - hinge) * %d = %s — the handle would not turn about its hinge" % [lever.offset, IMPORT_SCALE, want_offset])
		_check(not lever.centered and _approx(lever.scale.x, LAYER_SCALE, 0.001), "Lever: expected centered=false and scale %.4f" % LAYER_SCALE)
		_check(_approx(lever.rotation_degrees, 0.0), "Lever is at %.1f° while the belt runs, expected 0" % lever.rotation_degrees)
	var reach: CollisionShape2D = sw.get_node_or_null("CollisionShape2D")
	_check(reach != null and reach.shape is RectangleShape2D, "ConveyorSwitch has no rectangular reach shape")
	if reach != null and reach.shape is RectangleShape2D:
		var rbox: RectangleShape2D = reach.shape
		var rtop: float = reach.global_position.y - rbox.size.y * 0.5
		var rbottom: float = reach.global_position.y + rbox.size.y * 0.5
		var rright: float = reach.global_position.x + rbox.size.x * 0.5
		_check(rtop <= BAND_TOP and rbottom >= BAND_BOTTOM,
			"the switch reaches Y %.0f…%.0f, expected the whole walk band %.0f…%.0f — a hero on the near edge would walk past the lever with no prompt" % [rtop, rbottom, BAND_TOP, BAND_BOTTOM])
		_check(rright >= _world(Vector2(FRAME_FROM, 0)).x,
			"the switch reaches x %.1f, short of the gate's face %.1f — a hero stopped against the running belt would be out of reach of the lever" % [rright, _world(Vector2(FRAME_FROM, 0)).x])

	# 5. The chevrons move while the belt runs and wrap at one period.
	if belt != null and line.Period > 0.0:
		var before: float = belt.region_rect.position.x
		await _step(SCROLL_FRAMES)
		var after: float = belt.region_rect.position.x
		_check(not _approx(before, after, 0.001), "the belt's chevrons did not move in %d frames (region x stayed %.3f)" % [SCROLL_FRAMES, before])
		_check(after >= 0.0 and after < line.Period, "the belt scrolled to region x %.2f, expected it wrapped inside one period 0…%.2f" % [after, line.Period])

	# 5b. The running belt: the hero gets onto it and it carries him back out. The author asked for
	#     exactly this instead of a wall — he wants to be able to step on, and to be thrown back.
	var foot: CollisionShape2D = line.BlockerShape
	if foot != null and foot.shape is RectangleShape2D and player != null:
		var fbox: RectangleShape2D = foot.shape
		var face: float = foot.global_position.x - fbox.size.x * 0.5
		var far_edge: float = foot.global_position.x + fbox.size.x * 0.5

		# He can step on: walking into the belt from the drift, his x passes the face.
		player.global_position = Vector2(face - 40.0, BELT_WALK_Y)
		await _step(2)
		Input.action_press("move_right")
		var reached: float = player.global_position.x
		for i in CARRY_FRAMES:
			await physics_frame
			reached = maxf(reached, player.global_position.x)
		Input.action_release("move_right")
		await _step(2)
		_check(reached > face + ON_BELT_MARGIN,
			"the hero only reached x %.1f against a belt face at %.1f — he cannot get onto the belt at all, and the author asked to be able to" % [reached, face])

		# And it takes him back: he bobs on the near stretch of the belt and never gets near where the
		# same walk on open floor would have put him (CARRY_FRAMES at the hero's speed is ~330 px).
		_check(reached < face + MAX_ONTO_BELT,
			"walking into the running belt the hero reached %.1f px onto it; the band must sweep him back inside %.0f px or the lever means nothing" % [reached - face, MAX_ONTO_BELT])

		player.global_position = Vector2(foot.global_position.x, BELT_WALK_Y)
		await _step(2)
		var from_middle: float = player.global_position.x
		Input.action_press("move_right")
		var crossed := false
		for i in CARRY_FRAMES:
			await physics_frame
			crossed = crossed or player.global_position.x > far_edge
		Input.action_release("move_right")
		await _step(2)
		_check(player.global_position.x < from_middle,
			"standing on the running belt and walking right, the hero went from x %.1f to %.1f — the belt must beat his own speed or the lever means nothing" % [from_middle, player.global_position.x])
		_check(not crossed,
			"the hero forced his way off the far edge (x %.1f) of a running belt" % far_edge)

	# 6. The lever stops the belt: indicators swap, the handle turns, the gate opens, one-way after.
	var prompt_before: String = sw.CurrentPrompt
	_check(sw.CanInteract, "the lever refuses to be used while the belt runs")
	sw.Begin(player)
	await _step(SETTLE_FRAMES)
	_check(not line.Running, "the lever did not stop the belt")
	if shape != null:
		_check(shape.disabled, "the belt is stopped but its gate still blocks the band")
	if green != null:
		_check(not green.visible, "the green indicators are still shown with the belt stopped")
	if red != null:
		_check(red.visible, "the red indicators did not light when the belt stopped")
	if lever != null:
		_check(_approx(lever.rotation_degrees, sw.OffRotationDegrees, 0.01), "the handle is at %.1f°, expected OffRotationDegrees %.1f" % [lever.rotation_degrees, sw.OffRotationDegrees])
	if belt != null:
		var stopped: float = belt.region_rect.position.x
		await _step(SCROLL_FRAMES)
		_check(_approx(belt.region_rect.position.x, stopped, 0.001), "the chevrons kept moving after the belt was stopped")
	_check(not sw.CanInteract, "the lever can be thrown again — a hero respawning past the belt could be shut in")
	_check(sw.CurrentPrompt != prompt_before and sw.CurrentPrompt == sw.StoppedPromptText,
		"the prompt is '%s' after the belt stopped, expected StoppedPromptText '%s'" % [sw.CurrentPrompt, sw.StoppedPromptText])

	# 6b. Stopped, the belt is just floor: the hero walks the whole way across it.
	if foot != null and foot.shape is RectangleShape2D and player != null:
		# The guard stands a perception range past the belt and would wake mid-walk; this test is
		# about the floor, not about him.
		var guard: Node = level.get_node_or_null("Guard")
		if guard != null:
			guard.queue_free()
			await _step(1)
		var fbox2: RectangleShape2D = foot.shape
		var face2: float = foot.global_position.x - fbox2.size.x * 0.5
		var far_edge2: float = foot.global_position.x + fbox2.size.x * 0.5
		player.global_position = Vector2(face2 - 40.0, BELT_WALK_Y)
		await _step(2)
		Input.action_press("move_right")
		for i in CROSS_FRAMES:
			await physics_frame
			if player.global_position.x > far_edge2:
				break
		Input.action_release("move_right")
		await _step(2)
		_check(player.global_position.x > far_edge2,
			"with the belt stopped the hero only got to x %.1f in %d frames, short of the far edge %.1f — the way through is still shut" % [player.global_position.x, CROSS_FRAMES, far_edge2])

	# 7. The sparks of the live cable: a flickering overlay of the painted room, on its own crop.
	var sparks: Sprite2D = level.get_node_or_null("Backgrounds/Backdrop_Drift/Sparks")
	_check(sparks != null, "Backgrounds/Backdrop_Drift/Sparks is missing")
	if sparks != null:
		_check(_at(sparks.global_position, _world(SPARKS_CROP)), "Sparks at %s, expected the crop's world origin %s" % [sparks.global_position, _world(SPARKS_CROP)])
		_check(int(sparks.Motion) == MOTION_FLICKER, "Sparks.Motion=%s, expected Flicker (%d)" % [sparks.Motion, MOTION_FLICKER])
		_check(not sparks.NeedsPower, "Sparks.NeedsPower is on — a torn live cable does not stop arcing with the lamp string")
		var lo := 2.0
		var hi := -1.0
		for i in 120:
			var a: float = sparks.FlickerAlpha(i * 0.031)
			lo = minf(lo, a)
			hi = maxf(hi, a)
		_check(hi - lo >= 0.2, "Sparks: FlickerAlpha only ranges %.2f…%.2f — the discharge would look steady" % [lo, hi])

	level.queue_free()
	await _step(1)
	_finish()
