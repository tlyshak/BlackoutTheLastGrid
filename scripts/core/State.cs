using Godot;

namespace BlackoutLastGrid.Core;

/// <summary>
/// Base class for a single state of a <see cref="StateMachine"/>.
/// States are child nodes of a <see cref="StateMachine"/>; the node's <c>Name</c> is the state key
/// used by <see cref="StateMachine.TransitionTo"/>. Override the virtual hooks as needed;
/// all of them are no-ops by default.
/// </summary>
public abstract partial class State : Node
{
    /// <summary>The state machine that owns this state. Assigned by the machine on ready.</summary>
    public StateMachine Machine { get; internal set; } = null!;

    /// <summary>Called when the machine switches into this state.</summary>
    /// <param name="previous">The state being left, or <c>null</c> for the initial state.</param>
    public virtual void Enter(State? previous)
    {
    }

    /// <summary>Called when the machine switches out of this state.</summary>
    /// <param name="next">The state being entered, or <c>null</c> if none.</param>
    public virtual void Exit(State? next)
    {
    }

    /// <summary>Called from the machine's <c>_UnhandledInput</c> while this state is active.</summary>
    /// <param name="event">The unhandled input event.</param>
    public virtual void HandleInput(InputEvent @event)
    {
    }

    /// <summary>Called from the machine's <c>_Process</c> while this state is active.</summary>
    /// <param name="delta">Frame time in seconds.</param>
    public virtual void Update(double delta)
    {
    }

    /// <summary>Called from the machine's <c>_PhysicsProcess</c> while this state is active.</summary>
    /// <param name="delta">Physics step time in seconds.</param>
    public virtual void PhysicsUpdate(double delta)
    {
    }

    /// <summary>Convenience wrapper around <see cref="StateMachine.TransitionTo"/>.</summary>
    /// <param name="stateName">Name of the target state node.</param>
    protected void TransitionTo(string stateName) => Machine.TransitionTo(stateName);
}
