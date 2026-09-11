using BlackoutLastGrid.Core;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// Base for the companion's states: resolves the owning <see cref="Companion"/> (the state
/// machine's parent) once and shares the state names. None of the three states can fail — Dan
/// has no health, no hurt and no death of his own — and no transition ever originates inside a
/// state: every one is a level call (<see cref="Companion.HoldAt"/>, <see cref="Companion.LeadTo"/>,
/// <see cref="Companion.Resume"/>).
/// </summary>
public abstract partial class CompanionState : State
{
    /// <summary>State (node) names used for transitions.</summary>
    public const string StateFollow = "Follow";

    /// <inheritdoc cref="StateFollow"/>
    public const string StateWait = "Wait";

    /// <inheritdoc cref="StateFollow"/>
    public const string StateLead = "Lead";

    /// <summary>The companion this state controls.</summary>
    protected Companion Companion { get; private set; } = null!;

    /// <inheritdoc/>
    public override void _Ready() => Companion = Machine.GetParent<Companion>();
}
