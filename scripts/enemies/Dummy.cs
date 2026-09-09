using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Enemies;

/// <summary>
/// Training dummy: a hittable body with HP that reacts to hits (flash, knockback, knockdown) and
/// stays down once its HP reaches 0. Never attacks. Behaviour is driven by the child
/// <see cref="StateMachine"/> (Idle / Hurt / Down / KO); this class owns HP, the hurt flash and
/// the knockback integration. The node's origin is the contact point with the floor (Y = depth).
/// </summary>
public partial class Dummy : CharacterBody2D, IHittable
{
    private static readonly Color DimmedColor = new(0.35f, 0.35f, 0.4f);

    /// <summary>Emitted after every hit that was applied, with the remaining HP.</summary>
    [Signal]
    public delegate void DamagedEventHandler(float hp);

    /// <summary>Emitted once, when the dummy enters KO.</summary>
    [Signal]
    public delegate void KnockedOutEventHandler();

    /// <summary>Hit points at start.</summary>
    [Export] public float MaxHp { get; set; } = 30f;

    /// <summary>Deceleration of the knockback velocity, in px/s².</summary>
    [Export] public float KnockbackFriction { get; set; } = 900f;

    /// <summary>Time spent in Hurt before returning to Idle, in seconds.</summary>
    [Export] public float HurtDuration { get; set; } = 0.25f;

    /// <summary>Time spent on the floor after a knockdown before getting up, in seconds.</summary>
    [Export] public float DownDuration { get; set; } = 1f;

    /// <summary>Modulate applied to <see cref="Visual"/> at the moment of a hit (placeholder for a flash shader).</summary>
    [Export] public Color FlashColor { get; set; } = new(2f, 2f, 2f);

    /// <summary>Time the flash takes to fade back, in seconds.</summary>
    [Export] public float FlashDuration { get; set; } = 0.12f;

    /// <summary>Distance from the origin (feet) up to the visual's pivot, in px (half the sprite height).</summary>
    [Export] public float SpriteFeetOffset { get; set; } = 36f;

    /// <summary>Container for the body art; flashed on hit, rotated when down, dimmed in KO.</summary>
    [Export] public Node2D Visual { get; set; } = null!;

    /// <summary>Debug label above the head showing the remaining HP.</summary>
    [Export] public Label HpLabel { get; set; } = null!;

    /// <summary>Behaviour state machine (Idle / Hurt / Down / KO).</summary>
    [Export] public StateMachine StateMachine { get; set; } = null!;

    private Tween? _flashTween;
    private bool _dimmed;

    /// <summary>Remaining hit points; starts at <see cref="MaxHp"/>.</summary>
    public float Hp { get; private set; }

    /// <summary><c>true</c> once the dummy has entered KO; hits are ignored from then on.</summary>
    public bool IsKnockedOut { get; private set; }

    /// <summary>Name of the active state, for debug labels and tests.</summary>
    public string CurrentStateName => StateMachine.CurrentState?.Name ?? string.Empty;

    /// <inheritdoc/>
    public override void _Ready()
    {
        Hp = MaxHp;
        Visual.Position = new Vector2(0f, -SpriteFeetOffset);
        UpdateHpLabel();
    }

    /// <summary>
    /// Applies one hit: knockback velocity, HP loss, flash and the matching state (KO at 0 HP,
    /// Down for a knockdown hit, else Hurt). The depth check already happened in <see cref="Hitbox"/>.
    /// </summary>
    /// <param name="hit">Damage, knockback and timing of the hit.</param>
    /// <returns><c>false</c> when the dummy is already knocked out and the hit was ignored.</returns>
    public bool TakeHit(in HitInfo hit)
    {
        if (IsKnockedOut)
        {
            return false;
        }

        Velocity = new Vector2(hit.Knockback, 0f);
        Hp = Mathf.Max(0f, Hp - hit.Damage);
        UpdateHpLabel();
        EmitSignalDamaged(Hp);

        StateMachine.TransitionTo(Hp <= 0f ? DummyState.StateKO : hit.Knockdown ? DummyState.StateDown : DummyState.StateHurt);
        Flash();
        return true;
    }

    /// <summary>Decays the knockback velocity with <see cref="KnockbackFriction"/> and moves for one physics step.</summary>
    /// <param name="delta">Physics step in seconds.</param>
    public void ApplyKnockbackStep(double delta)
    {
        Velocity = Velocity.MoveToward(Vector2.Zero, KnockbackFriction * (float)delta);
        MoveAndSlide();
    }

    /// <summary>Lays the visual on its side (knockdown) or stands it back up.</summary>
    /// <param name="down"><c>true</c> to rotate the visual by 90°.</param>
    public void SetDown(bool down) => Visual.Rotation = down ? Mathf.Pi / 2f : 0f;

    /// <summary>Darkens the visual (KO) or restores its normal colour; cancels a running flash.</summary>
    /// <param name="dimmed"><c>true</c> to dim.</param>
    public void SetDimmed(bool dimmed)
    {
        _dimmed = dimmed;
        KillFlash();
        Visual.Modulate = RestingModulate;
    }

    /// <summary>Marks the dummy as knocked out and emits <see cref="KnockedOutEventHandler"/> once. Called by the KO state.</summary>
    public void MarkKnockedOut()
    {
        if (IsKnockedOut)
        {
            return;
        }

        IsKnockedOut = true;
        EmitSignalKnockedOut();
    }

    private Color RestingModulate => _dimmed ? DimmedColor : Colors.White;

    private void Flash()
    {
        KillFlash();
        Visual.Modulate = FlashColor;
        _flashTween = CreateTween();
        _flashTween.TweenProperty(Visual, "modulate", RestingModulate, FlashDuration);
    }

    private void KillFlash()
    {
        if (_flashTween is not null && _flashTween.IsValid())
        {
            _flashTween.Kill();
        }

        _flashTween = null;
    }

    private void UpdateHpLabel() => HpLabel.Text = $"HP {Hp:0}";
}
