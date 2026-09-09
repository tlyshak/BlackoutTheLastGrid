using BlackoutLastGrid.Actors;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Placeholder room for movement/combat tasks: a floor band, two <c>PH_</c> props at different
/// depths, side walls and a debug label. Owns the <see cref="Player"/> instance and reads only
/// its public state for the label.
/// </summary>
public partial class TestRoom : Node2D
{
    /// <summary>The hero instance placed in this room.</summary>
    [Export] public Player Player { get; set; } = null!;

    /// <summary>On-screen label showing the current state and jump height.</summary>
    [Export] public Label DebugLabel { get; set; } = null!;

    private string _lastState = string.Empty;
    private int _lastHeight = -1;

    /// <inheritdoc/>
    public override void _Process(double delta)
    {
        string state = Player.CurrentStateName;
        int height = Mathf.RoundToInt(Player.Height);
        if (state == _lastState && height == _lastHeight)
        {
            return;
        }

        _lastState = state;
        _lastHeight = height;
        DebugLabel.Text = $"State: {state}  z: {height}";
    }
}
