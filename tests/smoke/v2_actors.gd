extends SceneTree
# Smoke: the v2 actors on the shared scripts (T-V2-01 01b) — scenes/v2/actors/{Player,Guard,
# Companion}.tscn are the v1 scenes with only the Visual subtree and the animation data swapped:
# (1) parity with v1 — same script, identical [Export] values on the root (except Rig/Sprite) and
#     on every StateMachine child, identical Hurtbox/Hitbox/CollisionShape2D/sensor shapes,
#     positions, layers and masks, the same Visual position and light_mask, the same animation
#     names (plus `down` on the v2 guard) with the same lengths and loop modes, and the same
#     (time, method) pairs on every method track — HitboxOn/HitboxOff at 0.08/0.18, 0.08/0.18,
#     0.12/0.24, 0.22/0.36 for the hero and 0.30/0.40 for the guard, pinned as numbers too;
# (2) the v2 animation data — no Rig tracks, every animation carries a discrete
#     Visual/Sprite:animation track before a discrete Visual/Sprite:frame track, the frame key
#     times equal scenes/v2/actors/sprite_animations.json and the SpriteFrames animation has that
#     many frames (one source of truth), no v2 track keys Visual:rotation except RESET;
# (3) Rig == null breaks nothing: ResetPose / PlayAnimation on the v2 hero step the sprite through
#     light_1 at v1's times without the sprite ever playing itself; SetDown(true) on the v2 guard
#     shows the `down` animation and keeps Visual.rotation 0 while a v1 guard still rotates by
#     PI/2; Companion._Ready copies the headlamp render bit onto the sprite;
# (4) combat parity — the same scripted fight (hero light hit, heavy knockdown, an ignored hit
#     while Down, get-up, a hit taken by the hero) on a v1 pair and on a v2 pair produces the same
#     HP / energy / hit-stop / state numbers, and the numbers are v1's (an unaware guard:
#     30 -> 20 (5 x DarkFirstHitMultiplier) -> 8, hero energy 100 -> 92).
# Needs physics frames (section 4).
# Run: godot --headless --path . -s tests/smoke/v2_actors.gd
#
# Hit-stop sets Engine.time_scale = 0 (physics frames stall), so hits are observed on idle frames
# under a wall-clock cap and the restore is awaited in real time, as in combat_dummy.gd.

const NAME := "v2_actors"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s). Counts _process calls.
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "flashlight"]
const TABLE_PATH := "res://scenes/v2/actors/sprite_animations.json"
const PAIRS := {
	"Player": ["res://scenes/player/Player.tscn", "res://scenes/v2/actors/Player.tscn", "RayUnarmed"],
	"Guard": ["res://scenes/enemies/Guard.tscn", "res://scenes/v2/actors/Guard.tscn", "Guard"],
	"Companion": ["res://scenes/actors/Companion.tscn", "res://scenes/v2/actors/Companion.tscn", "Dan"],
}
# Node paths whose collision layers/masks and shapes must be byte-equal between v1 and v2.
const SHAPE_NODES := {
	"Player": ["Visual/Hurtbox", "Visual/Hurtbox/CollisionShape2D", "Visual/Hitbox", "Visual/Hitbox/CollisionShape2D", "CollisionShape2D", "LightSensor", "LightSensor/CollisionShape2D", "InteractionArea", "InteractionArea/CollisionShape2D"],
	"Guard": ["Visual/Hurtbox", "Visual/Hurtbox/CollisionShape2D", "Visual/Hitbox", "Visual/Hitbox/CollisionShape2D", "CollisionShape2D"],
	"Companion": ["CollisionShape2D"],
}
const EXTRA_V2_ANIMATIONS := {"Guard": ["down"]}
const EXCLUDED_EXPORTS := ["Rig", "Sprite"]
# Frozen method-track times (T-07i-b), pinned so the parity check cannot pass vacuously.
const HERO_HIT_WINDOWS := {"light_1": [0.08, 0.18], "light_2": [0.08, 0.18], "light_3": [0.12, 0.24], "heavy": [0.22, 0.36]}
const GUARD_HIT_WINDOW := [0.3, 0.4]
const HIT_CAP_MS := 800
const NO_HIT_WINDOW_MS := 450
const RESTORE_CAP_MS := 1000
const SETTLE_CAP := 10
const SETTLE_DELTA := 0.05
const AFTER_HIT_FRAMES := 30
const GETUP_CAP := 90          # frames allowed for Down -> up (DownDuration 1 s = 60)
const HURT_IDLE_CAP := 60      # frames allowed for the hero's Hurt -> Idle (0.30 s = 18)
const HERO_POS := Vector2(600, 450)
const GUARD_POS := Vector2(640, 450)
const HERO_HIT := [8.0, 60.0, false, 4]   # damage, knockback, knockdown, hit-stop frames of a guard punch
const IGNORED_HIT := [5.0, 60.0, false, 4]
const LIGHT_FRAME_TIME := 0.1            # light_1: attack_hit is keyed at 0.08 s
# Fight record fields that must be equal between v1 and v2 (everything except the visual pose).
const PARITY_FIELDS := ["hp_light", "hit_stop_light", "state_light", "state_after_light", "hero_after_light",
	"hp_heavy", "hit_stop_heavy", "state_heavy", "ignored", "hp_ignored", "up_after", "state_up",
	"energy_hurt", "hero_hurt_state", "hero_hurt_frames", "hero_after_hurt"]

