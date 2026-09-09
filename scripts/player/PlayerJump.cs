using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// In the air along the height axis. Horizontal/depth movement continues while airborne (as in
/// Streets of Rage); on landing returns to Move if a direction is held, else Idle. Entering the
/// state while already airborne (a reaction interrupted a jump) resumes the fall instead of
/// launching a second jump.
/// </summary>
public partial class PlayerJump : PlayerState
{
    /// <inheritdoc/>
    public override void Enter(State? previous)
    {
        if (!Player.IsAirborne)
        {
            Player.StartJump();
        }

        Player.PlayAnimation(AnimJump, AnimIdle);
    }

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        Vector2 input = Player.MoveInput;
        Player.ApplyFloorMove(input);
        Player.IntegrateJump(delta);

        if (Player.IsAirborne)
        {
            return;
        }

        TransitionTo(input == Vector2.Zero ? StateIdle : StateMove);
    }
}
