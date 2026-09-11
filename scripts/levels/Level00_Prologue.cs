using System.Collections.Generic;
using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Core;
using BlackoutLastGrid.Enemies;
using BlackoutLastGrid.Props;
using BlackoutLastGrid.Ui;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Level 0 — «Shift», third revision (GAME_DESIGN §3): the escape from the mine, six segments
/// from the coal face to the surface. Ray sets the charge on the belt motor; their own blast
/// seals the way back and kills the lamps; two guards come into the dark and leave their
/// powerbanks; Dan runs ahead and shows the way down the drift (the timber, one gas pocket);
/// a lit drift with a patrol to sneak past or fight; a dead cage that needs the drift's work
/// lights switched off; and at the cage the guards catch up from behind and take Dan, who holds
/// them on himself so the cage can lift. Ray comes out on the surface with his brother's bank.
/// Nothing here is a new mechanic: the level is placement, story flow and text over the props of
/// T-07s-a and the guide of T-07s-e (<see cref="PowerCircuit"/>, <see cref="PoweredMachine"/>,
/// <see cref="Hoist"/>, <see cref="GasZone"/>, <see cref="DebrisPile"/>, <see cref="CaveIn"/>,
/// <see cref="Checkpoint"/>, <see cref="WaveSpawner"/>, <see cref="Guard"/>,
/// <see cref="EnergyPickup"/>, <see cref="Companion"/>).
/// </summary>
/// <remarks>
/// <para>
/// The flow is driven by signals only — there is no per-frame logic beyond the debug label. Room
/// boundaries and story beats hang off <see cref="Checkpoint.Label"/>: crossing a checkpoint
/// applies its room's bounds, arms the respawn, leads Dan at least to that segment's route point
/// and fires the beat. Dan is driven by a <b>route table</b>: one <c>Marker2D</c> per stop under
/// <see cref="DanRoute"/> (<c>WP_&lt;key&gt;</c>, in route order), each stop gated on his own
/// <c>Arrived</c>, on the hero reaching him, or on a named level event. No route point sits past
/// a closed gate, so his forward failsafes can never put him on the wrong side of one.
/// </para>
/// <para>
/// The blast is scripted, never a walk trigger with a delay: the roof comes down only after the
/// hero has been frozen for the cutscene, on the open side of the seal by construction
/// (<see cref="TriggerBlast"/>). The capture at the cage is a cutscene with a fixed placement of
/// the hero, Dan and the guards (<see cref="OnCageDeparted"/>) — it plays the same way whatever
/// the player did, and Dan can neither be hurt nor lost before it.
/// </para>
/// </remarks>
public partial class Level00_Prologue : LevelBase
{
    /// <summary>Beats of the prologue, in order.</summary>
    public enum Stage
    {
        /// <summary>The coalface cutscene.</summary>
        Intro,
        /// <summary>Segment 0: the shift is still working, the lights are on.</summary>
        Face,
        /// <summary>Segment 0: the charge is set and counting; the brothers go behind the props.</summary>
        Charge,
        /// <summary>Segment 1: the blast cutscene.</summary>
        Blast,
        /// <summary>Segment 1: the dark, the head lamp.</summary>
        Dark,
        /// <summary>Segment 1: the two guards.</summary>
        Fight,
        /// <summary>Segment 2: down the drift, the timber.</summary>
        Drift,
        /// <summary>Segment 2: the gas pocket.</summary>
        Gas,
        /// <summary>Segment 3: the lit drift and the patrol.</summary>
        Patrol,
        /// <summary>Segment 4: the cage and the one refusal.</summary>
        Cage,
        /// <summary>Segment 5: the capture at the cage.</summary>
        Held,
        /// <summary>Segment 5: the surface.</summary>
        Surface,
        /// <summary>Hand-over to Level 1 requested.</summary>
        Done,
    }

    /// <summary>Which cutscene is on screen, so <see cref="OnCutsceneFinished"/> knows what follows.</summary>
    private enum Beat
    {
        None,
        Intro,
        Charge,
        Blast,
        Guards,
        Held,
        Surface,
    }

    /// <summary>What advances Dan from a route point to the next one.</summary>
    private enum Gate
    {
        /// <summary>His own <c>Arrived</c>: he walks straight on (a corner of the stealth route).</summary>
        Auto,
        /// <summary>The hero coming to him (<c>HeroReached</c>).</summary>
        HeroReached,
        /// <summary>A named level event handled elsewhere in this class.</summary>
        Event,
    }

    // ---- route keys (the WP_<key> markers under DanRoute) ----------------------------------

    private const string KeyCharge = "charge";
    private const string KeyProps = "props";
    private const string KeyDark = "dark";
    private const string KeyFaceExit = "face_exit";
    private const string KeyTimber = "timber";
    private const string KeyGasEdge = "gas_edge";
    private const string KeyPastGas = "past_gas";
    private const string KeyDriftExit = "drift_exit";
    private const string KeyPatrolIn = "patrol_in";
    private const string KeyP1 = "p1";
    private const string KeyC1 = "c1";
    private const string KeyC1b = "c1b";
    private const string KeyP2 = "p2";
    private const string KeyC2 = "c2";
    private const string KeyC2b = "c2b";
    private const string KeyP3 = "p3";
    private const string KeyP3Out = "p3_out";
    private const string KeyCage = "cage";
    private const string KeyBoard = "board";

    /// <summary>The gate of every stop; a key missing here is an <see cref="Gate.Auto"/> corner.</summary>
    private static readonly Dictionary<string, Gate> Gates = new()
    {
        [KeyCharge] = Gate.Event,
        [KeyProps] = Gate.Event,
        [KeyDark] = Gate.Event,
        [KeyFaceExit] = Gate.HeroReached,
        [KeyTimber] = Gate.Event,
        [KeyGasEdge] = Gate.Event,
        [KeyPastGas] = Gate.HeroReached,
        [KeyDriftExit] = Gate.HeroReached,
        [KeyPatrolIn] = Gate.HeroReached,
        [KeyP1] = Gate.HeroReached,
        [KeyP2] = Gate.HeroReached,
        [KeyP3] = Gate.HeroReached,
        [KeyP3Out] = Gate.HeroReached,
        [KeyCage] = Gate.Event,
        [KeyBoard] = Gate.Event,
    };

