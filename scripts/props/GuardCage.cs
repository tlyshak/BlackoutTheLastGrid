using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Core;
using BlackoutLastGrid.Enemies;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// The lift cage of the third painted section: two guards ride it down and wait behind the shut
/// grate, and the hero walks into their trap. The author asked for exactly this — «коли гравець
/// проходить ближче, відкриваються ворота і виходять охоронці» — so the order of events is the
/// order he described: the hero comes near, the grate goes (<see cref="Gate"/> is hidden and the
/// open shaft shows behind it), <see cref="OpenDelay"/> seconds pass so the eye reads the cage as
/// having opened, and only then do the <see cref="Caged"/> guards step out of it onto the walk
/// band and turn on him.
///
/// The trigger is a trip wire, not a wall: the area covers the last stretch of floor before the
/// cage across the whole depth of the band, so the ambush fires as the hero gets near the cage and
/// cannot be walked around along its far or near edge. It fires exactly once and never re-arms —
/// walking back out and in again finds an open cage and an empty lift, which is what an ambush
/// that has already been sprung should look like.
/// </summary>
/// <remarks>
/// <para>
/// Scene contract: root <c>Area2D</c> on layer 0 with mask 2 (Player), monitoring, one
/// <c>RectangleShape2D</c>. The level places the node on the floor in front of the painted cage
/// and fills in <see cref="Caged"/>, <see cref="Exits"/>, <see cref="Gate"/>,
/// <see cref="Player"/> and <see cref="Director"/>; the smoke test rebuilds the whole fixture and
/// fails on a drift.
/// </para>
/// <para>
/// The walk-out is a real walk, not a teleport: each guard is driven to his exit marker with
/// <see cref="Enemies.Guard.VelocityTowards"/> and <see cref="Enemies.Guard.Move"/>, the same
/// helpers his own Approach state uses, and only then is he given his target. Placing him at the
/// marker would have been the shorter code, but the author asked for guards that <i>come out</i>,
/// and a pair that pops onto the floor already fighting does not read as coming out of a cage.
/// Driving them is safe while they have no target: a guard without one stands in Idle and moves
/// nothing, so nothing fights this class for the velocity, and the moment he is woken the state
/// machine takes him over for good. <see cref="Guard"/> itself is untouched — only its public API.
/// </para>
/// <para>
/// Everything runs in <c>_PhysicsProcess</c>, so the delay and the walk freeze with the pause menu
/// and with a hit-stop instead of running on behind them, and the process is switched off for good
/// once the last guard is out.
/// </para>
/// </remarks>
public partial class GuardCage : Area2D
{
    /// <summary>Emitted once, the moment the cage opens (before the guards start out).</summary>
    [Signal]
    public delegate void OpenedEventHandler();

    /// <summary>The guards waiting inside the cage. May be empty: an empty cage still opens.</summary>
    [Export] public Guard[] Caged { get; set; } = { };

    /// <summary>
    /// The hero: the guards' target on release. Left <c>null</c> the cage takes whoever tripped it,
    /// so the prop works in a fixture with nothing but a hero and a guard.
    /// </summary>
    [Export] public Player? Player { get; set; }

    /// <summary>Attack-slot director of the level; handed to every released guard with the target.</summary>
    [Export] public EnemyDirector? Director { get; set; }

    /// <summary>
    /// The painted grate that shuts the cage, hidden the moment the cage opens — it is its own
    /// sprite cut out of the section art, so hiding it reveals the open shaft painted behind it.
    /// Optional: a cage without a drawn grate simply releases its guards.
    /// </summary>
    [Export] public CanvasItem? Gate { get; set; }

    /// <summary>
    /// Where each caged guard walks to when released, one marker per entry of
    /// <see cref="Caged"/> and in the same order. Every marker belongs inside the room's walk band,
    /// in front of the cage, or the guard walks out into the back wall. A guard with no marker of
    /// his own simply wakes where he stands.
    /// </summary>
    [Export] public Marker2D[] Exits { get; set; } = { };

    /// <summary>
    /// Seconds between the trigger firing and the guards starting out. Long enough that the grate
    /// is seen to go first — the author's order of events — short enough that the hero does not
    /// get to walk past an open cage before anyone reacts.
    /// </summary>
    [Export] public float OpenDelay { get; set; } = 0.35f;

    /// <summary>
    /// Px from his exit marker at which a guard counts as out and is woken. A hair of slack, so a
    /// guard nudged off the last half-pixel by a wall or by his fellow still finishes coming out.
    /// </summary>
    [Export] public float ArriveDistance { get; set; } = 6f;

    /// <summary>
    /// Seconds after which a guard still on his way out is woken regardless. The ambush must start
    /// even when something in the room stands in his path; without this a blocked guard would walk
    /// into an obstacle for the rest of the level instead of fighting.
    /// </summary>
    [Export] public float WalkOutTimeout { get; set; } = 3f;

    /// <summary>Looping animation played while a guard walks out of the cage (his own gait).</summary>
    [Export] public StringName WalkAnimation { get; set; } = "walk";

