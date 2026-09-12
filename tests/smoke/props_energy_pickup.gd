extends SceneTree
# Smoke: the powerbank pickup (T-07s-e) — EnergyPickup.tscn keeps the Interactable contract
# (layer 32, mask 0, monitoring off, one circular reach shape, an English prompt) and glows on its
# own; Begin() adds Amount once, emits Collected(Amount) then Finished(true), refuses a second use
# and frees itself within a few frames; a fixture that keeps it (FreeAfterPickup = false) sees the
# second Begin() end with Finished(false) and the energy untouched. Then the additive Guard drop:
# a guard with DropScene set leaves exactly one pickup as its SIBLING at its position + DropOffset
# when it is knocked out, announced once with Dropped; a guard with the default (null) DropScene
# adds nothing to its parent — T-06 byte-identical.
# Needs physics frames.
# Run: godot --headless --path . -s tests/smoke/props_energy_pickup.gd

const NAME := "props_energy_pickup"   # must equal the file basename
const MAX_FRAMES := 3000
const PICKUP_PATH := "res://scenes/props/EnergyPickup.tscn"
const PLAYER_PATH := "res://scenes/player/Player.tscn"
const GUARD_PATH := "res://scenes/enemies/Guard.tscn"
const START_ENERGY := 50.0
const AMOUNT := 25.0
const FREE_CAP := 6             # frames the taken pickup may survive
const DROP_CAP := 6             # frames the deferred drop may take to appear
const DROP_TOL := 1.0           # px between the drop and guard position + DropOffset

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

func _step(frames: int) -> void:
	for i in frames:
		await physics_frame

func _finish() -> void:
	if Engine.time_scale != 1.0:
		_check(false, "Engine.time_scale=%s at the end, expected 1" % Engine.time_scale)
		Engine.time_scale = 1.0
	var gs: Node = root.get_node_or_null("GameState")
	if gs != null:
		gs.ResetRun()
	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)

func _has_cyrillic(text: String) -> bool:
	for i in text.length():
		var code: int = text.unicode_at(i)
		if code >= 0x0400 and code <= 0x04FF:
			return true
	return false

func _is_pickup(node: Node) -> bool:
	var script: Variant = node.get_script()
	return script != null and str(script.resource_path).ends_with("EnergyPickup.cs")

func _pickups_under(parent: Node) -> Array:
	var out: Array = []
	for child in parent.get_children():
		if _is_pickup(child):
			out.append(child)
	return out

