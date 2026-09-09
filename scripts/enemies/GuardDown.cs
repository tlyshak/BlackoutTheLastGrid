using BlackoutLastGrid.Core;

namespace BlackoutLastGrid.Enemies;

/// <summary>Floored by a knockdown hit: lies on its side, invulnerable (<see cref="Guard.TakeHit"/> ignores hits), while the knockback decays; gets up into Approach after <see cref="Guard.DownDuration"/>.</summary>
public partial class GuardDown : GuardState
{
    private float _elapsed;

    /// <inheritdoc/>
    public override void Enter(State? previous)
    {
        _elapsed = 0f;
        Guard.ReleaseAttackSlot();
        Guard.SetDown(true);
    }

    /// <inheritdoc/>
    public override void Exit(State? next) => Guard.SetDown(false);

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        Guard.ApplyKnockbackStep(delta);

        _elapsed += (float)delta;
        if (_elapsed >= Guard.DownDuration)
        {
            TransitionTo(StateApproach);
        }
    }
}
