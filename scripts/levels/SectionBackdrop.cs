using Godot;

namespace BlackoutLastGrid.Levels;

/// <summary>
/// Painted backdrop of one mine room of the v2 prologue (T-V2-01 01c). Takes the three layer
/// derivatives of a mockup section (<c>assets/art/v2/backgrounds/*_back|_mid|_floor.svg</c>,
/// imported at <see cref="ImportScale"/>) and builds, in <c>_Ready</c>, the sprites that show
/// them at world scale so the drawn floor's far edge lands on <see cref="FloorFarEdgeY"/>:
/// the whole section at <see cref="SectionX"/>, then seamless slices tiled to its left and right
/// until the room is <see cref="RoomWidth"/> wide. A room is data — an inherited scene of
/// <c>SectionBackdrop.tscn</c> with the textures and slice columns set.
/// <para>
/// Layers (z from the visual brief): <c>Back</c> is a <see cref="Parallax2D"/> at
/// <see cref="BackZ"/> whose tiles sit on a level-wide grid, so where the parallax shift makes
/// the copies of neighbouring rooms overlap they coincide pixel for pixel; <c>Mid</c>
/// (<see cref="MidZ"/>) and <c>Floor</c> (<see cref="FloorZ"/>) scroll with the world — the wall
/// base must stay glued to the floor seam. No collision, no signals; the node's own position is
/// the room's left edge (world x of the room rect).
/// </para>
/// </summary>
public partial class SectionBackdrop : Node2D
{
    private const string BackName = "Back";
    private const string MidName = "Mid";
    private const string FloorName = "Floor";

    // ---- textures -------------------------------------------------------------------------------

    /// <summary>Far layer of the section (sky, hills, far cables). Empty → no back layer.</summary>
    [Export] public Texture2D? BackTexture { get; set; }

    /// <summary>Middle layer of the section (pillars, beam, back wall, doors, panels).</summary>
    [Export] public Texture2D? MidTexture { get; set; }

    /// <summary>Floor layer of the section (plates, rails, props standing on the floor).</summary>
    [Export] public Texture2D? FloorTexture { get; set; }

    /// <summary>Mid-layer texture the slices left of the section are cut from. Empty → <see cref="MidTexture"/>.</summary>
    [Export] public Texture2D? LeftFillTexture { get; set; }

    /// <summary>Mid-layer texture the slices right of the section are cut from. Empty → <see cref="MidTexture"/>.</summary>
    [Export] public Texture2D? RightFillTexture { get; set; }

    /// <summary>Floor-layer texture the floor slices on both sides are cut from. Empty → <see cref="FloorTexture"/>.</summary>
    [Export] public Texture2D? FloorFillTexture { get; set; }

    // ---- slices, in mockup (viewBox) px: x from … x to ---------------------------------------------

    /// <summary>Column of the back texture tiled across the whole far layer (hill height equal at both ends).</summary>
    [Export] public Vector2 BackSlice { get; set; } = new(240f, 680f);

    /// <summary>Column of <see cref="LeftFillTexture"/> tiled left of the section: pillar right edge to pillar right edge.</summary>
    [Export] public Vector2 LeftFillSlice { get; set; } = new(72f, 322f);

    /// <summary>Column of <see cref="RightFillTexture"/> tiled right of the section: pillar left edge to pillar left edge.</summary>
    [Export] public Vector2 RightFillSlice { get; set; } = new(228f, 418f);

    /// <summary>
    /// Column of <see cref="FloorFillTexture"/> tiled under every mid slice: plates, rails and one
    /// sleeper, no props (section 1: between the conveyor and the cart). The width sets where the
    /// room-boundary cuts land on the sleeper rhythm; 44 keeps them between sleepers at both seams.
    /// </summary>
    [Export] public Vector2 FloorFillSlice { get; set; } = new(422f, 466f);

    // ---- scale and placement ----------------------------------------------------------------------

    /// <summary>Texture px per mockup px — the <c>svg/scale</c> of the derivatives' import sidecars.</summary>
    [Export] public float ImportScale { get; set; } = 3f;

