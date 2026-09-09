using Godot;

namespace BlackoutLastGrid.Core;

/// <summary>
/// Which route the player chose for Level 2 (see GAME_DESIGN.md).
/// </summary>
public enum RouteType
{
    /// <summary>No route chosen yet.</summary>
    None = 0,
    /// <summary>Route through the car tunnel.</summary>
    Car = 1,
    /// <summary>Route through the metro.</summary>
    Metro = 2,
}

/// <summary>
/// Autoload singleton holding the global run state: flashlight energy, Level 2 route,
/// collected journals and district reputation. Registered in project.godot as "GameState".
/// This is the only place where cross-scene state lives; nodes talk to it via
/// <see cref="Instance"/> and react to changes through signals.
/// </summary>
public partial class GameState : Node
{
    /// <summary>Default upper bound of the energy reserve; also the pre-<see cref="_Ready"/> value of <see cref="Energy"/>.</summary>
    private const float DefaultMaxEnergy = 100f;

    /// <summary>Globally accessible instance, assigned when the autoload enters the tree.</summary>
    public static GameState Instance { get; private set; } = null!;

    /// <summary>Emitted whenever <see cref="Energy"/> actually changes (after clamping).</summary>
    [Signal]
    public delegate void EnergyChangedEventHandler(float energy);

    /// <summary>
    /// Upper bound of the energy reserve. The autoload is a script without a scene, so these
    /// exports are not editable in the inspector; change them in the Remote tree at runtime or
    /// give the autoload a scene later.
    /// </summary>
    [Export]
    public float MaxEnergy { get; set; } = DefaultMaxEnergy;

    /// <summary>Lower bound of the energy reserve (see <see cref="MaxEnergy"/> about editing).</summary>
    [Export]
    public float MinEnergy { get; set; } = 0f;

    /// <summary>Backing field for <see cref="Energy"/>; <see cref="_Ready"/> sets it to <see cref="MaxEnergy"/>.</summary>
    private float _energy = DefaultMaxEnergy;

    /// <summary>
    /// Current flashlight/energy reserve. Setting it clamps to [<see cref="MinEnergy"/>, <see cref="MaxEnergy"/>].
    /// The clamped value is always stored (tiny drains accumulate); <see cref="EnergyChangedEventHandler"/>
    /// is emitted only when the stored value differs from the previous one.
    /// </summary>
    public float Energy
    {
        get => _energy;
        set
        {
            float clamped = Mathf.Clamp(value, MinEnergy, MaxEnergy);
            bool changed = clamped != _energy;
            _energy = clamped;
            if (changed)
            {
                EmitSignalEnergyChanged(_energy);
            }
        }
    }

    /// <summary>Route chosen for Level 2.</summary>
    public RouteType Route { get; set; } = RouteType.None;

    /// <summary>Number of journal pages collected across the run.</summary>
    public int JournalsFound { get; set; }

    /// <summary>Reputation with the district inhabitants; affects dialogue and endings.</summary>
    public int DistrictReputation { get; set; }

    /// <summary>
    /// Registers the singleton and keeps processing while the tree is paused; <see cref="_Ready"/>
    /// starts a run with a full reserve (<see cref="MaxEnergy"/>), save/load (T-09) overwrites it.
    /// </summary>
    public override void _EnterTree()
    {
        Instance = this;
        ProcessMode = ProcessModeEnum.Always;
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        if (ReferenceEquals(Instance, this))
        {
            Instance = null!;
        }
    }

    /// <inheritdoc/>
    public override void _Ready() => _energy = MaxEnergy;

    /// <summary>Adds (or subtracts, for negative values) energy, respecting the clamp and signal rules.</summary>
    /// <param name="amount">Delta to apply; negative values drain energy.</param>
    public void AddEnergy(float amount) => Energy = _energy + amount;

    /// <summary>
    /// Resets per-run state: full energy and no route. <see cref="JournalsFound"/> and
    /// <see cref="DistrictReputation"/> are intentionally kept — save/load persistence arrives in T-09.
    /// </summary>
    public void ResetRun()
    {
        Energy = MaxEnergy;
        Route = RouteType.None;
    }
}
