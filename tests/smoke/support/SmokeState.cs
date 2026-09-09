using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Tests;

/// <summary>
/// Minimal <see cref="State"/> used only by smoke tests (tests/smoke/core_statemachine.gd).
/// Records lifecycle calls and can redirect to another state from <see cref="Enter"/>.
/// </summary>
public partial class SmokeState : State
{
    /// <summary>When non-empty, <see cref="Enter"/> immediately transitions to this state.</summary>
    [Export]
    public string RedirectOnEnter { get; set; } = string.Empty;

    /// <summary>Whether <see cref="State.Machine"/> was resolvable inside <c>_Ready</c>.</summary>
    public bool MachineAvailableAtReady { get; private set; }

    /// <summary>Number of <see cref="Enter"/> calls.</summary>
    public int EnterCount { get; private set; }

    /// <summary>Number of <see cref="Exit"/> calls.</summary>
    public int ExitCount { get; private set; }

    /// <inheritdoc/>
    public override void _Ready() => MachineAvailableAtReady = Machine is not null;

    /// <inheritdoc/>
    public override void Enter(State? previous)
    {
        EnterCount++;
        if (RedirectOnEnter.Length > 0)
        {
            TransitionTo(RedirectOnEnter);
        }
    }

    /// <inheritdoc/>
    public override void Exit(State? next) => ExitCount++;
}
