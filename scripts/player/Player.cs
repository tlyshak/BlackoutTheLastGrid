using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// The hero on the belt-scroll floor plane. The node's origin is the contact point with the
/// floor; Y is depth (used for Y-sorting), while jump height lives on a separate axis
/// (<see cref="Height"/>) that only offsets <see cref="Visual"/>. Behaviour is driven by the
/// child <see cref="StateMachine"/> (Idle / Move / Jump / attacks / Hurt / KO); this class owns
/// movement, the jump integration, the visual (flip, height offset, animation), the attack
/// <see cref="Hitbox"/> window and incoming hits.
/// </summary>
public partial class Player : CharacterBody2D, IHittable
{
    private static readonly StringName ActionLeft = "move_left";
    private static readonly StringName ActionRight = "move_right";
    private static readonly StringName ActionUp = "move_up";
    private static readonly StringName ActionDown = "move_down";
    private static readonly StringName ActionJump = "jump";
    private static readonly StringName ActionAttack = "attack";
    private static readonly StringName ActionHeavyAttack = "heavy_attack";
    private static readonly StringName ResetAnimation = "RESET";

    /// <summary>Emitted when a hit connected with the hero (after energy was drained).</summary>
    [Signal]
    public delegate void HurtEventHandler(float damage);

    /// <summary>Emitted once when the hero is knocked out (energy reached the minimum).</summary>
    [Signal]
    public delegate void KnockedOutEventHandler();

    /// <summary>Re-emits the state machine's transitions so owners (levels, HUD) never reach into the child.</summary>
    [Signal]
    public delegate void StateChangedEventHandler(string from, string to);

    /// <summary>Walk speed along X on the floor plane.</summary>
    [Export] public float MoveSpeed { get; set; } = 220f;

    /// <summary>Depth (Y) speed as a fraction of <see cref="MoveSpeed"/>, belt-scroll style.</summary>
    [Export] public float DepthSpeedFactor { get; set; } = 0.75f;

    /// <summary>Smallest Y the feet may reach (far edge of the floor). Test-room default; levels may override.</summary>
    [Export] public float FloorTop { get; set; } = 300f;

    /// <summary>Largest Y the feet may reach (near edge of the floor).</summary>
    [Export] public float FloorBottom { get; set; } = 600f;

    /// <summary>Initial vertical speed of a jump, in px/s along the height axis.</summary>
    [Export] public float JumpVelocity { get; set; } = 380f;

    /// <summary>Pull back to the floor along the height axis, in px/s².</summary>
    [Export] public float Gravity { get; set; } = 900f;

    /// <summary>Distance from the origin (feet) up to the visual's pivot, in px (half the sprite height).</summary>
    [Export] public float SpriteFeetOffset { get; set; } = 36f;

    /// <summary>Max |ΔY| between the hero and a target for a hit to connect, in px.</summary>
    [Export] public float DepthTolerance { get; set; } = 12f;

    /// <summary>Deceleration of the knockback received in Hurt, in px/s².</summary>
    [Export] public float HurtKnockbackFriction { get; set; } = 900f;

    /// <summary>Container for everything that is lifted by the jump and flipped by facing.</summary>
    [Export] public Node2D Visual { get; set; } = null!;

    /// <summary>Animated sprite; may have no <c>SpriteFrames</c> until art is wired.</summary>
    [Export] public AnimatedSprite2D Sprite { get; set; } = null!;

    /// <summary>Placeholder body shown while <see cref="Sprite"/> has no frames.</summary>
    [Export] public Node2D? PlaceholderBody { get; set; }

    /// <summary>Attack, hurt and KO animations; their method tracks call <see cref="HitboxOn"/>/<see cref="HitboxOff"/>.</summary>
    [Export] public AnimationPlayer AnimationPlayer { get; set; } = null!;

    /// <summary>The hero's attack area (under <see cref="Visual"/> so it flips with facing).</summary>
    [Export] public Hitbox Hitbox { get; set; } = null!;

    /// <summary>Behaviour state machine.</summary>
    [Export] public StateMachine StateMachine { get; set; } = null!;

    /// <summary>Head lamp; positioned by <see cref="UpdateVisual"/> so it turns with facing and rises with the jump.</summary>
    [Export] public Flashlight Flashlight { get; set; } = null!;

    /// <summary>Small area at the feet that masks the <c>LightDark</c> layer (bit 64); counts the lit zones the hero stands in.</summary>
    [Export] public Area2D LightSensor { get; set; } = null!;

