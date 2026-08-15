using Jellyfin.Plugin.DiscordPresence.Services;
using MediaBrowser.Controller;
using MediaBrowser.Controller.Plugins;
using Microsoft.Extensions.DependencyInjection;

namespace Jellyfin.Plugin.DiscordPresence;

public class PluginServiceRegistrator : IPluginServiceRegistrator
{
    public void RegisterServices(IServiceCollection serviceCollection, IServerApplicationHost applicationHost)
    {
        serviceCollection.AddSingleton<PresenceHub>();
        serviceCollection.AddSingleton<ArtworkResolver>();
        serviceCollection.AddHostedService<PlaybackListener>();
    }
}
