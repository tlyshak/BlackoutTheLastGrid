using Godot;

namespace BlackoutLastGrid.Core;

/// <summary>
/// Global hit-stop, registered as the <c>HitStop</c> autoload in <c>project.godot</c>: freezes the
/// game for a few physics frames via <c>Engine.TimeScale = 0</c> and restores it from its own
/// <c>_Process</c> using the wall clock (<see cref="Node.ProcessModeEnum.Always"/>), so the
/// restore never depends on the attacker, the target or the current level still being alive.
/// Overlapping requests extend the freeze to the latest end instead of restoring early.
/// </summary>
public partial class HitStop : Node
{
    private const double NormalTimeScale = 1.0;

    /// <summary>The autoload instance, assigned when it enters the tree.</summary>
    public static HitStop Instance { get; private set; } = null!;

    private ulong _restoreAtMsec;
    private bool _active;

    /// <summary><c>true</c> while a hit-stop freeze is in effect.</summary>
    public static bool IsActive => Instance is not null && Instance._active;

    /// <inheritdoc/>
    public override void _EnterTree()
    {
        Instance = this;
        ProcessMode = ProcessModeEnum.Always;
        SetProcess(false);
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        if (ReferenceEquals(Instance, this))
        {
            Cancel();
            Instance = null!;
        }
    }

    /// <summary>Freezes the game for <paramref name="frames"/> physics frames.</summary>
    /// <param name="frames">Length in physics frames; 0 or less does nothing.</param>
    public static void Trigger(int frames)
    {
        if (frames <= 0)
        {
            return;
        }

        if (Instance is null)
        {
            GD.PushError("HitStop autoload is not registered in project.godot; hit-stop skipped.");
            return;
        }

        Instance.Freeze(frames);
    }

    /// <summary>Restores the normal time scale immediately (scene change, game over, KO restart).</summary>
    public static void Cancel()
    {
        if (Instance is not null)
        {
            Instance._restoreAtMsec = 0;
            Instance._active = false;
            Instance.SetProcess(false);
        }

        Engine.TimeScale = NormalTimeScale;
    }

    /// <inheritdoc/>
    public override void _Process(double delta)
    {
        if (Time.GetTicksMsec() < _restoreAtMsec)
        {
            return;
        }

        _active = false;
        Engine.TimeScale = NormalTimeScale;
        SetProcess(false);
    }

    private void Freeze(int frames)
    {
        double seconds = frames / (double)Engine.PhysicsTicksPerSecond;
        ulong endsAt = Time.GetTicksMsec() + (ulong)(seconds * 1000.0);
        if (endsAt > _restoreAtMsec)
        {
            _restoreAtMsec = endsAt;
        }

        _active = true;
        Engine.TimeScale = 0.0;
        SetProcess(true);
    }
}
