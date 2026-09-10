using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Art;
using BlackoutLastGrid.Core;
using BlackoutLastGrid.Fx;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Combat feedback for one level, wired the same way as <see cref="Core.EnemyDirector"/>: a plain
/// node with <c>[Export]</c> references that listens to the hero's <b>public</b> signals and turns
/// them into effects — an <see cref="ImpactFx"/> burst at the point of contact on every landed hit,
/// a dust puff under the feet on landing, and a camera shake through
/// <see cref="LevelBase.ShakeCamera"/>. No combat class is touched and no balance value is read
/// beyond <see cref="HitInfo.HitStopFrames"/>, which only decides how heavy the feedback looks.
/// </summary>
public partial class LevelFx : Node
{
    /// <summary>The level that owns the camera; the only path to the shake.</summary>
    [Export] public LevelBase Level { get; set; } = null!;

    /// <summary>The hero whose signals drive the effects.</summary>
    [Export] public Player Player { get; set; } = null!;

    /// <summary>Effect spawned per event.</summary>
    [Export] public PackedScene ImpactFxScene { get; set; } = null!;

    /// <summary>Where spawned effects are parented; defaults to <see cref="Level"/>.</summary>
    [Export] public Node2D? FxParent { get; set; }

    /// <summary>Px above the target's feet where the spark burst appears.</summary>
    [Export] public float HitFxHeight { get; set; } = 40f;

    /// <summary>Particles in the burst of a light hit.</summary>
    [Export] public int HitSparkAmount { get; set; } = 12;

    /// <summary>Particles in the burst of a heavy hit.</summary>
    [Export] public int HeavySparkAmount { get; set; } = 22;

    /// <summary>A hit whose <c>HitStopFrames</c> reaches this counts as heavy for the feedback.</summary>
    [Export] public int HeavyHitStopFrames { get; set; } = 5;

    /// <summary>Shake amplitude of a light hit, in px.</summary>
    [Export] public float HitShake { get; set; } = 3f;

    /// <summary>Shake amplitude of a heavy hit, in px.</summary>
    [Export] public float HeavyShake { get; set; } = 7f;

    /// <summary>Shake amplitude of the hero's knockdown, in px.</summary>
    [Export] public float KnockdownShake { get; set; } = 11f;

    /// <summary>Seconds a shake decays over.</summary>
    [Export] public float ShakeTime { get; set; } = 0.18f;

    /// <summary>Particles in the dust puff under the feet on landing.</summary>
    [Export] public int LandDustAmount { get; set; } = 8;

    /// <summary>Colour of the landing dust — rock, not a discharge.</summary>
    [Export] public Color LandDustColor { get; set; } = Palette.RockNear;

    /// <summary>Scale of a landing dust puff relative to a spark burst.</summary>
    [Export] public float LandDustScale { get; set; } = 0.8f;

    /// <summary>Flash energy of a landing dust puff — dust is lit, not a discharge.</summary>
    [Export] public float LandDustFlashEnergy { get; set; } = 0.6f;

    /// <inheritdoc/>
    public override void _Ready()
    {
        Player.Hitbox.Hit += OnHeroHit;
        Player.Hurt += OnHeroHurt;
        Player.KnockedOut += OnHeroKnockedOut;
        Player.Landed += OnHeroLanded;
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        Player.Hitbox.Hit -= OnHeroHit;
        Player.Hurt -= OnHeroHurt;
        Player.KnockedOut -= OnHeroKnockedOut;
        Player.Landed -= OnHeroLanded;
    }

    private void OnHeroHit(Node2D target)
    {
        if (!IsInstanceValid(target))
        {
            return;
        }

        bool heavy = Player.CurrentAttack.HitStopFrames >= HeavyHitStopFrames;
        Spawn(target.GlobalPosition + new Vector2(0f, -HitFxHeight), heavy ? HeavySparkAmount : HitSparkAmount, Palette.EnergyPale, 1f, -1f);
        Level.ShakeCamera(heavy ? HeavyShake : HitShake, ShakeTime);
    }

    private void OnHeroHurt(float damage)
    {
        Spawn(Player.GlobalPosition + new Vector2(0f, -HitFxHeight), HitSparkAmount, Palette.AlarmGlow, 1f, -1f);
        Level.ShakeCamera(HitShake, ShakeTime);
    }

    private void OnHeroKnockedOut() => Level.ShakeCamera(KnockdownShake, ShakeTime);

    private void OnHeroLanded() =>
        Spawn(Player.GlobalPosition, LandDustAmount, LandDustColor, LandDustScale, LandDustFlashEnergy);

    /// <param name="flashEnergy">Peak energy of the effect's own light; negative keeps the scene's value.</param>
    private void Spawn(Vector2 position, int amount, Color color, float scale, float flashEnergy)
    {
        if (ImpactFxScene is null)
        {
            return;
        }

        Node2D parent = FxParent ?? Level;
        if (!IsInstanceValid(parent) || !parent.IsInsideTree())
        {
            return;
        }

        ImpactFx fx = ImpactFxScene.Instantiate<ImpactFx>();
        fx.SparkColor = color;
        if (flashEnergy >= 0f)
        {
            fx.FlashEnergy = flashEnergy;
        }

        parent.AddChild(fx);
        fx.GlobalPosition = position;
        fx.Play(amount, scale);
    }
}
