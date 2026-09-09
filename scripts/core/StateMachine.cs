using System.Collections.Generic;
using Godot;

namespace BlackoutLastGrid.Core;

/// <summary>
/// Generic finite state machine driver shared by the player and enemies.
/// Every direct <see cref="State"/> child is registered under its node name; the machine forwards
/// process, physics and unhandled-input callbacks to the current state and announces transitions
/// through <see cref="StateChangedEventHandler"/>.
/// </summary>
public partial class StateMachine : Node
{
    /// <summary>Emitted after a successful transition. <paramref name="from"/> is empty for the initial state.</summary>
    [Signal]
    public delegate void StateChangedEventHandler(string from, string to);

    /// <summary>State to enter on ready. Falls back to the first registered child when unset.</summary>
    [Export]
    public State? InitialState { get; set; }

    /// <summary>The currently active state, or <c>null</c> if the machine has no states.</summary>
    public State? CurrentState { get; private set; }

    private readonly Dictionary<string, State> _states = new();

    /// <summary>Registers child states, wires their <see cref="State.Machine"/> and enters the initial one.</summary>
    public override void _Ready()
    {
        State? firstRegistered = null;

        foreach (Node child in GetChildren())
        {
            if (child is not State state)
            {
                continue;
            }

            state.Machine = this;
            _states[state.Name] = state;
            firstRegistered ??= state;
        }

        if (firstRegistered is null)
        {
            GD.PushWarning($"StateMachine '{Name}' has no State children.");
            return;
        }

        State initial = InitialState ?? firstRegistered;
        CurrentState = initial;
        initial.Enter(null);
        EmitSignal(SignalName.StateChanged, string.Empty, initial.Name);
    }

    /// <inheritdoc/>
    public override void _Process(double delta) => CurrentState?.Update(delta);

    /// <inheritdoc/>
    public override void _PhysicsProcess(double delta) => CurrentState?.PhysicsUpdate(delta);

    /// <inheritdoc/>
    public override void _UnhandledInput(InputEvent @event) => CurrentState?.HandleInput(@event);

    /// <summary>
    /// Switches to the state named <paramref name="stateName"/>. Unknown names are reported with
    /// <c>GD.PushError</c> and ignored; transitioning to the current state is a no-op.
    /// </summary>
    /// <param name="stateName">Node name of the target state.</param>
    public void TransitionTo(string stateName)
    {
        if (!_states.TryGetValue(stateName, out State? next))
        {
            GD.PushError($"StateMachine '{Name}': unknown state '{stateName}'.");
            return;
        }

        if (ReferenceEquals(next, CurrentState))
        {
            return;
        }

        State? previous = CurrentState;
        string fromName = previous?.Name ?? string.Empty;

        previous?.Exit(next);
        CurrentState = next;
        next.Enter(previous);

        EmitSignal(SignalName.StateChanged, fromName, next.Name);
    }

    /// <summary>Returns <c>true</c> if a state with the given name is registered.</summary>
    /// <param name="name">Node name of the state.</param>
    public bool HasState(string name) => _states.ContainsKey(name);

    /// <summary>Returns <c>true</c> if the current state has the given name.</summary>
    /// <param name="name">Node name of the state.</param>
    public bool IsIn(string name) => CurrentState is not null && CurrentState.Name == name;
}
