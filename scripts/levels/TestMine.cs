using System.Collections.Generic;
using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Core;
using BlackoutLastGrid.Props;
using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Fixture room for the escape mechanics of the prologue (T-07s-a): one floor band that carries a
/// <see cref="PowerCircuit"/> with three machines (pump → flooded drift, extractor → gas pocket,
/// hoist → the way out), a debris pile for the heavy-attack lesson, a rehearsal gas pocket with a
/// long warning window next to a normal one, a scripted cave-in, two checkpoints and the brother
/// following the hero — or, with <see cref="DanLeads"/> ticked, guiding him along the three
/// markers of <see cref="DanRoute"/> (T-07s-e). Nothing here is a level: it changes no scenes and
/// tells no story, it only lets every mechanic be touched on its own (F6) and gives the smoke
/// scripts one place to drive them from. All of it is <c>PH_</c> placeholder art in the palette
/// of <see cref="Art.Palette"/>; every visible string is English.
/// </summary>
/// <remarks>
/// Deliberate differences from the prologue: an <c>Outlet</c> next to the start so a run can never
/// brick itself on energy, and the cave-in's pile is breakable by hand
/// (<see cref="DebrisPile.HeavyHitsToClear"/> 2 instead of 0) so sealing the drift cannot lock the
/// author away from the machines he still wants to try. Everything else — capacities, warning
/// windows, hit counts — is the shipping value.
/// </remarks>
public partial class TestMine : LevelBase
{
    /// <summary>The single room; its bounds are applied on ready.</summary>
    [Export] public RoomBounds StartRoom { get; set; } = null!;

    /// <summary>The emergency bus the three machines share.</summary>
    [Export] public PowerCircuit Circuit { get; set; } = null!;

    /// <summary>Top-left label: circuit load, armed checkpoint, the brother's state.</summary>
    [Export] public Label DebugLabel { get; set; } = null!;

    /// <summary>Second label: the last thing a mechanic announced, so a signal that fired is visible.</summary>
    [Export] public Label? EventLabel { get; set; }

    /// <summary>The way out; its departure is only reported here (a fixture changes no scenes).</summary>
    [Export] public Hoist? Cage { get; set; }

    /// <summary>Every gas pocket in the room — the rehearsal one and the normal one.</summary>
    [Export] public GasZone[] GasPockets { get; set; } = { };

    /// <summary>The scripted collapse that seals the drift behind the hero.</summary>
    [Export] public CaveIn? Collapse { get; set; }

    /// <summary>What the brother shouts when a pocket starts counting down.</summary>
    [Export] public string GasLine { get; set; } = "Lamp off! Gas!";

    /// <summary>What the brother shouts when the roof comes down.</summary>
    [Export] public string CollapseLine { get; set; } = "Move! It's coming down!";

    /// <summary>
    /// Opt-in: the brother guides instead of following. On ready he is led to the first marker of
    /// <see cref="DanRoute"/> (at the timber pile); powering <see cref="RouteMachine"/> — the pump
    /// that drains the drift — leads him on to <see cref="MachineRouteKey"/> (an explicit event);
    /// every armed checkpoint leads him at least to the marker <see cref="CheckpointRoute"/> names
    /// for it (never back). Off by default so the fixture and its Follow tests see exactly what
    /// they saw before.
    /// </summary>
    [Export] public bool DanLeads { get; set; }

    /// <summary>
    /// Container of <c>Marker2D</c> children named <c>WP_&lt;key&gt;</c>, in route order — the
    /// pattern any level can copy: the level names points by key, the companion only ever gets a
    /// position. Every point sits short of the blocker it waits at, never past one.
    /// </summary>
    [Export] public Node2D? DanRoute { get; set; }

    /// <summary>Route key the guide is led to (at least) when the n-th child of <see cref="LevelBase.Checkpoints"/> is armed.</summary>
    [Export] public string[] CheckpointRoute { get; set; } = { "A", "C" };

    /// <summary>The machine whose powering leads the guide to <see cref="MachineRouteKey"/> (the pump: the drift is drained, the way on is open).</summary>
    [Export] public PoweredMachine? RouteMachine { get; set; }

