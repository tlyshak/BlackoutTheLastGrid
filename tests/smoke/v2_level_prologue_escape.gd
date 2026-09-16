extends "res://tests/smoke/level_prologue_escape.gd"
# Smoke: the v2 prologue plays its second half exactly like v1 (T-V2-01, GAME_DESIGN §6a), only on
# a map whose mine rooms were compressed to one screen each (T-V2-07): _map_x() below carries every
# level x of level_prologue_escape.gd across, so the same steps land on the same props. Every step
# and assertion of level_prologue_escape.gd runs unchanged against
# scenes/v2/levels/Level00_Prologue.tscn: the timber, the gas pocket, the patrol room, the cage,
# the Held staging (HeldGuards shown — Sprite2Ds in v2), the surface and the exit into
# Level01_District. Only the scene path, the PASS-line name and the belt gate below differ.
# Run: godot --headless --path . -s tests/smoke/v2_level_prologue_escape.gd

const V2_NAME := "v2_level_prologue_escape"   # must equal the file basename
const V2_PROLOGUE_PATH := "res://scenes/v2/levels/Level00_Prologue.tscn"
const V2_LIMIT_TOP := -80   # the v2 mine rooms start 80 px above v1's (T-V2-05); the surface stays at 0
# T-V2-07 squeezed the three mine rooms from 2880 px to 1280 px each so that one room is exactly one
# painted section and one screenful at zoom 1.5 — the camera no longer scrolls inside a room. The
# surface room was already one section and keeps its width, so it is only shifted left.
const V2_MINE_OLD_W := 2880.0
const V2_MINE_NEW_W := 1280.0
const V2_MINE_K := V2_MINE_NEW_W / V2_MINE_OLD_W   # 4/9
const V2_MINE_ROOMS := 2.0                          # index of the last compressed room; past it the map is the surface
const V2_SURFACE_OLD_X := 8640.0
const V2_SURFACE_NEW_X := 3840.0
const BELT_LINE := "ConveyorLine"      # the v2 drift's belt gate (T-V2-06)
const BELT_SWITCH := "ConveyorSwitch"
# The belt is drawn on the painted ventilation room and is anchored to that art, so T-V2-07 did not
# compress it the way it compressed the rooms' contents: these four are px around the gate as it
# stands in the v2 map and are never passed through _map_x().
const BELT_APPROACH := 120.0           # px the hero starts left of the gate's face
const BELT_PROBE := 60.0               # px walked past it: enough to prove the wall, short of Checkpoint_GasNear (1866.67)
const BELT_PASS_MARGIN := 24.0         # px past the gate's face that counts as "walked onto the stopped belt"
const BELT_STOP_MARGIN := 8.0          # px short of the gate's face the hero must stop at (their own half-width is larger)
const SWITCH_FRAMES := 4

func _name() -> String:
	return V2_NAME

func _prologue_path() -> String:
	return V2_PROLOGUE_PATH

func _limit_top() -> int:
	return V2_LIMIT_TOP

# The v1 map squeezed into the v2 one: each mine room is scaled about its own left edge, so a point
# keeps the room it was in and its share of that room, and everything from the surface on is carried
# along by the total the three rooms lost.
func _map_x(x: float) -> float:
	if x >= V2_SURFACE_OLD_X:
		return V2_SURFACE_NEW_X + (x - V2_SURFACE_OLD_X)
	var room: float = minf(V2_MINE_ROOMS, floorf(x / V2_MINE_OLD_W))
	return room * V2_MINE_NEW_W + (x - room * V2_MINE_OLD_W) * V2_MINE_K

# The v2 mine is one screen per room, so the hero clearing the timber (1466.67) already stands
# inside Dan's HeroCloseDistance of his point at the belt (WP_gas_edge 1597.65, 131 px on): his
# «the hero came to me» fires here, at the pile, where v1's 780 px of drift let it wait for the gas
# itself. What decides that hand-over is the hero's lamp — lit, Dan holds at the edge and waits for
# it to go out; dark, he runs the pocket at once — and in play the hero comes down this drift lit,
# the mine having been black since the blast. So the lamp goes on with the level, not at the gas.
func _build_level() -> Node:
	var level: Node = await super()
	if level != null:
		level.get("Player").Flashlight.SetOn(true)
	return level

