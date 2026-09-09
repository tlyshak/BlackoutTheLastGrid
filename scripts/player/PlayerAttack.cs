using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// One attack of the hero (a light-combo step or the heavy attack). Plays
/// <see cref="AnimationName"/> on the player's <c>AnimationPlayer</c>; the animation's method
/// track opens and closes the <c>Hitbox</c> with the parameters exported here. When the animation
/// ends, continues into <see cref="NextCombo"/> if <c>attack</c> was pressed after
/// <see cref="ComboWindowStart"/>, else returns to Idle.
/// </summary>
public partial class PlayerAttack : PlayerState
{
    /// <summary>Animation on the player's AnimationPlayer (light_1, light_2, light_3, heavy).</summary>
    [Export] public StringName AnimationName { get; set; } = "light_1";

    /// <summary>Damage dealt per connected hit (hp).</summary>
    [Export] public float Damage { get; set; } = 5f;

    /// <summary>Horizontal push applied to the target, in px/s (signed by facing at hit time).</summary>
    [Export] public float Knockback { get; set; } = 60f;

    /// <summary><c>true</c> if the hit floors the target.</summary>
    [Export] public bool Knockdown { get; set; }

    /// <summary>Hit-stop requested on a connected hit, in physics frames.</summary>
    [Export] public int HitStopFrames { get; set; } = 4;

    /// <summary>State to chain into when <c>attack</c> is buffered; empty ends the combo.</summary>
    [Export] public string NextCombo { get; set; } = string.Empty;

    /// <summary>Seconds into the animation after which an <c>attack</c> press is buffered for <see cref="NextCombo"/>.</summary>
    [Export] public float ComboWindowStart { get; set; } = 0.1f;

    private bool _buffered;

    /// <inheritdoc/>
    public override void Enter(State? previous)
    {
        _buffered = false;
        Player.CurrentAttack = new HitInfo(
            Damage,
            Knockback * Player.Facing,
            Knockdown,
            HitStopFrames,
            Player.DepthTolerance,
            Player.GlobalPosition.Y);
        if (!Player.AnimationPlayer.HasAnimation(AnimationName))
        {
            GD.PushWarning($"{Name}: AnimationPlayer has no animation '{AnimationName}'; the attack ends immediately.");
        }

        Player.PlayAnimation(AnimationName);
    }

    /// <inheritdoc/>
    public override void Exit(State? next)
    {
        Player.HitboxOff();
        if (Player.IsAnimationPlaying(AnimationName))
        {
            Player.ResetPose();   // interrupted mid-swing (Hurt/KO): put the fist back
        }
    }

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        if (Player.IsAnimationPlaying(AnimationName))
        {
            // The combo window opens either at ComboWindowStart or as soon as the hit window is
            // open — a press during the hit-stop of this attack (animation frozen) still counts.
            bool windowOpen = Player.AnimationTime >= ComboWindowStart || Player.Hitbox.IsActive;
            if (NextCombo.Length > 0 && windowOpen && Player.AttackPressed)
            {
                _buffered = true;
            }

            Player.ApplyFloorMove(Vector2.Zero);
            return;
        }

        TransitionTo(_buffered && NextCombo.Length > 0 ? NextCombo : StateIdle);
    }
}
