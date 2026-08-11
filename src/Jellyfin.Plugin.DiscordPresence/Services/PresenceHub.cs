using System.Threading.Channels;
using Jellyfin.Plugin.DiscordPresence.Models;

namespace Jellyfin.Plugin.DiscordPresence.Services;

/// <summary>
/// Tracks what each user is playing across their sessions and pushes changes to subscribed companion apps.
/// </summary>
public sealed class PresenceHub
{
    // Progress arrives every ~10s; a position further than this from where playback should be is a seek.
    private static readonly long SeekThresholdTicks = TimeSpan.FromSeconds(5).Ticks;

    private readonly Lock _lock = new();
    private readonly Dictionary<Guid, UserPresence> _users = [];

    public PresenceState? GetCurrent(Guid userId)
    {
        lock (_lock)
        {
            return _users.GetValueOrDefault(userId)?.Published;
        }
    }

    public void Update(Guid userId, string sessionId, PresenceState state)
    {
        lock (_lock)
        {
            var user = GetOrAddUser(userId);
            user.Sessions[sessionId] = state;
            Publish(user);
        }
    }

    /// <summary>Adds artwork resolved after the fact, unless the session has moved on to another item.</summary>
    public void SetImage(Guid userId, string sessionId, string itemId, string imageUrl)
    {
        lock (_lock)
        {
            if (_users.TryGetValue(userId, out var user)
                && user.Sessions.TryGetValue(sessionId, out var state)
                && state.ItemId == itemId)
            {
                user.Sessions[sessionId] = state with { ImageUrl = imageUrl };
                Publish(user);
            }
        }
    }

    public void Remove(Guid userId, string sessionId)
    {
        lock (_lock)
        {
            if (_users.TryGetValue(userId, out var user) && user.Sessions.Remove(sessionId))
            {
                Publish(user);
            }
        }
    }

    public void Clear()
    {
        lock (_lock)
        {
            foreach (var user in _users.Values)
            {
                user.Sessions.Clear();
                Publish(user);
            }
        }
    }

    /// <summary>
    /// Yields the current state, then each change. Only the latest state is buffered, so a slow reader skips ahead.
    /// </summary>
    public Subscription Subscribe(Guid userId)
    {
        var channel = Channel.CreateBounded<PresenceState?>(
            new BoundedChannelOptions(1) { FullMode = BoundedChannelFullMode.DropOldest });

        lock (_lock)
        {
            var user = GetOrAddUser(userId);
            user.Subscribers.Add(channel);
            channel.Writer.TryWrite(user.Published);
        }

        return new Subscription(channel.Reader, () =>
        {
            lock (_lock)
            {
                _users[userId].Subscribers.Remove(channel);
            }
        });
    }

    private UserPresence GetOrAddUser(Guid userId)
    {
        if (!_users.TryGetValue(userId, out var user))
        {
            user = new UserPresence();
            _users[userId] = user;
        }

        return user;
    }

    private static void Publish(UserPresence user)
    {
        // With several sessions playing (say, a TV and a phone), show whichever reported last.
        var current = user.Sessions.Values.MaxBy(s => s.SampledAt);
        if (!IsMeaningfulChange(user.Published, current))
        {
            return;
        }

        user.Published = current;
        foreach (var subscriber in user.Subscribers)
        {
            subscriber.Writer.TryWrite(current);
        }
    }

    private static bool IsMeaningfulChange(PresenceState? previous, PresenceState? next)
    {
        if (previous is null || next is null)
        {
            return previous != next;
        }

        if (previous.ItemId != next.ItemId || previous.IsPaused != next.IsPaused || previous.ImageUrl != next.ImageUrl)
        {
            return true;
        }

        var elapsed = previous.IsPaused ? 0 : (next.SampledAt - previous.SampledAt).Ticks;
        return Math.Abs(next.PositionTicks - (previous.PositionTicks + elapsed)) > SeekThresholdTicks;
    }

    private sealed class UserPresence
    {
        public Dictionary<string, PresenceState> Sessions { get; } = [];

        public List<Channel<PresenceState?>> Subscribers { get; } = [];

        public PresenceState? Published { get; set; }
    }

    public sealed class Subscription(ChannelReader<PresenceState?> reader, Action unsubscribe) : IDisposable
    {
        public ChannelReader<PresenceState?> Reader { get; } = reader;

        public void Dispose() => unsubscribe();
    }
}
