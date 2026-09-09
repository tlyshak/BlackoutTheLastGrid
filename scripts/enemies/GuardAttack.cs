using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Enemies;

/// <summary>
/// The punch: plays <c>attack</c> (its first <see cref="Guard.TelegraphTime"/> is the wind-up,
/// then the method track opens the <c>Hitbox</c> with <see cref="Guard.CurrentAttack"/>). When
/// the animation ends — or the state is interrupted by Hurt/Down/KO — the attack slot goes back
/// to the director and the cooldown starts; a finished attack returns to Approach.
/// </summary>
public partial class GuardAttack : GuardState
{
    /// <inheritdoc/>
    public override void Enter(State? previous)
    {
        Guard.Stop();
        Guard.CurrentAttack = new HitInfo(
            Guard.Damage,
            Guard.Knockback * Guard.Facing,
            false,
            Guard.HitStopFrames,
            Guard.DepthTolerance,
            Guard.GlobalPosition.Y);
        Guard.PlayAnimation(AnimAttack);
    }

    /// <inheritdoc/>
    public override void Exit(State? next)
    {
        Guard.HitboxOff();
        if (Guard.IsAnimationPlaying(AnimAttack))
        {
            Guard.ResetPose();   // interrupted mid-swing: put the fist back
        }

        Guard.ReleaseAttackSlot();
        Guard.StartCooldown();
    }

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        // IsPlaying() only: comparing CurrentAnimation would allocate a string per tick per guard.
        if (Guard.AnimationPlayer.IsPlaying())
        {
            return;
        }

        TransitionTo(StateApproach);
    }
}
