using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Levels;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// The sealing crew's field of view (GAME_DESIGN §3, segment 3): a stretch of drift that is watched
/// by people the hero cannot fight at this point in the story, and is therefore crossed in the dark.
/// The zone reacts to <see cref="Player.IsLit"/> — the head lamp <b>or</b> one of the crew's own
/// <see cref="LitZone"/> lamp pools — so the segment is navigation and not "do not press F": weave
/// through the dark lanes the pools leave. Being seen opens a short warning window
/// (<see cref="WarningSeconds"/>) in which killing the lamp or stepping out of the pool still saves
/// you; letting it run out is an ordinary knock-out through <see cref="Player.Kill"/>, i.e. the same
/// checkpoint respawn every other mistake in this level costs.
/// </summary>
/// <remarks>
/// <para>
/// Scene contract: root <c>Area2D</c> with <c>collision_layer = 0</c>, <c>collision_mask = 2</c>
/// (Player), <c>monitorable = false</c> and one <c>CollisionShape2D</c> spanning the watched stretch
/// across the whole floor band — the <see cref="GasZone"/> contract, so no new physics layer is
/// needed. The alert light is an optional placeholder child wired through <see cref="AlertLight"/>.
/// </para>
/// <para>
/// A zone that does not cover the room's walk band is not a zone at all: the hero walks past it in
/// depth with his lamp on and the segment teaches nothing. <see cref="Room"/> makes <c>_Ready</c>
/// say so out loud, exactly as <see cref="GasZone"/> does.
/// </para>
/// <para>
/// <see cref="Player"/> exposes no "lit" signal (the state is the lamp plus a count of overlapping
/// lamp pools), so the flag is polled — one <c>bool</c> per physics frame, and only while the hero
/// is inside the zone: <c>_PhysicsProcess</c> is switched off on every exit.
/// </para>
/// </remarks>
public partial class WatchZone : Area2D
{
    /// <summary>Emitted when the hero is inside the zone and lit; the warning window starts.</summary>
    [Signal]
    public delegate void SpottedEventHandler();

    /// <summary>Emitted when he went dark or left before the window ran out.</summary>
    [Signal]
    public delegate void LostSightEventHandler();

    /// <summary>Emitted when the window ran out, just before the hero is knocked out.</summary>
    [Signal]
    public delegate void CaughtEventHandler(Player player);

    /// <summary>Seconds between "seen" and "caught": kill the lamp or leave the pool and you live.</summary>
    [Export] public float WarningSeconds { get; set; } = 0.6f;

    /// <summary>Lamp flared while the warning counts down, so being seen is visible and not only fatal.</summary>
    [Export] public PointLight2D? AlertLight { get; set; }

    /// <summary>
    /// Room this zone sits in. Optional, and used for nothing but the <c>_Ready</c> sanity check
    /// that the watched stretch really spans the room's walk band.
    /// </summary>
    [Export] public RoomBounds? Room { get; set; }

    /// <summary>
    /// <c>true</c> retires the zone for good — the crew moved on. Set by the level once the segment
    /// is over; a retired zone stops watching and can never catch anybody again.
    /// </summary>
    [Export]
    public bool Disabled
    {
        get => _disabled;
        set
        {
            _disabled = value;
            if (!_disabled || !IsInsideTree())
            {
                return;
            }

            Disarm();
            ForgetPlayer();
            SetDeferred(Area2D.PropertyName.Monitoring, false);
        }
    }

    private bool _disabled;
    private Player? _player;
    private bool _warning;
    private float _remaining;

    /// <summary><c>true</c> while the warning window is counting down.</summary>
    public bool IsWarning => _warning;

    /// <summary>Seconds left of the warning window, or 0 when none is running.</summary>
    public float WarningRemaining => _warning ? _remaining : 0f;

