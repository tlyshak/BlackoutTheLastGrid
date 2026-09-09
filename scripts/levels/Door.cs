using BlackoutLastGrid.Actors;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Passage between two rooms of a level: a trigger area across the floor band at the room
/// boundary. While <see cref="Locked"/> the child <see cref="BlockerShape"/> (a
/// <c>StaticBody2D</c> on the World layer) stops the hero and the <see cref="Gate"/> placeholder
/// shows <see cref="LockedColor"/>; once unlocked, the hero walking in emits
/// <see cref="EnteredEventHandler"/> and the level applies <see cref="TargetRoom"/>'s bounds and
/// moves the hero by <see cref="ArrivalOffset"/>. The door only reports; the level decides what
/// happens (bounds, camera, re-locking behind the hero).
/// </summary>
/// <remarks>
/// Scene contract: root <c>Area2D</c> with <c>collision_layer = 0</c>, <c>collision_mask = 2</c>
/// (Player) and one <c>CollisionShape2D</c> spanning the floor band; a <c>Blocker</c>
/// <c>StaticBody2D</c> child (layer 1, mask 0) whose shape is <see cref="BlockerShape"/>.
/// </remarks>
public partial class Door : Area2D
{
    /// <summary>Emitted when the hero enters the door while it is unlocked.</summary>
    [Signal]
    public delegate void EnteredEventHandler(Player player);

    /// <summary>Room the door leads into; its bounds are applied by the level on <see cref="EnteredEventHandler"/>.</summary>
    [Export] public RoomBounds TargetRoom { get; set; } = null!;

    /// <summary>Offset added to the hero's position on entry, so it lands past the door inside the target room, in px.</summary>
    [Export] public Vector2 ArrivalOffset { get; set; } = new(80f, 0f);

    /// <summary><c>true</c> keeps the hero out (blocker solid, gate red) and suppresses <see cref="EnteredEventHandler"/>.</summary>
    [Export]
    public bool Locked
    {
        get => _locked;
        set
        {
            _locked = value;
            if (IsNodeReady())
            {
                ApplyLock();
            }
        }
    }

    /// <summary>Colour of <see cref="Gate"/> while locked.</summary>
    [Export] public Color LockedColor { get; set; } = new(0.55f, 0.12f, 0.1f);

    /// <summary>Colour of <see cref="Gate"/> while open.</summary>
    [Export] public Color OpenColor { get; set; } = new(0.16f, 0.45f, 0.22f);

    /// <summary>Shape of the <c>Blocker</c> body; disabled while the door is open.</summary>
    [Export] public CollisionShape2D? BlockerShape { get; set; }

    /// <summary>Placeholder gate recoloured by the lock state.</summary>
    [Export] public Polygon2D? Gate { get; set; }

    private bool _locked;

    /// <inheritdoc/>
    public override void _Ready()
    {
        ApplyLock();
        BodyEntered += OnBodyEntered;
    }

    /// <inheritdoc/>
    public override void _ExitTree() => BodyEntered -= OnBodyEntered;

    private void OnBodyEntered(Node2D body)
    {
        if (_locked || body is not Player player)
        {
            return;
        }

        EmitSignalEntered(player);
    }

    /// <summary>Applies <see cref="Locked"/> to the blocker (deferred: the lock may change inside a physics callback) and the gate colour.</summary>
    private void ApplyLock()
    {
        BlockerShape?.SetDeferred(CollisionShape2D.PropertyName.Disabled, !_locked);
        if (Gate is not null)
        {
            Gate.Color = _locked ? LockedColor : OpenColor;
        }
    }
}
