using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// Dan, the hero's younger brother: the guide who runs ahead and shows the way
/// (<see cref="LeadTo"/> / <see cref="RunTo"/>), or a follower who trails the hero
/// (<see cref="Resume"/>), or a scripted extra who holds a spot (<see cref="HoldAt"/>); he speaks
/// short lines in a bubble over his head and carries his own headlamp so he stays readable in the
/// dark from a third of a screen ahead. The node's origin is the contact point with the floor
/// (Y = depth) and behaviour is driven by the child <see cref="StateMachine"/>
/// (Follow / Wait / Lead); this class owns the follow point, the route point, movement, the
/// anti-stuck failsafes, the visual flip, the lamp and the speech bubble.
/// </summary>
/// <remarks>
/// He is scenery with a heartbeat, never a puzzle: <c>collision_layer = 0</c> in
/// <c>Companion.tscn</c> means he cannot push the hero, cannot be hit and cannot trigger a door,
/// a checkpoint, a cave-in, a gas pocket or a tutorial prompt (all of which mask layer 2, the
/// hero), while <c>collision_mask = 1</c> keeps him out of walls. He has no health and no death
/// of his own — losing him is impossible by construction, so nothing may ever wait for him;
/// <see cref="ArrivedEventHandler"/>, <see cref="HeroReachedEventHandler"/> and
/// <see cref="HeroLaggingEventHandler"/> are information for the level, never a gate. Three
/// independent failsafes recover him from geometry without the player noticing:
/// <see cref="WarpDistance"/> (too far), <see cref="StuckSeconds"/> (wants to walk and is not
/// moving) and the explicit <see cref="OnHeroRelocated"/> a level calls on a room change or a
/// respawn. All three are live in every state, each aimed at that state's own anchor — the follow
/// point behind the hero, the held spot, or the route point <b>ahead</b>: a guide is never warped
/// back behind the hero. A hold and a route point are world positions; a level that wants him
/// somewhere else after a respawn re-issues the call. No transition ever originates inside a
/// state: every one is a level call.
/// </remarks>
public partial class Companion : CharacterBody2D
{
    /// <summary>Animation names on the companion's <c>AnimationPlayer</c>.</summary>
    private static readonly StringName AnimIdle = "idle";

    /// <inheritdoc cref="AnimIdle"/>
    private static readonly StringName AnimWalk = "walk";

    /// <summary>Emitted whenever <see cref="Say"/> puts a line up (levels, tests and future voice-over).</summary>
    [Signal]
    public delegate void LineShownEventHandler(string text);

    /// <summary>Emitted once per <see cref="HoldAt"/>, <see cref="LeadTo"/> or <see cref="RunTo"/> when he reaches the position.</summary>
    [Signal]
    public delegate void ArrivedEventHandler();

    /// <summary>Emitted on every failsafe or explicit warp, after the teleport.</summary>
    [Signal]
    public delegate void WarpedEventHandler();

    /// <summary>
    /// Emitted while leading, at the route point, the first time the hero comes within
    /// <see cref="HeroCloseDistance"/> of it — once per point. The moment a level checks the
    /// condition that gates the next point, or says a line.
    /// </summary>
    [Signal]
    public delegate void HeroReachedEventHandler();

    /// <summary>
    /// Emitted while leading (at the point or held by the leash) when the hero has stayed farther
    /// than <see cref="LeadResumeGap"/> for <see cref="CallAfterSeconds"/>, then every
    /// <see cref="CallRepeatSeconds"/>, at most <see cref="MaxCallsPerStop"/> times per point and
    /// never while warning. The moment for a call line; he never walks back himself.
    /// </summary>
    [Signal]
    public delegate void HeroLaggingEventHandler();

    /// <summary>The hero he follows or guides; wired by the level. Without one he simply stands still (or holds his point).</summary>
    [Export] public Player? Target { get; set; }

    /// <summary>Walk speed along X while trailing or walking to a hold, in px/s (just under the hero's 220 so he reads as trailing).</summary>
    [Export] public float MoveSpeed { get; set; } = 205f;

