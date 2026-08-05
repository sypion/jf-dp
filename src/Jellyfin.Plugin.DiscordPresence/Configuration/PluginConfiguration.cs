using MediaBrowser.Model.Plugins;

namespace Jellyfin.Plugin.DiscordPresence.Configuration;

public enum ArtworkSource
{
    None,

    /// <summary>Public URLs from Jellyfin's metadata providers (TMDB, MusicBrainz, ...). Works for LAN-only servers.</summary>
    MetadataProviders,

    /// <summary>This server's image endpoint, via <see cref="PluginConfiguration.PublicServerUrl"/>.</summary>
    PublicServerUrl
}

/// <summary>
/// Server-wide settings. Per-user display preferences live in each user's companion app.
/// </summary>
public class PluginConfiguration : BasePluginConfiguration
{
    public bool Enabled { get; set; } = true;

    /// <summary>Gets or sets the Discord application ID; its name is what Discord shows as "Watching ...".</summary>
    public string DiscordApplicationId { get; set; } = string.Empty;

    public ArtworkSource ArtworkSource { get; set; } = ArtworkSource.MetadataProviders;

    public string PublicServerUrl { get; set; } = string.Empty;

    public bool IncludeExternalLinks { get; set; } = true;

    /// <summary>Gets or sets library IDs (no dashes) whose items are never shared.</summary>
    public string[] ExcludedLibraryIds { get; set; } = [];
}
