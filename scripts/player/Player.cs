using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// The hero on the belt-scroll floor plane. The node's origin is the contact point with the
/// floor; Y is depth (used for Y-sorting), while jump height lives on a separate axis
/// (<see cref="Height"/>) that only offsets <see cref="Visual"/>. Behaviour is driven by the
/// child <see cref="StateMachine"/> (Idle / Move / Jump); this class owns movement, the jump
/// integration and the visual (flip, height offset, animation).
/// </summary>
public partial class Player : CharacterBody2D
{
    private static readonly StringName ActionLeft = "move_left";
    private static readonly StringName ActionRight = "move_right";
    private static readonly StringName ActionUp = "move_up";
    private static readonly StringName ActionDown = "move_down";
    private static readonly StringName ActionJump = "jump";

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

    /// <summary>Max |ΔY| between attacker and target for a hit to connect (used from T-02b).</summary>
    [Export] public float DepthTolerance { get; set; } = 12f;

    /// <summary>Container for everything that is lifted by the jump and flipped by facing.</summary>
    [Export] public Node2D Visual { get; set; } = null!;

    /// <summary>Animated sprite; may have no <c>SpriteFrames</c> until art is wired.</summary>
    [Export] public AnimatedSprite2D Sprite { get; set; } = null!;

    /// <summary>Placeholder body shown while <see cref="Sprite"/> has no frames.</summary>
    [Export] public Node2D? PlaceholderBody { get; set; }

    /// <summary>Behaviour state machine (Idle / Move / Jump).</summary>
    [Export] public StateMachine StateMachine { get; set; } = null!;

    private float _z;
    private float _zVelocity;

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

    /// <summary>Name of the active state, for debug labels and tests.</summary>
    public string CurrentStateName => StateMachine.CurrentState?.Name ?? string.Empty;

    /// <inheritdoc/>
    public override void _Ready()
    {
        if (PlaceholderBody is not null && Sprite.SpriteFrames is not null)
        {
            PlaceholderBody.Visible = false;
        }

        UpdateVisual();
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

        Vector2 position = Position;
        position.Y = Mathf.Clamp(position.Y, FloorTop, FloorBottom);
        Position = position;

        if (input.X != 0f)
        {
            Facing = input.X > 0f ? 1 : -1;
        }

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
    /// Plays <paramref name="animation"/> if the sprite has it, else <paramref name="fallback"/>;
    /// does nothing while no <c>SpriteFrames</c> are assigned (placeholder art).
    /// </summary>
    public void PlayAnimation(StringName animation, StringName? fallback = null)
    {
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

    private void UpdateVisual()
    {
        Visual.Position = new Vector2(0f, -(SpriteFeetOffset + _z));
        Visual.Scale = new Vector2(Facing, 1f);
    }
}