    /// <summary>Walk speed along X beyond <see cref="CatchUpDistance"/>, in px/s.</summary>
    [Export] public float CatchUpSpeed { get; set; } = 300f;

    /// <summary>Distance to the follow point under which he stops, in px.</summary>
    [Export] public float FollowDistance { get; set; } = 90f;

    /// <summary>Distance to the follow point above which he hurries at <see cref="CatchUpSpeed"/>, in px.</summary>
    [Export] public float CatchUpDistance { get; set; } = 260f;

    /// <summary>Anti-stuck failsafe 1: distance to the state's anchor (follow point, hold, route point) above which he is warped there at once, in px.</summary>
    [Export] public float WarpDistance { get; set; } = 900f;

    /// <summary>Anti-stuck failsafe 2: seconds of "wants to walk, is not moving" before a warp.</summary>
    [Export] public float StuckSeconds { get; set; } = 2.5f;

    /// <summary>Requested speed above which the stuck watchdog considers that he wants to walk, in px/s.</summary>
    [Export] public float StuckSpeed { get; set; } = 5f;

    /// <summary>Net distance he must cover to count as actually walking, in px (a wall keeps him jittering in place).</summary>
    [Export] public float StuckProgress { get; set; } = 8f;

    /// <summary>Depth (Y) speed as a fraction of the walk speed; matches the hero's belt-scroll factor.</summary>
    [Export] public float DepthSpeedFactor { get; set; } = 0.75f;

    /// <summary>X offset of the follow point from the hero, in px, signed by the hero's facing (negative = behind him).</summary>
    [Export] public float SideOffset { get; set; } = -56f;

    /// <summary>Y offset of the follow point from the hero, in px, so he never stands exactly on the hero's depth line.</summary>
    [Export] public float DepthOffset { get; set; } = 10f;

    /// <summary>Distance to a held position or a route point at which <see cref="ArrivedEventHandler"/> fires, in px.</summary>
    [Export] public float ArriveDistance { get; set; } = 12f;

    /// <summary>Seconds a spoken line stays in the bubble.</summary>
    [Export] public float BubbleSeconds { get; set; } = 2.6f;

    /// <summary>Speed above which <c>walk</c> plays instead of <c>idle</c>, in px/s.</summary>
    [Export] public float WalkAnimationMinSpeed { get; set; } = 12f;

    /// <summary>Walk speed along X while leading, in px/s (just over the hero's 220 so he reads as leading and is rarely overtaken on a straight).</summary>
    [Export] public float LeadSpeed { get; set; } = 240f;

    /// <summary>Speed along X for <see cref="RunTo"/>, in px/s; equals <see cref="CatchUpSpeed"/>, so nothing ever moves faster than the hero has already seen.</summary>
    [Export] public float RunSpeed { get; set; } = 300f;

    /// <summary>The leash: farther ahead of the hero than this (px, along the way) he stops and turns to him. Keeps his bubble inside a 1920 px view with the hero centred.</summary>
    [Export] public float LeadMaxGap { get; set; } = 640f;

    /// <summary>Leash hysteresis: held by the leash, he goes on once the hero is closer than this, in px. Also the distance beyond which the hero counts as lagging.</summary>
    [Export] public float LeadResumeGap { get; set; } = 380f;

    /// <summary>At the route point, the hero within this distance of it (px) fires <see cref="HeroReachedEventHandler"/> — once per point.</summary>
    [Export] public float HeroCloseDistance { get; set; } = 160f;

    /// <summary>At a stop, seconds facing the way before he turns to look for the hero; ignored while warning.</summary>
    [Export] public float LookBackSeconds { get; set; } = 1.5f;

    /// <summary>At a stop or held by the leash, seconds with the hero farther than <see cref="LeadResumeGap"/> before the first <see cref="HeroLaggingEventHandler"/>.</summary>
    [Export] public float CallAfterSeconds { get; set; } = 5f;

    /// <summary>Seconds between repeated <see cref="HeroLaggingEventHandler"/> at the same stop.</summary>
    [Export] public float CallRepeatSeconds { get; set; } = 10f;

