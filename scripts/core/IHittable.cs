namespace BlackoutLastGrid.Core;

/// <summary>
/// Implemented by the root node of any scene that owns a <c>Hurtbox</c> (the hero, enemies,
/// the training dummy). <see cref="Hitbox"/> calls it after the depth check passed.
/// </summary>
public interface IHittable
{
    /// <summary>Applies one hit. Return <c>false</c> to report that the hit was ignored (already KO, invulnerable).</summary>
    /// <param name="hit">Damage, knockback and timing of the hit.</param>
    bool TakeHit(in HitInfo hit);
}
