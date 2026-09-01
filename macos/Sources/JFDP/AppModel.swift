import AppKit
import JFDPCore
import ServiceManagement
import SystemConfiguration

@MainActor
@Observable
final class AppModel {
	enum Status: Equatable {
		case signedOut
		case connecting
		case following
		case offline(String)
		/// The server stopped accepting the token.
		case signInExpired
	}

	private(set) var config: Config
	private(set) var status: Status
	/// What's playing, or nil.
	private(set) var playing: PresenceState?
	/// Something should be on Discord but Discord isn't running.
	private(set) var discordMissing = false
	/// The user's libraries, for the Hide Libraries menu.
	private(set) var libraries: [String] = []

	private let discord = DiscordPresenter()
	private let (discordUpdates, requestDiscordUpdate) = AsyncStream.makeStream(of: Void.self, bufferingPolicy: .bufferingNewest(1))
	private var following: Task<Void, Never>?
	private var discordRetry: Task<Void, Never>?
	private var reconnectDelay = Duration.seconds(2)

	init() {
		config = (try? Config.load()) ?? Config()
		status = .signedOut

		Task { [weak self, discordUpdates] in
			for await _ in discordUpdates {
				await self?.updateDiscord()
			}
		}

		NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
			// The connection rarely survives sleep; don't wait out the timeout or the backoff.
			MainActor.assumeIsolated {
				if self?.config.isSignedIn == true {
					self?.startFollowing()
				}
			}
		}

