using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// Wall outlet that refills <see cref="GameState.Energy"/> by <see cref="Amount"/> on
/// <c>interact</c>. Limited by <see cref="Uses"/> and, between uses, by <see cref="Cooldown"/>;
/// the prompt counts the cooldown down and the <c>PH_Indicator</c> turns grey while the outlet
/// cannot be used. The interaction is instantaneous: <see cref="Begin"/> finishes in the same call.
/// </summary>
public partial class Outlet : Interactable
{
    /// <summary>Emitted after energy was added, with the amount.</summary>
    [Signal]
    public delegate void ChargedEventHandler(float amount);

    /// <summary>Energy added per use.</summary>
    [Export] public float Amount { get; set; } = 25f;

    /// <summary>Seconds before the outlet can be used again; 0 = no cooldown.</summary>
    [Export] public float Cooldown { get; set; } = 8f;

    /// <summary>Number of uses before the outlet is spent; −1 = unlimited.</summary>
    [Export] public int Uses { get; set; } = 1;

    /// <summary>Prompt shown while spent or cooling down without a countdown.</summary>
    [Export] public string SpentPromptText { get; set; } = "Розряджена";

    /// <summary>Prompt shown during the cooldown; {0} is the whole seconds left.</summary>
    [Export] public string CooldownPromptFormat { get; set; } = "Розряджена ({0} с)";

    /// <summary>Colour of <see cref="Indicator"/> while the outlet is ready.</summary>
    [Export] public Color ReadyColor { get; set; } = new(0.2f, 1f, 0.3f);

    /// <summary>Colour of <see cref="Indicator"/> while cooling down or spent.</summary>
    [Export] public Color SpentColor { get; set; } = new(0.4f, 0.42f, 0.45f);

    /// <summary>Placeholder status light, recoloured with <see cref="ReadyColor"/>/<see cref="SpentColor"/>.</summary>
    [Export] public Polygon2D? Indicator { get; set; }

    private int _usesLeft;
    private float _cooldownLeft;
    private int _shownSeconds;

    /// <summary><c>true</c> once every use is consumed (never with unlimited uses).</summary>
    public bool IsSpent => Uses >= 0 && _usesLeft <= 0;

    /// <summary><c>true</c> while the cooldown after the last use is running.</summary>
    public bool IsCoolingDown => _cooldownLeft > 0f;

    /// <inheritdoc/>
    public override bool CanInteract => !IsSpent && !IsCoolingDown;

    /// <inheritdoc/>
    public override string CurrentPrompt =>
        IsSpent ? SpentPromptText
        : IsCoolingDown ? string.Format(CooldownPromptFormat, _shownSeconds)
        : PromptText;

    /// <inheritdoc/>
    public override void _Ready()
    {
        _usesLeft = Uses;
        SetProcess(false);
        UpdateIndicator();
    }

    /// <inheritdoc/>
    public override void _Process(double delta)
    {
        _cooldownLeft -= (float)delta;
        if (_cooldownLeft <= 0f)
        {
            _cooldownLeft = 0f;
            SetProcess(false);
            UpdateIndicator();
            NotifyPromptChanged();
            return;
        }

        int seconds = Mathf.CeilToInt(_cooldownLeft);
        if (seconds != _shownSeconds)
        {
            _shownSeconds = seconds;
            NotifyPromptChanged();
        }
    }

    /// <inheritdoc/>
    public override void Begin(Player player)
    {
        Activate();
        if (!CanInteract)
        {
            Finish(false);
            return;
        }

        GameState.Instance.AddEnergy(Amount);
        if (Uses > 0)
        {
            _usesLeft--;
        }

        EmitSignalCharged(Amount);
        if (!IsSpent && Cooldown > 0f)
        {
            StartCooldown();
        }

        Finish(true);
        UpdateIndicator();
        NotifyPromptChanged();   // after Finish so the level formats the post-use prompt as a normal prompt
    }

    private void StartCooldown()
    {
        _cooldownLeft = Cooldown;
        _shownSeconds = Mathf.CeilToInt(Cooldown);
        SetProcess(true);
    }

    private void UpdateIndicator()
    {
        if (Indicator is not null)
        {
            Indicator.Color = CanInteract ? ReadyColor : SpentColor;
        }
    }
}
