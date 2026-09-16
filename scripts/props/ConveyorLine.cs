using System.Collections.Generic;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// The belt line of the ventilation room (T-V2-06, the author's r2 concept of section 2): while it
/// runs it carries whoever steps on it back down the drift, and the chevrons of its drawn belt keep
/// moving. The hero can walk onto the belt — the author asked for that explicitly: a body rides
/// <see cref="GrabDelay"/> seconds before the band takes hold, which is a step and a half onto the
/// drawn conveyor, and is then swept back out at <see cref="CarrySpeed"/>, far above his own walking
/// speed. Step on, get taken, land back in the drift; there is no forcing a way across, because the
/// grace resets every time he leaves. The lever is the only way through. The
/// carried area is as wide as the drawn conveyor and as deep as the walk band, so a running belt
/// cannot be walked around either; stopping it ends the carry for good in that run.
///
/// The band on either side of the drawn belt is closed for good by <see cref="RailFar"/> and
/// <see cref="RailNear"/> — the machinery behind the conveyor and the cart train in front of it —
/// so the strip the belt is drawn on is the only gap in the drift: a stopped belt is not an open
/// room, it is the one lane through. Bodies in <see cref="PassThrough"/> (the guide) are neither
/// carried nor stopped by the rails.
/// <see cref="ConveyorSwitch"/> is what stops it.
/// </summary>
/// <remarks>
/// <para>
/// Scene contract: root <c>Area2D</c> on layer 0 with mask 2 (Player), the
/// <see cref="BlockerShape"/> footprint (a <c>RectangleShape2D</c> stretched to
/// <see cref="BlockerDepth"/> across the band), the <see cref="Belt"/> sprite that tiles the
/// one-period chevron crop of the mockup, and the two indicator sprites. The sprites are placed by
/// the owning level on the very pixels the painted room draws them at — the smoke test recomputes
/// those from the mockup coordinates and fails on a drift.
/// </para>
/// <para>
/// The scroll lives in <c>_Process</c> and the carry in <c>_PhysicsProcess</c>: both freeze with
/// the pause menu (process mode inherit) and slow with a hit-stop (the delta is scaled). The carry
/// reads only the bodies the area already reports overlapping and moves them with
/// <c>MoveAndCollide</c>, so a wall or another body still stops them; no combat or player class is
/// touched. The level wires the switch to the line with an <c>[Export]</c>.
/// </para>
/// </remarks>
public partial class ConveyorLine : Area2D
{
    /// <summary>Emitted whenever <see cref="Running"/> changes.</summary>
    [Signal]
    public delegate void RunningChangedEventHandler(bool running);

    /// <summary>
    /// <c>true</c> while the belt runs: the band carries what stands on it, the chevrons move, the
    /// green indicators show. Set by <see cref="ConveyorSwitch"/>.
    /// </summary>
    [Export]
    public bool Running
    {
        get => _running;
        set
        {
            if (_running == value)
            {
                return;
            }
            _running = value;
            if (IsInsideTree())
            {
                Apply();
                EmitSignal(SignalName.RunningChanged, _running);
            }
        }
    }

    /// <summary>The belt's footprint: what stands inside it is carried while the belt runs. Disabled once it is stopped.</summary>
    [Export] public CollisionShape2D BlockerShape { get; set; } = null!;

    /// <summary>Wall closing the walk band behind the drawn belt (the machinery side). Always solid.</summary>
    [Export] public StaticBody2D? RailFar { get; set; }

    /// <summary>Wall closing the walk band in front of the drawn belt (the cart train). Always solid.</summary>
    [Export] public StaticBody2D? RailNear { get; set; }

    /// <summary>
    /// Px per second the running band sweeps a body back down the drift (towards the lever, the way
    /// the drawn chevrons travel). Must stay well above the hero's own speed, or he walks across a
    /// running belt and the lever stops meaning anything.
    /// </summary>
    [Export] public float CarrySpeed { get; set; } = 460f;

    /// <summary>
    /// Seconds a body rides the running band before it takes hold. Without it the sweep wins from
    /// the first frame of contact and the belt reads as a wall the hero bumps into; with it he walks
    /// properly onto the conveyor first. Long enough to see, short enough that it never adds up to a
    /// crossing: the grace starts again every time a body leaves the belt.
    /// </summary>
    [Export] public float GrabDelay { get; set; } = 0.5f;

    /// <summary>
    /// Depth (Y extent) of <see cref="BlockerShape"/> in px, applied in <c>_Ready</c>. The default
    /// is the mine rooms' walk band (<c>RoomBounds.FloorTop</c> 300 … <c>FloorBottom</c> 600): a
    /// shallower wall would leave a lane along the band's edge and the gate would read as broken.
    /// </summary>
    [Export] public float BlockerDepth { get; set; } = 300f;

    /// <summary>The moving part of the belt: one chevron period tiled across the drawn belt.</summary>
    [Export] public Sprite2D? Belt { get; set; }

    /// <summary>Texture px the belt's chevrons travel per second; positive moves them the way the chevrons point.</summary>
    [Export] public float BeltSpeed { get; set; } = 150f;

