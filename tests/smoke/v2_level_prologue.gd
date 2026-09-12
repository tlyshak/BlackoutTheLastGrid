extends "res://tests/smoke/level_prologue.gd"
# Smoke: the v2 prologue plays its first half exactly like v1 (T-V2-01, GAME_DESIGN §6a — the same
# story, the same map, the same balance). Every step and assertion of level_prologue.gd runs
# unchanged against scenes/v2/Main.tscn → scenes/v2/levels/Level00_Prologue.tscn: boot through
# Main, intro, crate, jam, charge, blast, dark, the wave of two v2 guards, two pickups, Dan led
# to the timber. Only the scene paths and the PASS-line name differ; a v2-only drift in any of
# those steps fails here while the v1 script stays green.
# Run: godot --headless --path . -s tests/smoke/v2_level_prologue.gd

const V2_NAME := "v2_level_prologue"   # must equal the file basename
const V2_MAIN_PATH := "res://scenes/v2/Main.tscn"
const V2_PROLOGUE_PATH := "res://scenes/v2/levels/Level00_Prologue.tscn"

func _name() -> String:
	return V2_NAME

func _main_path() -> String:
	return V2_MAIN_PATH

func _prologue_path() -> String:
	return V2_PROLOGUE_PATH
