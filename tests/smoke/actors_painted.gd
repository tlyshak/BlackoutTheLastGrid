extends SceneTree
# Smoke: the painted actor set — scenes/actors/{Player,Guard,Companion}.tscn are the only actors
# left, and they are drawn by an AnimatedSprite2D under Visual/Sprite (the procedural CharacterRig
# is gone, so there is nothing to compare them against any more):
# (1) the scene contract — each scene loads with its C# script on a CharacterBody2D root, carries a
#     Visual/Sprite AnimatedSprite2D with the SpriteFrames of scenes/actors/*Frames.tres assigned,
#     and both the AnimationPlayer and the SpriteFrames hold exactly the animations listed below
#     (the AnimationPlayer adds RESET, which reuses the `idle` pose);
# (2) the animation data — no track anywhere still targets a rig, every animation carries a
#     discrete Visual/Sprite:animation track before a discrete Visual/Sprite:frame track, the frame
#     key times and the animation length equal scenes/actors/sprite_animations.json and the
#     SpriteFrames animation has that many frames (one source of truth), nothing but RESET keys
#     Visual:rotation (the drawn poses replace the rotation), and the only method tracks are the
#     frozen hit windows — HitboxOn/HitboxOff at 0.08/0.18, 0.08/0.18, 0.12/0.24, 0.22/0.36 for the
#     hero and 0.30/0.40 for the guard, pinned as numbers;
# (3) the sprite is driven by the AnimationPlayer alone — ResetPose / PlayAnimation step the hero's
#     sprite through light_1 at the frozen times without the sprite ever playing itself,
#     SetDown(true) on the guard shows the `down` pose and keeps Visual.rotation 0, and
#     Companion._Ready copies the headlamp render bit onto the sprite;
# (4) combat — one scripted fight (hero light hit, heavy knockdown, an ignored hit while Down,
#     get-up, a hit taken by the hero) produces the frozen numbers: an unaware guard 30 -> 20
#     (5 x DarkFirstHitMultiplier) -> 8, hero energy 100 -> 92, hit-stop down to time scale 0, and
#     the poses that go with them (`down` while Down, `hurt` on the hero).
# Needs physics frames (sections 3 and 4).
# Run: godot --headless --path . -s tests/smoke/actors_painted.gd
#
# Hit-stop sets Engine.time_scale = 0 (physics frames stall), so hits are observed on idle frames
# under a wall-clock cap and the restore is awaited in real time.

const NAME := "actors_painted"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s). Counts _process calls.
const MAX_FRAMES := 6000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "flashlight"]
const TABLE_PATH := "res://scenes/actors/sprite_animations.json"
# kind -> [scene, actor id in the animation table, the SpriteFrames the scene must carry]
const ACTORS := {
	"Player": ["res://scenes/actors/Player.tscn", "RayUnarmed", "res://scenes/actors/RayUnarmedFrames.tres"],
	"Guard": ["res://scenes/actors/Guard.tscn", "Guard", "res://scenes/actors/GuardFrames.tres"],
	"Companion": ["res://scenes/actors/Companion.tscn", "Dan", "res://scenes/actors/DanFrames.tres"],
}
# Every animation on the scene's AnimationPlayer, sorted. RESET is the rest pose and has no entry
# in the table; every other name must be in the table under the actor's id.
const EXPECTED_ANIMATIONS := {
	"Player": ["RESET", "heavy", "hurt", "idle", "jump", "ko", "light_1", "light_2", "light_3", "walk"],
	"Guard": ["RESET", "attack", "down", "hurt", "idle", "ko", "walk"],
	"Companion": ["RESET", "idle", "walk"],
}
# Every animation in the scene's SpriteFrames, sorted (the AnimationPlayer list without RESET).
const EXPECTED_SPRITE_ANIMATIONS := {
	"Player": ["heavy", "hurt", "idle", "jump", "ko", "light_1", "light_2", "light_3", "walk"],
	"Guard": ["attack", "down", "hurt", "idle", "ko", "walk"],
	"Companion": ["idle", "walk"],
}
# Frozen method-track times (T-07i-b), pinned so a rebuilt animation cannot lose its hit window.
const HERO_HIT_WINDOWS := {"light_1": [0.08, 0.18], "light_2": [0.08, 0.18], "light_3": [0.12, 0.24], "heavy": [0.22, 0.36]}
const GUARD_HIT_WINDOW := [0.3, 0.4]
const HIT_CAP_MS := 800
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
const DAN_LIGHT_MASK := 3                # world bit 1 + the headlamp's bit 2

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

