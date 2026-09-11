extends SceneTree
# Smoke: the shared procedural character rig (T-07i-b) — CharacterRig.tscn has exactly the node
# tree the visual brief pins (LegBack, ArmBack, Torso, LegFront, Head, Face, ArmFront/Fist,
# Outline, in draw order), every part is a real polygon, _Ready paints them from the [Export]
# palette colours with the documented per-part shading, Build stretches the silhouette
# monotonically (Slim < Normal < Heavy), and the front arm is rebuilt every time an animation
# moves the fist so the hand never floats away from the shoulder. Then the migration itself:
# Player, Guard, Dummy and the prologue's Dan all carry a Rig with their own palette colours and
# build, the old PH_Body / PH_Face / PH_Fist rectangles are gone, and the empty Visual/Sprite slot
# for future hand-painted art is present in all three characters.
# Run: godot --headless --path . -s tests/smoke/actors_rig.gd
#
# Colours are asserted with is_equal_approx: the .tscn stores 8-9 decimals and Color("e08a1e")
# rebuilds the float from 224/255, which does not round-trip bit-for-bit.

const NAME := "actors_rig"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s).
const MAX_FRAMES := 1200
const RIG_PATH := "res://scenes/actors/CharacterRig.tscn"
const PLAYER_PATH := "res://scenes/player/Player.tscn"
const GUARD_PATH := "res://scenes/enemies/Guard.tscn"
const DUMMY_PATH := "res://scenes/enemies/Dummy.tscn"
const PROLOGUE_PATH := "res://scenes/levels/Level00_Prologue.tscn"
# Draw order is tree order (no z_index inside the rig): back limbs, torso, front leg, head, face,
# front arm, contour on top.
const PARTS := ["LegBack", "ArmBack", "Torso", "LegFront", "Head", "Face", "ArmFront", "Outline"]
const POLYGON_PARTS := ["LegBack", "ArmBack", "Torso", "LegFront", "Head", "Face"]
const BUILD_SLIM := 0     # CharacterRig.BuildKind, C# enums arrive as int
const BUILD_NORMAL := 1
const BUILD_HEAVY := 2
const ARM_VERTICES := 9   # 7-point hand arc + the two shoulder vertices that close the forearm
const REST_FIST := Vector2(14, -10)      # guard pose, 13 px from the shoulder
const EXTENDED_FIST := Vector2(48, -10)  # full extension of the heavy attack, 46 px away
const ANCHOR_TOL := 0.5   # px allowed between the shoulder vertices' midpoint and ShoulderAnchor
const LAG_FRAMES := 80    # idle frames sampled while the hero's 0.55 s 'heavy' plays
const LAG_TOL := 1.0      # px the forearm may trail the animated fist (must stay sub-pixel)
const HERO_SUIT := Color("e08a1e")
const HERO_SKIN := Color("d9a077")
const GUARD_SUIT := Color("2c3340")
const GUARD_SKIN := Color("b5825f")
const DUMMY_SUIT := Color("39424f")
const DUMMY_SKIN := Color("4d5866")
const DAN_SUIT := Color("c9752a")
const OUTLINE_DARK := Color("0a0d14")

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

func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

func _color_eq(actual, expected: Color) -> bool:
	return actual is Color and (actual as Color).is_equal_approx(expected)

# Instantiates the rig scene, optionally overriding Build before _Ready runs, and settles a frame
# so both _Ready (colours, build) and the first _Process (front arm) have happened.
func _spawn_rig(scene: PackedScene, build: int) -> Node2D:
	var rig: Node2D = scene.instantiate()
	if build >= 0:
		rig.set("Build", build)
	root.add_child(rig)
	await _step(1)
	await process_frame
	return rig

