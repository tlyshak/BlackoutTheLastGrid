using BlackoutLastGrid.Actors;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// The cage — the mine's only way out (GAME_DESIGN §3). A <see cref="PoweredMachine"/> that needs
/// the **whole** circuit, so starting it means giving up the last machine that still runs: one
/// visible, weighty decision instead of a walk back through the level. Once it runs, the hero
/// stepping into <see cref="BoardingArea"/> emits <see cref="DepartedEventHandler"/> and the level
/// decides what that means (a cutscene, the next horizon); the hoist changes no scenes itself.
/// </summary>
/// <remarks>
/// Scene contract: the <see cref="PoweredMachine"/> contract plus a <c>BoardingArea</c> child
/// (<c>Area2D</c>, layer 0, mask 2 Player, <c>monitorable = false</c>) across the floor band.
/// Instanced with <c>RequiresWholeCircuit = true</c> and <see cref="PowerPanel.CanPowerDown"/> off —
/// you do not switch off your own way out.
/// </remarks>
public partial class Hoist : PoweredMachine
{
    /// <summary>Emitted once, when the hero boarded a running hoist.</summary>
    [Signal]
    public delegate void DepartedEventHandler(Player player);

    /// <summary>Area the hero has to enter to ride the hoist up; crossing it while powered departs.</summary>
    [Export] public Area2D? BoardingArea { get; set; }

    /// <summary><c>false</c> ⇒ starting the hoist is enough to depart, without waiting for the hero to board (tests).</summary>
    [Export] public bool RequiresPlayerBoarding { get; set; } = true;

    private Player? _user;

    /// <summary><c>true</c> once <see cref="DepartedEventHandler"/> was emitted; the hoist leaves only once.</summary>
    public bool HasDeparted { get; private set; }

    /// <inheritdoc/>
    public override void _Ready()
    {
        base._Ready();
        PowerChanged += OnPowerChanged;
        if (BoardingArea is not null)
        {
            BoardingArea.BodyEntered += OnBoardingBodyEntered;
        }
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        PowerChanged -= OnPowerChanged;
        if (BoardingArea is not null)
        {
            BoardingArea.BodyEntered -= OnBoardingBodyEntered;
        }

        base._ExitTree();
    }

    /// <inheritdoc/>
    public override void Begin(Player player)
    {
        _user = player;
        base.Begin(player);
    }

    private void OnPowerChanged(bool powered)
    {
        if (!powered)
        {
            return;
        }

        if (!RequiresPlayerBoarding)
        {
            if (_user is not null && IsInstanceValid(_user))
            {
                Depart(_user);
            }

            return;
        }

        if (BoardingArea is null)
        {
            return;
        }

        // The panel's reach overlaps the cage, so the hero may already stand inside when it starts.
        foreach (Node2D body in BoardingArea.GetOverlappingBodies())
        {
            if (body is Player player)
            {
                Depart(player);
                return;
            }
        }
    }

    private void OnBoardingBodyEntered(Node2D body)
    {
        if (IsPowered && body is Player player)
        {
            Depart(player);
        }
    }

    private void Depart(Player player)
    {
        if (HasDeparted)
        {
            return;
        }

        HasDeparted = true;
        EmitSignalDeparted(player);
    }
}
