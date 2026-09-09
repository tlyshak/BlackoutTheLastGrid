using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>Knocked out: plays <c>ko</c>, slides to a stop and stays down (scene restart comes in T-06).</summary>
public partial class PlayerKO : PlayerState
{
    private static readonly StringName Animation = "ko";

    /// <inheritdoc/>
    public override void Enter(State? previous) => Player.PlayAnimation(Animation, AnimIdle);

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        if (Player.Velocity != Vector2.Zero)
        {
            Player.ApplyKnockbackStep(delta);
        }
    }
}
