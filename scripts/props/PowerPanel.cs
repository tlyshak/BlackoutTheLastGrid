using System.Collections.Generic;
using System.Text;
using BlackoutLastGrid.Actors;
using Godot;

namespace BlackoutLastGrid.Props;

/// <summary>
/// Dead power panel repaired by pressing a short <see cref="Sequence"/> of InputMap actions in
/// order (GAME_DESIGN §4: 3–4 buttons, no mini-game). While the sequence runs the panel polls the
/// tracked actions itself in <c>_PhysicsProcess</c> and shows the progress through the prompt
/// ("↑ [J] ↓ ␣"); a wrong action or a step timeout fails the attempt. Once activated it emits
/// <see cref="ActivatedEventHandler"/> (the level switches its lights on) and refuses further use.
/// A panel with <see cref="Powered"/> off accepts the sequence but cannot activate: it emits
/// <see cref="FailedNoPowerEventHandler"/> instead, flashes red and from then on refuses further
/// use, showing <see cref="NoPowerPromptText"/> — the player has been told it is dead.
/// </summary>
public partial class PowerPanel : Interactable
{
    /// <summary>Actions polled while the sequence is active; any of them counts as an answer to the current step.</summary>
    private static readonly StringName[] TrackedActions =
    {
        "move_left", "move_right", "move_up", "move_down", "jump", "attack", "heavy_attack", "special",
    };

    /// <summary>Keyboard glyph per action for the prompt (gamepad glyphs are a later task).</summary>
    private static readonly Dictionary<string, string> ActionGlyphs = new()
    {
        ["move_up"] = "↑",
        ["move_down"] = "↓",
        ["move_left"] = "←",
        ["move_right"] = "→",
        ["jump"] = "␣",
        ["attack"] = "J",
        ["heavy_attack"] = "K",
        ["special"] = "L",
    };

    /// <summary>Emitted once, when the whole sequence was entered correctly.</summary>
    [Signal]
    public delegate void ActivatedEventHandler();

    /// <summary>Emitted after every correct press: <paramref name="index"/> steps done out of <paramref name="total"/>.</summary>
    [Signal]
    public delegate void SequenceStepEventHandler(int index, int total);

    /// <summary>Emitted when a wrong action was pressed or a step timed out.</summary>
    [Signal]
    public delegate void SequenceFailedEventHandler();

    /// <summary>Emitted when the whole sequence was entered correctly but <see cref="Powered"/> is off; the attempt ends with <c>Finished(false)</c>.</summary>
    [Signal]
    public delegate void FailedNoPowerEventHandler();

    /// <summary><c>false</c> for a panel cut off upstream: the sequence completes but the panel cannot switch on.</summary>
    [Export] public bool Powered { get; set; } = true;

    /// <summary>InputMap actions to press in order.</summary>
    [Export] public string[] Sequence { get; set; } = { "move_up", "attack", "move_down", "jump" };

    /// <summary>Seconds allowed per step before the attempt fails; 0 = no limit.</summary>
    [Export] public float StepTimeout { get; set; } = 2f;

    /// <summary>Seconds the screen stays red after a failure before the hero is released.</summary>
    [Export] public float FailResetDelay { get; set; } = 0.5f;

    /// <summary>Prompt shown once the panel is activated.</summary>
    [Export] public string ActivatedPromptText { get; set; } = "Running";

    /// <summary>Prompt shown once an unpowered panel has failed with <see cref="FailedNoPowerEventHandler"/>.</summary>
    [Export] public string NoPowerPromptText { get; set; } = "No power";

    /// <summary>Colour of <see cref="Screen"/> while dead.</summary>
    [Export] public Color DeadColor { get; set; } = new(0.6f, 0.1f, 0.1f);

    /// <summary>Colour of <see cref="Screen"/> while the sequence is being entered.</summary>
    [Export] public Color BusyColor { get; set; } = new(1f, 0.85f, 0.2f);

    /// <summary>Colour of <see cref="Screen"/> once activated.</summary>
    [Export] public Color ActiveColor { get; set; } = new(0.2f, 1f, 0.3f);

    /// <summary>Colour of <see cref="Screen"/> flashed on a failed attempt.</summary>
    [Export] public Color FailColor { get; set; } = new(1f, 0.25f, 0.2f);

    /// <summary>Placeholder screen recoloured by the panel's status.</summary>
    [Export] public Polygon2D? Screen { get; set; }

    private int _step;
    private float _stepTime;
    private bool _failing;
    private float _failTime;
    private bool _deadNoPower;

    /// <summary><c>true</c> once the sequence was completed; the panel stays on.</summary>
    public bool IsActivated { get; private set; }

    /// <summary>Number of correct steps entered in the current attempt.</summary>
    public int CurrentStep => _step;