		if config.isSignedIn {
			startFollowing()
		}
	}

	// Display settings

	var showWhenPaused: Bool {
		get { config.showWhenPaused }
		set { changeSettings { $0.showWhenPaused = newValue } }
	}

	var showArtwork: Bool {
		get { config.showArtwork }
		set { changeSettings { $0.showArtwork = newValue } }
	}

	var showProgress: Bool {
		get { config.showProgress }
		set { changeSettings { $0.showProgress = newValue } }
	}

	var showButtons: Bool {
		get { config.showButtons }
		set { changeSettings { $0.showButtons = newValue } }
	}

	var libraryChoices: [String] {
		libraries + config.hiddenLibraries.filter { hidden in !libraries.contains { $0.caseInsensitiveCompare(hidden) == .orderedSame } }
	}

	func isHidden(_ library: String) -> Bool {
		config.hiddenLibraries.contains { $0.caseInsensitiveCompare(library) == .orderedSame }
	}

	func setHidden(_ library: String, _ hidden: Bool) {
		changeSettings { config in
			config.hiddenLibraries.removeAll { $0.caseInsensitiveCompare(library) == .orderedSame }
			if hidden {
				config.hiddenLibraries.append(library)
			}
		}
	}

	/// Whether what's playing is kept off Discord by the settings.
	var isPlayingHidden: Bool {
		playing != nil && Activity.make(for: playing, config: config) == nil
	}

	private func changeSettings(_ change: (inout Config) -> Void) {
		change(&config)
		save()
		requestDiscordUpdate.yield()
	}

	// Open at login

	var opensAtLogin: Bool {
		get { SMAppService.mainApp.status == .enabled }
		set {
			do {
				if newValue {
					try SMAppService.mainApp.register()
				} else {
					try SMAppService.mainApp.unregister()
				}
			} catch {
				NSAlert(error: error).runModal()
			}
		}
	}

	// Account

	func signIn(server: String, userName: String, password: String, openAtLogin: Bool) async throws {
		guard let serverURL = JellyfinClient.normalizeServerURL(server) else {
			throw JellyfinError.invalidServerURL
		}

		let token = try await client(serverURL, token: nil).logIn(userName: userName, password: password)
		let signedIn = client(serverURL, token: token)
		do {
			try await signedIn.checkPlugin()
		} catch {
			// Don't leave an unused session on the server.
			try? await signedIn.logOut()
			throw error
		}

		stopFollowing()
		config.serverUrl = serverURL.absoluteString
		config.userName = userName
		config.accessToken = token
		save()

		if openAtLogin, !opensAtLogin {
			opensAtLogin = true
		}
		startFollowing()
	}

	func signOut() {
		let session = currentClient()
		stopFollowing()
		config.accessToken = nil
		save()
		status = .signedOut
		libraries = []
		Task {
			// Revoke it on the server too; it's already gone here if the server can't be reached.
			try? await session?.logOut()
		}
	}

	/// Signs out, then moves the app and its settings to the Trash
	func uninstall() async throws {
		let session = currentClient()
		stopFollowing()
		await discord.disconnect()
		try? await session?.logOut()
		try? await SMAppService.mainApp.unregister()

		// Only the settings file goes from a JF_DP_CONFIG folder, which may hold other things.
		let settings = Config.isCustomDirectory ? Config.fileURL : Config.directoryURL
		var items = [settings, Bundle.main.bundleURL]
		if let bundleID = Bundle.main.bundleIdentifier {
			// Sparkle's download cache. Its preferences (when it last checked) go with the defaults below.
			items.append(FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appending(path: bundleID))
			UserDefaults.standard.removePersistentDomain(forName: bundleID)
		}
		_ = try await NSWorkspace.shared.recycle(items.filter { FileManager.default.fileExists(atPath: $0.path) })
	}

	// Following playback

	private func startFollowing() {
		stopFollowing()
		reconnectDelay = .seconds(2)
		following = Task { await follow() }
	}

	private func stopFollowing() {
		following?.cancel()
		following = nil
		show(nil)
	}

	private func follow() async {
		while !Task.isCancelled, let client = currentClient() {
			if case .offline = status {} else {
				status = .connecting
			}
			Task { [weak self] in
				guard let names = try? await client.libraryNames() else { return }
				self?.libraries = names
			}

			do {
				try await client.streamPresence { [weak self] state in
					await self?.received(state)
				}
				status = .offline("The server closed the connection.")
			} catch is CancellationError {
				return
			} catch let error as URLError where error.code == .cancelled {
				return
			} catch JellyfinError.sessionExpired {
				show(nil)
				status = .signInExpired
				return
			} catch {
				status = .offline(error.localizedDescription)
			}

			// Don't leave a stale "Watching" up while disconnected.
			show(nil)
			guard (try? await Task.sleep(for: reconnectDelay)) != nil else { return }
			reconnectDelay = min(reconnectDelay * 2, .seconds(60))
		}
	}

	private func received(_ state: PresenceState?) {
		guard following?.isCancelled == false else { return }
		status = .following
		reconnectDelay = .seconds(2)
		show(state)
	}

	private func show(_ state: PresenceState?) {
		playing = state
		requestDiscordUpdate.yield()
	}

	private func updateDiscord() async {
		let activity = Activity.make(for: playing, config: config)
		let shown = await discord.show(activity, applicationID: playing?.applicationId)
		discordMissing = !shown

		// Discord may be opened later; keep trying while there's something to show.
		discordRetry?.cancel()
		if !shown {
			discordRetry = Task { [requestDiscordUpdate] in
				guard (try? await Task.sleep(for: .seconds(10))) != nil else { return }
				requestDiscordUpdate.yield()
			}
		}
	}

	// Helpers

	private func currentClient() -> JellyfinClient? {
		guard let server = config.serverUrl.flatMap(URL.init(string:)), let token = config.accessToken else {
			return nil
		}
		return client(server, token: token)
	}

	private func client(_ server: URL, token: String?) -> JellyfinClient {
		JellyfinClient(
			serverURL: server,
			deviceId: config.deviceId,
			deviceName: SCDynamicStoreCopyComputerName(nil, nil) as String? ?? "Mac",
			clientVersion: Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0.0",
			token: token
		)
	}

	private func save() {
		do {
			try config.save()
		} catch {
			NSAlert(error: error).runModal()
		}
	}
}
