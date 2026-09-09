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
    /// <summary>Speed above which the guard plays <c>walk</c> instead of <c>idle</c>, in px/s.</summary>
    [Export] public float WalkAnimationMinSpeed { get; set; } = 8f;

    /// <summary><c>null</c> until the first gait decision of this visit, so it always starts an animation once.</summary>
    private bool? _walking;

    /// <inheritdoc/>
    public override void Enter(State? previous) => _walking = null;

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
            Vector2 holdVelocity = Guard.VelocityTowards(holdPoint, delta);
            UpdateGait(holdVelocity, delta);
            Guard.Move(holdVelocity);
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
        UpdateGait(velocity, delta);
        Guard.Move(velocity);
    }

    /// <summary>
    /// Switches between the looping <c>walk</c> and <c>idle</c> animations, and only on a change
    /// of gait — a guard holding its distance must not moonwalk, and restarting an animation
    /// every tick would reset it to frame 0 forever.
    /// </summary>
    /// <param name="velocity">Velocity the guard is about to move with, in px/s.</param>
    /// <param name="delta">Physics step in seconds; 0 during hit-stop, when nothing moves anyway.</param>
    private void UpdateGait(Vector2 velocity, double delta)
    {
        if (delta <= 0.0)
        {
            return;   // hit-stop: the animation player is frozen and every velocity reads as zero
        }

        bool walking = velocity.LengthSquared() >= WalkAnimationMinSpeed * WalkAnimationMinSpeed;
        if (_walking == walking)
        {
            return;
        }

        _walking = walking;
        Guard.PlayAnimation(walking ? AnimWalk : AnimIdle);
    }
}
