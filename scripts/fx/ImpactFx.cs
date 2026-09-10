using BlackoutLastGrid.Art;
using Godot;

namespace BlackoutLastGrid.Fx;

/// <summary>
/// One-shot impact effect: a burst of electric sparks plus a short-lived light at the point of
/// contact (GAME_DESIGN §6 — a hit reads as a discharge, and light is the scene's main visual
/// device, so the sparks carry their own <see cref="PointLight2D"/> instead of trying to out-shine
/// the level's <c>CanvasModulate</c>). Spawned by <see cref="Levels.LevelFx"/> per event and freed
/// by itself: whichever comes first of <see cref="GpuParticles2D.Finished"/> and a guard timer of
/// <see cref="Lifetime"/> + <see cref="FreeMargin"/> seconds.
/// </summary>
/// <remarks>
/// The guard timer is deliberately scaled and non-always: the effect freezes with the hit-stop and
/// with the pause menu, and can never outlive its level. It is also the only path a headless test
/// may rely on — the dummy renderer never simulates particles, so <c>Finished</c> never arrives
/// there. Nothing here touches <see cref="Engine.TimeScale"/>.
/// </remarks>
public partial class ImpactFx : Node2D
{
    /// <summary>The spark burst.</summary>
    [Export] public GpuParticles2D Sparks { get; set; } = null!;

    /// <summary>The discharge light lit for <see cref="FlashTime"/>.</summary>
    [Export] public PointLight2D Flash { get; set; } = null!;

    /// <summary>Tint of the burst; the spawner overrides it per event (sparks vs. dust).</summary>
    [Export] public Color SparkColor { get; set; } = Palette.EnergyPale;

    /// <summary>Colour of the flash. Stays warm even for a dust puff — a dark light would show nothing.</summary>
    [Export] public Color FlashColor { get; set; } = Palette.EnergyPale;

    /// <summary>Peak energy of the flash.</summary>
    [Export] public float FlashEnergy { get; set; } = 1.6f;

    /// <summary>Seconds the flash takes to fade to nothing.</summary>
    [Export] public float FlashTime { get; set; } = 0.12f;

    /// <summary>Particle lifetime in seconds; the guard timer is measured from it.</summary>
    [Export] public float Lifetime { get; set; } = 0.35f;

    /// <summary>Seconds added to <see cref="Lifetime"/> before the guaranteed self-free.</summary>
    [Export] public float FreeMargin { get; set; } = 0.25f;

    private SceneTreeTimer? _freeTimer;
    private Tween? _flashTween;

    /// <inheritdoc/>
    public override void _Ready()
    {
        Sparks.Lifetime = Lifetime;
        Sparks.Finished += OnSparksFinished;
        Flash.Enabled = false;
        Flash.Energy = 0f;
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        Sparks.Finished -= OnSparksFinished;
        if (_freeTimer is not null)
        {
            _freeTimer.Timeout -= OnGuardTimeout;
            _freeTimer = null;
        }

        if (_flashTween is not null && _flashTween.IsValid())
        {
            _flashTween.Kill();
        }

        _flashTween = null;
    }

    /// <summary>
    /// Fires the effect: <paramref name="amount"/> sparks at <paramref name="scale"/>, the flash
    /// lit and faded out, and the guaranteed self-free armed. Call once, after the node is in the
    /// tree and positioned.
    /// </summary>
    /// <param name="amount">Number of particles in the burst.</param>
    /// <param name="scale">Uniform scale of the whole effect.</param>
    public void Play(int amount, float scale)
    {
        Scale = new Vector2(scale, scale);
        Sparks.Amount = Mathf.Max(1, amount);
        Sparks.Modulate = SparkColor;
        Sparks.Restart();

        Flash.Color = FlashColor;
        Flash.Enabled = true;
        Flash.Energy = FlashEnergy;
        if (_flashTween is not null && _flashTween.IsValid())
        {
            _flashTween.Kill();
        }

        _flashTween = CreateTween();
        _flashTween.TweenProperty(Flash, "energy", 0f, FlashTime);

        // Held in a field: a SceneTreeTimer that goes out of scope loses the C# subscription.
        _freeTimer = GetTree().CreateTimer(Lifetime + FreeMargin, processAlways: false, processInPhysics: false, ignoreTimeScale: false);
        _freeTimer.Timeout += OnGuardTimeout;
    }

    private void OnSparksFinished() => FreeNow();

    private void OnGuardTimeout() => FreeNow();

    private void FreeNow()
    {
        if (IsInstanceValid(this) && !IsQueuedForDeletion())
        {
            QueueFree();
        }
    }
}