    /// <summary>The stops of the lit drift where his lamp stays off (the entrance, the stripes and the columns).</summary>
    private static readonly HashSet<string> DarkPatrolKeys = new()
    {
        KeyPatrolIn, KeyP1, KeyC1, KeyC1b, KeyP2, KeyC2, KeyC2b, KeyP3,
    };

    /// <summary>Route key Dan is led to (at least) when the checkpoint with that label is armed.</summary>
    private static readonly Dictionary<string, string> CheckpointRoute = new()
    {
        ["dark"] = KeyDark,
        ["drift"] = KeyTimber,
        ["gas_near"] = KeyGasEdge,
        ["past_gas"] = KeyPastGas,
        ["patrol"] = KeyPatrolIn,
        ["cage"] = KeyCage,
    };

    /// <summary>Emitted on every stage change with the new stage's name (for tests and the debug label).</summary>
    [Signal]
    public delegate void StageChangedEventHandler(string stage);

    // ---- tunables -------------------------------------------------------------------------

    /// <summary>Ambient light while the station lighting still burns (segment 0).</summary>
    [Export] public Color DarknessLit { get; set; } = Color.FromHtml("#8f97a3");

    /// <summary>Ambient light of the mine once the lamp string is gone (segments 1–2, and the drift once its lights are off).</summary>
    [Export] public Color DarknessMine { get; set; } = Color.FromHtml("#0a0d14");

    /// <summary>Ambient light of the lit drift while the work lights run (segments 3–4): dim, not black.</summary>
    [Export] public Color DarknessDrift { get; set; } = Color.FromHtml("#2b3040");

    /// <summary>Ambient light of the morning on the surface (segment 5).</summary>
    [Export] public Color DarknessSurface { get; set; } = Color.FromHtml("#6b7280");

    /// <summary>The black beat between the capture and the surface — nothing is shown of the ride up.</summary>
    [Export] public Color DarknessBlack { get; set; } = Color.FromHtml("#000000");

    /// <summary>Seconds the ambient light takes to move between those values.</summary>
    [Export] public float DarknessFadeSeconds { get; set; } = 1.2f;

    /// <summary>Whether the player may advance cutscene lines by hand.</summary>
    [Export] public bool CutsceneSkippable { get; set; } = true;

    /// <summary>Seconds between Dan's lamp going out at the gas pocket and his warning line — the rule is shown before it is said.</summary>
    [Export] public float GasWarnDelaySeconds { get; set; } = 0.5f;

    /// <summary>Seconds of black between the capture cutscene and the surface.</summary>
    [Export] public float BlackBeatSeconds { get; set; } = 2f;

    // ---- cutscenes (docs/plans/t07s-e-dan-leads/script-en.md) -----------------------------

    /// <summary>«Coalface»: the last hour of the shift and what Dan saw behind the bars.</summary>
    [Export] public string[] IntroLines { get; set; } = System.Array.Empty<string>();

    /// <summary>«Charge»: two minutes with the motor open.</summary>
    [Export] public string[] ChargeLines { get; set; } = System.Array.Empty<string>();

    /// <summary>«Blast»: the roof comes down behind them, the lamp string dies.</summary>
    [Export] public string[] BlastLines { get; set; } = System.Array.Empty<string>();

    /// <summary>«Guards»: two lamps coming down the drift at a run.</summary>
    [Export] public string[] GuardsLines { get; set; } = System.Array.Empty<string>();

    /// <summary>«Held»: the cage lifts, the lamps behind, Dan walks back to them and is taken.</summary>
    [Export] public string[] HeldLines { get; set; } = System.Array.Empty<string>();

    /// <summary>«Surface»: the pit head behind, the lit centre ahead, the bank that is not his.</summary>
    [Export] public string[] EndLines { get; set; } = System.Array.Empty<string>();

    // ---- Dan's lines (script-en.md, «Зведена таблиця подія → репліка») ----------------------

    /// <summary>Segment 0, the move hint.</summary>
    [Export] public string DanMoveLine { get; set; } = "Come on. Belt end. This way.";

    /// <summary>Segment 0, the jump hint.</summary>
    [Export] public string DanJumpLine { get; set; } = "Over the sleepers.";

    /// <summary>Segment 0, the hero reaches him by the motor — where, not how.</summary>
    [Export] public string DanChargeLine { get; set; } = "Motor's there. Do your thing.";

    /// <summary>Segment 0, he is behind the props with the charge counting.</summary>
    [Export] public string DanPropsLine { get; set; } = "Here. Behind the props.";

    /// <summary>Segment 0, the hero lags behind the props — the one call with a story reason to hurry.</summary>
    [Export] public string DanCountingLine { get; set; } = "Ray. It's counting.";

    /// <summary>Segment 1, the head-lamp hint.</summary>
    [Export] public string DanLampLine { get; set; } = "Lamp on. I can't see you.";

    /// <summary>Segment 1, the light-attack hint.</summary>
    [Export] public string DanAttackLine { get; set; } = "Hit him. Ray. Hit him.";

    /// <summary>Segment 1, the heavy-attack hint.</summary>
    [Export] public string DanHeavyLine { get; set; } = "Harder than that.";

    /// <summary>Segment 1, the wave is down — where the banks are.</summary>
    [Export] public string DanBanksLine { get; set; } = "Banks. Off their belts.";

    /// <summary>Segment 1, the first bank taken (§3 «that's ours now»).</summary>
    [Export] public string DanOursLine { get; set; } = "That's ours now.";

