using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>Walking in 8 directions on the floor plane. Attacks and Jump interrupt; back to Idle without input.</summary>
public partial class PlayerMove : PlayerState
{
    /// <inheritdoc/>
    public override void Enter(State? previous) => Player.PlayAnimation(AnimWalk, AnimIdle);

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        if (TryStartAction())
        {
            return;
        }

        Vector2 input = Player.MoveInput;
        if (input == Vector2.Zero)
        {
            TransitionTo(StateIdle);
            return;
        }

        Player.ApplyFloorMove(input);
    }
}
