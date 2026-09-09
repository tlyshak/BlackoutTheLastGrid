using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Enemies;

/// <summary>Knocked out at 0 HP: gives up its attack slot, falls (<c>ko</c> animation), dims and never gets up; only the last knockback still decays.</summary>
public partial class GuardKO : GuardState
{
    /// <inheritdoc/>
    public override void Enter(State? previous)
    {
        Guard.ReleaseAttackSlot();
        Guard.PlayAnimation(AnimKO);
        Guard.SetDimmed(true);
        Guard.MarkKnockedOut();
    }

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        if (Guard.Velocity != Vector2.Zero)
        {
            Guard.ApplyKnockbackStep(delta);
        }
    }
}
