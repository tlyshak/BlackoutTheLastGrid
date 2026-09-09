using System.Collections.Generic;
using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Ui;

/// <summary>
/// Title screen and <c>run/main_scene</c>: the logo from GAME_DESIGN.md §8 — the word BLACKOUT
/// with one letter glowing like the single lit window in a dark block, built procedurally from
/// Labels and an additive halo — plus «Нова гра» / «Налаштування» / «Вихід» and its own settings
/// overlay. «Нова гра» changes the tree's scene to <see cref="NewGameScenePath"/>, so <c>Main</c>
/// becomes the current scene and a KO still reloads the run through it. The run entry point is a
/// path, not an <c>[Export] PackedScene</c> as elsewhere, on purpose: a PackedScene reference
/// would pull the whole prologue into this scene's load graph before the menu could draw.
/// </summary>
public partial class MainMenu : Control
{
    /// <summary>Name of the halo node added under the glowing letter.</summary>
    private const string GlowNodeName = "Glow";

    /// <summary>Row the logo letters are built into.</summary>
    [Export] public HBoxContainer LogoRow { get; set; } = null!;

    /// <summary>Button that starts a fresh run.</summary>
    [Export] public Button NewGameButton { get; set; } = null!;

    /// <summary>Button that opens <see cref="Settings"/>.</summary>
    [Export] public Button SettingsButton { get; set; } = null!;

    /// <summary>Button that quits the game.</summary>
    [Export] public Button QuitButton { get; set; } = null!;

    /// <summary>The settings overlay instanced under this menu.</summary>
    [Export] public SettingsMenu Settings { get; set; } = null!;

    /// <summary>Scene made the current scene by «Нова гра» — the run entry point.</summary>
    [Export(PropertyHint.File, "*.tscn")]
    public string NewGameScenePath { get; set; } = "res://scenes/Main.tscn";

    /// <summary>Word shown as the logo, one Label per character.</summary>
    [Export] public string TitleText { get; set; } = "BLACKOUT";

    /// <summary>0-based index of the lit letter; clamped to the last character.</summary>
    [Export] public int GlowLetterIndex { get; set; } = 5;

    /// <summary>Font size of the logo letters, in pixels.</summary>
    [Export] public int LetterFontSize { get; set; } = 112;

    /// <summary>Gap between the logo letters, in pixels.</summary>
    [Export] public int LetterSpacing { get; set; } = 6;

    /// <summary>Colour of the unlit letters.</summary>
    [Export] public Color TitleColor { get; set; } = new("e6e1d0");

    /// <summary>Colour of the lit letter's glyph (EnergyPale).</summary>
    [Export] public Color GlowLetterColor { get; set; } = new("ffd98a");

    /// <summary>Colour of the halo behind the lit letter (EnergyAmber).</summary>
    [Export] public Color GlowColor { get; set; } = new("f0a326");

    /// <summary>Radial texture used for the halo; a gradient sub-resource of the scene.</summary>
    [Export] public Texture2D GlowTexture { get; set; } = null!;

    /// <summary>Size of the halo box around the lit letter, in pixels.</summary>
    [Export] public Vector2 GlowSize { get; set; } = new(220f, 220f);

    /// <summary>Seconds of one full dim→bright→dim pulse of the halo.</summary>
    [Export] public float GlowPulsePeriod { get; set; } = 2.4f;

    /// <summary>Halo alpha at the dim end of the pulse.</summary>
    [Export] public float GlowMinAlpha { get; set; } = 0.45f;

    /// <summary>Halo alpha at the bright end of the pulse.</summary>
    [Export] public float GlowMaxAlpha { get; set; } = 1f;

    private readonly List<Label> _letters = new();
    private Tween? _glowTween;

    /// <summary>The logo letters, in reading order.</summary>
    public IReadOnlyList<Label> Letters => _letters;

    /// <summary>The lit letter, or <c>null</c> while the logo is not built.</summary>
    public Label? GlowLetter { get; private set; }

