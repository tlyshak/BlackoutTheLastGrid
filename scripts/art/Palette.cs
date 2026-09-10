using Godot;

namespace BlackoutLastGrid.Art;

/// <summary>
/// The project's single colour table (T-07i visual brief). Every procedural colour used by
/// scenes and scripts comes from here or from an <c>[Export]</c> seeded with one of these
/// values — no ad-hoc <c>Color(...)</c> literals in gameplay code.
/// </summary>
/// <remarks>
/// Deliberately a plain static class, not an autoload: it holds compile-time data, no runtime
/// state, and needs no node. The contrast rule the table encodes is "hero warm, enemies cold";
/// light is the only warm source in a scene.
/// </remarks>
public static class Palette
{
    /// <summary>Deepest rock layer, background.</summary>
    public static readonly Color RockDeep = Color.FromHtml("#12161d");

    /// <summary>Middle rock layer, walls.</summary>
    public static readonly Color RockMid = Color.FromHtml("#1b212b");

    /// <summary>Near rock, pit props.</summary>
    public static readonly Color RockNear = Color.FromHtml("#252d3a");

    /// <summary>Concrete, built structures.</summary>
    public static readonly Color ConcreteCold = Color.FromHtml("#39424f");

    /// <summary>Metal, pipes, grates.</summary>
    public static readonly Color SteelCold = Color.FromHtml("#4d5866");

    /// <summary>Rust, old metal.</summary>
    public static readonly Color RustDeep = Color.FromHtml("#5a3722");

    /// <summary>Rust accent.</summary>
    public static readonly Color RustWarm = Color.FromHtml("#8a4f28");

    /// <summary>Energy, working lamps, HUD accent.</summary>
    public static readonly Color EnergyAmber = Color.FromHtml("#f0a326");

    /// <summary>Core of a light source, incandescence.</summary>
    public static readonly Color EnergyPale = Color.FromHtml("#ffd98a");

    /// <summary>Alarm.</summary>
    public static readonly Color AlarmRed = Color.FromHtml("#c0392b");

    /// <summary>Alarm light.</summary>
    public static readonly Color AlarmGlow = Color.FromHtml("#ff6b52");

    /// <summary>Hero's face and hands.</summary>
    public static readonly Color SkinWarm = Color.FromHtml("#d9a077");

    /// <summary>Guards' faces and hands.</summary>
    public static readonly Color SkinCool = Color.FromHtml("#b5825f");

    /// <summary>Rey's overalls — the warm accent that keeps the hero readable in the dark.</summary>
    public static readonly Color HeroSuit = Color.FromHtml("#e08a1e");

    /// <summary>Dan's overalls.</summary>
    public static readonly Color DanSuit = Color.FromHtml("#c9752a");

    /// <summary>Guard uniform — cold, blends into the darkness.</summary>
    public static readonly Color GuardSuit = Color.FromHtml("#2c3340");

    /// <summary>Silhouette outline; the same colour as the darkness <c>CanvasModulate</c>.</summary>
    public static readonly Color OutlineDark = Color.FromHtml("#0a0d14");

    /// <summary>Decal shadow under a character.</summary>
    public static readonly Color ShadowSoft = new(0f, 0f, 0f, 0.45f);
}
