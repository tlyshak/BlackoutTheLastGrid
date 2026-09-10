using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// Holding a scripted position (<see cref="Companion.HoldAt"/>): walks to
/// <see cref="Companion.HoldPosition"/>, emits <see cref="Companion.ArrivedEventHandler"/> once
/// inside <see cref="Companion.ArriveDistance"/> and then stands there facing the hero. The same
/// stuck watchdog applies, and it warps him onto the held position — a scripted beat must never
/// stall because he caught a corner on the way.
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

        if (offset.LengthSquared() <= Companion.ArriveDistance * Companion.ArriveDistance)
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