func _run() -> void:
	var rig_scene: PackedScene = load(RIG_PATH)
	_check(rig_scene != null, "%s failed to load" % RIG_PATH)
	if rig_scene == null:
		_finish()
		return

	# 1. Structure of the standalone rig: the brief's node tree, in draw order, with real polygons.
	var rig: Node2D = await _spawn_rig(rig_scene, -1)
	_check(rig.get_script() != null and str(rig.get_script().resource_path).ends_with("CharacterRig.cs"),
		"CharacterRig.tscn has no CharacterRig.cs attached (did dotnet build run?)")
	var names: Array = []
	for child in rig.get_children():
		names.append(String(child.name))
	_check(names == PARTS, "rig children %s, expected %s (order is draw order)" % [names, PARTS])
	for part_name in POLYGON_PARTS:
		var part: Node = rig.get_node_or_null(part_name)
		_check(part is Polygon2D, "rig part '%s' is %s, expected Polygon2D" % [part_name, part])
		if part is Polygon2D:
			_check((part as Polygon2D).polygon.size() >= 3,
				"rig part '%s' has %d polygon vertices, expected >= 3" % [part_name, (part as Polygon2D).polygon.size()])
	var arm_front: Node = rig.get_node_or_null("ArmFront")
	_check(arm_front != null and arm_front.get_child_count() == 1,
		"ArmFront has %s children, expected exactly one (Fist)" % [arm_front.get_child_count() if arm_front != null else "no node"])
	var fist: Polygon2D = rig.get_node_or_null("ArmFront/Fist")
	_check(fist != null, "rig has no ArmFront/Fist Polygon2D")
	var outline: Node = rig.get_node_or_null("Outline")
	_check(outline is Line2D and (outline as Line2D).closed, "Outline is %s / closed=%s, expected a closed Line2D" % [outline, outline.get("closed") if outline != null else null])
	# The rig must never flip itself: the owning Visual node mirrors it as a whole.
	_check(rig.scale.is_equal_approx(Vector2.ONE), "rig scale is %s, expected (1, 1) — facing belongs to Visual" % rig.scale)
	_check(rig.get("y_sort_enabled") == false, "Rig.y_sort_enabled is true; its parts must draw in tree order")

	# 2. Exported defaults and the per-part shading _Ready bakes in (criterion 2).
	var suit: Color = rig.get("SuitColor")
	var skin: Color = rig.get("SkinColor")
	var back_shade: float = rig.get("BackLimbShade")
	var front_shade: float = rig.get("FrontLimbShade")
	_check(is_equal_approx(rig.get("OutlineWidth"), 2.0), "OutlineWidth default %s, expected 2.0" % rig.get("OutlineWidth"))
	_check(rig.get("ShowFace") == true, "ShowFace default %s, expected true" % rig.get("ShowFace"))
	_check(rig.get("Build") == BUILD_NORMAL, "Build default %s, expected Normal (%d)" % [rig.get("Build"), BUILD_NORMAL])
	_check(is_equal_approx(back_shade, 0.6), "BackLimbShade default %s, expected 0.6" % back_shade)
	_check(is_equal_approx(front_shade, 0.85), "FrontLimbShade default %s, expected 0.85" % front_shade)
	_check(_color_eq(rig.get("OutlineColor"), OUTLINE_DARK), "OutlineColor default %s, expected %s" % [rig.get("OutlineColor"), OUTLINE_DARK])
	var torso: Polygon2D = rig.get_node("Torso")
	var leg_back: Polygon2D = rig.get_node("LegBack")
	var leg_front: Polygon2D = rig.get_node("LegFront")
	var head: Polygon2D = rig.get_node("Head")
	var face: Polygon2D = rig.get_node("Face")
	var line: Line2D = rig.get_node("Outline")
	_check(torso.color.is_equal_approx(suit), "Torso.color %s, expected SuitColor %s" % [torso.color, suit])
	_check(leg_back.color.is_equal_approx(Color(suit.r * back_shade, suit.g * back_shade, suit.b * back_shade, suit.a)),
		"LegBack.color %s, expected SuitColor * BackLimbShade with alpha kept" % leg_back.color)
	_check(leg_front.color.is_equal_approx(Color(suit.r * front_shade, suit.g * front_shade, suit.b * front_shade, suit.a)),
		"LegFront.color %s, expected SuitColor * FrontLimbShade" % leg_front.color)
	_check(head.color.is_equal_approx(skin), "Head.color %s, expected SkinColor %s" % [head.color, skin])
	_check(fist.color.is_equal_approx(skin), "Fist.color %s, expected SkinColor %s" % [fist.color, skin])
	_check(face.color.is_equal_approx(rig.get("OutlineColor")), "Face.color %s, expected OutlineColor" % face.color)
	_check(line.default_color.is_equal_approx(rig.get("OutlineColor")), "Outline.default_color %s, expected OutlineColor" % line.default_color)
	_check(is_equal_approx(line.width, rig.get("OutlineWidth")), "Outline.width %s, expected OutlineWidth %s" % [line.width, rig.get("OutlineWidth")])

	# 3. Build stretches the silhouette monotonically (criterion 3).
	var slim: Node2D = await _spawn_rig(rig_scene, BUILD_SLIM)
	var heavy: Node2D = await _spawn_rig(rig_scene, BUILD_HEAVY)
	var slim_torso: Polygon2D = slim.get_node("Torso")
	var heavy_torso: Polygon2D = heavy.get_node("Torso")
	var slim_leg: Polygon2D = slim.get_node("LegFront")
	var heavy_leg: Polygon2D = heavy.get_node("LegFront")
	_check(slim_torso.scale.x < torso.scale.x and torso.scale.x < heavy_torso.scale.x,
		"Torso.scale.x Slim/Normal/Heavy = %.3f / %.3f / %.3f, expected strictly increasing" % [slim_torso.scale.x, torso.scale.x, heavy_torso.scale.x])
	_check(slim_leg.position.x < leg_front.position.x and leg_front.position.x < heavy_leg.position.x,
		"LegFront.position.x Slim/Normal/Heavy = %.3f / %.3f / %.3f, expected strictly increasing" % [slim_leg.position.x, leg_front.position.x, heavy_leg.position.x])
	slim.queue_free()
	heavy.queue_free()

	# 4. The front arm follows the animated fist: same vertex count at rest and at full extension,
	#    and the two shoulder vertices always straddle ShoulderAnchor (their midpoint is on it).
	var anchor: Vector2 = rig.get("ShoulderAnchor")
	for target in [REST_FIST, EXTENDED_FIST]:
		fist.position = target
		await process_frame
		var poly: PackedVector2Array = fist.polygon
		_check(poly.size() == ARM_VERTICES, "front arm at fist %s has %d vertices, expected %d" % [target, poly.size(), ARM_VERTICES])
		if poly.size() == ARM_VERTICES:
			var midpoint: Vector2 = (poly[0] + poly[ARM_VERTICES - 1]) * 0.5
			var expected: Vector2 = anchor - target
			_check(midpoint.distance_to(expected) <= ANCHOR_TOL,
				"front arm at fist %s reaches back to %s (local), expected ShoulderAnchor at %s" % [target, midpoint, expected])
	rig.queue_free()
	await _step(1)

	# 5. Migration: every character carries a Rig with its own palette colours, the old
	#    PH_ rectangles are gone and the empty Sprite slot for future art is in place.
	await _check_player()
	await _check_guard()
	await _check_dummy()
	_check_dan()
	_finish()

