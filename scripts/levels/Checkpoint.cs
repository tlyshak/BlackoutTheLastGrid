using BlackoutLastGrid.Actors;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// A respawn anchor: a one-shot trigger across the floor band that tells the level "from here on, a
/// death costs seconds, not the level". Crossing it emits <see cref="ReachedEventHandler"/> once and
/// the trigger goes quiet; <see cref="LevelBase"/> remembers the checkpoint and the energy the hero
/// had, and <see cref="LevelBase.RespawnAtCheckpoint"/> puts him back here without reloading the
/// scene. The checkpoint itself stores nothing — it only announces that it was reached.
/// </summary>
/// <remarks>
/// Scene contract (the <see cref="Door"/> precedent — a script plus an <c>Area2D</c> that a level
/// composes or instances): root <c>Area2D</c> with <c>collision_layer = 0</c>,
/// <c>collision_mask = 2</c> (Player), <c>monitorable = false</c>, one <c>CollisionShape2D</c>
/// across the floor band and a <c>PH_</c> floor decal so the spot is a landmark in the dark.
/// Checkpoints belong in a container the level exports as <see cref="LevelBase.Checkpoints"/>, and
/// never inside a scripted beat — a soft respawn does not rewind cutscenes.
/// </remarks>
public partial class Checkpoint : Area2D
{
    /// <summary>Emitted the first time the hero crosses this checkpoint.</summary>
    [Signal]
    public delegate void ReachedEventHandler(Checkpoint checkpoint);

    /// <summary>Px added to this node's position when the hero respawns here.</summary>
    [Export] public Vector2 RespawnOffset { get; set; } = Vector2.Zero;

    /// <summary>Room whose bounds (camera limits and floor band) are re-applied on a respawn; optional for a one-room level.</summary>
    [Export] public RoomBounds? Room { get; set; }

    /// <summary><c>true</c> respawns with a full reserve instead of the energy the hero had when he got here.</summary>
    [Export] public bool RestoresFullEnergy { get; set; }

    /// <summary>Name for debug labels and tests; never shown to the player.</summary>
    [Export] public string Label { get; set; } = string.Empty;

    /// <summary><c>true</c> once the hero has crossed this checkpoint.</summary>
    public bool IsReached { get; private set; }

    /// <summary>World position the hero is placed at on a respawn.</summary>
    public Vector2 RespawnPosition => GlobalPosition + RespawnOffset;

    /// <inheritdoc/>
    public override void _Ready() => BodyEntered += OnBodyEntered;

    /// <inheritdoc/>
    public override void _ExitTree() => BodyEntered -= OnBodyEntered;

    private void OnBodyEntered(Node2D body)
    {
        if (IsReached || body is not Player)
        {
            return;
        }

        IsReached = true;
        // Deferred: the flag is written from inside a physics callback.
        SetDeferred(Area2D.PropertyName.Monitoring, false);
        EmitSignalReached(this);
    }
}