    /// <summary>After this many calls at one point he is quiet until the next — the anti-nag cap.</summary>
    [Export] public int MaxCallsPerStop { get; set; } = 2;

    /// <summary>The hero counts as "ahead of him" once past this distance along the way, in px (levels, tests, docs).</summary>
    [Export] public float OvertakeDistance { get; set; } = 120f;

    /// <summary>+1 facing right, -1 facing left. Set in the scene for a placed companion; updated while he walks.</summary>
    [Export] public int Facing { get; set; } = 1;

    /// <summary>
    /// Container for the body art; mirrored by <see cref="Facing"/>. Its <c>light_mask</c> is the
    /// one his headlamp lights (bit 2 on top of the world's bit 1) and is copied onto every drawn
    /// child once on ready, because Godot does not inherit the mask.
    /// </summary>
    [Export] public Node2D Visual { get; set; } = null!;

    /// <summary>Painted frames for Dan.</summary>
    [Export] public AnimatedSprite2D? Sprite { get; set; }

    /// <summary>idle / walk / RESET; no combat animations — he never fights.</summary>
    [Export] public AnimationPlayer AnimationPlayer { get; set; } = null!;

    /// <summary>Behaviour state machine (Follow / Wait / Lead).</summary>
    [Export] public StateMachine StateMachine { get; set; } = null!;

    /// <summary>
    /// Speech bubble over his head. A child of the root, not of <see cref="Visual"/>, so the
    /// facing flip does not mirror the text. It never pauses the game — story beats go through
    /// the level's cutscene overlay instead. Carries the headlamp's render bit so the line reads
    /// in the dark.
    /// </summary>
    [Export] public Label? Bubble { get; set; }

    /// <summary>
    /// His own headlamp (<c>PH_DanLight</c>): a light whose <c>range_item_cull_mask</c> is a render
    /// bit only his body and his bubble carry, so it lights him and nothing else — not the floor,
    /// not the hero. On by default; a level switches it with <see cref="SetLampOn"/> (off before a
    /// gas pocket, so the rule is shown before it is said).
    /// </summary>
    [Export] public PointLight2D? Lamp { get; set; }

    private bool _walking;
    private bool? _gait;
    private Vector2 _stuckAnchor;
    private float _stuckFor;
    private float _bubbleFor;
    private bool _bubbleSuppressed;
    private CompanionLead? _lead;

    /// <summary>Position the <c>Wait</c> state walks to and holds; set by <see cref="HoldAt"/>. A world position — it never moves with him.</summary>
    public Vector2 HoldPosition { get; private set; }

    /// <summary>Route point the <c>Lead</c> state walks to and shows the way from; set by <see cref="LeadTo"/> / <see cref="RunTo"/>.</summary>
    public Vector2 LeadTarget { get; private set; }

    /// <summary>+1 when the route point lies to his right, -1 to his left: the direction he shows and the axis of "ahead" / "behind".</summary>
    public int TravelSign { get; private set; } = 1;

    /// <summary><c>true</c> while the leash is on (<see cref="LeadTo"/>); <c>false</c> after <see cref="RunTo"/>.</summary>
    public bool LeadLeashed { get; private set; } = true;

    /// <summary>Walk speed the <c>Lead</c> state uses: <see cref="LeadSpeed"/> after <see cref="LeadTo"/>, <see cref="RunSpeed"/> after <see cref="RunTo"/>.</summary>
    public float LeadMoveSpeed { get; private set; }

    /// <summary><c>true</c> in the warning stance (<see cref="SetWarning"/>): at the point, facing the danger, no look-back, no calls.</summary>
    public bool IsWarning { get; private set; }

    /// <summary><c>true</c> once <see cref="Vanish"/> removed him from play for good.</summary>
    public bool IsGone { get; private set; }

    /// <summary>Name of the active state, for debug labels and tests.</summary>
    public string CurrentStateName => StateMachine.CurrentState?.Name ?? string.Empty;

    /// <summary><c>true</c> while he holds a scripted position instead of following.</summary>
    public bool IsWaiting => StateMachine.IsIn(CompanionState.StateWait);

