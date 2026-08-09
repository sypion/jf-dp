using System.Text.Json.Serialization;

// Shared with the companion app, so it must not reference Jellyfin types.
namespace Jellyfin.Plugin.DiscordPresence.Models;

[JsonConverter(typeof(JsonStringEnumConverter<MediaKind>))]
public enum MediaKind
{
    Movie,
    Episode,
    Audio,
    Video
}

/// <summary>What a user is playing. Raw fields, so the companion decides how it reads on Discord.</summary>
public sealed record PresenceState
{
    public string ApplicationId { get; set; } = string.Empty;

    public string ItemId { get; set; } = string.Empty;

    public MediaKind Kind { get; set; }

    public string Name { get; set; } = string.Empty;

    public int? Year { get; set; }

    public string? SeriesName { get; set; }

    public int? SeasonNumber { get; set; }

    public int? EpisodeNumber { get; set; }

    public string? Album { get; set; }

    public string[] Artists { get; set; } = [];

    public string? LibraryName { get; set; }

    public string? ImageUrl { get; set; }

    public bool IsPaused { get; set; }

    public long PositionTicks { get; set; }

    public long? RunTimeTicks { get; set; }

    /// <summary>Gets or sets when <see cref="PositionTicks"/> was sampled; positions are extrapolated from here.</summary>
    public DateTimeOffset SampledAt { get; set; }

    public PresenceLink[] Links { get; set; } = [];
}

public sealed class PresenceLink
{
    public string Label { get; set; } = string.Empty;

    public string Url { get; set; } = string.Empty;
}
