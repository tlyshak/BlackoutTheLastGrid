using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Ui;

/// <summary>
/// Settings overlay: the fullscreen checkbox, the master-volume slider and the game-version
/// dropdown, all bound to the <see cref="GameSettings"/> autoload. The scene is instanced once under the main menu and once
/// under the pause menu — each host owns its instance and its visibility, so no menu has to reach
/// across the tree for a shared one. Runs with <see cref="Node.ProcessModeEnum.Always"/> and on a
/// layer above the pause menu, so it also works while the tree is paused. Preferences are written
/// to disk on <see cref="Close"/>.
/// </summary>
public partial class SettingsMenu : CanvasLayer
{
    private static readonly StringName ActionCancel = "ui_cancel";
    private static readonly StringName ActionPause = "pause";

    /// <summary>Emitted after the overlay closed, so the host can restore its own focus.</summary>
    [Signal]
    public delegate void ClosedEventHandler();

    /// <summary>Overlay root, hidden while the screen is closed.</summary>
    [Export] public Control Root { get; set; } = null!;

    /// <summary>Checkbox bound to <see cref="GameSettings.Fullscreen"/>.</summary>
    [Export] public CheckBox FullscreenCheck { get; set; } = null!;

    /// <summary>Slider bound to <see cref="GameSettings.MasterVolume"/> (linear 0…1).</summary>
    [Export] public HSlider VolumeSlider { get; set; } = null!;

    /// <summary>Label showing the slider value.</summary>
    [Export] public Label VolumeValue { get; set; } = null!;

    /// <summary>Dropdown bound to <see cref="GameSettings.GameVersion"/>; each item's id is the enum value.</summary>
    [Export] public OptionButton VersionOption { get; set; } = null!;

    /// <summary>Button that closes the screen.</summary>
    [Export] public Button BackButton { get; set; } = null!;

    /// <summary>Format of <see cref="VolumeValue"/>; {0} is the volume as a whole percent (an <c>int</c>).</summary>
    [Export] public string VolumeFormat { get; set; } = "{0} %";

    private GameSettings? _settings;
    private int _shownPercent = int.MinValue;

    /// <summary><c>true</c> while the overlay is on screen.</summary>
    public bool IsOpen => Root.Visible;

    /// <inheritdoc/>
    public override void _Ready()
    {
        ProcessMode = ProcessModeEnum.Always;
        Root.Visible = false;
        SetProcessUnhandledInput(false);

        FullscreenCheck.Toggled += OnFullscreenToggled;
        VolumeSlider.ValueChanged += OnVolumeSliderChanged;
        VersionOption.ItemSelected += OnVersionSelected;
        BackButton.Pressed += Close;

        _settings = GameSettings.Instance;
        if (_settings is null)
        {
            GD.PushWarning($"{Name}: GameSettings autoload is missing; the settings screen will not change anything.");
            return;
        }

        _settings.FullscreenChanged += OnFullscreenChanged;
        _settings.MasterVolumeChanged += OnMasterVolumeChanged;
        _settings.GameVersionChanged += OnGameVersionChanged;
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        FullscreenCheck.Toggled -= OnFullscreenToggled;
        VolumeSlider.ValueChanged -= OnVolumeSliderChanged;
        VersionOption.ItemSelected -= OnVersionSelected;
        BackButton.Pressed -= Close;

        if (_settings is null)
        {
            return;
        }

        _settings.FullscreenChanged -= OnFullscreenChanged;
        _settings.MasterVolumeChanged -= OnMasterVolumeChanged;
        _settings.GameVersionChanged -= OnGameVersionChanged;
        _settings = null;
    }

    /// <inheritdoc/>
    public override void _UnhandledInput(InputEvent @event)
    {
        // Escape is both `ui_cancel` and `pause`: consuming it here keeps the press from reaching
        // the pause menu behind this overlay.
        if (!@event.IsActionPressed(ActionCancel) && !@event.IsActionPressed(ActionPause))
        {
            return;
        }

        Close();
        GetViewport().SetInputAsHandled();
    }

    /// <summary>Shows the screen with the preferences the autoload currently holds.</summary>
    public void Open()
    {
        SyncFromSettings();
        Root.Visible = true;
        BackButton.GrabFocus();
        SetProcessUnhandledInput(true);
    }

    /// <summary>Persists the preferences, hides the screen and emits <see cref="ClosedEventHandler"/>.</summary>
    public void Close()
    {
        _settings?.Save();
        Root.Visible = false;
        SetProcessUnhandledInput(false);
        EmitSignalClosed();
    }

    private void SyncFromSettings()
    {
        if (_settings is null)
        {
            return;
        }

        // No-signal setters: syncing the widgets must never write back into the settings
        // (OptionButton.Select does not emit item_selected either).
        FullscreenCheck.SetPressedNoSignal(_settings.Fullscreen);
        VolumeSlider.SetValueNoSignal(_settings.MasterVolume);
        UpdateVolumeLabel(_settings.MasterVolume);
        SelectVersion((int)_settings.GameVersion);
    }

    private void OnFullscreenToggled(bool pressed)
    {
        if (_settings is not null)
        {
            _settings.Fullscreen = pressed;
        }
    }

    private void OnVolumeSliderChanged(double value)
    {
        if (_settings is not null)
        {
            _settings.MasterVolume = (float)value;
        }

        UpdateVolumeLabel((float)value);
    }

    private void OnVersionSelected(long index)
    {
        if (_settings is not null)
        {
            _settings.GameVersion = (GameVersion)VersionOption.GetItemId((int)index);
        }
    }

    private void OnFullscreenChanged(bool fullscreen) => FullscreenCheck.SetPressedNoSignal(fullscreen);

    private void OnMasterVolumeChanged(float volume)
    {
        VolumeSlider.SetValueNoSignal(volume);
        UpdateVolumeLabel(volume);
    }

    private void OnGameVersionChanged(int version) => SelectVersion(version);

    /// <summary>Selects the item whose id is <paramref name="version"/>; an unknown id leaves the dropdown as it is.</summary>
    private void SelectVersion(int version)
    {
        int index = VersionOption.GetItemIndex(version);
        if (index >= 0)
        {
            VersionOption.Select(index);
        }
    }

    private void UpdateVolumeLabel(float volume)
    {
        int percent = Mathf.RoundToInt(volume * 100f);
        if (percent == _shownPercent)
        {
            return;   // dragging the slider builds one string per percent, not per frame
        }

        _shownPercent = percent;
        VolumeValue.Text = string.Format(VolumeFormat, percent);
    }
}
