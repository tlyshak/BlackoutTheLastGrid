using BlackoutLastGrid.Actors;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Placeholder room for movement/combat tasks: a floor band, two <c>PH_</c> props at different
/// depths, dummies, side walls and a debug label. Owns the <see cref="Player"/> instance and reads
/// only its public API: the <c>StateChanged</c> signal and <c>Height</c>.
/// </summary>
public partial class TestRoom : Node2D
{
    /// <summary>The hero instance placed in this room.</summary>
    [Export] public Player Player { get; set; } = null!;

    /// <summary>On-screen label showing the current state and jump height.</summary>
    [Export] public Label DebugLabel { get; set; } = null!;

    private string _state = string.Empty;
    private int _height = -1;

    /// <inheritdoc/>
    public override void _Ready()
    {
        Player.StateChanged += OnPlayerStateChanged;
        _state = Player.CurrentStateName;
        RefreshLabel();
    }

    /// <inheritdoc/>
    public override void _ExitTree() => Player.StateChanged -= OnPlayerStateChanged;

    /// <inheritdoc/>
    public override void _Process(double delta)
    {
        int height = Mathf.RoundToInt(Player.Height);
        if (height != _height)
        {
            _height = height;
            RefreshLabel();
        }
    }

    private void OnPlayerStateChanged(string from, string to)
    {
        _state = to;
        RefreshLabel();
    }

    private void RefreshLabel() => DebugLabel.Text = $"State: {_state}  z: {_height}";
}