# --- helpers ---------------------------------------------------------------------------------

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

func _sorted_names(source: Array) -> Array:
	var out: Array = []
	for n in source:
		out.append(String(n))
	out.sort()
	return out

# --- sections -------------------------------------------------------------------------------

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	var table: Variant = _read_json(TABLE_PATH)
	if gs == null or table == null or not (table is Dictionary) or not table.has("actors"):
		_finish()
		return
	_table = table["actors"]

	# 1-2. The scene contract and the animation data, on instantiated (not running) scenes.
	for kind in ACTORS:
		_check_actor(kind, ACTORS[kind][0], ACTORS[kind][1], ACTORS[kind][2])
	if _failures.size() > 0:
		_finish()
		return

	# 3. The AnimationPlayer is the only clock the sprite obeys.
	await _behaviour()

	# 4. One scripted fight, with the frozen numbers.
	var r: Dictionary = await _fight(gs)
	# A guard without a target is unaware: the first hit from the dark is doubled (5 x 2), as
	# enemy_guard.gd section 3 pins; the heavy then deals its plain 12.
	_check(is_equal_approx(float(r.get("hp_light", -1.0)), 20.0), "fight: Hp after the light hit %s, expected 20 (30 - 5 x DarkFirstHitMultiplier 2)" % r.get("hp_light"))
	_check(is_equal_approx(float(r.get("hp_heavy", -1.0)), 8.0), "fight: Hp after the heavy %s, expected 8 (20 - 12)" % r.get("hp_heavy"))
	_check(is_equal_approx(float(r.get("energy_hurt", -1.0)), 92.0), "fight: Energy after the punch %s, expected 92" % r.get("energy_hurt"))
	_check(r.get("hit_stop_light") == 0.0 and r.get("hit_stop_heavy") == 0.0, "fight: hit-stop min time scale %s / %s, expected 0 / 0" % [r.get("hit_stop_light"), r.get("hit_stop_heavy")])
	_check(r.get("state_heavy") == "Down", "fight: guard state after the heavy '%s', expected 'Down'" % r.get("state_heavy"))
	_check(r.get("ignored") == false, "fight: a hit landed on the guard while he was Down (TakeDamage returned %s, expected false)" % r.get("ignored"))
	_check(is_equal_approx(float(r.get("hp_ignored", -1.0)), 8.0), "fight: Hp %s after the ignored hit, expected it to stay 8" % r.get("hp_ignored"))
	_check(r.get("up_after") == true, "fight: the guard got up after %s frames, expected roughly DownDuration (40..%d)" % [r.get("up_frames"), GETUP_CAP])
	_check(r.get("state_up") == "Idle" or r.get("state_up") == "Approach", "fight: guard state '%s' after getting up, expected Idle or Approach" % r.get("state_up"))
	_check(is_zero_approx(float(r.get("down_rotation", -1.0))), "fight: Visual.rotation while Down %s, expected 0 (the `down` pose replaces the rotation)" % r.get("down_rotation"))
	_check(r.get("down_sprite") == "down", "fight: Sprite.animation while Down '%s', expected 'down'" % r.get("down_sprite"))
	_check(r.get("up_sprite") == "idle" or r.get("up_sprite") == "walk", "fight: Sprite.animation after getting up '%s', expected 'idle' or 'walk'" % r.get("up_sprite"))
	_check(r.get("hero_hurt_state") == "Hurt", "fight: hero state '%s' right after the punch, expected 'Hurt'" % r.get("hero_hurt_state"))
	_check(r.get("hurt_sprite") == "hurt", "fight: hero Sprite.animation right after the punch '%s', expected 'hurt'" % r.get("hurt_sprite"))
	_check(r.get("hero_hurt_frames") == true, "fight: the hero left Hurt after %s frames, expected roughly 0.30 s (15..%d)" % [r.get("hurt_frames"), HURT_IDLE_CAP])
	_check(r.get("hero_after_hurt") == "Idle", "fight: hero state '%s' after Hurt, expected 'Idle'" % r.get("hero_after_hurt"))
	print("actors_painted: fight %s" % [r])
	_finish()

