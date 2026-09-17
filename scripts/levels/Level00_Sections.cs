using BlackoutLastGrid.Core;
using BlackoutLastGrid.Enemies;
using BlackoutLastGrid.Props;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// The painted sections of level 0, and nothing else: the mine face the hero starts on, the
/// ventilation drift next to it and the exit hall with the lift, each one painting wide and placed
/// side by side so every one begins exactly where the one before it ends. Ray walks, Dan follows,
/// the conveyor blocks the drift until its lever is thrown, a guard waits at the end of the drift,
/// and the lift cage in the exit hall opens on the hero and puts two more on him.
///
/// The two paintings are one corridor, not two arenas, so there is a single
/// <see cref="RoomBounds"/> spanning both of them: the camera pans continuously across the seam
/// instead of stopping at the end of the first painting. The far layers of both backdrops are
/// drawn while the camera limits overlap their room, which the full span always does.
///
/// Everything a level needs — the camera, the room bounds, the checkpoints, the pause menu, the
/// restart rule — comes from <see cref="LevelBase"/>. This class only puts the hero in his starting
/// room and hands the guard his target, the way every level with a standing guard does.
/// </summary>
public partial class Level00_Sections : LevelBase
{
    /// <summary>The playable area: both paintings. Its bounds are applied on ready and on every respawn.</summary>
    [Export] public RoomBounds StartRoom { get; set; } = null!;

    /// <summary>Attack-slot director shared by every enemy in the level.</summary>
    [Export] public EnemyDirector Director { get; set; } = null!;

    /// <summary>The guard standing at the end of the second section; he gets the hero as target here.</summary>
    [Export] public Guard? StandingGuard { get; set; }

    /// <summary>
    /// The section gates, left to right. Each one shuts the way out of its section until every
    /// enemy in it is down (the author's rule of 2026-09-16: «Go … тільки якщо всі вороги
    /// переможені»), and the level turns them into the one GO arrow the HUD shows.
    /// </summary>
    [Export] public SectionGate[] Gates { get; set; } = { };

    /// <inheritdoc/>
    public override void _Ready()
    {
        base._Ready();
        ApplyRoomBounds(StartRoom);
        StandingGuard?.SetTarget(Player, Director);
        RefreshGo();
    }

    /// <inheritdoc/>
    public override void _Process(double delta)
    {
        base._Process(delta);
        RefreshGo();
    }

    /// <summary>
    /// Shows GO only while the hero stands in a section he has cleared and has not yet left. The
    /// gates cannot work this out between them — each one knows its own enemies and nothing about
    /// where the hero is — so the level reads the nearest gate ahead of him: open means the way on
    /// is clear and the arrow points at it, shut means there is still a fight between him and it.
    /// The last section's gate never opens onto anything, so once it is cleared the arrow simply
    /// stays lit, which is what the author asked for.
    /// </summary>
    private void RefreshGo()
    {
        if (Hud is null)
        {
            return;
        }

        SectionGate? ahead = null;
        foreach (SectionGate gate in Gates)
        {
            if (gate is null || !IsInstanceValid(gate) || gate.GlobalPosition.X <= Player.GlobalPosition.X)
            {
                continue;
            }

            if (ahead is null || gate.GlobalPosition.X < ahead.GlobalPosition.X)
            {
                ahead = gate;
            }
        }

        Hud.GoVisible = ahead is not null && ahead.IsOpen;
    }
}
