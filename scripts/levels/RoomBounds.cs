using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// One room of a belt-scroll level, as data: the world rectangle the camera is limited to while
/// the hero is inside, and the floor band (world Y) the hero's feet may reach there. Applied by
/// <see cref="LevelBase.ApplyRoomBounds"/> at level start and when a <see cref="Door"/> leads
/// into the room. The node's own position is irrelevant; values are absolute world px.
/// </summary>
public partial class RoomBounds : Node2D
{
    /// <summary>Camera limits while the hero is in this room, in world px.</summary>
    [Export] public Rect2 Rect { get; set; } = new(0f, 0f, 1920f, 1080f);

    /// <summary>Smallest Y the hero's feet may reach in this room (far edge of the floor), in world px.</summary>
    [Export] public float FloorTop { get; set; } = 300f;

    /// <summary>Largest Y the hero's feet may reach in this room (near edge of the floor), in world px.</summary>
    [Export] public float FloorBottom { get; set; } = 600f;

    /// <summary>
    /// Ambient-FX group belonging to this room (dust, flicker, loops). Simulated only while the
    /// room is the active one — <see cref="LevelBase.ApplyRoomBounds"/> switches it on and stops
    /// the group of the room being left. Optional: a room without ambient FX leaves it empty.
    /// </summary>
    [Export] public Node2D? Fx { get; set; }
}
