using System.Collections.Generic;
using BlackoutLastGrid.Actors;
using BlackoutLastGrid.Enemies;
using Godot;

namespace BlackoutLastGrid.Core;

/// <summary>
/// A belt-scroll wave: when the hero walks into the trigger area, the camera is locked to
/// <see cref="LockRect"/>, <see cref="Count"/> enemies are spawned one by one at the
/// <see cref="SpawnPoints"/> markers (cycling) with the hero as their target, and once every
/// one of them is knocked out the wave is cleared: "GO →" is shown for <see cref="GoDuration"/>
/// and the camera limits are released. Owns the enemies it spawns (they are its children, so the
/// spawner must be <c>y_sort_enabled</c> under a y-sorted level). Spent after one run when
/// <see cref="OneShot"/> is set.
/// </summary>
public partial class WaveSpawner : Area2D
{
    /// <summary>Emitted when the hero triggers the wave, before the first enemy spawns.</summary>
    [Signal]
    public delegate void WaveStartedEventHandler();

    /// <summary>Emitted for every enemy instanced by this wave, after it entered the tree.</summary>
    [Signal]
    public delegate void EnemySpawnedEventHandler(Node2D enemy);

    /// <summary>Emitted once all spawned enemies are knocked out.</summary>
    [Signal]
    public delegate void WaveClearedEventHandler();

    /// <summary>Enemy scene to spawn; its root must be a <see cref="Node2D"/> (a <see cref="Guard"/> gets the hero as target).</summary>
    [Export] public PackedScene? EnemyScene { get; set; }

    /// <summary>Number of enemies in the wave.</summary>
    [Export] public int Count { get; set; } = 3;

    /// <summary>Seconds between two spawns (the first one comes on the physics tick after the trigger).</summary>
    [Export] public float SpawnInterval { get; set; } = 0.4f;

    /// <summary>Seconds the "GO →" hint stays visible after the wave is cleared.</summary>
    [Export] public float GoDuration { get; set; } = 2f;

    /// <summary><c>true</c> to run the wave once; otherwise the hero can trigger it again after clearing it.</summary>
    [Export] public bool OneShot { get; set; } = true;

    /// <summary>
    /// <c>true</c> makes spawned guards aware of the hero immediately (an alarm wave charges in,
    /// SoR style); <c>false</c> leaves them to the normal perception rules (darkness works on them).
    /// </summary>
    [Export] public bool SpawnAware { get; set; } = true;

    /// <summary>Camera limits while the wave is locked (world px). A zero-size rect means the view at trigger time.</summary>
    [Export] public Rect2 LockRect { get; set; }

    /// <summary>The hero to hand to spawned enemies; set by the level. Falls back to the hero that triggers the wave.</summary>
    [Export] public Player? Player { get; set; }

    /// <summary>The level's attack-slot director handed to spawned enemies.</summary>
    [Export] public EnemyDirector? Director { get; set; }

    /// <summary>Camera whose limits are locked during the wave; optional.</summary>
    [Export] public Camera2D? Camera { get; set; }

    /// <summary>Parent of the <see cref="Marker2D"/> spawn points, used in order and cycled.</summary>
    [Export] public Node2D SpawnPoints { get; set; } = null!;

    /// <summary>The "GO →" hint (on an overlay layer), hidden until the wave is cleared.</summary>
    [Export] public Label GoLabel { get; set; } = null!;

    private readonly List<Marker2D> _markers = new();
    private bool _started;
    private bool _spawning;
    private bool _cleared;
    private bool _cameraLocked;
    private int _spawned;
    private int _alive;
    private int _nextMarker;
    private float _spawnTimer;
    private float _goTimer;
    private int _savedLimitLeft;
    private int _savedLimitTop;
    private int _savedLimitRight;
    private int _savedLimitBottom;

    /// <summary><c>true</c> from the trigger until the wave is cleared.</summary>
    public bool IsRunning => _started && !_cleared;

    /// <summary><c>true</c> once every enemy of the last run was knocked out.</summary>
    public bool IsCleared => _cleared;

    /// <summary>Enemies spawned so far in the current run.</summary>
    public int Spawned => _spawned;

    /// <summary>Spawned enemies not yet knocked out.</summary>
    public int Alive => _alive;

    /// <inheritdoc/>
    public override void _Ready()
    {
        foreach (Node child in SpawnPoints.GetChildren())
        {
            if (child is Marker2D marker)
            {
                _markers.Add(marker);
            }
        }

        if (_markers.Count == 0)
        {
            GD.PushWarning($"WaveSpawner '{Name}': SpawnPoints has no Marker2D children; enemies spawn at the spawner's origin.");
        }

        GoLabel.Visible = false;
        BodyEntered += OnBodyEntered;
    }