    /// <summary><c>true</c> while he guides the hero to <see cref="LeadTarget"/>.</summary>
    public bool IsLeading => StateMachine.IsIn(CompanionState.StateLead);

    /// <summary><c>true</c> while he is leading and has reached <see cref="LeadTarget"/>.</summary>
    public bool IsAtLeadTarget => IsLeading && _lead is { AtTarget: true };

    /// <summary><c>true</c> while he is leading and the leash holds him (the hero fell more than <see cref="LeadMaxGap"/> behind).</summary>
    public bool IsLeashed => IsLeading && _lead is { Leashed: true };

    /// <summary><c>true</c> while the headlamp is on.</summary>
    public bool IsLampOn => Lamp is { Enabled: true };

    /// <summary><c>true</c> while a spoken line is still counting down (whether or not it is visible).</summary>
    public bool IsSpeaking => _bubbleFor > 0f;

    /// <summary>The line currently counting down, or an empty string.</summary>
    public string CurrentLine { get; private set; } = string.Empty;

    /// <summary><see cref="Target"/> while it is alive in the tree, else <c>null</c>.</summary>
    public Player? ActiveTarget =>
        Target is { } target && IsInstanceValid(target) && !target.IsQueuedForDeletion() ? target : null;

    /// <summary><c>true</c> while <see cref="ActiveTarget"/> is available.</summary>
    public bool HasTarget => ActiveTarget is not null;

    /// <summary>
    /// Where he wants to stand while following: behind the hero by <see cref="SideOffset"/>
    /// (mirrored with the hero's facing) and <see cref="DepthOffset"/> off his depth line, clamped
    /// to the hero's own floor band so he inherits it and needs no room bounds of his own. Falls
    /// back to the current position without a target.
    /// </summary>
    public Vector2 FollowPoint
    {
        get
        {
            if (ActiveTarget is not { } target)
            {
                return GlobalPosition;
            }

            Vector2 anchor = target.GlobalPosition;
            return new Vector2(
                anchor.X + target.Facing * SideOffset,
                Mathf.Clamp(anchor.Y + DepthOffset, target.FloorTop, target.FloorBottom));
        }
    }

    /// <summary>
    /// Anti-stuck failsafe 2: <c>true</c> once he has asked to walk for <see cref="StuckSeconds"/>
    /// without actually moving. The states answer it with a warp and <see cref="ClearStuck"/>.
    /// </summary>
    public bool IsStuck => _stuckFor >= StuckSeconds;

    /// <inheritdoc/>
    public override void _Ready()
    {
        if (Bubble is not null)
        {
            Bubble.Text = string.Empty;
            Bubble.Visible = false;
        }

        _lead = StateMachine.GetNodeOrNull<CompanionLead>(CompanionState.StateLead);
        LeadMoveSpeed = LeadSpeed;
        ApplyLightMask(Visual, Visual.LightMask);
        UpdateVisual();
    }

    /// <inheritdoc/>
    public override void _Process(double delta)
    {
        if (_bubbleFor > 0f)
        {
            _bubbleFor -= (float)delta;
            if (_bubbleFor <= 0f)
            {
                _bubbleFor = 0f;
                CurrentLine = string.Empty;
                UpdateBubble();
            }
        }

        UpdateGait();
    }

    /// <summary>
    /// Puts a line in the bubble for <see cref="BubbleSeconds"/> and emits
    /// <see cref="LineShownEventHandler"/> so the level (and later the audio) can react. The game
    /// keeps running: this is a reaction, not a story beat. An empty line clears the bubble.
    /// </summary>
    /// <param name="text">The line, already in the player's language.</param>
    public void Say(string text)
    {
        CurrentLine = text;
        _bubbleFor = string.IsNullOrEmpty(text) ? 0f : BubbleSeconds;

        if (Bubble is not null)
        {
            Bubble.Text = text;
        }

        UpdateBubble();
        EmitSignalLineShown(text);
    }

