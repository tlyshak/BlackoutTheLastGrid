using System;
using Godot;

namespace BlackoutLastGrid.Core;

/// <summary>
/// Base class for a single state of a <see cref="StateMachine"/>.
/// States are direct child nodes of a <see cref="StateMachine"/>; the node's <c>Name</c> is the
/// state key used by <see cref="StateMachine.TransitionTo"/>. Override the virtual hooks as
/// needed; all of them are no-ops by default.
/// </summary>
public abstract partial class State : Node
{
    private StateMachine? _machine;

    /// <summary>
    /// The state machine that owns this state. Assigned by the machine in its <c>_EnterTree</c>;
    /// if read earlier, resolves to the parent node, which must be a <see cref="StateMachine"/>.
    /// </summary>
    /// <exception cref="InvalidOperationException">The parent is not a <see cref="StateMachine"/>.</exception>
    public StateMachine Machine
    {
        get => _machine ??= GetParentOrNull<StateMachine>()
            ?? throw new InvalidOperationException($"State '{Name}' must be a direct child of a StateMachine.");
        internal set => _machine = value;
    }

    /// <summary>Called when the machine switches into this state. Requesting another transition from here is allowed.</summary>
    /// <param name="previous">The state being left, or <c>null</c> for the initial state.</param>
    public virtual void Enter(State? previous)
    {
    }

    /// <summary>Called when the machine switches out of this state. Transitions requested from here are ignored.</summary>
    /// <param name="next">The state being entered.</param>
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
