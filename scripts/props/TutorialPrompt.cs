using BlackoutLastGrid.Actors;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// One-shot tutorial hint: when the hero first walks into the area, <see cref="ShownEventHandler"/>
/// asks the level to show <see cref="Text"/> on the HUD; the hint is over —
/// <see cref="CompletedEventHandler"/> — as soon as <see cref="CompletesOnAction"/> is pressed or
/// <see cref="Timeout"/> seconds have passed, whichever comes first. The prompt does not touch the
/// HUD itself; the level owns the prompt label. Polls the action in <c>_PhysicsProcess</c> only
/// while showing, so a paused level (cutscene) also pauses the hint.
/// </summary>
/// <remarks>
/// Scene contract: root <c>Area2D</c> with <c>collision_layer = 0</c>, <c>collision_mask = 2</c>
/// (Player), <c>monitorable = false</c> and one <c>CollisionShape2D</c> covering the trigger zone.
/// </remarks>
public partial class TutorialPrompt : Area2D
{
    /// <summary>Emitted once, when the hero first enters the area; the level shows <see cref="Text"/>.</summary>
    [Signal]
    public delegate void ShownEventHandler();

    /// <summary>Emitted once, when the action was pressed or the timeout ran out; the level hides the hint.</summary>
    [Signal]
    public delegate void CompletedEventHandler();

    /// <summary>Hint shown on the HUD, e.g. "Space — jump".</summary>
    [Export] public string Text { get; set; } = string.Empty;

    /// <summary>InputMap action whose press completes the hint; empty = timeout only.</summary>
    [Export] public string CompletesOnAction { get; set; } = string.Empty;

    /// <summary>Seconds the hint stays before completing on its own; 0 = until the action is pressed.</summary>
    [Export] public float Timeout { get; set; } = 6f;

    private StringName? _action;
    private float _elapsed;

    /// <summary><c>true</c> after the hero triggered the hint (whether or not it is still showing).</summary>
    public bool IsShown { get; private set; }

    /// <summary><c>true</c> once the hint completed.</summary>
    public bool IsCompleted { get; private set; }

    /// <summary><c>true</c> while the hint should be visible.</summary>
    public bool IsShowing => IsShown && !IsCompleted;

    /// <inheritdoc/>
    public override void _Ready()
    {
        if (CompletesOnAction.Length > 0)
        {
            if (InputMap.HasAction(CompletesOnAction))
            {
                _action = CompletesOnAction;
            }
            else
            {
                GD.PushWarning($"{Name}: CompletesOnAction '{CompletesOnAction}' is not an InputMap action; the hint completes on timeout only.");
            }
        }

        if (_action is null && Timeout <= 0f)
        {
            GD.PushWarning($"{Name}: no action and no timeout; the hint would never complete — using a 6 s timeout.");
            Timeout = 6f;
        }

        SetPhysicsProcess(false);
        BodyEntered += OnBodyEntered;
    }

    /// <inheritdoc/>
    public override void _ExitTree() => BodyEntered -= OnBodyEntered;

    /// <inheritdoc/>
    public override void _PhysicsProcess(double delta)
    {
        if (_action is not null && Input.IsActionJustPressed(_action))
        {
            Complete();
            return;
        }

        if (Timeout > 0f)
        {
            _elapsed += (float)delta;
            if (_elapsed >= Timeout)
            {
                Complete();
            }
        }
    }

    /// <summary>Shows the hint now, as if the hero had walked in; a no-op once shown.</summary>
    public void Trigger()
    {
        if (IsShown)
        {
            return;
        }

        IsShown = true;
        _elapsed = 0f;
        SetDeferred(Area2D.PropertyName.Monitoring, false);   // one-shot; may be called from a physics callback
        SetPhysicsProcess(true);
        EmitSignalShown();
    }

    private void OnBodyEntered(Node2D body)
    {
        if (body is Player)
        {
            Trigger();
        }
    }

    /// <summary>Ends the hint now, as if the action had been pressed (the level uses it when the hint is moot); a no-op once completed.</summary>
    public void Complete()
    {
        if (IsCompleted)
        {
            return;
        }

        IsCompleted = true;
        SetPhysicsProcess(false);
        EmitSignalCompleted();
    }
}
