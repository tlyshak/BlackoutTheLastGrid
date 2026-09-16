using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Ui;

/// <summary>
/// On-screen energy bar bound to <see cref="GameState.Energy"/> and an interaction prompt at the
/// bottom centre. Event-driven: the bar and its label are updated from
/// <see cref="GameState.EnergyChangedEventHandler"/>, never per frame; the prompt is set by the
/// level through <see cref="ShowPrompt"/>/<see cref="HidePrompt"/>, and the arcade "GO ▶" prompt
/// at the right edge by whoever cleared the section through <see cref="GoVisible"/>. Instantiated
/// by the level (or by <c>Main</c> once levels are loaded through it).
/// </summary>
/// <remarks>
/// The only thing here that costs a frame is the GO blink, and <c>_Process</c> is switched off
/// whenever the prompt is hidden — which is every second of the game outside a cleared section.
/// </remarks>
public partial class HUD : CanvasLayer
{
    /// <summary>Bar showing the current energy between the state's min and max.</summary>
    [Export] public ProgressBar EnergyBar { get; set; } = null!;

    /// <summary>Optional numeric label next to the bar.</summary>
    [Export] public Label? EnergyLabel { get; set; }

    /// <summary>Format of <see cref="EnergyLabel"/>; {0} is the energy rounded to a whole unit (an <c>int</c>).</summary>
    [Export] public string LabelFormat { get; set; } = "ENERGY {0}";

    /// <summary>Interaction prompt at the bottom centre; hidden until <see cref="ShowPrompt"/>.</summary>
    [Export] public Label? Prompt { get; set; }

    /// <summary>
    /// The arcade "GO ▶" prompt at the right edge — the word and the arrow under one
    /// <c>Control</c>, so the blink fades both together. Hidden until <see cref="ShowGo"/>. Shown
    /// by <see cref="Props.SectionGate"/> when the section's last enemy goes down: the author asked
    /// for the classic rule — «як на 2 секції, так і на цій Go (перехід на наступну секцію),
    /// тільки якщо всі вороги переможені» — and this is the half of it the player actually sees.
    /// </summary>
    [Export] public Control? Go { get; set; }

    /// <summary>Length of one on-off cycle of the GO blink, in seconds. Short: it has to read as an arcade prompt, not as a warning lamp.</summary>
    [Export] public float GoBlinkPeriod { get; set; } = 0.7f;

    /// <summary>Share of the cycle the GO prompt is at full alpha.</summary>
    [Export(PropertyHint.Range, "0,1")] public float GoBlinkOnFraction { get; set; } = 0.6f;

    /// <summary>Alpha of the GO prompt while it is off — it dims, it does not disappear.</summary>
    [Export(PropertyHint.Range, "0,1")] public float GoBlinkOffAlpha { get; set; } = 0.2f;

    private GameState? _state;
    private int _shownRounded = int.MinValue;
    private bool _goVisible;
    private float _goTime;

    /// <summary>The value currently displayed by the bar.</summary>
    public float DisplayedEnergy => (float)EnergyBar.Value;

    /// <summary>Text of the prompt while it is visible, else an empty string.</summary>
    public string PromptText => Prompt is { Visible: true } ? Prompt.Text : string.Empty;

    /// <summary>
    /// <c>true</c> while the "GO ▶" prompt is on screen and blinking. Setting it is the whole
    /// public API a level (or a <see cref="Props.SectionGate"/>) needs; <see cref="ShowGo"/> and
    /// <see cref="HideGo"/> are the same thing spelled out for GDScript and for signal
    /// connections, which cannot assign a property.
    /// </summary>
    public bool GoVisible
    {
        get => _goVisible;
        set
        {
            if (_goVisible == value)
            {
                return;
            }

            _goVisible = value;
            ApplyGo();
        }
    }

    /// <inheritdoc/>
    public override void _Ready()
    {
        ApplyGo();   // hidden, and _Process switched off with it
        Bind(GameState.Instance);
    }

    /// <inheritdoc/>
    public override void _Process(double delta)
    {
        if (Go is null)
        {
            return;
        }

        // Wrapped to one period: the prompt can stay up for a whole level, and an ever-growing
        // float would slowly lose the beat.
        _goTime = GoBlinkPeriod > 0f ? Mathf.PosMod(_goTime + (float)delta, GoBlinkPeriod) : 0f;
        Go.Modulate = WithAlpha(Go.Modulate, GoAlpha(_goTime));
    }

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

    /// <summary>Shows the "GO ▶" prompt, starting the blink on a lit frame.</summary>
    public void ShowGo() => GoVisible = true;

    /// <summary>Hides the "GO ▶" prompt and stops its blink.</summary>
    public void HideGo() => GoVisible = false;

    /// <summary>
    /// Alpha of the blinking GO prompt <paramref name="time"/> seconds after it appeared. Pure, so
    /// the schedule can be checked without watching frames go by.
    /// </summary>
    /// <param name="time">Seconds since the prompt was shown.</param>
    public float GoAlpha(float time)
    {
        if (GoBlinkPeriod <= 0f)
        {
            return 1f;
        }

        float phase = Mathf.PosMod(time, GoBlinkPeriod) / GoBlinkPeriod;
        return phase < GoBlinkOnFraction ? 1f : GoBlinkOffAlpha;
    }

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

    /// <summary>Shows the interaction prompt with <paramref name="text"/>.</summary>
    /// <param name="text">Prompt text, e.g. "E: Charge".</param>
    public void ShowPrompt(string text)
    {
        if (Prompt is null)
        {
            return;
        }

        Prompt.Text = text;
        Prompt.Visible = true;
    }

    /// <summary>Hides the interaction prompt.</summary>
    public void HidePrompt()
    {
        if (Prompt is not null)
        {
            Prompt.Visible = false;
        }
    }

    /// <summary>
    /// Applies the GO prompt's visibility and restarts its blink. <c>_Process</c> runs only while
    /// the prompt is on screen, so a HUD without one — every second of the game outside a cleared
    /// section — costs nothing per frame.
    /// </summary>
    private void ApplyGo()
    {
        _goTime = 0f;   // every showing starts lit, so the prompt never appears mid-blink
        SetProcess(_goVisible && Go is not null);
        if (Go is null)
        {
            return;
        }

        Go.Visible = _goVisible;
        Go.Modulate = WithAlpha(Go.Modulate, 1f);
    }

    private static Color WithAlpha(Color color, float alpha) => new(color.R, color.G, color.B, alpha);

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
