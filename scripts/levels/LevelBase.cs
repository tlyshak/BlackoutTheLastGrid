using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Core;
using BlackoutLastGrid.Props;
using BlackoutLastGrid.Ui;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Common behaviour of a playable level: the camera follows the hero along X with a lookahead
/// (clamped by the camera's own limits, which a <see cref="WaveSpawner"/> may tighten while a
/// wave is locked, or which <see cref="ApplyRoomBounds"/> moves from room to room) and can be
/// shaken by <see cref="ShakeCamera"/>; the prop in reach is forwarded to the <see cref="Hud"/>
/// as a prompt (<see cref="RefreshPrompt"/>, which levels with several prompt sources override);
/// each room's ambient FX group runs only while that room is the active one; the hero's KO
/// restarts the level after <see cref="RestartDelay"/> — hit-stop cancelled, run state reset,
/// current scene reloaded (with <c>Main</c> as the current scene that re-instantiates the level)
/// — unless a <see cref="Checkpoint"/> has been reached, in which case it costs a soft respawn
/// after <see cref="RespawnDelay"/> instead (<see cref="RespawnAtCheckpoint"/>: no reload, the
/// world exactly as the player left it); and <see cref="GoToLevel"/> hands the run over to the
/// next level. The level also owns the <see cref="Pause"/> menu instanced in its scene and the
/// way out of the run (<see cref="GoToMainMenu"/>). Every transition lifts the pause and the
/// hit-stop first, so the next scene can never come up frozen. Concrete levels derive from it and
/// add their props.
/// </summary>
public partial class LevelBase : Node2D
{
    /// <summary>Emitted when the hero reaches a checkpoint, which becomes the one a death returns him to.</summary>
    [Signal]
    public delegate void CheckpointArmedEventHandler(Checkpoint checkpoint);

    /// <summary>Emitted after a soft respawn; a level that wants to rewind its own scripted state does it here.</summary>
    [Signal]
    public delegate void RespawnedEventHandler();

    /// <summary>The hero instance placed in this level.</summary>
    [Export] public Player Player { get; set; } = null!;

    /// <summary>Level camera; optional for rooms that fit one screen.</summary>
    [Export] public Camera2D? Camera { get; set; }

    /// <summary>Pause overlay instanced in the level scene; optional, so a test-instanced level works without one.</summary>
    [Export] public PauseMenu? Pause { get; set; }

    /// <summary>HUD showing the energy bar and the interaction prompt; optional for a level instanced by a test.</summary>
    [Export] public HUD? Hud { get; set; }

    /// <summary>
    /// The brother escorting the hero through this level, when it has one. The level owns the two
    /// places he cannot recover from on his own — a room change and a respawn, both of which
    /// teleport the hero — and tells him the hero was relocated there
    /// (<see cref="Actors.Companion.OnHeroRelocated"/>, the third anti-stuck safeguard from the
    /// plan; the other two live in <see cref="Actors.Companion"/> itself). What he does about it
    /// depends on his state: a follower is warped behind the hero, a guide or a scripted extra
    /// stays on his own point unless the hero is now half a screen away.
    /// </summary>
    [Export] public Companion? Companion { get; set; }

    /// <summary>Prompt shown for a ready interactable; {0} is its prompt text.</summary>
    [Export] public string PromptFormat { get; set; } = "E: {0}";

    /// <summary>Real seconds between the hero's KO and the scene reload (hit-stop does not stretch it).</summary>
    [Export] public float RestartDelay { get; set; } = 1f;

    /// <summary>
    /// Container whose <see cref="Checkpoint"/> children are connected on ready; leave it empty and
    /// the level keeps the plain "a KO reloads the level" rule.
    /// </summary>
    [Export] public Node2D? Checkpoints { get; set; }

    /// <summary>Real seconds between the hero's KO and a checkpoint respawn (hit-stop does not stretch it).</summary>
    [Export] public float RespawnDelay { get; set; } = 0.9f;

    /// <summary>Energy floor a checkpoint respawn hands back, so a death can never start a spiral.</summary>
    [Export] public float MinRespawnEnergy { get; set; } = 30f;

