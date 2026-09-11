using System.Collections.Generic;
using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Core;
using BlackoutLastGrid.Props;
using BlackoutLastGrid.Ui;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Level 0 — «Shift» (GAME_DESIGN §3): the coal-mine escape, seven segments from the face to the
/// surface. One methane blast seals the way back, one power unit is shared by every machine, light
/// kills in the gas, the sealing crew cannot be fought, the brother walks the whole run and does not
/// come out of it. Nothing here is a new mechanic: the level is placement, story flow and text over
/// the props of T-07s-a (<see cref="PowerCircuit"/>, <see cref="PoweredMachine"/>,
/// <see cref="Hoist"/>, <see cref="GasZone"/>, <see cref="WatchZone"/>, <see cref="DebrisPile"/>,
/// <see cref="CaveIn"/>, <see cref="Checkpoint"/>, <see cref="Companion"/>).
/// </summary>
/// <remarks>
/// <para>
/// The flow is driven by signals only — there is no per-frame logic beyond the debug label. Room
/// boundaries and story beats both hang off <see cref="Checkpoint.Label"/>: crossing a checkpoint
/// applies its room's bounds (camera limits, floor band, ambient FX gating), arms the respawn and
/// fires that segment's beat, so "a checkpoint before every hazard" is the structure of the level
/// and not a rule somebody has to remember.
/// </para>
/// <para>
/// <b>Circuit reachability invariant.</b> Only three cave-ins exist. The first falls before anything
/// is powered; the second powers <i>down</i> every machine it seals away and hands the unit to the
/// cage floodlight ahead of it (<see cref="OnUpperCollapsed"/>); after the third no machine is ever
/// needed again. So at no moment can the single power unit be stranded behind rubble, and the run
/// can never lock itself.
/// </para>
/// <para>
/// The brother can neither be hurt nor lost, and nothing in the level ever waits for him. He is held
/// in place for exactly three scripted beats — the blast, the crew (silence, §3), the farewell — and
/// at the farewell the level drops its <see cref="LevelBase.Companion"/> reference so the follower's
/// own anti-stuck warps can never pull him through the last fall.
/// </para>
/// </remarks>
public partial class Level00_Prologue : LevelBase
{
    /// <summary>Beats of the prologue, in order.</summary>
    public enum Stage
    {
        /// <summary>Intro cutscene at the coal face.</summary>
        Intro,
        /// <summary>Segment 0: the shift is still working, the lights are on.</summary>
        Face,
        /// <summary>Segment 1: the blast, the dark, finding Dan.</summary>
        Blast,
        /// <summary>Segment 2: the flooded drift and the pump.</summary>
        Flood,
        /// <summary>Segment 3a: the gas pockets and the extractor.</summary>
        Gas,
        /// <summary>Segment 3b: the sealing crew.</summary>
        Crew,
        /// <summary>Segment 4: the upper horizon.</summary>
        Upper,
        /// <summary>Segment 5: the cage and the last switch-off.</summary>
        Cage,
        /// <summary>Segment 6: the last fall; Dan stays behind it.</summary>
        Farewell,
        /// <summary>Segment 7a: up top, the foreman's line.</summary>
        Surface,
        /// <summary>Segment 7b: the guard who wants Dan's powerbank.</summary>
        Fight,
        /// <summary>Closing cutscene: the dead plant behind, the lit centre ahead.</summary>
        Ending,
        /// <summary>Hand-over to Level 1 requested.</summary>
        Done,
    }

    /// <summary>Which cutscene is on screen, so <see cref="OnCutsceneFinished"/> knows what follows.</summary>
    private enum Beat
    {
        None,
        Intro,
        Blast,
        Farewell,
        Foreman,
        Guard,
        Ending,
    }

    /// <summary>Emitted on every stage change with the new stage's name (for tests and the debug label).</summary>
    [Signal]
    public delegate void StageChangedEventHandler(string stage);

    /// <summary>Energy the foreman fines the shift once the hero is up top.</summary>
    [Export] public float FinePenalty { get; set; } = 20f;

    /// <summary>Ambient light while the station lighting still burns (segment 0).</summary>
    [Export] public Color DarknessLit { get; set; } = Color.FromHtml("#8f97a3");

