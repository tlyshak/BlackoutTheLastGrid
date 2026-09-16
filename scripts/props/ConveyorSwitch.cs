using BlackoutLastGrid.Actors;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// The lever beside the belt line (T-V2-06): one <c>interact</c> throws it, the
/// <see cref="ConveyorLine"/> it is wired to stops, the red indicator lights and the drawn handle
/// swings to its other position. No sequence and no power cost — the belt is a door with a handle,
/// not a repair (<see cref="PowerPanel"/> is the prop for those).
/// </summary>
/// <remarks>
/// <para>
/// <see cref="OneWay"/> is on by default: once the belt is stopped the lever refuses further use.
/// A player who could start the belt again could strand themselves behind it after a respawn at a
/// checkpoint on the far side, and nothing in this level is ever solved twice.
/// </para>
/// <para>
/// Scene contract: the <see cref="Interactable"/> contract (root <c>Area2D</c>, layer 32
/// Interactable, mask 0, <c>monitoring = false</c>) with a reach shape that covers the walk band in
/// front of the drawn post, and the <see cref="Lever"/> sprite whose <c>offset</c> puts its hinge
/// on the node's origin so <see cref="OffRotationDegrees"/> turns it about that hinge.
/// </para>
/// </remarks>
public partial class ConveyorSwitch : Interactable
{
    /// <summary>Emitted after the lever was thrown, with the line's new state.</summary>
    [Signal]
    public delegate void SwitchedEventHandler(bool running);

    /// <summary>The line this lever throws; without it the lever cannot be used.</summary>
    [Export] public ConveyorLine? Line { get; set; }

    /// <summary><c>true</c> (the default) refuses every use after the belt was stopped; <c>false</c> makes it a toggle.</summary>
    [Export] public bool OneWay { get; set; } = true;

    /// <summary>The drawn handle, turned to <see cref="OffRotationDegrees"/> while the belt is stopped.</summary>
    [Export] public Sprite2D? Lever { get; set; }

    /// <summary>
    /// Rotation of <see cref="Lever"/> about its hinge while the belt is stopped, in degrees. The
    /// default mirrors the handle the concept draws (up and to the right, 53.13° above the hinge)
    /// about the vertical, to up and to the <b>left</b>: an exact mirror of the drawn pose that
    /// still lands inside the drawn cabinet (mockup x 115…147.5, y 283.5…313.5). Swinging it the
    /// other way, down through 106.2°, puts the knob below the cabinet foot and over the floor.
    /// </summary>
    [Export] public float OffRotationDegrees { get; set; } = -73.74f;

    /// <summary>Prompt shown once the belt is stopped and the lever is spent.</summary>
    [Export] public string StoppedPromptText { get; set; } = "Belt stopped";

    /// <inheritdoc/>
    public override bool CanInteract => Line is not null && (!OneWay || Line.Running);

    /// <inheritdoc/>
    public override string CurrentPrompt => CanInteract ? PromptText : StoppedPromptText;

    /// <inheritdoc/>
    public override void _Ready()
    {
        ApplyLever();
    }

    /// <inheritdoc/>
    public override void Begin(Player player)
    {
        Activate();
        if (Line is null || (OneWay && !Line.Running))
        {
            Finish(false);
            return;
        }
        Line.Running = !Line.Running;
        ApplyLever();
        EmitSignal(SignalName.Switched, Line.Running);
        NotifyPromptChanged();
        Finish(true);
    }

    private void ApplyLever()
    {
        if (Lever is null)
        {
            return;
        }
        bool running = Line?.Running ?? true;
        Lever.RotationDegrees = running ? 0f : OffRotationDegrees;
    }
}
