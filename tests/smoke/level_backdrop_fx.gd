extends SceneTree
# Smoke: the animated pieces of the revised first room (2026-09-16 — the author's r2 concept of
# section 1: the alarm blinks, the work lamp flickers, the fan turns). Headless has no renderer,
# so this asserts the data and the motion:
#   * Backdrop_Face.tscn carries four BackdropOverlay children on the r2 crops
#     (assets/art/v2/backgrounds/level0_section1_mineface_r2_{alarm,worklamp_wall,worklamp_floor,fan_blades}.svg)
#     at the brief's depths: wall pieces just above the wall layer (-39), the floor glow just above
#     the floor layer (-19);
#   * placement — SectionBackdrop puts every crop on its mockup pixels: node at the world point of
#     Pivot (offset and scale derived from WorldScale = 1280/680), texture offset CropOrigin -
#     Pivot in texture px, layer scale WorldScale/3; the fan's pivot is the hub, so its texture
#     offset is minus half the texture — the blades
#     turn about their centre;
#   * motion — the fan's rotation grows frame after frame at TurnsPerSecond; the alarm's schedule is
#     the pure BlinkAlpha (on for BlinkOnFraction of BlinkPeriod, else BlinkOffAlpha); the lamp's
#     FlickerAlpha is deterministic in (Seed, time), stays inside [DropoutAlpha, 1], varies, and the
#     wall and floor glows (one seed) show the same alpha on the same frame;
#   * power — SectionBackdrop.Powered false darkens the lamp (UnpoweredAlpha), leaves the alarm
#     blinking (NeedsPower false) and spins the fan down; true brings it back;
#   * in Level00_Sections both painted rooms are instanced powered and follow no lamp string
#     (PowerFrom unset — there is no blast in this build), and switching one room's Powered off
#     still darkens that room's work lamp through the level's own instance.
# Run: godot --headless --path . -s tests/smoke/level_backdrop_fx.gd

const NAME := "level_backdrop_fx"   # must equal the file basename
const MAX_FRAMES := 600
const FACE := "res://scenes/levels/Backdrop_Face.tscn"
const LEVEL := "res://scenes/levels/Level00_Sections.tscn"
const OVERLAY_SCRIPT := "res://scripts/levels/BackdropOverlay.cs"
const ART := "res://assets/art/v2/backgrounds/level0_section1_mineface_r2_"
# One painted section is exactly one room and one camera window at zoom 1.5 (T-V2-07), so the
# world scale is 1280/680 rather than a pasted number; everything else falls out of it.
const WORLD_SCALE := 1280.0 / 680.0
const IMPORT_SCALE := 3.0
const OFFSET_Y := 300.0 - 280.0 * WORLD_SCALE   # the drawn floor edge on the walk band top
const Z_WALL_FX := -39             # just above the wall layer (-40)
const Z_FLOOR_FX := -19            # just above the floor layer (-20)
const MOTION_BLINK := 1
const MOTION_FLICKER := 2
const MOTION_SPIN := 3
const EPS := 0.01
# name: [texture suffix, crop origin, pivot, z, motion]
const PIECES := {
	"Alarm": ["alarm", Vector2(0, 154), Vector2(0, 154), Z_WALL_FX, MOTION_BLINK],
	"WorkLampWall": ["worklamp_wall", Vector2(0, 92), Vector2(0, 92), Z_WALL_FX, MOTION_FLICKER],
	"WorkLampFloor": ["worklamp_floor", Vector2(30, 296), Vector2(30, 296), Z_FLOOR_FX, MOTION_FLICKER],
	"FanBlades": ["fan_blades", Vector2(296, 106), Vector2(330, 140), Z_WALL_FX, MOTION_SPIN],
}
const SPIN_FRAMES := 12
const POWER_FRAMES := 6
const FLICKER_SAMPLES := 200
const FLICKER_SAMPLE_STEP := 0.037

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

func _approx(a: float, b: float, eps: float = EPS) -> bool:
	return absf(a - b) <= eps

func _world(mockup: Vector2) -> Vector2:
	return Vector2(mockup.x * WORLD_SCALE, OFFSET_Y + mockup.y * WORLD_SCALE)

