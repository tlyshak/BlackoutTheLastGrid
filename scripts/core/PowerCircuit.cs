using System.Collections.Generic;
using BlackoutLastGrid.Props;
using Godot;

namespace BlackoutLastGrid.Core;

/// <summary>
/// The mine's emergency bus: <see cref="Capacity"/> power units shared by every
/// <see cref="PoweredMachine"/> of one level (GAME_DESIGN §1 «Два контури», §3). Machines join it
/// themselves in their <c>_Ready</c> and ask for power when their panel completes. The circuit
/// never preempts a running machine — a request that does not fit is **refused** and names the
/// machine the player has to switch off first, so the trade-off is a decision the player takes and
/// not a side effect they never see.
/// </summary>
/// <remarks>
/// Level-local state on purpose: a plain <see cref="Node"/> in the level scene (the
/// <see cref="EnemyDirector"/> pattern), never an autoload, so reloading the level starts with an
/// empty bus and nothing has to be reset by hand. Everything here is event-driven; no code runs
/// per frame.
/// </remarks>
public partial class PowerCircuit : Node
{
    /// <summary>Emitted when a machine joined the bus from its <c>_Ready</c>.</summary>
    [Signal]
    public delegate void MachineRegisteredEventHandler(PoweredMachine machine);

    /// <summary>Emitted when a power request was granted and the machine is now running.</summary>
    [Signal]
    public delegate void MachinePoweredEventHandler(PoweredMachine machine);

    /// <summary>Emitted when a running machine gave its units back (the player switched it off, or it left the tree).</summary>
    [Signal]
    public delegate void MachineReleasedEventHandler(PoweredMachine machine);

    /// <summary>
    /// Emitted when a request did not fit: <paramref name="blocking"/> is the machine the player has
    /// to switch off first, and the panel shows its name.
    /// </summary>
    [Signal]
    public delegate void RequestRefusedEventHandler(PoweredMachine machine, PoweredMachine blocking);

    /// <summary>Emitted after every granted or released request with the new load.</summary>
    [Signal]
    public delegate void LoadChangedEventHandler(int used, int capacity);

    /// <summary>Power units the emergency bus can feed at once; the level's difficulty dial.</summary>
    [Export] public int Capacity { get; set; } = 1;

    private readonly List<PoweredMachine> _powered = new();

    /// <summary>Power units currently drawn by running machines.</summary>
    public int Used { get; private set; }

    /// <summary>
    /// Power units still available; a request larger than this is refused. Named
    /// <c>FreeCapacity</c> and not <c>Free</c> because <c>Free()</c> is a
    /// <see cref="GodotObject"/> method.
    /// </summary>
    public int FreeCapacity => Capacity - Used;

    /// <summary>
    /// Machines registered on this bus, in registration order. A Godot array so tests and tools can
    /// read it from GDScript; treat it as read-only — the circuit owns its contents.
    /// </summary>
    public Godot.Collections.Array<PoweredMachine> Machines { get; } = new();

    /// <summary>Adds <paramref name="machine"/> to the bus; a machine already registered is ignored.</summary>
    /// <param name="machine">The machine whose <c>_Ready</c> is running.</param>
    public void Register(PoweredMachine machine)
    {
        if (Machines.Contains(machine))
        {
            return;
        }

        Machines.Add(machine);
        EmitSignalMachineRegistered(machine);
    }

    /// <summary>
    /// Removes <paramref name="machine"/> from the bus, releasing its units first; a machine that
    /// was never registered is ignored. Called from the machine's <c>_ExitTree</c>.
    /// </summary>
    /// <param name="machine">The machine leaving the tree.</param>
    public void Unregister(PoweredMachine machine)
    {
        Release(machine);
        Machines.Remove(machine);
    }

    /// <summary>
    /// Asks for the units <paramref name="machine"/> needs — <see cref="Capacity"/> for a machine
    /// with <see cref="PoweredMachine.RequiresWholeCircuit"/>, its
    /// <see cref="PoweredMachine.PowerCost"/> otherwise. Never switches anything off: when the
    /// units are not free the call fails and <paramref name="blocking"/> names the machine that has
    /// been running longest, which is the one to switch off. A machine that already runs gets
    /// <c>true</c> without drawing twice.
    /// </summary>
    /// <param name="machine">The machine whose panel was just completed.</param>
    /// <param name="blocking">
    /// The machine to switch off first, or <c>null</c> when the request can never fit (a wiring
    /// error, reported with a warning).
    /// </param>
    /// <returns><c>true</c> when the machine may run.</returns>
    public bool TryPower(PoweredMachine machine, out PoweredMachine? blocking)
    {
        blocking = null;
        if (_powered.Contains(machine))
        {
            return true;
        }

        int needed = machine.RequiresWholeCircuit ? Capacity : machine.PowerCost;
        if (needed > Capacity)
        {
            GD.PushWarning($"{Name}: {machine.Name} needs {needed} of {Capacity} power units and can never be switched on; check the level's wiring.");
            return false;
        }

        if (FreeCapacity < needed)
        {
            // needed <= Capacity, so FreeCapacity < needed implies Used > 0: there is always a machine to name.
            blocking = _powered[0];
            EmitSignalRequestRefused(machine, _powered[0]);
            return false;
        }

        _powered.Add(machine);
        Used += needed;
        EmitSignalMachinePowered(machine);
        EmitSignalLoadChanged(Used, Capacity);
        return true;
    }

    /// <summary>
    /// Gives the units held by <paramref name="machine"/> back. Idempotent — a machine that is not
    /// running is a no-op — so a panel may release from inside a signal handler.
    /// </summary>
    /// <param name="machine">The machine that was switched off.</param>
    public void Release(PoweredMachine machine)
    {
        if (!_powered.Remove(machine))
        {
            return;
        }

        Used = Mathf.Max(0, Used - (machine.RequiresWholeCircuit ? Capacity : machine.PowerCost));
        EmitSignalMachineReleased(machine);
        EmitSignalLoadChanged(Used, Capacity);
    }
}
