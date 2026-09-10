using Godot;

namespace BlackoutLastGrid.Ui;

/// <summary>
/// Placeholder text cutscene: a dark overlay with one line of text at a time and a "next" hint.
/// <see cref="Play"/> shows the first line; each <c>interact</c> or <c>attack</c> press (when
/// <see cref="Skippable"/>) or <see cref="LineDuration"/> seconds (when set) advance, and the
/// last line ends with <see cref="FinishedEventHandler"/>. The level pauses the hero while the
/// cutscene plays; the overlay itself runs with <see cref="Node.ProcessModeEnum.Always"/> and
/// polls input in <c>_PhysicsProcess</c>, so the press that advances a line is consumed in a
/// physics frame the paused hero skips and never doubles as an attack or an interaction when the
/// hero resumes (the level resumes it deferred, after this frame's physics). While the tree is
/// paused the overlay freezes: no line advances and no <see cref="LineDuration"/> accumulates.
/// </summary>
public partial class Cutscene : CanvasLayer
{
    private static readonly StringName ActionInteract = "interact";
    private static readonly StringName ActionAttack = "attack";

    /// <summary>Seconds per line used when a run could otherwise never advance (not skippable, no <see cref="LineDuration"/>).</summary>
    private const float FallbackLineDuration = 3f;

    /// <summary>Emitted once, after the last line was dismissed.</summary>
    [Signal]
    public delegate void FinishedEventHandler();

    /// <summary>Lines played by <see cref="PlayDefault"/>; levels usually pass their own to <see cref="Play"/>.</summary>
    [Export] public string[] Lines { get; set; } = System.Array.Empty<string>();

    /// <summary><c>true</c> lets the player advance lines with <c>interact</c>/<c>attack</c>.</summary>
    [Export] public bool Skippable { get; set; } = true;

    /// <summary>Seconds after which a line advances on its own; 0 = wait for the player.</summary>
    [Export] public float LineDuration { get; set; }

    /// <summary>Hint under the text while more lines follow.</summary>
    [Export] public string HintText { get; set; } = "E — next";

    /// <summary>Hint under the last line.</summary>
    [Export] public string LastHintText { get; set; } = "E — continue";

    /// <summary>Overlay root, hidden while idle.</summary>
    [Export] public Control Root { get; set; } = null!;

    /// <summary>Label carrying the current line.</summary>
    [Export] public Label TextLabel { get; set; } = null!;

    /// <summary>Label carrying the "next" hint.</summary>
    [Export] public Label HintLabel { get; set; } = null!;

    private string[] _lines = System.Array.Empty<string>();
    private float _lineTime;

    /// <summary><c>true</c> between <see cref="Play"/> and <see cref="FinishedEventHandler"/>.</summary>
    public bool IsPlaying { get; private set; }

    /// <summary>Index of the line on screen; −1 while idle.</summary>
    public int CurrentLine { get; private set; } = -1;

    /// <summary>Number of lines in the current (or last) run.</summary>
    public int LineCount => _lines.Length;

    /// <inheritdoc/>
    public override void _Ready()
    {
        ProcessMode = ProcessModeEnum.Always;
        Root.Visible = false;
        SetPhysicsProcess(false);
    }

    /// <inheritdoc/>
    public override void _PhysicsProcess(double delta)
    {
        if (GetTree().Paused)
        {
            return;   // a paused game must neither advance a line nor accumulate LineDuration
        }

        if (Skippable && (Input.IsActionJustPressed(ActionInteract) || Input.IsActionJustPressed(ActionAttack)))
        {
            Advance();
            return;
        }

        if (LineDuration > 0f)
        {
            _lineTime += (float)delta;
            if (_lineTime >= LineDuration)
            {
                Advance();
            }
        }
    }

    /// <summary>
    /// Shows <paramref name="lines"/> from the first one. Empty input finishes at once (deferred, so
    /// the listener is connected). Checked here, not in <c>_Ready</c>, because the level assigns
    /// <see cref="Skippable"/> after this node is ready: a run that could never advance (not
    /// skippable, no <see cref="LineDuration"/>) warns and uses <see cref="FallbackLineDuration"/>.
    /// </summary>
    /// <param name="lines">Lines to show, one at a time.</param>
    public void Play(string[] lines)
    {
        _lines = lines;
        IsPlaying = true;
        if (lines.Length == 0)
        {
            Callable.From(Finish).CallDeferred();
            return;
        }

        if (!Skippable && LineDuration <= 0f)
        {
            GD.PushWarning($"{Name}: not skippable and no LineDuration; lines could never advance — using {FallbackLineDuration} s per line.");
            LineDuration = FallbackLineDuration;
        }

        Root.Visible = true;
        ShowLine(0);
        SetPhysicsProcess(true);
    }

    /// <summary>Plays the scene's own <see cref="Lines"/>.</summary>
    public void PlayDefault() => Play(Lines);

    /// <summary>Goes to the next line, or finishes after the last one. A no-op while idle.</summary>
    public void Advance()
    {
        if (!IsPlaying)
        {
            return;
        }

        if (CurrentLine + 1 >= _lines.Length)
        {
            Finish();
            return;
        }

        ShowLine(CurrentLine + 1);
    }

    private void ShowLine(int index)
    {
        CurrentLine = index;
        _lineTime = 0f;
        TextLabel.Text = _lines[index];
        HintLabel.Text = index + 1 < _lines.Length ? HintText : LastHintText;
        HintLabel.Visible = Skippable;
    }

    private void Finish()
    {
        if (!IsPlaying)
        {
            return;
        }

        IsPlaying = false;
        CurrentLine = -1;
        SetPhysicsProcess(false);
        Root.Visible = false;
        EmitSignalFinished();
    }
}
