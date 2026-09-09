using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Enemies;

/// <summary>Knocked out at 0 HP: lies down dimmed and never gets up; only the last knockback still decays.</summary>
public partial class DummyKO : DummyState
{
    /// <inheritdoc/>
    public override void Enter(State? previous)
    {
        Dummy.SetDown(true);
        Dummy.SetDimmed(true);
        Dummy.MarkKnockedOut();
    }

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        if (Dummy.Velocity != Vector2.Zero)
        {
            Dummy.ApplyKnockbackStep(delta);
        }
    }
}
