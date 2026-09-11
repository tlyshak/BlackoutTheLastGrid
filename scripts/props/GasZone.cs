using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Art;
using BlackoutLastGrid.Core;
using BlackoutLastGrid.Levels;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// A methane pocket: the inversion of the game's core resource — light kills here. The air is
/// visibly tinted (<see cref="HazeColor"/>) at all times, so the pocket is readable *before* it can
/// hurt anybody; entering it with the head lamp on (or switching the lamp on inside) starts a short
/// warning window (<see cref="WarningSeconds"/>) during which the haze flares and
/// <see cref="WarningStartedEventHandler"/> lets the level react (the companion shouts). Switching
/// the lamp off or leaving the pocket cancels the window; only when it runs out does the pocket
/// ignite and route into the hero's ordinary KO through <see cref="Player.Kill"/>. Cleared once and
/// for ever by an extractor (<see cref="Clear"/>) — there is no refill timer.
/// </summary>
/// <remarks>
/// <para>
/// Scene contract: root <c>Area2D</c> with <c>collision_layer = 0</c>, <c>collision_mask = 2</c>
/// (Player), <c>monitorable = false</c> and one <c>CollisionShape2D</c> spanning the pocket across
/// the floor band — the same trigger shape as <c>Door</c> and <c>TutorialPrompt</c>, so no new
/// physics layer is needed. The haze, the warning light and the motes are optional placeholder
/// children wired through the exports below.
/// </para>
/// <para>
/// The shape has to cover the room's <b>whole</b> walk band, or the gate is not a gate: a pocket
/// the hero can walk around in depth turns "power the extractor or cross it in the dark" into an
/// optional detour. The prefab ships band-deep (320 px) and <see cref="Room"/> makes
/// <c>_Ready</c> say so out loud when an instance was narrowed below its room's band.
/// </para>
/// <para>
/// The lamp state is learned by subscribing to the hero's <see cref="Flashlight.Toggled"/> on
/// <c>BodyEntered</c> and unsubscribing on <c>BodyExited</c>: no polling, no export to wire, and
/// <c>_PhysicsProcess</c> runs only while a warning is actually counting down.
/// </para>
/// </remarks>
public partial class GasZone : Area2D, IClearable
{
    /// <summary>Alpha of the resting haze — visible enough to read as "the air is wrong", not enough to hide the floor.</summary>
    private const float HazeRestingAlpha = 0.2f;

    /// <summary>Alpha of the haze while the warning counts down.</summary>
    private const float HazeWarningAlpha = 0.42f;

    /// <summary>Emitted when the hero is inside with the lamp on and the warning window starts.</summary>
    [Signal]
    public delegate void WarningStartedEventHandler();

    /// <summary>Emitted when the window is cancelled in time — the lamp went off or the hero left.</summary>
    [Signal]
    public delegate void WarningStoppedEventHandler();

    /// <summary>Emitted the moment the window ran out, before the blast is applied to the hero.</summary>
    [Signal]
    public delegate void IgnitedEventHandler(Player player);

    /// <summary>Emitted once when the pocket is cleared for good.</summary>
    [Signal]
    public delegate void ClearedEventHandler();

    /// <summary>
    /// Seconds between "the lamp is on inside the gas" and the ignition. This is the fairness
    /// budget of the whole mechanic: long enough to kill the lamp and live. A rehearsal pocket
    /// raises it (≈1.5 s) so the first contact is a scare, not a corpse.
    /// </summary>
    [Export] public float WarningSeconds { get; set; } = 0.8f;

    /// <summary><c>true</c> ignites into a death; <c>false</c> makes the blast a flash burn (energy + knockdown).</summary>
    [Export] public bool Lethal { get; set; } = true;

    /// <summary>Energy units the blast costs when <see cref="Lethal"/> is <c>false</c>.</summary>
    [Export] public float BlastDamage { get; set; } = 25f;

    /// <summary>Horizontal push of a non-lethal blast, in px/s (away from the pocket's centre).</summary>
    [Export] public float BlastKnockback { get; set; } = 220f;

    /// <summary>Physics frames of hit-stop on ignition.</summary>
    [Export] public int BlastHitStopFrames { get; set; } = 6;

