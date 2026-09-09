extends SceneTree
# Smoke: scripts/core/StateMachine.cs + State.cs — registration in _EnterTree, initial state,
# signal order for a nested transition from Enter(), IsIn/HasState, TransitionToOrRestart/Restart
# re-entering the current state without a StateChanged event (T-02b review S3).
# Run: godot --headless --path . -s tests/smoke/core_statemachine.gd

const NAME := "core_statemachine"

var _done := false
var _failures: Array[String] = []

func _check(cond: bool, msg: String) -> void:
	if not cond:
		_failures.append(msg)

func _make_state(state_name: String, redirect: String = "") -> Node:
	var s: Node = load("res://tests/smoke/support/SmokeState.cs").new()
	s.name = state_name
	s.RedirectOnEnter = redirect
	return s

func _process(_delta: float) -> bool:
	if _done:
		return true
	_done = true

	var sm: Node = load("res://scripts/core/StateMachine.cs").new()
	sm.name = "StateMachine"
	var idle := _make_state("Idle")
	var attack := _make_state("Attack", "Idle")   # redirects back to Idle from Enter()
	var hurt := _make_state("Hurt")
	sm.add_child(idle)
	sm.add_child(attack)
	sm.add_child(hurt)

	var events: Array = []
	sm.StateChanged.connect(func(from, to): events.append("%s>%s" % [from, to]))
	root.add_child(sm)   # _EnterTree registers children, then _Ready enters Idle

	_check(sm.CurrentState == idle, "initial state should be first child 'Idle'")
	_check(idle.MachineAvailableAtReady, "State.Machine must be usable inside State._Ready")
	_check(events == [">Idle"], "initial signal expected ['>Idle'], got %s" % [events])
	_check(sm.IsIn("Idle") and not sm.IsIn("Attack"), "IsIn mismatch after ready")
	_check(sm.HasState("Hurt") and not sm.HasState("Nope"), "HasState mismatch")

	events.clear()
	sm.TransitionTo("Attack")   # Attack.Enter redirects to Idle
	_check(events == ["Idle>Attack", "Attack>Idle"],
		"nested transition signal order expected [Idle>Attack, Attack>Idle], got %s" % [events])
	_check(sm.CurrentState == idle, "machine should end in Idle after redirect")
	_check(attack.EnterCount == 1 and attack.ExitCount == 1, "Attack Enter/Exit counts %d/%d" % [attack.EnterCount, attack.ExitCount])
	_check(idle.EnterCount == 2 and idle.ExitCount == 1, "Idle Enter/Exit counts %d/%d" % [idle.EnterCount, idle.ExitCount])

	events.clear()
	sm.TransitionTo("Idle")     # same state -> no-op
	_check(events.is_empty(), "transition to current state must not emit")

	sm.TransitionTo("Hurt")
	_check(sm.IsIn("Hurt") and events == ["Idle>Hurt"], "plain transition failed: %s" % [events])

	# Restart (T-02b review S3): TransitionToOrRestart on the current state and Restart() re-enter
	# it (Exit + Enter, counts +1/+1) without a StateChanged event; the current state is unchanged.
	sm.TransitionTo("Idle")
	_check(sm.IsIn("Idle") and events == ["Idle>Hurt", "Hurt>Idle"], "return to Idle failed: %s" % [events])
	var idle_enter0: int = idle.EnterCount
	var idle_exit0: int = idle.ExitCount
	events.clear()
	sm.TransitionToOrRestart("Idle")
	_check(sm.IsIn("Idle"), "TransitionToOrRestart(Idle) left Idle")
	_check(idle.EnterCount == idle_enter0 + 1 and idle.ExitCount == idle_exit0 + 1,
		"TransitionToOrRestart(current) Idle Enter/Exit counts %d/%d, expected %d/%d" % [idle.EnterCount, idle.ExitCount, idle_enter0 + 1, idle_exit0 + 1])
	_check(events.is_empty(), "TransitionToOrRestart(current) must not emit StateChanged, got %s" % [events])
	sm.Restart()
	_check(sm.IsIn("Idle"), "Restart() left Idle")
	_check(idle.EnterCount == idle_enter0 + 2 and idle.ExitCount == idle_exit0 + 2,
		"Restart() Idle Enter/Exit counts %d/%d, expected %d/%d" % [idle.EnterCount, idle.ExitCount, idle_enter0 + 2, idle_exit0 + 2])
	_check(events.is_empty(), "Restart() must not emit StateChanged, got %s" % [events])
	_check(hurt.EnterCount == 1 and hurt.ExitCount == 1, "Hurt Enter/Exit counts %d/%d after restarts, expected 1/1 (untouched)" % [hurt.EnterCount, hurt.ExitCount])
	events.clear()
	sm.TransitionToOrRestart("Hurt")   # not current -> a plain transition with its event
	_check(sm.IsIn("Hurt") and events == ["Idle>Hurt"] and hurt.EnterCount == 2,
		"TransitionToOrRestart(other) expected a normal transition, got %s (Hurt EnterCount %d)" % [events, hurt.EnterCount])

	sm.queue_free()

	if _failures.is_empty():
		print("SMOKE %s PASS" % NAME)
		quit(0)
	else:
		print("SMOKE %s FAIL: %s" % [NAME, "; ".join(_failures)])
		quit(1)
	return true
