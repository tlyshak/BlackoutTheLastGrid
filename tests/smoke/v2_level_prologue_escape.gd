extends "res://tests/smoke/level_prologue_escape.gd"
# Smoke: the v2 prologue plays its second half exactly like v1 (T-V2-01, GAME_DESIGN §6a). Every
# step and assertion of level_prologue_escape.gd runs unchanged against
# scenes/v2/levels/Level00_Prologue.tscn: the timber, the gas pocket, the patrol room, the cage,
# the Held staging (HeldGuards shown — Sprite2Ds in v2), the surface and the exit into
# Level01_District. Only the scene path and the PASS-line name differ.
# Run: godot --headless --path . -s tests/smoke/v2_level_prologue_escape.gd

const V2_NAME := "v2_level_prologue_escape"   # must equal the file basename
const V2_PROLOGUE_PATH := "res://scenes/v2/levels/Level00_Prologue.tscn"
const V2_LIMIT_TOP := -80   # the v2 mine rooms start 80 px above v1's (T-V2-05); the surface stays at 0
const BELT_LINE := "ConveyorLine"      # the v2 drift's belt gate (T-V2-06)
const BELT_SWITCH := "ConveyorSwitch"
const BELT_APPROACH := 120.0           # px the hero starts left of the gate's face
const BELT_PROBE := 60.0               # px walked past it: enough to prove the wall, short of Checkpoint_GasNear (4200)
const BELT_PASS_MARGIN := 24.0         # px past the gate's face that counts as "walked onto the stopped belt"
const BELT_STOP_MARGIN := 8.0          # px short of the gate's face the hero must stop at (their own half-width is larger)
const SWITCH_FRAMES := 4

func _name() -> String:
	return V2_NAME

func _prologue_path() -> String:
	return V2_PROLOGUE_PATH

func _limit_top() -> int:
	return V2_LIMIT_TOP

# The belt line the v2 drift gained with the author's r2 concept of section 2 (T-V2-06): between
# the timber and the gas the drawn conveyor blocks the whole band while it runs, and the lever
# beside it stops it for good. Played out here exactly as the hero has to: walk into the gate at
# both edges of the band, press `interact` on the lever that the gate leaves him standing next to,
# walk past. Dan must still be on the near side while the belt runs — his route point was moved to
# 4040 for exactly that (T-V2-06), and a point behind the gate makes CompanionLead warp him through
# it. The hero is left short of Checkpoint_GasNear (4200) so the shared script still drives the gas
# beat itself.
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
