using System.Collections.Generic;
using Godot;

namespace BlackoutLastGrid.Core;

/// <summary>
/// Hands out attack slots so that no more than <see cref="MaxAttackers"/> enemies swing at the
/// hero at the same time (the Streets of Rage rule): an enemy asks
/// <see cref="TryAcquireAttackSlot"/> before entering its Attack state, holds the slot while it
/// attacks and gives it back with <see cref="ReleaseAttackSlot"/>. Enemies without a slot keep
/// their distance. Slots of freed nodes are dropped automatically. Owned by the level (one per
/// scene) and injected into enemies by the level or the <see cref="WaveSpawner"/>.
/// </summary>
public partial class EnemyDirector : Node
{
    /// <summary>Maximum number of enemies allowed in their Attack state at once.</summary>
    [Export] public int MaxAttackers { get; set; } = 2;

    private readonly List<Node> _attackers = new();

    /// <summary>Number of enemies currently holding an attack slot (freed nodes excluded).</summary>
    public int ActiveAttackers
    {
        get
        {
            Prune();
            return _attackers.Count;
        }
    }

    /// <summary><c>true</c> while at least one attack slot is free.</summary>
    public bool HasFreeSlot => ActiveAttackers < MaxAttackers;

    /// <summary>
    /// Reserves an attack slot for <paramref name="attacker"/>. Returns <c>true</c> when the slot
    /// is granted (or was already held by the same node), <c>false</c> when all slots are taken.
    /// </summary>
    /// <param name="attacker">The enemy about to attack.</param>
    public bool TryAcquireAttackSlot(Node attacker)
    {
        Prune();
        if (_attackers.Contains(attacker))
        {
            return true;
        }

        if (_attackers.Count >= MaxAttackers)
        {
            return false;
        }

        _attackers.Add(attacker);
        return true;
    }

    /// <summary>Gives the slot held by <paramref name="attacker"/> back; a no-op when it holds none.</summary>
    /// <param name="attacker">The enemy that finished (or aborted) its attack.</param>
    public void ReleaseAttackSlot(Node attacker) => _attackers.Remove(attacker);

    private void Prune()
    {
        for (int i = _attackers.Count - 1; i >= 0; i--)
        {
            Node attacker = _attackers[i];
            if (!IsInstanceValid(attacker) || attacker.IsQueuedForDeletion())
            {
                _attackers.RemoveAt(i);
            }
        }
    }
}