    /// <summary>The layer that colours the air; a <c>Polygon2D</c> placeholder today, a painted sprite later.</summary>
    [Export] public CanvasItem? Haze { get; set; }

    /// <summary>Colour of the air while the pocket is dangerous but quiet.</summary>
    [Export] public Color HazeColor { get; set; } = new(Palette.GasHaze, HazeRestingAlpha);

    /// <summary>Colour of the air while the warning counts down.</summary>
    [Export] public Color HazeWarningColor { get; set; } = new(Color.FromHtml("#e0d24a"), HazeWarningAlpha);

    /// <summary>Seconds the haze takes to fade out once the pocket is cleared.</summary>
    [Export] public float HazeFadeSeconds { get; set; } = 0.9f;

    /// <summary>Light that flares while the warning counts down; off at rest.</summary>
    [Export] public PointLight2D? WarningLight { get; set; }

    /// <summary>Still motes in the beam — "no draught here"; emitting while the pocket is dangerous, stopped once it is cleared.</summary>
    [Export] public GpuParticles2D? Motes { get; set; }

    /// <summary>
    /// Room this pocket sits in. Optional, and used for nothing but a sanity check: a pocket whose
    /// trigger does not span the room's walk band can be walked around in depth, and
    /// <c>_Ready</c> warns about it instead of letting the level ship a gate that is not one.
    /// </summary>
    [Export] public RoomBounds? Room { get; set; }

    private Player? _player;
    private bool _warning;
    private float _remaining;

    /// <summary><c>true</c> once the pocket has been cleared; a cleared pocket is inert for good.</summary>
    public bool IsCleared { get; private set; }

    /// <summary><c>true</c> while the warning window is counting down.</summary>
    public bool IsWarning => _warning;

    /// <summary>Seconds left of the warning window, or 0 when none is running.</summary>
    public float WarningRemaining => _warning ? _remaining : 0f;

    /// <inheritdoc/>
    public override void _Ready()
    {
        SetPhysicsProcess(false);
        ApplyHazeColor(HazeColor);
        if (WarningLight is not null)
        {
            WarningLight.Enabled = false;
        }

        if (Motes is not null)
        {
            // Still motes are the readability cue for "no draught here" (GAME_DESIGN §6): they run
            // for as long as the pocket is dangerous, and Clear() is what stops them.
            Motes.Emitting = !IsCleared;
        }

        WarnUnlessTheBandIsCovered();
        BodyEntered += OnBodyEntered;
        BodyExited += OnBodyExited;
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        BodyEntered -= OnBodyEntered;
        BodyExited -= OnBodyExited;
        ForgetPlayer();
    }

    /// <inheritdoc/>
    public override void _PhysicsProcess(double delta)
    {
        if (!_warning)
        {
            SetPhysicsProcess(false);
            return;
        }

        // During a hit-stop the physics step arrives with delta == 0, so the window freezes with
        // the rest of the game instead of burning down behind a frozen frame.
        _remaining -= (float)delta;
        if (_remaining <= 0f)
        {
            Ignite();
        }
    }

    /// <summary>
    /// Removes the pocket for good (the extractor did its work): the window stops, the trigger goes
    /// quiet, the haze fades out over <see cref="HazeFadeSeconds"/> and the motes stop. Idempotent,
    /// and safe to call from a physics callback — the monitoring flag is deferred.
    /// </summary>
    public void Clear()
    {
        if (IsCleared)
        {
            return;
        }

        IsCleared = true;
        StopWarning(notify: false);
        ForgetPlayer();
        SetDeferred(Area2D.PropertyName.Monitoring, false);
        FadeHazeOut();
        if (Motes is not null)
        {
            Motes.Emitting = false;
        }

        EmitSignalCleared();
    }

    private void OnBodyEntered(Node2D body)
    {
        if (IsCleared || body is not Player player)
        {
            return;
        }

        if (!ReferenceEquals(_player, player))
        {
            ForgetPlayer();
            _player = player;
            player.Flashlight.Toggled += OnLampToggled;
        }

        if (player.Flashlight.IsOn)
        {
            StartWarning();
        }
    }