func _check_player() -> void:
	var scene: PackedScene = load(PLAYER_PATH)
	_check(scene != null, "%s failed to load" % PLAYER_PATH)
	if scene == null:
		return
	var p: Node = scene.instantiate()
	root.add_child(p)
	await _step(1)
	var rig: Node = p.get_node_or_null("Visual/Rig")
	_check(rig != null and str(rig.get_script().resource_path).ends_with("CharacterRig.cs"), "Player has no Visual/Rig CharacterRig")
	if rig != null:
		_check(_color_eq(rig.get("SuitColor"), HERO_SUIT), "Player rig SuitColor %s, expected HeroSuit %s" % [rig.get("SuitColor"), HERO_SUIT])
		_check(_color_eq(rig.get("SkinColor"), HERO_SKIN), "Player rig SkinColor %s, expected SkinWarm %s" % [rig.get("SkinColor"), HERO_SKIN])
		_check(rig.get("Build") == BUILD_NORMAL, "Player rig Build %s, expected Normal (%d)" % [rig.get("Build"), BUILD_NORMAL])
		_check(p.get("Rig") == rig, "Player.Rig export does not point at Visual/Rig")
		_check(rig.visible, "Player rig hidden although Sprite has no SpriteFrames")
	for gone in ["Visual/PH_Body", "Visual/PH_Face", "Visual/PH_Fist"]:
		_check(p.get_node_or_null(gone) == null, "Player still has the old '%s' placeholder" % gone)
	var sprite: Node = p.get_node_or_null("Visual/Sprite")
	_check(sprite is AnimatedSprite2D and (sprite as AnimatedSprite2D).sprite_frames == null,
		"Player Visual/Sprite must stay an empty AnimatedSprite2D slot, got %s" % sprite)
	var shadow: Node = p.get_node_or_null("PH_Shadow")
	_check(shadow is Polygon2D, "Player PH_Shadow must stay a direct child of the root, got %s" % shadow)

	# The forearm must follow the fist the animation moves *this* frame, not the previous one:
	# the rig sits before the AnimationPlayer in the tree, so without a higher process_priority it
	# rebuilds from stale data and the arm tears off the shoulder mid-punch (review B1).
	var ap: AnimationPlayer = p.get_node_or_null("AnimationPlayer")
	var rig_fist: Polygon2D = p.get_node_or_null("Visual/Rig/ArmFront/Fist")
	if ap != null and rig != null and rig_fist != null and ap.has_animation("heavy"):
		var anchor: Vector2 = rig.get("ShoulderAnchor")
		ap.play("heavy")
		ap.seek(0.0, true)
		var worst := 0.0
		var travelled := 0.0
		var previous: Vector2 = rig_fist.position
		for i in LAG_FRAMES:
			await process_frame
			travelled = maxf(travelled, previous.distance_to(rig_fist.position))
			previous = rig_fist.position
			var poly: PackedVector2Array = rig_fist.polygon
			if poly.size() == ARM_VERTICES:
				var midpoint: Vector2 = (poly[0] + poly[ARM_VERTICES - 1]) * 0.5
				worst = maxf(worst, midpoint.distance_to(anchor - rig_fist.position))
		_check(travelled > 0.0, "the 'heavy' animation never moved the fist — the lag check would pass vacuously")
		_check(worst <= LAG_TOL, "front arm trails the animated fist by %.3f px during 'heavy' (max allowed %.1f); the rig must process after the AnimationPlayer" % [worst, LAG_TOL])
		ap.play("RESET")
		ap.seek(0.0, true)
	else:
		_check(false, "Player lacks AnimationPlayer / Visual/Rig/ArmFront/Fist / the 'heavy' animation")
	p.queue_free()
	await _step(1)

