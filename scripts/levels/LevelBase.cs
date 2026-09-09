using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Core;
using BlackoutLastGrid.Ui;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Common behaviour of a playable level: the camera follows the hero along X (clamped by the
/// camera's own limits, which a <see cref="WaveSpawner"/> may tighten while a wave is locked, or
/// which <see cref="ApplyRoomBounds"/> moves from room to room), the hero's KO restarts the level
/// after <see cref="RestartDelay"/> — hit-stop cancelled, run state reset, current scene reloaded
/// (with <c>Main</c> as the current scene that re-instantiates the level) — and
/// <see cref="GoToLevel"/> hands the run over to the next level. The level also owns the
/// <see cref="Pause"/> menu instanced in its scene and the way out of the run
/// (<see cref="GoToMainMenu"/>). Every transition lifts the pause and the hit-stop first, so the
/// next scene can never come up frozen. Concrete levels derive from it and add their props.
/// </summary>
public partial class LevelBase : Node2D
{
    /// <summary>The hero instance placed in this level.</summary>
    [Export] public Player Player { get; set; } = null!;

    /// <summary>Level camera; optional for rooms that fit one screen.</summary>
    [Export] public Camera2D? Camera { get; set; }

    /// <summary>Pause overlay instanced in the level scene; optional, so a test-instanced level works without one.</summary>
    [Export] public PauseMenu? Pause { get; set; }

    /// <summary>Real seconds between the hero's KO and the scene reload (hit-stop does not stretch it).</summary>
    [Export] public float RestartDelay { get; set; } = 1f;

    /// <summary>Scene loaded when the player abandons the run from the pause menu.</summary>
    [Export(PropertyHint.File, "*.tscn")]
    public string MainMenuScenePath { get; set; } = "res://scenes/ui/MainMenu.tscn";

    private SceneTreeTimer? _restartTimer;

    /// <summary><c>true</c> between the hero's KO and the reload.</summary>
    public bool IsRestartPending => _restartTimer is not null;

    /// <inheritdoc/>
    public override void _Ready()
    {
        Player.KnockedOut += OnPlayerKnockedOut;
        if (Pause is not null)
        {
            Pause.QuitToMenuRequested += GoToMainMenu;
        }

        FollowPlayer();
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        Player.KnockedOut -= OnPlayerKnockedOut;
        if (Pause is not null)
        {
            Pause.QuitToMenuRequested -= GoToMainMenu;
        }

        if (_restartTimer is not null)
        {
            _restartTimer.Timeout -= OnRestartTimeout;
            _restartTimer = null;
        }
    }

    /// <inheritdoc/>
    public override void _Process(double delta) => FollowPlayer();

    /// <summary>
    /// Restarts the level now: lifts any hit-stop and the pause, resets the run state and reloads
    /// the current scene. Does nothing (with a warning) when the tree has no current scene, e.g. a
    /// level instanced by a test.
    /// </summary>
    public void RestartLevel()
    {
        HitStop.Cancel();
        GetTree().Paused = false;
        GameState.Instance.ResetRun();

        SceneTree tree = GetTree();
        if (tree.CurrentScene is null)
        {
            GD.PushWarning($"{Name}: no current scene to reload (level not started as the main scene).");
            return;
        }

        tree.ReloadCurrentScene();
    }

    /// <summary>
    /// Leaves this level for <paramref name="next"/>: lifts any hit-stop and the pause, records the
    /// destination in <see cref="GameState.CurrentScenePath"/> and swaps the current scene at the
    /// end of the frame (deferred, so it is safe from signal handlers and physics callbacks).
    /// </summary>
    /// <param name="next">The level scene to load.</param>
    public void GoToLevel(PackedScene next)
    {
        HitStop.Cancel();
        GetTree().Paused = false;
        GameState.Instance.CurrentScenePath = next.ResourcePath;
        GetTree().CallDeferred(SceneTree.MethodName.ChangeSceneToPacked, next);
    }

    /// <summary>
    /// Abandons the run and returns to <see cref="MainMenuScenePath"/>: lifts the hit-stop and the
    /// pause, resets the run state and swaps the current scene at the end of the frame. Wired to
    /// <see cref="PauseMenu.QuitToMenuRequestedEventHandler"/> — the menu never changes scenes itself.
    /// </summary>
    public void GoToMainMenu()
    {
        HitStop.Cancel();
        GetTree().Paused = false;
        GameState.Instance.ResetRun();
        GetTree().CallDeferred(SceneTree.MethodName.ChangeSceneToFile, MainMenuScenePath);
    }

    /// <summary>
    /// Makes <paramref name="room"/> the playable area: the camera limits become its
    /// <see cref="RoomBounds.Rect"/> and the hero's floor band its floor bounds. Called by the
    /// level at start and on every door transition.
    /// </summary>
    /// <param name="room">The room to confine the camera and the hero to.</param>
    public void ApplyRoomBounds(RoomBounds room)
    {
        Player.FloorTop = room.FloorTop;
        Player.FloorBottom = room.FloorBottom;
        if (Camera is null)
        {
            return;
        }

        Rect2 rect = room.Rect;
        Camera.LimitLeft = Mathf.RoundToInt(rect.Position.X);
        Camera.LimitTop = Mathf.RoundToInt(rect.Position.Y);
        Camera.LimitRight = Mathf.RoundToInt(rect.End.X);
        Camera.LimitBottom = Mathf.RoundToInt(rect.End.Y);
    }

    private void FollowPlayer()
    {
        if (Camera is null)
        {
            return;
        }

        Vector2 position = Camera.GlobalPosition;
        position.X = Player.GlobalPosition.X;
        Camera.GlobalPosition = position;
    }

    private void OnPlayerKnockedOut()
    {
        if (_restartTimer is not null)
        {
            return;
        }

        // ignoreTimeScale keeps the delay out of the hit-stop; processAlways stays false so the
        // level never reloads under an open pause menu.
        _restartTimer = GetTree().CreateTimer(RestartDelay, processAlways: false, processInPhysics: false, ignoreTimeScale: true);
        _restartTimer.Timeout += OnRestartTimeout;
    }

    private void OnRestartTimeout()
    {
        if (!IsInstanceValid(this) || !IsInsideTree())
        {
            return;   // the level was freed before the delay ran out (test teardown, scene change)
        }

        _restartTimer = null;
        RestartLevel();
    }
}
