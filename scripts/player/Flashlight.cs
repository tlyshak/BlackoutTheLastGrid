using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// The hero's head lamp: a <see cref="PointLight2D"/> cone toggled with the <c>flashlight</c>
/// action that drains <see cref="GameState.Energy"/> while on and dies when the energy reaches
/// its minimum. Works in every player state (it polls input itself). The owner positions it via
/// <see cref="Follow"/> so the beam turns with facing and rises with the jump.
/// </summary>
public partial class Flashlight : PointLight2D
{
    private static readonly StringName ActionFlashlight = "flashlight";

    /// <summary>Emitted whenever the lamp switches on or off (input, energy death or <see cref="SetOn"/>).</summary>
    [Signal]
    public delegate void ToggledEventHandler(bool isOn);

    /// <summary>Energy units drained per second while the lamp is on.</summary>
    [Export] public float DrainPerSecond { get; set; } = 1f;

    /// <summary>Height of the lamp above the feet, in px.</summary>
    [Export] public float HeadOffset { get; set; } = 60f;

    /// <summary>Extra tilt of the beam in degrees (positive = downwards when facing right).</summary>
    [Export] public float BeamAngleDeg { get; set; }

    /// <summary>Whether the lamp starts on when the scene loads.</summary>
    [Export] public bool EnabledAtStart { get; set; }

    /// <summary><c>true</c> while the lamp is on.</summary>
    public bool IsOn { get; private set; }

    private int _facing = 1;
    private float _height;

    /// <inheritdoc/>
    public override void _Ready()
    {
        Enabled = false;
        IsOn = false;
        if (EnabledAtStart)
        {
            SetOn(true);
        }

        ApplyTransform();
    }

    /// <inheritdoc/>
    public override void _PhysicsProcess(double delta)
    {
        if (Input.IsActionJustPressed(ActionFlashlight))
        {
            Toggle();
        }

        if (!IsOn)
        {
            return;
        }

        GameState state = GameState.Instance;
        state.AddEnergy(-DrainPerSecond * (float)delta);
        if (state.Energy <= state.MinEnergy)
        {
            SetOn(false);
        }
    }

    /// <summary>Switches the lamp to the opposite state (turning on is refused without energy).</summary>
    public void Toggle() => SetOn(!IsOn);

    /// <summary>
    /// Turns the lamp on or off. Turning on is refused while <see cref="GameState.Energy"/> is at
    /// <see cref="GameState.MinEnergy"/> (no signal). Emits <see cref="ToggledEventHandler"/> on a change.
    /// </summary>
    /// <param name="on">Desired state.</param>
    public void SetOn(bool on)
    {
        if (on && GameState.Instance.Energy <= GameState.Instance.MinEnergy)
        {
            return;
        }

        if (on == IsOn)
        {
            return;
        }

        IsOn = on;
        Enabled = on;
        EmitSignalToggled(on);
    }

    /// <summary>Positions the beam for the owner's facing and jump height; called from the player's visual update.</summary>
    /// <param name="facing">+1 right, −1 left.</param>
    /// <param name="height">Current jump height in px.</param>
    public void Follow(int facing, float height)
    {
        _facing = facing;
        _height = height;
        ApplyTransform();
    }

    private void ApplyTransform()
    {
        Position = new Vector2(0f, -(HeadOffset + _height));
        float tilt = Mathf.DegToRad(BeamAngleDeg);
        Rotation = _facing >= 0 ? tilt : Mathf.Pi - tilt;
    }
}