# 1-2. One actor scene: the contract, then every animation against the table.
func _check_actor(kind: String, scene_path: String, table_id: String, frames_path: String) -> void:
	var scene: PackedScene = load(scene_path)
	_check(scene != null, "%s: %s failed to load" % [kind, scene_path])
	if scene == null:
		return
	var actor: Node = scene.instantiate()
	_check(actor is CharacterBody2D, "%s: root is a %s, expected CharacterBody2D" % [kind, actor.get_class()])
	var script: Variant = actor.get_script()
	_check(script != null and String(script.resource_path).ends_with("%s.cs" % kind),
		"%s: root script is %s, expected .../%s.cs (did dotnet build run?)" % [kind, script.resource_path if script != null else "null", kind])

	# The rig is gone for good: nothing in the scene may still refer to it.
	_check(actor.get_node_or_null("Visual/Rig") == null, "%s: the scene still has a Visual/Rig (CharacterRig was deleted)" % kind)
	_check(not ("Rig" in actor), "%s: the script still exports a Rig" % kind)

	var visual: Node2D = actor.get_node_or_null("Visual")
	_check(visual != null, "%s: no Visual node" % kind)
	var sprite: AnimatedSprite2D = actor.get_node_or_null("Visual/Sprite")
	_check(sprite != null, "%s: no Visual/Sprite AnimatedSprite2D" % kind)
	if sprite == null or visual == null:
		actor.free()
		return
	# Player and Companion reach the sprite through an export; Guard drives it from the tracks only.
	if "Sprite" in actor:
		_check(actor.get("Sprite") == sprite, "%s: the Sprite export does not point at Visual/Sprite" % kind)
	var frames: SpriteFrames = sprite.sprite_frames
	_check(frames != null, "%s: Visual/Sprite has no SpriteFrames — the actor would draw nothing" % kind)
	if frames == null:
		actor.free()
		return
	_check(frames.resource_path == frames_path, "%s: Visual/Sprite.sprite_frames is %s, expected %s" % [kind, frames.resource_path, frames_path])
	_check(_sorted_names(frames.get_animation_names()) == EXPECTED_SPRITE_ANIMATIONS[kind],
		"%s: SpriteFrames animations %s, expected %s" % [kind, _sorted_names(frames.get_animation_names()), EXPECTED_SPRITE_ANIMATIONS[kind]])

	var ap: AnimationPlayer = actor.get_node_or_null("AnimationPlayer")
	_check(ap != null, "%s: no AnimationPlayer" % kind)
	if ap == null:
		actor.free()
		return
	_check(actor.get("AnimationPlayer") == ap, "%s: the AnimationPlayer export does not point at the child" % kind)
	var list: Array = _sorted_names(ap.get_animation_list())
	_check(list == EXPECTED_ANIMATIONS[kind], "%s: AnimationPlayer animations %s, expected %s" % [kind, list, EXPECTED_ANIMATIONS[kind]])
	_check_animations(kind, ap, table_id, frames)
	actor.free()

