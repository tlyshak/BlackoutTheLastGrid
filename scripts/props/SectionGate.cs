using System;
using System.Collections.Generic;
using BlackoutLastGrid.Enemies;
using BlackoutLastGrid.Ui;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// The section gate (T-V3-04): the classic beat-'em-up rule the author asked for —
/// «як на 2 секції, так і на цій Go (перехід на наступну секцію), тільки якщо всі вороги
/// переможені»: on section 2 and on section 3 alike, the way into the next section stays shut
/// until every enemy of this one is down. It is a wall across the walk band at the right-hand edge
/// of the section; the last knockout takes the wall away and shows the arcade "GO ▶" prompt
/// (<see cref="GoIndicator"/>), which is what tells the player the fight is over and he may move on.
///
/// The gate counts, it does not fight: it knows its section's <see cref="Enemies"/> and listens to
/// each of them. An enemy counts as beaten when it is knocked out
/// (<see cref="Guard.KnockedOutEventHandler"/>), when it is already knocked out at level start
/// (a checkpoint reload that keeps the bodies), or when it leaves the tree at all — a freed enemy
/// can never be beaten again, and a gate that waited for it would lock the player in for good.
/// An empty <see cref="Enemies"/> is a gate that is open from the first frame: a section with
/// nothing to fight must not stop anybody.
/// </summary>
/// <remarks>
/// <para>
/// Scene contract: root <c>StaticBody2D</c> on layer 1 (World) with mask 0 — it stops bodies,
/// it never looks for them — and one <c>CollisionShape2D</c> holding a <c>RectangleShape2D</c>
/// stretched to <see cref="BlockerDepth"/> across the walk band, the same way
/// <see cref="ConveyorLine"/> closes the band. The enemies come from the level through
/// <see cref="Enemies"/>; nothing else is wired.
/// </para>
/// <para>
/// Event-driven, never polled: the gate subscribes once in <c>_Ready</c> and drops every
/// subscription in <c>_ExitTree</c>, so it costs nothing per frame and leaves no handler on a
/// guard that outlives it. <b>A gate that opened stays open.</b> A checkpoint respawn that revives
/// or re-spawns the section's enemies must not shut the way back: the player already earned the
/// crossing, and a gate that closed behind him would read as a bug, not as a rule.
/// </para>
/// <para>
/// Nothing is emitted from <c>_Ready</c>: a gate that starts open has nothing to announce, and a
/// parent's own <c>_Ready</c> runs after its children's, so no listener could hear it anyway.
/// A level that has to know the starting state reads <see cref="IsOpen"/>.
/// </para>
/// </remarks>
public partial class SectionGate : StaticBody2D
{
    /// <summary>Emitted once, when the last enemy of the section goes down. Never emitted again.</summary>
    [Signal]
    public delegate void OpenedEventHandler();

    /// <summary>
    /// The enemies of this section. Empty means the gate is open from the start. Enemies already
    /// knocked out (or already gone) when the gate becomes ready count as beaten.
    /// </summary>
    [Export] public Guard[] Enemies { get; set; } = { };

    /// <summary>The wall across the walk band, disabled once the gate opens.</summary>
    [Export] public CollisionShape2D BlockerShape { get; set; } = null!;

    /// <summary>
    /// Depth (Y extent) of <see cref="BlockerShape"/> in px, applied in <c>_Ready</c>. The default
    /// is the walk band of the mine rooms (<see cref="Levels.RoomBounds.FloorTop"/> 300 …
    /// <see cref="Levels.RoomBounds.FloorBottom"/> 600): a shallower wall would leave a lane along
    /// the near or the far edge of the band and the gate would read as broken.
    /// </summary>
    [Export] public float BlockerDepth { get; set; } = 300f;

    /// <summary>
    /// The "GO ▶" prompt, shown while the gate is open and hidden while it is shut. Optional, and
    /// the coupling is one-way: the gate drives the prompt, the prompt knows nothing about gates.
    /// A <see cref="HUD"/> is driven through <see cref="HUD.GoVisible"/>; any other
    /// <c>CanvasItem</c> / <c>CanvasLayer</c> is simply shown and hidden, so a level may point this
    /// at a sign painted in the room instead.
    /// </summary>
    [Export] public Node? GoIndicator { get; set; }

    private readonly List<EnemyWatch> _watched = new();
    private bool _open;
    private bool _bound;

    /// <summary><c>true</c> once every enemy of the section is down and the band is clear.</summary>
    public bool IsOpen => _open;

