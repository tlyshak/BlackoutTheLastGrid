using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// The belt line of the ventilation room (T-V2-06, the author's r2 concept of section 2): while it
/// runs nobody walks across it, and the chevrons of its drawn belt keep moving. The line is a wall
/// as wide as the drawn conveyor and as deep as the walk band, so a running belt is a gate and not
/// a lane the hero can slip around; stopping it disables the wall for good in that run. Bodies in
/// <see cref="PassThrough"/> (the guide) are never stopped by it.
/// <see cref="ConveyorSwitch"/> is what stops it.
/// </summary>
/// <remarks>
/// <para>
/// Scene contract: root <c>StaticBody2D</c> on layer 1 (World) with mask 0, the blocking
/// <see cref="BlockerShape"/> (a <c>RectangleShape2D</c> stretched to <see cref="BlockerDepth"/>
/// across the band), the <see cref="Belt"/> sprite that tiles the
/// one-period chevron crop of the mockup, and the two indicator sprites. The sprites are placed by
/// the owning level on the very pixels the painted room draws them at — the smoke test recomputes
/// those from the mockup coordinates and fails on a drift.
/// </para>
/// <para>
/// The scroll lives in <c>_Process</c>: it freezes with the pause menu (process mode inherit) and
/// slows with a hit-stop (the delta is scaled). Nothing here polls the hero or looks outside the
/// scene; the level wires the switch to the line with an <c>[Export]</c>.
/// </para>
/// </remarks>
public partial class ConveyorLine : StaticBody2D
{
    /// <summary>Emitted whenever <see cref="Running"/> changes.</summary>
    [Signal]
    public delegate void RunningChangedEventHandler(bool running);

    /// <summary>
    /// <c>true</c> while the belt runs: the wall blocks the band, the chevrons move, the green
    /// indicators show. Set by <see cref="ConveyorSwitch"/>.
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

    /// <summary>The wall that stops the hero while the belt runs; disabled once it is stopped.</summary>
    [Export] public CollisionShape2D BlockerShape { get; set; } = null!;

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
            if (body is PhysicsBody2D physics)
            {
                AddCollisionExceptionWith(physics);
            }
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

    private void Apply()
    {
        SetProcess(_running);   // a stopped belt has nothing left to move
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
    /// a copy of the shape so a shared resource is never edited.
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