func _check_animations(kind: String, ap: AnimationPlayer, table_id: String, frames: SpriteFrames) -> void:
	var table_anims: Dictionary = _table.get(table_id, {}).get("animations", {})
	for anim_name in _sorted_names(ap.get_animation_list()):
		var a: Animation = ap.get_animation(anim_name)
		if a == null:
			continue
		# The frozen hit windows; every other animation calls nothing.
		var pinned: Variant = null
		if kind == "Player" and HERO_HIT_WINDOWS.has(anim_name):
			pinned = HERO_HIT_WINDOWS[anim_name]
		elif kind == "Guard" and anim_name == "attack":
			pinned = GUARD_HIT_WINDOW
		var expected_keys: Array = []
		if pinned != null:
			expected_keys = ["%.3f:HitboxOn" % pinned[0], "%.3f:HitboxOff" % pinned[1]]
			expected_keys.sort()
		_check(_method_keys(a) == expected_keys, "%s/%s: method keys %s, expected %s" % [kind, anim_name, _method_keys(a), expected_keys])

		# The painted tracks: no rig, discrete sprite tracks in order, keys from the table.
		for t in a.get_track_count():
			var path: String = String(a.track_get_path(t))
			_check(not path.contains("Rig"), "%s/%s: track %d still targets the rig (%s)" % [kind, anim_name, t, path])
			if a.track_get_type(t) == Animation.TYPE_VALUE and path == "Visual:rotation":
				_check(anim_name == "RESET", "%s/%s: keys Visual:rotation; only RESET may (the drawn poses replace the rotation)" % [kind, anim_name])
		var ta: int = _track_index(a, "Visual/Sprite:animation")
		var tf: int = _track_index(a, "Visual/Sprite:frame")
		_check(ta >= 0 and tf >= 0, "%s/%s: no Visual/Sprite:animation (%d) or :frame (%d) track" % [kind, anim_name, ta, tf])
		if ta < 0 or tf < 0:
			continue
		_check(ta < tf, "%s/%s: the frame track (%d) comes before the animation track (%d); a key that changes both must apply the animation first" % [kind, anim_name, tf, ta])
		_check(a.value_track_get_update_mode(ta) == Animation.UPDATE_DISCRETE, "%s/%s: Visual/Sprite:animation track is not discrete" % [kind, anim_name])
		_check(a.value_track_get_update_mode(tf) == Animation.UPDATE_DISCRETE, "%s/%s: Visual/Sprite:frame track is not discrete" % [kind, anim_name])
		var sprite_anim: String = "idle" if anim_name == "RESET" else anim_name
		_check(a.track_get_key_count(ta) >= 1 and String(a.track_get_key_value(ta, 0)) == sprite_anim, "%s/%s: animation key '%s', expected '%s'" % [kind, anim_name, a.track_get_key_value(ta, 0) if a.track_get_key_count(ta) > 0 else "", sprite_anim])
		var frame_times: Array = []
		var frame_values: Array = []
		for k in a.track_get_key_count(tf):
			frame_times.append(snappedf(a.track_get_key_time(tf, k), 0.001))
			frame_values.append(int(a.track_get_key_value(tf, k)))
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
		_check(is_equal_approx(a.length, float(table_anims[anim_name]["length"])), "%s/%s: length %s, expected the table's %s" % [kind, anim_name, a.length, table_anims[anim_name]["length"]])
		_check(a.loop_mode == (Animation.LOOP_LINEAR if bool(table_anims[anim_name].get("loop", false)) else Animation.LOOP_NONE),
			"%s/%s: loop_mode %s, expected the table's loop=%s" % [kind, anim_name, a.loop_mode, table_anims[anim_name].get("loop", false)])
		_check(frames.has_animation(sprite_anim) and frames.get_frame_count(sprite_anim) == expected_values.size(),
			"%s/%s: SpriteFrames has %s frames, expected %d" % [kind, anim_name, frames.get_frame_count(sprite_anim) if frames.has_animation(sprite_anim) else "none", expected_values.size()])

