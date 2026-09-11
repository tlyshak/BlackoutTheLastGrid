using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// Trailing the hero: walks to <see cref="Companion.FollowPoint"/> at
/// <see cref="Companion.MoveSpeed"/>, hurries at <see cref="Companion.CatchUpSpeed"/> past
/// <see cref="Companion.CatchUpDistance"/>, and stands still (facing the hero) inside
/// <see cref="Companion.FollowDistance"/>. Runs two of the three anti-stuck failsafes: a warp when
/// the follow point is farther than <see cref="Companion.WarpDistance"/>, and a warp when he has
/// asked to walk without moving for <see cref="Companion.StuckSeconds"/>.
/// </summary>
public partial class CompanionFollow : CompanionState
{
    /// <inheritdoc/>
    public override void Enter(State? previous) => Companion.ClearStuck();

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        if (Companion.ActiveTarget is not { } target)
        {
            Companion.Stop();
            return;
        }

        Vector2 point = Companion.FollowPoint;
        Vector2 offset = point - Companion.GlobalPosition;
        float distanceSquared = offset.LengthSquared();

        // Failsafe 1: half a screen behind (a sealed drift, a warp of the hero) — appear at once.
        if (distanceSquared > Companion.WarpDistance * Companion.WarpDistance)
        {
            Companion.WarpBehind();
            return;
        }

        if (distanceSquared <= Companion.FollowDistance * Companion.FollowDistance)
        {
            Companion.Stop();
            Companion.FaceTowards(target.GlobalPosition.X - Companion.GlobalPosition.X);
            return;
        }

        float speed = distanceSquared >= Companion.CatchUpDistance * Companion.CatchUpDistance
            ? Companion.CatchUpSpeed
            : Companion.MoveSpeed;

        Vector2 velocity = Companion.VelocityTowards(point, delta, speed);
        Companion.FaceTowards(velocity.X);
        Companion.Move(velocity, delta);

        // Failsafe 2: wedged in the geometry — recover before the player can notice him missing.
        if (Companion.IsStuck)
        {
            Companion.WarpBehind();
        }
    }
}