var _started := false
var _frames := 0
var _failures: Array[String] = []
var _table: Dictionary = {}

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
	if Engine.time_scale != 1.0:
		_check(false, "Engine.time_scale=%s at the end, expected 1 (reset by the test)" % Engine.time_scale)
		Engine.time_scale = 1.0
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

func _real_wait(seconds: float) -> void:
	await create_timer(seconds, true, false, true).timeout

func _tap(action: String) -> void:
	Input.action_press(action)
	await _step(1)
	Input.action_release(action)

# Watches idle frames until `guard.Hp` drops or `cap_ms` of wall time pass.
func _watch_hit(guard: Node, cap_ms: int) -> Dictionary:
	var hp0: float = guard.Hp
	var r := {"hit": false, "min_scale": Engine.time_scale, "state": ""}
	var deadline: int = Time.get_ticks_msec() + cap_ms
	while Time.get_ticks_msec() < deadline:
		await process_frame
		r["min_scale"] = minf(r["min_scale"], Engine.time_scale)
		if guard.Hp < hp0:
			r["hit"] = true
			r["state"] = guard.CurrentStateName
			break
	return r

func _wait_restored(cap_ms: int) -> bool:
	var start: int = Time.get_ticks_msec()
	while Time.get_ticks_msec() - start < cap_ms:
		if Engine.time_scale == 1.0:
			return true
		await process_frame
	return false

func _read_json(path: String) -> Variant:
	if not FileAccess.file_exists(path):
		_check(false, "%s: file not found" % path)
		return null
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK:
		_check(false, "%s: JSON parse error: %s" % [path, json.get_error_message()])
		return null
	return json.data

# --- comparison helpers ---------------------------------------------------------------------

# A comparable form of an export value: nodes by their path from `owner`, resources by path.
func _comparable(owner: Node, value: Variant) -> Variant:
	if value is Node:
		return String(owner.get_path_to(value))
	if value is Resource:
		return (value as Resource).resource_path
	if value is Array:
		var out: Array = []
		for v in value:
			out.append(_comparable(owner, v))
		return out
	return value

func _values_equal(a: Variant, b: Variant) -> bool:
	if a is float and b is float:
		return is_equal_approx(a, b)
	return a == b

func _exports(node: Node) -> Array:
	var names: Array = []
	for p in node.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and p["usage"] & PROPERTY_USAGE_STORAGE:
			names.append(p["name"])
	return names

# Every [Export] of `v1` (except `excluded`) exists on `v2` with an equal value, and vice versa.
func _compare_exports(label: String, owner1: Node, v1: Node, owner2: Node, v2: Node, excluded: Array, require_any: bool) -> void:
	var names1: Array = _exports(v1)
	var names2: Array = _exports(v2)
	_check(names1.size() > 0 or not require_any, "%s: v1 has no exports (C# script attached? did dotnet build run?)" % label)
	for n in names2:
		_check(n in names1, "%s: v2 export '%s' is not on v1" % [label, n])
	for n in names1:
		if n in excluded:
			continue
		_check(n in names2, "%s: v1 export '%s' missing on v2" % [label, n])
		if not (n in names2):
			continue
		var a: Variant = _comparable(owner1, v1.get(n))
		var b: Variant = _comparable(owner2, v2.get(n))
		_check(_values_equal(a, b), "%s: export '%s' is %s on v2, expected v1's %s" % [label, n, b, a])

