using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid;

/// <summary>
/// Entry point of the game (<c>run/main_scene</c>): instantiates <see cref="StartLevel"/> as its
/// child and records it in <see cref="GameState.CurrentScenePath"/>. Being the current scene, a
/// <c>ReloadCurrentScene</c> issued by a level's KO restart reloads <c>Main</c>, which builds the
/// level again; a level change (<c>LevelBase.GoToLevel</c>) replaces <c>Main</c> with the next
/// level. Resuming a saved run from <c>CurrentScenePath</c> is T-09.
/// </summary>
public partial class Main : Node
{
    /// <summary>Level loaded at start.</summary>
    [Export] public PackedScene StartLevel { get; set; } = null!;

    /// <summary>The level instance built in <see cref="_Ready"/>; <c>null</c> when <see cref="StartLevel"/> is unset.</summary>
    public Node? CurrentLevel { get; private set; }

    /// <inheritdoc/>
    public override void _Ready()
    {
        if (StartLevel is null)
        {
            GD.PushError($"{Name}: StartLevel is not set; nothing to play.");
            return;
        }

        Node level = StartLevel.Instantiate();
        AddChild(level);
        CurrentLevel = level;
        GameState.Instance.CurrentScenePath = StartLevel.ResourcePath;
    }
}