    /// <summary>World px per mockup px (1.88: the 160 px drawn floor covers the 300 px walk band and the wall base).</summary>
    [Export] public float WorldScale { get; set; } = 1.88f;

    /// <summary>Mockup y where the drawn floor starts (the wall base), in mockup px.</summary>
    [Export] public float DrawnFloorTop { get; set; } = 280f;

    /// <summary>World y the drawn floor's far edge is placed on; the walk band's far 80 px stand against the wall base above it.</summary>
    [Export] public float FloorFarEdgeY { get; set; } = 380f;

    /// <summary>
    /// World x of the section's left edge, relative to this node (the room's left edge). Chosen
    /// together with <see cref="FillFrom"/> so the first left slice's edge (a pipe end) lands on the
    /// pillar that starts the previous room's last right slice — the room scenes carry the derived
    /// values.
    /// </summary>
    [Export] public float SectionX { get; set; } = 0f;

    /// <summary>Width of the room the camera is limited to, in world px; the far layer is sized from it.</summary>
    [Export] public float RoomWidth { get; set; } = 2880f;

    /// <summary>
    /// Relative world x the mid and floor layers start at and are cropped to. Neighbouring rooms
    /// meet where one's <see cref="FillTo"/> equals the other's <see cref="FillFrom"/> (in level
    /// space), on a pillar edge, so nothing is drawn twice: the mid layer is transparent above the
    /// wall, and an overlap would show through there.
    /// </summary>
    [Export] public float FillFrom { get; set; } = 0f;

    /// <summary>Relative world x the mid and floor layers end at and are cropped to (see <see cref="FillFrom"/>).</summary>
    [Export] public float FillTo { get; set; } = 2880f;

    // ---- far-layer parallax -----------------------------------------------------------------------

    /// <summary>Horizontal scroll of the back layer relative to the camera (1 = glued to the world, 0 = glued to the screen).</summary>
    [Export] public float BackScrollScale { get; set; } = 0.6f;

    /// <summary>World width the camera shows (viewport width / camera zoom) — the far layer must cover it at every camera x inside the room.</summary>
    [Export] public float ViewWidth { get; set; } = 1280f;

    /// <summary>Extra far-layer coverage on each side, in world px, for camera look-ahead and shake.</summary>
    [Export] public float BackMargin { get; set; } = 320f;

    // ---- depth ------------------------------------------------------------------------------------

    /// <summary>z_index of the far layer (visual brief: parallax background −100…−60).</summary>
    [Export] public int BackZ { get; set; } = -80;

    /// <summary>z_index of the wall layer (visual brief: room background, walls −40).</summary>
    [Export] public int MidZ { get; set; } = -40;

    /// <summary>z_index of the floor layer (visual brief: floor and decals −20).</summary>
    [Export] public int FloorZ { get; set; } = -20;

    /// <summary>Node scale applied to every sprite: world px per texture px.</summary>
    public float LayerScale => WorldScale / ImportScale;

    /// <summary>World y of every sprite's top edge: puts mockup y <see cref="DrawnFloorTop"/> on <see cref="FloorFarEdgeY"/>.</summary>
    public float OffsetY => FloorFarEdgeY - DrawnFloorTop * WorldScale;

    public override void _Ready()
    {
        var back = new Parallax2D { Name = BackName, ZIndex = BackZ, ScrollScale = new Vector2(BackScrollScale, 1f) };
        var mid = new Node2D { Name = MidName, ZIndex = MidZ };
        var floor = new Node2D { Name = FloorName, ZIndex = FloorZ };
        AddChild(back);
        AddChild(mid);
        AddChild(floor);

        BuildBack(back);
        BuildLayer(mid, MidTexture, LeftFillTexture ?? MidTexture, LeftFillSlice, RightFillTexture ?? MidTexture, RightFillSlice);
        BuildLayer(floor, FloorTexture, FloorFillTexture ?? FloorTexture, FloorFillSlice, FloorFillTexture ?? FloorTexture, FloorFillSlice);
    }

