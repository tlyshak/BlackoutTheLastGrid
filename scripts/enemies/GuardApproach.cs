using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Enemies;

/// <summary>
/// Closing in on the target along the floor plane: faces it, aligns depth (Y) within
/// <see cref="Guard.DepthTolerance"/> and walks along X until <see cref="Guard.AttackRange"/>
/// while an attack slot can be had, or keeps <see cref="Guard.HoldDistance"/> when the
/// <see cref="EnemyDirector"/> is full. In range, aligned, cooled down and granted a slot → Attack.
/// Loses the target (freed or knocked out) → Idle.
/// </summary>
public partial class GuardApproach : GuardState
{
    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        if (Guard.ActiveTarget is not { } target)
        {
            Guard.Stop();
            TransitionTo(StateIdle);
            return;
        }

        Vector2 targetPosition = target.GlobalPosition;
        Vector2 position = Guard.GlobalPosition;
        float dx = targetPosition.X - position.X;
        float absDx = Mathf.Abs(dx);
        int side = dx >= 0f ? 1 : -1;   // the target lies on this side of the guard
        Guard.FaceTowards(dx);

        if (!Guard.CanTakeAttackSlot)
        {
            Vector2 holdPoint = new(targetPosition.X - side * Guard.HoldDistance, targetPosition.Y);
            Guard.Move(Guard.VelocityTowards(holdPoint, delta));
            return;
        }

        bool inRange = absDx <= Guard.AttackRange && Mathf.Abs(targetPosition.Y - position.Y) <= Guard.DepthTolerance;
        if (inRange && Guard.IsCooldownOver && Guard.TryAcquireAttackSlot())
        {
            Guard.Stop();
            TransitionTo(StateAttack);
            return;
        }

        // Full speed along X until in range (a step past the threshold is fine), exact on Y.
        Vector2 velocity = Guard.VelocityTowards(targetPosition, delta);
        velocity.X = absDx > Guard.AttackRange ? side * Guard.MoveSpeed : 0f;
        Guard.Move(velocity);
    }
}