    /// <summary>Px the camera leads the hero in his direction of travel; 0 disables the lookahead.</summary>
    [Export] public float CameraLookahead { get; set; } = 90f;

    /// <summary>Rate (1/s) at which the lookahead approaches its target; higher is snappier.</summary>
    [Export] public float CameraLookaheadSpeed { get; set; } = 5f;

    /// <summary>Group whose <see cref="GpuParticles2D"/> members are never switched on by the room gating (the level drives them itself).</summary>
    [Export] public string ManualFxGroup { get; set; } = "fx_manual";

    /// <summary>Scene loaded when the player abandons the run from the pause menu.</summary>
    [Export(PropertyHint.File, "*.tscn")]
    public string MainMenuScenePath { get; set; } = "res://scenes/ui/MainMenu.tscn";

    private readonly RandomNumberGenerator _rng = new();
    private SceneTreeTimer? _restartTimer;
    private Checkpoint? _checkpoint;
    private float _checkpointEnergy;
    private Interactable? _currentInteractable;
    private string? _interactablePrompt;
    private Node2D? _activeFx;
    private float _lookahead;
    private float _shakeAmplitude;
    private float _shakeDuration;
    private float _shakeTime;
    private float _shakeFlip = 1f;

    /// <summary><c>true</c> between the hero's KO and the reload (or the checkpoint respawn).</summary>
    public bool IsRestartPending => _restartTimer is not null;

    /// <summary>The checkpoint a death returns the hero to, or <c>null</c> while none has been reached.</summary>
    public Checkpoint? ArmedCheckpoint => _checkpoint;

    /// <summary>Formatted prompt of the prop currently in reach, or <c>null</c> when there is none.</summary>
    protected string? InteractablePrompt => _interactablePrompt;

    /// <inheritdoc/>
    public override void _Ready()
    {
        _rng.Randomize();
        Player.KnockedOut += OnPlayerKnockedOut;
        Player.InteractableChanged += OnInteractableChanged;
        if (Pause is not null)
        {
            Pause.QuitToMenuRequested += GoToMainMenu;
        }

        ConnectCheckpoints(true);
        FollowPlayer(0.0);
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        Player.KnockedOut -= OnPlayerKnockedOut;
        Player.InteractableChanged -= OnInteractableChanged;
        if (Pause is not null)
        {
            Pause.QuitToMenuRequested -= GoToMainMenu;
        }

        ConnectCheckpoints(false);
        FollowInteractable(null);
        if (Camera is not null)
        {
            Camera.Offset = Vector2.Zero;   // a level freed mid-shake must not leave the camera displaced
        }

        if (_restartTimer is not null)
        {
            _restartTimer.Timeout -= OnRestartTimeout;
            _restartTimer = null;
        }
    }

    /// <inheritdoc/>
    public override void _Process(double delta) => FollowPlayer(delta);

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
    /// Arms <paramref name="checkpoint"/> and snapshots the energy the hero has right now, so a
    /// respawn restores what he had instead of handing out a free refill.
    /// </summary>
    /// <param name="checkpoint">The checkpoint a death returns the hero to from now on.</param>
    public void SetCheckpoint(Checkpoint checkpoint)
    {
        _checkpoint = checkpoint;
        _checkpointEnergy = GameState.Instance.Energy;
        EmitSignalCheckpointArmed(checkpoint);
    }