    /// <summary>Ambient light of the mine once the lamp string is gone (segments 1–6).</summary>
    [Export] public Color DarknessMine { get; set; } = Color.FromHtml("#0a0d14");

    /// <summary>Ambient light of an overcast morning on the surface (segment 7).</summary>
    [Export] public Color DarknessSurface { get; set; } = Color.FromHtml("#6b7280");

    /// <summary>Seconds the ambient light takes to move between those three values.</summary>
    [Export] public float DarknessFadeSeconds { get; set; } = 1.2f;

    /// <summary>Whether the player may advance cutscene lines by hand.</summary>
    [Export] public bool CutsceneSkippable { get; set; } = true;

    /// <summary>Seconds of quiet at the face before Dan's ambient line about the motor.</summary>
    [Export] public float AmbientLineSeconds { get; set; } = 8f;

    /// <summary>Seconds between Dan's two lines when the hero finds him after the blast.</summary>
    [Export] public float FoundFollowUpSeconds { get; set; } = 3f;

    // ---- cutscenes (docs/plans/t07s-b-prologue-rebuild/script-en.md) ----------------------

    /// <summary>Intro at the coal face.</summary>
    [Export] public string[] IntroLines { get; set; } = System.Array.Empty<string>();

    /// <summary>The spark, the blast, the lamp string going out.</summary>
    [Export] public string[] BlastLines { get; set; } = System.Array.Empty<string>();

    /// <summary>The last fall and the powerbank — Dan's death.</summary>
    [Export] public string[] FarewellLines { get; set; } = System.Array.Empty<string>();

    /// <summary>The lamp room: the fine and the missing report.</summary>
    [Export] public string[] ForemanLines { get; set; } = System.Array.Empty<string>();

    /// <summary>The guard who comes for the second powerbank.</summary>
    [Export] public string[] GuardLines { get; set; } = System.Array.Empty<string>();

    /// <summary>Closing lines: the dead plant behind, the lit centre ahead.</summary>
    [Export] public string[] EndLines { get; set; } = System.Array.Empty<string>();

    // ---- Dan's lines (script-en.md, "Зведена таблиця подія → репліка") --------------------

    /// <summary>Segment 0, the move hint.</summary>
    [Export] public string DanMoveLine { get; set; } = "Come on. Cart won't fill itself.";

    /// <summary>Segment 0, the jump hint.</summary>
    [Export] public string DanJumpLine { get; set; } = "Over the sleepers. Don't trip.";

    /// <summary>Segment 0, ambient — the conveyor motor that will give the spark.</summary>
    [Export] public string DanMotorLine { get; set; } = "You hear that motor? It's cooking.";

    /// <summary>Segment 1, the hero finds him.</summary>
    [Export] public string DanFoundLine { get; set; } = "Ray! Here! I'm all right.";

    /// <summary>Segment 1, three seconds later — he is convincing himself, not Ray.</summary>
    [Export] public string DanUnhurtLine { get; set; } = "Nothing's broken. Nothing's broken.";

    /// <summary>Segment 1, the head-lamp hint.</summary>
    [Export] public string DanLampLine { get; set; } = "Lamp on. I can't see my hands.";

    /// <summary>Segment 1, the first outlet.</summary>
    [Export] public string DanOutletLine { get; set; } = "That's your light. Don't waste it.";

    /// <summary>Segment 1, a light attack bounced off the timber.</summary>
    [Export] public string DanTimberLine { get; set; } = "Hit the prop, not the middle.";

    /// <summary>Segment 1, the timber pile is down.</summary>
    [Export] public string DanClearedLine { get; set; } = "There. Go.";

    /// <summary>Segment 1, the first roof fall.</summary>
    [Export] public string DanWayBackLine { get; set; } = "That's the way back gone.";

    /// <summary>Segment 2, the flooded drift.</summary>
    [Export] public string DanFloodLine { get; set; } = "Waist deep. Not walking through that.";

    /// <summary>Segment 2, the first refusal — the rule of the bus, said by a person.</summary>
    [Export] public string DanRuleLine { get; set; } = "Won't take both. Kill the lights.";