    /// <inheritdoc/>
    public override void _Ready()
    {
        BuildLogo();

        NewGameButton.Pressed += OnNewGamePressed;
        SettingsButton.Pressed += OnSettingsPressed;
        QuitButton.Pressed += OnQuitPressed;
        Settings.Closed += OnSettingsClosed;

        NewGameButton.GrabFocus();   // keyboard and gamepad work without touching the mouse
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        NewGameButton.Pressed -= OnNewGamePressed;
        SettingsButton.Pressed -= OnSettingsPressed;
        QuitButton.Pressed -= OnQuitPressed;
        Settings.Closed -= OnSettingsClosed;

        if (_glowTween is not null)
        {
            _glowTween.Kill();
            _glowTween = null;
        }
    }

    private void BuildLogo()
    {
        LogoRow.AddThemeConstantOverride("separation", LetterSpacing);
        int glowIndex = Mathf.Clamp(GlowLetterIndex, 0, Mathf.Max(TitleText.Length - 1, 0));

        for (int i = 0; i < TitleText.Length; i++)
        {
            bool lit = i == glowIndex;
            var letter = new Label
            {
                Name = $"Letter{i}",
                Text = TitleText[i].ToString(),
                MouseFilter = MouseFilterEnum.Ignore,
            };
            letter.AddThemeFontSizeOverride("font_size", LetterFontSize);
            letter.AddThemeColorOverride("font_color", lit ? GlowLetterColor : TitleColor);
            LogoRow.AddChild(letter);
            _letters.Add(letter);

            if (!lit)
            {
                continue;
            }

            GlowLetter = letter;
            StartGlow(AddGlow(letter));
        }
    }

    private TextureRect AddGlow(Label letter)
    {
        var glow = new TextureRect
        {
            Name = GlowNodeName,
            Texture = GlowTexture,
            ExpandMode = TextureRect.ExpandModeEnum.IgnoreSize,
            CustomMinimumSize = GlowSize,
            ShowBehindParent = true,
            MouseFilter = MouseFilterEnum.Ignore,
            Modulate = new Color(GlowColor, GlowMaxAlpha),
            Material = new CanvasItemMaterial { BlendMode = CanvasItemMaterial.BlendModeEnum.Add },
        };

        // Anchored to the letter's centre, so the halo stays put once the container lays out.
        glow.AnchorLeft = 0.5f;
        glow.AnchorTop = 0.5f;
        glow.AnchorRight = 0.5f;
        glow.AnchorBottom = 0.5f;
        glow.OffsetLeft = -GlowSize.X * 0.5f;
        glow.OffsetTop = -GlowSize.Y * 0.5f;
        glow.OffsetRight = GlowSize.X * 0.5f;
        glow.OffsetBottom = GlowSize.Y * 0.5f;

        letter.AddChild(glow);
        return glow;
    }

    private void StartGlow(TextureRect glow)
    {
        float half = Mathf.Max(GlowPulsePeriod, 0.1f) * 0.5f;
        _glowTween = CreateTween().SetLoops();
        _glowTween.TweenProperty(glow, "modulate:a", GlowMinAlpha, half).SetTrans(Tween.TransitionType.Sine);
        _glowTween.TweenProperty(glow, "modulate:a", GlowMaxAlpha, half).SetTrans(Tween.TransitionType.Sine);
    }

    private void OnNewGamePressed()
    {
        GameState.Instance.ResetRun();   // a new run never inherits the energy of an abandoned one
        SceneTree tree = GetTree();
        tree.Paused = false;             // defensive: the menu is never reached paused
        tree.CallDeferred(SceneTree.MethodName.ChangeSceneToFile, NewGameScenePath);
    }

    private void OnSettingsPressed() => Settings.Open();

    private void OnSettingsClosed() => SettingsButton.GrabFocus();

    private void OnQuitPressed() => GetTree().Quit();
}