func _run() -> void:
	var gs: Node = root.get_node_or_null("GameState")
	_check(gs != null, "GameState autoload not in tree")
	if gs == null:
		_finish()
		return
	gs.ResetRun()

	var pickup_scene: PackedScene = load(PICKUP_PATH)
	var player_scene: PackedScene = load(PLAYER_PATH)
	var guard_scene: PackedScene = load(GUARD_PATH)
	_check(pickup_scene != null and player_scene != null and guard_scene != null, "a scene failed to load")
	if pickup_scene == null or player_scene == null or guard_scene == null:
		_finish()
		return

	var stage: Node2D = Node2D.new()
	stage.y_sort_enabled = true
	root.add_child(stage)
	var player: Node = player_scene.instantiate()
	stage.add_child(player)
	player.global_position = Vector2(-500, -500)   # well away from everything below
	await _step(1)

	# 1. The prefab contract.
	var pickup: Node = pickup_scene.instantiate()
	stage.add_child(pickup)
	pickup.global_position = Vector2(200, 450)
	await _step(1)
	_check(_is_pickup(pickup), "EnergyPickup.tscn has no EnergyPickup.cs attached (did dotnet build run?)")
	if pickup.get("Amount") == null:
		_check(false, "EnergyPickup.Amount export missing — C# script not attached, aborting")
		_finish()
		return
	_check(pickup is Area2D, "EnergyPickup root is a %s, expected Area2D" % pickup.get_class())
	_check(pickup.collision_layer == 32, "EnergyPickup.collision_layer=%d, expected 32 (Interactable)" % pickup.collision_layer)
	_check(pickup.collision_mask == 0, "EnergyPickup.collision_mask=%d, expected 0" % pickup.collision_mask)
	_check(pickup.monitoring == false, "EnergyPickup.monitoring is on; an interactable is passive")
	_check(pickup.monitorable == true, "EnergyPickup.monitorable is off; the hero's InteractionArea could never find it")
	var shape: Node = pickup.get_node_or_null("CollisionShape2D")
	_check(shape is CollisionShape2D and shape.shape is CircleShape2D, "EnergyPickup has no circular reach shape")
	if shape is CollisionShape2D and shape.shape is CircleShape2D:
		_check(shape.shape.radius >= 36.0, "the reach radius is %s, expected at least the hero's InteractionArea (36)" % shape.shape.radius)
	_check(is_equal_approx(pickup.Amount, AMOUNT), "EnergyPickup.Amount=%s, expected %s" % [pickup.Amount, AMOUNT])
	_check(pickup.FreeAfterPickup == true, "EnergyPickup.FreeAfterPickup=%s, expected true" % pickup.FreeAfterPickup)
	_check(not pickup.PromptText.is_empty() and not _has_cyrillic(pickup.PromptText), "EnergyPickup.PromptText '%s' is empty or not English" % pickup.PromptText)
	_check(pickup.CanInteract == true, "a fresh pickup is not interactable")
	var glow: Node = pickup.get_node_or_null("PH_Glow")
	_check(glow is PointLight2D and glow.enabled and glow.energy > 0.0 and glow.texture != null and glow.shadow_enabled == false,
		"PH_Glow is not a lit, shadowless PointLight2D with a texture — the bank would be invisible in the dark")

	# 2. Taking it: +Amount once, Collected then Finished(true), then gone.
	var collected: Array = []
	var finished: Array = []
	pickup.Collected.connect(func(a: float): collected.append(a))
	pickup.Finished.connect(func(ok: bool): finished.append(ok))
	gs.Energy = START_ENERGY
	pickup.Begin(player)
	_check(is_equal_approx(gs.Energy, START_ENERGY + AMOUNT), "Begin() left the energy at %s, expected %s" % [gs.Energy, START_ENERGY + AMOUNT])
	_check(collected.size() == 1 and is_equal_approx(collected[0], AMOUNT), "Collected fired %s, expected [%s]" % [collected, AMOUNT])
	_check(finished == [true], "Finished fired %s, expected [true]" % [finished])
	_check(pickup.IsTaken == true and pickup.CanInteract == false, "a taken pickup is still interactable")
	var freed: int = -1
	for i in FREE_CAP:
		await physics_frame
		if not is_instance_valid(pickup):
			freed = i
			break
	_check(freed >= 0, "the taken pickup is still in the tree after %d frames (FreeAfterPickup)" % FREE_CAP)

	# 3. A kept one refuses the second use.
	var kept: Node = pickup_scene.instantiate()
	kept.FreeAfterPickup = false
	stage.add_child(kept)
	kept.global_position = Vector2(300, 450)
	await _step(1)
	var kept_finished: Array = []
	kept.Finished.connect(func(ok: bool): kept_finished.append(ok))
	gs.Energy = START_ENERGY
	kept.Begin(player)
	kept.Begin(player)
	await _step(2)
	_check(is_instance_valid(kept), "a pickup with FreeAfterPickup = false freed itself")
	_check(kept_finished == [true, false], "two Begin() calls finished %s, expected [true, false]" % [kept_finished])
	_check(is_equal_approx(gs.Energy, START_ENERGY + AMOUNT), "a second Begin() changed the energy to %s, expected %s" % [gs.Energy, START_ENERGY + AMOUNT])

	# 4. The guard drop: a sibling at position + DropOffset, announced once.
	var arena: Node2D = Node2D.new()
	arena.y_sort_enabled = true
	stage.add_child(arena)
	var guard: Node = guard_scene.instantiate()
	arena.add_child(guard)
	guard.global_position = Vector2(600, 450)
	await _step(1)
	_check(guard.get("DropScene") == null, "Guard.DropScene is %s on a fresh Guard.tscn, expected null (T-06 unchanged)" % guard.get("DropScene"))
	guard.DropScene = pickup_scene
	var dropped: Array = []
	guard.Dropped.connect(func(n: Node2D): dropped.append(n))
	var before: int = arena.get_child_count()
	guard.TakeDamage(999.0, 0.0, true, 0)
	var drops: Array = []
	for i in DROP_CAP:
		await physics_frame
		drops = _pickups_under(arena)
		if not drops.is_empty():
			break
	_check(guard.IsKnockedOut == true, "the guard is not knocked out after a 999 hit")
	_check(drops.size() == 1, "after the KO the guard's parent holds %d EnergyPickup(s), expected exactly 1" % drops.size())
	_check(arena.get_child_count() == before + 1, "the guard's parent grew by %d children, expected 1 (the drop)" % (arena.get_child_count() - before))
	if drops.size() == 1:
		var expected: Vector2 = guard.global_position + guard.DropOffset
		_check(drops[0].global_position.distance_to(expected) <= DROP_TOL,
			"the drop landed at %s, expected %s (guard + DropOffset)" % [drops[0].global_position, expected])
		_check(drops[0].get_parent() == arena, "the drop is a child of %s, expected the guard's parent (a sibling)" % drops[0].get_parent())
		_check(dropped.size() == 1 and dropped[0] == drops[0], "Dropped fired %d time(s) with %s, expected once with the drop" % [dropped.size(), dropped])

	# 5. The default: nothing dropped, nothing added.
	var plain: Node = guard_scene.instantiate()
	arena.add_child(plain)
	plain.global_position = Vector2(800, 450)
	await _step(1)
	var before_plain: int = arena.get_child_count()
	var plain_dropped: Array = []
	plain.Dropped.connect(func(n: Node2D): plain_dropped.append(n))
	plain.TakeDamage(999.0, 0.0, true, 0)
	await _step(DROP_CAP)
	_check(plain.IsKnockedOut == true, "the plain guard is not knocked out")
	_check(arena.get_child_count() == before_plain, "a guard with DropScene = null added %d node(s) to its parent" % (arena.get_child_count() - before_plain))
	_check(plain_dropped.is_empty(), "a guard with DropScene = null emitted Dropped")
	_check(_pickups_under(arena).size() == 1, "the arena holds %d pickups after the plain KO, expected still 1" % _pickups_under(arena).size())

	stage.queue_free()
	await _step(2)
	_finish()
