using BlackoutLastGrid.Art;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>Body proportions of a <see cref="CharacterRig"/>; characters differ by colour and build, not by scene.</summary>
public enum BuildKind
{
    /// <summary>Narrow and slightly taller — Dan.</summary>
    Slim,

    /// <summary>The reference proportions the rig scene is authored in — Rey, the training dummy.</summary>
    Normal,

    /// <summary>Broad and slightly shorter — the guards.</summary>
    Heavy,
}

/// <summary>
/// The shared procedural human silhouette used by every character (hero, guards, training
/// dummy, Dan). Pure graphics: a child of the character's <c>Visual</c> node, it owns no
/// <c>Area2D</c>, no collision shape and no <c>AnimationPlayer</c> — animation lives on each
/// character's own player and drives the parts by node path.
/// </summary>
/// <remarks>
/// The rig's local origin is the <c>Visual</c> origin: the body centre, feet at <c>y = +36</c>,
/// top of the head at <c>y = -36</c>. Part polygons are authored in <c>CharacterRig.tscn</c> for
/// the <see cref="BuildKind.Normal"/> build so the scene previews correctly in the editor;
/// <see cref="Apply"/> paints them and stretches them to <see cref="Build"/>. Only the front arm
/// is rebuilt at runtime, because the attack animations drag its hand from 13 px to 46 px away
/// from the shoulder and a fixed sleeve would either tear off or stretch into a sausage.
/// Facing is not the rig's business: the owning <c>Visual</c> mirrors the whole rig through
/// <c>scale.x</c>, so this class must never write <c>scale.x</c> on itself.
/// </remarks>
public partial class CharacterRig : Node2D
{
    /// <summary>Vertices on the hand arc, swept from one side of the forearm to the other.</summary>
    private const int HandArcPoints = 7;

    /// <summary>Hand arc plus the two shoulder vertices that close the forearm.</summary>
    private const int ArmVertexCount = HandArcPoints + 2;

    /// <summary>
    /// Process priority of the rig. Idle-frame callbacks run in priority order and then in tree
    /// order; the character's <c>AnimationPlayer</c> is a sibling of <c>Visual</c> at the default
    /// priority 0, so at 0 the rig would rebuild the front arm from the *previous* frame's fist
    /// position and the forearm would trail the hand by up to ~14 px during a punch. Anything
    /// above 0 puts the rig after every default-priority node, the animation player included.
    /// </summary>
    private const int AfterAnimationPriority = 1;

    /// <summary>Per-build stretch factors, indexed by <see cref="BuildKind"/>.</summary>
    private static readonly BuildFactors[] Builds =
    {
        new(new Vector2(0.88f, 1.02f), 0.85f, 0.88f),   // Slim
        new(new Vector2(1.00f, 1.00f), 1.00f, 1.00f),   // Normal
        new(new Vector2(1.18f, 0.97f), 1.20f, 1.18f),   // Heavy
    };

    /// <summary>Torso and limbs (each part shaded from it); the character's main colour.</summary>
    [Export] public Color SuitColor { get; set; } = Palette.SteelCold;

    /// <summary>Head and hand.</summary>
    [Export] public Color SkinColor { get; set; } = Palette.SkinWarm;

    /// <summary>Silhouette contour and the face wedge.</summary>
    [Export] public Color OutlineColor { get; set; } = Palette.OutlineDark;

    /// <summary>Body proportions.</summary>
    [Export] public BuildKind Build { get; set; } = BuildKind.Normal;

    /// <summary>Thickness of the silhouette contour, in px (2 px for characters per the visual brief).</summary>
    [Export] public float OutlineWidth { get; set; } = 2f;

    /// <summary><c>false</c> hides the face wedge — the training dummy is a faceless mannequin.</summary>
    [Export] public bool ShowFace { get; set; } = true;

