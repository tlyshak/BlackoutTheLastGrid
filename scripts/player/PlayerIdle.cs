using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>Standing still. Leaves for an attack, Jump, or Move on any direction input.</summary>
public partial class PlayerIdle : PlayerState
{
    /// <inheritdoc/>
    public override void Enter(State? previous) => Player.PlayAnimation(AnimIdle);

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        if (TryStartAction())
        {
            return;
        }

        Vector2 input = Player.MoveInput;
        if (input != Vector2.Zero)
        {
            TransitionTo(StateMove);
            return;
        }

        Player.ApplyFloorMove(Vector2.Zero);
    }
}