    /// <summary>How many of the section's enemies are still standing. 0 means the gate is open.</summary>
    public int RemainingEnemies { get; private set; }

    /// <inheritdoc/>
    public override void _Ready()
    {
        ApplyBlockerDepth();
        Bind();
        _open = RemainingEnemies == 0;
        Apply();
    }

    /// <inheritdoc/>
    public override void _EnterTree()
    {
        // A gate removed from the tree and put back (a level swapping its rooms) lost its
        // subscriptions in _ExitTree; Godot does not run _Ready a second time, so re-bind here.
        if (IsNodeReady() && !_bound && !_open)
        {
            Bind();
        }
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        foreach (EnemyWatch watch in _watched)
        {
            if (!IsInstanceValid(watch.Enemy))
            {
                continue;   // the enemy was freed first; its signals died with it
            }

            watch.Enemy.KnockedOut -= watch.OnDown;
            watch.Enemy.TreeExited -= watch.OnGone;
        }

        _watched.Clear();
        _bound = false;
    }

    /// <summary>
    /// Subscribes to every enemy still standing and counts them. Enemies that are already down,
    /// already freed, or listed twice are skipped, so <see cref="RemainingEnemies"/> is the number
    /// of knockouts the player still owes.
    /// </summary>
    private void Bind()
    {
        RemainingEnemies = 0;
        foreach (Guard? enemy in Enemies)
        {
            if (enemy is null || !IsInstanceValid(enemy) || enemy.IsKnockedOut || IsWatched(enemy))
            {
                continue;
            }

            Guard standing = enemy;
            var watch = new EnemyWatch(standing);
            watch.OnDown = () => OnEnemyBeaten(watch);
            watch.OnGone = () => OnEnemyBeaten(watch);
            standing.KnockedOut += watch.OnDown;
            standing.TreeExited += watch.OnGone;
            _watched.Add(watch);
            RemainingEnemies++;
        }

        _bound = true;
    }

    private bool IsWatched(Guard enemy)
    {
        foreach (EnemyWatch watch in _watched)
        {
            if (ReferenceEquals(watch.Enemy, enemy))
            {
                return true;
            }
        }

        return false;
    }

    /// <summary>
    /// One enemy is down for good — knocked out, or gone from the tree. Fires at most once per
    /// enemy (a knockout followed by the body being freed is still one), and never after the gate
    /// has opened.
    /// </summary>
    private void OnEnemyBeaten(EnemyWatch watch)
    {
        if (_open || watch.Beaten || !IsInsideTree())
        {
            return;   // an enemy leaving the tree during our own teardown is not a victory
        }

        watch.Beaten = true;
        RemainingEnemies = Mathf.Max(0, RemainingEnemies - 1);
        if (RemainingEnemies > 0)
        {
            return;
        }

        _open = true;
        Apply();
        EmitSignalOpened();
    }

    private void Apply()
    {
        // Deferred: the last knockout lands inside a hitbox overlap callback, where the physics
        // server is mid-flush and a collision shape may not be switched in place.
        BlockerShape.SetDeferred(CollisionShape2D.PropertyName.Disabled, _open);
        ApplyGoIndicator();
    }

    private void ApplyGoIndicator()
    {
        switch (GoIndicator)
        {
            case HUD hud:
                hud.GoVisible = _open;
                break;
            case CanvasItem item:
                item.Visible = _open;
                break;
            case CanvasLayer layer:
                layer.Visible = _open;
                break;
        }
    }

    /// <summary>
    /// Stretches <see cref="BlockerShape"/> to <see cref="BlockerDepth"/> across the walk band, on
    /// a copy of the shape so a resource shared by several gates is never edited in place (the
    /// same guard <see cref="ConveyorLine"/> uses for its own blocker).
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

    /// <summary>One watched enemy and the two handlers the gate must take back off it.</summary>
    private sealed class EnemyWatch
    {
        internal EnemyWatch(Guard enemy) => Enemy = enemy;

        /// <summary>The enemy this gate waits for.</summary>
        internal Guard Enemy { get; }

        /// <summary>Handler on <see cref="Guard.KnockedOutEventHandler"/>.</summary>
        internal Guard.KnockedOutEventHandler OnDown { get; set; } = null!;

        /// <summary>Handler on <c>Node.TreeExited</c> — a freed enemy counts as beaten.</summary>
        internal Action OnGone { get; set; } = null!;

        /// <summary><c>true</c> once this enemy has been counted, so it is never counted twice.</summary>
        internal bool Beaten { get; set; }
    }
}