func _compare_shape_node(label: String, v1: Node, v2: Node) -> void:
	_check(v1.get_class() == v2.get_class(), "%s: type %s on v2, expected %s" % [label, v2.get_class(), v1.get_class()])
	if v1 is Node2D and v2 is Node2D:
		_check((v1 as Node2D).position == (v2 as Node2D).position, "%s: position %s on v2, expected %s" % [label, (v2 as Node2D).position, (v1 as Node2D).position])
		_check(is_equal_approx((v1 as Node2D).rotation, (v2 as Node2D).rotation), "%s: rotation %s on v2, expected %s" % [label, (v2 as Node2D).rotation, (v1 as Node2D).rotation])
	if v1 is CollisionObject2D and v2 is CollisionObject2D:
		for prop in ["collision_layer", "collision_mask", "monitoring", "monitorable"]:
			if prop in v1:
				_check(v1.get(prop) == v2.get(prop), "%s: %s=%s on v2, expected %s" % [label, prop, v2.get(prop), v1.get(prop)])
		var s1: Variant = v1.get_script()
		var s2: Variant = v2.get_script()
		_check((s1 == null) == (s2 == null) and (s1 == null or s1.resource_path == s2.resource_path), "%s: script differs between v1 and v2" % label)
	if v1 is CollisionShape2D and v2 is CollisionShape2D:
		var sh1: Shape2D = (v1 as CollisionShape2D).shape
		var sh2: Shape2D = (v2 as CollisionShape2D).shape
		_check(sh1 != null and sh2 != null, "%s: a shape is null (v1 %s, v2 %s)" % [label, sh1, sh2])
		if sh1 == null or sh2 == null:
			return
		_check(sh1.get_class() == sh2.get_class(), "%s: shape %s on v2, expected %s" % [label, sh2.get_class(), sh1.get_class()])
		for prop in ["size", "radius", "height"]:
			if prop in sh1:
				_check(_values_equal(sh1.get(prop), sh2.get(prop)), "%s: shape %s=%s on v2, expected %s" % [label, prop, sh2.get(prop), sh1.get(prop)])

# Sorted "time:method" strings from every method track of `anim`.
func _method_keys(anim: Animation) -> Array:
	var out: Array = []
	for t in anim.get_track_count():
		if anim.track_get_type(t) != Animation.TYPE_METHOD:
			continue
		for k in anim.track_get_key_count(t):
			out.append("%.3f:%s" % [anim.track_get_key_time(t, k), anim.method_track_get_name(t, k)])
	out.sort()
	return out

func _track_index(anim: Animation, path: String) -> int:
	for t in anim.get_track_count():
		if anim.track_get_type(t) == Animation.TYPE_VALUE and String(anim.track_get_path(t)) == path:
			return t
	return -1

func _anim(player: AnimationPlayer, anim_name: String) -> Animation:
	return player.get_animation(anim_name) if player.has_animation(anim_name) else null

# --- sections -------------------------------------------------------------------------------

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	var table: Variant = _read_json(TABLE_PATH)
	if gs == null or table == null or not (table is Dictionary) or not table.has("actors"):
		_finish()
		return
	_table = table["actors"]

	# 1-2. Structural parity and the v2 animation data, on instantiated (not running) scenes.
	for kind in PAIRS:
		_compare_pair(kind, PAIRS[kind][0], PAIRS[kind][1], PAIRS[kind][2])
	if _failures.size() > 0:
		_finish()
		return

	# 3. Rig == null at runtime.
	await _behaviour()

	# 4. The same fight on both pairs.
	var r1: Dictionary = await _fight("v1", PAIRS["Player"][0], PAIRS["Guard"][0], gs)
	var r2: Dictionary = await _fight("v2", PAIRS["Player"][1], PAIRS["Guard"][1], gs)
	for f in PARITY_FIELDS:
		_check(_values_equal(r1.get(f), r2.get(f)), "fight: '%s' is %s on v2, expected v1's %s" % [f, r2.get(f), r1.get(f)])
	# A guard without a target is unaware: the first hit from the dark is doubled (5 x 2), as
	# enemy_guard.gd section 3 pins; the heavy then deals its plain 12.
	_check(is_equal_approx(float(r1.get("hp_light", -1.0)), 20.0), "fight v1: Hp after the light hit %s, expected 20 (30 - 5 x DarkFirstHitMultiplier 2)" % r1.get("hp_light"))
	_check(is_equal_approx(float(r1.get("hp_heavy", -1.0)), 8.0), "fight v1: Hp after the heavy %s, expected 8 (20 - 12)" % r1.get("hp_heavy"))
	_check(is_equal_approx(float(r1.get("energy_hurt", -1.0)), 92.0), "fight v1: Energy after the punch %s, expected 92" % r1.get("energy_hurt"))
	_check(r1.get("hit_stop_light") == 0.0 and r1.get("hit_stop_heavy") == 0.0, "fight v1: hit-stop min time scale %s / %s, expected 0 / 0" % [r1.get("hit_stop_light"), r1.get("hit_stop_heavy")])
	_check(r1.get("state_heavy") == "Down", "fight v1: guard state after the heavy '%s', expected 'Down'" % r1.get("state_heavy"))
	_check(is_equal_approx(float(r1.get("down_rotation", -1.0)), PI / 2.0), "fight v1: Visual.rotation while Down %s, expected PI/2 (the rig lies on its side)" % r1.get("down_rotation"))
	_check(is_zero_approx(float(r2.get("down_rotation", -1.0))), "fight v2: Visual.rotation while Down %s, expected 0 (the `down` pose replaces the rotation)" % r2.get("down_rotation"))
	_check(r2.get("down_sprite") == "down", "fight v2: Sprite.animation while Down '%s', expected 'down'" % r2.get("down_sprite"))
	_check(r2.get("up_sprite") == "idle" or r2.get("up_sprite") == "walk", "fight v2: Sprite.animation after getting up '%s', expected 'idle' or 'walk'" % r2.get("up_sprite"))
	_check(r2.get("hurt_sprite") == "hurt", "fight v2: hero Sprite.animation right after the punch '%s', expected 'hurt'" % r2.get("hurt_sprite"))
	print("v2_actors: fight v1 %s" % [r1])
	print("v2_actors: fight v2 %s" % [r2])
	_finish()