# The belt line the v2 drift gained with the author's r2 concept of section 2 (T-V2-06): between
# the timber and the gas the drawn conveyor blocks the whole band while it runs, and the lever
# beside it stops it for good. Played out here exactly as the hero has to: walk into the gate at
# both edges of the band, press `interact` on the lever that the gate leaves him standing next to,
# walk past. Dan must still be on the near side while the belt runs — his route point sits just
# short of the gate's face for exactly that (T-V2-06), and a point behind the gate makes
# CompanionLead warp him through it. Everything here is read off the gate itself rather than
# mapped, because the gate is anchored to the painted belt and did not move with T-V2-07; the walk
# is BELT_APPROACH + BELT_PROBE long, which from the gate's face (1637.65) cannot carry the hero
# past Checkpoint_GasNear (1866.67), so the shared script still drives the gas beat itself.
func _drift_extra(level: Node, player: Node) -> void:
	var line: Node2D = level.get_node_or_null(BELT_LINE)
	var sw: Node2D = level.get_node_or_null(BELT_SWITCH)
	_check(line != null and sw != null, "the v2 drift has no %s / %s" % [BELT_LINE, BELT_SWITCH])
	if line == null or sw == null:
		await _step(1)
		return
	var box: Shape2D = line.BlockerShape.shape
	if box is not RectangleShape2D:
		_check(false, "%s has no rectangular blocker" % BELT_LINE)
		await _step(1)
		return
	var left: float = line.BlockerShape.global_position.x - box.size.x * 0.5
	var top: float = line.BlockerShape.global_position.y - box.size.y * 0.5
	var bottom: float = line.BlockerShape.global_position.y + box.size.y * 0.5
	_check(top <= player.FloorTop and bottom >= player.FloorBottom,
		"the running belt blocks Y %.0f…%.0f, expected the whole walk band %.0f…%.0f" % [top, bottom, player.FloorTop, player.FloorBottom])
	_check(line.Running, "the belt is not running when the hero arrives at it")
	_check(line.PassThrough.size() == 1 and line.PassThrough[0] == level.get("Companion"),
		"ConveyorLine.PassThrough is %s, expected the guide — the gate is the hero's alone, and a body it stops gets warped through it" % [line.PassThrough])
	player.Flashlight.SetOn(true)   # the dark mine: the hero walks up to the gas edge lit, and Dan waits for the lamp to go out
	await _step(2)
	for depth in [player.FloorTop + BAND_MARGIN, player.FloorBottom - BAND_MARGIN]:
		var reached: float = await _walk(player, Vector2(left - BELT_APPROACH, depth), BELT_APPROACH + BELT_PROBE)
		_check(reached <= left - BELT_STOP_MARGIN,
			"walking right at Y %.0f the hero reached x %.0f, past the running belt at x %.0f — the gate can be bypassed in depth" % [depth, reached, left])
	_release_all()
	var dan: Node = level.get("Companion")
	_check(dan == null or dan.global_position.x <= left,
		"Dan is at x %.0f, past the running belt at x %.0f — the guide walked (or warped) through a closed gate" % [dan.global_position.x if dan else 0.0, left])
	_check(sw.CanInteract, "the lever refuses to be used while the belt runs")
	_check(player.CurrentInteractable == sw,
		"stopped against the running belt the hero's interactable is %s, expected the lever — the prompt must be there where the gate stops him" % player.CurrentInteractable)
	await _tap("interact")
	await _step(SWITCH_FRAMES)
	_check(not line.Running, "throwing the lever did not stop the belt")
	_check(line.StopIndicators != null and line.StopIndicators.visible, "the red indicator did not light when the belt stopped")
	_check(sw.Lever != null and absf(sw.Lever.rotation_degrees - sw.OffRotationDegrees) < 0.01,
		"the handle stayed at %.1f°, expected it thrown to %.1f°" % [sw.Lever.rotation_degrees if sw.Lever else 0.0, sw.OffRotationDegrees])
	for depth in [player.FloorTop + BAND_MARGIN, player.FloorBottom - BAND_MARGIN]:
		var open: float = await _walk(player, Vector2(left - BELT_APPROACH, depth), BELT_APPROACH + BELT_PROBE)
		_check(open >= left + BELT_PASS_MARGIN,
			"with the belt stopped the hero only reached x %.0f walking at Y %.0f, expected past x %.0f" % [open, depth, left + BELT_PASS_MARGIN])
	_release_all()
	await _step(1)
