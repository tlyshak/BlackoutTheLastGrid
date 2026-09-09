using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// A lit area of the floor (street lamp, open door, powered panel): while the hero's
/// <c>LightSensor</c> overlaps it, <c>Player.IsLit</c> is <c>true</c> even with the head lamp
/// off, so enemies see the hero at full range. Passive: it sits on the <c>LightDark</c> layer
/// (7, bit 64) and is found by the sensor; it looks for nothing itself. The visual light is a
/// sibling/child <c>PointLight2D</c> placed by the level.
/// </summary>
public partial class LitZone : Area2D
{
    /// <summary>Collision layer bit of the <c>LightDark</c> layer (7) that the hero's sensor masks.</summary>
    public const uint LightDarkLayer = 1u << 6;

    /// <inheritdoc/>
    public override void _Ready()
    {
        if ((CollisionLayer & LightDarkLayer) == 0)
        {
            GD.PushWarning($"LitZone '{Name}' is not on the LightDark layer (bit {LightDarkLayer}); the hero's LightSensor will never see it.");
        }
    }
}
