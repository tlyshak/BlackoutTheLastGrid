using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// Base for the hero's states: resolves the owning <see cref="Player"/> (the state machine's
/// parent) once, and shares the animation and state names.
/// </summary>
public abstract partial class PlayerState : State
{
    /// <summary>Animation names looked up on the player's <c>SpriteFrames</c>.</summary>
    protected static readonly StringName AnimIdle = "idle";

    /// <inheritdoc cref="AnimIdle"/>
    protected static readonly StringName AnimWalk = "walk";

    /// <inheritdoc cref="AnimIdle"/>
    protected static readonly StringName AnimJump = "jump";

    /// <inheritdoc cref="AnimIdle"/>
    protected static readonly StringName AnimHurt = "hurt";

    /// <inheritdoc cref="AnimIdle"/>
    protected static readonly StringName AnimKO = "ko";

    /// <summary>State (node) names used for transitions.</summary>
    public const string StateIdle = "Idle";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateMove = "Move";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateJump = "Jump";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateLightAttack1 = "LightAttack1";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateHeavyAttack = "HeavyAttack";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateHurt = "Hurt";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateKO = "KO";

    /// <summary>The hero this state controls.</summary>
    protected Player Player { get; private set; } = null!;

    /// <inheritdoc/>
    public override void _Ready() => Player = Machine.GetParent<Player>();

    /// <summary>Shared grounded transitions: heavy/light attack or jump. Returns <c>true</c> if a transition happened.</summary>
    protected bool TryStartAction()
    {
        if (Player.HeavyPressed)
        {
            TransitionTo(StateHeavyAttack);
            return true;
        }

        if (Player.AttackPressed)
        {
            TransitionTo(StateLightAttack1);
            return true;
        }

        if (Player.JumpPressed)
        {
            TransitionTo(StateJump);
            return true;
        }

        return false;
    }
}