    /// <summary>The first outlet, wherever it is.</summary>
    [Export] public string DanOutletLine { get; set; } = "Socket's live. Take it.";

    /// <summary>Direction line at the face exit, before the descent.</summary>
    [Export] public string DanDownHereLine { get; set; } = "Down here.";

    /// <summary>Direction line on the long straight before the lit drift.</summary>
    [Export] public string DanKeepComingLine { get; set; } = "Keep coming.";

    /// <summary>The lagging call, first variant.</summary>
    [Export] public string DanCallLine { get; set; } = "Ray. Here.";

    /// <summary>The lagging call, second variant.</summary>
    [Export] public string DanCallAgainLine { get; set; } = "Come on. It's this way.";

    /// <summary>Segment 2, the hero reaches him at the timber pile.</summary>
    [Export] public string DanTimberLine { get; set; } = "Timber's down. Through it, not over.";

    /// <summary>Segment 2, a light attack bounced off the timber.</summary>
    [Export] public string DanResistedLine { get; set; } = "Not a punch. Shoulder in.";

    /// <summary>Segment 2, the timber pile is down.</summary>
    [Export] public string DanClearedLine { get; set; } = "Go.";

    /// <summary>Segment 2, at the edge of the gas, after his lamp went out.</summary>
    [Export] public string DanGasWarnLine { get; set; } = "Air's yellow past here. No lamps.";

    /// <summary>Segment 2, the warning window — recognised by its shape, not read.</summary>
    [Export] public string DanGasLine { get; set; } = "LAMP OFF!";

    /// <summary>Segment 2, back at the edge after a death in the gas.</summary>
    [Export] public string DanGasAgainLine { get; set; } = "Black all the way. Told you.";

    /// <summary>Segment 2, the far side of the pocket, his lamp back on.</summary>
    [Export] public string DanGasPastLine { get; set; } = "Clear. Light it.";

    /// <summary>Segment 3, at the entrance of the lit drift — then silence.</summary>
    [Export] public string DanDuckLine { get; set; } = "Lamps on them. Keep to the black.";

    /// <summary>Segment 3, the patrol is down instead of passed.</summary>
    [Export] public string DanFoughtLine { get; set; } = "Or that. Come on.";

    /// <summary>Segment 3, past the patrol without being seen.</summary>
    [Export] public string DanNeverLookedLine { get; set; } = "Never looked. Go.";

    /// <summary>Segment 4, the cage in sight — the only time he repeats himself.</summary>
    [Export] public string DanCageLine { get; set; } = "That's the cage. Ray, that's the cage.";

    /// <summary>Segment 4, the first refusal — the rule of the bus, said by a person.</summary>
    [Export] public string DanRuleLine { get; set; } = "Won't take both.";

    /// <summary>Segment 4, every later refusal.</summary>
    [Export] public string DanRefusedLine { get; set; } = "Both. Something's still on it.";

    /// <summary>Segment 4, the work lights go out.</summary>
    [Export] public string DanDarkLine { get; set; } = "Fine. We've had darker.";

    /// <summary>Segment 4, the cage is running.</summary>
    [Export] public string DanBoardLine { get; set; } = "It's live. Get in.";

    // ---- scene references ----------------------------------------------------------------

    /// <summary>Level loaded when the hero walks off the surface.</summary>
    [Export] public PackedScene NextLevel { get; set; } = null!;

    /// <summary>Room the hero starts in (the coal face).</summary>
    [Export] public RoomBounds StartRoom { get; set; } = null!;

    /// <summary>The surface room; the black beat puts the hero there without a checkpoint of his own.</summary>
    [Export] public RoomBounds SurfaceRoom { get; set; } = null!;

    /// <summary>The single emergency bus of the level (<c>Capacity = 1</c>).</summary>
    [Export] public PowerCircuit Circuit { get; set; } = null!;

    /// <summary>The level's attack-slot director handed to every guard.</summary>
    [Export] public EnemyDirector Director { get; set; } = null!;

    /// <summary>The drift's work lights — the one machine the cage has to take the power from.</summary>
    [Export] public PoweredMachine Lights { get; set; } = null!;

    /// <summary>The cage. It needs the whole bus, and boarding it ends the mine.</summary>
    [Export] public Hoist Cage { get; set; } = null!;

    /// <summary>The charge on the belt motor — the one repair sequence of the level.</summary>
    [Export] public PowerPanel Charge { get; set; } = null!;

    /// <summary>The loaded cart train wedged across the drift past the motor; the blast throws it clear.</summary>
    [Export] public DebrisPile Jam { get; set; } = null!;

    /// <summary>Placeholder carts drawn over the jam; hidden with it.</summary>
    [Export] public Node2D? JamDecal { get; set; }

    /// <summary>The scripted fall that seals the face behind the brothers; its trigger is off for good.</summary>
    [Export] public CaveIn BlastCollapse { get; set; } = null!;

    /// <summary>
    /// Trigger past the props: the hero walking into it sets the blast off, in case he reaches the
    /// props before Dan does (the level never waits for Dan). Sits far enough past the seal that
    /// the hero is on the open side whenever it fires.
    /// </summary>
    [Export] public Area2D BlastTrigger { get; set; } = null!;

    /// <summary>The timber pile of segment 2 — the heavy-attack lesson on rubble instead of on a person.</summary>
    [Export] public DebrisPile TimberPile { get; set; } = null!;

    /// <summary>Both halves of the one gas pocket.</summary>
    [Export] public GasZone[] GasPockets { get; set; } = { };

    /// <summary>The two guards who come into the dark.</summary>
    [Export] public WaveSpawner GuardWave { get; set; } = null!;

    /// <summary>The lit stretch the guards' hand lamp makes; its shape is off until the wave starts.</summary>
    [Export] public LitZone ArenaZone { get; set; } = null!;

    /// <summary>The hand lamp set down on the floor (light, body and pool decal); shown from the wave on.</summary>
    [Export] public Node2D ArenaLamp { get; set; } = null!;

