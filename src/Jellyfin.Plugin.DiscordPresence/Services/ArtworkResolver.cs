using System.Collections.Concurrent;
using Jellyfin.Plugin.DiscordPresence.Configuration;
using MediaBrowser.Controller.Entities;
using MediaBrowser.Controller.Entities.Audio;
using MediaBrowser.Controller.Entities.TV;
using MediaBrowser.Controller.Providers;
using MediaBrowser.Model.Entities;
using MediaBrowser.Model.Providers;
using Microsoft.Extensions.Logging;

namespace Jellyfin.Plugin.DiscordPresence.Services;

/// <summary>
/// Finds a public image URL for an item. Discord downloads artwork itself, so LAN-only URLs won't load.
/// </summary>
public sealed class ArtworkResolver(IProviderManager providerManager, ILogger<ArtworkResolver> logger)
{
    // Discord's limit for image keys.
    private const int MaxUrlLength = 256;

    // Includes "nothing found", so items without artwork aren't looked up on every progress report.
    private readonly ConcurrentDictionary<Guid, string?> _remoteCache = new();

    /// <summary>Returns false when the URL needs a remote lookup (<see cref="ResolveRemoteAsync"/>).</summary>
    public bool TryGetImmediate(BaseItem item, PluginConfiguration config, out string? url)
    {
        var artItem = GetArtworkItem(item);
        switch (config.ArtworkSource)
        {
            case ArtworkSource.MetadataProviders:
                return _remoteCache.TryGetValue(artItem.Id, out url);
            case ArtworkSource.PublicServerUrl:
                url = BuildServerUrl(artItem, config.PublicServerUrl);
                return true;
            default:
                url = null;
                return true;
        }
    }

    /// <summary>Asks Jellyfin's remote image providers (TMDB, MusicBrainz, ...). Never throws.</summary>
    public async Task<string?> ResolveRemoteAsync(BaseItem item)
    {
        var artItem = GetArtworkItem(item);
        if (_remoteCache.TryGetValue(artItem.Id, out var cached))
        {
            return cached;
        }

        try
        {
            var images = await providerManager.GetAvailableRemoteImages(
                artItem,
                new RemoteImageQuery(string.Empty) { ImageType = ImageType.Primary },
                CancellationToken.None).ConfigureAwait(false);

            var url = images
                .Select(i => ShrinkTmdbUrl(i.Url))
                .FirstOrDefault(u => u is not null
                    && u.StartsWith("https://", StringComparison.OrdinalIgnoreCase)
                    && u.Length <= MaxUrlLength);

            _remoteCache[artItem.Id] = url;
            return url;
        }
        catch (Exception ex)
        {
            // Not cached: the provider may only be temporarily unreachable.
            logger.LogDebug(ex, "Remote artwork lookup failed for {Item}", artItem.Name);
            return null;
        }
    }

    // Series posters and album covers are more recognizable than episode stills or track images.
    private static BaseItem GetArtworkItem(BaseItem item) => item switch
    {
        Episode { Series: not null } episode => episode.Series,
        Audio { AlbumEntity: not null } track => track.AlbumEntity,
        _ => item
    };

    private static string? BuildServerUrl(BaseItem item, string baseUrl)
    {
        if (string.IsNullOrWhiteSpace(baseUrl) || !item.HasImage(ImageType.Primary, 0))
        {
            return null;
        }

        // Jellyfin serves item images without authentication.
        var url = $"{baseUrl.TrimEnd('/')}/Items/{item.Id:N}/Images/Primary?fillWidth=512&fillHeight=512&quality=90";
        return url.Length <= MaxUrlLength ? url : null;
    }

    // TMDB "original" posters are several MB; w500 is plenty for Discord.
    private static string? ShrinkTmdbUrl(string? url)
        => url?.Replace("image.tmdb.org/t/p/original/", "image.tmdb.org/t/p/w500/", StringComparison.Ordinal);
}
