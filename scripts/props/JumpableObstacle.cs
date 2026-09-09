using BlackoutLastGrid.Actors;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// A low obstacle (crate row, pipe) that blocks walking but lets a jump pass: a
/// <c>StaticBody2D</c> on the World layer whose <see cref="Shape"/> is solid only while the
/// hero's <see cref="Player.Height"/> is below <see cref="ClearHeight"/>. Chosen over a
/// height-aware collision layer because it needs no change to the hero and no new layer; the
/// shape is toggled at most once per height change, from <c>_PhysicsProcess</c>, so it never
/// changes inside a physics flush. Landing on the obstacle pops the hero out sideways by the
/// body's depenetration — keep the obstacle thin along X.
/// </summary>
public partial class JumpableObstacle : StaticBody2D
{
    /// <summary>The hero whose jump height decides whether the obstacle is solid; set by the level.</summary>
    [Export] public Player Player { get; set; } = null!;

    /// <summary>Jump height (px above the floor) from which the hero clears the obstacle.</summary>
    [Export] public float ClearHeight { get; set; } = 20f;

    /// <summary>The blocking shape, toggled with the hero's height.</summary>
    [Export] public CollisionShape2D Shape { get; set; } = null!;

    /// <inheritdoc/>
    public override void _PhysicsProcess(double delta)
    {
        bool cleared = Player.Height >= ClearHeight;
        if (Shape.Disabled != cleared)
        {
            Shape.Disabled = cleared;
        }
    }
}
