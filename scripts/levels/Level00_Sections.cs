using BlackoutLastGrid.Core;
using BlackoutLastGrid.Enemies;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// The two painted sections of level 0, and nothing else: the mine face the hero starts on and the
/// ventilation drift next to it, each one painting wide, placed side by side so the second begins
/// exactly where the first ends. Ray walks, Dan follows, the conveyor blocks the drift until its
/// lever is thrown, and one guard waits at the far end.
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

    /// <inheritdoc/>
    public override void _Ready()
    {
        base._Ready();
        ApplyRoomBounds(StartRoom);
        StandingGuard?.SetTarget(Player, Director);
    }
}
