using BlackoutLastGrid.Core;
using BlackoutLastGrid.Enemies;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Placeholder room for movement/combat tasks: a floor band, two <c>PH_</c> props at different
/// depths, dummies, a standing guard, a wave spawner, a lit zone, side walls and a debug label.
/// Owns the hero, the camera and the restart rule through <see cref="LevelBase"/>; reads only the
/// hero's public API (the <c>StateChanged</c> signal and <c>Height</c>) for the label.
/// </summary>
public partial class TestRoom : LevelBase
{
    /// <summary>On-screen label showing the current state and jump height.</summary>
    [Export] public Label DebugLabel { get; set; } = null!;

    /// <summary>Attack-slot director shared by every enemy in the room.</summary>
    [Export] public EnemyDirector Director { get; set; } = null!;

    /// <summary>The guard placed in the scene (not spawned by a wave); it gets the hero as target here.</summary>
    [Export] public Guard? StandingGuard { get; set; }

    private string _state = string.Empty;
    private int _height = -1;

    /// <inheritdoc/>
    public override void _Ready()
    {
        base._Ready();
        StandingGuard?.SetTarget(Player, Director);
        Player.StateChanged += OnPlayerStateChanged;
        _state = Player.CurrentStateName;
        RefreshLabel();
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        base._ExitTree();
        Player.StateChanged -= OnPlayerStateChanged;
    }

    /// <inheritdoc/>
    public override void _Process(double delta)
    {
        base._Process(delta);
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