func _compare_pair(kind: String, path1: String, path2: String, table_id: String) -> void:
	var s1: PackedScene = load(path1)
	var s2: PackedScene = load(path2)
	_check(s1 != null and s2 != null, "%s: %s or %s failed to load" % [kind, path1, path2])
	if s1 == null or s2 == null:
		return
	var v1: Node = s1.instantiate()
	var v2: Node = s2.instantiate()
	_check(v1.get_script() != null and v2.get_script() != null and v1.get_script().resource_path == v2.get_script().resource_path,
		"%s: v2 script %s, expected v1's %s" % [kind, v2.get_script().resource_path if v2.get_script() else "null", v1.get_script().resource_path if v1.get_script() else "null"])
	_check(v1.get_class() == v2.get_class(), "%s: root type %s on v2, expected %s" % [kind, v2.get_class(), v1.get_class()])
	if v1 is CollisionObject2D and v2 is CollisionObject2D:
		_check(v1.collision_layer == v2.collision_layer and v1.collision_mask == v2.collision_mask, "%s: root layer/mask %s/%s on v2, expected %s/%s" % [kind, v2.collision_layer, v2.collision_mask, v1.collision_layer, v1.collision_mask])
		_check(v1.motion_mode == v2.motion_mode, "%s: motion_mode %s on v2, expected %s" % [kind, v2.motion_mode, v1.motion_mode])
	_compare_exports("%s root" % kind, v1, v1, v2, v2, EXCLUDED_EXPORTS, true)

	# The v1 scene still carries the rig; the v2 scene has no rig and a null Rig export.
	_check(v1.get_node_or_null("Visual/Rig") != null, "%s: v1 has no Visual/Rig any more" % kind)
	_check(v2.get_node_or_null("Visual/Rig") == null, "%s: v2 still has a Visual/Rig" % kind)
	if "Rig" in v2:
		_check(v2.get("Rig") == null, "%s: v2 Rig export is %s, expected null" % [kind, v2.get("Rig")])
	var sprite2: AnimatedSprite2D = v2.get_node_or_null("Visual/Sprite")
	_check(sprite2 != null and sprite2.sprite_frames != null, "%s: v2 Visual/Sprite missing or without SpriteFrames" % kind)
	var sprite1: AnimatedSprite2D = v1.get_node_or_null("Visual/Sprite")
	_check(sprite1 != null and sprite1.sprite_frames == null, "%s: v1 Visual/Sprite missing or now has SpriteFrames" % kind)

	# Visual: same position and light mask (the companion's headlamp bit).
	var vis1: Node2D = v1.get_node_or_null("Visual")
	var vis2: Node2D = v2.get_node_or_null("Visual")
	_check(vis1 != null and vis2 != null, "%s: a Visual node is missing" % kind)
	if vis1 != null and vis2 != null:
		_check(vis1.position == vis2.position, "%s: Visual.position %s on v2, expected %s" % [kind, vis2.position, vis1.position])
		_check(vis1.light_mask == vis2.light_mask, "%s: Visual.light_mask %s on v2, expected %s" % [kind, vis2.light_mask, vis1.light_mask])

	# Shapes, layers, masks.
	for p in SHAPE_NODES[kind]:
		var n1: Node = v1.get_node_or_null(p)
		var n2: Node = v2.get_node_or_null(p)
		_check(n1 != null, "%s: v1 has no %s" % [kind, p])
		_check(n2 != null, "%s: v2 has no %s" % [kind, p])
		if n1 != null and n2 != null:
			_compare_shape_node("%s %s" % [kind, p], n1, n2)

	# StateMachine: same children, scripts and exports.
	var sm1: Node = v1.get_node_or_null("StateMachine")
	var sm2: Node = v2.get_node_or_null("StateMachine")
	_check(sm1 != null and sm2 != null, "%s: a StateMachine is missing" % kind)
	if sm1 != null and sm2 != null:
		_compare_exports("%s StateMachine" % kind, sm1, sm1, sm2, sm2, [], true)
		var names1: Array = []
		for c in sm1.get_children():
			names1.append(c.name)
		var names2: Array = []
		for c in sm2.get_children():
			names2.append(c.name)
		_check(names1 == names2, "%s: states %s on v2, expected %s" % [kind, names2, names1])
		for c1 in sm1.get_children():
			var c2: Node = sm2.get_node_or_null(NodePath(c1.name))
			if c2 == null:
				continue
			_check(c1.get_script() != null and c2.get_script() != null and c1.get_script().resource_path == c2.get_script().resource_path, "%s: state '%s' script differs" % [kind, c1.name])
			_compare_exports("%s state %s" % [kind, c1.name], c1, c1, c2, c2, [], false)

	# AnimationPlayer: names, lengths, loops, method tracks; then the v2 sprite tracks.
	var ap1: AnimationPlayer = v1.get_node_or_null("AnimationPlayer")
	var ap2: AnimationPlayer = v2.get_node_or_null("AnimationPlayer")
	_check(ap1 != null and ap2 != null, "%s: an AnimationPlayer is missing" % kind)
	if ap1 != null and ap2 != null:
		_compare_animations(kind, ap1, ap2, table_id, sprite2)

	v1.free()
	v2.free()