    /// <summary>Container of the placed patrol guards (y-sorted; their drops land in it too).</summary>
    [Export] public Node2D Patrol { get; set; } = null!;

    /// <summary>The lamp pools of the lit drift; their shapes go with the work lights.</summary>
    [Export] public LitZone[] PatrolPools { get; set; } = { };

    /// <summary>What a knocked-out guard leaves on the floor.</summary>
    [Export] public PackedScene PickupScene { get; set; } = null!;

    /// <summary>Every outlet of the level — the first charge gets Dan's line, wherever it happens.</summary>
    [Export] public Outlet[] Outlets { get; set; } = { };

    /// <summary>Container of <c>Marker2D</c> children named <c>WP_&lt;key&gt;</c>, in route order.</summary>
    [Export] public Node2D DanRoute { get; set; } = null!;

    /// <summary>Where Dan holds during the intro — past the crate, up the drift.</summary>
    [Export] public Vector2 DanStart { get; set; } = new(960f, 470f);

    /// <summary>Where the hero stands in the cage for the capture scene.</summary>
    [Export] public Vector2 HeroHeldAt { get; set; } = new(8500f, 476f);

    /// <summary>Where Dan stands at the gate for the capture scene.</summary>
    [Export] public Vector2 DanHeldAt { get; set; } = new(8410f, 470f);

    /// <summary>The guards who catch up from behind — rigs only, shown for the capture scene.</summary>
    [Export] public Node2D? HeldGuards { get; set; }

    /// <summary>Where the black beat puts the hero down on the surface.</summary>
    [Export] public Vector2 SurfaceArrival { get; set; } = new(8760f, 480f);

    /// <summary>Respawn point armed by the level on the surface; never crossed (its trigger is off).</summary>
    [Export] public Checkpoint SurfaceCheckpoint { get; set; } = null!;

    /// <summary>The edge of the surface; walking into it hands the run to <see cref="NextLevel"/>.</summary>
    [Export] public Area2D LevelExit { get; set; } = null!;

    /// <summary>Station lighting of segment 0; it dies with the blast and never comes back.</summary>
    [Export] public Node2D? WorkLamps { get; set; }

    /// <summary>Sparks raining from the torn cable at the blast; they never stop (§3).</summary>
    [Export] public GpuParticles2D? BlastSparks { get; set; }

    /// <summary>Light of those sparks, switched on with them so the discharge reads in the dark.</summary>
    [Export] public PointLight2D? BlastSparkLight { get; set; }

    /// <summary>The belt animation; it stops with the motor.</summary>
    [Export] public AnimationPlayer? ConveyorAnimation { get; set; }

    /// <summary>Text overlay used for every cutscene.</summary>
    [Export] public Cutscene Cutscene { get; set; } = null!;

    /// <summary>Ambient light of the whole level.</summary>
    [Export] public CanvasModulate Darkness { get; set; } = null!;

    /// <summary>Parent of the tutorial prompts; frozen with the hero during cutscenes.</summary>
    [Export] public Node2D Tutorial { get; set; } = null!;

    /// <summary>The move hint of segment 0.</summary>
    [Export] public TutorialPrompt MovePrompt { get; set; } = null!;

    /// <summary>The jump hint of segment 0.</summary>
    [Export] public TutorialPrompt JumpPrompt { get; set; } = null!;

    /// <summary>The head-lamp hint of segment 1.</summary>
    [Export] public TutorialPrompt FlashlightPrompt { get; set; } = null!;

    /// <summary>The light-attack hint, triggered by the level when the guards are in.</summary>
    [Export] public TutorialPrompt AttackPrompt { get; set; } = null!;

    /// <summary>The heavy-attack hint, triggered by the level after the first hit lands.</summary>
    [Export] public TutorialPrompt HeavyPrompt { get; set; } = null!;

    /// <summary>On-screen label showing the stage, the hero's state, his jump height, the bus load and Dan's route key.</summary>
    [Export] public Label DebugLabel { get; set; } = null!;

    private readonly List<string> _routeKeys = new();
    private readonly List<Vector2> _routePoints = new();
    private readonly List<CollisionShape2D> _poolShapes = new();
    private readonly List<Guard> _patrolGuards = new();
    private readonly List<Guard> _waveGuards = new();
    private readonly List<EnergyPickup> _pickups = new();
    private readonly List<(TutorialPrompt Hint, TutorialPrompt.ShownEventHandler Shown, TutorialPrompt.CompletedEventHandler Completed)> _hintHandlers = new();
    private readonly Queue<string> _pendingLines = new();
    private readonly Queue<float> _pendingDelays = new();
    private Stage _stage = Stage.Intro;
    private Beat _playing = Beat.None;
    private Companion? _dan;
    private CollisionShape2D? _arenaShape;
    private SceneTreeTimer? _lineTimer;
    private SceneTreeTimer? _beatTimer;
    private Tween? _darknessTween;
    private TutorialPrompt? _activeHint;
    private string _playerState = string.Empty;
    private int _height = -1;
    private int _routeIndex = -1;
    private int _patrolDown;
    private bool _danSilent;
    private bool _waitingForLampOff;
    private bool _heavyHinted;
    private bool _oursSaid;
    private bool _outletSaid;
    private bool _ruleSaid;
    private bool _diedInGas;
    private bool _patrolNoticed;
    private bool _enemiesRetired;
    private bool _callAgain;

    /// <summary>The current beat of the prologue.</summary>
    public Stage CurrentStage => _stage;

    /// <summary>Key of the route point Dan was last led to, or an empty string.</summary>
    public string CurrentRouteKey => _routeIndex < 0 ? string.Empty : _routeKeys[_routeIndex];

    /// <summary>World position of the route point <paramref name="key"/>, for tests and the label; zero for an unknown key.</summary>
    /// <param name="key">Route key, the marker's name without the <c>WP_</c> prefix.</param>
    public Vector2 RoutePoint(string key)
    {
        int index = _routeKeys.IndexOf(key);
        return index < 0 ? Vector2.Zero : _routePoints[index];
    }

