import AppKit

/// Opening the app straight from the disk image is an easy mistake. Pffer to copy it to Applications.
@MainActor
enum Relocation {
	/// Returns true when it's relaunching from Applications, so this copy is about to quit.
	static func offerMoveToApplications() -> Bool {
		let bundle = Bundle.main.bundleURL
		guard bundle.path.hasPrefix("/Volumes/") || bundle.path.contains("/AppTranslocation/") else {
			return false
		}

		NSApp.activate()
		let alert = NSAlert()
		alert.messageText = "Move jf-dp to your Applications folder?"
		alert.informativeText = "It's running from the disk image, so it can't open when you log in, and it stops working once the disk image is ejected."
		alert.addButton(withTitle: "Move to Applications")
		alert.addButton(withTitle: "Not Now")
		guard alert.runModal() == .alertFirstButtonReturn else {
			return false
		}

		let destination = URL(filePath: "/Applications", directoryHint: .isDirectory).appending(path: bundle.lastPathComponent)
		do {
			if FileManager.default.fileExists(atPath: destination.path) {
				try FileManager.default.trashItem(at: destination, resultingItemURL: nil)
			}
			try FileManager.default.copyItem(at: bundle, to: destination)
		} catch {
			let failure = NSAlert(error: error)
			failure.informativeText = "Drag jf-dp into the Applications folder yourself, then open it from there."
			failure.runModal()
			return false
		}

		let configuration = NSWorkspace.OpenConfiguration()
		configuration.createsNewApplicationInstance = true
		NSWorkspace.shared.openApplication(at: destination, configuration: configuration) { _, _ in
			DispatchQueue.main.async { NSApp.terminate(nil) }
		}
		return true
	}
}
