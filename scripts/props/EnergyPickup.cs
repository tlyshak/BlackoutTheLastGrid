using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// A powerbank lying where a guard fell (GAME_DESIGN §3: the first thing the player takes by
/// force is the energy of those who took it from him). Taken with <c>interact</c> like an
/// <see cref="Outlet"/> — a decision, not a walk-over — it adds <see cref="Amount"/> to
/// <see cref="GameState.Energy"/> once, announces it with <see cref="CollectedEventHandler"/> and
/// frees itself. It glows on its own (<c>PH_Glow</c>) so it reads in a mine that has no other
/// light. Dropped by <see cref="Enemies.Guard"/> through <see cref="Enemies.Guard.DropScene"/>.
/// </summary>
/// <remarks>
/// Scene contract: the <see cref="Interactable"/> contract (root <c>Area2D</c>, layer 32
/// Interactable, mask 0, <c>monitoring = false</c>, <c>monitorable = true</c>, one circular
/// <c>CollisionShape2D</c> for the reach) with the origin at the floor contact so it y-sorts with
/// the guard it fell from. It has no hurtbox and no depth rule — the reach circle is the rule.
/// </remarks>
public partial class EnergyPickup : Interactable
{
    /// <summary>Emitted after the energy was added, with the amount, before <c>Finished(true)</c>.</summary>
    [Signal]
    public delegate void CollectedEventHandler(float amount);

    /// <summary>Energy added on pickup.</summary>
    [Export] public float Amount { get; set; } = 25f;

    /// <summary><c>true</c> frees the node (deferred) once it was taken; a fixture keeps it to assert on it.</summary>
    [Export] public bool FreeAfterPickup { get; set; } = true;

    private bool _taken;

    /// <summary><c>true</c> once the bank was taken; the prop refuses a second use.</summary>
    public bool IsTaken => _taken;

    /// <inheritdoc/>
    public override bool CanInteract => !_taken;

    /// <inheritdoc/>
    public override void Begin(Player player)
    {
        Activate();
        if (!CanInteract)
        {
            Finish(false);
            return;
        }

        _taken = true;
        GameState.Instance.AddEnergy(Amount);
        EmitSignalCollected(Amount);
        Finish(true);
        NotifyPromptChanged();
        if (FreeAfterPickup)
        {
            // Deferred: the hero's Interact state still holds this prop for the rest of the step.
            CallDeferred(MethodName.QueueFree);
        }
    }
}
