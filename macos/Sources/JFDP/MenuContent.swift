import AppKit
import JFDPCore
import SwiftUI

struct MenuContent: View {
	@Bindable var model: AppModel
	let updates: Updates

	var body: some View {
		if let version = updates.availableVersion {
			Button("Update to jf-dp \(version)…") {
				updates.check()
			}
			Divider()
		}

		ForEach(statusLines, id: \.self) { line in
			Text(line)
		}

		Divider()

		Toggle("Show While Paused", isOn: $model.showWhenPaused)
		Toggle("Show Poster or Album Art", isOn: $model.showArtwork)
		Toggle("Show Progress Bar", isOn: $model.showProgress)
		Toggle("Show IMDb and TMDB Buttons", isOn: $model.showButtons)
		Menu("Hide Libraries") {
			if model.libraryChoices.isEmpty {
				Text(model.config.isSignedIn ? "No libraries found" : "Sign in to see your libraries")
			}
			ForEach(model.libraryChoices, id: \.self) { library in
				Toggle(library, isOn: Binding(
					get: { model.isHidden(library) },
					set: { model.setHidden(library, $0) }
				))
			}
		}

		Divider()

		Toggle("Open at Login", isOn: $model.opensAtLogin)
		Button(model.config.isSignedIn && model.status != .signInExpired ? "Account…" : "Sign In…") {
			AccountWindow.show(model: model)
		}

		Divider()

		Button("About jf-dp") {
			AboutPanel.show()
		}
		if updates.isAvailable {
			Button("Check for Updates…") {
				updates.check()
			}
		}

		Divider()

		Button("Uninstall jf-dp…") {
			Task { await confirmUninstall() }
		}
		Button("Quit jf-dp") {
			NSApp.terminate(nil)
		}
		.keyboardShortcut("q")
	}

	private var statusLines: [String] {
		switch model.status {
		case .signedOut:
			return ["Not signed in"]
		case .signInExpired:
			return ["Jellyfin signed you out. Sign in again."]
		case .connecting:
			return ["Connecting to Jellyfin…"]
		case let .offline(reason):
			return ["Can't reach Jellyfin. Retrying…", reason]
		case .following:
			guard let playing = model.playing else {
				return ["Nothing playing"]
			}
			let verb = playing.kind == .audio ? "Listening to" : "Watching"
			let title = playing.seriesName ?? playing.name
			if model.isPlayingHidden {
				return ["\(verb) \(title)", "Not shown on Discord (see settings below)"]
			}
			if model.discordMissing {
				return ["\(verb) \(title)", "Open the Discord app to show it there"]
			}
			return ["\(verb) \(title)" + (playing.isPaused ? " (paused)" : "")]
		}
	}

	private func confirmUninstall() async {
		NSApp.activate()
		let alert = NSAlert()
		alert.messageText = "Uninstall jf-dp?"
		alert.informativeText = "This signs you out, then moves jf-dp and its settings to the Trash. Your Discord status stops showing what you play on Jellyfin."
		alert.addButton(withTitle: "Uninstall")
		alert.addButton(withTitle: "Cancel")
		alert.buttons[0].hasDestructiveAction = true
		guard alert.runModal() == .alertFirstButtonReturn else {
			return
		}

		do {
			try await model.uninstall()
			NSApp.terminate(nil)
		} catch {
			let failure = NSAlert(error: error)
			failure.informativeText = "Drag jf-dp from your Applications folder to the Trash to finish uninstalling."
			failure.runModal()
		}
	}
}
