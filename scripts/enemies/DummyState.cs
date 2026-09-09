using BlackoutLastGrid.Core;

namespace BlackoutLastGrid.Enemies;

/// <summary>
/// Base for the training dummy's states: resolves the owning <see cref="Dummy"/> (the state
/// machine's parent) once, and shares the state names.
/// </summary>
public abstract partial class DummyState : State
{
    /// <summary>State names used for transitions.</summary>
    public const string StateIdle = "Idle";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateHurt = "Hurt";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateDown = "Down";

    /// <inheritdoc cref="StateIdle"/>
    public const string StateKO = "KO";

    /// <summary>The dummy this state controls.</summary>
    protected Dummy Dummy { get; private set; } = null!;

    /// <inheritdoc/>
    public override void _Ready() => Dummy = Machine.GetParent<Dummy>();
}
