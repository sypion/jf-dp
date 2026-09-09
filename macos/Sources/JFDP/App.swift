import AppKit
import SwiftUI

@main
struct JFDPApp: App {
	@NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

	var body: some Scene {
		MenuBarExtra {
			MenuContent(model: delegate.model, updates: delegate.updates)
		} label: {
			MenuBarIcon(model: delegate.model)
		}
		.menuBarExtraStyle(.menu)
	}
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
	let model = AppModel()
	let updates = Updates()

	func applicationDidFinishLaunching(_ notification: Notification) {
		if Relocation.offerMoveToApplications() {
			return
		}
		updates.start()

		if !model.config.isSignedIn || model.status == .signInExpired {
			AccountWindow.show(model: model)
		}
	}

	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		AccountWindow.show(model: model)
		return false
	}
}

struct MenuBarIcon: View {
	let model: AppModel

	var body: some View {
		let symbol = switch model.status {
		case .following where model.playing != nil && !model.isPlayingHidden: "play.tv.fill"
		case .following, .connecting: "play.tv"
		case .signedOut, .offline, .signInExpired: "tv.slash"
		}
		Image(systemName: symbol)
			.accessibilityLabel("jf-dp")
	}
}
