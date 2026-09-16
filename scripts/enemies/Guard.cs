using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Enemies;

/// <summary>
/// The rank-and-file enemy: notices the hero (at full range when the hero is lit, at
/// <see cref="DarkPerceptionFactor"/> of it and only in front of him when unlit), walks up on
/// the floor plane, telegraphs and punches, flinches, falls and stays down when out of HP.
/// Behaviour is driven by the child <see cref="StateMachine"/> (Idle / Approach / Attack / Hurt /
/// Down / KO); this class owns HP, perception, the attack slot held with the
/// <see cref="EnemyDirector"/>, the attack cooldown, movement helpers and the visual (flip,
/// flash, dim). The node's origin is the contact point with the floor (Y = depth).
/// </summary>
public partial class Guard : CharacterBody2D, IHittable
{
    private static readonly StringName ResetAnimation = "RESET";
    private static readonly StringName DownAnimation = "down";

    /// <summary>Emitted after every hit that was applied, with the remaining HP.</summary>
    [Signal]
    public delegate void DamagedEventHandler(float hp);

    /// <summary>Emitted once, when the guard enters KO.</summary>
    [Signal]
    public delegate void KnockedOutEventHandler();

    /// <summary>Emitted once, when the guard becomes aware of its target (seen or hit).</summary>
    [Signal]
    public delegate void NoticedEventHandler();

    /// <summary>Emitted after the <see cref="DropScene"/> instance entered the tree (levels connect its own signals from here).</summary>
    [Signal]
    public delegate void DroppedEventHandler(Node2D drop);

    /// <summary>Hit points at start.</summary>
    [Export] public float MaxHp { get; set; } = 30f;

    /// <summary>Walk speed along X on the floor plane, in px/s.</summary>
    [Export] public float MoveSpeed { get; set; } = 140f;

    /// <summary>Depth (Y) speed as a fraction of <see cref="MoveSpeed"/>.</summary>
    [Export] public float DepthSpeedFactor { get; set; } = 0.75f;

    /// <summary>|ΔX| to the target at which Attack may start, in px (the punch reaches ~48 px).</summary>
    [Export] public float AttackRange { get; set; } = 46f;

    /// <summary>Max |ΔY| between the guard and its target for a hit (given or taken) to connect, in px.</summary>
    [Export] public float DepthTolerance { get; set; } = 12f;

    /// <summary>Energy drained from the hero per connected punch.</summary>
    [Export] public float Damage { get; set; } = 8f;

    /// <summary>Horizontal push applied to the hero, in px/s (signed by facing at attack time).</summary>
    [Export] public float Knockback { get; set; } = 120f;

    /// <summary>Hit-stop requested on a connected punch, in physics frames.</summary>
    [Export] public int HitStopFrames { get; set; } = 4;

    /// <summary>Seconds after an attack (finished or interrupted) before the next one may start.</summary>
    [Export] public float AttackCooldown { get; set; } = 0.8f;

    /// <summary>Wind-up before the punch connects, in seconds. Documented here; the <c>attack</c> animation carries it (its hitbox opens at this time).</summary>
    [Export] public float TelegraphTime { get; set; } = 0.3f;

    /// <summary>Distance at which an Idle guard notices a lit hero, in px.</summary>
    [Export] public float PerceptionRange { get; set; } = 420f;

    /// <summary>Fraction of <see cref="PerceptionRange"/> that applies to an unlit hero (who must also be in front).</summary>
    [Export] public float DarkPerceptionFactor { get; set; } = 0.5f;

    /// <summary>Damage multiplier for a hit taken while still unaware (the first hit from the dark).</summary>
    [Export] public float DarkFirstHitMultiplier { get; set; } = 2f;

    /// <summary>Time spent in Hurt before resuming, in seconds.</summary>
    [Export] public float HurtDuration { get; set; } = 0.25f;

    /// <summary>Time spent on the floor (invulnerable) after a knockdown, in seconds.</summary>
    [Export] public float DownDuration { get; set; } = 1f;

    /// <summary>Deceleration of the knockback velocity, in px/s².</summary>
    [Export] public float KnockbackFriction { get; set; } = 900f;