    /// <inheritdoc/>
    public override void _Ready()
    {
        SetPhysicsProcess(false);
        if (AlertLight is not null)
        {
            AlertLight.Enabled = false;
        }

        WarnUnlessTheBandIsCovered();
        BodyEntered += OnBodyEntered;
        BodyExited += OnBodyExited;
        if (_disabled)
        {
            SetDeferred(Area2D.PropertyName.Monitoring, false);
        }
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        BodyEntered -= OnBodyEntered;
        BodyExited -= OnBodyExited;
        ForgetPlayer();
    }

    /// <summary>Polls the hero's lit state and runs the warning window; off whenever the zone is empty.</summary>
    /// <param name="delta">Physics frame time in seconds.</param>
    public override void _PhysicsProcess(double delta)
    {
        if (_player is null || !IsInstanceValid(_player))
        {
            ForgetPlayer();
            Disarm();
            SetPhysicsProcess(false);
            return;
        }

        if (_player.IsKnockedOut)
        {
            // A hero who is already down is not watched. Player.Kill() is a no-op while he is
            // knocked out and his head lamp only goes out on the revive, so without this the zone
            // re-arms on the very next frame and flares (and would fire Spotted/Caught a second
            // time) over a body for the whole respawn delay.
            if (_warning)
            {
                Disarm();
                EmitSignalLostSight();
            }

            return;
        }

        if (!_player.IsLit)
        {
            if (_warning)
            {
                Disarm();
                EmitSignalLostSight();
            }

            return;
        }

        if (!_warning)
        {
            _warning = true;
            _remaining = WarningSeconds;
            if (AlertLight is not null)
            {
                AlertLight.Enabled = true;
            }

            EmitSignalSpotted();
            return;
        }

        // A hit-stop delivers delta == 0, so the window freezes with the rest of the game.
        _remaining -= (float)delta;
        if (_remaining <= 0f)
        {
            Catch();
        }
    }

    private void OnBodyEntered(Node2D body)
    {
        if (_disabled || body is not Player player)
        {
            return;
        }

        _player = player;
        SetPhysicsProcess(true);
    }

    private void OnBodyExited(Node2D body)
    {
        if (!ReferenceEquals(body, _player))
        {
            return;
        }

        bool wasWarning = _warning;
        ForgetPlayer();
        Disarm();
        SetPhysicsProcess(false);
        if (wasWarning)
        {
            EmitSignalLostSight();
        }
    }

    /// <summary>The window ran out: announce it and hand the hero to the level's ordinary KO path.</summary>
    private void Catch()
    {
        Player? player = _player;
        Disarm();
        if (player is null || !IsInstanceValid(player))
        {
            return;
        }

        EmitSignalCaught(player);
        player.Kill();
    }

    /// <summary>Ends a running window without announcing anything and puts the alert lamp out.</summary>
    private void Disarm()
    {
        _warning = false;
        _remaining = 0f;
        if (AlertLight is not null)
        {
            AlertLight.Enabled = false;
        }
    }

    private void ForgetPlayer() => _player = null;

    /// <summary>
    /// Warns when the watched stretch is shallower than <see cref="Room"/>'s walk band — i.e. when
    /// the hero can walk past the crew in depth with his lamp on. Runs once, in <c>_Ready</c>; a
    /// zone without a room says nothing.
    /// </summary>
    private void WarnUnlessTheBandIsCovered()
    {
        if (Room is null)
        {
            return;
        }

        float top = float.MaxValue;
        float bottom = float.MinValue;
        foreach (Node child in GetChildren())
        {
            if (child is not CollisionShape2D { Disabled: false, Shape: RectangleShape2D rectangle } shape)
            {
                continue;
            }

            float centre = shape.GlobalPosition.Y;
            top = Mathf.Min(top, centre - (rectangle.Size.Y * 0.5f));
            bottom = Mathf.Max(bottom, centre + (rectangle.Size.Y * 0.5f));
        }

        if (top <= Room.FloorTop && bottom >= Room.FloorBottom)
        {
            return;
        }

        GD.PushWarning($"{Name}: the crew watches Y {top}…{bottom} but {Room.Name}'s walk band is {Room.FloorTop}…{Room.FloorBottom}; the hero can walk past them in depth.");
    }
}
