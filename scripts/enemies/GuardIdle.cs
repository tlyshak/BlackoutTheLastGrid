using BlackoutLastGrid.Core;

namespace BlackoutLastGrid.Enemies;

/// <summary>
/// Standing at its post. Each physics tick checks whether the target is already known or
/// visible (<see cref="Guard.CanSeeTarget"/>), then notices it and goes to Approach. Without a
/// target, or with a knocked-out one, stays put.
/// </summary>
public partial class GuardIdle : GuardState
{
    /// <inheritdoc/>
    public override void Enter(State? previous) => Guard.Stop();

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        if (!Guard.HasActiveTarget)
        {
            return;
        }

        if (Guard.IsAware || Guard.CanSeeTarget())
        {
            Guard.SetAware();
            TransitionTo(StateApproach);
        }
    }
}