    /// <summary>Modulate applied to <see cref="Visual"/> at the moment of a hit (placeholder for a flash shader).</summary>
    [Export] public Color FlashColor { get; set; } = new(2f, 2f, 2f);

    /// <summary>Time the flash takes to fade back, in seconds.</summary>
    [Export] public float FlashDuration { get; set; } = 0.12f;

    /// <summary>Modulate applied to <see cref="Visual"/> once knocked out.</summary>
    [Export] public Color DimmedColor { get; set; } = new(0.35f, 0.35f, 0.4f);

    /// <summary>Distance from the origin (feet) up to the visual's pivot, in px (half the sprite height).</summary>
    [Export] public float SpriteFeetOffset { get; set; } = 36f;

    /// <summary>|ΔX| kept from the target while no attack slot is free, in px.</summary>
    [Export] public float HoldDistance { get; set; } = 120f;

    /// <summary>+1 facing right, -1 facing left. Set in the scene for a placed guard; updated by the states at runtime.</summary>
    [Export] public int Facing { get; set; } = 1;

    /// <summary>
    /// Scene instanced once when the guard is knocked out — the powerbank off its belt
    /// (a battery). Added as a <b>sibling</b> at the guard's position plus
    /// <see cref="DropOffset"/>, so it y-sorts with the body under the same parent. <c>null</c>
    /// (the default) drops nothing and leaves the guard exactly as it was.
    /// </summary>
    [Export] public PackedScene? DropScene { get; set; }

    /// <summary>Px added to the guard's position for the drop — just in front of the fallen body, clear of the HP label.</summary>
    [Export] public Vector2 DropOffset { get; set; } = new(0f, 6f);

    /// <summary>Container for the body art; flipped by facing, flashed on hit, rotated when down, dimmed in KO.</summary>
    [Export] public Node2D Visual { get; set; } = null!;

    /// <summary>The punch area (under <see cref="Visual"/> so it flips with facing).</summary>
    [Export] public Hitbox Hitbox { get; set; } = null!;

    /// <summary>Debug label above the head showing the remaining HP.</summary>
    [Export] public Label HpLabel { get; set; } = null!;

    /// <summary>attack / hurt / ko / RESET; the attack's method track calls <see cref="HitboxOn"/>/<see cref="HitboxOff"/>.</summary>
    [Export] public AnimationPlayer AnimationPlayer { get; set; } = null!;

    /// <summary>Behaviour state machine (Idle / Approach / Attack / Hurt / Down / KO).</summary>
    [Export] public StateMachine StateMachine { get; set; } = null!;

    private Tween? _flashTween;
    private bool _dimmed;
    private bool _hasAttackSlot;
    private float _cooldownRemaining;

    /// <summary>The hero this guard hunts; <c>null</c> until <see cref="SetTarget"/> (a placed guard without a level stands idle).</summary>
    public Player? Target { get; private set; }

    /// <summary>Attack-slot arbiter shared by the level's enemies; <c>null</c> means no limit.</summary>
    public EnemyDirector? Director { get; private set; }

    /// <summary><c>true</c> once the guard has seen or been hit by its target.</summary>
    public bool IsAware { get; private set; }

    /// <summary>Remaining hit points; starts at <see cref="MaxHp"/>.</summary>
    public float Hp { get; private set; }

    /// <summary><c>true</c> once the guard has entered KO; hits are ignored from then on.</summary>
    public bool IsKnockedOut { get; private set; }

    /// <summary>Name of the active state, for debug labels and tests.</summary>
    public string CurrentStateName => StateMachine.CurrentState?.Name ?? string.Empty;

    /// <summary>Hit parameters of the punch in progress; set by the Attack state, read by <see cref="HitboxOn"/>.</summary>
    public HitInfo CurrentAttack { get; set; }

    /// <summary><c>true</c> while this guard holds an attack slot of the <see cref="Director"/>.</summary>
    public bool HasAttackSlot => _hasAttackSlot;

