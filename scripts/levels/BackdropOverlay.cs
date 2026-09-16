using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// One animated piece of a painted room: a crop of the section mockup (an alarm lamp, a lamp's
/// glow, a fan's blades — <c>assets/art/v2/backgrounds/*_alarm|_worklamp_*|_fan_blades.svg</c>)
/// drawn over the static layers of its <see cref="SectionBackdrop"/> and moved by
/// <see cref="Motion"/>. The crop is authored in mockup px: <see cref="CropOrigin"/> is the
/// mockup point at the texture's top-left corner, <see cref="Pivot"/> the mockup point this node
/// sits on and turns about (the fan's hub; for a lamp, the crop's own origin). The parent
/// backdrop calls <see cref="Place"/> from its <c>_Ready</c> with the section's placement, so the
/// piece lands on the very pixels it was cut from and needs no world coordinates of its own.
/// </summary>
/// <remarks>
/// Purely visual, so it lives in <c>_Process</c>: it freezes with the pause menu (process mode
/// inherit) and slows with a hit-stop (the delta is scaled). Every motion is a function of the
/// accumulated time, so two pieces with the same exports (a lamp's wall and floor glow) stay in
/// step by construction, and the flicker's noise is a hash of <see cref="Seed"/> — no random
/// state, no allocation per frame. <see cref="Powered"/> false is the station's blackout: a lamp
/// goes dark, a fan spins down, an alarm on its own battery keeps blinking.
/// </remarks>
public partial class BackdropOverlay : Sprite2D
{
    /// <summary>How the piece moves.</summary>
    public enum MotionKind
    {
        /// <summary>Drawn as cut, no motion.</summary>
        Static,

        /// <summary>Alpha steps between 1 and <see cref="BlinkOffAlpha"/> every <see cref="BlinkPeriod"/> (an alarm beacon).</summary>
        Blink,

        /// <summary>Alpha wanders below 1 with value noise at <see cref="FlickerRate"/>, with short dropouts (a lamp on a bad contact).</summary>
        Flicker,

        /// <summary>Rotates about <see cref="Pivot"/> at <see cref="TurnsPerSecond"/> (a fan).</summary>
        Spin,
    }

    // ---- placement, in mockup (viewBox) px ----------------------------------------------------------

    /// <summary>Mockup point at the texture's top-left corner (the crop's viewBox origin).</summary>
    [Export] public Vector2 CropOrigin { get; set; }

    /// <summary>Mockup point this node is placed on and rotates about; the crop's origin for a lamp, the hub for a fan.</summary>
    [Export] public Vector2 Pivot { get; set; }

    // ---- motion ------------------------------------------------------------------------------------

    /// <summary>The motion of this piece.</summary>
    [Export] public MotionKind Motion { get; set; } = MotionKind.Static;

    /// <summary><c>false</c> keeps the piece going through a blackout (an alarm on a battery); <c>true</c> lets <see cref="Powered"/> stop it.</summary>
    [Export] public bool NeedsPower { get; set; } = true;

    /// <summary>Blink: length of one on-off cycle, in seconds.</summary>
    [Export] public float BlinkPeriod { get; set; } = 1.2f;

    /// <summary>Blink: share of the cycle the lamp is on.</summary>
    [Export(PropertyHint.Range, "0,1")] public float BlinkOnFraction { get; set; } = 0.4f;

    /// <summary>Blink: alpha while off — the dark bulb stays visible.</summary>
    [Export(PropertyHint.Range, "0,1")] public float BlinkOffAlpha { get; set; } = 0.25f;

    /// <summary>Flicker: noise samples per second; higher is a faster buzz.</summary>
    [Export] public float FlickerRate { get; set; } = 14f;

    /// <summary>Flicker: how far below full the alpha wanders (0 = steady).</summary>
    [Export(PropertyHint.Range, "0,1")] public float FlickerDepth { get; set; } = 0.45f;

    /// <summary>Flicker: noise above this value is a dropout, the lamp nearly out for that sample.</summary>
    [Export(PropertyHint.Range, "0,1")] public float DropoutAbove { get; set; } = 0.93f;

    /// <summary>Flicker: alpha during a dropout.</summary>
    [Export(PropertyHint.Range, "0,1")] public float DropoutAlpha { get; set; } = 0.15f;

    /// <summary>Flicker: seed of the noise; two pieces with one seed flicker as one lamp.</summary>
    [Export] public int Seed { get; set; } = 1;

    /// <summary>Spin: turns per second while powered; positive is clockwise on screen.</summary>
    [Export] public float TurnsPerSecond { get; set; } = 0.6f;

    /// <summary>Spin: seconds a powered fan takes to stop after a blackout.</summary>
    [Export] public float SpinDownSeconds { get; set; } = 4f;

