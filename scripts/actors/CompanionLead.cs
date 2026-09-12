using BlackoutLastGrid.Core;
using Godot;

namespace BlackoutLastGrid.Actors;

/// <summary>
/// Guiding the hero (<see cref="Companion.LeadTo"/> / <see cref="Companion.RunTo"/>): walks to
/// <see cref="Companion.LeadTarget"/> at <see cref="Companion.LeadMoveSpeed"/>, emits
/// <see cref="Companion.ArrivedEventHandler"/> once inside <see cref="Companion.ArriveDistance"/>
/// and then stands there showing the way — facing <see cref="Companion.TravelSign"/>, and after
/// <see cref="Companion.LookBackSeconds"/> turning to look for the hero. While walking with the
/// leash on (<see cref="Companion.LeadLeashed"/>) he never gets more than
/// <see cref="Companion.LeadMaxGap"/> ahead of the hero: past it he stops and turns to him, and
/// goes on once the hero is closer than <see cref="Companion.LeadResumeGap"/>. At the point,
/// <see cref="Companion.HeroReachedEventHandler"/> fires the first time the hero comes within
/// <see cref="Companion.HeroCloseDistance"/>; until then (and while leashed)
/// <see cref="Companion.HeroLaggingEventHandler"/> fires after <see cref="Companion.CallAfterSeconds"/>
/// with the hero farther than <see cref="Companion.LeadResumeGap"/>, then every
/// <see cref="Companion.CallRepeatSeconds"/>, at most <see cref="Companion.MaxCallsPerStop"/> times
/// per point. He never walks towards the hero: the two failsafes here aim <b>forward</b>, at the
/// route point — a point (or a hero) farther than <see cref="Companion.WarpDistance"/> along the
/// way, or <see cref="Companion.StuckSeconds"/> of pressing against geometry, both end with a warp
/// onto the point. The warning stance (<see cref="Companion.SetWarning"/>) keeps him facing the
/// way with no look-back and no calls. Without a hero he still walks to the point and holds it.
/// </summary>
public partial class CompanionLead : CompanionState
{
    private bool _arrived;
    private bool _leashed;
    private bool _heroReached;
    private float _stoodFor;
    private float _lagFor;
    private int _calls;

    /// <summary><c>true</c> once he has reached the route point (and <see cref="Companion.ArrivedEventHandler"/> fired).</summary>
    public bool AtTarget => _arrived;

    /// <summary><c>true</c> while the leash holds him: he has stopped because the hero is too far behind.</summary>
    public bool Leashed => _leashed;

    /// <summary><c>true</c> once <see cref="Companion.HeroReachedEventHandler"/> fired for the current point.</summary>
    public bool HeroReached => _heroReached;

    /// <inheritdoc/>
    public override void Enter(State? previous)
    {
        _arrived = false;
        _leashed = false;
        _heroReached = false;
        _stoodFor = 0f;
        _lagFor = 0f;
        _calls = 0;
        Companion.ClearStuck();
    }

    /// <inheritdoc/>
    public override void Exit(State? next) => Companion.SetWarning(false);

    /// <inheritdoc/>
    public override void PhysicsUpdate(double delta)
    {
        Vector2 point = Companion.LeadTarget;
        Vector2 offset = point - Companion.GlobalPosition;
        float distanceSquared = offset.LengthSquared();
        Player? hero = Companion.ActiveTarget;

        if (distanceSquared <= Companion.ArriveDistance * Companion.ArriveDistance)
        {
            HoldPoint(delta, point, hero);
            return;
        }

        // Failsafe 1, aimed forward: the point is half a screen away (issued from across the
        // level, or he was left behind a seal), or the hero has already outrun him by that much —
        // the route point is the ceiling, so being there is always right. Never behind the hero.
        if (distanceSquared > Companion.WarpDistance * Companion.WarpDistance || IsHeroFarAhead(hero))
        {
            Companion.WarpTo(point);
            return;
        }

        Walk(delta, point, hero);
    }

    /// <summary>Standing at the route point: show the way, look back, notice the hero, call him.</summary>
    private void HoldPoint(double delta, Vector2 point, Player? hero)
    {
        Companion.Stop();
        if (!_arrived)
        {
            _arrived = true;
            _leashed = false;
            _stoodFor = 0f;
            _lagFor = 0f;
            _calls = 0;
            Companion.FaceTowards(Companion.TravelSign);
            Companion.NotifyArrived();
        }

        _stoodFor += (float)delta;
        if (Companion.IsWarning)
        {
            Companion.FaceTowards(Companion.TravelSign);   // eyes on the danger, never on the hero
        }
        else if (hero is not null && _stoodFor >= Companion.LookBackSeconds)
        {
            Companion.FaceTowards(hero.GlobalPosition.X - Companion.GlobalPosition.X);
        }

        if (hero is null)
        {
            return;
        }

        if (!_heroReached
            && hero.GlobalPosition.DistanceSquaredTo(point) <= Companion.HeroCloseDistance * Companion.HeroCloseDistance)
        {
            _heroReached = true;
            Companion.NotifyHeroReached();
        }

        UpdateLag(delta, hero);
    }

    /// <summary>Walking to the route point, held by the leash when the hero falls too far behind.</summary>
    private void Walk(double delta, Vector2 point, Player? hero)
    {
        if (Companion.LeadLeashed && hero is not null)
        {
            float behind = (Companion.GlobalPosition.X - hero.GlobalPosition.X) * Companion.TravelSign;
            if (behind > Companion.LeadMaxGap)
            {
                _leashed = true;
            }
            else if (_leashed && behind < Companion.LeadResumeGap)
            {
                _leashed = false;
            }

            if (_leashed)
            {
                Companion.Stop();
                Companion.FaceTowards(hero.GlobalPosition.X - Companion.GlobalPosition.X);
                UpdateLag(delta, hero);
                return;
            }
        }

        Vector2 velocity = Companion.VelocityTowards(point, delta, Companion.LeadMoveSpeed);
        Companion.FaceTowards(velocity.X);
        Companion.Move(velocity, delta);

        // Failsafe 2, aimed forward: wedged on the way — appear at the point, on its side of
        // whatever he caught on.
        if (Companion.IsStuck)
        {
            Companion.WarpTo(point);
        }
    }

    /// <summary>
    /// The call timer: runs only while the hero is farther than <see cref="Companion.LeadResumeGap"/>,
    /// has not reached this point yet, the cap is not spent and he is not in the warning stance.
    /// </summary>
    private void UpdateLag(double delta, Player hero)
    {
        if (Companion.IsWarning || _heroReached || _calls >= Companion.MaxCallsPerStop)
        {
            _lagFor = 0f;
            return;
        }

        if (hero.GlobalPosition.DistanceSquaredTo(Companion.GlobalPosition) <= Companion.LeadResumeGap * Companion.LeadResumeGap)
        {
            _lagFor = 0f;
            return;
        }

        _lagFor += (float)delta;
        float due = _calls == 0 ? Companion.CallAfterSeconds : Companion.CallRepeatSeconds;
        if (_lagFor >= due)
        {
            _lagFor = 0f;
            _calls++;
            Companion.NotifyHeroLagging();
        }
    }

    /// <summary><c>true</c> when the hero is more than <see cref="Companion.WarpDistance"/> ahead of him along the way.</summary>
    private bool IsHeroFarAhead(Player? hero) =>
        hero is not null
        && (hero.GlobalPosition.X - Companion.GlobalPosition.X) * Companion.TravelSign > Companion.WarpDistance;
}