    /// <summary>Every later refusal.</summary>
    [Export] public string DanRefusedLine { get; set; } = "Same story. One at a time.";

    /// <summary>Segment 2, the work lights go out — the one line that says what the game is about.</summary>
    [Export] public string DanDarkLine { get; set; } = "Same as up top. Give here, take there.";

    /// <summary>Segment 2, the pump starts.</summary>
    [Export] public string DanPumpLine { get; set; } = "Dark it is, then.";

    /// <summary>Segment 3, walking up to the gas.</summary>
    [Export] public string DanGasNearLine { get; set; } = "Air's gone yellow. Don't light it.";

    /// <summary>Segment 3, the warning window — recognised by its shape, not read.</summary>
    [Export] public string DanGasLine { get; set; } = "LAMP OFF!";

    /// <summary>The same shout once the hero has already died here.</summary>
    [Export] public string DanGasAgainLine { get; set; } = "OFF! NOW!";

    /// <summary>Segment 3, the extractor cleared the pocket.</summary>
    [Export] public string DanGasClearedLine { get; set; } = "Breathe. It's moving now.";

    /// <summary>Segment 3, the pocket crossed in the dark instead.</summary>
    [Export] public string DanDarkCrossingLine { get; set; } = "Told you. Straight line, no light.";

    /// <summary>Segment 3, the crew comes into view — his last word before the silence.</summary>
    [Export] public string DanCrewLine { get; set; } = "Down.";

    /// <summary>Segment 3, past the crew: what they were actually doing.</summary>
    [Export] public string DanSealingLine { get; set; } = "They're not digging. They're sealing it.";

    /// <summary>Segment 4, the cage is in sight.</summary>
    [Export] public string DanCageSeenLine { get; set; } = "That's the cage. Ray, that's the cage.";

    /// <summary>Segment 4, a few steps on.</summary>
    [Export] public string DanCagePowerLine { get; set; } = "Cage has power up top. It'll lift.";

    /// <summary>Segment 4, halfway to the cage — the line the foreman will answer in segment 7.</summary>
    [Export] public string DanPayLine { get; set; } = "They'll have to pay the shift for this.";

    /// <summary>Segment 4, closer to the cage.</summary>
    [Export] public string DanDaysOffLine { get; set; } = "Two days off. Minimum.";

    /// <summary>Segment 4, the last steps before the cage.</summary>
    [Export] public string DanMumLine { get; set; } = "Mum'll be at the gate. She always is.";

    /// <summary>Segment 5, the cage refuses while the floodlight runs.</summary>
    [Export] public string DanHoistRefusedLine { get; set; } = "It wants the lot. Shut that one down.";

    /// <summary>Segment 5, the cage is running.</summary>
    [Export] public string DanBoardLine { get; set; } = "Get in. Get in, Ray.";

    // ---- scene references ----------------------------------------------------------------

    /// <summary>Level loaded after the closing cutscene.</summary>
    [Export] public PackedScene NextLevel { get; set; } = null!;

    /// <summary>Room the hero starts in (the coal face).</summary>
    [Export] public RoomBounds StartRoom { get; set; } = null!;

    /// <summary>The surface room; the cage arrives there without a checkpoint of its own.</summary>
    [Export] public RoomBounds SurfaceRoom { get; set; } = null!;

    /// <summary>The single emergency bus every machine of the level draws from.</summary>
    [Export] public PowerCircuit Circuit { get; set; } = null!;

    /// <summary>Segment 2's work lights — the load the pump has to take the power from.</summary>
    [Export] public PoweredMachine Lights { get; set; } = null!;

    /// <summary>Segment 2's pump; it drains the flooded drift for good.</summary>
    [Export] public PoweredMachine Pump { get; set; } = null!;

    /// <summary>Segment 3's extractor; it blows both gas pockets out for good.</summary>
    [Export] public PoweredMachine Extractor { get; set; } = null!;

    /// <summary>Segment 5's floodlight over the cage; the last thing between the hero and the surface.</summary>
    [Export] public PoweredMachine Floodlight { get; set; } = null!;

    /// <summary>The cage. It needs the whole bus, and boarding it ends the mine.</summary>
    [Export] public Hoist Cage { get; set; } = null!;

