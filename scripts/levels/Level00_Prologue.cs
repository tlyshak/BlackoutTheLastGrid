using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Core;
using BlackoutLastGrid.Props;
using BlackoutLastGrid.Ui;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Level 0 — the mine-dump «Зміна» (GAME_DESIGN §3): three rooms side by side (забій,
/// вентиляційна, вихід) with the tutorial, the fan panel that has no power, the alarm, Dan's
/// loss, the first stealth moment past the guards, the foreman's fine and the hand-over to
/// Level 1. The scripted flow is a <see cref="Stage"/> sequence driven purely by signals from the
/// props (prompts, doors, panel, exit, cutscene) — no per-frame logic beyond the debug label.
/// The level owns the HUD prompt with a fixed priority: a usable interactable in reach, then the
/// stage hint, then the active tutorial hint, then the text of an unusable prop in reach (a dead
/// panel); nothing shows while a cutscene plays.
/// </summary>
public partial class Level00_Prologue : LevelBase
{
    /// <summary>Beats of the prologue, in order.</summary>
    public enum Stage
    {
        /// <summary>Intro cutscene: Rey and Dan at the shift.</summary>
        Intro,
        /// <summary>Room 1, tutorial prompts, up to Door_1.</summary>
        Tutorial,
        /// <summary>Room 2, up to the fan panel.</summary>
        Ventilation,
        /// <summary>The panel failed for lack of power; its cutscene plays.</summary>
        NoPower,
        /// <summary>Alarm lights, guards spawned, Dan's cutscene.</summary>
        Alarm,
        /// <summary>Door_2 open; room 3 with the guards, up to the exit.</summary>
        Escape,
        /// <summary>Foreman cutscene and the fine.</summary>
        Foreman,
        /// <summary>Closing cutscene: the dead station in the window.</summary>
        Ending,
        /// <summary>Hand-over to Level 1 requested.</summary>
        Done,
    }

    /// <summary>Emitted on every stage change with the new stage's name (for tests and the debug label).</summary>
    [Signal]
    public delegate void StageChangedEventHandler(string stage);

    /// <summary>Energy taken from the shift by the foreman at the end.</summary>
    [Export] public float FinePenalty { get; set; } = 20f;

    /// <summary>Full on-off cycle of an alarm light, in seconds.</summary>
    [Export] public float AlarmBlinkPeriod { get; set; } = 0.5f;

    /// <summary>Peak energy of an alarm light.</summary>
    [Export] public float AlarmLightEnergy { get; set; } = 1.4f;

    /// <summary>Base darkness once the alarm is on (a touch redder than the mine's blue-black).</summary>
    [Export] public Color AlarmDarkness { get; set; } = new(0.11f, 0.04f, 0.05f);

    /// <summary>Seconds the darkness takes to shift to <see cref="AlarmDarkness"/>.</summary>
    [Export] public float AlarmFadeTime { get; set; } = 1f;

    /// <summary>Real seconds the alarm is seen before Dan's cutscene starts.</summary>
    [Export] public float AlarmToDanDelay { get; set; } = 1.5f;

    /// <summary>Whether the player may advance cutscene lines by hand.</summary>
    [Export] public bool CutsceneSkippable { get; set; } = true;

    /// <summary>Prompt shown for a ready interactable; {0} is its prompt text.</summary>
    [Export] public string PromptFormat { get; set; } = "E: {0}";

    /// <summary>Stage hint while the alarm beat plays.</summary>
    [Export] public string AlarmPromptText { get; set; } = "ТРИВОГА — вентиляцію нижніх горизонтів вимкнено";

    /// <summary>Stage hint after Dan's cutscene until the hero passes Door_2.</summary>
    [Export] public string EscapePromptText { get; set; } = "Двері відчинено. Охорона зачищає горизонт →";

    /// <summary>Intro cutscene lines.</summary>
    [Export] public string[] IntroLines { get; set; } = System.Array.Empty<string>();

    /// <summary>Lines after the fan panel fails.</summary>
    [Export] public string[] NoPowerLines { get; set; } = System.Array.Empty<string>();

    /// <summary>Dan's loss.</summary>
    [Export] public string[] DanLines { get; set; } = System.Array.Empty<string>();

    /// <summary>The foreman's verdict.</summary>
    [Export] public string[] ForemanLines { get; set; } = System.Array.Empty<string>();

    /// <summary>Closing lines: the dead station and the decision.</summary>
    [Export] public string[] EndLines { get; set; } = System.Array.Empty<string>();

    /// <summary>Level loaded after the closing cutscene.</summary>
    [Export] public PackedScene NextLevel { get; set; } = null!;

    /// <summary>Room the hero starts in.</summary>
    [Export] public RoomBounds StartRoom { get; set; } = null!;

    /// <summary>On-screen label showing the stage, the hero's state and jump height.</summary>
    [Export] public Label DebugLabel { get; set; } = null!;

    /// <summary>HUD showing the energy bar and the prompt.</summary>
    [Export] public HUD Hud { get; set; } = null!;

    /// <summary>Text overlay used for every cutscene.</summary>
    [Export] public Cutscene Cutscene { get; set; } = null!;

    /// <summary>Base darkness of the mine, tinted by the alarm.</summary>
    [Export] public CanvasModulate Darkness { get; set; } = null!;

    /// <summary>Parent of the tutorial prompts; paused with the hero during cutscenes.</summary>
    [Export] public Node2D Tutorial { get; set; } = null!;

    /// <summary>Dan's placeholder, standing by the hatch during the intro and gone below afterwards.</summary>
    [Export] public Node2D? DanFigure { get; set; }

    /// <summary>Passage from the забій to the вентиляційна; locked until the flashlight hint is done.</summary>
    [Export] public Door Door1 { get; set; } = null!;

    /// <summary>Passage from the вентиляційна to the exit room; locked until the alarm.</summary>
    [Export] public Door Door2 { get; set; } = null!;

    /// <summary>The hint that unlocks <see cref="Door1"/> once completed.</summary>
    [Export] public TutorialPrompt FlashlightPrompt { get; set; } = null!;

    /// <summary>The fan panel; unpowered, so its sequence ends in <c>FailedNoPower</c>.</summary>
    [Export] public PowerPanel FanPanel { get; set; } = null!;

    /// <summary>Parent of the red <c>PH_AlarmLight</c> lights, blinked after the alarm.</summary>
    [Export] public Node2D AlarmLights { get; set; } = null!;

    /// <summary>Spawns the two guards in the exit room at the alarm; frozen once the hero reaches the exit.</summary>
    [Export] public WaveSpawner GuardSpawner { get; set; } = null!;

    /// <summary>The lift cage trigger that ends the escape.</summary>
    [Export] public Area2D Exit { get; set; } = null!;

    private Stage _stage = Stage.Intro;
    private string _playerState = string.Empty;
    private int _height = -1;
    private Interactable? _currentInteractable;
    private string? _interactablePrompt;
    private TutorialPrompt? _activeHint;
    private string? _stagePrompt;
    private bool _noPowerPending;
    private Tween? _alarmTween;
    private Tween? _darknessTween;
    private SceneTreeTimer? _danTimer;

    /// <summary>The current beat of the prologue.</summary>
    public Stage CurrentStage => _stage;

    /// <inheritdoc/>
    public override void _Ready()
    {
        base._Ready();
        ApplyRoomBounds(StartRoom);
        Cutscene.Skippable = CutsceneSkippable;

        Player.StateChanged += OnPlayerStateChanged;
        Player.InteractableChanged += OnInteractableChanged;
        Cutscene.Finished += OnCutsceneFinished;
        Door1.Entered += OnDoor1Entered;
        Door2.Entered += OnDoor2Entered;
        FlashlightPrompt.Completed += OnFlashlightPromptCompleted;
        FanPanel.FailedNoPower += OnFanPanelFailedNoPower;
        FanPanel.Finished += OnFanPanelFinished;
        Exit.BodyEntered += OnExitBodyEntered;
        foreach (Node child in Tutorial.GetChildren())
        {
            if (child is TutorialPrompt hint)
            {
                // The hint is this level's own child, so the captured reference cannot outlive the connection.
                hint.Shown += () => OnHintShown(hint);
                hint.Completed += () => OnHintCompleted(hint);
            }
        }

        _playerState = Player.CurrentStateName;
        RefreshLabel();
        PlayCutscene(IntroLines);
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        base._ExitTree();
        Player.StateChanged -= OnPlayerStateChanged;
        Player.InteractableChanged -= OnInteractableChanged;
        Cutscene.Finished -= OnCutsceneFinished;
        Door1.Entered -= OnDoor1Entered;
        Door2.Entered -= OnDoor2Entered;
        FlashlightPrompt.Completed -= OnFlashlightPromptCompleted;
        FanPanel.FailedNoPower -= OnFanPanelFailedNoPower;
        FanPanel.Finished -= OnFanPanelFinished;
        Exit.BodyEntered -= OnExitBodyEntered;
        FollowInteractable(null);
        KillTween(ref _alarmTween);
        KillTween(ref _darknessTween);
        if (_danTimer is not null)
        {
            _danTimer.Timeout -= OnDanTimerTimeout;
            _danTimer = null;
        }
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

    // ---- flow ---------------------------------------------------------------------------

    private void SetStage(Stage stage)
    {
        if (stage == _stage)
        {
            return;
        }

        _stage = stage;
        RefreshLabel();
        EmitSignalStageChanged(stage.ToString());
    }

    private void OnCutsceneFinished()
    {
        switch (_stage)
        {
            case Stage.Intro:
                if (DanFigure is not null)
                {
                    DanFigure.Visible = false;   // Dan went down to the lower level
                }

                SetStage(Stage.Tutorial);
                ResumeActors();
                break;
            case Stage.NoPower:
                StartAlarm();
                break;
            case Stage.Alarm:
                SetStage(Stage.Escape);
                SetStagePrompt(EscapePromptText);
                ResumeActors();
                break;
            case Stage.Foreman:
                SetStage(Stage.Ending);
                PlayCutscene(EndLines);
                break;
            case Stage.Ending:
                SetStage(Stage.Done);
                GoToLevel(NextLevel);
                break;
            default:
                ResumeActors();
                break;
        }
    }

    private void OnFlashlightPromptCompleted() => Door1.Locked = false;

    private void OnDoor1Entered(Player player)
    {
        PassDoor(Door1);
        SetStage(Stage.Ventilation);
    }

    private void OnDoor2Entered(Player player)
    {
        PassDoor(Door2);
        SetStagePrompt(null);
    }

    /// <summary>Moves the hero past <paramref name="door"/>, confines camera and floor to its room and shuts the gate behind (belt-scroll: no way back).</summary>
    private void PassDoor(Door door)
    {
        ApplyRoomBounds(door.TargetRoom);
        Player.Position += door.ArrivalOffset;
        door.Locked = true;
    }

    private void OnFanPanelFailedNoPower()
    {
        if (_stage == Stage.Ventilation)
        {
            _noPowerPending = true;   // the panel still flashes red; the cutscene starts once it releases the hero
        }
    }

    private void OnFanPanelFinished(bool success)
    {
        if (!_noPowerPending)
        {
            return;
        }

        _noPowerPending = false;
        SetStage(Stage.NoPower);
        PlayCutscene(NoPowerLines);
    }

    private void StartAlarm()
    {
        SetStage(Stage.Alarm);
        SetStagePrompt(AlarmPromptText);
        Door2.Locked = false;
        StartAlarmLights();
        GuardSpawner.StartWave();

        _danTimer = GetTree().CreateTimer(AlarmToDanDelay, processAlways: true, processInPhysics: false, ignoreTimeScale: true);
        _danTimer.Timeout += OnDanTimerTimeout;
    }

    private void OnDanTimerTimeout()
    {
        if (_danTimer is not null)
        {
            _danTimer.Timeout -= OnDanTimerTimeout;
            _danTimer = null;
        }

        if (!IsInstanceValid(this) || !IsInsideTree())
        {
            return;
        }

        SetStagePrompt(null);
        PlayCutscene(DanLines);
    }

    private void OnExitBodyEntered(Node2D body)
    {
        if (_stage != Stage.Escape || !ReferenceEquals(body, Player))
        {
            return;
        }

        SetStage(Stage.Foreman);
        GuardSpawner.ProcessMode = ProcessModeEnum.Disabled;   // the chase is over; guards (and their hitboxes) leave the simulation
        GameState.Instance.AddEnergy(-FinePenalty);
        PlayCutscene(ForemanLines);
    }

    // ---- cutscenes and pausing ----------------------------------------------------------

    /// <summary>
    /// Freezes the hero and the hints (a disabled <c>CollisionObject2D</c> also leaves the physics
    /// space, so nothing triggers meanwhile), hides the prompt and plays <paramref name="lines"/>.
    /// </summary>
    private void PlayCutscene(string[] lines)
    {
        SetActorsPaused(true);
        Cutscene.Play(lines);
        RefreshPrompt();
    }

    /// <summary>Unfreezes at the end of the frame, so the press that closed the cutscene is not re-read by the hero.</summary>
    private void ResumeActors() => Callable.From(ResumeActorsNow).CallDeferred();

    private void ResumeActorsNow()
    {
        SetActorsPaused(false);
        RefreshPrompt();
    }

    private void SetActorsPaused(bool paused)
    {
        ProcessModeEnum mode = paused ? ProcessModeEnum.Disabled : ProcessModeEnum.Inherit;
        Player.ProcessMode = mode;
        Tutorial.ProcessMode = mode;
    }

    // ---- alarm --------------------------------------------------------------------------

    private void StartAlarmLights()
    {
        KillTween(ref _alarmTween);
        KillTween(ref _darknessTween);

        _darknessTween = CreateTween();
        _darknessTween.TweenProperty(Darkness, "color", AlarmDarkness, AlarmFadeTime);

        float half = AlarmBlinkPeriod * 0.5f;
        _alarmTween = CreateTween().SetLoops();
        _alarmTween.SetParallel(true);
        foreach (Node child in AlarmLights.GetChildren())
        {
            if (child is PointLight2D light)
            {
                light.Energy = 0f;
                light.Enabled = true;
                _alarmTween.TweenProperty(light, "energy", AlarmLightEnergy, half);
            }
        }

        _alarmTween.Chain();
        foreach (Node child in AlarmLights.GetChildren())
        {
            if (child is PointLight2D light)
            {
                _alarmTween.TweenProperty(light, "energy", 0f, half);
            }
        }
    }

    private static void KillTween(ref Tween? tween)
    {
        if (tween is not null && tween.IsValid())
        {
            tween.Kill();
        }

        tween = null;
    }

    // ---- prompts ------------------------------------------------------------------------

    private void OnHintShown(TutorialPrompt hint)
    {
        if (ReferenceEquals(hint, FlashlightPrompt) && Player.Flashlight.IsOn)
        {
            hint.Complete();   // the lamp is already on: pressing F now would only switch it off
            return;
        }

        _activeHint = hint;
        RefreshPrompt();
    }

    private void OnHintCompleted(TutorialPrompt hint)
    {
        if (ReferenceEquals(_activeHint, hint))
        {
            _activeHint = null;
            RefreshPrompt();
        }
    }

    private void SetStagePrompt(string? text)
    {
        _stagePrompt = text;
        RefreshPrompt();
    }

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

    /// <summary>A ready prop gets the key hint ("E: Зарядити"); a busy or unusable one shows its text as is.</summary>
    private string FormatPrompt(Interactable interactable, string text) =>
        interactable.IsActive || !interactable.CanInteract ? text : string.Format(PromptFormat, text);

    /// <summary><c>true</c> while the prop in reach is busy or ready — its prompt outranks every hint; a dead one ranks last.</summary>
    private bool IsInteractableUsable() =>
        _currentInteractable is not null && IsInstanceValid(_currentInteractable)
        && (_currentInteractable.IsActive || _currentInteractable.CanInteract);

    /// <summary>Shows the highest-priority prompt: usable interactable, stage hint, active tutorial hint, unusable interactable; none during a cutscene.</summary>
    private void RefreshPrompt()
    {
        if (Cutscene.IsPlaying)
        {
            Hud.HidePrompt();
            return;
        }

        string? hint = _activeHint is not null && _activeHint.IsShowing ? _activeHint.Text : null;
        string? text = IsInteractableUsable()
            ? _interactablePrompt
            : _stagePrompt ?? hint ?? _interactablePrompt;
        if (text is null)
        {
            Hud.HidePrompt();
        }
        else
        {
            Hud.ShowPrompt(text);
        }
    }

    private void OnPlayerStateChanged(string from, string to)
    {
        _playerState = to;
        RefreshLabel();
    }

    private void RefreshLabel() => DebugLabel.Text = $"Stage: {_stage}  State: {_playerState}  z: {_height}";
}