func _check_guard() -> void:
	var scene: PackedScene = load(GUARD_PATH)
	_check(scene != null, "%s failed to load" % GUARD_PATH)
	if scene == null:
		return
	var g: Node = scene.instantiate()
	root.add_child(g)
	await _step(1)
	var rig: Node = g.get_node_or_null("Visual/Rig")
	_check(rig != null, "Guard has no Visual/Rig")
	if rig != null:
		_check(_color_eq(rig.get("SuitColor"), GUARD_SUIT), "Guard rig SuitColor %s, expected GuardSuit %s" % [rig.get("SuitColor"), GUARD_SUIT])
		_check(_color_eq(rig.get("SkinColor"), GUARD_SKIN), "Guard rig SkinColor %s, expected SkinCool %s" % [rig.get("SkinColor"), GUARD_SKIN])
		_check(rig.get("Build") == BUILD_HEAVY, "Guard rig Build %s, expected Heavy (%d)" % [rig.get("Build"), BUILD_HEAVY])
	_check(g.get_node_or_null("Visual/PH_Body") == null and g.get_node_or_null("Visual/PH_Fist") == null,
		"Guard still has the old PH_Body / PH_Fist placeholders")
	var sprite: Node = g.get_node_or_null("Visual/Sprite")
	_check(sprite is AnimatedSprite2D and (sprite as AnimatedSprite2D).sprite_frames == null,
		"Guard Visual/Sprite must be an empty AnimatedSprite2D slot, got %s" % sprite)
	g.queue_free()
	await _step(1)