# 3. The AnimationPlayer drives the sprite; the sprite never plays itself.
func _behaviour() -> void:
	var box := Node2D.new()
	root.add_child(box)
	var p: Node = load(ACTORS["Player"][0]).instantiate()
	var g: Node = load(ACTORS["Guard"][0]).instantiate()
	var c: Node = load(ACTORS["Companion"][0]).instantiate()
	p.position = Vector2(200, 450)
	g.position = Vector2(500, 450)
	c.position = Vector2(1100, 450)
	for n in [p, g, c]:
		box.add_child(n)
	await _settle()
	await _step(2)

	var ps: AnimatedSprite2D = p.get_node("Visual/Sprite")
	var gsprite: AnimatedSprite2D = g.get_node("Visual/Sprite")
	var cs: AnimatedSprite2D = c.get_node("Visual/Sprite")
	_check(p.CurrentStateName == "Idle", "behaviour: hero state '%s', expected 'Idle'" % p.CurrentStateName)
	_check(String(ps.animation) == "idle" and not ps.is_playing(), "behaviour: hero sprite '%s' playing=%s, expected 'idle' driven by the AnimationPlayer only" % [ps.animation, ps.is_playing()])
	_check(p.AnimationPlayer.current_animation == "idle", "behaviour: hero AnimationPlayer '%s', expected 'idle'" % p.AnimationPlayer.current_animation)
	_check(String(cs.animation) == "idle" and c.AnimationPlayer.current_animation == "idle", "behaviour: Dan sprite '%s' / player '%s', expected idle / idle" % [cs.animation, c.AnimationPlayer.current_animation])
	_check(cs.light_mask == DAN_LIGHT_MASK, "behaviour: Dan Visual/Sprite.light_mask %s, expected %d (Companion._Ready copies the lamp bit)" % [cs.light_mask, DAN_LIGHT_MASK])

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
	_check(is_zero_approx(g.Visual.rotation), "behaviour: guard Visual.rotation %s after SetDown(true), expected 0" % g.Visual.rotation)
	_check(String(gsprite.animation) == "down" and gsprite.frame == 0, "behaviour: guard sprite '%s' frame %d after SetDown(true), expected 'down' 0" % [gsprite.animation, gsprite.frame])
	_check(g.AnimationPlayer.current_animation == "down", "behaviour: guard AnimationPlayer '%s', expected 'down'" % g.AnimationPlayer.current_animation)
	await _step(12)   # past the 0.1 s `down` animation: the pose must hold
	_check(String(gsprite.animation) == "down" and is_zero_approx(g.Visual.rotation), "behaviour: guard sprite '%s' rotation %s 12 frames later, expected 'down' 0 (pose held)" % [gsprite.animation, g.Visual.rotation])
	g.SetDown(false)
	_check(String(gsprite.animation) == "idle" and gsprite.frame == 0 and is_zero_approx(g.Visual.rotation), "behaviour: guard after SetDown(false) sprite '%s' frame %d rotation %s, expected 'idle' 0 0" % [gsprite.animation, gsprite.frame, g.Visual.rotation])
	_check(not g.AnimationPlayer.is_playing(), "behaviour: guard AnimationPlayer still playing '%s' after SetDown(false), expected stopped (ResetPose)" % g.AnimationPlayer.current_animation)

	box.queue_free()
	await _step(2)