    /// <summary><c>true</c> when <see cref="AttackCooldown"/> has elapsed since the last attack.</summary>
    public bool IsCooldownOver => _cooldownRemaining <= 0f;

    /// <summary>
    /// <see cref="Target"/> while it is alive in the tree and not knocked out, else <c>null</c>.
    /// States read it once per tick instead of re-validating the target themselves.
    /// </summary>
    public Player? ActiveTarget =>
        Target is { } target && IsInstanceValid(target) && !target.IsQueuedForDeletion() && !target.IsKnockedOut ? target : null;

    /// <summary><c>true</c> while <see cref="ActiveTarget"/> is available.</summary>
    public bool HasActiveTarget => ActiveTarget is not null;

    /// <summary>
    /// <c>true</c> when an attack may be started as far as the slots go: this guard already holds
    /// one, there is no director, or the director has a free slot.
    /// </summary>
    public bool CanTakeAttackSlot => _hasAttackSlot || ActiveDirector is not { } director || director.HasFreeSlot;

    private EnemyDirector? ActiveDirector => Director is { } director && IsInstanceValid(director) ? director : null;

    /// <inheritdoc/>
    public override void _Ready()
    {
        Hp = MaxHp;
        Visual.Position = new Vector2(0f, -SpriteFeetOffset);
        Hitbox.Attacker = this;
        UpdateHpLabel();
        UpdateVisual();
    }

    /// <inheritdoc/>
    public override void _ExitTree() => ReleaseAttackSlot();

    /// <inheritdoc/>
    public override void _PhysicsProcess(double delta)
    {
        if (_cooldownRemaining > 0f)
        {
            _cooldownRemaining -= (float)delta;
        }
    }

    /// <summary>Gives the guard its prey and the slot arbiter. Called once by the spawner or the level, before or after <c>_Ready</c>.</summary>
    /// <param name="target">The hero to hunt.</param>
    /// <param name="director">The level's attack-slot director.</param>
    public void SetTarget(Player target, EnemyDirector director)
    {
        Target = target;
        Director = director;
    }

    /// <summary>
    /// Perception check for the Idle state: a lit target within <see cref="PerceptionRange"/> in
    /// any direction, or an unlit one within <see cref="PerceptionRange"/> × <see cref="DarkPerceptionFactor"/>
    /// on the side the guard is facing (an unlit hero behind the guard stays unseen).
    /// </summary>
    public bool CanSeeTarget()
    {
        if (ActiveTarget is not { } target)
        {
            return false;
        }

        Vector2 toTarget = target.GlobalPosition - GlobalPosition;
        float range = PerceptionRange;
        if (!target.IsLit)
        {
            range *= DarkPerceptionFactor;
            bool inFront = toTarget.X == 0f || Mathf.Sign(toTarget.X) == Facing;
            if (!inFront)
            {
                return false;
            }
        }

        return toTarget.LengthSquared() <= range * range;
    }

    /// <summary>Marks the guard aware of its target and emits <see cref="NoticedEventHandler"/> the first time.</summary>
    public void SetAware()
    {
        if (IsAware)
        {
            return;
        }

        IsAware = true;
        EmitSignalNoticed();
    }

    /// <summary>Turns towards <paramref name="dx"/> (the target's X minus the guard's); 0 keeps the current facing.</summary>
    /// <param name="dx">Signed horizontal offset to face.</param>
    public void FaceTowards(float dx)
    {
        if (dx != 0f)
        {
            Facing = dx > 0f ? 1 : -1;
        }

        UpdateVisual();
    }

    /// <summary>Moves with <paramref name="velocity"/> for one physics step (walls on the World layer are resolved by <see cref="CharacterBody2D.MoveAndSlide"/>).</summary>
    /// <param name="velocity">Floor-plane velocity in px/s.</param>
    public void Move(Vector2 velocity)
    {
        Velocity = velocity;
        MoveAndSlide();
    }

    /// <summary>Stands still (clears the velocity).</summary>
    public void Stop() => Velocity = Vector2.Zero;

