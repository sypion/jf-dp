using Jellyfin.Plugin.DiscordPresence.Configuration;
using MediaBrowser.Common.Configuration;
using MediaBrowser.Common.Plugins;
using MediaBrowser.Model.Plugins;
using MediaBrowser.Model.Serialization;

namespace Jellyfin.Plugin.DiscordPresence;

public class Plugin : BasePlugin<PluginConfiguration>, IHasWebPages
{
    public Plugin(IApplicationPaths applicationPaths, IXmlSerializer xmlSerializer)
        : base(applicationPaths, xmlSerializer)
    {
        Instance = this;
    }

    public override string Name => "Discord Rich Presence";

    public override Guid Id => Guid.Parse("bef32adf-0271-405b-97eb-aa01d658ef21");

    public override string Description => "Shows what users are playing on their Discord profile, via a companion app.";

    public static Plugin? Instance { get; private set; }

    public IEnumerable<PluginPageInfo> GetPages() =>
    [
        new PluginPageInfo
        {
            Name = Name,
            EmbeddedResourcePath = $"{GetType().Namespace}.Configuration.configPage.html"
        }
    ];
}