    /// <summary>Route key the guide is led to when <see cref="RouteMachine"/> is powered.</summary>
    [Export] public string MachineRouteKey { get; set; } = "B";

    /// <summary>Fixture-only line shown when the guide reaches a route point, so a human sees the event.</summary>
    [Export] public string LeadLine { get; set; } = "This way.";

    /// <summary>Fixture-only line shown when the guide calls the lagging hero.</summary>
    [Export] public string CallLine { get; set; } = "Come on!";

    private readonly List<string> _routeKeys = new();
    private readonly List<Vector2> _routePoints = new();
    private string _companionState = string.Empty;
    private int _routeIndex = -1;

    /// <summary>Key of the route point the guide was last led to, or an empty string.</summary>
    public string CurrentRouteKey => _routeIndex < 0 ? string.Empty : _routeKeys[_routeIndex];

    /// <inheritdoc/>
    public override void _Ready()
    {
        base._Ready();
        ApplyRoomBounds(StartRoom);
        ReadRoute();
        if (Companion is not null)
        {
            Companion.Arrived += OnDanArrived;
            Companion.HeroReached += OnHeroReachedDan;
            Companion.HeroLagging += OnHeroLagging;
        }

        if (DanLeads && _routeKeys.Count > 0)
        {
            LeadTo(_routeKeys[0]);
        }

        Circuit.LoadChanged += OnLoadChanged;
        Circuit.MachinePowered += OnMachinePowered;
        Circuit.MachineReleased += OnMachineReleased;
        Circuit.RequestRefused += OnRequestRefused;
        foreach (GasZone pocket in GasPockets)
        {
            pocket.WarningStarted += OnGasWarningStarted;
            pocket.WarningStopped += OnGasWarningStopped;
            pocket.Ignited += OnGasIgnited;
            pocket.Cleared += OnGasCleared;
        }

        if (Collapse is not null)
        {
            Collapse.Collapsed += OnCollapsed;
        }

        if (Cage is not null)
        {
            Cage.Departed += OnDeparted;
        }

        CheckpointArmed += OnCheckpointArmed;
        Respawned += OnRespawned;
        RefreshLabel();
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        base._ExitTree();
        if (Companion is not null && IsInstanceValid(Companion))
        {
            Companion.Arrived -= OnDanArrived;
            Companion.HeroReached -= OnHeroReachedDan;
            Companion.HeroLagging -= OnHeroLagging;
        }

        Circuit.LoadChanged -= OnLoadChanged;
        Circuit.MachinePowered -= OnMachinePowered;
        Circuit.MachineReleased -= OnMachineReleased;
        Circuit.RequestRefused -= OnRequestRefused;
        foreach (GasZone pocket in GasPockets)
        {
            pocket.WarningStarted -= OnGasWarningStarted;
            pocket.WarningStopped -= OnGasWarningStopped;
            pocket.Ignited -= OnGasIgnited;
            pocket.Cleared -= OnGasCleared;
        }

        if (Collapse is not null)
        {
            Collapse.Collapsed -= OnCollapsed;
        }

        if (Cage is not null)
        {
            Cage.Departed -= OnDeparted;
        }

        CheckpointArmed -= OnCheckpointArmed;
        Respawned -= OnRespawned;
    }

    /// <summary>Follows the hero (base) and refreshes the label only when the brother changed state.</summary>
    /// <param name="delta">Idle frame time in seconds.</param>
    public override void _Process(double delta)
    {
        base._Process(delta);
        string state = Companion is null ? string.Empty : Companion.CurrentStateName;
        if (state != _companionState)
        {
            _companionState = state;
            RefreshLabel();
        }
    }