    /// <summary>
    /// Velocity that reaches <paramref name="destination"/> within this step when close enough,
    /// clamped per axis to <see cref="MoveSpeed"/> / <see cref="MoveSpeed"/> × <see cref="DepthSpeedFactor"/>.
    /// Converges without overshooting, so a held distance does not jitter.
    /// </summary>
    /// <param name="destination">World position to walk to.</param>
    /// <param name="delta">Physics step in seconds.</param>
    public Vector2 VelocityTowards(Vector2 destination, double delta)
    {
        float dt = (float)delta;
        if (dt <= 0f)
        {
            return Vector2.Zero;   // a frozen physics tick (hit-stop) has delta 0: nothing moves
        }

        Vector2 offset = destination - GlobalPosition;
        float depthSpeed = MoveSpeed * DepthSpeedFactor;
        return new Vector2(
            Mathf.Clamp(offset.X / dt, -MoveSpeed, MoveSpeed),
            Mathf.Clamp(offset.Y / dt, -depthSpeed, depthSpeed));
    }

    /// <summary>Decays the knockback velocity with <see cref="KnockbackFriction"/> and moves for one physics step.</summary>
    /// <param name="delta">Physics step in seconds.</param>
    public void ApplyKnockbackStep(double delta)
    {
        Velocity = Velocity.MoveToward(Vector2.Zero, KnockbackFriction * (float)delta);
        MoveAndSlide();
    }

    /// <summary>Asks the <see cref="Director"/> for an attack slot (always granted without one). Returns <c>true</c> when the guard may attack.</summary>
    public bool TryAcquireAttackSlot()
    {
        if (_hasAttackSlot)
        {
            return true;
        }

        if (ActiveDirector is not { } director || director.TryAcquireAttackSlot(this))
        {
            _hasAttackSlot = true;
        }

        return _hasAttackSlot;
    }

    /// <summary>Returns the attack slot, if held. Safe to call repeatedly (Attack exit, Hurt, Down, KO, leaving the tree).</summary>
    public void ReleaseAttackSlot()
    {
        if (!_hasAttackSlot)
        {
            return;
        }

        _hasAttackSlot = false;
        if (ActiveDirector is { } director)
        {
            director.ReleaseAttackSlot(this);
        }
    }

    /// <summary>Starts the <see cref="AttackCooldown"/> timer.</summary>
    public void StartCooldown() => _cooldownRemaining = AttackCooldown;

    /// <summary>Plays <paramref name="animation"/> on the <see cref="AnimationPlayer"/> from its first frame; a missing animation is a warning.</summary>
    /// <param name="animation">Animation name (attack, hurt, ko).</param>
    public void PlayAnimation(StringName animation)
    {
        if (!AnimationPlayer.HasAnimation(animation))
        {
            GD.PushWarning($"{Name}: AnimationPlayer has no animation '{animation}'.");
            return;
        }

        // Play() on the animation that is already playing keeps its position; a re-entered
        // reaction must restart, so always rewind and apply frame 0.
        AnimationPlayer.Play(animation);
        AnimationPlayer.Seek(0.0, update: true);
    }

    /// <summary><c>true</c> while <see cref="AnimationPlayer"/> is playing <paramref name="animation"/>.</summary>
    public bool IsAnimationPlaying(StringName animation) =>
        AnimationPlayer.IsPlaying() && AnimationPlayer.CurrentAnimation == animation;

    /// <summary>Returns the <see cref="AnimationPlayer"/> to its rest pose after an interrupted animation (keys applied immediately).</summary>
    public void ResetPose()
    {
        if (AnimationPlayer.HasAnimation(ResetAnimation))
        {
            AnimationPlayer.Play(ResetAnimation);
            AnimationPlayer.Seek(0.0, update: true);
            // Stop so RESET does not keep re-applying its keys (it would undo Down's rotation two
            // frames later). Callers must not read CurrentAnimationPosition while nothing plays.
            AnimationPlayer.Stop(keepState: true);
        }
    }

    /// <summary>Opens the punch window with <see cref="CurrentAttack"/>. Called from the <c>attack</c> animation's method track.</summary>
    public void HitboxOn() => Hitbox.Activate(CurrentAttack);

