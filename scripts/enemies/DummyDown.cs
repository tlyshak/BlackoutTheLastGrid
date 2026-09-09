using BlackoutLastGrid.Core;

namespace BlackoutLastGrid.Enemies;

/// <summary>Floored by a knockdown hit: lies on its side while the knockback decays, gets up to Idle after <see cref="Dummy.DownDuration"/>.</summary>
public partial class DummyDown : DummyState
{
    private float _elapsed;

    /// <inheritdoc/>
    public override void Enter(State? previous)
    {
        _elapsed = 0f;
        Dummy.SetDown(true);
    }

    /// <inheritdoc/>
    public override void Exit(State? next) => Dummy.SetDown(false);

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        Dummy.ApplyKnockbackStep(delta);

        _elapsed += (float)delta;
        if (_elapsed >= Dummy.DownDuration)
        {
            TransitionTo(StateIdle);
        }
    }
}
