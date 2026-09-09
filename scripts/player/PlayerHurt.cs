using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>Hit reaction: plays <c>hurt</c>, slides with the knockback, then returns to Idle.</summary>
public partial class PlayerHurt : PlayerState
{
    private static readonly StringName Animation = "hurt";

    /// <inheritdoc/>
    public override void Enter(State? previous) => Player.PlayAnimation(Animation, AnimIdle);

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        Player.ApplyKnockbackStep(delta);
        if (!Player.IsAnimationPlaying(Animation))
        {
            TransitionTo(StateIdle);
        }
    }
}