    /// <summary>
    /// Brings the hero back at the armed checkpoint <b>without reloading the scene</b>: the hit-stop
    /// and the pause are lifted, the hero is revived (lamp forced off) at the checkpoint, its room
    /// bounds are re-applied and the energy is restored to the snapshot, never below
    /// <see cref="MinRespawnEnergy"/>. Everything the player changed in the world — cleared rubble,
    /// drained water, powered machines — stays exactly as it was: one mistake costs seconds, not the
    /// puzzle. The run state is <b>not</b> reset. Falls back to <see cref="RestartLevel"/> when no
    /// checkpoint is armed.
    /// </summary>
    public void RespawnAtCheckpoint()
    {
        if (_checkpoint is null || !IsInstanceValid(_checkpoint))
        {
            RestartLevel();
            return;
        }

        HitStop.Cancel();
        GetTree().Paused = false;
        Player.Revive();
        Player.GlobalPosition = _checkpoint.RespawnPosition;
        if (_checkpoint.Room is not null)
        {
            ApplyRoomBounds(_checkpoint.Room);
        }

        GameState state = GameState.Instance;
        state.Energy = _checkpoint.RestoresFullEnergy
            ? state.MaxEnergy
            : Mathf.Max(_checkpointEnergy, MinRespawnEnergy);
        Companion?.OnHeroRelocated();   // the hero jumped back to the checkpoint; the brother decides by his state
        EmitSignalRespawned();
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
        SwitchRoomFx(room.Fx);
        Companion?.OnHeroRelocated();   // a door hop teleports the hero; walking after him could strand a follower
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

    /// <summary>
    /// Shakes the camera for <paramref name="duration"/> seconds with a linearly decaying
    /// amplitude, written to <see cref="Camera2D.Offset"/> only — the limits (and therefore a
    /// <see cref="WaveSpawner"/> lock) are never touched. A shake already running is replaced only
    /// by a stronger one, and the offset is set to exactly zero when the last one runs out.
    /// Driven by the scaled <c>_Process</c> delta, so a hit-stop holds it instead of skipping it.
    /// </summary>
    /// <param name="amplitude">Peak offset in px.</param>
    /// <param name="duration">Seconds the shake decays over.</param>
    public void ShakeCamera(float amplitude, float duration)
    {
        if (Camera is null || amplitude <= 0f || duration <= 0f || (amplitude < _shakeAmplitude && _shakeTime > 0f))
        {
            return;
        }

        _shakeAmplitude = amplitude;
        _shakeDuration = duration;
        _shakeTime = duration;
    }

    /// <summary><c>true</c> while the prop in reach is busy or ready — its prompt outranks every hint; a dead one ranks last.</summary>
    protected bool IsInteractableUsable() =>
        _currentInteractable is not null && IsInstanceValid(_currentInteractable)
        && (_currentInteractable.IsActive || _currentInteractable.CanInteract);

    /// <summary>Shows <paramref name="text"/> in the HUD, or hides the prompt when it is <c>null</c>. A level without a HUD does nothing.</summary>
    /// <param name="text">Prompt text, already formatted.</param>
    protected void ShowPrompt(string? text)
    {
        // Author's rule: a speech bubble that would collide with a HUD prompt loses to the prompt.
        // Suppressing only hides it — the line is not lost and reappears when the prompt clears.
        Companion?.SetBubbleSuppressed(text is not null);
        if (Hud is null)
        {
            return;
        }

        if (text is null)
        {
            Hud.HidePrompt();
        }
        else
        {
            Hud.ShowPrompt(text);
        }
    }

    /// <summary>
    /// Pushes the current prompt to the HUD. The base rule is "the prop in reach, or nothing";
    /// a level with more prompt sources (stage hints, tutorial hints, cutscenes) overrides this
    /// with its own priority and calls the base helpers.
    /// </summary>
    protected virtual void RefreshPrompt() => ShowPrompt(_interactablePrompt);

    /// <summary>A ready prop gets the key hint ("E: Charge"); a busy or unusable one shows its text as is.</summary>
    private string FormatPrompt(Interactable interactable, string text) =>
        interactable.IsActive || !interactable.CanInteract ? text : string.Format(PromptFormat, text);

    private void OnInteractableChanged(Interactable? current)
    {
        FollowInteractable(current);
        _interactablePrompt = current is null ? null : FormatPrompt(current, current.CurrentPrompt);
        RefreshPrompt();
    }

    private void OnPromptChanged(string text)
    {
        if (_currentInteractable is not null)
        {
            _interactablePrompt = FormatPrompt(_currentInteractable, text);
            RefreshPrompt();
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

    /// <summary>Stops the ambient FX of the room being left and starts those of <paramref name="next"/>.</summary>
    private void SwitchRoomFx(Node2D? next)
    {
        if (ReferenceEquals(_activeFx, next))
        {
            return;
        }

        if (_activeFx is not null && IsInstanceValid(_activeFx))
        {
            SetFxActive(_activeFx, false);
        }

        _activeFx = next;
        if (next is not null)
        {
            SetFxActive(next, true);
        }
    }

    /// <summary>
    /// Switches an ambient-FX group on or off: the emitters stop (or resume, unless they are in
    /// <see cref="ManualFxGroup"/> and driven by the level itself) and the whole group leaves the
    /// process loop, which also freezes its <c>AnimationPlayer</c> loops. Walked only on a room
    /// change — three times in a playthrough — never per frame. The groups hold no collision
    /// shapes, so a disabled group never removes a body from the physics space.
    /// </summary>
    private void SetFxActive(Node2D group, bool on)
    {
        if (on)
        {
            group.ProcessMode = ProcessModeEnum.Inherit;
        }

        SetEmittersActive(group, on);
        if (!on)
        {
            group.ProcessMode = ProcessModeEnum.Disabled;
        }
    }

    private void SetEmittersActive(Node node, bool on)
    {
        if (node is GpuParticles2D particles && (!on || !particles.IsInGroup(ManualFxGroup)))
        {
            particles.Emitting = on;
        }

        foreach (Node child in node.GetChildren())
        {
            SetEmittersActive(child, on);
        }
    }

    private void FollowPlayer(double delta)
    {
        if (Camera is null)
        {
            return;
        }

        float target = Player.Velocity.X > 0f ? CameraLookahead : Player.Velocity.X < 0f ? -CameraLookahead : 0f;
        _lookahead = Mathf.Lerp(_lookahead, target, 1f - Mathf.Exp(-CameraLookaheadSpeed * (float)delta));

        Vector2 position = Camera.GlobalPosition;
        position.X = Player.GlobalPosition.X + _lookahead;
        Camera.GlobalPosition = position;

        UpdateShake(delta);
    }

    private void UpdateShake(double delta)
    {
        if (_shakeTime <= 0f || Camera is null)
        {
            return;
        }

        _shakeTime -= (float)delta;
        if (_shakeTime <= 0f)
        {
            _shakeTime = 0f;
            _shakeAmplitude = 0f;
            Camera.Offset = Vector2.Zero;   // exactly zero, never a lerp tail
            return;
        }

        float strength = _shakeAmplitude * (_shakeTime / _shakeDuration);
        _shakeFlip = -_shakeFlip;   // alternating X keeps it reading as a shake, not as drift
        Camera.Offset = new Vector2(_shakeFlip * strength, _rng.RandfRange(-strength, strength));
    }

    /// <summary>
    /// Subscribes to (or unsubscribes from) every <see cref="Checkpoint"/> under
    /// <see cref="Checkpoints"/>. Walked once on ready and once on teardown, never per frame; a
    /// level without the container does nothing at all, which is why its KO behaviour is unchanged.
    /// </summary>
    /// <param name="connect"><c>true</c> subscribes, <c>false</c> drops the subscriptions.</param>
    private void ConnectCheckpoints(bool connect)
    {
        if (Checkpoints is null || !IsInstanceValid(Checkpoints))
        {
            return;
        }

        foreach (Node child in Checkpoints.GetChildren())
        {
            if (child is not Checkpoint checkpoint)
            {
                continue;
            }

            if (connect)
            {
                checkpoint.Reached += OnCheckpointReached;
            }
            else
            {
                checkpoint.Reached -= OnCheckpointReached;
            }
        }
    }

    private void OnCheckpointReached(Checkpoint checkpoint) => SetCheckpoint(checkpoint);

    private void OnPlayerKnockedOut()
    {
        if (_restartTimer is not null)
        {
            return;
        }

        // ignoreTimeScale keeps the delay out of the hit-stop; processAlways stays false so the
        // level never reloads (or respawns) under an open pause menu.
        float delay = _checkpoint is null ? RestartDelay : RespawnDelay;
        _restartTimer = GetTree().CreateTimer(delay, processAlways: false, processInPhysics: false, ignoreTimeScale: true);
        _restartTimer.Timeout += OnRestartTimeout;
    }

    private void OnRestartTimeout()
    {
        if (!IsInstanceValid(this) || !IsInsideTree())
        {
            return;   // the level was freed before the delay ran out (test teardown, scene change)
        }

        _restartTimer = null;
        if (_checkpoint is null)
        {
            RestartLevel();
            return;
        }

        RespawnAtCheckpoint();
    }
}
