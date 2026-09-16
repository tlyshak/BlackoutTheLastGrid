extends "res://tests/smoke/level_prologue.gd"
# Smoke: the v2 prologue plays its first half exactly like v1 (T-V2-01, GAME_DESIGN §6a — the same
# story, the same map, the same balance). Every step and assertion of level_prologue.gd runs
# unchanged against scenes/v2/Main.tscn → scenes/v2/levels/Level00_Prologue.tscn: boot through
# Main, intro, the first room, jam, charge, blast, dark, the wave of two v2 guards, two pickups,
# Dan led to the timber. Only the scene paths and the PASS-line name differ — and the first room's
# obstacle: the author's playtest of 2026-09-12 took the crate row out of v2 («I don't want to
# jump over them»), so _check_crate here asserts the opposite of v1: no Crate, no PH_Crate_Stack,
# the hero walks through where the crates stood at every depth, the jump hint still shows there
# and completes on a jump. A v2-only drift in any other step fails here while the v1 script stays
# green.
# Run: godot --headless --path . -s tests/smoke/v2_level_prologue.gd

const V2_NAME := "v2_level_prologue"   # must equal the file basename
const V2_MAIN_PATH := "res://scenes/v2/Main.tscn"
const V2_PROLOGUE_PATH := "res://scenes/v2/levels/Level00_Prologue.tscn"
const CRATES_GONE := ["Crate", "PH_Crate_Stack"]   # v2 deliberately without (author's playtest 2026-09-12)
const V2_LIMIT_TOP := -80   # the v2 mine rooms start 80 px above v1's: the painted beam, fan and lamps sit in the window (T-V2-05)

func _name() -> String:
	return V2_NAME

func _main_path() -> String:
	return V2_MAIN_PATH

func _prologue_path() -> String:
	return V2_PROLOGUE_PATH

func _limit_top() -> int:
	return V2_LIMIT_TOP

# v2 first room without the crate row: nothing blocks the walk where v1's crate stood, the jump
# hint still appears on the way and completes on a jump.
func _check_crate(level: Node, player: Node) -> void:
	for name in CRATES_GONE:
		_check(level.get_node_or_null(name) == null, "the v2 prologue still carries '%s' — the author asked for the first room without the crate stack" % name)
	for depth in [player.FloorTop + BAND_MARGIN, 450.0, player.FloorBottom - BAND_MARGIN]:
		var reached: float = await _walk_right(player, Vector2(BEFORE_CRATE.x, depth))
		_check(reached >= CRATE_CLEAR_X, "walking right at Y %.0f the hero stopped at x %.0f, expected past %.0f on foot (v2 has no crate at x %.0f)" % [depth, reached, CRATE_CLEAR_X, CRATE_X])
	_release_all()
	var hint: Node = level.get("JumpPrompt")
	_check(hint != null and hint.IsShown == true, "the jump hint never appeared on the walk through the first room")
	_check(hint != null and hint.IsCompleted == false, "the jump hint completed before any jump")
	await _tap("jump")
	await _step(JUMP_CAP)
	_check(hint != null and hint.IsCompleted == true, "the jump hint did not complete on a jump")
	_release_all()
