using Godot;

namespace BlackoutLastGrid.Core;

/// <summary>
/// Everything a target needs to react to one hit. Built by the attacker's state from its
/// <c>[Export]</c> tunables; passed to <see cref="Hitbox.Activate"/> and then to
/// <see cref="IHittable.TakeHit"/>.
/// </summary>
/// <param name="Damage">Damage in hp (dummies) or energy units (the hero, from T-06).</param>
/// <param name="Knockback">Horizontal push in px/s, already signed by the attacker's facing.</param>
/// <param name="Knockdown"><c>true</c> when the hit floors the target (heavy attacks).</param>
/// <param name="HitStopFrames">Physics frames of hit-stop the attacker requests on a successful hit.</param>
/// <param name="DepthTolerance">Max |ΔY| between attacker and target for the hit to connect, in px.</param>
/// <param name="SourceY">Attacker's floor Y (depth) at the moment of the hit.</param>
public readonly record struct HitInfo(
    float Damage,
    float Knockback,
    bool Knockdown,
    int HitStopFrames,
    float DepthTolerance,
    float SourceY);
