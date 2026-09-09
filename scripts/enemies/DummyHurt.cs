using BlackoutLastGrid.Core;

namespace BlackoutLastGrid.Enemies;

/// <summary>Flinching from a light hit: slides back with the knockback, then returns to Idle after <see cref="Dummy.HurtDuration"/>.</summary>
public partial class DummyHurt : DummyState
{
    private float _elapsed;

    /// <inheritdoc/>
    public override void Enter(State? previous) => _elapsed = 0f;

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        Dummy.ApplyKnockbackStep(delta);

        _elapsed += (float)delta;
        if (_elapsed >= Dummy.HurtDuration)
        {
            TransitionTo(StateIdle);
        }
    }
}