func _run() -> void:
	var packed: PackedScene = load(FACE)
	_check(packed != null, "%s did not load" % FACE)
	if packed == null:
		_finish()
		return
	var bd: Node2D = packed.instantiate()
	root.add_child(bd)
	await process_frame

	# 1. The four pieces: script, texture, depth, motion, placement.
	var pieces := {}
	for name in PIECES:
		var spec: Array = PIECES[name]
		var node: Sprite2D = bd.get_node_or_null(name)
		_check(node != null, "Backdrop_Face/%s is missing" % name)
		if node == null:
			continue
		pieces[name] = node
		var script: Script = node.get_script()
		_check(script != null and script.resource_path == OVERLAY_SCRIPT, "%s: script %s, expected %s" % [name, script.resource_path if script else null, OVERLAY_SCRIPT])
		var tex_path: String = node.texture.resource_path if node.texture != null else ""
		_check(tex_path == ART + spec[0] + ".svg", "%s: texture %s, expected %s" % [name, tex_path, ART + spec[0] + ".svg"])
		_check(node.z_index == spec[3], "%s: z_index %d, expected %d" % [name, node.z_index, spec[3]])
		_check(int(node.Motion) == spec[4], "%s: Motion %s, expected %d" % [name, node.Motion, spec[4]])
		_check(not node.centered, "%s: centered, expected the crop anchored by its offset" % name)
		var want_pos: Vector2 = _world(spec[2])
		_check(node.position.distance_to(want_pos) <= EPS, "%s: at %s, expected the world point of pivot %s = %s" % [name, node.position, spec[2], want_pos])
		var want_offset: Vector2 = (spec[1] - spec[2]) * IMPORT_SCALE
		_check(node.offset.is_equal_approx(want_offset), "%s: offset %s, expected (CropOrigin - Pivot) * %d = %s" % [name, node.offset, IMPORT_SCALE, want_offset])
		var s: float = WORLD_SCALE / IMPORT_SCALE
		_check(_approx(node.scale.x, s, 0.001) and _approx(node.scale.y, s, 0.001), "%s: scale %s, expected %.4f" % [name, node.scale, s])
	var fan: Sprite2D = pieces.get("FanBlades")
	if fan != null and fan.texture != null:
		var half: Vector2 = -Vector2(fan.texture.get_size()) / 2.0
		_check(fan.offset.is_equal_approx(half), "FanBlades: offset %s is not minus half the texture %s — the blades would not turn about the hub" % [fan.offset, fan.texture.get_size()])

	# 2. Motion.
	if fan != null:
		var r0: float = fan.rotation
		var last: float = r0
		var monotonic := true
		for i in SPIN_FRAMES:
			await process_frame
			if fposmod(fan.rotation - last, TAU) <= 0.0 or fposmod(fan.rotation - last, TAU) > PI:
				monotonic = false
			last = fan.rotation
		_check(monotonic and last != r0, "FanBlades: rotation %.3f → %.3f over %d frames, expected it to grow (mod TAU) every frame" % [r0, last, SPIN_FRAMES])
		_check(_approx(fan.SpinRate, fan.TurnsPerSecond, 0.0001), "FanBlades: SpinRate %.3f, expected TurnsPerSecond %.3f while powered" % [fan.SpinRate, fan.TurnsPerSecond])
	var alarm: Sprite2D = pieces.get("Alarm")
	if alarm != null:
		var period: float = alarm.BlinkPeriod
		var on_frac: float = alarm.BlinkOnFraction
		_check(_approx(alarm.BlinkAlpha(period * on_frac * 0.5), 1.0), "Alarm: BlinkAlpha inside the on phase is not 1")
		_check(_approx(alarm.BlinkAlpha(period * (on_frac + 1.0) * 0.5), alarm.BlinkOffAlpha), "Alarm: BlinkAlpha inside the off phase is not BlinkOffAlpha %.2f" % alarm.BlinkOffAlpha)
		_check(_approx(alarm.BlinkAlpha(period * 3.0 + period * on_frac * 0.5), 1.0), "Alarm: BlinkAlpha does not repeat every BlinkPeriod")
		var live: float = alarm.self_modulate.a
		_check(_approx(live, 1.0) or _approx(live, alarm.BlinkOffAlpha), "Alarm: live alpha %.2f is neither on (1) nor off (%.2f)" % [live, alarm.BlinkOffAlpha])
	var wall: Sprite2D = pieces.get("WorkLampWall")
	var glow: Sprite2D = pieces.get("WorkLampFloor")
	if wall != null and glow != null:
		_check(wall.Seed == glow.Seed, "WorkLampWall/WorkLampFloor: seeds %d/%d differ — the two glows of one lamp would flicker apart" % [wall.Seed, glow.Seed])
		var lo := 2.0
		var hi := -1.0
		var same := true
		for i in FLICKER_SAMPLES:
			var t: float = i * FLICKER_SAMPLE_STEP
			var a: float = wall.FlickerAlpha(t)
			lo = minf(lo, a)
			hi = maxf(hi, a)
			if not _approx(a, glow.FlickerAlpha(t), 0.0001):
				same = false
		_check(same, "WorkLampWall/WorkLampFloor: FlickerAlpha differs for the same time and seed")
		_check(lo >= wall.DropoutAlpha - 0.0001 and hi <= 1.0 + 0.0001, "WorkLampWall: FlickerAlpha ranges %.2f…%.2f, expected inside [%.2f, 1]" % [lo, hi, wall.DropoutAlpha])
		_check(hi - lo >= wall.FlickerDepth * 0.5, "WorkLampWall: FlickerAlpha ranges only %.2f…%.2f over %d samples — no visible flicker" % [lo, hi, FLICKER_SAMPLES])
		_check(_approx(wall.self_modulate.a, glow.self_modulate.a, 0.0001), "WorkLampWall/WorkLampFloor: live alphas %.3f/%.3f differ on the same frame" % [wall.self_modulate.a, glow.self_modulate.a])
		_check(wall.self_modulate.a > 0.0, "WorkLampWall: dark while powered")

	# 3. Power: the blast darkens the lamp, spins the fan down and leaves the alarm on its battery.
	bd.Powered = false
	for i in POWER_FRAMES:
		await process_frame
	if wall != null and glow != null:
		_check(_approx(wall.self_modulate.a, wall.UnpoweredAlpha) and _approx(glow.self_modulate.a, glow.UnpoweredAlpha),
			"work lamp alphas %.2f/%.2f after the blackout, expected UnpoweredAlpha %.2f" % [wall.self_modulate.a, glow.self_modulate.a, wall.UnpoweredAlpha])
	if alarm != null:
		_check(not alarm.NeedsPower, "Alarm: NeedsPower is true — the beacon would die with the station instead of blinking on its battery")
		var live: float = alarm.self_modulate.a
		_check(_approx(live, 1.0) or _approx(live, alarm.BlinkOffAlpha), "Alarm: alpha %.2f after the blackout, expected it still blinking" % live)
	if fan != null:
		_check(fan.SpinRate < fan.TurnsPerSecond and fan.SpinRate > 0.0, "FanBlades: SpinRate %.3f %d frames after the blackout, expected between 0 and %.2f (spinning down)" % [fan.SpinRate, POWER_FRAMES, fan.TurnsPerSecond])
	bd.Powered = true
	await process_frame
	await process_frame
	if wall != null:
		_check(wall.self_modulate.a > 0.0, "WorkLampWall: still dark after the power came back")
	if fan != null:
		_check(_approx(fan.SpinRate, fan.TurnsPerSecond, 0.0001), "FanBlades: SpinRate %.3f after the power came back, expected %.2f" % [fan.SpinRate, fan.TurnsPerSecond])
	bd.queue_free()
	await process_frame

	# 4. In the level: both painted rooms are instanced, powered, and wired to no lamp string — this
	#    build has no blast, so each keeps the Powered it was authored with. Switching one room off
	#    by hand still reaches that room's overlays through the level's own instance.
	var level_packed: PackedScene = load(LEVEL)
	_check(level_packed != null, "%s did not load" % LEVEL)
	if level_packed != null:
		var level: Node = level_packed.instantiate()
		root.add_child(level)
		await process_frame
		for room in ["Backdrop_Face", "Backdrop_Drift"]:
			var bd_room: Node = level.get_node_or_null("Backgrounds/" + room)
			_check(bd_room != null, "Backgrounds/%s is missing from the level" % room)
			if bd_room == null:
				continue
			_check(bd_room.PowerFrom == null, "Backgrounds/%s: PowerFrom is %s, expected unset — there is no lamp string in this level" % [room, bd_room.PowerFrom])
			_check(bd_room.Powered, "Backgrounds/%s unpowered at the start" % room)
		var level_face: Node = level.get_node_or_null("Backgrounds/Backdrop_Face")
		var lamp_wall: Sprite2D = level.get_node_or_null("Backgrounds/Backdrop_Face/WorkLampWall")
		if level_face != null and lamp_wall != null:
			_check(lamp_wall.self_modulate.a > 0.0, "Backdrop_Face/WorkLampWall is dark in the level while the room is powered")
			level_face.Powered = false
			for i in POWER_FRAMES:
				await process_frame
			_check(_approx(lamp_wall.self_modulate.a, lamp_wall.UnpoweredAlpha), "Backdrop_Face/WorkLampWall alpha %.2f after the room was unpowered, expected UnpoweredAlpha %.2f" % [lamp_wall.self_modulate.a, lamp_wall.UnpoweredAlpha])
		else:
			_check(false, "Backgrounds/Backdrop_Face/WorkLampWall is missing from the level")
		level.queue_free()
		await process_frame

	_finish()