    private Player? _hero;          // who the guards are given: the export, or whoever tripped the trigger
    private bool[] _released = { }; // per caged guard: already woken, never woken twice
    private float _delayLeft;
    private float _walkTime;
    private bool _walkStarted;

    /// <summary><c>true</c> once the cage has opened; it never goes back to <c>false</c>.</summary>
    public bool IsOpen { get; private set; }

    /// <inheritdoc/>
    public override void _PhysicsProcess(double delta)
    {
        if (delta <= 0d)
        {
            return;   // hit-stop: the delay must not run and nobody walks on a frozen frame
        }

        float step = (float)delta;
        if (!IsOpen)
        {
            WatchForHero();
            return;
        }

        if (_delayLeft > 0f)
        {
            _delayLeft = Mathf.Max(0f, _delayLeft - step);
            return;   // the grate is gone, the guards have not started yet
        }

        _walkTime += step;
        WalkOut(delta);
    }

    /// <summary>Opens the cage on the first hero standing in the trigger. Only the Player layer is masked, so nothing else can spring it.</summary>
    private void WatchForHero()
    {
        foreach (Node2D body in GetOverlappingBodies())
        {
            if (body is not Player hero || hero.IsKnockedOut)
            {
                continue;
            }

            Open(hero);
            return;
        }
    }

    /// <summary>Springs the trap: the grate goes, the trigger disarms for good, the delay starts.</summary>
    /// <param name="hero">The hero who tripped it; used as the target when <see cref="Player"/> is unset.</param>
    private void Open(Player hero)
    {
        IsOpen = true;
        _hero = Player ?? hero;
        _delayLeft = OpenDelay;
        _released = new bool[Caged.Length];
        if (Gate is not null)
        {
            Gate.Visible = false;
        }

        // Deferred: the area is being read for its overlaps right now, and an ambush that is over
        // must not watch the floor any more — a hero walking back and forth finds an empty lift.
        SetDeferred(Area2D.PropertyName.Monitoring, false);
        EmitSignalOpened();
    }

    /// <summary>Walks every guard still inside towards his exit marker, and wakes each one as he arrives.</summary>
    /// <param name="delta">Physics step in seconds.</param>
    private void WalkOut(double delta)
    {
        StartWalk();
        bool walking = false;
        for (int i = 0; i < Caged.Length; i++)
        {
            if (!IsStillCaged(i, out Guard? guard) || guard is null)
            {
                continue;
            }

            Marker2D? exit = ExitOf(i);
            Vector2 offset = exit is null ? Vector2.Zero : exit.GlobalPosition - guard.GlobalPosition;
            if (exit is null || offset.Length() <= ArriveDistance || _walkTime >= WalkOutTimeout)
            {
                Release(i, guard);
                continue;
            }

            guard.FaceTowards(offset.X);
            guard.Move(guard.VelocityTowards(exit.GlobalPosition, delta));
            walking = true;
        }

        if (!walking)
        {
            SetPhysicsProcess(false);   // the cage is empty and disarmed: nothing left to do, ever
        }
    }

    /// <summary>Puts every guard about to come out into his walking gait, once.</summary>
    private void StartWalk()
    {
        if (_walkStarted)
        {
            return;
        }

        _walkStarted = true;
        for (int i = 0; i < Caged.Length; i++)
        {
            if (IsStillCaged(i, out Guard? guard) && guard is not null && ExitOf(i) is not null)
            {
                guard.PlayAnimation(WalkAnimation);
            }
        }
    }

    /// <summary>Hands the guard his prey and makes him aware, which sends his own state machine to Approach.</summary>
    /// <param name="index">Index in <see cref="Caged"/>.</param>
    /// <param name="guard">The guard that has finished coming out.</param>
    private void Release(int index, Guard guard)
    {
        _released[index] = true;
        guard.Stop();
        if (_hero is { } hero && Director is { } director && IsInstanceValid(director))
        {
            guard.SetTarget(hero, director);
        }

        // Awake on release, not on sight: this is an ambush sprung on the hero from a few paces
        // away, so it must fire even when he stands unlit behind the guard's back.
        guard.SetAware();
    }

    /// <summary>
    /// <c>true</c> while the guard at <paramref name="index"/> is a live node that still owes the
    /// cage a walk-out. A guard freed from the tree (killed and cleaned up by the level, or never
    /// wired at all) is skipped, and one already released is left to his state machine.
    /// </summary>
    /// <param name="index">Index in <see cref="Caged"/>.</param>
    /// <param name="guard">The guard, when there is one.</param>
    private bool IsStillCaged(int index, out Guard? guard)
    {
        guard = Caged[index];
        return guard is not null
            && IsInstanceValid(guard)
            && !guard.IsQueuedForDeletion()
            && guard.IsInsideTree()
            && !_released[index];
    }

    /// <summary>The exit marker of the guard at <paramref name="index"/>, or <c>null</c> when he has none (he wakes where he stands).</summary>
    /// <param name="index">Index in <see cref="Caged"/>.</param>
    private Marker2D? ExitOf(int index)
    {
        if (index >= Exits.Length)
        {
            return null;
        }

        Marker2D? exit = Exits[index];
        return exit is not null && IsInstanceValid(exit) && exit.IsInsideTree() ? exit : null;
    }
}