    /// <summary>Multiplier applied to <see cref="SuitColor"/> for the far-side arm and leg (alpha kept).</summary>
    [Export] public float BackLimbShade { get; set; } = 0.60f;

    /// <summary>Multiplier applied to <see cref="SuitColor"/> for the near-side leg (alpha kept).</summary>
    [Export] public float FrontLimbShade { get; set; } = 0.85f;

    /// <summary>Rig-local origin of the front arm, in px; the rebuilt forearm always reaches back to it.</summary>
    [Export] public Vector2 ShoulderAnchor { get; set; } = new(2f, -16f);

    /// <summary>Half-thickness of the forearm at the shoulder, in px (scaled by the build's limb width).</summary>
    [Export] public float ArmWidth { get; set; } = 5f;

    /// <summary>Radius of the hand, in px (scaled by the build's limb width).</summary>
    [Export] public float HandRadius { get; set; } = 6.5f;

    /// <summary>Far-side leg; hip pivot, rotated by walk and jump.</summary>
    [Export] public Polygon2D LegBack { get; set; } = null!;

    /// <summary>Far-side arm; shoulder pivot, rotated by idle, walk and jump.</summary>
    [Export] public Polygon2D ArmBack { get; set; } = null!;

    /// <summary>Chest and hips; breathes and bobs.</summary>
    [Export] public Polygon2D Torso { get; set; } = null!;

    /// <summary>Near-side leg; hip pivot.</summary>
    [Export] public Polygon2D LegFront { get; set; } = null!;

    /// <summary>Head.</summary>
    [Export] public Polygon2D Head { get; set; } = null!;

    /// <summary>Dark brow wedge on the facing side of the head — the gaze direction.</summary>
    [Export] public Polygon2D Face { get; set; } = null!;

    /// <summary>Pivot of the front arm; sits at the rig origin so the animated fist keys stay unchanged.</summary>
    [Export] public Node2D ArmFront { get; set; } = null!;

    /// <summary>Hand and forearm in one polygon, rebuilt whenever the animation moves it.</summary>
    [Export] public Polygon2D Fist { get; set; } = null!;

    /// <summary>Closed contour around head and torso.</summary>
    [Export] public Line2D Outline { get; set; } = null!;

    private readonly Vector2[] _armPoints = new Vector2[ArmVertexCount];
    private Vector2 _baseLegBack;
    private Vector2 _baseLegFront;
    private Vector2 _baseArmBack;
    private bool _basesCaptured;
    private float _limbWidth = 1f;
    private Vector2 _lastFistPosition;
    private bool _armDirty = true;

    /// <inheritdoc/>
    public override void _Ready()
    {
        ProcessPriority = AfterAnimationPriority;
        Apply();
    }

    /// <summary>
    /// Re-applies colours and <see cref="Build"/> to every part. Idempotent: the limb attach
    /// points are always derived from the positions the scene was authored with, never from the
    /// current ones, so calling this twice does not compound the stretch.
    /// </summary>
    public void Apply()
    {
        CaptureBasePositions();
        BuildFactors factors = Builds[(int)Build];
        _limbWidth = factors.LimbWidth;

        Torso.Color = SuitColor;
        LegFront.Color = Shade(SuitColor, FrontLimbShade);
        LegBack.Color = Shade(SuitColor, BackLimbShade);
        ArmBack.Color = Shade(SuitColor, BackLimbShade);
        Head.Color = SkinColor;
        Fist.Color = SkinColor;
        Face.Color = OutlineColor;
        Face.Visible = ShowFace;
        Outline.DefaultColor = OutlineColor;
        Outline.Width = OutlineWidth;

        // The head keeps its authored position: an idle animation owns Head:position and would
        // erase a build offset every frame. Scaling the node alone drifts its centre by <1 px.
        Torso.Scale = factors.Body;
        Head.Scale = factors.Body;
        Outline.Scale = factors.Body;

        StretchLimb(LegBack, _baseLegBack, factors);
        StretchLimb(LegFront, _baseLegFront, factors);
        StretchLimb(ArmBack, _baseArmBack, factors);

        _armDirty = true;
    }

