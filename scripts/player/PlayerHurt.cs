using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// Hit reaction: plays <c>hurt</c>, slides with the knockback, keeps falling if the hit landed
/// mid-jump, then returns to Idle once both the animation and the fall are over.
/// A second hit re-enters this state via <see cref="StateMachine.Restart"/>, restarting the stun.
/// </summary>
public partial class PlayerHurt : PlayerState
{
    /// <inheritdoc/>
    public override void Enter(State? previous) => Player.PlayAnimation(AnimHurt, AnimIdle);

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        Player.ApplyKnockbackStep(delta);
        if (Player.IsAirborne)
        {
            Player.IntegrateJump(delta);
        }

        if (!Player.IsAnimationPlaying(AnimHurt) && !Player.IsAirborne)
        {
            TransitionTo(StateIdle);
        }
    }
}
