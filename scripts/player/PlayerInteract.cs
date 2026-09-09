using BlackoutLastGrid.Core;
using BlackoutLastGrid.Props;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// Using the current <see cref="Interactable"/>: the hero stands still, the prop runs the
/// interaction (instant for an outlet, a button sequence for a panel) and its <c>Finished</c>
/// signal returns the hero to Idle on the next physics step — not inside the handler, so the
/// key that completed a sequence is not re-read by Idle in the same frame. Moves and attacks
/// are ignored meanwhile; a hit reaction (<c>Hurt</c>/<c>KO</c>) may interrupt, in which case
/// <see cref="Exit"/> cancels the prop.
/// </summary>
public partial class PlayerInteract : PlayerState
{
    private Interactable? _interactable;
    private bool _finished;

    /// <inheritdoc/>
    public override void Enter(State? previous)
    {
        _finished = false;
        Player.ApplyFloorMove(Vector2.Zero);
        Player.PlayAnimation(AnimIdle);

        Interactable? target = Player.CurrentInteractable;
        if (target is null || !target.CanInteract)
        {
            TransitionTo(StateIdle);
            return;
        }

        _interactable = target;
        target.Finished += OnFinished;
        target.Begin(Player);   // an outlet finishes synchronously; the panel finishes from its own physics step
    }

    /// <inheritdoc/>
    public override void Exit(State? next)
    {
        Interactable? target = _interactable;
        _interactable = null;
        if (target is null || !IsInstanceValid(target))
        {
            return;
        }

        target.Finished -= OnFinished;
        if (target.IsActive)
        {
            target.Cancel();
        }
    }

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        // Leave when the prop reported completion, or when it vanished / went inactive without
        // reporting (freed mid-sequence, cancelled by the level) so the hero is never stuck here.
        if (_finished || _interactable is null || !IsInstanceValid(_interactable) || !_interactable.IsActive)
        {
            TransitionTo(StateIdle);
            return;
        }

        Player.ApplyFloorMove(Vector2.Zero);
    }

    private void OnFinished(bool success) => _finished = true;
}