    /// <summary>Every gas pocket in the level — the rehearsal one and the two that form the real pocket.</summary>
    [Export] public GasZone[] GasPockets { get; set; } = { };

    /// <summary>The sealing crew's field of view; optional, so a stripped-down level still runs.</summary>
    [Export] public WatchZone? Crew { get; set; }

    /// <summary>The methane blast that ends segment 0 and seals the face behind the hero.</summary>
    [Export] public CaveIn BlastCollapse { get; set; } = null!;

    /// <summary>The fall that cuts the lower horizon off and moves the power unit up to the cage.</summary>
    [Export] public CaveIn UpperCollapse { get; set; } = null!;

    /// <summary>The last fall, between the hero and his brother.</summary>
    [Export] public CaveIn FinalCollapse { get; set; } = null!;

    /// <summary>The timber pile of segment 1 — the heavy-attack lesson Dan comments on.</summary>
    [Export] public DebrisPile TimberPile { get; set; } = null!;

    /// <summary>The first outlet, the one Dan reacts to.</summary>
    [Export] public Outlet FirstOutlet { get; set; } = null!;

    /// <summary>Where the hero finds Dan after the blast.</summary>
    [Export] public Vector2 DanFallenAt { get; set; } = new(1900f, 520f);

    /// <summary>Where Dan stays when the last fall comes down — always on the far side of the rubble.</summary>
    [Export] public Vector2 DanLastStandAt { get; set; } = new(10600f, 470f);

    /// <summary>Where the cage puts the hero down on the surface.</summary>
    [Export] public Vector2 SurfaceArrival { get; set; } = new(11640f, 480f);

    /// <summary>Station lighting of segment 0; it dies with the blast and never comes back.</summary>
    [Export] public Node2D? WorkLamps { get; set; }

    /// <summary>Sparks raining from the torn cable at the blast; they never stop (§3).</summary>
    [Export] public GpuParticles2D? BlastSparks { get; set; }

    /// <summary>Light of those sparks, switched on with them so the discharge reads in the dark.</summary>
    [Export] public PointLight2D? BlastSparkLight { get; set; }

    /// <summary>The one guard of the surface fight; started after the foreman's cutscene.</summary>
    [Export] public WaveSpawner GuardSpawner { get; set; } = null!;

    /// <summary>
    /// Respawn point armed by the level itself when the last fall comes down, so a death in
    /// segment 6 can never put the hero back on the wrong side of the rubble. Never crossed by
    /// the player — its trigger is off in the scene.
    /// </summary>
    [Export] public Checkpoint FarewellCheckpoint { get; set; } = null!;

    /// <summary>
    /// Respawn point armed by the level the moment the cage arrives up top. The hero is put down a
    /// few px short of this checkpoint's own trigger, so without arming it by hand a knock-out in
    /// the first seconds of the surface fight would send him back to
    /// <see cref="FarewellCheckpoint"/> — inside the sealed mine, below a cage that has gone.
    /// </summary>
    [Export] public Checkpoint SurfaceCheckpoint { get; set; } = null!;

    /// <summary>Text overlay used for every cutscene.</summary>
    [Export] public Cutscene Cutscene { get; set; } = null!;

    /// <summary>Ambient light of the whole level: station lighting, mine dark, overcast morning.</summary>
    [Export] public CanvasModulate Darkness { get; set; } = null!;

    /// <summary>Parent of the tutorial prompts; frozen with the hero during cutscenes.</summary>
    [Export] public Node2D Tutorial { get; set; } = null!;

    /// <summary>The move hint of segment 0.</summary>
    [Export] public TutorialPrompt MovePrompt { get; set; } = null!;

    /// <summary>The jump hint of segment 0.</summary>
    [Export] public TutorialPrompt JumpPrompt { get; set; } = null!;

    /// <summary>The head-lamp hint of segment 1.</summary>
    [Export] public TutorialPrompt FlashlightPrompt { get; set; } = null!;

    /// <summary>On-screen label showing the stage, the hero's state, his jump height and the bus load.</summary>
    [Export] public Label DebugLabel { get; set; } = null!;