    /// <summary>Alpha of a lamp that has lost its power.</summary>
    [Export(PropertyHint.Range, "0,1")] public float UnpoweredAlpha { get; set; } = 0f;

    /// <summary>Station power; set by the parent backdrop (<see cref="SectionBackdrop.Powered"/>). Ignored when <see cref="NeedsPower"/> is false.</summary>
    public bool Powered { get; set; } = true;

    /// <summary>Seconds of motion so far (scaled by the engine's time scale).</summary>
    public float Elapsed { get; private set; }

    /// <summary>Current spin rate, turns per second; decays to 0 after a blackout.</summary>
    public float SpinRate { get; private set; }

    private bool Running => Powered || !NeedsPower;

    /// <inheritdoc/>
    public override void _Ready()
    {
        SpinRate = Motion == MotionKind.Spin ? TurnsPerSecond : 0f;
        Apply(0f);
    }

    /// <summary>
    /// Puts the crop on its mockup pixels: the node on the world point of <see cref="Pivot"/>, the
    /// texture offset so <see cref="CropOrigin"/> lands at the top-left, scaled from texture px
    /// to world px like the section's own layers.
    /// </summary>
    /// <param name="sectionX">World x of the section's left edge, relative to the backdrop.</param>
    /// <param name="offsetY">World y of the mockup's row 0 (<see cref="SectionBackdrop.OffsetY"/>).</param>
    /// <param name="worldScale">World px per mockup px.</param>
    /// <param name="importScale">Texture px per mockup px.</param>
    public void Place(float sectionX, float offsetY, float worldScale, float importScale)
    {
        Centered = false;
        Position = new Vector2(sectionX + Pivot.X * worldScale, offsetY + Pivot.Y * worldScale);
        Offset = (CropOrigin - Pivot) * importScale;
        float s = worldScale / importScale;
        Scale = new Vector2(s, s);
    }

    /// <inheritdoc/>
    public override void _Process(double delta)
    {
        float dt = (float)delta;
        if (dt <= 0f)
        {
            return;
        }
        Elapsed += dt;
        Apply(dt);
    }

    /// <summary>Alpha of a blinking piece at <paramref name="time"/> (pure; the test checks the schedule).</summary>
    public float BlinkAlpha(float time)
    {
        if (BlinkPeriod <= 0f)
        {
            return 1f;
        }
        float phase = Mathf.PosMod(time, BlinkPeriod) / BlinkPeriod;
        return phase < BlinkOnFraction ? 1f : BlinkOffAlpha;
    }

    /// <summary>Alpha of a flickering piece at <paramref name="time"/> (pure: value noise on <see cref="Seed"/>, dropouts above <see cref="DropoutAbove"/>).</summary>
    public float FlickerAlpha(float time)
    {
        float p = time * FlickerRate;
        int i = Mathf.FloorToInt(p);
        float f = p - i;
        float n = Mathf.Lerp(Hash(Seed, i), Hash(Seed, i + 1), f * f * (3f - 2f * f));
        float alpha = 1f - FlickerDepth * n;
        return n > DropoutAbove ? Mathf.Min(alpha, DropoutAlpha) : alpha;
    }

    private void Apply(float dt)
    {
        switch (Motion)
        {
            case MotionKind.Blink:
                SetAlpha(Running ? BlinkAlpha(Elapsed) : UnpoweredAlpha);
                break;
            case MotionKind.Flicker:
                SetAlpha(Running ? FlickerAlpha(Elapsed) : UnpoweredAlpha);
                break;
            case MotionKind.Spin:
                if (Running)
                {
                    SpinRate = TurnsPerSecond;
                }
                else if (SpinRate != 0f)
                {
                    float decay = SpinDownSeconds > 0f ? Mathf.Abs(TurnsPerSecond) * dt / SpinDownSeconds : Mathf.Abs(SpinRate);
                    SpinRate = Mathf.MoveToward(SpinRate, 0f, decay);
                }
                Rotation = Mathf.Wrap(Rotation + SpinRate * Mathf.Tau * dt, 0f, Mathf.Tau);
                break;
        }
    }

    private void SetAlpha(float alpha)
    {
        Color c = SelfModulate;
        c.A = Mathf.Clamp(alpha, 0f, 1f);
        SelfModulate = c;
    }

    /// <summary>Deterministic hash of (<paramref name="seed"/>, <paramref name="i"/>) to [0, 1).</summary>
    private static float Hash(int seed, int i)
    {
        unchecked
        {
            uint h = (uint)(seed * 374761393) + (uint)(i * 668265263);
            h = (h ^ (h >> 13)) * 1274126177u;
            h ^= h >> 16;
            return (h & 0xFFFFFFu) / 16777216f;
        }
    }
}
