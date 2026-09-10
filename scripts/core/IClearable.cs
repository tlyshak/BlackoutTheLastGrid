namespace BlackoutLastGrid.Core;

/// <summary>
/// Implemented by the root node of any obstacle that can be taken out of the hero's way — a gas
/// pocket the extractor blows out, a flooded drift the pump empties, a debris pile a heavy attack
/// breaks. Clearing is one-way and permanent (GAME_DESIGN §3): cutting the power back off never
/// brings the obstacle back, so the player never has to hold a timer or a water level in their head.
/// </summary>
public interface IClearable
{
    /// <summary><c>true</c> once <see cref="Clear"/> has run; never goes back to <c>false</c>.</summary>
    bool IsCleared { get; }

    /// <summary>Removes the obstacle for good. Idempotent: calling it on a cleared obstacle does nothing.</summary>
    void Clear();
}
