using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// A blockage in a drift — a pile of collapsed timber, or a flooded stretch: a solid body across
/// the walk band that is removed either by the hero's <c>heavy_attack</c>
/// (<see cref="HeavyHitsToClear"/> hits, the level's heavy-attack lesson taught on rubble instead
/// of on a person) or by a machine that clears it through <see cref="Clear"/>. Removal is one-shot
/// and permanent: a cleared pile never comes back, so a death or a switched-off machine can never
/// force the player to re-solve anything. <see cref="SetBlocked"/> is the inverse, used by
/// <see cref="Levels.CaveIn"/> to *create* a pile behind the hero.
/// </summary>
/// <remarks>
/// <para>
/// Scene contract: root <c>StaticBody2D</c> on layer 1 (World) with mask 0 and the blocking
/// <see cref="BlockerShape"/>; a <c>Hurtbox</c> <c>Area2D</c> child on layer 4 (3 <c>Enemy</c> — in
/// practice "a <c>Hitbox</c> may hit this", the layer the hero's hitbox masks) with
/// <c>monitoring = false</c>, <c>monitorable = true</c>.
/// </para>
/// <para>
/// Depth rule: <see cref="Hitbox"/> compares the attacker's Y with the <b>root</b> node's Y against
/// the attacker's <c>DepthTolerance</c> (12 px, inclusive), and a pile cannot widen that. Place a
/// pile's root at the centre of the room's floor band and mark the strip with a <c>PH_</c> decal, or
/// heavy attacks will read as "nothing happens".
/// </para>
/// </remarks>
public partial class DebrisPile : StaticBody2D, IHittable
{
    /// <summary>Emitted when a qualifying hit landed but the pile still stands; carries the hits left.</summary>
    [Signal]
    public delegate void DamagedEventHandler(int hitsLeft);

    /// <summary>Emitted when a hit does not qualify — a light attack, or a pile hands cannot clear at all.</summary>
    [Signal]
    public delegate void ResistedEventHandler();

    /// <summary>Emitted once when the pile is gone for good.</summary>
    [Signal]
    public delegate void ClearedEventHandler();

    /// <summary>Heavy hits needed to clear the pile; <c>0</c> means hands can never clear it (a machine must).</summary>
    [Export] public int HeavyHitsToClear { get; set; } = 2;

    /// <summary>
    /// <c>true</c> counts only a hit that floors a target (<see cref="HitInfo.Knockdown"/>), i.e.
    /// only <c>heavy_attack</c> — the light combo's third step shares the heavy's hit-stop frames,
    /// so the knockdown flag is the only reliable discriminator.
    /// </summary>
    [Export] public bool RequiresKnockdown { get; set; } = true;

    /// <summary>The blocking shape of this body; disabled while the pile is cleared.</summary>
    [Export] public CollisionShape2D BlockerShape { get; set; } = null!;

    /// <summary>The pile's hurtbox; stops being monitorable once the pile is cleared.</summary>
    [Export] public Area2D? Hurtbox { get; set; }

    /// <summary>Placeholder rubble; hidden while the pile is cleared.</summary>
    [Export] public Node2D? Rubble { get; set; }

    /// <summary>Dust burst, fired one-shot on every landed hit and on clearing.</summary>
    [Export] public GpuParticles2D? Dust { get; set; }

    /// <summary>
    /// <c>true</c> starts the pile cleared and hidden — the state a pile that a
    /// <see cref="Levels.CaveIn"/> will later drop into the drift begins in. Assigning it after the
    /// node is ready applies at once (the <see cref="Levels.Door.Locked"/> precedent), so a level
    /// or a test may compose a pile in either order.
    /// </summary>
    [Export]
    public bool StartsCleared
    {
        get => _startsCleared;
        set
        {
            _startsCleared = value;
            if (IsNodeReady())
            {
                SetBlocked(!value);
            }
        }
    }

    /// <summary>Stable id for save/load (T-09); empty means "not persisted".</summary>
    [Export] public string SaveId { get; set; } = string.Empty;

    private bool _startsCleared;
    private int _hits;

    /// <summary><c>true</c> while the way through is open.</summary>
    public bool IsCleared { get; private set; }

    /// <summary>Qualifying hits still needed to clear the pile; 0 once it is cleared or unclearable by hand.</summary>
    public int HitsLeft => IsCleared ? 0 : Mathf.Max(0, HeavyHitsToClear - _hits);

    /// <inheritdoc/>
    public override void _Ready() => SetBlocked(!StartsCleared);

    /// <inheritdoc/>
    public bool TakeHit(in HitInfo hit)
    {
        if (IsCleared)
        {
            return false;
        }

        if (HeavyHitsToClear <= 0 || (RequiresKnockdown && !hit.Knockdown))
        {
            EmitSignalResisted();
            return false;   // false ⇒ no hit-stop and no sparks: the pile shrugs the hit off
        }

        _hits++;
        BurstDust();
        if (_hits >= HeavyHitsToClear)
        {
            Clear();
        }
        else
        {
            EmitSignalDamaged(HitsLeft);
        }

        return true;   // true ⇒ the Hitbox applies hit-stop and reports the hit, so LevelFx reacts
    }

    /// <summary>
    /// Opens the way for good — the last heavy hit landed, or a machine (pump, extractor) removed
    /// the blockage. Idempotent, and safe from a physics callback: the shape flags are deferred.
    /// </summary>
    public void Clear()
    {
        if (IsCleared)
        {
            return;
        }

        SetBlocked(false);
        BurstDust();
        EmitSignalCleared();
    }

    /// <summary>
    /// Puts the blockage back, or takes it away without announcing it. Used by
    /// <see cref="Levels.CaveIn"/> to drop a fresh pile behind the hero; it does not emit
    /// <see cref="ClearedEventHandler"/>, so a pile that starts cleared announces nothing.
    /// </summary>
    /// <param name="blocked"><c>true</c> makes the pile solid and visible again and resets its hit count.</param>
    public void SetBlocked(bool blocked)
    {
        IsCleared = !blocked;
        if (blocked)
        {
            _hits = 0;
        }

        BlockerShape.SetDeferred(CollisionShape2D.PropertyName.Disabled, !blocked);
        Hurtbox?.SetDeferred(Area2D.PropertyName.Monitorable, blocked);
        if (Rubble is not null)
        {
            Rubble.Visible = blocked;
        }
    }

    private void BurstDust()
    {
        if (Dust is null)
        {
            return;
        }

        Dust.Restart();   // a one-shot emitter re-fires only on a restart
    }
}
