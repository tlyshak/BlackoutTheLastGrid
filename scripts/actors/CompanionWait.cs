using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// Holding a scripted position (<see cref="Companion.HoldAt"/>): walks to
/// <see cref="Companion.HoldPosition"/>, emits <see cref="Companion.ArrivedEventHandler"/> once
/// inside <see cref="Companion.ArriveDistance"/> and then stands there facing the hero. All three
/// failsafes are live here too, each aimed at the held spot instead of the follow point: a hold
/// farther away than <see cref="Companion.WarpDistance"/> is taken at once instead of walked to
/// (the walk would cross whatever a <see cref="Levels.CaveIn"/> has sealed), the stuck watchdog
/// warps him onto the spot, and <see cref="Companion.OnHeroRelocated"/> puts him on the spot when
/// the hero is teleported half a screen away. A hold is a world position: nothing moves it with
/// him, and a level that wants him elsewhere after a respawn re-issues <see cref="Companion.HoldAt"/>.
/// A scripted beat must never stall because he caught a corner on the way.
/// </summary>
public partial class CompanionWait : CompanionState
{
    private bool _arrived;

    /// <inheritdoc/>
    public override void Enter(State? previous)
    {
        _arrived = false;
        Companion.ClearStuck();
    }

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        Vector2 point = Companion.HoldPosition;
        Vector2 offset = point - Companion.GlobalPosition;
        float distanceSquared = offset.LengthSquared();

        // Failsafe 1: the held spot is half a screen away (the level warped him, or the hold was
        // issued from across the mine) — appear there instead of walking through sealed geometry.
        if (distanceSquared > Companion.WarpDistance * Companion.WarpDistance)
        {
            Companion.WarpTo(point);
            return;
        }

        if (distanceSquared <= Companion.ArriveDistance * Companion.ArriveDistance)
        {
            Companion.Stop();

            if (Companion.ActiveTarget is { } target)
            {
                Companion.FaceTowards(target.GlobalPosition.X - Companion.GlobalPosition.X);
            }

            if (!_arrived)
            {
                _arrived = true;
                Companion.NotifyArrived();
            }

            return;
        }

        Vector2 velocity = Companion.VelocityTowards(point, delta, Companion.MoveSpeed);
        Companion.FaceTowards(velocity.X);
        Companion.Move(velocity, delta);

        if (Companion.IsStuck)
        {
            Companion.WarpTo(point);
        }
    }
}