func _compare_animations(kind: String, ap1: AnimationPlayer, ap2: AnimationPlayer, table_id: String, sprite2: AnimatedSprite2D) -> void:
	var list1: Array = Array(ap1.get_animation_list())
	var list2: Array = Array(ap2.get_animation_list())
	var expected2: Array = list1.duplicate()
	for extra in EXTRA_V2_ANIMATIONS.get(kind, []):
		expected2.append(extra)
	expected2.sort()
	list2.sort()
	_check(list2 == expected2, "%s: v2 animations %s, expected %s" % [kind, list2, expected2])
	var table_anims: Dictionary = _table.get(table_id, {}).get("animations", {})
	var frames2: SpriteFrames = sprite2.sprite_frames if sprite2 != null else null

	for anim_name in list2:
		var a2: Animation = _anim(ap2, anim_name)
		var a1: Animation = _anim(ap1, anim_name)
		if a1 != null:
			_check(is_equal_approx(a1.length, a2.length), "%s/%s: length %s on v2, expected %s" % [kind, anim_name, a2.length, a1.length])
			_check(a1.loop_mode == a2.loop_mode, "%s/%s: loop_mode %s on v2, expected %s" % [kind, anim_name, a2.loop_mode, a1.loop_mode])
			var m1: Array = _method_keys(a1)
			var m2: Array = _method_keys(a2)
			_check(m1 == m2, "%s/%s: method keys %s on v2, expected %s" % [kind, anim_name, m2, m1])
		# Pinned windows: the parity above must be parity with the frozen numbers.
		var pinned: Variant = null
		if kind == "Player" and HERO_HIT_WINDOWS.has(anim_name):
			pinned = HERO_HIT_WINDOWS[anim_name]
		elif kind == "Guard" and anim_name == "attack":
			pinned = GUARD_HIT_WINDOW
		if pinned != null:
			var expected_keys: Array = ["%.3f:HitboxOn" % pinned[0], "%.3f:HitboxOff" % pinned[1]]
			expected_keys.sort()
			_check(_method_keys(a2) == expected_keys, "%s/%s: v2 method keys %s, expected %s" % [kind, anim_name, _method_keys(a2), expected_keys])
		# v2 tracks: no rig, discrete sprite tracks in order, keys from the table.
		for t in a2.get_track_count():
			var path: String = String(a2.track_get_path(t))
			_check(not path.contains("Rig"), "%s/%s: v2 track %d still targets the rig (%s)" % [kind, anim_name, t, path])
			if a2.track_get_type(t) == Animation.TYPE_VALUE and path == "Visual:rotation":
				_check(anim_name == "RESET", "%s/%s: v2 keys Visual:rotation; only RESET may (the sprite poses replace the rotation)" % [kind, anim_name])
		var ta: int = _track_index(a2, "Visual/Sprite:animation")
		var tf: int = _track_index(a2, "Visual/Sprite:frame")
		_check(ta >= 0 and tf >= 0, "%s/%s: v2 lacks a Visual/Sprite:animation (%d) or :frame (%d) track" % [kind, anim_name, ta, tf])
		if ta < 0 or tf < 0:
			continue
		_check(ta < tf, "%s/%s: the frame track (%d) comes before the animation track (%d); a key that changes both must apply the animation first" % [kind, anim_name, tf, ta])
		_check(a2.value_track_get_update_mode(ta) == Animation.UPDATE_DISCRETE, "%s/%s: Visual/Sprite:animation track is not discrete" % [kind, anim_name])
		_check(a2.value_track_get_update_mode(tf) == Animation.UPDATE_DISCRETE, "%s/%s: Visual/Sprite:frame track is not discrete" % [kind, anim_name])
		var sprite_anim: String = "idle" if anim_name == "RESET" else anim_name
		_check(a2.track_get_key_count(ta) >= 1 and String(a2.track_get_key_value(ta, 0)) == sprite_anim, "%s/%s: animation key '%s', expected '%s'" % [kind, anim_name, a2.track_get_key_value(ta, 0) if a2.track_get_key_count(ta) > 0 else "", sprite_anim])
		var frame_times: Array = []
		var frame_values: Array = []
		for k in a2.track_get_key_count(tf):
			frame_times.append(snappedf(a2.track_get_key_time(tf, k), 0.001))
			frame_values.append(int(a2.track_get_key_value(tf, k)))
		if anim_name == "RESET":
			_check(frame_times == [0.0] and frame_values == [0], "%s/RESET: frame keys %s=%s, expected [0]=[0]" % [kind, frame_times, frame_values])
			continue
		_check(table_anims.has(anim_name), "%s/%s: not in %s under '%s'" % [kind, anim_name, TABLE_PATH, table_id])
		if not table_anims.has(anim_name):
			continue
		var expected_times: Array = []
		var expected_values: Array = []
		for i in table_anims[anim_name]["keys"].size():
			expected_times.append(snappedf(float(table_anims[anim_name]["keys"][i][0]), 0.001))
			expected_values.append(i)
		_check(frame_times == expected_times, "%s/%s: frame key times %s, expected the table's %s" % [kind, anim_name, frame_times, expected_times])
		_check(frame_values == expected_values, "%s/%s: frame key values %s, expected %s" % [kind, anim_name, frame_values, expected_values])
		_check(is_equal_approx(a2.length, float(table_anims[anim_name]["length"])), "%s/%s: length %s, expected the table's %s" % [kind, anim_name, a2.length, table_anims[anim_name]["length"]])
		_check(frames2 != null and frames2.has_animation(sprite_anim) and frames2.get_frame_count(sprite_anim) == expected_values.size(),
			"%s/%s: SpriteFrames has %s frames, expected %d" % [kind, anim_name, frames2.get_frame_count(sprite_anim) if frames2 != null and frames2.has_animation(sprite_anim) else "none", expected_values.size()])