    private readonly Queue<string> _pendingLines = new();
    private readonly Queue<float> _pendingDelays = new();
    private Stage _stage = Stage.Intro;
    private Beat _playing = Beat.None;
    private Companion? _dan;
    private SceneTreeTimer? _lineTimer;
    private Tween? _darknessTween;
    private TutorialPrompt? _activeHint;
    private string _playerState = string.Empty;
    private int _height = -1;
    private bool _danSilent;
    private bool _danFound;
    private bool _ruleSaid;
    private bool _gasClearedSaid;
    private bool _diedInGas;

    /// <summary>The current beat of the prologue.</summary>
    public Stage CurrentStage => _stage;

    /// <inheritdoc/>
    public override void _Ready()
    {
        base._Ready();
        _dan = Companion;
        ApplyRoomBounds(StartRoom);
        Darkness.Color = DarknessLit;
        Cutscene.Skippable = CutsceneSkippable;

        Player.StateChanged += OnPlayerStateChanged;
        Cutscene.Finished += OnCutsceneFinished;
        CheckpointArmed += OnCheckpointArmed;
        Respawned += OnRespawned;

        Circuit.RequestRefused += OnRequestRefused;
        Circuit.MachinePowered += OnMachinePowered;
        Circuit.MachineReleased += OnMachineReleased;
        Circuit.LoadChanged += OnLoadChanged;

        BlastCollapse.Triggered += OnBlastTriggered;
        BlastCollapse.Collapsed += OnBlastCollapsed;
        UpperCollapse.Collapsed += OnUpperCollapsed;
        FinalCollapse.Collapsed += OnFinalCollapsed;
        Floodlight.PowerChanged += OnFloodlightPowerChanged;
        Cage.Departed += OnCageDeparted;
        TimberPile.Resisted += OnTimberResisted;
        TimberPile.Cleared += OnTimberCleared;
        FirstOutlet.Charged += OnOutletCharged;
        GuardSpawner.WaveCleared += OnWaveCleared;

        foreach (GasZone pocket in GasPockets)
        {
            pocket.WarningStarted += OnGasWarningStarted;
            pocket.Ignited += OnGasIgnited;
            pocket.Cleared += OnGasCleared;
        }

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
        PlayCutscene(Beat.Intro, IntroLines);
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        base._ExitTree();
        Player.StateChanged -= OnPlayerStateChanged;
        Cutscene.Finished -= OnCutsceneFinished;
        CheckpointArmed -= OnCheckpointArmed;
        Respawned -= OnRespawned;

        Circuit.RequestRefused -= OnRequestRefused;
        Circuit.MachinePowered -= OnMachinePowered;
        Circuit.MachineReleased -= OnMachineReleased;
        Circuit.LoadChanged -= OnLoadChanged;

        BlastCollapse.Triggered -= OnBlastTriggered;
        BlastCollapse.Collapsed -= OnBlastCollapsed;
        UpperCollapse.Collapsed -= OnUpperCollapsed;
        FinalCollapse.Collapsed -= OnFinalCollapsed;
        Floodlight.PowerChanged -= OnFloodlightPowerChanged;
        Cage.Departed -= OnCageDeparted;
        TimberPile.Resisted -= OnTimberResisted;
        TimberPile.Cleared -= OnTimberCleared;
        FirstOutlet.Charged -= OnOutletCharged;
        GuardSpawner.WaveCleared -= OnWaveCleared;

        foreach (GasZone pocket in GasPockets)
        {
            pocket.WarningStarted -= OnGasWarningStarted;
            pocket.Ignited -= OnGasIgnited;
            pocket.Cleared -= OnGasCleared;
        }

        ClearPendingLines();
        if (_darknessTween is not null && _darknessTween.IsValid())
        {
            _darknessTween.Kill();
        }

        _darknessTween = null;
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

    // ---- stages -------------------------------------------------------------------------

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

    /// <summary>
    /// Room bounds, respawn point and story beat in one place: the checkpoint's
    /// <see cref="Checkpoint.Label"/> is this level's event key.
    /// </summary>
    private void OnCheckpointArmed(Checkpoint checkpoint)
    {
        if (checkpoint.Room is not null)
        {
            ApplyRoomBounds(checkpoint.Room);
        }

        switch (checkpoint.Label)
        {
            case "face":
                SetStage(Stage.Face);
                break;
            case "dan":
                _danFound = true;
                _dan?.Resume();
                SayLine(DanFoundLine);
                SayAfter(FoundFollowUpSeconds, DanUnhurtLine);
                break;
            case "flood":
                SetStage(Stage.Flood);
                SayLine(DanFloodLine);
                break;
            case "gas_rehearsal":
                SetStage(Stage.Gas);
                SayLine(DanGasNearLine);
                break;
            case "past_pocket":
                if (!_gasClearedSaid)
                {
                    SayLine(DanDarkCrossingLine);   // he went through in the dark; the extractor never ran
                }

                break;
            case "crew":
                SetStage(Stage.Crew);
                SayLine(DanCrewLine);
                ClearPendingLines();
                _danSilent = true;   // §3: he ducks and goes quiet by himself, and stays quiet
                break;
            case "upper":
                SetStage(Stage.Upper);
                break;
            // Segment 4's five lines are placed, not timed: the road from the first sight of the
            // cage to the cage itself is 3.4 s of walking, so a cumulative timer chain let the
            // hero outrun it and hear the last line («Mum'll be at the gate») second, overwritten
            // 0.6 s later. script-en.md rows 28–30 ask for positions anyway, and the order is the
            // point of the scene: fact → future → mother, immediately before the fall.
            case "sight":
                SayLine(DanCageSeenLine);
                break;
            case "road_power":
                SayLine(DanCagePowerLine);
                break;
            case "road_pay":
                SayLine(DanPayLine);
                break;
            case "road_days":
                SayLine(DanDaysOffLine);
                break;
            case "cage":
                SetStage(Stage.Cage);
                ClearPendingLines();   // nothing queued may land on top of the last line before the fall
                SayLine(DanMumLine);
                break;
        }
    }

    private void OnRespawned()
    {
        if (_dan is null || !IsInstanceValid(_dan))
        {
            return;
        }

        if (_stage >= Stage.Farewell)
        {
            HoldDan(DanLastStandAt);   // the follower's failsafes must never pull him through the rubble
            return;
        }

        if (_danFound)
        {
            _dan.Resume();
            return;
        }

        HoldDan(DanFallenAt);
    }

    // ---- the blast ----------------------------------------------------------------------

    private void OnBlastTriggered()
    {
        SetStage(Stage.Blast);
        HoldDan(DanFallenAt);
        if (WorkLamps is not null)
        {
            WorkLamps.Visible = false;   // the lamp string is gone for the rest of the mine
        }

        if (BlastSparks is not null)
        {
            BlastSparks.Emitting = true;
        }

        if (BlastSparkLight is not null)
        {
            BlastSparkLight.Enabled = true;
        }

        TweenDarkness(DarknessMine);
        PlayCutscene(Beat.Blast, BlastLines);
    }

    private void OnBlastCollapsed() => SayLine(DanWayBackLine);

    // ---- the circuit --------------------------------------------------------------------

    private void OnRequestRefused(PoweredMachine machine, PoweredMachine blocking)
    {
        if (ReferenceEquals(machine, Cage) && ReferenceEquals(blocking, Floodlight))
        {
            SayLine(DanHoistRefusedLine);
            return;
        }

        if (!_ruleSaid)
        {
            _ruleSaid = true;
            SayLine(DanRuleLine);
            return;
        }

        SayLine(DanRefusedLine);
    }

    private void OnMachinePowered(PoweredMachine machine)
    {
        if (ReferenceEquals(machine, Pump))
        {
            SayLine(DanPumpLine);
        }
        else if (ReferenceEquals(machine, Cage))
        {
            SayLine(DanBoardLine);
        }
    }

    private void OnMachineReleased(PoweredMachine machine)
    {
        if (ReferenceEquals(machine, Lights))
        {
            SayLine(DanDarkLine);
        }
    }

    /// <summary>The only place the bus load reaches the debug label; it fires after every grant and release.</summary>
    private void OnLoadChanged(int used, int capacity) => RefreshLabel();

    /// <summary>
    /// The hand-over that keeps the run solvable: everything the fresh rubble just sealed away is
    /// switched off, and the freed unit goes to the floodlight over the cage — the only machine the
    /// hero can still reach. Release before power, or the bus is momentarily full and refuses.
    /// </summary>
    private void OnUpperCollapsed()
    {
        Lights.PowerDown();
        Pump.PowerDown();
        Extractor.PowerDown();
        Floodlight.ForcePower();
        if (Crew is not null)
        {
            Crew.Disabled = true;   // the crew is behind the seal; they can never reach him again
        }

        _danSilent = false;
        SayLine(DanSealingLine);
    }

    private void OnFloodlightPowerChanged(bool powered)
    {
        if (powered || FinalCollapse.HasCollapsed)
        {
            return;   // the fall itself cuts the floodlight; re-arming a spent trigger is noise
        }

        // The way to the cage is dark now, and the roof over it is ready to go.
        FinalCollapse.SetDeferred(Area2D.PropertyName.Monitoring, true);
    }

    private void OnFinalCollapsed()
    {
        SetStage(Stage.Farewell);
        // The last seal takes the floodlight's cable with it. Without this a player who switched the
        // floodlight back on after arming the fall would leave the only power unit behind the rubble
        // with the cage still asking for the whole bus — the one soft-lock this level could have.
        Floodlight.PowerDown();
        HoldDan(DanLastStandAt);
        Companion = null;   // LevelBase must never warp him again: he stays behind the rubble
        SetCheckpoint(FarewellCheckpoint);
        ClearPendingLines();
        _danSilent = true;   // he never speaks again
        PlayCutscene(Beat.Farewell, FarewellLines);
    }

    // ---- hazards ------------------------------------------------------------------------

    private void OnGasWarningStarted() => SayLine(_diedInGas ? DanGasAgainLine : DanGasLine);

    private void OnGasIgnited(Player player) => _diedInGas = true;

    private void OnGasCleared()
    {
        if (_gasClearedSaid)
        {
            return;   // the extractor clears both halves of the pocket; one line is enough
        }

        _gasClearedSaid = true;
        SayLine(DanGasClearedLine);
    }

    // ---- the surface --------------------------------------------------------------------

    private void OnCageDeparted(Player player)
    {
        SetStage(Stage.Surface);
        Player.GlobalPosition = SurfaceArrival;
        ApplyRoomBounds(SurfaceRoom);
        SetCheckpoint(SurfaceCheckpoint);   // the mine is behind him for good; a KO must never send him back down
        TweenDarkness(DarknessSurface);
        PlayCutscene(Beat.Foreman, ForemanLines);
    }

    private void OnWaveCleared()
    {
        SetStage(Stage.Ending);
        PlayCutscene(Beat.Ending, EndLines);
    }

    // ---- props --------------------------------------------------------------------------

    private void OnTimberResisted() => SayLine(DanTimberLine);

    private void OnTimberCleared() => SayLine(DanClearedLine);

    private void OnOutletCharged(float amount) => SayLine(DanOutletLine);

    // ---- cutscenes and pausing ----------------------------------------------------------

    private void OnCutsceneFinished()
    {
        Beat beat = _playing;
        _playing = Beat.None;
        switch (beat)
        {
            case Beat.Intro:
                SetStage(Stage.Face);
                ResumeActors();
                SayAfter(AmbientLineSeconds, DanMotorLine);
                break;
            case Beat.Foreman:
                GameState.Instance.AddEnergy(-FinePenalty);
                PlayCutscene(Beat.Guard, GuardLines);
                break;
            case Beat.Guard:
                SetStage(Stage.Fight);
                GuardSpawner.StartWave();
                ResumeActors();
                break;
            case Beat.Ending:
                SetStage(Stage.Done);
                GoToLevel(NextLevel);
                break;
            default:
                ResumeActors();
                break;
        }
    }

    /// <summary>
    /// Freezes the hero and the hints (a disabled <c>CollisionObject2D</c> also leaves the physics
    /// space, so nothing triggers meanwhile), hides the prompt and plays <paramref name="lines"/>.
    /// </summary>
    private void PlayCutscene(Beat beat, string[] lines)
    {
        _playing = beat;
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

    // ---- Dan ----------------------------------------------------------------------------

    /// <summary>Puts a line in Dan's bubble, unless he is being deliberately silent (or already gone).</summary>
    private void SayLine(string text)
    {
        if (_danSilent || _dan is null || !IsInstanceValid(_dan))
        {
            return;
        }

        _dan.Say(text);
    }

    /// <summary>
    /// Queues a line <paramref name="seconds"/> after the previous queued one (or after now, when
    /// the queue is empty). One timer at a time, so a level freed mid-chain leaves nothing behind.
    /// </summary>
    private void SayAfter(float seconds, string text)
    {
        _pendingDelays.Enqueue(seconds);
        _pendingLines.Enqueue(text);
        StartNextLineTimer();
    }

    private void StartNextLineTimer()
    {
        if (_lineTimer is not null || _pendingLines.Count == 0)
        {
            return;
        }

        // processAlways: false so nothing is said behind an open pause menu; ignoreTimeScale so a
        // hit-stop does not stretch the beat.
        _lineTimer = GetTree().CreateTimer(_pendingDelays.Peek(), processAlways: false, processInPhysics: false, ignoreTimeScale: true);
        _lineTimer.Timeout += OnLineTimerTimeout;
    }

    private void OnLineTimerTimeout()
    {
        if (_lineTimer is not null)
        {
            _lineTimer.Timeout -= OnLineTimerTimeout;
            _lineTimer = null;
        }

        if (!IsInstanceValid(this) || !IsInsideTree())
        {
            return;   // the level was freed before the delay ran out (test teardown, scene change)
        }

        if (_pendingLines.Count > 0)
        {
            _pendingDelays.Dequeue();
            SayLine(_pendingLines.Dequeue());
        }

        StartNextLineTimer();
    }

    private void ClearPendingLines()
    {
        _pendingLines.Clear();
        _pendingDelays.Clear();
        if (_lineTimer is not null)
        {
            _lineTimer.Timeout -= OnLineTimerTimeout;
            _lineTimer = null;
        }
    }

    /// <summary>Puts Dan on a scripted spot at once and keeps him there; nothing ever waits for him to walk.</summary>
    private void HoldDan(Vector2 position)
    {
        if (_dan is null || !IsInstanceValid(_dan))
        {
            return;
        }

        _dan.WarpTo(position);
        _dan.HoldAt(position);
    }

    // ---- darkness -----------------------------------------------------------------------

    private void TweenDarkness(Color target)
    {
        if (_darknessTween is not null && _darknessTween.IsValid())
        {
            _darknessTween.Kill();
        }

        _darknessTween = CreateTween();
        _darknessTween.TweenProperty(Darkness, "color", target, DarknessFadeSeconds);
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

        if (ReferenceEquals(hint, MovePrompt))
        {
            SayLine(DanMoveLine);
        }
        else if (ReferenceEquals(hint, JumpPrompt))
        {
            SayLine(DanJumpLine);
        }
        else if (ReferenceEquals(hint, FlashlightPrompt))
        {
            SayLine(DanLampLine);
        }
    }

    private void OnHintCompleted(TutorialPrompt hint)
    {
        if (ReferenceEquals(_activeHint, hint))
        {
            _activeHint = null;
            RefreshPrompt();
        }
    }

    /// <summary>
    /// The prologue's prompt priority, replacing the base rule: a usable interactable in reach,
    /// then the active tutorial hint, then the text of an unusable prop in reach; nothing at all
    /// while a cutscene plays.
    /// </summary>
    protected override void RefreshPrompt()
    {
        if (Cutscene.IsPlaying)
        {
            ShowPrompt(null);
            return;
        }

        string? hint = _activeHint is not null && _activeHint.IsShowing ? _activeHint.Text : null;
        ShowPrompt(IsInteractableUsable() ? InteractablePrompt : hint ?? InteractablePrompt);
    }

    private void OnPlayerStateChanged(string from, string to)
    {
        _playerState = to;
        RefreshLabel();
    }

    private void RefreshLabel() =>
        DebugLabel.Text = $"Stage: {_stage}  State: {_playerState}  z: {_height}  Circuit {Circuit.Used}/{Circuit.Capacity}";
}
