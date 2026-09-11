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
/// following the hero. Nothing here is a level: it changes no scenes and tells no story, it only
/// lets every mechanic be touched on its own (F6) and gives the smoke scripts one place to drive
/// them from. All of it is <c>PH_</c> placeholder art in the palette of
/// <see cref="Art.Palette"/>; every visible string is English.
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

    private string _companionState = string.Empty;

    /// <inheritdoc/>
    public override void _Ready()
    {
        base._Ready();
        ApplyRoomBounds(StartRoom);

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

    private void OnLoadChanged(int used, int capacity) => RefreshLabel();

    private void OnMachinePowered(PoweredMachine machine) => Announce($"{machine.DisplayName} running");

    private void OnMachineReleased(PoweredMachine machine) => Announce($"{machine.DisplayName} switched off");

    private void OnRequestRefused(PoweredMachine machine, PoweredMachine blocking) =>
        Announce($"{machine.DisplayName} refused: {blocking.DisplayName} is running");

    private void OnGasWarningStarted()
    {
        Companion?.Say(GasLine);
        Announce("Gas: warning");
    }

    private void OnGasWarningStopped() => Announce("Gas: warning off");

    private void OnGasIgnited(Player player) => Announce("Gas: ignited");

    private void OnGasCleared() => Announce("Gas: cleared for good");

    private void OnCollapsed()
    {
        Companion?.Say(CollapseLine);
        Announce("The roof came down");
    }

    private void OnDeparted(Player player) => Announce("The hoist departed");

    private void OnCheckpointArmed(Checkpoint checkpoint) => Announce($"Checkpoint: {checkpoint.Label}");

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
        DebugLabel.Text = $"Circuit {Circuit.Used}/{Circuit.Capacity}   Checkpoint: {checkpoint}   Dan: {_companionState}";
    }
}
