using BlackoutLastGrid.Core;
using BlackoutLastGrid.Enemies;
using BlackoutLastGrid.Props;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Placeholder room for movement/combat/interaction tasks: a floor band, two <c>PH_</c> props at
/// different depths, dummies, an outlet, a power panel with a lamp it switches on, a standing
/// guard, a wave spawner, a lit zone, side walls and a debug label. Owns the hero, the camera,
/// the restart rule and the HUD prompt forwarding through <see cref="LevelBase"/>; reads only the
/// hero's public API (the <c>StateChanged</c> signal and <c>Height</c>) for its debug label.
/// </summary>
public partial class TestRoom : LevelBase
{
    /// <summary>On-screen label showing the current state and jump height.</summary>
    [Export] public Label DebugLabel { get; set; } = null!;

    /// <summary>Attack-slot director shared by every enemy in the room.</summary>
    [Export] public EnemyDirector Director { get; set; } = null!;

    /// <summary>The guard placed in the scene (not spawned by a wave); it gets the hero as target here.</summary>
    [Export] public Guard? StandingGuard { get; set; }

    /// <summary>The panel whose activation switches <see cref="Lamp"/> on.</summary>
    [Export] public PowerPanel Panel { get; set; } = null!;

    /// <summary>Ceiling lamp above the panel; disabled until the panel is activated.</summary>
    [Export] public PointLight2D Lamp { get; set; } = null!;

    /// <summary>Placeholder lamp fixture, brightened when the lamp goes on.</summary>
    [Export] public Node2D? LampBody { get; set; }

    /// <summary>Modulate applied to <see cref="LampBody"/> once lit.</summary>
    [Export] public Color LampLitModulate { get; set; } = new(2.5f, 2.2f, 1.6f);

    private string _state = string.Empty;
    private int _height = -1;

    /// <inheritdoc/>
    public override void _Ready()
    {
        base._Ready();
        StandingGuard?.SetTarget(Player, Director);
        Player.StateChanged += OnPlayerStateChanged;
        Panel.Activated += OnPanelActivated;
        _state = Player.CurrentStateName;
        RefreshLabel();
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        base._ExitTree();
        Player.StateChanged -= OnPlayerStateChanged;
        Panel.Activated -= OnPanelActivated;
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

    private void OnPanelActivated()
    {
        Lamp.Enabled = true;
        if (LampBody is not null)
        {
            LampBody.Modulate = LampLitModulate;
        }
    }

    private void RefreshLabel() => DebugLabel.Text = $"State: {_state}  z: {_height}";
}
