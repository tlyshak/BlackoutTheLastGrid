using Godot;

namespace BlackoutLastGrid.Core;

/// <summary>
/// Global hit-stop: freezes the game for a few physics frames via <c>Engine.TimeScale = 0</c>.
/// The restore is driven by this node's own <c>_Process</c> using the wall clock, and the node
/// lives directly under the scene-tree root with <see cref="Node.ProcessModeEnum.Always"/>, so it
/// never depends on the attacker, the target or the current level still being alive.
/// Overlapping requests extend the freeze to the latest end instead of restoring early.
/// </summary>
public partial class HitStop : Node
{
    private const double NormalTimeScale = 1.0;

    private static HitStop? _instance;
    private ulong _restoreAtMsec;

    /// <summary><c>true</c> while a hit-stop freeze is in effect.</summary>
    public static bool IsActive => Engine.TimeScale == 0.0;

    /// <summary>Freezes the game for <paramref name="frames"/> physics frames.</summary>
    /// <param name="tree">The scene tree whose root hosts the restore node.</param>
    /// <param name="frames">Length in physics frames; 0 or less does nothing.</param>
    public static void Trigger(SceneTree tree, int frames)
    {
        if (frames <= 0)
        {
            return;
        }

        HitStop node = GetOrCreate(tree);
        double seconds = frames / (double)Engine.PhysicsTicksPerSecond;
        ulong endsAt = Time.GetTicksMsec() + (ulong)(seconds * 1000.0);
        if (endsAt > node._restoreAtMsec)
        {
            node._restoreAtMsec = endsAt;
        }

        Engine.TimeScale = 0.0;
        node.SetProcess(true);
    }

    /// <summary>Restores the normal time scale immediately (scene change, game over).</summary>
    public static void Cancel()
    {
        if (_instance is not null && IsInstanceValid(_instance))
        {
            _instance._restoreAtMsec = 0;
            _instance.SetProcess(false);
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

        Engine.TimeScale = NormalTimeScale;
        SetProcess(false);
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        if (ReferenceEquals(_instance, this))
        {
            _instance = null;
            Engine.TimeScale = NormalTimeScale;
        }
    }

    private static HitStop GetOrCreate(SceneTree tree)
    {
        if (_instance is not null && IsInstanceValid(_instance))
        {
            return _instance;
        }

        HitStop node = new()
        {
            Name = "HitStop",
            ProcessMode = ProcessModeEnum.Always,
        };
        node.SetProcess(false);
        tree.Root.AddChild(node);
        _instance = node;
        return node;
    }
}
