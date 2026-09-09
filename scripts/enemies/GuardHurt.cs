using BlackoutLastGrid.Core;

namespace BlackoutLastGrid.Enemies;

/// <summary>Flinching from a hit: gives up any attack slot, plays <c>hurt</c>, slides back with the knockback, then resumes Approach after <see cref="Guard.HurtDuration"/>.</summary>
public partial class GuardHurt : GuardState
{
    private float _elapsed;

    /// <inheritdoc/>
    public override void Enter(State? previous)
    {
        _elapsed = 0f;
        Guard.ReleaseAttackSlot();
        Guard.PlayAnimation(AnimHurt);
    }

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        Guard.ApplyKnockbackStep(delta);

        _elapsed += (float)delta;
        if (_elapsed >= Guard.HurtDuration)
        {
            TransitionTo(StateApproach);
        }
    }
}