    /// <inheritdoc/>
    public override void _Ready()
    {
        base._Ready();
        _dan = Companion;
        ApplyRoomBounds(StartRoom);
        Darkness.Color = DarknessLit;
        Cutscene.Skippable = CutsceneSkippable;
        ReadRoute();
        _arenaShape = ArenaZone.GetNodeOrNull<CollisionShape2D>("CollisionShape2D");
        foreach (LitZone pool in PatrolPools)
        {
            if (pool.GetNodeOrNull<CollisionShape2D>("CollisionShape2D") is { } shape)
            {
                _poolShapes.Add(shape);
            }
        }

        Player.StateChanged += OnPlayerStateChanged;
        Player.Flashlight.Toggled += OnLampToggled;
        Cutscene.Finished += OnCutsceneFinished;
        CheckpointArmed += OnCheckpointArmed;
        Respawned += OnRespawned;

        if (_dan is not null)
        {
            _dan.Arrived += OnDanArrived;
            _dan.HeroReached += OnHeroReachedDan;
            _dan.HeroLagging += OnHeroLagging;
            _dan.WarpTo(DanStart);
            _dan.HoldAt(DanStart);
        }

        Circuit.LoadChanged += OnLoadChanged;
        Charge.Activated += OnChargeActivated;
        BlastTrigger.BodyEntered += OnBlastTriggerEntered;
        GuardWave.WaveStarted += OnWaveStarted;
        GuardWave.EnemySpawned += OnEnemySpawned;
        GuardWave.WaveCleared += OnWaveCleared;
        TimberPile.Resisted += OnTimberResisted;
        TimberPile.Cleared += OnTimberCleared;
        Lights.PowerChanged += OnLightsPowerChanged;
        Cage.PowerChanged += OnCagePowerChanged;
        Cage.ActivationRefused += OnCageRefused;
        Cage.Departed += OnCageDeparted;
        LevelExit.BodyEntered += OnExitEntered;

        foreach (Outlet outlet in Outlets)
        {
            outlet.Charged += OnOutletCharged;
        }

        foreach (GasZone pocket in GasPockets)
        {
            pocket.WarningStarted += OnGasWarningStarted;
            pocket.Ignited += OnGasIgnited;
        }

        foreach (Node child in Patrol.GetChildren())
        {
            if (child is Guard guard)
            {
                guard.SetTarget(Player, Director);
                guard.Noticed += OnPatrolNoticed;
                guard.KnockedOut += OnPatrolKnockedOut;
                guard.Dropped += OnGuardDropped;
                _patrolGuards.Add(guard);
            }
        }

        foreach (Node child in Tutorial.GetChildren())
        {
            if (child is TutorialPrompt hint)
            {
                TutorialPrompt.ShownEventHandler shown = () => OnHintShown(hint);
                TutorialPrompt.CompletedEventHandler completed = () => OnHintCompleted(hint);
                hint.Shown += shown;
                hint.Completed += completed;
                _hintHandlers.Add((hint, shown, completed));
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
        Player.Flashlight.Toggled -= OnLampToggled;
        Cutscene.Finished -= OnCutsceneFinished;
        CheckpointArmed -= OnCheckpointArmed;
        Respawned -= OnRespawned;

        if (_dan is not null && IsInstanceValid(_dan))
        {
            _dan.Arrived -= OnDanArrived;
            _dan.HeroReached -= OnHeroReachedDan;
            _dan.HeroLagging -= OnHeroLagging;
        }

        Circuit.LoadChanged -= OnLoadChanged;
        Charge.Activated -= OnChargeActivated;
        BlastTrigger.BodyEntered -= OnBlastTriggerEntered;
        GuardWave.WaveStarted -= OnWaveStarted;
        GuardWave.EnemySpawned -= OnEnemySpawned;
        GuardWave.WaveCleared -= OnWaveCleared;
        TimberPile.Resisted -= OnTimberResisted;
        TimberPile.Cleared -= OnTimberCleared;
        Lights.PowerChanged -= OnLightsPowerChanged;
        Cage.PowerChanged -= OnCagePowerChanged;
        Cage.ActivationRefused -= OnCageRefused;
        Cage.Departed -= OnCageDeparted;
        LevelExit.BodyEntered -= OnExitEntered;

        foreach (Outlet outlet in Outlets)
        {
            outlet.Charged -= OnOutletCharged;
        }

        foreach (GasZone pocket in GasPockets)
        {
            pocket.WarningStarted -= OnGasWarningStarted;
            pocket.Ignited -= OnGasIgnited;
        }

        foreach (Guard guard in _patrolGuards)
        {
            if (IsInstanceValid(guard))
            {
                guard.Noticed -= OnPatrolNoticed;
                guard.KnockedOut -= OnPatrolKnockedOut;
                guard.Dropped -= OnGuardDropped;
            }
        }

        foreach (Guard guard in _waveGuards)
        {
            if (IsInstanceValid(guard))
            {
                guard.Damaged -= OnWaveGuardDamaged;
                guard.Dropped -= OnGuardDropped;
            }
        }

        foreach (EnergyPickup pickup in _pickups)
        {
            if (IsInstanceValid(pickup))
            {
                pickup.Collected -= OnPickupCollected;
            }
        }

        foreach ((TutorialPrompt hint, TutorialPrompt.ShownEventHandler shown, TutorialPrompt.CompletedEventHandler completed) in _hintHandlers)
        {
            hint.Shown -= shown;
            hint.Completed -= completed;
        }

        _hintHandlers.Clear();
        ClearPendingLines();
        DropBeatTimer();
        KillDarknessTween();
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
    /// Room bounds, respawn point, Dan's route and the story beat in one place: the checkpoint's
    /// <see cref="Checkpoint.Label"/> is this level's event key.
    /// </summary>
    private void OnCheckpointArmed(Checkpoint checkpoint)
    {
        if (checkpoint.Room is not null)
        {
            ApplyRoomBounds(checkpoint.Room);
        }

        if (CheckpointRoute.TryGetValue(checkpoint.Label, out string? key))
        {
            LeadAtLeast(key);
        }

        switch (checkpoint.Label)
        {
            case "face":
                SetStage(Stage.Face);
                break;
            case "dark":
                SetStage(Stage.Dark);
                break;
            case "drift":
                SetStage(Stage.Drift);
                break;
            case "gas_near":
                SetStage(Stage.Gas);
                break;
            case "patrol":
                SetStage(Stage.Patrol);
                if (Lights.IsPowered)
                {
                    TweenDarkness(DarknessDrift);
                }

                break;
            case "cage":
                SetStage(Stage.Cage);
                break;
        }
    }

    /// <summary>
    /// A soft respawn put the hero back at the armed checkpoint: Dan keeps his route point
    /// (re-issuing it is a no-op) and gets the stance of that point back — <see cref="Companion.LeadTo"/>
    /// clears the warning stance, so it is re-applied here. Gone, he needs nothing.
    /// </summary>
    private void OnRespawned()
    {
        if (_dan is null || !IsInstanceValid(_dan) || _dan.IsGone || _routeIndex < 0)
        {
            return;
        }

        string key = CurrentRouteKey;
        _dan.LeadTo(_routePoints[_routeIndex]);
        if (key == KeyGasEdge)
        {
            _dan.SetLampOn(false);
            _dan.SetWarning(true);
            if (_diedInGas)
            {
                SayLine(DanGasAgainLine);   // the respawn puts the hero back at his side
            }

            if (!Player.Flashlight.IsOn)
            {
                RunTo(KeyPastGas);   // the revived hero's lamp is off: the gate opens, he shows the dark crossing
            }
        }
        else if (DarkPatrolKeys.Contains(key))
        {
            _dan.SetLampOn(false);
        }
    }

    // ---- segment 0: the charge and the blast --------------------------------------------

    private void OnChargeActivated()
    {
        SetStage(Stage.Charge);
        PlayCutscene(Beat.Charge, ChargeLines);
    }

    private void OnBlastTriggerEntered(Node2D body)
    {
        if (body is Actors.Player && _stage == Stage.Charge)
        {
            TriggerBlast();
        }
    }

    /// <summary>
    /// The blast, scripted: the hero is frozen first, then the roof comes down behind him and the
    /// jam ahead is thrown clear, the lamps die and the mine goes black; the cutscene plays over
    /// it. Idempotent — the props trigger and Dan's <c>HeroReached</c> both call it.
    /// </summary>
    private void TriggerBlast()
    {
        if (_stage != Stage.Charge || BlastCollapse.HasCollapsed)
        {
            return;
        }

        SetStage(Stage.Blast);
        SetActorsPaused(true);   // frozen before anything moves: the seal lands behind him by construction
        BlastTrigger.SetDeferred(Area2D.PropertyName.Monitoring, false);
        BlastCollapse.Collapse();
        Jam.Clear();
        if (JamDecal is not null)
        {
            JamDecal.Visible = false;
        }

        if (WorkLamps is not null)
        {
            WorkLamps.Visible = false;   // the lamp string is gone for the rest of the mine
        }

        ConveyorAnimation?.Stop();
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

    // ---- segment 1: the wave and the banks ----------------------------------------------

    private void OnWaveStarted()
    {
        SetStage(Stage.Fight);
        _arenaShape?.SetDeferred(CollisionShape2D.PropertyName.Disabled, false);
        ArenaLamp.Visible = true;   // the guards bring the light: the fight is lit whether or not the lamp is on
        _dan?.SetWarning(true);   // faces the fight, no calls
        PlayCutscene(Beat.Guards, GuardsLines);
    }

    private void OnEnemySpawned(Node2D enemy)
    {
        if (enemy is not Guard guard)
        {
            return;
        }

        guard.DropScene = PickupScene;
        guard.Damaged += OnWaveGuardDamaged;
        guard.Dropped += OnGuardDropped;
        _waveGuards.Add(guard);
    }

    private void OnWaveGuardDamaged(float hp)
    {
        if (_heavyHinted)
        {
            return;
        }

        _heavyHinted = true;
        HeavyPrompt.Trigger();   // J and K are not taught in the same second
    }

    private void OnWaveCleared()
    {
        _dan?.SetWarning(false);
        LeadTo(KeyFaceExit);
        SayLine(DanBanksLine);
    }

    private void OnGuardDropped(Node2D drop)
    {
        if (drop is EnergyPickup pickup)
        {
            pickup.Collected += OnPickupCollected;
            _pickups.Add(pickup);
        }
    }

    private void OnPickupCollected(float amount)
    {
        if (_oursSaid)
        {
            return;
        }

        _oursSaid = true;
        SayLine(DanOursLine);
    }

    private void OnOutletCharged(float amount)
    {
        if (_outletSaid)
        {
            return;
        }

        _outletSaid = true;
        SayLine(DanOutletLine);
    }

    // ---- segment 2: the timber and the gas ----------------------------------------------

    private void OnTimberResisted() => SayLine(DanResistedLine);

    private void OnTimberCleared()
    {
        SayLine(DanClearedLine);
        LeadTo(KeyGasEdge);
    }

    private void OnGasWarningStarted() => SayLine(DanGasLine, bypassSilence: true);

    private void OnGasIgnited(Player player)
    {
        _diedInGas = true;
        _waitingForLampOff = false;   // the revive forces the lamp off; that toggle must not open the gate by itself
    }

    /// <summary>The gate at the edge of the gas: Dan goes on only once the hero's lamp is off.</summary>
    private void OnLampToggled(bool isOn)
    {
        if (isOn || !_waitingForLampOff)
        {
            return;
        }

        _waitingForLampOff = false;
        RunTo(KeyPastGas);   // he crosses the pocket dark, leash off
    }

    // ---- segment 3: the patrol ----------------------------------------------------------

    private void OnPatrolNoticed() => _patrolNoticed = true;

    private void OnPatrolKnockedOut()
    {
        _patrolDown++;
        if (_patrolDown < _patrolGuards.Count)
        {
            return;
        }

        _danSilent = false;
        SayLine(DanFoughtLine);
    }

    // ---- segment 4: the lights and the cage ---------------------------------------------

    private void OnLightsPowerChanged(bool powered)
    {
        // An invisible Area2D keeps colliding: the pools are *disabled* with the lights, never hidden.
        foreach (CollisionShape2D shape in _poolShapes)
        {
            shape.SetDeferred(CollisionShape2D.PropertyName.Disabled, !powered);
        }

        if (_stage >= Stage.Patrol && _stage < Stage.Held)
        {
            TweenDarkness(powered ? DarknessDrift : DarknessMine);
        }

        if (!powered)
        {
            _dan?.SetLampOn(true);
            SayLine(DanDarkLine);
        }
    }

    private void OnCageRefused()
    {
        if (!_ruleSaid)
        {
            _ruleSaid = true;
            SayLine(DanRuleLine);
            return;
        }

        SayLine(DanRefusedLine);
    }

    private void OnCagePowerChanged(bool powered)
    {
        // The hoist's own handler runs first and departs at once when the hero already stands in
        // the boarding area; the capture has then placed Dan and nothing may move him again.
        if (!powered || _stage >= Stage.Held)
        {
            return;
        }

        SayLine(DanBoardLine);
        RunTo(KeyBoard);
    }

    /// <summary>The only place the bus load reaches the debug label; it fires after every grant and release.</summary>
    private void OnLoadChanged(int used, int capacity) => RefreshLabel();

    // ---- segment 5: the capture and the surface -----------------------------------------

    /// <summary>
    /// The capture: a fixed placement, whatever the player did — the hero in the cage, Dan at the
    /// gate, the guards behind them where the drift they came through opens — then the cutscene.
    /// The patrol (if alive) is frozen for good: the mine is behind him from here on.
    /// </summary>
    private void OnCageDeparted(Player player)
    {
        SetStage(Stage.Held);
        _enemiesRetired = true;
        ClearPendingLines();
        SetActorsPaused(true);
        Player.GlobalPosition = HeroHeldAt;
        if (_dan is not null && IsInstanceValid(_dan))
        {
            _dan.WarpTo(DanHeldAt);
            _dan.HoldAt(DanHeldAt);
        }

        if (HeldGuards is not null)
        {
            HeldGuards.Visible = true;
        }

        PlayCutscene(Beat.Held, HeldLines);
    }

    /// <summary>After the capture: Dan is taken (no shot, no body), the screen goes black for a beat, nothing of the ride up is shown.</summary>
    private void OnHeldFinished()
    {
        if (_dan is not null && IsInstanceValid(_dan))
        {
            _dan.Vanish();
        }

        Companion = null;   // LevelBase must never relocate him again: he is gone from this level
        _danSilent = true;
        if (HeldGuards is not null)
        {
            HeldGuards.Visible = false;
        }

        TweenDarkness(DarknessBlack);
        DropBeatTimer();
        // processAlways: false so the beat waits behind an open pause menu; ignoreTimeScale so a
        // leftover hit-stop does not stretch it.
        _beatTimer = GetTree().CreateTimer(BlackBeatSeconds, processAlways: false, processInPhysics: false, ignoreTimeScale: true);
        _beatTimer.Timeout += OnBlackBeatElapsed;
    }

    private void OnBlackBeatElapsed()
    {
        DropBeatTimer();
        if (!IsInstanceValid(this) || !IsInsideTree())
        {
            return;   // the level was freed before the beat ran out (test teardown, scene change)
        }

        Player.GlobalPosition = SurfaceArrival;
        ApplyRoomBounds(SurfaceRoom);
        SetCheckpoint(SurfaceCheckpoint);   // the mine is behind him for good; a KO must never send him back down
        TweenDarkness(DarknessSurface);
        SetStage(Stage.Surface);
        PlayCutscene(Beat.Surface, EndLines);
    }

    private void OnExitEntered(Node2D body)
    {
        if (body is not Actors.Player || _stage != Stage.Surface)
        {
            return;
        }

        SetStage(Stage.Done);
        GoToLevel(NextLevel);
    }

    // ---- Dan's route ----------------------------------------------------------------------

    private void ReadRoute()
    {
        _routeKeys.Clear();
        _routePoints.Clear();
        foreach (Node child in DanRoute.GetChildren())
        {
            if (child is Marker2D marker && marker.Name.ToString().StartsWith("WP_"))
            {
                _routeKeys.Add(marker.Name.ToString()["WP_".Length..]);
                _routePoints.Add(marker.GlobalPosition);
            }
        }
    }

    /// <summary>Leads Dan to the route point <paramref name="key"/> with the leash on; an unknown key is an error and does nothing.</summary>
    private void LeadTo(string key) => Issue(key, run: false);

    /// <summary>Sends Dan to the route point <paramref name="key"/> at a run with the leash off.</summary>
    private void RunTo(string key) => Issue(key, run: true);

    /// <summary>Leads Dan to <paramref name="key"/> only if it lies further along the route than his current point — never back.</summary>
    private void LeadAtLeast(string key)
    {
        if (_routeKeys.IndexOf(key) > _routeIndex)
        {
            LeadTo(key);
        }
    }

    private void Issue(string key, bool run)
    {
        int index = _routeKeys.IndexOf(key);
        if (index < 0)
        {
            GD.PushError($"{Name}: no route point '{key}' under {DanRoute.Name}.");
            return;
        }

        _routeIndex = index;
        if (_dan is null || !IsInstanceValid(_dan) || _dan.IsGone)
        {
            return;
        }

        if (run)
        {
            _dan.RunTo(_routePoints[index]);
        }
        else
        {
            _dan.LeadTo(_routePoints[index]);
        }

        RefreshLabel();
    }

    private void LeadNext()
    {
        if (_routeIndex >= 0 && _routeIndex + 1 < _routeKeys.Count)
        {
            LeadTo(_routeKeys[_routeIndex + 1]);
        }
    }

    /// <summary>Dan reached his route point: the stance and the line of that point, or straight on at a corner.</summary>
    private void OnDanArrived()
    {
        if (_dan is null || !_dan.IsLeading)
        {
            return;   // a scripted hold, not a route point
        }

        string key = CurrentRouteKey;
        switch (key)
        {
            case KeyProps:
                SayLine(DanPropsLine);
                break;
            case KeyFaceExit:
                SayLine(DanDownHereLine);
                break;
            case KeyGasEdge:
                // The rule is shown before it is said: lamp out, a beat, then the line.
                _dan.SetLampOn(false);
                _dan.SetWarning(true);
                SayAfter(GasWarnDelaySeconds, DanGasWarnLine);
                break;
            case KeyPastGas:
                _dan.SetLampOn(true);
                break;
            case KeyDriftExit:
                SayLine(DanKeepComingLine);
                break;
            case KeyPatrolIn:
                _dan.SetLampOn(false);
                _dan.SetWarning(true);
                break;
            case KeyP3Out:
                _dan.SetLampOn(true);
                break;
        }

        if (!Gates.TryGetValue(key, out Gate gate) || gate == Gate.Auto)
        {
            LeadNext();
        }
    }

    /// <summary>The hero came to Dan at his route point: the line of that point, then the next one where the hero is the gate.</summary>
    private void OnHeroReachedDan()
    {
        if (_dan is null || !_dan.IsLeading)
        {
            return;
        }

        string key = CurrentRouteKey;
        switch (key)
        {
            case KeyCharge:
                SayLine(DanChargeLine);
                break;
            case KeyProps:
                TriggerBlast();
                return;
            case KeyTimber:
                SayLine(DanTimberLine);
                break;
            case KeyGasEdge:
                if (Player.Flashlight.IsOn)
                {
                    _waitingForLampOff = true;   // he does not go into the gas ahead of a lit lamp
                    return;
                }

                RunTo(KeyPastGas);
                return;
            case KeyPastGas:
                SayLine(DanGasPastLine);
                break;
            case KeyPatrolIn:
                SayLine(DanDuckLine);
                _danSilent = true;   // §3: the only full silence of the level
                break;
            case KeyP3Out:
                _danSilent = false;
                if (!_patrolNoticed)
                {
                    SayLine(DanNeverLookedLine);
                }

                break;
            case KeyCage:
                SayLine(DanCageLine);
                break;
        }

        if (Gates.TryGetValue(key, out Gate gate) && gate == Gate.HeroReached)
        {
            LeadNext();
        }
    }

    private void OnHeroLagging()
    {
        if (CurrentRouteKey == KeyProps)
        {
            SayLine(DanCountingLine);
            return;
        }

        SayLine(_callAgain ? DanCallAgainLine : DanCallLine);
        _callAgain = !_callAgain;
    }

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
                LeadTo(KeyCharge);
                break;
            case Beat.Charge:
                ResumeActors();
                RunTo(KeyProps);
                break;
            case Beat.Blast:
                ResumeActors();
                RunTo(KeyDark);
                break;
            case Beat.Guards:
                ResumeActors();
                AttackPrompt.Trigger();
                break;
            case Beat.Held:
                OnHeldFinished();   // the hero stays frozen through the black beat
                break;
            default:
                ResumeActors();
                break;
        }
    }

    /// <summary>
    /// Freezes the hero, the hints and every guard (a disabled <c>CollisionObject2D</c> also leaves
    /// the physics space, so nothing triggers meanwhile), hides the prompt and plays <paramref name="lines"/>.
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
        // Deferred: the wave's own trigger callback is one of the callers, and a collision object
        // may not leave the physics space from inside its overlap signal.
        ProcessModeEnum enemies = paused || _enemiesRetired ? ProcessModeEnum.Disabled : ProcessModeEnum.Inherit;
        Patrol.SetDeferred(Node.PropertyName.ProcessMode, (int)enemies);
        GuardWave.SetDeferred(Node.PropertyName.ProcessMode, (int)enemies);
    }

    // ---- Dan's lines --------------------------------------------------------------------

    /// <summary>Puts a line in Dan's bubble, unless he is deliberately silent (or already gone); the gas shout bypasses the silence.</summary>
    private void SayLine(string text, bool bypassSilence = false)
    {
        if ((_danSilent && !bypassSilence) || _dan is null || !IsInstanceValid(_dan) || _dan.IsGone)
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

    private void DropBeatTimer()
    {
        if (_beatTimer is not null)
        {
            _beatTimer.Timeout -= OnBlackBeatElapsed;
            _beatTimer = null;
        }
    }

    // ---- darkness -----------------------------------------------------------------------

    private void TweenDarkness(Color target)
    {
        KillDarknessTween();
        _darknessTween = CreateTween();
        _darknessTween.TweenProperty(Darkness, "color", target, DarknessFadeSeconds);
    }

    private void KillDarknessTween()
    {
        if (_darknessTween is not null && _darknessTween.IsValid())
        {
            _darknessTween.Kill();
        }

        _darknessTween = null;
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
        else if (ReferenceEquals(hint, AttackPrompt))
        {
            SayLine(DanAttackLine);
        }
        else if (ReferenceEquals(hint, HeavyPrompt))
        {
            SayLine(DanHeavyLine);
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
        DebugLabel.Text = $"Stage: {_stage}  State: {_playerState}  z: {_height}  Circuit {Circuit.Used}/{Circuit.Capacity}  Dan: {CurrentRouteKey}";
}