    /// <summary>
    /// Hides the bubble while a HUD prompt owns the screen (author's rule: a bubble that would
    /// collide with a prompt loses to the prompt). The line keeps counting down, so an unsuppressed
    /// bubble reappears only for the time it has left.
    /// </summary>
    /// <param name="suppressed"><c>true</c> to keep the bubble hidden.</param>
    public void SetBubbleSuppressed(bool suppressed)
    {
        _bubbleSuppressed = suppressed;
        UpdateBubble();
    }

    /// <summary>Switches his headlamp; a level turns it off before a gas pocket so Dan goes dark before he shouts.</summary>
    /// <param name="on"><c>true</c> lights him up.</param>
    public void SetLampOn(bool on)
    {
        if (Lamp is not null)
        {
            Lamp.Enabled = on;
        }
    }

    /// <summary>
    /// Anti-stuck failsafes 1 and 3 of the <c>Follow</c> state: teleports him to
    /// <see cref="FollowPoint"/>. Called by the Follow state when he is too far or wedged, and by
    /// <see cref="OnHeroRelocated"/> while he follows, so a door or a death never leaves him on the
    /// wrong side of a sealed drift. Without a target, or once gone, it does nothing. A hold or a
    /// route point is never moved by this.
    /// </summary>
    public void WarpBehind()
    {
        if (IsGone || !HasTarget)
        {
            return;
        }

        WarpTo(FollowPoint);
    }

    /// <summary>
    /// The level's hook after it teleported the hero (a door hop between room bounds, a respawn);
    /// what he does about it depends on his state. Following: <see cref="WarpBehind"/>, as a
    /// follower has no place of his own. Holding or leading: nothing, unless the hero is now
    /// farther than <see cref="WarpDistance"/> from him — then a warp onto the held spot or the
    /// route point, never behind the hero. The level re-issues a hold or a route point where it
    /// wants him after a respawn.
    /// </summary>
    public void OnHeroRelocated()
    {
        if (IsGone || ActiveTarget is not { } target)
        {
            return;
        }

        if (!IsWaiting && !IsLeading)
        {
            WarpBehind();
            return;
        }

        if (target.GlobalPosition.DistanceSquaredTo(GlobalPosition) > WarpDistance * WarpDistance)
        {
            WarpTo(IsLeading ? LeadTarget : HoldPosition);
        }
    }

    /// <summary>Teleports him to <paramref name="position"/>, stops him and emits <see cref="WarpedEventHandler"/>.</summary>
    /// <param name="position">World position to appear at.</param>
    public void WarpTo(Vector2 position)
    {
        GlobalPosition = position;
        Stop();
        EmitSignalWarped();
    }

    /// <summary>
    /// Sends him to <paramref name="position"/> and keeps him there (the scripted beats). He walks
    /// there himself and emits <see cref="ArrivedEventHandler"/> once he is within
    /// <see cref="ArriveDistance"/> — but nothing in a level may ever wait for that signal.
    /// </summary>
    /// <param name="position">World position to hold.</param>
    public void HoldAt(Vector2 position)
    {
        HoldPosition = position;
        StateMachine.TransitionToOrRestart(CompanionState.StateWait);
    }

    /// <summary>
    /// Sends him ahead to <paramref name="target"/> as the guide: he walks there at
    /// <see cref="LeadSpeed"/> with the leash on, stops, shows the way and waits for the hero,
    /// emitting <see cref="ArrivedEventHandler"/> once on reaching the point. Re-issuing the same
    /// point while already leading there only refreshes the leash and speed and clears the warning
    /// stance — it never restarts the walk or re-fires <see cref="ArrivedEventHandler"/>, so a
    /// respawn handler may re-issue freely. Ignored once he is gone.
    /// </summary>
    /// <param name="target">World position of the route point.</param>
    public void LeadTo(Vector2 target) => Lead(target, leashed: true, LeadSpeed);

    /// <summary>As <see cref="LeadTo"/>, but with the leash off and at <see cref="RunSpeed"/>: he does not wait for the hero on the way.</summary>
    /// <param name="target">World position of the route point.</param>
    public void RunTo(Vector2 target) => Lead(target, leashed: false, RunSpeed);

