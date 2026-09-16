extends SceneTree
# Smoke: interactables no level tracks — levers built at runtime and wired by hand, next to the
# hero of Level00_Sections. tests/smoke/props_interact.gd covers the lever the level owns; the
# cases here need props the shipped level does not contain:
#   * a lever wired to nothing (Line unset) — CanInteract is false, so the HUD shows its spent text
#     with no key hint, `interact` never takes the hero into Interact, and a direct Begin is the
#     refusal path: Finished(false), IsActive back to false;
#   * a two-way lever (OneWay off) on its own belt — the first use stops the belt (Switched(false),
#     the handle at OffRotationDegrees) and the second starts it again (Switched(true), the handle
#     back upright); the HUD refresh inside the use lands while the prop still counts as active, so
#     the key hint is dropped for that moment and is back the next time the lever is picked —
#     unlike the one-way lever of the level, which ends on its spent text for good;
#   * two levers in reach at once — the hero enters from the left with only the near one in reach,
#     walks right, and the pick (and the prompt) must switch to the other as soon as it is the
#     nearer of the two while both are still in reach; a teleport inside the overlap band, which
#     raises no area enter/exit event at all, must re-pick as well.
#
# Splitting these off keeps props_interact.gd to one instantiated level and no hand-built props —
# the T-B21 rule (a heavy script that also builds and frees many scenes is the one that crashes
# Godot 4.7.2-mono at exit). Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/props_interact_untracked.gd

const NAME := "props_interact_untracked"   # must equal the file basename
# Safety net: quit(1) instead of hanging into the runner timeout (60 s).
const MAX_FRAMES := 2000
const ACTIONS := ["move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special", "interact", "flashlight"]
const LEVEL := "res://scenes/levels/Level00_Sections.tscn"
const SWITCH_SCENE := "res://scenes/props/ConveyorSwitch.tscn"
const LINE_SCENE := "res://scenes/props/ConveyorLine.tscn"
const SETTLE_CAP := 10         # idle frames allowed for the post-load physics catch-up to end (2-3 in practice)
const SETTLE_DELTA := 0.05     # process delta (s) below which the loop is back to normal pacing (16.7 ms at 60 Hz)
const AWAY_POS := Vector2(300, 480)    # the mine face room: no prop in reach
# A lever's reach is a 200x300 rectangle whose centre sits at the node + (10.59, 86.94), so a lever
# at (x, 363) is in reach for a hero at y 450 while his interaction circle (r 36 at his head-height
# offset) overlaps x ∈ [x - 89.41, x + 110.59] — that is, for feet x ∈ [x - 125.41, x + 146.59].
const LEVER_Y := 363.0
const HERO_Y := 450.0
const NO_LINE_X := 700.0       # the lever wired to nothing
const TOGGLE_X := 1000.0       # the two-way lever
const OFF_BAND_POS := Vector2(1000, 3000)   # where the hand-built belts stand: their gate must never touch the walk band
const BAND_A_X := 600.0        # the two levers of the re-pick case…
const BAND_B_X := 660.0        # …60 px apart: both in reach for feet x in ~[534.6, 746.6]
const BAND_START_X := 500.0    # hero start: only lever A in reach
const BAND_SWITCH_X := 630.0   # feet midpoint: lever B is nearer past this x
const BAND_SWITCH_MAX_X := 650.0   # the switch must show within a few frames of the midpoint, well inside the band
const BAND_REPICK_X := 560.0   # teleport inside the band (no enter/exit event): lever A nearer again
const BAND_WALK_CAP := 80      # frames of move_right allowed to cross 500 -> 630 (220 px/s = 3.7 px/frame -> ~36)
const OVERLAP_FRAMES := 3      # physics frames for Area2D overlaps to refresh after a teleport
const INTERACT_CAP := 6        # frames allowed for Idle -> Interact -> Idle on a lever
const IDLE_CAP := 4            # frames allowed for the hero to be Idle after releasing a key
const EXPECTED_PROMPT := "Stop the belt"
const EXPECTED_STOPPED_PROMPT := "Belt stopped"

var _started := false
var _frames := 0
var _failures: Array[String] = []
var _transitions: Array = []

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

# Instantiating the level (~100 ms of C# instancing) makes the next iteration run several physics
# steps back-to-back; wait until the process delta is normal again (same helper as props_interact.gd).
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

