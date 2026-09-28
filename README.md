# jf-dp

Shows what you're watching or listening to on Jellyfin in your Discord status, with the poster, a progress bar and IMDb/TMDB links.

There are two parts: a **plugin** on your Jellyfin server and a small menu bar **app** on each user's Mac.

## Server

The plugin supports Jellyfin 10.11 and 12.0.

1. Create an application at [discord.com/developers](https://discord.com/developers/applications). Its name is what profiles show (e.g. "Watching Jellyfin"). Copy the **Application ID**.
2. In Jellyfin, open **Dashboard → Plugins → Manage Repositories** and add:
  ```
   https://raw.githubusercontent.com/sypion/jf-dp/main/manifest.json
  ```
3. Install **Discord Rich Presence** from the **Catalog** and restart Jellyfin.
4. In the plugin's settings, paste the Application ID. You can also exclude libraries there.

Updates install automatically and take effect after a restart.

## Users

You need macOS 14 or newer, and the Discord **desktop** app open on the same Mac.

1. Download **jf-dp_macos.dmg** from the [latest release](https://github.com/sypion/jf-dp/releases/latest/download/jf-dp_macos.dmg), open it, and drag **jf-dp** into **Applications**.
2. Open jf-dp from Applications and sign in with your Jellyfin server's address, username and password.

jf-dp then sits in the menu bar as a small TV icon. Click it to see what's showing and to choose whether to show your status while paused, the poster, the progress bar, the IMDb/TMDB buttons, and which libraries to hide. It updates itself: new versions install when it next quits, or from **Check for Updates…** in the menu. **Uninstall jf-dp…** at the bottom of that menu signs out and moves it to the Trash.

## License

jf-dp is free software: you can redistribute it and/or modify it under the terms of the [GNU General Public License v3.0](LICENSE).