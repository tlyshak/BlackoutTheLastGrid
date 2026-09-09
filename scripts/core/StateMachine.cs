using System.Collections.Generic;
using Godot;

namespace BlackoutLastGrid.Core;

/// <summary>
/// Generic finite state machine driver shared by the player and enemies.
/// Every direct <see cref="State"/> child is registered under its node name; the machine forwards
/// process, physics and unhandled-input callbacks to the current state and announces transitions
/// through <see cref="StateChangedEventHandler"/>.
/// </summary>
/// <remarks>
/// Children are registered in <see cref="_EnterTree"/>, which Godot runs before any child's
/// <c>_Ready</c>, so a state may use <see cref="State.Machine"/> from its own <c>_Ready</c>.
/// <see cref="StateChangedEventHandler"/> is emitted after <see cref="CurrentState"/> is updated but
/// before <see cref="State.Enter"/> runs, so a state that immediately redirects from
/// <c>Enter</c> produces signals in causal order (A→B, then B→C). Transitions requested from
/// <see cref="State.Exit"/> are rejected: the machine is already committed to the next state.
/// </remarks>
public partial class StateMachine : Node
{
    /// <summary>Emitted on every transition. <paramref name="from"/> is empty for the initial state.</summary>
    [Signal]
    public delegate void StateChangedEventHandler(string from, string to);

    /// <summary>
    /// State to enter on ready. Must be a direct child of this machine; otherwise an error is
    /// reported and the first child state is used. Falls back to the first child when unset.
    /// </summary>
    [Export]
    public State? InitialState { get; set; }

    /// <summary>The currently active state, or <c>null</c> if the machine has no states.</summary>
    public State? CurrentState { get; private set; }

    private readonly Dictionary<string, State> _states = new();
    private bool _exiting;

    /// <summary>Registers child states and wires their <see cref="State.Machine"/> before any child is ready.</summary>
    public override void _EnterTree()
    {
        _states.Clear();

        foreach (Node child in GetChildren())
        {
            if (child is not State state)
            {
                continue;
            }

            state.Machine = this;
            _states[state.Name] = state;
        }
    }

    /// <summary>Enters the initial state.</summary>
    public override void _Ready()
    {
        State? initial = ResolveInitialState();
        if (initial is null)
        {
            GD.PushWarning($"StateMachine '{Name}' has no State children.");
            return;
        }

        CurrentState = initial;
        EmitSignalStateChanged(string.Empty, initial.Name);
        initial.Enter(null);
    }

    /// <inheritdoc/>
    public override void _Process(double delta) => CurrentState?.Update(delta);

    /// <inheritdoc/>
    public override void _PhysicsProcess(double delta) => CurrentState?.PhysicsUpdate(delta);

    /// <inheritdoc/>
    public override void _UnhandledInput(InputEvent @event) => CurrentState?.HandleInput(@event);

    /// <summary>
    /// Switches to the state named <paramref name="stateName"/>. Unknown names and requests made
    /// from inside <see cref="State.Exit"/> are reported with <c>GD.PushError</c> and ignored;
    /// transitioning to the current state is a no-op (see <see cref="TransitionToOrRestart"/>
    /// for hit reactions that must restart).
    /// </summary>
    /// <param name="stateName">Node name of the target state.</param>
    public void TransitionTo(string stateName) => Transition(stateName, restartIfCurrent: false);

    /// <summary>
    /// Like <see cref="TransitionTo"/>, but re-enters the state when it is already current
    /// (a second hit while already in Hurt/Down restarts the reaction). Kept as a separate
    /// method because Godot does not expose C# optional parameters to scripts.
    /// </summary>
    /// <param name="stateName">Node name of the target state.</param>
    public void TransitionToOrRestart(string stateName) => Transition(stateName, restartIfCurrent: true);

    private void Transition(string stateName, bool restartIfCurrent)
    {
        if (!_states.TryGetValue(stateName, out State? next))
        {
            GD.PushError($"StateMachine '{Name}': unknown state '{stateName}'.");
            return;
        }

        if (ReferenceEquals(next, CurrentState))
        {
            if (restartIfCurrent)
            {
                Restart();
            }

            return;
        }

        if (_exiting)
        {
            GD.PushError($"StateMachine '{Name}': TransitionTo('{stateName}') called from Exit() is ignored.");
            return;
        }

        State? previous = CurrentState;
        string fromName = previous?.Name ?? string.Empty;

        if (previous is not null)
        {
            _exiting = true;
            previous.Exit(next);
            _exiting = false;
        }

        CurrentState = next;
        EmitSignalStateChanged(fromName, next.Name);
        next.Enter(previous);
    }

    /// <summary>
    /// Re-enters the current state: <see cref="State.Exit"/> then <see cref="State.Enter"/> with
    /// the state itself as the other party. No <see cref="StateChangedEventHandler"/> is emitted.
    /// Ignored while exiting or when there is no current state.
    /// </summary>
    public void Restart()
    {
        if (CurrentState is null || _exiting)
        {
            return;
        }

        State current = CurrentState;
        _exiting = true;
        current.Exit(current);
        _exiting = false;
        current.Enter(current);
    }

    /// <summary>Returns <c>true</c> if a state with the given name is registered.</summary>
    /// <param name="name">Node name of the state.</param>
    public bool HasState(string name) => _states.ContainsKey(name);

    /// <summary>Returns <c>true</c> if the current state has the given name.</summary>
    /// <param name="name">Node name of the state.</param>
    public bool IsIn(string name) =>
        _states.TryGetValue(name, out State? state) && ReferenceEquals(state, CurrentState);

    private State? ResolveInitialState()
    {
        State? first = null;
        foreach (State state in _states.Values)
        {
            first = state;
            break;
        }

        if (InitialState is null)
        {
            return first;
        }

        if (_states.TryGetValue(InitialState.Name, out State? registered) && ReferenceEquals(registered, InitialState))
        {
            return InitialState;
        }

        GD.PushError($"StateMachine '{Name}': InitialState '{InitialState.Name}' is not a direct child; using '{first?.Name}'.");
        return first;
    }
}