# Presses `action` for exactly one physics frame (see props_interact.gd).
func _tap(action: String) -> void:
	Input.action_press(action)
	await _step(1)
	Input.action_release(action)

# Waits (physics frames) until `cond` holds, checking before each frame. Returns the number of
# frames waited, or -1 after `cap` frames.
func _wait_until(cond: Callable, cap: int) -> int:
	for i in cap:
		if cond.call():
			return i
		await physics_frame
	return -1

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	var switch_scene: PackedScene = load(SWITCH_SCENE)
	var line_scene: PackedScene = load(LINE_SCENE)
	var packed: PackedScene = load(LEVEL)
	_check(switch_scene != null, "%s failed to load" % SWITCH_SCENE)
	_check(line_scene != null, "%s failed to load" % LINE_SCENE)
	_check(packed != null, "%s failed to load" % LEVEL)
	if switch_scene == null or line_scene == null or packed == null:
		_finish()
		return
	var level: Node = packed.instantiate()
	root.add_child(level)
	current_scene = level
	await _settle()

	var player: Node = level.get_node_or_null("Player")
	var hud: Node = level.get_node_or_null("HUD")
	_check(player != null, "the level has no 'Player' child")
	_check(hud != null, "the level has no 'HUD' child")
	if player == null or hud == null or player.get("DepthTolerance") == null or hud.get("PromptText") == null:
		_check(false, "Player/HUD exports missing in the level — C# scripts not attached (did dotnet build run?), aborting")
		level.queue_free()
		_finish()
		return
	_release_all()
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	player.StateChanged.connect(func(_from: String, to: String): _transitions.append(to))
	var changes: Array = []
	player.InteractableChanged.connect(func(cur): changes.append(cur))

	# 1. A lever wired to nothing: the prompt says it is spent, `interact` is refused before the
	#    hero enters Interact, and a direct Begin answers Finished(false) without leaving it active.
	var dead: Node = switch_scene.instantiate()
	dead.position = Vector2(NO_LINE_X, LEVER_Y)
	root.add_child(dead)
	var dead_finished: Array = []
	var dead_switched: Array = []
	dead.Finished.connect(func(ok: bool): dead_finished.append(ok))
	dead.Switched.connect(func(running: bool): dead_switched.append(running))
	player.position = Vector2(NO_LINE_X, HERO_Y)
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == dead, "dead lever: CurrentInteractable=%s, expected the lever with no Line" % player.CurrentInteractable)
	_check(dead.CanInteract == false, "dead lever: CanInteract=%s with no Line, expected false" % dead.CanInteract)
	_check(hud.PromptText == EXPECTED_STOPPED_PROMPT, "dead lever: prompt '%s', expected '%s' with no key hint (an unusable prop shows its text as is)" % [hud.PromptText, EXPECTED_STOPPED_PROMPT])
	_transitions.clear()
	await _tap("interact")
	await _step(INTERACT_CAP)
	_check(_transitions.is_empty(), "dead lever: transitions %s on interact, expected none (CanInteract false)" % [_transitions])
	_check(player.CurrentStateName == "Idle", "dead lever: state '%s' after interact, expected 'Idle'" % player.CurrentStateName)
	_check(dead_finished.is_empty(), "dead lever: Finished %s on interact, expected none (Begin never called)" % [dead_finished])
	dead.Begin(player)
	_check(dead_finished == [false], "dead lever: Finished events %s after a direct Begin, expected [false]" % [dead_finished])
	_check(dead_switched.is_empty(), "dead lever: Switched fired %s on a lever with no line" % [dead_switched])
	_check(dead.IsActive == false, "dead lever: IsActive=%s after the refusal, expected false" % dead.IsActive)
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	dead.queue_free()
	await _step(1)

	# 2. A two-way lever (OneWay off) on its own belt: stop, then start again. It can always be
	#    thrown, so the HUD keeps the key hint after the first use — the one-way lever of the level
	#    drops it (props_interact.gd, step 4).
	var belt: Node = line_scene.instantiate()
	belt.position = OFF_BAND_POS
	root.add_child(belt)
	var toggle: Node = switch_scene.instantiate()
	toggle.OneWay = false
	toggle.Line = belt
	toggle.position = Vector2(TOGGLE_X, LEVER_Y)
	root.add_child(toggle)
	var switched: Array = []
	var finished: Array = []
	toggle.Switched.connect(func(running: bool): switched.append(running))
	toggle.Finished.connect(func(ok: bool): finished.append(ok))
	player.position = Vector2(TOGGLE_X, HERO_Y)
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == toggle, "two-way lever: CurrentInteractable=%s, expected the two-way lever" % player.CurrentInteractable)
	_check(belt.Running == true, "two-way lever: the belt is not running before the first use")
	_check(hud.PromptText == "E: " + EXPECTED_PROMPT, "two-way lever: prompt '%s' before the first use, expected 'E: %s'" % [hud.PromptText, EXPECTED_PROMPT])
	_transitions.clear()
	await _tap("interact")
	var stop_frames: int = await _wait_until(func(): return "Interact" in _transitions and player.CurrentStateName == "Idle", INTERACT_CAP)
	await _step(1)
	_check(stop_frames >= 0, "two-way lever: state '%s' with transitions %s after interact, expected Interact -> Idle" % [player.CurrentStateName, _transitions])
	_check(belt.Running == false, "two-way lever: the belt still runs after the first use")
	_check(switched == [false] and finished == [true], "two-way lever: Switched=%s Finished=%s after the first use, expected [false] / [true]" % [switched, finished])
	_check(toggle.Lever != null and is_equal_approx(toggle.Lever.rotation_degrees, toggle.OffRotationDegrees),
		"two-way lever: the handle is at %.2f°, expected OffRotationDegrees %.2f" % [toggle.Lever.rotation_degrees if toggle.Lever != null else 0.0, toggle.OffRotationDegrees])
	_check(toggle.CanInteract == true, "two-way lever: CanInteract=%s after the first use, expected true (OneWay is off)" % toggle.CanInteract)
	# ConveyorSwitch.Begin announces the new prompt before it calls Finish, so the HUD is refreshed
	# while the interaction still counts as active and LevelBase shows the text without the key hint
	# (cosmetic: the shipped lever is one-way, and its spent text carries no hint either way). The
	# hint comes back the next time the prop is picked.
	_check(hud.PromptText == EXPECTED_PROMPT, "two-way lever: prompt '%s' right after the first use, expected '%s' — the refresh lands while the prop is still active" % [hud.PromptText, EXPECTED_PROMPT])
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	_check(hud.PromptText == "", "two-way lever: prompt '%s' after walking away, expected hidden" % hud.PromptText)
	player.position = Vector2(TOGGLE_X, HERO_Y)
	await _step(OVERLAP_FRAMES)
	_check(hud.PromptText == "E: " + EXPECTED_PROMPT, "two-way lever: prompt '%s' after coming back, expected 'E: %s' — the lever can be thrown again" % [hud.PromptText, EXPECTED_PROMPT])
	_transitions.clear()
	await _tap("interact")
	var start_frames: int = await _wait_until(func(): return "Interact" in _transitions and player.CurrentStateName == "Idle", INTERACT_CAP)
	await _step(1)
	_check(start_frames >= 0, "two-way lever: state '%s' with transitions %s on the second use, expected Interact -> Idle" % [player.CurrentStateName, _transitions])
	_check(belt.Running == true, "two-way lever: the second use did not start the belt again")
	_check(switched == [false, true] and finished == [true, true], "two-way lever: Switched=%s Finished=%s after two uses, expected [false, true] / [true, true]" % [switched, finished])
	_check(toggle.Lever != null and is_equal_approx(toggle.Lever.rotation_degrees, 0.0),
		"two-way lever: the handle is at %.2f° with the belt running again, expected 0" % (toggle.Lever.rotation_degrees if toggle.Lever != null else 0.0))
	print("props_interact_untracked: the two-way lever stopped the belt in %d frames and started it again in %d" % [stop_frames + 1, start_frames + 1])
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	toggle.queue_free()
	belt.queue_free()
	await _step(1)

	# 3. Two levers in reach: the hero enters from the left (lever A only), walks right; the pick
	#    and the prompt must switch to lever B as soon as it is nearer (x > 630) while A is still in
	#    reach (up to ~746); a teleport inside the band re-picks with no enter/exit event.
	var band_belt: Node = line_scene.instantiate()
	band_belt.position = OFF_BAND_POS
	root.add_child(band_belt)
	var lever_a: Node = switch_scene.instantiate()
	lever_a.Line = band_belt
	lever_a.PromptText = "Lever A"
	lever_a.position = Vector2(BAND_A_X, LEVER_Y)
	root.add_child(lever_a)
	var lever_b: Node = switch_scene.instantiate()
	lever_b.Line = band_belt
	lever_b.PromptText = "Lever B"
	lever_b.position = Vector2(BAND_B_X, LEVER_Y)
	root.add_child(lever_b)
	changes.clear()
	player.position = Vector2(BAND_START_X, HERO_Y)
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == lever_a, "band: CurrentInteractable=%s at x=%s, expected lever A (the only one in reach)" % [player.CurrentInteractable, BAND_START_X])
	_check(hud.PromptText == "E: Lever A", "band: prompt '%s' at x=%s, expected 'E: Lever A'" % [hud.PromptText, BAND_START_X])
	_check(changes == [lever_a], "band: InteractableChanged events %s on entering, expected [lever A]" % [changes])
	var switch_x: float = -1.0
	Input.action_press("move_right")
	for i in BAND_WALK_CAP:
		await physics_frame
		if player.CurrentInteractable == lever_b:
			switch_x = player.position.x
			break
		if player.position.x > BAND_SWITCH_MAX_X:
			break
	var switch_prompt: String = hud.PromptText
	Input.action_release("move_right")
	_check(switch_x >= 0.0, "band: CurrentInteractable=%s at x=%.1f, expected lever B once past x=%s (the pick must be refreshed while both are in reach)" % [player.CurrentInteractable, player.position.x, BAND_SWITCH_X])
	_check(switch_x < 0.0 or (switch_x > BAND_SWITCH_X and switch_x <= BAND_SWITCH_MAX_X), "band: the pick switched at x=%.1f, expected in (%s, %s] — both levers still in reach" % [switch_x, BAND_SWITCH_X, BAND_SWITCH_MAX_X])
	_check(switch_prompt == "E: Lever B", "band: prompt '%s' at the switch, expected 'E: Lever B'" % switch_prompt)
	_check(changes == [lever_a, lever_b], "band: InteractableChanged events %s after the walk, expected [lever A, lever B]" % [changes])
	var band_idle: int = await _wait_until(func(): return player.CurrentStateName == "Idle", IDLE_CAP)
	_check(band_idle >= 0, "band: state '%s' after releasing move_right, expected 'Idle'" % player.CurrentStateName)
	_check(player.CurrentInteractable == lever_b, "band: CurrentInteractable=%s after stopping at x=%.1f, expected still lever B" % [player.CurrentInteractable, player.position.x])
	player.position = Vector2(BAND_REPICK_X, HERO_Y)
	await _step(2)
	_check(player.CurrentInteractable == lever_a, "band: CurrentInteractable=%s after a teleport to x=%s inside the band, expected lever A (re-pick without an enter/exit event)" % [player.CurrentInteractable, BAND_REPICK_X])
	_check(hud.PromptText == "E: Lever A", "band: prompt '%s' after the teleport back, expected 'E: Lever A'" % hud.PromptText)
	_check(changes == [lever_a, lever_b, lever_a], "band: InteractableChanged events %s after the teleport back, expected [lever A, lever B, lever A]" % [changes])
	print("props_interact_untracked: the pick switched to lever B at x=%.1f (midpoint %s), prompt '%s'" % [switch_x, BAND_SWITCH_X, switch_prompt])
	player.position = AWAY_POS
	await _step(OVERLAP_FRAMES)
	_check(player.CurrentInteractable == null, "band: CurrentInteractable=%s after leaving, expected null" % player.CurrentInteractable)
	lever_a.queue_free()
	lever_b.queue_free()
	band_belt.queue_free()
	await _step(1)

	# 4. Teardown.
	_check(hud.PromptText == "", "teardown: prompt '%s', expected hidden" % hud.PromptText)
	_release_all()
	gs.ResetRun()
	level.queue_free()
	await _step(1)
	print("props_interact_untracked: idle frames used %d of MAX_FRAMES %d" % [_frames, MAX_FRAMES])
	_finish()