    /// <summary>Indicators lit while the belt runs (the switch's green lamp, its green slot, the drive dot).</summary>
    [Export] public CanvasItem? RunIndicators { get; set; }

    /// <summary>Indicators lit once the belt is stopped (the same three in red).</summary>
    [Export] public CanvasItem? StopIndicators { get; set; }

    /// <summary>
    /// Bodies the wall never stops — the guide. His route runs along y 470, in front of the drawn
    /// belt (its near edge is y 462), so he walks past the conveyor where the picture says he can,
    /// and the gate stays what the room is about: the <b>hero</b> cannot cross a running belt.
    /// Without this the level would break rather than gate: the shared script leads him to a point
    /// beyond the belt the moment the timber falls, and <c>CompanionLead</c> answers a body it
    /// cannot walk through by warping him through it.
    /// </summary>
    [Export] public Node2D[] PassThrough { get; set; } = { };

    private bool _running = true;
    private float _scroll;
    private float _period;

    /// <summary>Texture px of one chevron period — the width the scroll wraps at.</summary>
    public float Period => _period;

    /// <inheritdoc/>
    public override void _Ready()
    {
        _period = Belt?.Texture is { } texture ? texture.GetWidth() : 0f;
        foreach (Node2D body in PassThrough)
        {
            if (body is not PhysicsBody2D physics)
            {
                continue;
            }

            RailFar?.AddCollisionExceptionWith(physics);
            RailNear?.AddCollisionExceptionWith(physics);
        }

        ApplyBlockerDepth();
        Apply();
    }

    /// <inheritdoc/>
    public override void _Process(double delta)
    {
        if (!_running || Belt is null || delta <= 0d || _period <= 0f)
        {
            return;
        }
        _scroll = Mathf.PosMod(_scroll + BeltSpeed * (float)delta, _period);
        Rect2 region = Belt.RegionRect;
        region.Position = new Vector2(_scroll, region.Position.Y);
        Belt.RegionRect = region;
    }

    /// <inheritdoc/>
    public override void _PhysicsProcess(double delta)
    {
        if (!_running || CarrySpeed <= 0f || delta <= 0d)
        {
            return;
        }

        _onBeltNow.Clear();
        float step = -CarrySpeed * (float)delta;   // negative: back the way the chevrons travel
        foreach (Node2D body in GetOverlappingBodies())
        {
            if (body is not CharacterBody2D character || IsPassThrough(character))
            {
                continue;
            }

            ulong id = character.GetInstanceId();
            _onBeltNow.Add(id);
            float ridden = (_ridden.TryGetValue(id, out float was) ? was : 0f) + (float)delta;
            _ridden[id] = ridden;
            if (ridden >= GrabDelay)
            {
                character.MoveAndCollide(new Vector2(step, 0f));
            }
        }

        ForgetBodiesOffTheBelt();
    }

    /// <summary>Drops the ride time of everyone no longer on the band, so stepping on again gets the same grace.</summary>
    private void ForgetBodiesOffTheBelt()
    {
        if (_ridden.Count == _onBeltNow.Count)
        {
            return;
        }

        _left.Clear();
        foreach (ulong id in _ridden.Keys)
        {
            if (!_onBeltNow.Contains(id))
            {
                _left.Add(id);
            }
        }

        foreach (ulong id in _left)
        {
            _ridden.Remove(id);
        }
    }

    /// <summary>The guide and anyone else the level exempts stand on a running belt untouched.</summary>
    private bool IsPassThrough(Node2D body)
    {
        foreach (Node2D exempt in PassThrough)
        {
            if (ReferenceEquals(exempt, body))
            {
                return true;
            }
        }

        return false;
    }

    private readonly Dictionary<ulong, float> _ridden = new();   // body -> seconds on the running band
    private readonly HashSet<ulong> _onBeltNow = new();
    private readonly List<ulong> _left = new();

    private void Apply()
    {
        SetProcess(_running);            // a stopped belt has nothing left to move
        SetPhysicsProcess(_running);     // and nothing left to carry
        if (!_running)
        {
            _ridden.Clear();
        }
        BlockerShape.SetDeferred(CollisionShape2D.PropertyName.Disabled, !_running);
        if (RunIndicators is not null)
        {
            RunIndicators.Visible = _running;
        }
        if (StopIndicators is not null)
        {
            StopIndicators.Visible = !_running;
        }
        if (Belt is not null)
        {
            Belt.Visible = true;   // a stopped belt still shows its chevrons, they just stop moving
        }
    }

    /// <summary>
    /// Stretches <see cref="BlockerShape"/> to <see cref="BlockerDepth"/> across the walk band, on
    /// a copy of the shape so a shared resource is never edited. The band is carried over its whole
    /// depth, so a running belt cannot be walked around at the near or the far rail.
    /// </summary>
    private void ApplyBlockerDepth()
    {
        if (BlockerDepth <= 0f
            || BlockerShape.Shape is not RectangleShape2D rectangle
            || Mathf.IsEqualApprox(rectangle.Size.Y, BlockerDepth))
        {
            return;
        }
        var own = (RectangleShape2D)rectangle.Duplicate();
        own.Size = new Vector2(rectangle.Size.X, BlockerDepth);
        BlockerShape.Shape = own;
    }
}
