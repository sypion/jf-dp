using Jellyfin.Data.Enums;
using Jellyfin.Plugin.DiscordPresence.Configuration;
using Jellyfin.Plugin.DiscordPresence.Models;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Entities.Movies;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Library;
using MediaBrowser.Controller.Session;
using MediaBrowser.Model.Entities;
using MediaBrowser.Model.Plugins;
using Microsoft.Extensions.Hosting;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.DiscordPresence.Services;

/// <summary>
/// Turns Jellyfin playback events into <see cref="PresenceHub"/> updates.
/// </summary>
public sealed class PlaybackListener(
    ISessionManager sessionManager,
    ILibraryManager libraryManager,
    PresenceHub hub,
    ArtworkResolver artwork,
    ILogger<PlaybackListener> logger) : IHostedService
{
    public Task StartAsync(CancellationToken cancellationToken)
    {
        sessionManager.PlaybackStart += OnPlayback;
        sessionManager.PlaybackProgress += OnPlayback;
        sessionManager.PlaybackStopped += OnPlaybackStopped;
        sessionManager.SessionEnded += OnSessionEnded;
        if (Plugin.Instance is { } plugin)
        {
            plugin.ConfigurationChanged += OnConfigurationChanged;
        }

        return Task.CompletedTask;
    }

    public Task StopAsync(CancellationToken cancellationToken)
    {
        sessionManager.PlaybackStart -= OnPlayback;
        sessionManager.PlaybackProgress -= OnPlayback;
        sessionManager.PlaybackStopped -= OnPlaybackStopped;
        sessionManager.SessionEnded -= OnSessionEnded;
        if (Plugin.Instance is { } plugin)
        {
            plugin.ConfigurationChanged -= OnConfigurationChanged;
        }

        return Task.CompletedTask;
    }

    // Raised synchronously while handling the client's playback report: stay fast and never throw.
    private void OnPlayback(object? sender, PlaybackProgressEventArgs e)
    {
        try
        {
            HandlePlayback(e);
        }
        catch (Exception ex)
        {
            logger.LogError(ex, "Failed to update Discord presence");
        }
    }

    private void OnPlaybackStopped(object? sender, PlaybackStopEventArgs e) => RemoveSession(e);

    private void OnSessionEnded(object? sender, SessionEventArgs e) => hub.Remove(e.SessionInfo.UserId, e.SessionInfo.Id);

    // Sessions come back on their next progress report (~10s) with the new settings applied.
    private void OnConfigurationChanged(object? sender, BasePluginConfiguration config) => hub.Clear();

    private void HandlePlayback(PlaybackProgressEventArgs e)
    {
        var config = Plugin.Instance?.Configuration;
        if (config is null || e.Session is null || e.Item is null)
        {
            return;
        }

        var kind = GetKind(e.Item);
        var library = libraryManager.GetCollectionFolders(e.Item).FirstOrDefault();
        if (kind is null
            || !config.Enabled
            || string.IsNullOrWhiteSpace(config.DiscordApplicationId)
            || (library is not null && config.ExcludedLibraryIds.Contains(library.Id.ToString("N"), StringComparer.OrdinalIgnoreCase)))
        {
            RemoveSession(e);
            return;
        }

        var needsRemoteArtwork = !artwork.TryGetImmediate(e.Item, config, out var imageUrl);
        var state = BuildState(e, kind.Value, config, library, imageUrl);
        foreach (var user in e.Users)
        {
            hub.Update(user.Id, e.Session.Id, state);
        }

        if (needsRemoteArtwork)
        {
            // Show presence now; the poster follows when the lookup finishes.
            _ = AddRemoteArtworkAsync(e.Item, state.ItemId, e.Session.Id, [.. e.Users.Select(u => u.Id)]);
        }
    }

    private void RemoveSession(PlaybackProgressEventArgs e)
    {
        if (e.Session is null)
        {
            return;
        }

        foreach (var user in e.Users)
        {
            hub.Remove(user.Id, e.Session.Id);
        }
    }

    private async Task AddRemoteArtworkAsync(BaseItem item, string itemId, string sessionId, Guid[] userIds)
    {
        if (await artwork.ResolveRemoteAsync(item).ConfigureAwait(false) is { } url)
        {
            foreach (var userId in userIds)
            {
                hub.SetImage(userId, sessionId, itemId, url);
            }
        }
    }

    private static PresenceState BuildState(
        PlaybackProgressEventArgs e, MediaKind kind, PluginConfiguration config, Folder? library, string? imageUrl)
    {
        var item = e.Item;
        var state = new PresenceState
        {
            ApplicationId = config.DiscordApplicationId.Trim(),
            ItemId = item.Id.ToString("N"),
            Kind = kind,
            Name = item.Name,
            Year = item.ProductionYear,
            LibraryName = library?.Name,
            ImageUrl = imageUrl,
            IsPaused = e.IsPaused,
            PositionTicks = e.PlaybackPositionTicks ?? 0,
            RunTimeTicks = item.RunTimeTicks,
            SampledAt = DateTimeOffset.UtcNow,
            Links = config.IncludeExternalLinks ? GetLinks(item) : []
        };

        switch (item)
        {
            case Episode episode:
                state.SeriesName = episode.SeriesName;
                state.SeasonNumber = episode.ParentIndexNumber;
                state.EpisodeNumber = episode.IndexNumber;
                break;
            case Audio track:
                state.Album = track.Album;
                state.Artists = track.Artists.Count > 0 ? [.. track.Artists] : [.. track.AlbumArtists];
                break;
        }

        return state;
    }

    // Photos, books and anything else aren't worth showing.
    private static MediaKind? GetKind(BaseItem item) => item switch
    {
        Movie => MediaKind.Movie,
        Episode => MediaKind.Episode,
        _ when item.MediaType == MediaType.Audio => MediaKind.Audio,
        _ when item.MediaType == MediaType.Video => MediaKind.Video,
        _ => null
    };

    private static PresenceLink[] GetLinks(BaseItem item)
    {
        var links = new List<PresenceLink>();
        var source = item is Episode { Series: not null } episode ? episode.Series : item;

        if (source.TryGetProviderId(MetadataProvider.Imdb, out var imdb))
        {
            links.Add(new PresenceLink { Label = "IMDb", Url = $"https://www.imdb.com/title/{imdb}/" });
        }

        if (source.TryGetProviderId(MetadataProvider.Tmdb, out var tmdb))
        {
            var kind = source is Series ? "tv" : "movie";
            links.Add(new PresenceLink { Label = "TMDB", Url = $"https://www.themoviedb.org/{kind}/{tmdb}" });
        }

        if (item is Audio && item.TryGetProviderId(MetadataProvider.MusicBrainzAlbum, out var release))
        {
            links.Add(new PresenceLink { Label = "MusicBrainz", Url = $"https://musicbrainz.org/release/{release}" });
        }

        // Discord shows at most two buttons.
        return [.. links.Take(2)];
    }
}