    private float _z;
    private float _zVelocity;
    private bool _knockedOut;
    private int _litZones;

    /// <summary>Current height above the floor along the jump axis, in px (0 when grounded).</summary>
    public float Height => _z;

    /// <summary><c>true</c> while a jump is in progress.</summary>
    public bool IsAirborne => _z > 0f || _zVelocity > 0f;

    /// <summary>+1 when facing right, −1 when facing left.</summary>
    public int Facing { get; private set; } = 1;

    /// <summary>Normalised 8-way input from the InputMap (read on demand, no allocation).</summary>
    public Vector2 MoveInput => Input.GetVector(ActionLeft, ActionRight, ActionUp, ActionDown);

    /// <summary><c>true</c> on the frame the jump action was pressed.</summary>
    public bool JumpPressed => Input.IsActionJustPressed(ActionJump);

    /// <summary><c>true</c> on the frame the light attack action was pressed.</summary>
    public bool AttackPressed => Input.IsActionJustPressed(ActionAttack);

    /// <summary><c>true</c> on the frame the heavy attack action was pressed.</summary>
    public bool HeavyPressed => Input.IsActionJustPressed(ActionHeavyAttack);

    /// <summary>Name of the active state, for debug labels and tests.</summary>
    public string CurrentStateName => StateMachine.CurrentState?.Name ?? string.Empty;

    /// <summary>Hit parameters of the attack in progress; set by the attack state, read by <see cref="HitboxOn"/>.</summary>
    public HitInfo CurrentAttack { get; set; }

    /// <summary><c>true</c> once the hero has been knocked out.</summary>
    public bool IsKnockedOut => _knockedOut;

    /// <summary><c>true</c> while enemies can see the hero at full range: the head lamp is on or the hero stands in a lit zone.</summary>
    public bool IsLit => Flashlight.IsOn || _litZones > 0;

    /// <inheritdoc/>
    public override void _Ready()
    {
        if (PlaceholderBody is not null && Sprite.SpriteFrames is not null)
        {
            PlaceholderBody.Visible = false;
        }

        Hitbox.Attacker = this;
        StateMachine.StateChanged += OnStateChanged;
        LightSensor.AreaEntered += OnLitZoneEntered;
        LightSensor.AreaExited += OnLitZoneExited;
        UpdateVisual();
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        StateMachine.StateChanged -= OnStateChanged;
        LightSensor.AreaEntered -= OnLitZoneEntered;
        LightSensor.AreaExited -= OnLitZoneExited;
    }

    /// <summary>
    /// Moves along the floor plane for one physics step, clamps depth to the floor bounds and
    /// updates facing. Horizontal collisions (room walls on the World layer) are resolved by
    /// <see cref="CharacterBody2D.MoveAndSlide"/>.
    /// </summary>
    /// <param name="input">8-way input vector, typically <see cref="MoveInput"/>.</param>
    public void ApplyFloorMove(Vector2 input)
    {
        Velocity = new Vector2(input.X * MoveSpeed, input.Y * MoveSpeed * DepthSpeedFactor);
        MoveAndSlide();
        ClampToFloor();

        if (input.X != 0f)
        {
            Facing = input.X > 0f ? 1 : -1;
        }

        UpdateVisual();
    }

    /// <summary>Slides with the current knockback velocity, decelerating by <see cref="HurtKnockbackFriction"/>.</summary>
    /// <param name="delta">Physics step in seconds.</param>
    public void ApplyKnockbackStep(double delta)
    {
        Velocity = Velocity.MoveToward(Vector2.Zero, HurtKnockbackFriction * (float)delta);
        MoveAndSlide();
        ClampToFloor();
        UpdateVisual();
    }

    /// <summary>Starts a jump along the height axis.</summary>
    public void StartJump()
    {
        _zVelocity = JumpVelocity;
        UpdateVisual();
    }

    /// <summary>Integrates the jump for one physics step; lands when the height returns to 0.</summary>
    /// <param name="delta">Physics step in seconds.</param>
    public void IntegrateJump(double delta)
    {
        float dt = (float)delta;
        _zVelocity -= Gravity * dt;
        _z += _zVelocity * dt;

        if (_z <= 0f)
        {
            _z = 0f;
            _zVelocity = 0f;
        }

        UpdateVisual();
    }