    /// <summary>
    /// The warning stance at the route point: he faces <see cref="TravelSign"/> — the danger, not
    /// the hero — never looks back and never calls. The level says the line and decides when the
    /// point may be advanced; the next <see cref="LeadTo"/> / <see cref="RunTo"/> clears it.
    /// </summary>
    /// <param name="on"><c>true</c> to warn, <c>false</c> to stand normally again.</param>
    public void SetWarning(bool on) => IsWarning = on;

    /// <summary>
    /// Takes him out of the story for good: hidden, no processing, silent, and every later
    /// <see cref="LeadTo"/> / <see cref="RunTo"/> / <see cref="OnHeroRelocated"/> is ignored.
    /// Irreversible for this level instance — how and when is the level's decision.
    /// </summary>
    public void Vanish()
    {
        IsGone = true;
        Stop();
        Say(string.Empty);
        Visible = false;
        ProcessMode = ProcessModeEnum.Disabled;
    }

    /// <summary>Sends him back to following the hero.</summary>
    public void Resume() => StateMachine.TransitionTo(CompanionState.StateFollow);

    /// <summary>Turns towards <paramref name="dx"/> (the destination's X minus his own); 0 keeps the current facing.</summary>
    /// <param name="dx">Signed horizontal offset to face.</param>
    public void FaceTowards(float dx)
    {
        if (dx != 0f)
        {
            Facing = dx > 0f ? 1 : -1;
        }

        UpdateVisual();
    }

    /// <summary>
    /// Moves with <paramref name="velocity"/> for one physics step (walls on the World layer are
    /// resolved by <see cref="CharacterBody2D.MoveAndSlide"/>) and feeds the stuck watchdog with
    /// the difference between the requested and the achieved motion.
    /// </summary>
    /// <param name="velocity">Floor-plane velocity in px/s.</param>
    /// <param name="delta">Physics step in seconds; 0 during hit-stop, when nothing moves anyway.</param>
    public void Move(Vector2 velocity, double delta)
    {
        if (delta <= 0.0)
        {
            // Hit-stop: the step arrives with delta 0 and every velocity is zero, so writing the
            // gait here would snap him to the idle pose for the freeze frames. Hold everything.
            return;
        }

        Velocity = velocity;
        MoveAndSlide();
        _walking = velocity.LengthSquared() >= WalkAnimationMinSpeed * WalkAnimationMinSpeed;
        UpdateStuckWatchdog(velocity, delta);
    }

    /// <summary>Stands still: clears the velocity, the gait and the stuck watchdog.</summary>
    public void Stop()
    {
        Velocity = Vector2.Zero;
        _walking = false;
        ClearStuck();
    }

    /// <summary>Resets the stuck watchdog; called after a warp and on entering a state.</summary>
    public void ClearStuck() => _stuckFor = 0f;

    /// <summary>
    /// Velocity that reaches <paramref name="destination"/> within this step when close enough,
    /// clamped per axis to <paramref name="speed"/> / <paramref name="speed"/> ×
    /// <see cref="DepthSpeedFactor"/>. Converges without overshooting, so a held position does not
    /// jitter.
    /// </summary>
    /// <param name="destination">World position to walk to.</param>
    /// <param name="delta">Physics step in seconds.</param>
    /// <param name="speed">Walk speed along X in px/s.</param>
    public Vector2 VelocityTowards(Vector2 destination, double delta, float speed)
    {
        float dt = (float)delta;
        if (dt <= 0f)
        {
            return Vector2.Zero;   // a frozen physics tick (hit-stop) has delta 0: nothing moves
        }

        Vector2 offset = destination - GlobalPosition;
        float depthSpeed = speed * DepthSpeedFactor;
        return new Vector2(
            Mathf.Clamp(offset.X / dt, -speed, speed),
            Mathf.Clamp(offset.Y / dt, -depthSpeed, depthSpeed));
    }

    /// <summary>Emits <see cref="ArrivedEventHandler"/>; called by the Wait and Lead states once per position.</summary>
    public void NotifyArrived() => EmitSignalArrived();

