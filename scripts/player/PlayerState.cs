using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// Base for the hero's states: resolves the owning <see cref="Player"/> (the state machine's
/// parent) once, and shares the animation names.
/// </summary>
public abstract partial class PlayerState : State
{
    /// <summary>Animation names looked up on the player's <c>SpriteFrames</c>.</summary>
    protected static readonly StringName AnimIdle = "idle";

    /// <inheritdoc cref="AnimIdle"/>
    protected static readonly StringName AnimWalk = "walk";

    /// <inheritdoc cref="AnimIdle"/>
    protected static readonly StringName AnimJump = "jump";

    /// <summary>State names used for transitions.</summary>
    protected const string StateIdle = "Idle";

    /// <inheritdoc cref="StateIdle"/>
    protected const string StateMove = "Move";

    /// <inheritdoc cref="StateIdle"/>
    protected const string StateJump = "Jump";

    /// <summary>The hero this state controls.</summary>
    protected Player Player { get; private set; } = null!;

    /// <inheritdoc/>
    public override void _Ready() => Player = Machine.GetParent<Player>();
}