    /// <summary>
    /// Plays <paramref name="animation"/>: on the <see cref="AnimationPlayer"/> when it has it
    /// (attacks, hurt, ko), else on the sprite when its <c>SpriteFrames</c> has it, else
    /// <paramref name="fallback"/> on the sprite. Silently does nothing without art.
    /// </summary>
    public void PlayAnimation(StringName animation, StringName? fallback = null)
    {
        if (AnimationPlayer.HasAnimation(animation))
        {
            // Play() on the animation that is already playing keeps its position; a re-entered
            // reaction (second hit while in Hurt) must restart, so always rewind and apply frame 0.
            AnimationPlayer.Play(animation);
            AnimationPlayer.Seek(0.0, update: true);
            return;
        }

        SpriteFrames? frames = Sprite.SpriteFrames;
        if (frames is null)
        {
            return;
        }

        if (frames.HasAnimation(animation))
        {
            Sprite.Play(animation);
        }
        else if (fallback is not null && frames.HasAnimation(fallback))
        {
            Sprite.Play(fallback);
        }
    }

    /// <summary>
    /// Returns the <see cref="AnimationPlayer"/> to its rest pose (fist, tint, rotation) after an
    /// interrupted animation. The RESET keys are applied immediately so the next animation played
    /// in the same frame starts from the rest pose.
    /// </summary>
    public void ResetPose()
    {
        if (AnimationPlayer.HasAnimation(ResetAnimation))
        {
            AnimationPlayer.Play(ResetAnimation);
            AnimationPlayer.Seek(0.0, update: true);
        }
    }

    /// <summary><c>true</c> while <see cref="AnimationPlayer"/> is playing <paramref name="animation"/>.</summary>
    public bool IsAnimationPlaying(StringName animation) =>
        AnimationPlayer.IsPlaying() && AnimationPlayer.CurrentAnimation == animation;

    /// <summary>Seconds elapsed in the current <see cref="AnimationPlayer"/> animation, or 0 when none is playing.</summary>
    public double AnimationTime => AnimationPlayer.IsPlaying() ? AnimationPlayer.CurrentAnimationPosition : 0.0;

    /// <summary>Opens the attack window with <see cref="CurrentAttack"/>. Called from animation method tracks.</summary>
    public void HitboxOn() => Hitbox.Activate(CurrentAttack);

    /// <summary>Closes the attack window. Called from animation method tracks and on leaving an attack state.</summary>
    public void HitboxOff() => Hitbox.Deactivate();

    /// <inheritdoc/>
    public bool TakeHit(in HitInfo hit)
    {
        if (_knockedOut)
        {
            return false;
        }

        GameState state = GameState.Instance;
        state.AddEnergy(-hit.Damage);
        Velocity = new Vector2(hit.Knockback, 0f);
        Facing = hit.Knockback > 0f ? -1 : hit.Knockback < 0f ? 1 : Facing;
        UpdateVisual();
        EmitSignalHurt(hit.Damage);

        // Only a hit that actually drains energy can knock the hero out: a 0-damage hit at
        // MinEnergy is a flinch, not a KO.
        if (hit.Damage > 0f && state.Energy <= state.MinEnergy)
        {
            _knockedOut = true;
            StateMachine.TransitionToOrRestart(PlayerState.StateKO);
            EmitSignalKnockedOut();
        }
        else
        {
            StateMachine.TransitionToOrRestart(PlayerState.StateHurt);
        }

        return true;
    }

    /// <summary>
    /// Variant-friendly form of <see cref="TakeHit(in HitInfo)"/> for tests and scripted events
    /// (GDScript cannot construct <see cref="HitInfo"/>).
    /// </summary>
    public bool TakeDamage(float damage, float knockback, bool knockdown, int hitStopFrames) =>
        TakeHit(new HitInfo(damage, knockback, knockdown, hitStopFrames, DepthTolerance, GlobalPosition.Y));

    private void OnStateChanged(string from, string to) => EmitSignalStateChanged(from, to);

    private void OnLitZoneEntered(Area2D area) => _litZones++;

    private void OnLitZoneExited(Area2D area) => _litZones = Mathf.Max(0, _litZones - 1);

    private void ClampToFloor()
    {
        Vector2 position = Position;
        position.Y = Mathf.Clamp(position.Y, FloorTop, FloorBottom);
        Position = position;
    }

    private void UpdateVisual()
    {
        Visual.Position = new Vector2(0f, -(SpriteFeetOffset + _z));
        Visual.Scale = new Vector2(Facing, 1f);
        Flashlight.Follow(Facing, _z);
    }
}
