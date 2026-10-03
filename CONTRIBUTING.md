# Contributing to jf-dp

For installing and using it, see the [README](README.md).

## Overview

Discord only accepts a status from the computer it's running on, so jf-dp has a server half and a desktop half:

1. **The plugin** (`src/Jellyfin.Plugin.DiscordPresence`) runs inside Jellyfin. It watches playback and streams each user's `PresenceState` to them as server-sent events from `GET /DiscordPresence/Me/Stream`.
2. **The menu bar app** (`macos/`, Swift) on the user's Mac signs in as that user, follows the stream, and turns each state into a Discord activity over Discord's local IPC socket.

The wire format is defined twice, in `src/Jellyfin.Plugin.DiscordPresence/Models/PresenceState.cs` and `macos/Sources/JFDPCore/PresenceState.swift`. When you change one, change the other in the same pull request.

## Layout

```
src/Jellyfin.Plugin.DiscordPresence/      The Jellyfin plugin (Jellyfin 10.11 and 12.0)
macos/                                    The menu bar app (Swift package)
  Sources/JFDPCore/                       No UI: settings, the Jellyfin client, the Discord IPC client
  Sources/JFDP/                           The app: menu, sign-in window, updates, moving to Applications
  Tests/JFDPCoreTests/                    swift-testing tests
  packaging/                              App icon, the dmg background and window layout
  scripts/                                bundle.sh, release.sh, ci.sh, make-dmg.sh, make-icon.swift, make-dmg-background.swift
manifest.json                             The plugin repository Jellyfin servers read (updated by releases)
```



## The plugin

You need the [.NET 10 SDK](https://dotnet.microsoft.com/download/dotnet/10.0). It builds for both Jellyfin release lines:

```sh
dotnet build -c Release -warnaserror
```

Each Jellyfin line runs on its own .NET, so the plugin is built once per line, set in the project's `TargetFrameworks`:

| Build | Jellyfin | Version |
| --- | --- | --- |
| `net9.0` | 10.11 | `X.Y.Z.0` |
| `net10.0` | 12.0 and newer | `X.Y.Z.1` |

To try a plugin change on a server, copy the matching `src/Jellyfin.Plugin.DiscordPresence/bin/Release/<build>/Jellyfin.Plugin.DiscordPresence.dll` into a folder in your server's `plugins` directory and restart Jellyfin. Every build on GitHub also uploads both DLLs as the `plugin-dll` artifact.

Each build's `JellyfinVersion` is the oldest server it runs on, and releases copy it into `manifest.json` as that build's `targetAbi`. Servers install the highest version whose `targetAbi` they meet, so a 12.0 server takes `X.Y.Z.1` and a 10.11 server takes `X.Y.Z.0`. When a new Jellyfin line needs its own build, add a target framework with the next `PluginRevision`.

## The macOS app

You need macOS 14 or newer and Xcode 16 or newer. The scripts use `/Applications/Xcode.app` when `xcode-select` points at the Command Line Tools.

```sh
cd macos
swift test                                    # unit tests
scripts/bundle.sh && open build/jf-dp.app     # dev build
```

Dev builds use the bundle id `io.github.sypion.jf-dp.dev`, are signed ad hoc, and never update themselves. Two environment variables help when testing:

- `JF_DP_CONFIG` points the app at another settings folder.
- `XDG_RUNTIME_DIR` is the first folder it looks in for Discord's `discord-ipc-0` socket, ahead of `$TMPDIR`. Point it at a fake Discord to keep tests off your real status. Socket paths can't be longer than 104 bytes, so use a short folder.

The app reads both when it starts, so pass them with `open --env`, or run `build/jf-dp.app/Contents/MacOS/jf-dp` directly.

To change the icon, edit `scripts/make-icon.swift` and run `swift scripts/make-icon.swift` from `macos/`. It rewrites `packaging/AppIcon.icns`.

## Pull requests

`build.yml` runs on every pull request. It builds the plugin with warnings as errors, then runs the Swift tests and a dev build of the macOS app on a macOS runner. Run the same commands locally first.

### The macOS app's updates

Each macOS release carries the app three ways:

- `jf-dp_macos.dmg`, for new installs
- `jf-dp_macos.zip` and `appcast.xml`, for [Sparkle](https://sparkle-project.org) updates

Installed apps read `https://github.com/sypion/jf-dp/releases/latest/download/appcast.xml` each time they open, and once a day while they stay open. Updates download in the background and install when the app quits.