extends SceneTree
# Smoke: the v1 build is structurally what it was before the v2 line (T-V2-01, GAME_DESIGN §6a).
# The byte-level gate is tools/check-v1-untouched.ps1 (git diff against main); this script is the
# in-engine half that runs forever, after main moves on: the v1 actor scenes still carry the
# procedural CharacterRig under Visual/Rig with no SpriteFrames on Visual/Sprite; the v1 prologue
# keeps its uid and instances the v1 Player / Companion / Guard scenes; scenes/Main.tscn starts the
# v1 prologue; the exposition's NextScenePath still points at scenes/Main.tscn (the v2 path lives
# in the script default only, so the .tscn stays byte-identical); the main menu still points at the
# exposition; and the v2 scenes are separate files with their own uids, never aliases.
# No frames needed: everything is read off instantiated scenes that never enter the tree.
# Run: godot --headless --path . -s tests/smoke/v2_v1_untouched.gd

const NAME := "v2_v1_untouched"   # must equal the file basename
const ACTORS := {
	"res://scenes/player/Player.tscn": "Player.cs",
	"res://scenes/enemies/Guard.tscn": "Guard.cs",
	"res://scenes/actors/Companion.tscn": "Companion.cs",
}
const RIG_SCRIPT := "CharacterRig.cs"
const PROLOGUE_V1 := "res://scenes/levels/Level00_Prologue.tscn"
const PROLOGUE_V1_UID := "uid://d3d1177b7jpkm"
const PROLOGUE_V2 := "res://scenes/v2/levels/Level00_Prologue.tscn"
const MAIN_V1 := "res://scenes/Main.tscn"
const MAIN_V2 := "res://scenes/v2/Main.tscn"
const EXPOSITION_PATH := "res://scenes/ui/Exposition.tscn"
const MENU_PATH := "res://scenes/ui/MainMenu.tscn"
const V1_ACTOR_NODES := {
	"Player": "res://scenes/player/Player.tscn",
	"Dan": "res://scenes/actors/Companion.tscn",
	"Patrol/Guard_1": "res://scenes/enemies/Guard.tscn",
	"Patrol/Guard_2": "res://scenes/enemies/Guard.tscn",
	"Patrol/Guard_3": "res://scenes/enemies/Guard.tscn",
}

var _done := false
var _failures: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _finish() -> void:
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

func _process(_delta: float) -> bool:
	# Autoloads are added after _init(), so all checks run on the first frame.
	if _done:
		return true
	_done = true
	_run()
	_finish()
	return true

func _script_name(node: Node) -> String:
	var script: Variant = node.get_script()
	return str(script.resource_path).get_file() if script != null else ""

func _instance(path: String) -> Node:
	var scene: PackedScene = load(path)
	_check(scene != null, "%s failed to load" % path)
	return scene.instantiate() if scene != null else null

func _run() -> void:
	# 1. The v1 actors: rig under Visual/Rig, an empty Visual/Sprite, the v1 script.
	for path in ACTORS:
		var actor: Node = _instance(path)
		if actor == null:
			continue
		_check(_script_name(actor) == ACTORS[path], "%s runs '%s', expected %s" % [path, _script_name(actor), ACTORS[path]])
		var rig: Node = actor.get_node_or_null("Visual/Rig")
		_check(rig != null and _script_name(rig) == RIG_SCRIPT,
			"%s has no Visual/Rig with %s — the v1 actor must keep its procedural rig" % [path, RIG_SCRIPT])
		var sprite: Node = actor.get_node_or_null("Visual/Sprite")
		_check(sprite != null and sprite is AnimatedSprite2D and sprite.sprite_frames == null,
			"%s Visual/Sprite must stay an empty AnimatedSprite2D in v1 (the v2 twin gets the SpriteFrames)" % path)
		actor.free()

	# 2. The v1 prologue: its uid, the shared script, the v1 actor instances.
	var uid1: int = ResourceLoader.get_resource_uid(PROLOGUE_V1)
	_check(uid1 != ResourceUID.INVALID_ID and ResourceUID.id_to_text(uid1) == PROLOGUE_V1_UID,
		"%s carries uid %s, expected %s" % [PROLOGUE_V1, ResourceUID.id_to_text(uid1) if uid1 != ResourceUID.INVALID_ID else "none", PROLOGUE_V1_UID])
	var uid2: int = ResourceLoader.get_resource_uid(PROLOGUE_V2)
	_check(uid2 != ResourceUID.INVALID_ID and uid2 != uid1, "%s must have its own valid uid, not the v1 one" % PROLOGUE_V2)
	var level: Node = _instance(PROLOGUE_V1)
	if level != null:
		_check(_script_name(level) == "Level00_Prologue.cs", "the v1 prologue runs '%s', expected Level00_Prologue.cs" % _script_name(level))
		for node_path in V1_ACTOR_NODES:
			var actor: Node = level.get_node_or_null(node_path)
			_check(actor != null and actor.scene_file_path == V1_ACTOR_NODES[node_path],
				"v1 prologue %s instances %s, expected %s" % [node_path, actor.scene_file_path if actor != null else "nothing", V1_ACTOR_NODES[node_path]])
		var wave: Node = level.get_node_or_null("GuardWave")
		var wave_scene: PackedScene = wave.get("EnemyScene") if wave != null else null
		_check(wave_scene != null and wave_scene.resource_path == "res://scenes/enemies/Guard.tscn",
			"v1 GuardWave.EnemyScene is %s, expected the v1 Guard" % (wave_scene.resource_path if wave_scene != null else "null"))
		level.free()

	# 3. The v1 entry points: Main -> v1 prologue, exposition -> Main, menu -> exposition.
	var main: Node = _instance(MAIN_V1)
	if main != null:
		var start: PackedScene = main.get("StartLevel")
		_check(start != null and start.resource_path == PROLOGUE_V1,
			"%s starts %s, expected %s" % [MAIN_V1, start.resource_path if start != null else "null", PROLOGUE_V1])
		main.free()
	var main_v2: Node = _instance(MAIN_V2)
	if main_v2 != null:
		var start2: PackedScene = main_v2.get("StartLevel")
		_check(start2 != null and start2.resource_path == PROLOGUE_V2,
			"%s starts %s, expected %s" % [MAIN_V2, start2.resource_path if start2 != null else "null", PROLOGUE_V2])
		_check(_script_name(main_v2) == "Main.cs", "%s runs '%s', expected the shared Main.cs" % [MAIN_V2, _script_name(main_v2)])
		main_v2.free()
	var expo: Node = _instance(EXPOSITION_PATH)
	if expo != null:
		_check(expo.get("NextScenePath") == MAIN_V1, "Exposition.NextScenePath='%s', expected %s" % [expo.get("NextScenePath"), MAIN_V1])
		_check(expo.get("NextScenePathV2") == MAIN_V2, "Exposition.NextScenePathV2='%s', expected %s" % [expo.get("NextScenePathV2"), MAIN_V2])
		expo.free()
	var menu: Node = _instance(MENU_PATH)
	if menu != null:
		_check(menu.get("NewGameScenePath") == EXPOSITION_PATH, "MainMenu.NewGameScenePath='%s', expected %s" % [menu.get("NewGameScenePath"), EXPOSITION_PATH])
		menu.free()
