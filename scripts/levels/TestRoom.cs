using BlackoutLastGrid.Core;
using BlackoutLastGrid.Enemies;

using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Props;
using BlackoutLastGrid.Ui;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Placeholder room for movement/combat/interaction tasks: a floor band, two <c>PH_</c> props at
/// different depths, dummies, an outlet, a power panel with a lamp it switches on, a standing
/// guard, a wave spawner, a lit zone, side walls and a debug label. Owns the hero, the camera and
/// the restart rule through <see cref="LevelBase"/>; reads only the hero's public API (the
/// <c>StateChanged</c> / <c>InteractableChanged</c> signals and <c>Height</c>) and forwards the
/// current interactable's prompt to the <see cref="HUD"/>.
/// </summary>
public partial class TestRoom : LevelBase
{
    /// <summary>On-screen label showing the current state and jump height.</summary>
    [Export] public Label DebugLabel { get; set; } = null!;

    /// <summary>Attack-slot director shared by every enemy in the room.</summary>
    [Export] public EnemyDirector Director { get; set; } = null!;

    /// <summary>The guard placed in the scene (not spawned by a wave); it gets the hero as target here.</summary>
    [Export] public Guard? StandingGuard { get; set; }

    /// <summary>HUD showing the energy bar and the interaction prompt.</summary>
    [Export] public HUD Hud { get; set; } = null!;

    /// <summary>The panel whose activation switches <see cref="Lamp"/> on.</summary>
    [Export] public PowerPanel Panel { get; set; } = null!;

    /// <summary>Ceiling lamp above the panel; disabled until the panel is activated.</summary>
    [Export] public PointLight2D Lamp { get; set; } = null!;

    /// <summary>Placeholder lamp fixture, brightened when the lamp goes on.</summary>
    [Export] public Node2D? LampBody { get; set; }

    /// <summary>Modulate applied to <see cref="LampBody"/> once lit.</summary>
    [Export] public Color LampLitModulate { get; set; } = new(2.5f, 2.2f, 1.6f);

    /// <summary>Prompt shown for a ready interactable; {0} is its prompt text.</summary>
    [Export] public string PromptFormat { get; set; } = "E: {0}";

    private string _state = string.Empty;
    private int _height = -1;
    private Interactable? _currentInteractable;

    /// <inheritdoc/>
    public override void _Ready()
    {
        base._Ready();
        StandingGuard?.SetTarget(Player, Director);
        Player.StateChanged += OnPlayerStateChanged;
        Player.InteractableChanged += OnInteractableChanged;
        Panel.Activated += OnPanelActivated;
        _state = Player.CurrentStateName;
        RefreshLabel();
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        base._ExitTree();
        Player.StateChanged -= OnPlayerStateChanged;
        Player.InteractableChanged -= OnInteractableChanged;
        Panel.Activated -= OnPanelActivated;
        FollowInteractable(null);
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

    private void OnInteractableChanged(Interactable? current)
    {
        FollowInteractable(current);
        if (current is null)
        {
            Hud.HidePrompt();
            return;
        }

        Hud.ShowPrompt(FormatPrompt(current, current.CurrentPrompt));
    }

    private void OnPromptChanged(string text)
    {
        if (_currentInteractable is not null)
        {
            Hud.ShowPrompt(FormatPrompt(_currentInteractable, text));
        }
    }

    private void OnPanelActivated()
    {
        Lamp.Enabled = true;
        if (LampBody is not null)
        {
            LampBody.Modulate = LampLitModulate;
        }
    }

    /// <summary>Subscribes to the prompt of <paramref name="next"/> and drops the previous subscription.</summary>
    private void FollowInteractable(Interactable? next)
    {
        if (_currentInteractable is not null && IsInstanceValid(_currentInteractable))
        {
            _currentInteractable.PromptChanged -= OnPromptChanged;
        }

        _currentInteractable = next;
        if (next is not null)
        {
            next.PromptChanged += OnPromptChanged;
        }
    }

    /// <summary>A ready prop gets the key hint ("E: Зарядити"); a busy or unusable one shows its text as is.</summary>
    private string FormatPrompt(Interactable interactable, string text) =>
        interactable.IsActive || !interactable.CanInteract ? text : string.Format(PromptFormat, text);

    private void RefreshLabel() => DebugLabel.Text = $"State: {_state}  z: {_height}";
}
