using BlackoutLastGrid.Core;

namespace BlackoutLastGrid.Enemies;

/// <summary>
/// Standing at its post, breathing. Each physics tick checks whether the target is already known
/// or visible (<see cref="Guard.CanSeeTarget"/>), then notices it and goes to Approach. Without a
/// target, or with a knocked-out one, stays put.
/// </summary>
/// <remarks>
/// This is the initial state, so <see cref="Enter"/> runs from <c>StateMachine._Ready</c> —
/// before <c>Guard._Ready</c>. Starting the looping <c>idle</c> animation here is only safe
/// because <c>AnimationPlayer</c> is an earlier sibling in <c>Guard.tscn</c> and is therefore
/// ready first; do not reorder those nodes.
/// </remarks>
public partial class GuardIdle : GuardState
{
    /// <inheritdoc/>
    public override void Enter(State? previous)
    {
        Guard.Stop();
        Guard.PlayAnimation(AnimIdle);
    }

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