    /// <inheritdoc/>
    public override void _Process(double delta)
    {
        // Visual only, so _Process and not _PhysicsProcess; delta is deliberately unused because
        // hit-stop delivers frames with delta == 0 while the fist is frozen mid-swing. Runs after
        // the AnimationPlayer thanks to AfterAnimationPriority, so the fist position read here is
        // this frame's, not the previous one's.
        Vector2 fistPosition = Fist.Position;
        if (!_armDirty && fistPosition == _lastFistPosition)
        {
            return;
        }

        _lastFistPosition = fistPosition;
        _armDirty = false;
        RebuildFrontArm(fistPosition);
    }

    /// <summary>
    /// Writes the hand-plus-forearm polygon for the current fist position: a hand arc around the
    /// fist origin closed by two vertices at <see cref="ShoulderAnchor"/>. Reuses one buffer, so
    /// nothing is allocated per frame.
    /// </summary>
    /// <param name="fistPosition">Rig-local position of the fist this frame.</param>
    private void RebuildFrontArm(Vector2 fistPosition)
    {
        Vector2 anchor = ShoulderAnchor - fistPosition;   // shoulder, in the fist's local space
        Vector2 direction = anchor.LengthSquared() > 0.0001f ? (-anchor).Normalized() : Vector2.Right;
        Vector2 normal = new(-direction.Y, direction.X);
        float halfWidth = ArmWidth * _limbWidth;
        float radius = HandRadius * _limbWidth;
        float step = Mathf.Pi / (HandArcPoints - 1);

        _armPoints[0] = anchor + normal * halfWidth;
        for (int i = 0; i < HandArcPoints; i++)
        {
            float angle = Mathf.Pi / 2f - i * step;   // from the +normal side round the hand to -normal
            _armPoints[i + 1] = direction * (radius * Mathf.Cos(angle)) + normal * (radius * Mathf.Sin(angle));
        }

        _armPoints[ArmVertexCount - 1] = anchor - normal * halfWidth;
        Fist.Polygon = _armPoints;
    }

    /// <summary>Remembers the authored limb attach points once, so <see cref="Apply"/> stays idempotent.</summary>
    private void CaptureBasePositions()
    {
        if (_basesCaptured)
        {
            return;
        }

        _baseLegBack = LegBack.Position;
        _baseLegFront = LegFront.Position;
        _baseArmBack = ArmBack.Position;
        _basesCaptured = true;
    }

    /// <summary>Moves a limb's attach point outwards and widens it for <paramref name="factors"/>.</summary>
    /// <param name="limb">Leg or arm whose pivot sits at the hip/shoulder.</param>
    /// <param name="basePosition">The position the scene was authored with.</param>
    /// <param name="factors">Stretch factors of the current build.</param>
    private static void StretchLimb(Polygon2D limb, Vector2 basePosition, in BuildFactors factors)
    {
        limb.Position = new Vector2(basePosition.X * factors.LimbAttach, basePosition.Y);
        limb.Scale = new Vector2(factors.LimbWidth, 1f);
    }

    /// <summary>Darkens <paramref name="color"/> by <paramref name="factor"/>, keeping its alpha.</summary>
    private static Color Shade(Color color, float factor) =>
        new(color.R * factor, color.G * factor, color.B * factor, color.A);

    /// <summary>Stretch factors of one <see cref="BuildKind"/>.</summary>
    /// <param name="Body">Scale of torso, head and outline.</param>
    /// <param name="LimbWidth">Horizontal scale of the limbs, and of the rebuilt front arm.</param>
    /// <param name="LimbAttach">Multiplier of the limbs' authored attach offset along X.</param>
    private readonly record struct BuildFactors(Vector2 Body, float LimbWidth, float LimbAttach);
}
