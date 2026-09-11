using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Ui;

/// <summary>
/// Pause overlay instanced by every level and wired to it through <c>LevelBase.Pause</c>. It owns
/// <c>SceneTree.Paused</c> and nothing else: «Quit to Main Menu» only emits
/// <see cref="QuitToMenuRequestedEventHandler"/>, because scene transitions belong to the level.
/// Opening cancels a hit-stop in flight, so the menu can never come up over a frozen
/// <c>Engine.TimeScale</c> (the freeze is dropped, not resumed afterwards).
/// </summary>
public partial class PauseMenu : CanvasLayer
{
    private static readonly StringName ActionPause = "pause";

    /// <summary>Emitted when the game is paused (<c>true</c>) or resumed (<c>false</c>) by this menu.</summary>
    [Signal]
    public delegate void PauseToggledEventHandler(bool paused);

    /// <summary>Emitted when the player chose to abandon the run and go back to the main menu.</summary>
    [Signal]
    public delegate void QuitToMenuRequestedEventHandler();

    /// <summary>Overlay root, hidden while the game runs.</summary>
    [Export] public Control Root { get; set; } = null!;

    /// <summary>Button that resumes the game.</summary>
    [Export] public Button ResumeButton { get; set; } = null!;

    /// <summary>Button that opens <see cref="Settings"/>.</summary>
    [Export] public Button SettingsButton { get; set; } = null!;

    /// <summary>Button that asks the level to return to the main menu.</summary>
    [Export] public Button QuitButton { get; set; } = null!;

    /// <summary>The settings overlay instanced under this menu.</summary>
    [Export] public SettingsMenu Settings { get; set; } = null!;

    /// <summary><c>false</c> lets a level suppress pausing for a beat without touching the menu.</summary>
    [Export] public bool PauseEnabled { get; set; } = true;

    /// <summary><c>true</c> while the pause overlay is on screen.</summary>
    public bool IsOpen => Root.Visible;

    /// <inheritdoc/>
    public override void _Ready()
    {
        ProcessMode = ProcessModeEnum.Always;
        Root.Visible = false;

        ResumeButton.Pressed += Resume;
        SettingsButton.Pressed += OnSettingsPressed;
        QuitButton.Pressed += OnQuitPressed;
        Settings.Closed += OnSettingsClosed;
        SetProcessUnhandledInput(true);
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        ResumeButton.Pressed -= Resume;
        SettingsButton.Pressed -= OnSettingsPressed;
        QuitButton.Pressed -= OnQuitPressed;
        Settings.Closed -= OnSettingsClosed;

        if (IsOpen)
        {
            GetTree().Paused = false;   // a menu freed while open must not leave the tree frozen
        }
    }

    /// <inheritdoc/>
    public override void _UnhandledInput(InputEvent @event)
    {
        // The settings overlay consumes Escape itself; the explicit guard keeps the behaviour
        // independent of input propagation order.
        if (!PauseEnabled || Settings.IsOpen || !@event.IsActionPressed(ActionPause))
        {
            return;
        }

        if (IsOpen)
        {
            Resume();
        }
        else
        {
            Open();
        }

        GetViewport().SetInputAsHandled();
    }

    /// <summary>Pauses the tree and shows the menu.</summary>
    public void Open()
    {
        HitStop.Cancel();   // first: a freeze in flight would stall the menu's own tweens and timers
        GetTree().Paused = true;
        Root.Visible = true;
        ResumeButton.GrabFocus();
        EmitSignalPauseToggled(true);
    }

    /// <summary>Hides the menu and unpauses the tree.</summary>
    public void Resume()
    {
        Root.Visible = false;   // hiding releases the focused button
        GetTree().Paused = false;
        EmitSignalPauseToggled(false);
    }

    private void OnSettingsPressed() => Settings.Open();

    private void OnSettingsClosed()
    {
        if (IsOpen)
        {
            SettingsButton.GrabFocus();
        }
    }

    private void OnQuitPressed()
    {
        Resume();
        EmitSignalQuitToMenuRequested();
    }
}
