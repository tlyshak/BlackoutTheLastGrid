using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Props;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// A scripted collapse: the hero crosses the trigger, the roof comes down a moment later
/// (<see cref="Delay"/>, so the rubble lands <b>behind</b> him), the camera shakes and a
/// <see cref="Blockage"/> seals the way back. One-shot and, deliberately, <b>never lethal</b> — a
/// collapse the player cannot avoid must not kill; it cuts the route and hurries him, nothing else.
/// The level decides what the collapse means by listening to
/// <see cref="CollapsedEventHandler"/> (a companion line, a stage advance).
/// </summary>
/// <remarks>
/// <para>
/// Scene contract: root <c>Area2D</c> with <c>collision_layer = 0</c>, <c>collision_mask = 2</c>
/// (Player), <c>monitorable = false</c> and one <c>CollisionShape2D</c> strip across the floor band.
/// The pile it drops is a <see cref="DebrisPile"/> placed where the roof gives way, exported here and
/// authored with <c>StartsCleared = true</c> (and normally <c>HeavyHitsToClear = 0</c>, so the way
/// back stays shut).
/// </para>
/// <para>
/// <b>Placement rule — the trigger's margin.</b> The trigger must sit far enough past
/// <see cref="Blockage"/> that a hero who turns round the instant the roof starts to go still ends
/// up on the open side of the rubble. Nothing freezes him during <see cref="Delay"/>, so the margin
/// has to cover the trigger's own half-width (24 px), the hero's (14 px), the pile's blocker
/// half-width (28 px) and the distance he can walk back, <c>Player.MoveSpeed × Delay</c> (220 × 0.35
/// ≈ 77 px at the defaults). The prologue's three falls use <b>220 px</b>, which leaves ~63 px of
/// clearance in the worst case. A short margin does not read as a bug in the editor and it seals the
/// run with no way out but the main menu, so it is checked by <c>tests/smoke/level_seals.gd</c>.
/// </para>
/// </remarks>
public partial class CaveIn : Area2D
{
    /// <summary>Emitted when the hero crosses the trigger and the delay starts.</summary>
    [Signal]
    public delegate void TriggeredEventHandler();

    /// <summary>Emitted when the rubble is solid and the way back is shut.</summary>
    [Signal]
    public delegate void CollapsedEventHandler();

    /// <summary>
    /// The level that owns the camera — the only path to the shake. Optional: a collapse in a
    /// fixture without a camera still seals the drift, it just does not shake.
    /// </summary>
    [Export] public LevelBase? Level { get; set; }

    /// <summary>The pile that appears; author it with <c>StartsCleared = true</c> so it is invisible until now.</summary>
    [Export] public DebrisPile? Blockage { get; set; }

    /// <summary>Seconds between the trigger and the collapse, so the rubble lands behind the hero.</summary>
    [Export] public float Delay { get; set; } = 0.35f;

    /// <summary>Peak camera offset of the collapse, in px.</summary>
    [Export] public float ShakeAmplitude { get; set; } = 12f;

    /// <summary>Seconds the collapse shake decays over.</summary>
    [Export] public float ShakeSeconds { get; set; } = 0.7f;

    /// <summary>Dust burst fired one-shot when the roof gives way.</summary>
    [Export] public GpuParticles2D? Dust { get; set; }

    /// <summary>Optional group of nodes shown while the drift comes down (falling rock, a rumble light).</summary>
    [Export] public Node2D? Rumble { get; set; }

    private SceneTreeTimer? _timer;

    /// <summary><c>true</c> once the hero has crossed the trigger.</summary>
    public bool IsTriggered { get; private set; }

    /// <summary><c>true</c> once the rubble is down.</summary>
    public bool HasCollapsed { get; private set; }

    /// <inheritdoc/>
    public override void _Ready() => BodyEntered += OnBodyEntered;

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        BodyEntered -= OnBodyEntered;
        if (_timer is not null)
        {
            // A C# subscription to a SceneTreeTimer that goes out of scope never fires, so the
            // handle is kept in a field and dropped here.
            _timer.Timeout -= OnDelayElapsed;
            _timer = null;
        }
    }

    /// <summary>
    /// Brings the drift down now, whatever the trigger did: the rubble becomes solid, the dust
    /// bursts, the camera shakes and <see cref="CollapsedEventHandler"/> is emitted. Idempotent, so a
    /// level may script a collapse without a trigger.
    /// </summary>
    public void Collapse()
    {
        if (HasCollapsed)
        {
            return;
        }

        HasCollapsed = true;
        IsTriggered = true;
        Blockage?.SetBlocked(true);
        Dust?.Restart();
        if (Rumble is not null)
        {
            Rumble.Visible = true;
        }

        Level?.ShakeCamera(ShakeAmplitude, ShakeSeconds);
        EmitSignalCollapsed();
    }

    private void OnBodyEntered(Node2D body)
    {
        if (IsTriggered || body is not Player)
        {
            return;
        }

        IsTriggered = true;
        SetDeferred(Area2D.PropertyName.Monitoring, false);
        EmitSignalTriggered();

        if (Delay <= 0f)
        {
            Collapse();
            return;
        }

        // processAlways: false so the mine never comes down behind an open pause menu;
        // ignoreTimeScale: true so a hit-stop does not stretch the delay (the LevelBase precedent).
        _timer = GetTree().CreateTimer(Delay, processAlways: false, processInPhysics: false, ignoreTimeScale: true);
        _timer.Timeout += OnDelayElapsed;
    }

    private void OnDelayElapsed()
    {
        _timer = null;
        if (!IsInstanceValid(this) || !IsInsideTree())
        {
            return;   // the level was freed before the delay ran out (test teardown, scene change)
        }

        Collapse();
    }
}