# 3. Rig == null does not break the shared scripts at runtime.
func _behaviour() -> void:
	var box := Node2D.new()
	root.add_child(box)
	var p: Node = load(PAIRS["Player"][1]).instantiate()
	var g: Node = load(PAIRS["Guard"][1]).instantiate()
	var g1: Node = load(PAIRS["Guard"][0]).instantiate()
	var c: Node = load(PAIRS["Companion"][1]).instantiate()
	p.position = Vector2(200, 450)
	g.position = Vector2(500, 450)
	g1.position = Vector2(800, 450)
	c.position = Vector2(1100, 450)
	for n in [p, g, g1, c]:
		box.add_child(n)
	await _settle()
	await _step(2)

	var ps: AnimatedSprite2D = p.get_node("Visual/Sprite")
	var gsprite: AnimatedSprite2D = g.get_node("Visual/Sprite")
	var cs: AnimatedSprite2D = c.get_node("Visual/Sprite")
	_check(p.Rig == null and c.Rig == null, "behaviour: Rig is %s / %s, expected null / null" % [p.Rig, c.Rig])
	_check(p.CurrentStateName == "Idle", "behaviour: hero state '%s', expected 'Idle'" % p.CurrentStateName)
	_check(String(ps.animation) == "idle" and not ps.is_playing(), "behaviour: hero sprite '%s' playing=%s, expected 'idle' driven by the AnimationPlayer only" % [ps.animation, ps.is_playing()])
	_check(p.AnimationPlayer.current_animation == "idle", "behaviour: hero AnimationPlayer '%s', expected 'idle'" % p.AnimationPlayer.current_animation)
	_check(String(cs.animation) == "idle" and c.AnimationPlayer.current_animation == "idle", "behaviour: Dan sprite '%s' / player '%s', expected idle / idle" % [cs.animation, c.AnimationPlayer.current_animation])
	_check(cs.light_mask == 3, "behaviour: Dan Visual/Sprite.light_mask %s, expected 3 (Companion._Ready copies the lamp bit)" % cs.light_mask)

	p.ResetPose()
	p.PlayAnimation("light_1", "idle")
	_check(String(ps.animation) == "light_1" and ps.frame == 0, "behaviour: after PlayAnimation(light_1) sprite '%s' frame %d, expected 'light_1' 0" % [ps.animation, ps.frame])
	for i in 30:
		await physics_frame
		if p.AnimationTime >= LIGHT_FRAME_TIME:
			break
	_check(String(ps.animation) == "light_1" and ps.frame == 1, "behaviour: at AnimationTime %.3f sprite '%s' frame %d, expected 'light_1' 1 (attack_hit keyed at 0.08)" % [p.AnimationTime, ps.animation, ps.frame])
	_check(not ps.is_playing(), "behaviour: the hero sprite plays itself (two clocks)")
	await _step(20)
	_check(ps.frame == 2, "behaviour: after light_1 sprite frame %d, expected 2 (attack_recover holds)" % ps.frame)
	p.ResetPose()
	_check(String(ps.animation) == "idle" and ps.frame == 0, "behaviour: after ResetPose sprite '%s' frame %d, expected 'idle' 0" % [ps.animation, ps.frame])

	g.SetDown(true)
	_check(is_zero_approx(g.Visual.rotation), "behaviour: v2 guard Visual.rotation %s after SetDown(true), expected 0" % g.Visual.rotation)
	_check(String(gsprite.animation) == "down" and gsprite.frame == 0, "behaviour: v2 guard sprite '%s' frame %d after SetDown(true), expected 'down' 0" % [gsprite.animation, gsprite.frame])
	_check(g.AnimationPlayer.current_animation == "down", "behaviour: v2 guard AnimationPlayer '%s', expected 'down'" % g.AnimationPlayer.current_animation)
	await _step(12)   # past the 0.1 s `down` animation: the pose must hold
	_check(String(gsprite.animation) == "down" and is_zero_approx(g.Visual.rotation), "behaviour: v2 guard sprite '%s' rotation %s 12 frames later, expected 'down' 0 (pose held)" % [gsprite.animation, g.Visual.rotation])
	g.SetDown(false)
	_check(String(gsprite.animation) == "idle" and gsprite.frame == 0 and is_zero_approx(g.Visual.rotation), "behaviour: v2 guard after SetDown(false) sprite '%s' frame %d rotation %s, expected 'idle' 0 0" % [gsprite.animation, gsprite.frame, g.Visual.rotation])
	_check(not g.AnimationPlayer.is_playing(), "behaviour: v2 guard AnimationPlayer still playing '%s' after SetDown(false), expected stopped (ResetPose)" % g.AnimationPlayer.current_animation)
	g1.SetDown(true)
	_check(is_equal_approx(g1.Visual.rotation, PI / 2.0), "behaviour: v1 guard Visual.rotation %s after SetDown(true), expected PI/2 (unchanged)" % g1.Visual.rotation)
	g1.SetDown(false)
	_check(is_zero_approx(g1.Visual.rotation), "behaviour: v1 guard Visual.rotation %s after SetDown(false), expected 0" % g1.Visual.rotation)

	box.queue_free()
	await _step(2)