    /// <inheritdoc/>
    public override void _ExitTree()
    {
        BodyEntered -= OnBodyEntered;
        ReleaseCamera();
    }

    /// <inheritdoc/>
    public override void _PhysicsProcess(double delta)
    {
        float dt = (float)delta;
        if (_spawning)
        {
            _spawnTimer -= dt;
            if (_spawnTimer <= 0f)
            {
                SpawnOne();
                _spawnTimer += SpawnInterval;
            }
        }

        if (_goTimer > 0f)
        {
            _goTimer -= dt;
            if (_goTimer <= 0f)
            {
                GoLabel.Visible = false;
            }
        }
    }

    /// <summary>Starts the wave now (the trigger does this when the hero enters). Ignored while a run is in progress or after a one-shot run.</summary>
    public void StartWave()
    {
        if (_started)
        {
            return;
        }

        if (EnemyScene is null)
        {
            GD.PushError($"WaveSpawner '{Name}': EnemyScene is not set; the wave cannot start.");
            return;
        }

        if (Player is null || Director is null)
        {
            GD.PushWarning($"WaveSpawner '{Name}': Player or Director is not set; spawned enemies will have no target.");
        }

        _started = true;
        _cleared = false;
        _spawned = 0;
        _alive = 0;
        _spawnTimer = 0f;
        _spawning = true;
        LockCamera();
        EmitSignalWaveStarted();
    }

    private void OnBodyEntered(Node2D body)
    {
        if (_started || body is not Player hero)
        {
            return;
        }

        if (Player is not null && !ReferenceEquals(hero, Player))
        {
            return;
        }

        Player = hero;
        StartWave();
    }

    private void SpawnOne()
    {
        Node2D enemy = EnemyScene!.Instantiate<Node2D>();
        AddChild(enemy);
        enemy.GlobalPosition = NextSpawnPosition();

        if (enemy is Guard guard)
        {
            if (Player is not null && Director is not null)
            {
                guard.SetTarget(Player, Director);
                guard.FaceTowards(Player.GlobalPosition.X - enemy.GlobalPosition.X);
                if (SpawnAware)
                {
                    guard.SetAware();
                }
            }

            guard.KnockedOut += OnEnemyKnockedOut;
        }

        _spawned++;
        _alive++;
        EmitSignalEnemySpawned(enemy);

        if (_spawned >= Count)
        {
            _spawning = false;
        }
    }

    private Vector2 NextSpawnPosition()
    {
        if (_markers.Count == 0)
        {
            return GlobalPosition;
        }

        Vector2 position = _markers[_nextMarker].GlobalPosition;
        _nextMarker = (_nextMarker + 1) % _markers.Count;
        return position;
    }

    private void OnEnemyKnockedOut()
    {
        _alive--;
        if (!_spawning && _alive <= 0)
        {
            ClearWave();
        }
    }

    private void ClearWave()
    {
        _cleared = true;
        ReleaseCamera();
        GoLabel.Visible = true;
        _goTimer = GoDuration;
        EmitSignalWaveCleared();

        if (!OneShot)
        {
            _started = false;
        }
    }

    private void LockCamera()
    {
        if (Camera is null)
        {
            return;
        }

        _savedLimitLeft = Camera.LimitLeft;
        _savedLimitTop = Camera.LimitTop;
        _savedLimitRight = Camera.LimitRight;
        _savedLimitBottom = Camera.LimitBottom;

        Rect2 rect = LockRect.Size == Vector2.Zero ? CurrentView(Camera) : LockRect;
        Camera.LimitLeft = Mathf.RoundToInt(rect.Position.X);
        Camera.LimitTop = Mathf.RoundToInt(rect.Position.Y);
        Camera.LimitRight = Mathf.RoundToInt(rect.End.X);
        Camera.LimitBottom = Mathf.RoundToInt(rect.End.Y);
        _cameraLocked = true;
    }

    private void ReleaseCamera()
    {
        if (!_cameraLocked)
        {
            return;
        }

        _cameraLocked = false;
        if (Camera is null || !IsInstanceValid(Camera))
        {
            return;
        }

        Camera.LimitLeft = _savedLimitLeft;
        Camera.LimitTop = _savedLimitTop;
        Camera.LimitRight = _savedLimitRight;
        Camera.LimitBottom = _savedLimitBottom;
    }

    private static Rect2 CurrentView(Camera2D camera)
    {
        Vector2 size = camera.GetViewportRect().Size / camera.Zoom;
        return new Rect2(camera.GetScreenCenterPosition() - size * 0.5f, size);
    }
}
