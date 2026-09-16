using BlackoutLastGrid.Actors;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// The torn feed cable of the ventilation room (the author's r2 concept of section 2): it hangs
/// from the gantry and arcs into the floor at the head of the conveyor, and whoever stands in the
/// discharge is shocked. The shock costs <see cref="Damage"/> energy and throws the hero away from
/// the cable, then waits <see cref="ShockInterval"/> before it can bite again, so walking through
/// costs one hit and standing in it drains him.
///
/// The arc reaches the near rail of the belt, which is the one way past the conveyor, so the drift
/// is crossed along the near half of the band. The area is placed on the pixels the room paints the
/// discharge at, plus the depth it spreads across the belt — the smoke test recomputes both from
/// the mockup coordinates and fails on a drift.
/// </summary>
/// <remarks>
/// Scene contract: root <c>Area2D</c> on layer 0 with mask 2 (Player), monitoring, one
/// <c>RectangleShape2D</c>. The shock runs in <c>_PhysicsProcess</c>, so it freezes with the pause
/// menu and slows with a hit-stop, and it reads only the bodies the area already reports
/// overlapping — no combat class is touched. <see cref="Actors.Player.TakeDamage"/> does the rest:
/// energy, knockback, the Hurt state and, at zero energy, the knockout.
/// </remarks>
public partial class LiveCable : Area2D
{
    /// <summary>Emitted on every shock, with the energy it cost.</summary>
    [Signal]
    public delegate void ShockedEventHandler(float damage);

    /// <summary>Energy one shock costs the hero.</summary>
    [Export] public float Damage { get; set; } = 14f;

    /// <summary>Px/s the shock throws the hero, away from the cable along X.</summary>
    [Export] public float Knockback { get; set; } = 240f;

    /// <summary>Physics frames of hit-stop the shock requests, so it lands as hard as a punch.</summary>
    [Export] public int HitStopFrames { get; set; } = 4;

    /// <summary>Seconds before the cable can bite the same hero again.</summary>
    [Export] public float ShockInterval { get; set; } = 0.9f;

    /// <summary>
    /// <c>false</c> leaves the cable dead: nothing is shocked and <see cref="Arc"/> stops drawing.
    /// Nothing in the game switches it yet; it exists so a level can cut the feed.
    /// </summary>
    [Export]
    public bool Live
    {
        get => _live;
        set
        {
            _live = value;
            if (IsInsideTree())
            {
                Apply();
            }
        }
    }

    /// <summary>The painted discharge, hidden while the cable is dead. Optional.</summary>
    [Export] public CanvasItem? Arc { get; set; }

    private bool _live = true;
    private float _cooldown;

    /// <summary><c>true</c> while the cable is armed and its wait has run out.</summary>
    public bool IsArmed => _live && _cooldown <= 0f;

    /// <inheritdoc/>
    public override void _Ready() => Apply();

    /// <inheritdoc/>
    public override void _PhysicsProcess(double delta)
    {
        if (!_live || delta <= 0d)
        {
            return;
        }

        if (_cooldown > 0f)
        {
            _cooldown = Mathf.Max(0f, _cooldown - (float)delta);
            return;
        }

        foreach (Node2D body in GetOverlappingBodies())
        {
            if (body is not Player hero || hero.IsKnockedOut)
            {
                continue;
            }

            // Thrown further from the cable, so a shock never shoves him deeper into the arc.
            float away = hero.GlobalPosition.X < GlobalPosition.X ? -Knockback : Knockback;
            if (hero.TakeDamage(Damage, away, false, HitStopFrames))
            {
                _cooldown = ShockInterval;
                EmitSignal(SignalName.Shocked, Damage);
            }

            return;   // one hero, one shock
        }
    }

    private void Apply()
    {
        SetPhysicsProcess(_live);
        if (!_live)
        {
            _cooldown = 0f;
        }

        if (Arc is not null)
        {
            Arc.Visible = _live;
        }
    }
}
