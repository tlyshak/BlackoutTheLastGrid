using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Common behaviour of a playable level: the camera follows the hero along X (clamped by the
/// camera's own limits, which a <see cref="WaveSpawner"/> may tighten while a wave is locked),
/// and the hero's KO restarts the level after <see cref="RestartDelay"/> — hit-stop cancelled,
/// run state reset, current scene reloaded. Concrete levels derive from it and add their props.
/// </summary>
public partial class LevelBase : Node2D
{
    /// <summary>The hero instance placed in this level.</summary>
    [Export] public Player Player { get; set; } = null!;

    /// <summary>Level camera; optional for rooms that fit one screen.</summary>
    [Export] public Camera2D? Camera { get; set; }

    /// <summary>Real seconds between the hero's KO and the scene reload (hit-stop does not stretch it).</summary>
    [Export] public float RestartDelay { get; set; } = 1f;

    private SceneTreeTimer? _restartTimer;

    /// <summary><c>true</c> between the hero's KO and the reload.</summary>
    public bool IsRestartPending => _restartTimer is not null;

    /// <inheritdoc/>
    public override void _Ready()
    {
        Player.KnockedOut += OnPlayerKnockedOut;
        FollowPlayer();
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        Player.KnockedOut -= OnPlayerKnockedOut;
        if (_restartTimer is not null)
        {
            _restartTimer.Timeout -= OnRestartTimeout;
            _restartTimer = null;
        }
    }

    /// <inheritdoc/>
    public override void _Process(double delta) => FollowPlayer();

    /// <summary>
    /// Restarts the level now: lifts any hit-stop, resets the run state and reloads the current
    /// scene. Does nothing (with a warning) when the tree has no current scene, e.g. a level
    /// instanced by a test.
    /// </summary>
    public void RestartLevel()
    {
        HitStop.Cancel();
        GameState.Instance.ResetRun();

        SceneTree tree = GetTree();
        if (tree.CurrentScene is null)
        {
            GD.PushWarning($"{Name}: no current scene to reload (level not started as the main scene).");
            return;
        }

        tree.ReloadCurrentScene();
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

        _restartTimer = GetTree().CreateTimer(RestartDelay, processAlways: true, processInPhysics: false, ignoreTimeScale: true);
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