# 4. One scripted fight; returns the numbers it observed.
func _fight(label: String, hero_path: String, guard_path: String, gs: Node) -> Dictionary:
	var r: Dictionary = {}
	gs.ResetRun()
	_release_all()
	var box := Node2D.new()
	root.add_child(box)
	var hero: Node = load(hero_path).instantiate()
	var guard: Node = load(guard_path).instantiate()
	hero.position = HERO_POS
	guard.position = GUARD_POS
	box.add_child(guard)
	box.add_child(hero)
	await _settle()
	await _step(2)
	var gvisual: Node2D = guard.get_node("Visual")
	var gsprite: AnimatedSprite2D = guard.get_node("Visual/Sprite")
	var hsprite: AnimatedSprite2D = hero.get_node("Visual/Sprite")
	_check(hero.CurrentStateName == "Idle" and guard.CurrentStateName == "Idle", "%s: initial states hero '%s' guard '%s', expected Idle/Idle" % [label, hero.CurrentStateName, guard.CurrentStateName])
	_check(is_equal_approx(guard.Hp, 30.0), "%s: initial guard Hp %s, expected 30" % [label, guard.Hp])

	# a. light hit
	await _tap("attack")
	var h: Dictionary = await _watch_hit(guard, HIT_CAP_MS)
	_check(h["hit"], "%s: light attack did not land within %d ms (Hp %s)" % [label, HIT_CAP_MS, guard.Hp])
	r["hp_light"] = guard.Hp
	r["hit_stop_light"] = h["min_scale"]
	r["state_light"] = h["state"]
	_check(await _wait_restored(RESTORE_CAP_MS), "%s: hit-stop not lifted within %d ms" % [label, RESTORE_CAP_MS])
	await _step(AFTER_HIT_FRAMES)
	r["state_after_light"] = guard.CurrentStateName
	r["hero_after_light"] = hero.CurrentStateName

	# b. heavy knockdown, an ignored hit while Down, get-up
	await _tap("heavy_attack")
	var hk: Dictionary = await _watch_hit(guard, HIT_CAP_MS)
	_check(hk["hit"], "%s: heavy did not land within %d ms (Hp %s)" % [label, HIT_CAP_MS, guard.Hp])
	r["hp_heavy"] = guard.Hp
	r["hit_stop_heavy"] = hk["min_scale"]
	r["state_heavy"] = hk["state"]
	_check(await _wait_restored(RESTORE_CAP_MS), "%s: hit-stop after the heavy not lifted within %d ms" % [label, RESTORE_CAP_MS])
	await _step(2)
	r["down_rotation"] = gvisual.rotation
	r["down_sprite"] = String(gsprite.animation) if gsprite.sprite_frames != null else ""
	r["ignored"] = guard.TakeDamage(IGNORED_HIT[0], IGNORED_HIT[1], IGNORED_HIT[2], IGNORED_HIT[3])
	r["hp_ignored"] = guard.Hp
	var up_after := -1
	for i in GETUP_CAP:
		await physics_frame
		if guard.CurrentStateName != "Down":
			up_after = i + 1
			break
	_check(up_after > 0, "%s: guard still Down after %d frames" % [label, GETUP_CAP])
	r["up_after"] = up_after >= 40 and up_after <= GETUP_CAP   # ~DownDuration; the exact frame may differ by one
	r["state_up"] = guard.CurrentStateName
	await _step(2)
	r["up_sprite"] = String(gsprite.animation) if gsprite.sprite_frames != null else ""
	r["up_rotation"] = gvisual.rotation
	_check(is_zero_approx(gvisual.rotation), "%s: guard Visual.rotation %s after getting up, expected 0" % [label, gvisual.rotation])

	# c. the hero takes a punch
	await _step(AFTER_HIT_FRAMES)
	_check(hero.CurrentStateName == "Idle", "%s: hero state '%s' before the punch, expected Idle" % [label, hero.CurrentStateName])
	hero.TakeDamage(HERO_HIT[0], HERO_HIT[1], HERO_HIT[2], HERO_HIT[3])
	r["energy_hurt"] = gs.Energy
	r["hero_hurt_state"] = hero.CurrentStateName
	r["hurt_sprite"] = String(hsprite.animation) if hsprite.sprite_frames != null else ""
	var hurt_frames := -1
	for i in HURT_IDLE_CAP:
		await physics_frame
		if hero.CurrentStateName == "Idle":
			hurt_frames = i + 1
			break
	r["hero_hurt_frames"] = hurt_frames >= 15 and hurt_frames <= HURT_IDLE_CAP   # 0.30 s = 18 frames, +-alignment
	r["hero_after_hurt"] = hero.CurrentStateName
	_check(Engine.time_scale == 1.0, "%s: Engine.time_scale %s at the end of the fight, expected 1" % [label, Engine.time_scale])

	box.queue_free()
	await _step(2)
	return r