    /// <summary>Leads the guide to the route point <paramref name="key"/> (a <c>WP_&lt;key&gt;</c> marker); an unknown key is an error and does nothing.</summary>
    /// <param name="key">Route key, the marker's name without the <c>WP_</c> prefix.</param>
    public void LeadTo(string key)
    {
        int index = _routeKeys.IndexOf(key);
        if (index < 0)
        {
            GD.PushError($"{Name}: no route point '{key}' under {DanRoute?.Name}.");
            return;
        }

        _routeIndex = index;
        Companion?.LeadTo(_routePoints[index]);
        RefreshLabel();
    }

    /// <summary>
    /// Leads the guide to <paramref name="key"/> only if it lies further along the route than the
    /// point he was last led to — the rule for the hero's checkpoints: the guide is never sent back
    /// behind the hero's progress.
    /// </summary>
    /// <param name="key">Route key.</param>
    public void LeadAtLeast(string key)
    {
        if (_routeKeys.IndexOf(key) > _routeIndex)
        {
            LeadTo(key);
        }
    }

    private void ReadRoute()
    {
        _routeKeys.Clear();
        _routePoints.Clear();
        if (DanRoute is null)
        {
            return;
        }

        foreach (Node child in DanRoute.GetChildren())
        {
            if (child is Marker2D marker && marker.Name.ToString().StartsWith("WP_"))
            {
                _routeKeys.Add(marker.Name.ToString()["WP_".Length..]);
                _routePoints.Add(marker.GlobalPosition);
            }
        }
    }

    private void OnDanArrived()
    {
        if (Companion is { IsLeading: true })
        {
            Companion.Say(LeadLine);
            Announce($"Dan reached {CurrentRouteKey}");
        }
    }

    private void OnHeroReachedDan() => Announce($"The hero reached Dan at {CurrentRouteKey}");

    private void OnHeroLagging()
    {
        Companion?.Say(CallLine);
        Announce("Dan calls the hero");
    }

    private void OnLoadChanged(int used, int capacity) => RefreshLabel();

    private void OnMachinePowered(PoweredMachine machine)
    {
        Announce($"{machine.DisplayName} running");
        if (DanLeads && ReferenceEquals(machine, RouteMachine))
        {
            LeadTo(MachineRouteKey);
        }
    }

    private void OnMachineReleased(PoweredMachine machine) => Announce($"{machine.DisplayName} switched off");

    private void OnRequestRefused(PoweredMachine machine, PoweredMachine blocking) =>
        Announce($"{machine.DisplayName} refused: {blocking.DisplayName} is running");

    private void OnGasWarningStarted()
    {
        // Author's rule: Dan goes dark first, then shouts — the lamp shows the rule before the line says it.
        Companion?.SetLampOn(false);
        Companion?.Say(GasLine);
        Announce("Gas: warning");
    }

    private void OnGasWarningStopped()
    {
        Companion?.SetLampOn(true);
        Announce("Gas: warning off");
    }

    private void OnGasIgnited(Player player) => Announce("Gas: ignited");

    private void OnGasCleared()
    {
        Companion?.SetLampOn(true);
        Announce("Gas: cleared for good");
    }

    private void OnCollapsed()
    {
        Companion?.Say(CollapseLine);
        Announce("The roof came down");
    }

    private void OnDeparted(Player player) => Announce("The hoist departed");

    private void OnCheckpointArmed(Checkpoint checkpoint)
    {
        Announce($"Checkpoint: {checkpoint.Label}");
        int index = checkpoint.GetIndex();
        if (DanLeads && index < CheckpointRoute.Length)
        {
            LeadAtLeast(CheckpointRoute[index]);
        }
    }

    private void OnRespawned() => Announce("Respawned at the checkpoint");

    private void Announce(string text)
    {
        if (EventLabel is not null)
        {
            EventLabel.Text = text;
        }

        RefreshLabel();
    }

    private void RefreshLabel()
    {
        string checkpoint = ArmedCheckpoint is null ? "-" : ArmedCheckpoint.Label;
        string dan = _companionState == CompanionState.StateLead ? $"{_companionState} -> {CurrentRouteKey}" : _companionState;
        DebugLabel.Text = $"Circuit {Circuit.Used}/{Circuit.Capacity}   Checkpoint: {checkpoint}   Dan: {dan}";
    }
}
