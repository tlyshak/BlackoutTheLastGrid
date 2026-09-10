using System.Collections.Generic;
using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// A mine machine driven from its own panel: the extractor that blows a gas pocket out, the pump
/// that empties a flooded drift (GAME_DESIGN §3). Switching it on asks the level's
/// <see cref="PowerCircuit"/> for power; if the bus is busy the panel does **not** switch on and
/// says which machine has to be switched off first, so the scarcity is a choice the player makes.
/// A running machine clears everything in <see cref="ClearTargets"/> **for good** — cutting the
/// power later leaves the way open, because nothing in this level is ever solved twice.
/// </summary>
/// <remarks>
/// Scene contract: the <see cref="Interactable"/> contract (root <c>Area2D</c>, layer 32
/// Interactable, mask 0) plus <see cref="Circuit"/> and <see cref="ClearTargets"/> wired by the
/// level, one instance of <c>PoweredMachine.tscn</c> per machine. The panel ships with an empty
/// <see cref="PowerPanel.Sequence"/> and <see cref="PowerPanel.CanPowerDown"/> on, so both
/// switching on and switching off are a single <c>interact</c>.
/// </remarks>
public partial class PoweredMachine : PowerPanel
{
    /// <summary>Emitted after the circuit granted or released this machine's power.</summary>
    [Signal]
    public delegate void PowerChangedEventHandler(bool powered);

    /// <summary>The bus this machine draws from; wired by the level. Without it the machine can never run.</summary>
    [Export] public PowerCircuit? Circuit { get; set; }

    /// <summary>Name other panels print when they refuse because this machine is running.</summary>
    [Export] public string DisplayName { get; set; } = "Machine";

    /// <summary>Power units drawn from <see cref="Circuit"/> while running.</summary>
    [Export] public int PowerCost { get; set; } = 1;

    /// <summary><c>true</c> for a machine that needs the whole bus (the hoist) instead of <see cref="PowerCost"/> units.</summary>
    [Export] public bool RequiresWholeCircuit { get; set; }

    /// <summary>Obstacles removed permanently when this machine starts; each entry must implement <see cref="IClearable"/>.</summary>
    [Export] public Node2D[] ClearTargets { get; set; } = { };

    /// <summary>Prompt shown after a refusal; <c>{0}</c> is the blocking machine's <see cref="DisplayName"/>.</summary>
    [Export] public string OverloadPromptFormat { get; set; } = "Not enough power: {0} is running";

    /// <summary>Seconds the refusal prompt stays in the HUD before the idle prompt returns.</summary>
    [Export] public float OverloadPromptSeconds { get; set; } = 3f;

    /// <summary>Lamp switched on while the machine runs.</summary>
    [Export] public PointLight2D? RunLight { get; set; }

    /// <summary>Optional effect group (steam, dust) shown and emitting while the machine runs.</summary>
    [Export] public Node2D? RunFx { get; set; }

    private readonly List<IClearable> _targets = new();
    private string _overloadText = string.Empty;
    private float _overloadTime;

    /// <summary><c>true</c> while the circuit feeds this machine.</summary>
    public bool IsPowered { get; private set; }

    /// <inheritdoc/>
    public override string CurrentPrompt => _overloadTime > 0f ? _overloadText : base.CurrentPrompt;

    /// <inheritdoc/>
    public override void _Ready()
    {
        base._Ready();
        ResolveTargets();
        SetProcess(false);
        Activated += OnActivated;
        Deactivated += OnDeactivated;
        if (Circuit is null)
        {
            GD.PushWarning($"{Name}: Circuit is not wired; the machine can never be switched on.");
            return;
        }

        Circuit.Register(this);
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        Activated -= OnActivated;
        Deactivated -= OnDeactivated;
        Circuit?.Unregister(this);
        base._ExitTree();
    }

    /// <summary>Counts down the refusal prompt; idle processing is off the rest of the time.</summary>
    /// <param name="delta">Idle frame time in seconds.</param>
    public override void _Process(double delta)
    {
        _overloadTime -= (float)delta;
        if (_overloadTime > 0f)
        {
            return;
        }

        _overloadTime = 0f;
        SetProcess(false);
        NotifyPromptChanged();
    }

    /// <summary>
    /// Asks <see cref="Circuit"/> before the panel commits, so the player never sees the screen turn
    /// green on a machine that cannot run. A refusal flashes the panel, shows the blocking machine's
    /// name and leaves the panel usable for a retry.
    /// </summary>
    protected override void Complete()
    {
        if (!Powered)
        {
            base.Complete();
            return;
        }

        PoweredMachine? blocking = null;
        if (Circuit is null || !Circuit.TryPower(this, out blocking))
        {
            if (blocking is not null)
            {
                ShowOverload(blocking);
            }

            RefuseActivation();
            return;
        }

        base.Complete();
    }

    private void OnActivated() => SetPowered(true);

    private void OnDeactivated()
    {
        Circuit?.Release(this);
        SetPowered(false);
    }

    private void SetPowered(bool powered)
    {
        IsPowered = powered;
        if (RunLight is not null)
        {
            RunLight.Enabled = powered;
        }

        if (RunFx is not null)
        {
            RunFx.Visible = powered;
            if (RunFx is GpuParticles2D particles)
            {
                particles.Emitting = powered;
            }
        }

        if (powered)
        {
            HideOverload();
            foreach (IClearable target in _targets)
            {
                target.Clear();
            }
        }

        EmitSignalPowerChanged(powered);
    }

    private void ShowOverload(PoweredMachine blocking)
    {
        _overloadText = string.Format(OverloadPromptFormat, blocking.DisplayName);
        _overloadTime = OverloadPromptSeconds;
        SetProcess(_overloadTime > 0f);
    }

    private void HideOverload()
    {
        _overloadTime = 0f;
        SetProcess(false);
    }

    private void ResolveTargets()
    {
        _targets.Clear();
        foreach (Node2D? target in ClearTargets)
        {
            if (target is IClearable clearable)
            {
                _targets.Add(clearable);
            }
            else if (target is not null)
            {
                GD.PushWarning($"{Name}: ClearTargets entry '{target.Name}' does not implement IClearable and is ignored.");
            }
        }
    }
}
