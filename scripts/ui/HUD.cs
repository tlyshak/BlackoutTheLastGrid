using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Ui;

/// <summary>
/// On-screen energy bar bound to <see cref="GameState.Energy"/>. Event-driven: the bar and its
/// label are updated from <see cref="GameState.EnergyChangedEventHandler"/>, never per frame.
/// Instantiated by the level (or by <c>Main</c> once levels are loaded through it).
/// </summary>
public partial class HUD : CanvasLayer
{
    /// <summary>Bar showing the current energy between the state's min and max.</summary>
    [Export] public ProgressBar EnergyBar { get; set; } = null!;

    /// <summary>Optional numeric label next to the bar.</summary>
    [Export] public Label? EnergyLabel { get; set; }

    /// <summary>Format of <see cref="EnergyLabel"/>; {0} is the energy rounded to a whole unit (an <c>int</c>).</summary>
    [Export] public string LabelFormat { get; set; } = "ЕНЕРГІЯ {0}";

    private GameState? _state;
    private int _shownRounded = int.MinValue;

    /// <summary>The value currently displayed by the bar.</summary>
    public float DisplayedEnergy => (float)EnergyBar.Value;

    /// <inheritdoc/>
    public override void _Ready() => Bind(GameState.Instance);

    /// <inheritdoc/>
    public override void _EnterTree()
    {
        // A HUD removed and re-added by its owner (Main swapping levels) must follow the state again.
        if (IsNodeReady() && _state is null)
        {
            Bind(GameState.Instance);
        }
    }

    /// <inheritdoc/>
    public override void _ExitTree() => Unbind();

    /// <summary>Binds the bar to <paramref name="state"/> (replacing any previous binding) and shows its current energy.</summary>
    /// <param name="state">The game state to follow.</param>
    public void Bind(GameState state)
    {
        Unbind();
        _state = state;
        EnergyBar.MinValue = state.MinEnergy;
        EnergyBar.MaxValue = state.MaxEnergy;
        state.EnergyChanged += OnEnergyChanged;
        OnEnergyChanged(state.Energy);
    }

    /// <summary>Stops following the bound state.</summary>
    public void Unbind()
    {
        if (_state is null)
        {
            return;
        }

        _state.EnergyChanged -= OnEnergyChanged;
        _state = null;
    }

    private void OnEnergyChanged(float energy)
    {
        EnergyBar.Value = energy;

        if (EnergyLabel is null)
        {
            return;
        }

        int rounded = Mathf.RoundToInt(energy);
        if (rounded == _shownRounded)
        {
            return;   // the label only changes on whole units; no string per physics tick
        }

        _shownRounded = rounded;
        EnergyLabel.Text = string.Format(LabelFormat, rounded);   // one rounding rule for throttle and text
    }
}