    /// <summary>Emits <see cref="HeroReachedEventHandler"/>; called by the Lead state once per route point.</summary>
    public void NotifyHeroReached() => EmitSignalHeroReached();

    /// <summary>Emits <see cref="HeroLaggingEventHandler"/>; called by the Lead state, rate-limited and capped.</summary>
    public void NotifyHeroLagging() => EmitSignalHeroLagging();

    private void Lead(Vector2 target, bool leashed, float speed)
    {
        if (IsGone)
        {
            return;
        }

        if (IsLeading && LeadTarget == target)
        {
            return;   // the same point again: a true no-op — the leash, the gait and the stance stay, Arrived must not fire twice
        }

        LeadLeashed = leashed;
        LeadMoveSpeed = speed;
        IsWarning = false;
        LeadTarget = target;
        float dx = target.X - GlobalPosition.X;
        TravelSign = dx == 0f ? Facing : dx > 0f ? 1 : -1;
        StateMachine.TransitionToOrRestart(CompanionState.StateLead);
    }

    /// <summary>
    /// Counts the time he asks for a walk faster than <see cref="StuckSpeed"/> without leaving the
    /// spot he asked from — a wedge in the geometry, or a wall he keeps pressing. Net displacement
    /// from an anchor, not the frame velocity: a body pressed against a wall keeps a small
    /// depenetration velocity while going nowhere.
    /// </summary>
    /// <param name="requested">Velocity handed to <see cref="Move"/>, in px/s.</param>
    /// <param name="delta">Physics step in seconds.</param>
    private void UpdateStuckWatchdog(Vector2 requested, double delta)
    {
        if (delta <= 0.0 || requested.LengthSquared() < StuckSpeed * StuckSpeed)
        {
            _stuckFor = 0f;
            return;
        }

        if (_stuckFor <= 0f)
        {
            _stuckAnchor = GlobalPosition;
        }
        else if (GlobalPosition.DistanceSquaredTo(_stuckAnchor) > StuckProgress * StuckProgress)
        {
            _stuckFor = 0f;
            return;
        }

        _stuckFor += (float)delta;
    }

    /// <summary>
    /// Switches between the looping <c>walk</c> and <c>idle</c> animations, and only on a change of
    /// gait — restarting an animation every frame would keep it at frame 0 forever.
    /// </summary>
    private void UpdateGait()
    {
        if (_gait == _walking)
        {
            return;
        }

        _gait = _walking;
        PlayAnimation(_walking ? AnimWalk : AnimIdle);
    }

    /// <summary>Plays <paramref name="animation"/> from its first frame; a missing animation is a warning.</summary>
    /// <param name="animation">Animation name (idle, walk).</param>
    private void PlayAnimation(StringName animation)
    {
        if (!AnimationPlayer.HasAnimation(animation))
        {
            GD.PushWarning($"{Name}: AnimationPlayer has no animation '{animation}'.");
            return;
        }

        // Play() on the animation that is already playing keeps its position; always rewind so a
        // re-entered gait starts at frame 0.
        AnimationPlayer.Play(animation);
        AnimationPlayer.Seek(0.0, update: true);
    }

    /// <summary>
    /// Copies <paramref name="mask"/> onto every drawn descendant of <paramref name="node"/> (the
    /// rig's polygons, future sprite frames), so the headlamp's render bit reaches the items that
    /// are actually lit. Walked once on ready, never per frame. The lamp itself is skipped: a
    /// light's mask is what it lights, not what lights it.
    /// </summary>
    private static void ApplyLightMask(Node node, int mask)
    {
        foreach (Node child in node.GetChildren())
        {
            if (child is CanvasItem item && child is not Light2D)
            {
                item.LightMask = mask;
            }

            ApplyLightMask(child, mask);
        }
    }

    private void UpdateBubble()
    {
        if (Bubble is not null)
        {
            Bubble.Visible = _bubbleFor > 0f && !_bubbleSuppressed;
        }
    }

    private void UpdateVisual() => Visual.Scale = new Vector2(Facing, 1f);
}