    private void OnBodyExited(Node2D body)
    {
        if (!ReferenceEquals(body, _player))
        {
            return;
        }

        ForgetPlayer();
        StopWarning(notify: true);
    }

    private void OnLampToggled(bool isOn)
    {
        if (isOn)
        {
            StartWarning();
        }
        else
        {
            StopWarning(notify: true);
        }
    }

    /// <summary>Starts the warning window (or leaves a running one alone) and flares the haze.</summary>
    private void StartWarning()
    {
        if (_warning || IsCleared || _player is null)
        {
            return;
        }

        _warning = true;
        _remaining = WarningSeconds;
        ApplyHazeColor(HazeWarningColor);
        if (WarningLight is not null)
        {
            WarningLight.Enabled = true;
        }

        SetPhysicsProcess(true);
        EmitSignalWarningStarted();
    }

    /// <summary>Stops a running window and calms the haze; <paramref name="notify"/> reports a cancel, an ignition does not.</summary>
    private void StopWarning(bool notify)
    {
        SetPhysicsProcess(false);
        if (!_warning)
        {
            return;
        }

        _warning = false;
        _remaining = 0f;
        if (WarningLight is not null)
        {
            WarningLight.Enabled = false;
        }

        if (!IsCleared)
        {
            ApplyHazeColor(HazeColor);
        }

        if (notify)
        {
            EmitSignalWarningStopped();
        }
    }

    /// <summary>
    /// The window ran out: freeze for a few frames, announce it and hand the hero to the ordinary
    /// death path (or to a flash burn on a non-lethal pocket). Nothing re-arms by itself — the
    /// hero has to leave and come back, or toggle the lamp again.
    /// </summary>
    private void Ignite()
    {
        Player? player = _player;
        StopWarning(notify: false);
        if (player is null || !IsInstanceValid(player))
        {
            return;
        }

        HitStop.Trigger(BlastHitStopFrames);
        EmitSignalIgnited(player);
        if (Lethal)
        {
            player.Kill();
            return;
        }

        float side = player.GlobalPosition.X >= GlobalPosition.X ? 1f : -1f;
        player.TakeDamage(BlastDamage, BlastKnockback * side, true, BlastHitStopFrames);
    }

    /// <summary>
    /// Warns when the pocket's trigger is shallower than <see cref="Room"/>'s walk band, i.e. when
    /// the hero can simply walk past the gas in depth with the lamp on. Runs once, in
    /// <c>_Ready</c>; a pocket without a room says nothing.
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

        GD.PushWarning($"{Name}: the pocket covers Y {top}…{bottom} but {Room.Name}'s walk band is {Room.FloorTop}…{Room.FloorBottom}; the hero can walk around the gas in depth.");
    }

    /// <summary>Drops the subscription to the hero's lamp; safe to call when there is none.</summary>
    private void ForgetPlayer()
    {
        if (_player is not null && IsInstanceValid(_player))
        {
            _player.Flashlight.Toggled -= OnLampToggled;
        }

        _player = null;
    }

    /// <summary>
    /// Paints the air. A <c>Polygon2D</c> placeholder carries the colour itself; any other
    /// <see cref="CanvasItem"/> (a painted haze sprite) is tinted through its modulate.
    /// </summary>
    private void ApplyHazeColor(Color color)
    {
        switch (Haze)
        {
            case null:
                return;
            case Polygon2D polygon:
                polygon.Color = color;
                return;
            default:
                Haze.Modulate = color;
                return;
        }
    }

    /// <summary>Fades the air to fully transparent; an instant fade is applied without a tween.</summary>
    private void FadeHazeOut()
    {
        if (Haze is null)
        {
            return;
        }

        Color target = Haze is Polygon2D polygon ? polygon.Color : Haze.Modulate;
        target.A = 0f;
        if (HazeFadeSeconds <= 0f)
        {
            ApplyHazeColor(target);
            return;
        }

        Tween tween = CreateTween();
        tween.TweenProperty(Haze, Haze is Polygon2D ? "color" : "modulate", target, HazeFadeSeconds);
    }
}