    /// <summary>
    /// Tiles <see cref="BackSlice"/> on a grid anchored at world x = 0 across the span the far
    /// layer must cover for this room. With follow-viewport parallax a tile at base x <c>b</c> shows
    /// at <c>b + o·(1 − s)</c> for camera left edge <c>o</c>, so covering the screen for every
    /// <c>o</c> inside the room needs base x from <c>s·room.left</c> to <c>s·room.right + (1 − s)·view</c>.
    /// </summary>
    private void BuildBack(Parallax2D back)
    {
        if (BackTexture == null)
        {
            return;
        }
        float period = (BackSlice.Y - BackSlice.X) * WorldScale;
        if (period <= 0f)
        {
            return;
        }
        float roomLeft = GlobalPosition.X;
        float roomRight = roomLeft + RoomWidth;
        float s = BackScrollScale;
        float spanFrom = s * roomLeft - BackMargin;
        float spanTo = s * roomRight + (1f - s) * ViewWidth + BackMargin;
        int first = Mathf.FloorToInt(spanFrom / period);
        int last = Mathf.CeilToInt(spanTo / period) - 1;
        int index = 0;
        for (int k = first; k <= last; k++)
        {
            float worldX = k * period - roomLeft;
            AddSlice(back, BackTexture, BackSlice.X, BackSlice.Y, worldX, $"Tile_{index}", float.NegativeInfinity, float.PositiveInfinity);
            index++;
        }
    }

    /// <summary>The whole section at <see cref="SectionX"/>, then left and right slices until <see cref="FillFrom"/>…<see cref="FillTo"/> is covered.</summary>
    private void BuildLayer(Node2D layer, Texture2D? section, Texture2D? leftFill, Vector2 leftSlice, Texture2D? rightFill, Vector2 rightSlice)
    {
        if (section == null)
        {
            return;
        }
        float sectionWidth = section.GetWidth() / ImportScale;
        AddSlice(layer, section, 0f, sectionWidth, SectionX, "Section", FillFrom, FillTo);

        if (leftFill != null)
        {
            float width = (leftSlice.Y - leftSlice.X) * WorldScale;
            int i = 1;
            for (float x = SectionX - width; width > 0f && x + width > FillFrom; x -= width)
            {
                AddSlice(layer, leftFill, leftSlice.X, leftSlice.Y, x, $"Fill_L{i}", FillFrom, FillTo);
                i++;
            }
        }
        if (rightFill != null)
        {
            float width = (rightSlice.Y - rightSlice.X) * WorldScale;
            int i = 1;
            for (float x = SectionX + sectionWidth * WorldScale; width > 0f && x < FillTo; x += width)
            {
                AddSlice(layer, rightFill, rightSlice.X, rightSlice.Y, x, $"Fill_R{i}", FillFrom, FillTo);
                i++;
            }
        }
    }

    /// <summary>
    /// One region sprite showing mockup columns <paramref name="fromX"/>…<paramref name="toX"/> of
    /// <paramref name="texture"/> with its left edge at <paramref name="worldX"/>, cropped to
    /// <paramref name="clipFrom"/>…<paramref name="clipTo"/> (relative world x). Skipped when
    /// nothing is left.
    /// </summary>
    private void AddSlice(Node2D parent, Texture2D texture, float fromX, float toX, float worldX, string name, float clipFrom, float clipTo)
    {
        if (worldX < clipFrom)
        {
            fromX += (clipFrom - worldX) / WorldScale;
            worldX = clipFrom;
        }
        float overshoot = worldX + (toX - fromX) * WorldScale - clipTo;
        if (overshoot > 0f)
        {
            toX -= overshoot / WorldScale;
        }
        if (toX <= fromX)
        {
            return;
        }
        var sprite = new Sprite2D
        {
            Name = name,
            Texture = texture,
            Centered = false,
            RegionEnabled = true,
            RegionFilterClipEnabled = true,
            RegionRect = new Rect2(fromX * ImportScale, 0f, (toX - fromX) * ImportScale, texture.GetHeight()),
            Position = new Vector2(worldX, OffsetY),
            Scale = new Vector2(LayerScale, LayerScale),
        };
        parent.AddChild(sprite);
    }
}