    /// <inheritdoc/>
    public override bool CanInteract => !IsActivated && !_deadNoPower;

    private static bool IsTracked(string action)
    {
        foreach (StringName tracked in TrackedActions)
        {
            if (tracked == action)
            {
                return true;
            }
        }

        return false;
    }

    /// <inheritdoc/>
    public override string CurrentPrompt =>
        IsActivated ? ActivatedPromptText
        : _deadNoPower ? NoPowerPromptText
        : IsActive && !_failing ? BuildSequencePrompt()
        : PromptText;

    /// <inheritdoc/>
    public override void _Ready()
    {
        foreach (string action in Sequence)
        {
            if (!InputMap.HasAction(action))
            {
                GD.PushWarning($"{Name}: Sequence contains unknown InputMap action '{action}'.");
            }
            else if (!IsTracked(action))
            {
                GD.PushWarning($"{Name}: Sequence action '{action}' is not polled by the panel (tracked: move_*, jump, attack, heavy_attack, special); the sequence cannot be completed.");
            }
        }

        SetPhysicsProcess(false);
        SetScreen(DeadColor);
    }

    /// <inheritdoc/>
    public override void _PhysicsProcess(double delta)
    {
        if (_failing)
        {
            _failTime -= (float)delta;
            if (_failTime <= 0f)
            {
                AbortAttempt();
            }

            return;
        }

        StringName? pressed = FirstPressedAction();
        if (pressed is not null)
        {
            HandlePress(pressed);
            return;
        }

        _stepTime += (float)delta;
        if (StepTimeout > 0f && _stepTime > StepTimeout)
        {
            Fail();
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

        _step = 0;
        _stepTime = 0f;
        _failing = false;
        if (Sequence.Length == 0)
        {
            Complete();
            return;
        }

        SetScreen(BusyColor);
        SetPhysicsProcess(true);
        NotifyPromptChanged();
    }

    /// <inheritdoc/>
    public override void Cancel()
    {
        if (!IsActive)
        {
            return;
        }

        EndAttempt();
        base.Cancel();
        NotifyPromptChanged();
    }

    private void HandlePress(StringName action)
    {
        if (action != Sequence[_step])
        {
            Fail();
            return;
        }

        _step++;
        _stepTime = 0f;
        EmitSignalSequenceStep(_step, Sequence.Length);
        if (_step >= Sequence.Length)
        {
            Complete();
            return;
        }

        NotifyPromptChanged();
    }

    private void Complete()
    {
        if (!Powered)
        {
            _deadNoPower = true;
            EmitSignalFailedNoPower();
            StartFailFlash();
            return;
        }

        IsActivated = true;
        SetPhysicsProcess(false);
        SetScreen(ActiveColor);
        EmitSignalActivated();
        NotifyPromptChanged();
        Finish(true);
    }

    private void Fail()
    {
        EmitSignalSequenceFailed();
        StartFailFlash();
    }

    /// <summary>Shows <see cref="FailColor"/> for <see cref="FailResetDelay"/>, then aborts the attempt (at once without a delay).</summary>
    private void StartFailFlash()
    {
        SetScreen(FailColor);
        NotifyPromptChanged();
        if (FailResetDelay <= 0f)
        {
            AbortAttempt();
            return;
        }

        _failing = true;
        _failTime = FailResetDelay;
    }

    /// <summary>Ends a failed attempt: releases the hero with <c>Finished(false)</c> and restores the idle prompt.</summary>
    private void AbortAttempt()
    {
        EndAttempt();
        Finish(false);
        NotifyPromptChanged();
    }

    /// <summary>Stops polling and returns the screen to its dead colour after a failed or cancelled attempt.</summary>
    private void EndAttempt()
    {
        _failing = false;
        _step = 0;
        SetPhysicsProcess(false);
        SetScreen(DeadColor);
    }

    private static StringName? FirstPressedAction()
    {
        foreach (StringName action in TrackedActions)
        {
            if (Input.IsActionJustPressed(action))
            {
                return action;
            }
        }

        return null;
    }

    private string BuildSequencePrompt()
    {
        StringBuilder prompt = new();
        for (int i = 0; i < Sequence.Length; i++)
        {
            if (i > 0)
            {
                prompt.Append(' ');
            }

            string glyph = ActionGlyphs.TryGetValue(Sequence[i], out string? known) ? known : Sequence[i];
            if (i == _step)
            {
                prompt.Append('[').Append(glyph).Append(']');
            }
            else
            {
                prompt.Append(glyph);
            }
        }

        return prompt.ToString();
    }

    private void SetScreen(Color color)
    {
        if (Screen is not null)
        {
            Screen.Color = color;
        }
    }
}
