using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Ui;

/// <summary>
/// The text before the game (GAME_DESIGN §1 «Рік і експозиція», §3 «Експозиція»): a few screens
/// about 2073 on a black ground, then the run starts. Sits between the main menu and
/// <c>Main</c> on the «New Game» path only — <c>Main</c> is the current scene once the run is
/// on, so a level restart (<c>ReloadCurrentScene</c>) or a checkpoint respawn never shows the
/// exposition again. Plays <see cref="Lines"/> through the shared <see cref="Cutscene"/> overlay
/// and changes the scene to <see cref="NextScenePath"/> — or to <see cref="NextScenePathV2"/>
/// when <see cref="GameSettings.GameVersion"/> is <see cref="GameVersion.V2"/> (GAME_DESIGN §6a;
/// this is the one place in the run that branches on the version) — when it finishes; an empty
/// <see cref="Lines"/> goes straight on. No <c>GameState</c> access and no input of its own.
/// </summary>
public partial class Exposition : Node
{
    /// <summary>The screens, one string each, from <c>script-en.md</c> (<c>CUT_EXPOSITION</c>).</summary>
    [Export] public string[] Lines { get; set; } = System.Array.Empty<string>();

    /// <summary>Scene made current once the last screen is dismissed — where a v1 run starts.</summary>
    [Export(PropertyHint.File, "*.tscn")]
    public string NextScenePath { get; set; } = "res://scenes/Main.tscn";

    /// <summary>Where a v2 run starts instead; empty falls back to <see cref="NextScenePath"/>.</summary>
    [Export(PropertyHint.File, "*.tscn")]
    public string NextScenePathV2 { get; set; } = "res://scenes/v2/Main.tscn";

    /// <summary>Whether <c>interact</c>/<c>attack</c> advance the screens; forwarded to the overlay.</summary>
    [Export] public bool Skippable { get; set; } = true;

    /// <summary>The text overlay instanced in this scene.</summary>
    [Export] public Cutscene Cutscene { get; set; } = null!;

    /// <inheritdoc/>
    public override void _Ready()
    {
        Cutscene.Skippable = Skippable;
        Cutscene.Finished += OnFinished;
        Cutscene.Play(Lines);
    }

    /// <inheritdoc/>
    public override void _ExitTree() => Cutscene.Finished -= OnFinished;

    private void OnFinished() => GetTree().CallDeferred(SceneTree.MethodName.ChangeSceneToFile, PickNextScene());

    /// <summary>The run entry for the version the player chose; v1 when the autoload is missing.</summary>
    private string PickNextScene()
    {
        bool v2 = GameSettings.Instance is { GameVersion: GameVersion.V2 } && NextScenePathV2.Length > 0;
        return v2 ? NextScenePathV2 : NextScenePath;
    }
}