# 4. One scripted fight; returns the numbers it observed.
func _fight(gs: Node) -> Dictionary:
	var r: Dictionary = {}
	gs.ResetRun()
	_release_all()
	var box := Node2D.new()
	root.add_child(box)
	var hero: Node = load(ACTORS["Player"][0]).instantiate()
	var guard: Node = load(ACTORS["Guard"][0]).instantiate()
	hero.position = HERO_POS
	guard.position = GUARD_POS
	box.add_child(guard)
	box.add_child(hero)
	await _settle()
	await _step(2)
	var gvisual: Node2D = guard.get_node("Visual")
	var gsprite: AnimatedSprite2D = guard.get_node("Visual/Sprite")
	var hsprite: AnimatedSprite2D = hero.get_node("Visual/Sprite")
	_check(hero.CurrentStateName == "Idle" and guard.CurrentStateName == "Idle", "fight: initial states hero '%s' guard '%s', expected Idle/Idle" % [hero.CurrentStateName, guard.CurrentStateName])
	_check(is_equal_approx(guard.Hp, 30.0), "fight: initial guard Hp %s, expected 30" % guard.Hp)

	# a. light hit
	await _tap("attack")
	var h: Dictionary = await _watch_hit(guard, HIT_CAP_MS)
	_check(h["hit"], "fight: light attack did not land within %d ms (Hp %s)" % [HIT_CAP_MS, guard.Hp])
	r["hp_light"] = guard.Hp
	r["hit_stop_light"] = h["min_scale"]
	r["state_light"] = h["state"]
	_check(await _wait_restored(RESTORE_CAP_MS), "fight: hit-stop not lifted within %d ms" % RESTORE_CAP_MS)
	await _step(AFTER_HIT_FRAMES)
	r["state_after_light"] = guard.CurrentStateName
	r["hero_after_light"] = hero.CurrentStateName

	# b. heavy knockdown, an ignored hit while Down, get-up
	await _tap("heavy_attack")
	var hk: Dictionary = await _watch_hit(guard, HIT_CAP_MS)
	_check(hk["hit"], "fight: heavy did not land within %d ms (Hp %s)" % [HIT_CAP_MS, guard.Hp])
	r["hp_heavy"] = guard.Hp
	r["hit_stop_heavy"] = hk["min_scale"]
	r["state_heavy"] = hk["state"]
	_check(await _wait_restored(RESTORE_CAP_MS), "fight: hit-stop after the heavy not lifted within %d ms" % RESTORE_CAP_MS)
	await _step(2)
	r["down_rotation"] = gvisual.rotation
	r["down_sprite"] = String(gsprite.animation)
	r["ignored"] = guard.TakeDamage(IGNORED_HIT[0], IGNORED_HIT[1], IGNORED_HIT[2], IGNORED_HIT[3])
	r["hp_ignored"] = guard.Hp
	var up_after := -1
	for i in GETUP_CAP:
		await physics_frame
		if guard.CurrentStateName != "Down":
			up_after = i + 1
			break
	_check(up_after > 0, "fight: guard still Down after %d frames" % GETUP_CAP)
	r["up_frames"] = up_after
	r["up_after"] = up_after >= 40 and up_after <= GETUP_CAP   # ~DownDuration; the exact frame may differ by one
	r["state_up"] = guard.CurrentStateName
	await _step(2)
	r["up_sprite"] = String(gsprite.animation)
	r["up_rotation"] = gvisual.rotation
	_check(is_zero_approx(gvisual.rotation), "fight: guard Visual.rotation %s after getting up, expected 0" % gvisual.rotation)

	# c. the hero takes a punch
	await _step(AFTER_HIT_FRAMES)
	_check(hero.CurrentStateName == "Idle", "fight: hero state '%s' before the punch, expected Idle" % hero.CurrentStateName)
	hero.TakeDamage(HERO_HIT[0], HERO_HIT[1], HERO_HIT[2], HERO_HIT[3])
	r["energy_hurt"] = gs.Energy
	r["hero_hurt_state"] = hero.CurrentStateName
	r["hurt_sprite"] = String(hsprite.animation)
	var hurt_frames := -1
	for i in HURT_IDLE_CAP:
		await physics_frame
		if hero.CurrentStateName == "Idle":
			hurt_frames = i + 1
			break
	r["hurt_frames"] = hurt_frames
	r["hero_hurt_frames"] = hurt_frames >= 15 and hurt_frames <= HURT_IDLE_CAP   # 0.30 s = 18 frames, +-alignment
	r["hero_after_hurt"] = hero.CurrentStateName
	_check(Engine.time_scale == 1.0, "fight: Engine.time_scale %s at the end of the fight, expected 1" % Engine.time_scale)

	box.queue_free()
	await _step(2)
	return r
