using Godot;

namespace BlackoutLastGrid.Core;

/// <summary>
/// Autoload holding the machine preferences — window mode and master volume — persisted to
/// <see cref="ConfigPath"/> with a <see cref="ConfigFile"/>.
/// Registered in project.godot as "GameSettings". It is the only place that calls
/// <c>DisplayServer.WindowSetMode</c> or <c>AudioServer</c> for the master bus and the only owner
/// of the global <c>toggle_fullscreen</c> hotkey, so the settings screen and the hotkey can never
/// disagree. This is not run state (that lives in <see cref="GameState"/> and is reset by
/// «New Game»): these values are per machine, survive a new run and are never written into a
/// save slot.
/// </summary>
public partial class GameSettings : Node
{
    private static readonly StringName ActionToggleFullscreen = "toggle_fullscreen";

    /// <summary>Name of the headless display driver; window calls are skipped under it.</summary>
    private const string HeadlessDisplayDriver = "headless";

    private const string SectionDisplay = "display";
    private const string SectionAudio = "audio";
    private const string KeyFullscreen = "fullscreen";
    private const string KeyMasterVolume = "master_volume";

    /// <summary>Index of the always-present <c>Master</c> audio bus.</summary>
    private const int MasterBus = 0;

    /// <summary>Globally accessible instance, assigned when the autoload enters the tree.</summary>
    public static GameSettings Instance { get; private set; } = null!;

    /// <summary>Emitted when <see cref="Fullscreen"/> actually changes.</summary>
    [Signal]
    public delegate void FullscreenChangedEventHandler(bool fullscreen);

    /// <summary>Emitted when <see cref="MasterVolume"/> actually changes; the payload is linear 0…1.</summary>
    [Signal]
    public delegate void MasterVolumeChangedEventHandler(float volume);

    /// <summary>
    /// Where the preferences live. Settable at runtime so a smoke test can redirect it to a
    /// throwaway file instead of the player's own settings.
    /// </summary>
    [Export] public string ConfigPath { get; set; } = "user://settings.cfg";

    /// <summary>Window mode used when <see cref="ConfigPath"/> does not exist yet.</summary>
    [Export] public bool DefaultFullscreen { get; set; } = true;

    /// <summary>Master volume (linear 0…1) used when <see cref="ConfigPath"/> does not exist yet.</summary>
    [Export] public float DefaultMasterVolume { get; set; } = 0.8f;

    /// <summary>Linear volume at or below which the master bus is muted instead of set to −∞ dB.</summary>
    [Export] public float MuteThreshold { get; set; } = 0.001f;

    private bool _fullscreen = true;
    private float _masterVolume = 0.8f;

    /// <summary>
    /// <c>true</c> while the game runs fullscreen. Setting it <b>always</b> applies the mode to
    /// the window (skipped under <c>--headless</c>, where the stored value still changes) and
    /// emits <see cref="FullscreenChangedEventHandler"/> only when the value really changed. The
    /// apply is deliberately not gated on the change: <see cref="Load"/> assigns values that
    /// often equal the current ones, and they must still reach the window and the audio bus.
    /// </summary>
    public bool Fullscreen
    {
        get => _fullscreen;
        set
        {
            bool changed = value != _fullscreen;
            _fullscreen = value;
            ApplyFullscreen();
            if (changed)
            {
                EmitSignalFullscreenChanged(_fullscreen);
            }
        }
    }

    /// <summary>
    /// Master volume as a linear 0…1 factor, clamped on set. Setting it <b>always</b> applies the
    /// volume to the master bus (see <see cref="Fullscreen"/> for why the apply is not gated on
    /// the change) and emits <see cref="MasterVolumeChangedEventHandler"/> only on a real change.
    /// </summary>
    public float MasterVolume
    {
        get => _masterVolume;
        set
        {
            float clamped = Mathf.Clamp(value, 0f, 1f);
            bool changed = !Mathf.IsEqualApprox(clamped, _masterVolume);
            _masterVolume = clamped;
            ApplyMasterVolume();
            if (changed)
            {
                EmitSignalMasterVolumeChanged(_masterVolume);
            }
        }
    }

    /// <inheritdoc/>
    public override void _EnterTree()
    {
        Instance = this;
        ProcessMode = ProcessModeEnum.Always;
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        if (ReferenceEquals(Instance, this))
        {
            Instance = null!;
        }
    }

    /// <inheritdoc/>
    public override void _Ready()
    {
        Load();
        SetProcessUnhandledInput(true);
    }

    /// <inheritdoc/>
    public override void _UnhandledInput(InputEvent @event)
    {
        // _UnhandledInput runs after GUI input, so a focused Button keeps its own keys.
        if (!@event.IsActionPressed(ActionToggleFullscreen))
        {
            return;
        }

        ToggleFullscreen();
        Save();
        GetViewport().SetInputAsHandled();
    }

    /// <summary>Flips <see cref="Fullscreen"/> between fullscreen and windowed.</summary>
    public void ToggleFullscreen() => Fullscreen = !_fullscreen;

    /// <summary>
    /// Reads the preferences from <see cref="ConfigPath"/> and applies them. A missing or broken
    /// file is normal (first launch) and falls back to <see cref="DefaultFullscreen"/>,
    /// <see cref="DefaultMasterVolume"/> without logging an error.
    /// </summary>
    public void Load()
    {
        var config = new ConfigFile();
        if (config.Load(ConfigPath) != Error.Ok)
        {
            Fullscreen = DefaultFullscreen;
            MasterVolume = DefaultMasterVolume;
            return;
        }

        Fullscreen = config.GetValue(SectionDisplay, KeyFullscreen, DefaultFullscreen).AsBool();
        MasterVolume = config.GetValue(SectionAudio, KeyMasterVolume, DefaultMasterVolume).AsSingle();
    }

    /// <summary>Writes the current preferences to <see cref="ConfigPath"/>; a write error warns, never throws.</summary>
    public void Save()
    {
        var config = new ConfigFile();
        config.SetValue(SectionDisplay, KeyFullscreen, _fullscreen);
        config.SetValue(SectionAudio, KeyMasterVolume, _masterVolume);

        Error error = config.Save(ConfigPath);
        if (error != Error.Ok)
        {
            GD.PushWarning($"{Name}: could not write '{ConfigPath}' ({error}); settings stay for this session only.");
        }
    }

    /// <summary>Applies the stored window mode; a no-op under the headless display driver.</summary>
    private void ApplyFullscreen()
    {
        if (DisplayServer.GetName() == HeadlessDisplayDriver)
        {
            return;
        }

        DisplayServer.WindowSetMode(_fullscreen
            ? DisplayServer.WindowMode.Fullscreen
            : DisplayServer.WindowMode.Windowed);
    }

    /// <summary>Applies the stored volume to the master bus, muting it instead of going to −∞ dB.</summary>
    private void ApplyMasterVolume()
    {
        bool mute = _masterVolume <= MuteThreshold;
        AudioServer.SetBusMute(MasterBus, mute);
        AudioServer.SetBusVolumeDb(MasterBus, Mathf.LinearToDb(Mathf.Max(_masterVolume, MuteThreshold)));
    }
}