    /// <summary>Closes the punch window. Called from the method track and on leaving Attack.</summary>
    public void HitboxOff() => Hitbox.Deactivate();

    /// <summary>
    /// Applies one hit: ignored while knocked out or lying Down (T-B01); multiplied by
    /// <see cref="DarkFirstHitMultiplier"/> while unaware, which also makes the guard aware.
    /// Then knockback, HP loss, flash and the matching state (KO at 0 HP, Down for a knockdown,
    /// else Hurt). The depth check already happened in <see cref="Hitbox"/>.
    /// </summary>
    /// <param name="hit">Damage, knockback and timing of the hit.</param>
    /// <returns><c>false</c> when the hit was ignored.</returns>
    public bool TakeHit(in HitInfo hit)
    {
        if (IsKnockedOut || StateMachine.IsIn(GuardState.StateDown))
        {
            return false;
        }

        float damage = IsAware ? hit.Damage : hit.Damage * DarkFirstHitMultiplier;
        SetAware();

        Velocity = new Vector2(hit.Knockback, 0f);
        FaceTowards(-hit.Knockback);
        Hp = Mathf.Max(0f, Hp - damage);
        UpdateHpLabel();
        EmitSignalDamaged(Hp);

        string reaction = Hp <= 0f ? GuardState.StateKO : hit.Knockdown ? GuardState.StateDown : GuardState.StateHurt;
        StateMachine.TransitionToOrRestart(reaction);
        Flash();
        return true;
    }

    /// <summary>
    /// Variant-friendly form of <see cref="TakeHit(in HitInfo)"/> for tests and scripted events
    /// (GDScript cannot construct <see cref="HitInfo"/>).
    /// </summary>
    public bool TakeDamage(float damage, float knockback, bool knockdown, int hitStopFrames) =>
        TakeHit(new HitInfo(damage, knockback, knockdown, hitStopFrames, DepthTolerance, GlobalPosition.Y));

    /// <summary>
    /// Shows the knockdown pose or stands back up. A scene whose <see cref="AnimationPlayer"/>
    /// has a <c>down</c> animation (the v2 sprite guard) plays it and returns through
    /// <see cref="ResetPose"/>; without one (the v1 rig) the visual is laid on its side by 90°.
    /// </summary>
    /// <param name="down"><c>true</c> for the knockdown pose.</param>
    public void SetDown(bool down)
    {
        if (AnimationPlayer.HasAnimation(DownAnimation))
        {
            if (down)
            {
                PlayAnimation(DownAnimation);
            }
            else
            {
                ResetPose();
            }

            return;
        }

        Visual.Rotation = down ? Mathf.Pi / 2f : 0f;
    }

    /// <summary>Darkens the visual (KO) or restores its normal colour; cancels a running flash.</summary>
    /// <param name="dimmed"><c>true</c> to dim.</param>
    public void SetDimmed(bool dimmed)
    {
        _dimmed = dimmed;
        KillFlash();
        Visual.Modulate = RestingModulate;
    }

    /// <summary>Marks the guard as knocked out and emits <see cref="KnockedOutEventHandler"/> once. Called by the KO state.</summary>
    public void MarkKnockedOut()
    {
        if (IsKnockedOut)
        {
            return;
        }

        IsKnockedOut = true;
        if (DropScene is not null)
        {
            // Deferred: the KO usually lands inside a hitbox overlap callback, where adding a new
            // collision object to the tree is not allowed.
            CallDeferred(MethodName.SpawnDrop);
        }

        EmitSignalKnockedOut();
    }

    /// <summary>Instances <see cref="DropScene"/> next to the fallen body and announces it with <see cref="DroppedEventHandler"/>.</summary>
    private void SpawnDrop()
    {
        if (DropScene is null || !IsInsideTree() || GetParent() is not Node parent)
        {
            return;
        }

        Node2D drop = DropScene.Instantiate<Node2D>();
        parent.AddChild(drop);
        drop.GlobalPosition = GlobalPosition + DropOffset;
        EmitSignalDropped(drop);
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

    private void UpdateVisual() => Visual.Scale = new Vector2(Facing, 1f);
}
