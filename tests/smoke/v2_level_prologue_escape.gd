extends "res://tests/smoke/level_prologue_escape.gd"
# Smoke: the v2 prologue plays its second half exactly like v1 (T-V2-01, GAME_DESIGN §6a). Every
# step and assertion of level_prologue_escape.gd runs unchanged against
# scenes/v2/levels/Level00_Prologue.tscn: the timber, the gas pocket, the patrol room, the cage,
# the Held staging (HeldGuards shown — Sprite2Ds in v2), the surface and the exit into
# Level01_District. Only the scene path and the PASS-line name differ.
# Run: godot --headless --path . -s tests/smoke/v2_level_prologue_escape.gd

const V2_NAME := "v2_level_prologue_escape"   # must equal the file basename
const V2_PROLOGUE_PATH := "res://scenes/v2/levels/Level00_Prologue.tscn"

func _name() -> String:
	return V2_NAME

func _prologue_path() -> String:
	return V2_PROLOGUE_PATH
