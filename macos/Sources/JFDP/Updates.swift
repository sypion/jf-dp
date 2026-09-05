import AppKit
import Observation
import Sparkle

/// Sparkle self-updates.
@MainActor
@Observable
final class Updates: NSObject, SPUStandardUserDriverDelegate {
	/// A scheduled check found this version, and it's waiting in the menu.
	private(set) var availableVersion: String?
	/// Whether this build updates itself; dev builds don't.
	private(set) var isAvailable = false
	@ObservationIgnored private var controller: SPUStandardUpdaterController?

	// Builds without a feed and a signing key (every dev build) don't update.
	static var configured: Bool {
		let info = Bundle.main.infoDictionary ?? [:]
		return (info["SUFeedURL"] as? String)?.isEmpty == false && (info["SUPublicEDKey"] as? String)?.isEmpty == false
	}

	func start() {
		guard Self.configured else { return }
		let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: self)
		self.controller = controller
		isAvailable = true

		// Sparkle checks once a day on its own; check at every launch too, so nobody waits a day for a fix.
		// Still off if someone has turned automatic checks off in Sparkle's update window.
		if controller.updater.automaticallyChecksForUpdates {
			controller.updater.checkForUpdatesInBackground()
		}
	}

	func check() {
		NSApp.activate()
		controller?.checkForUpdates(nil)
	}

	nonisolated var supportsGentleScheduledUpdateReminders: Bool { true }

	// Near launch, or after the Mac's been idle, Sparkle shows it in front itself otherwise it waits in the menu.
	nonisolated func standardUserDriverShouldHandleShowingScheduledUpdate(_ update: SUAppcastItem, andInImmediateFocus immediateFocus: Bool) -> Bool {
		immediateFocus
	}

	nonisolated func standardUserDriverWillHandleShowingUpdate(_ handleShowingUpdate: Bool, forUpdate update: SUAppcastItem, state: SPUUserUpdateState) {
		let version = update.displayVersionString
		MainActor.assumeIsolated {
			if handleShowingUpdate {
				NSApp.activate()
			} else {
				availableVersion = version
			}
		}
	}

	nonisolated func standardUserDriverDidReceiveUserAttention(forUpdate update: SUAppcastItem) {
		MainActor.assumeIsolated { availableVersion = nil }
	}

	nonisolated func standardUserDriverWillFinishUpdateSession() {
		MainActor.assumeIsolated { availableVersion = nil }
	}
}
