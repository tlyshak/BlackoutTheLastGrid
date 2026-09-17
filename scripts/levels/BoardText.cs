using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// One line of a painted room's LED board. Godot's SVG importer draws no <c>&lt;text&gt;</c> at all,
/// so the board in the author's concept comes through as a blank panel and its lines are drawn by
/// the engine instead — same colours, same size, placed on the pixels the panel occupies. The
/// author asked for the quota line to blink (his note of 2026-09-16), which a text node does for
/// free and a baked sprite could not.
/// </summary>
/// <remarks>
/// A steady line leaves <see cref="BlinkPeriod"/> at zero and never enters the process loop. The
/// blink is driven by the scaled delta, so it freezes with the pause menu and slows with a
/// hit-stop, exactly like <see cref="BackdropOverlay"/>'s.
/// </remarks>
public partial class BoardText : Label
{
    /// <summary>Seconds of one blink cycle; 0 leaves the line lit and out of the process loop.</summary>
    [Export] public float BlinkPeriod { get; set; }

    /// <summary>Fraction of the cycle the line is fully lit.</summary>
    [Export] public float BlinkOnFraction { get; set; } = 0.55f;

    /// <summary>Alpha the line drops to for the rest of the cycle; never 0, an LED bar keeps a glow.</summary>
    [Export] public float BlinkOffAlpha { get; set; } = 0.18f;

    /// <summary>Seconds the cycle starts in, so two boards on one wall are not in step.</summary>
    [Export] public float Phase { get; set; }

    private float _elapsed;

    /// <summary>Seconds this line has been running; the blink is a pure function of it.</summary>
    public float Elapsed => _elapsed;

    /// <inheritdoc/>
    public override void _Ready()
    {
        _elapsed = Phase;
        SetProcess(BlinkPeriod > 0f);
        Apply();
    }

    /// <inheritdoc/>
    public override void _Process(double delta)
    {
        _elapsed += (float)delta;
        Apply();
    }

    /// <summary>Alpha of the line at <paramref name="time"/> seconds; exposed so a test can read the curve.</summary>
    public float AlphaAt(float time) =>
        BlinkPeriod <= 0f || Mathf.PosMod(time, BlinkPeriod) < BlinkPeriod * BlinkOnFraction
            ? 1f
            : BlinkOffAlpha;

    private void Apply()
    {
        Color tint = Modulate;
        tint.A = AlphaAt(_elapsed);
        Modulate = tint;
    }
}