func _check_dummy() -> void:
	var scene: PackedScene = load(DUMMY_PATH)
	_check(scene != null, "%s failed to load" % DUMMY_PATH)
	if scene == null:
		return
	var d: Node = scene.instantiate()
	root.add_child(d)
	await _step(1)
	var rig: Node = d.get_node_or_null("Visual/Rig")
	_check(rig != null, "Dummy has no Visual/Rig")
	if rig != null:
		_check(_color_eq(rig.get("SuitColor"), DUMMY_SUIT), "Dummy rig SuitColor %s, expected ConcreteCold %s" % [rig.get("SuitColor"), DUMMY_SUIT])
		_check(_color_eq(rig.get("SkinColor"), DUMMY_SKIN), "Dummy rig SkinColor %s, expected SteelCold %s" % [rig.get("SkinColor"), DUMMY_SKIN])
		_check(rig.get("ShowFace") == false, "Dummy rig ShowFace %s, expected false (faceless mannequin)" % rig.get("ShowFace"))
		var face: Node = rig.get_node_or_null("Face")
		_check(face != null and face.get("visible") == false, "Dummy rig Face.visible %s after _Ready, expected false" % [face.get("visible") if face != null else null])
	_check(d.get_node_or_null("Visual/PH_Body") == null and d.get_node_or_null("Visual/PH_Face") == null,
		"Dummy still has the old PH_Body / PH_Face placeholders")
	var sprite: Node = d.get_node_or_null("Visual/Sprite")
	_check(sprite is AnimatedSprite2D and (sprite as AnimatedSprite2D).sprite_frames == null,
		"Dummy Visual/Sprite must be an empty AnimatedSprite2D slot, got %s" % sprite)
	_check(d.get_node_or_null("AnimationPlayer") == null, "Dummy must stay a static mannequin without an AnimationPlayer")
	d.queue_free()
	await _step(1)

# Dan is checked on the instantiated (but not running) prologue: booting the whole level here
# would only duplicate level_prologue.gd, and the rig colours are stored export values. Since
# T-07s-b he is the level's Companion (LevelBase.Companion) and no longer a decorative Node2D, so
# his rig sits under Visual/ — the palette contract below is unchanged.
func _check_dan() -> void:
	var scene: PackedScene = load(PROLOGUE_PATH)
	_check(scene != null, "%s failed to load" % PROLOGUE_PATH)
	if scene == null:
		return
	var level: Node = scene.instantiate()
	var dan: Node = level.get("Companion")
	_check(dan is CharacterBody2D and String(dan.name) == "Dan", "Level00_Prologue.Companion is %s, expected a CharacterBody2D named 'Dan'" % dan)
	_check(level.get_node_or_null("PH_Dan") == null, "the prologue still has the old PH_Dan rectangle")
	if dan != null:
		var rig: Node = dan.get_node_or_null("Visual/Rig")
		_check(rig != null, "Dan has no Visual/Rig child")
		if rig != null:
			_check(_color_eq(rig.get("SuitColor"), DAN_SUIT), "Dan rig SuitColor %s, expected DanSuit %s" % [rig.get("SuitColor"), DAN_SUIT])
			_check(rig.get("Build") == BUILD_SLIM, "Dan rig Build %s, expected Slim (%d)" % [rig.get("Build"), BUILD_SLIM])
		_check(dan.get_node_or_null("PH_Shadow") is Polygon2D, "Dan has no PH_Shadow — a silhouette must not float")
	level.free()
