using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Enemies;

/// <summary>
/// Base for the guard's states: resolves the owning <see cref="Guard"/> (the state machine's
/// parent) once, and shares the animation and state names.
/// </summary>
public abstract partial class GuardState : State
{
    /// <summary>Animation names on the guard's <c>AnimationPlayer</c>.</summary>
    protected static readonly StringName AnimAttack = "attack";

    /// <inheritdoc cref="AnimAttack"/>
    protected static readonly StringName AnimHurt = "hurt";

    /// <inheritdoc cref="AnimAttack"/>
    protected static readonly StringName AnimKO = "ko";

    /// <summary>State (node) names used for transitions.</summary>
    public const string StateIdle = "Idle";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateApproach = "Approach";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateAttack = "Attack";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateHurt = "Hurt";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateDown = "Down";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateKO = "KO";

    /// <summary>The guard this state controls.</summary>
    protected Guard Guard { get; private set; } = null!;

    /// <inheritdoc/>
    public override void _Ready() => Guard = Machine.GetParent<Guard>();
}
