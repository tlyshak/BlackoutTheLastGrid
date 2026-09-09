using System.Collections.Generic;
using Godot;

namespace BlackoutLastGrid.Core;

/// <summary>
/// Attack area shared by the hero and enemies. Stays <c>Monitoring</c> all the time and is gated
/// by <see cref="Activate"/>/<see cref="Deactivate"/> (called from animation method tracks), so
/// targets that already overlap when the active window opens are hit too. A target is hit at most
/// once per activation, and only when the attacker and the target stand within
/// <see cref="HitInfo.DepthTolerance"/> of each other on the depth (Y) axis.
/// </summary>
/// <remarks>
/// Scene contract: node name <c>Hitbox</c>; targets are <c>Area2D</c> nodes named <c>Hurtbox</c>
/// whose parent (the scene root) implements <see cref="IHittable"/>. Collision layers/masks are
/// set in the scene (<c>Player/Visual/Hitbox</c> = layer 4 / mask 3, enemy hitboxes = 5 / 2).
/// </remarks>
public partial class Hitbox : Area2D
{
    private static readonly StringName HurtboxName = "Hurtbox";

    /// <summary>Emitted once per target that was actually hit during the current activation.</summary>
    [Signal]
    public delegate void HitEventHandler(Node2D target);

    /// <summary>
    /// The attacking actor (its position is the depth reference). Defaults to the scene owner,
    /// which is the scene root for instanced scenes.
    /// </summary>
    [Export] public Node2D? Attacker { get; set; }

    /// <summary><c>true</c> while an attack's active window is open.</summary>
    public bool IsActive { get; private set; }

    private HitInfo _info;
    private readonly HashSet<Node> _alreadyHit = new();

    /// <inheritdoc/>
    public override void _Ready()
    {
        Attacker ??= Owner as Node2D ?? GetParent<Node2D>();
        Monitoring = true;
        AreaEntered += OnAreaEntered;
    }

    /// <inheritdoc/>
    public override void _ExitTree() => AreaEntered -= OnAreaEntered;

    /// <summary>Opens the active window with the given hit parameters and hits anything already overlapping.</summary>
    /// <param name="info">Hit parameters; <see cref="HitInfo.SourceY"/> is filled in from <see cref="Attacker"/>.</param>
    public void Activate(in HitInfo info)
    {
        _info = info with { SourceY = Attacker?.GlobalPosition.Y ?? info.SourceY };
        _alreadyHit.Clear();
        IsActive = true;

        foreach (Area2D area in GetOverlappingAreas())
        {
            TryHit(area);
        }
    }

    /// <summary>Closes the active window.</summary>
    public void Deactivate()
    {
        IsActive = false;
        _alreadyHit.Clear();
    }

    private void OnAreaEntered(Area2D area)
    {
        if (IsActive)
        {
            TryHit(area);
        }
    }

    private void TryHit(Area2D area)
    {
        if (area.Name != HurtboxName)
        {
            return;
        }

        Node target = area.GetParent();
        if (target is not IHittable hittable || target is not Node2D targetNode || _alreadyHit.Contains(target))
        {
            return;
        }

        if (Mathf.Abs(targetNode.GlobalPosition.Y - _info.SourceY) > _info.DepthTolerance)
        {
            return;
        }

        _alreadyHit.Add(target);
        if (hittable.TakeHit(_info))
        {
            EmitSignalHit(targetNode);
        }
    }
}
