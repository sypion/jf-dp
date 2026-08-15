using System.Net.Mime;
using System.Text.Json;
using Jellyfin.Plugin.DiscordPresence.Models;
using Jellyfin.Plugin.DiscordPresence.Services;
using MediaBrowser.Controller.Net;
using Microsoft.AspNetCore.Authorization;
using Microsoft.AspNetCore.Http;
using Microsoft.AspNetCore.Http.Features;
using Microsoft.AspNetCore.Mvc;

namespace Jellyfin.Plugin.DiscordPresence.Api;

/// <summary>
/// Endpoints the companion app uses to follow the signed-in user's playback.
/// </summary>
[ApiController]
[Authorize]
[Route("DiscordPresence")]
public class PresenceController(PresenceHub hub, IAuthorizationContext authContext) : ControllerBase
{
    private const string ApiKeyNotSupported = "Sign in as a user; API keys aren't tied to a user's playback.";

    // Keeps reverse proxies (nginx defaults to 60s) from closing an idle stream.
    private static readonly TimeSpan HeartbeatInterval = TimeSpan.FromSeconds(20);

    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web);

    /// <response code="200">What the user is playing.</response>
    /// <response code="204">Nothing is playing.</response>
    [HttpGet("Me")]
    [Produces(MediaTypeNames.Application.Json)]
    public async Task<ActionResult<PresenceState>> GetCurrent()
    {
        if (await GetUserIdAsync().ConfigureAwait(false) is not { } userId)
        {
            return BadRequest(ApiKeyNotSupported);
        }

        return hub.GetCurrent(userId) is { } state ? state : NoContent();
    }

    /// <summary>
    /// Server-sent events: a <c>presence</c> event now and on every change, with a
    /// <see cref="PresenceState"/> or <c>null</c> (nothing playing) as data.
    /// </summary>
    [HttpGet("Me/Stream")]
    [Produces("text/event-stream")]
    public async Task<IActionResult> Stream(CancellationToken cancellationToken)
    {
        if (await GetUserIdAsync().ConfigureAwait(false) is not { } userId)
        {
            return BadRequest(ApiKeyNotSupported);
        }

        Response.ContentType = "text/event-stream";
        Response.Headers.CacheControl = "no-cache";
        Response.Headers["X-Accel-Buffering"] = "no";
        HttpContext.Features.Get<IHttpResponseBodyFeature>()?.DisableBuffering();

        using var subscription = hub.Subscribe(userId);
        try
        {
            while (true)
            {
                using var heartbeat = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                heartbeat.CancelAfter(HeartbeatInterval);

                string message;
                try
                {
                    var state = await subscription.Reader.ReadAsync(heartbeat.Token).ConfigureAwait(false);
                    message = $"event: presence\ndata: {JsonSerializer.Serialize(state, JsonOptions)}\n\n";
                }
                catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
                {
                    message = ": keep-alive\n\n";
                }

                await Response.WriteAsync(message, cancellationToken).ConfigureAwait(false);
                await Response.Body.FlushAsync(cancellationToken).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException)
        {
            // Client disconnected.
        }

        return new EmptyResult();
    }

    private async Task<Guid?> GetUserIdAsync()
    {
        var auth = await authContext.GetAuthorizationInfo(HttpContext).ConfigureAwait(false);
        return auth.UserId == Guid.Empty ? null : auth.UserId;
    }
}
