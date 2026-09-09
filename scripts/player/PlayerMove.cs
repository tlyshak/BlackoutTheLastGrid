using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>Walking in 8 directions on the floor plane. Back to Idle without input, Jump on <c>jump</c>.</summary>
public partial class PlayerMove : PlayerState
{
    /// <inheritdoc/>
    public override void Enter(State? previous) => Player.PlayAnimation(AnimWalk, AnimIdle);

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        if (Player.JumpPressed)
        {
            TransitionTo(StateJump);
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
