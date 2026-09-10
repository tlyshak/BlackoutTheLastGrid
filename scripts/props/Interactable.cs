using BlackoutLastGrid.Actors;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// Base of every prop the hero can use with the <c>interact</c> action (outlets, power panels,
/// pickups). It is a passive <see cref="Area2D"/> on the Interactable layer that the hero's
/// interaction area finds; it never looks for the hero itself. The hero's Interact state calls
/// <see cref="Begin"/>, waits for <see cref="FinishedEventHandler"/> and calls <see cref="Cancel"/>
/// if it has to leave early (a hit, a state change). Prompt text for the HUD comes from
/// <see cref="CurrentPrompt"/> and changes are announced with <see cref="PromptChangedEventHandler"/>.
/// </summary>
/// <remarks>
/// Scene contract: root <c>Area2D</c> with <c>collision_layer = 32</c> (6 Interactable),
/// <c>collision_mask = 0</c>, <c>monitoring = false</c>, <c>monitorable = true</c> and one
/// <c>CollisionShape2D</c> for the interaction radius; the origin is the contact point with the floor.
/// </remarks>
public abstract partial class Interactable : Area2D
{
    /// <summary>Emitted when an interaction started with <see cref="Begin"/> is over; <paramref name="success"/> is <c>false</c> when it was refused or failed.</summary>
    [Signal]
    public delegate void FinishedEventHandler(bool success);

    /// <summary>Emitted whenever <see cref="CurrentPrompt"/> changes (cooldown countdown, sequence progress).</summary>
    [Signal]
    public delegate void PromptChangedEventHandler(string text);

    /// <summary>Prompt shown by the HUD while this prop is the hero's current interactable and ready.</summary>
    [Export] public string PromptText { get; set; } = "Use";

    /// <summary>Stable id for save/load (T-09); unused until then.</summary>
    [Export] public string SaveId { get; set; } = string.Empty;

    /// <summary><c>true</c> while the hero may start an interaction (the Interact state is only entered when this holds).</summary>
    public virtual bool CanInteract => true;

    /// <summary><c>true</c> between <see cref="Begin"/> and the matching <see cref="FinishedEventHandler"/> or <see cref="Cancel"/>.</summary>
    public bool IsActive { get; private set; }

    /// <summary>Text the HUD should show right now; <see cref="PromptText"/> unless the prop overrides it.</summary>
    public virtual string CurrentPrompt => PromptText;

    /// <summary>
    /// Starts the interaction for <paramref name="player"/>. Implementations either finish at once
    /// (an outlet) or stay active and finish later (a panel sequence); both end with
    /// <see cref="Finish"/>. Called by the hero's Interact state only.
    /// </summary>
    /// <param name="player">The hero using the prop.</param>
    public abstract void Begin(Player player);

    /// <summary>Aborts an active interaction without emitting <see cref="FinishedEventHandler"/>; a no-op when idle.</summary>
    public virtual void Cancel() => IsActive = false;

    /// <summary>Marks the interaction as running; call at the start of <see cref="Begin"/>.</summary>
    protected void Activate() => IsActive = true;

    /// <summary>Ends the interaction and emits <see cref="FinishedEventHandler"/>.</summary>
    /// <param name="success"><c>false</c> when the interaction was refused or failed.</param>
    protected void Finish(bool success)
    {
        IsActive = false;
        EmitSignalFinished(success);
    }

    /// <summary>Announces the current <see cref="CurrentPrompt"/> to listeners.</summary>
    protected void NotifyPromptChanged() => EmitSignalPromptChanged(CurrentPrompt);
}
