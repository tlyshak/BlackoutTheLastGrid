using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// A work lamp that never burns steady: at irregular intervals it picks a new target energy
/// somewhere between <see cref="BaseEnergy"/> and <see cref="BaseEnergy"/> × (1 −
/// <see cref="FlickerDepth"/>) and eases towards it. Attached to a <c>PointLight2D</c> placed by
/// a level (the <see cref="LitZone"/> pattern — no scene of its own), so a level can give each
/// lamp its own rhythm through the exports.
/// </summary>
/// <remarks>
/// Purely visual, so it lives in <c>_Process</c> and freezes with the pause menu (process mode
/// inherit) and with a hit-stop (a zero delta is a no-op). One cached
/// <see cref="RandomNumberGenerator"/>, no allocation per frame.
/// </remarks>
public partial class FlickerLight : PointLight2D
{
    /// <summary>Energy the lamp burns at when it is not dipping.</summary>
    [Export] public float BaseEnergy { get; set; } = 1.1f;

    /// <summary>Deepest dip as a fraction of <see cref="BaseEnergy"/>.</summary>
    [Export] public float FlickerDepth { get; set; } = 0.35f;

    /// <summary>Shortest gap between two flicker events, in seconds.</summary>
    [Export] public float MinInterval { get; set; } = 0.07f;

    /// <summary>Longest gap between two flicker events, in seconds.</summary>
    [Export] public float MaxInterval { get; set; } = 0.9f;

    /// <summary>Rate (1/s) at which the energy approaches its target; higher is harsher.</summary>
    [Export] public float Smoothing { get; set; } = 14f;

    /// <summary><c>false</c> leaves a steady lamp burning at <see cref="BaseEnergy"/>.</summary>
    [Export] public bool Active { get; set; } = true;

    private readonly RandomNumberGenerator _rng = new();
    private float _target;
    private float _nextEvent;

    /// <inheritdoc/>
    public override void _Ready()
    {
        _rng.Randomize();
        _target = BaseEnergy;
        Energy = BaseEnergy;
        _nextEvent = _rng.RandfRange(MinInterval, MaxInterval);
    }

    /// <inheritdoc/>
    public override void _ExitTree() => Energy = BaseEnergy;

    /// <inheritdoc/>
    public override void _Process(double delta)
    {
        if (!Active || delta <= 0.0)
        {
            return;
        }

        float dt = (float)delta;
        _nextEvent -= dt;
        if (_nextEvent <= 0f)
        {
            _nextEvent = _rng.RandfRange(MinInterval, MaxInterval);
            _target = BaseEnergy * (1f - _rng.Randf() * FlickerDepth);
        }

        Energy = Mathf.Lerp(Energy, _target, 1f - Mathf.Exp(-Smoothing * dt));
    }
}
