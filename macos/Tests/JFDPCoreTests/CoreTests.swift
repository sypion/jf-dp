import Foundation
@testable import JFDPCore
import Testing

// As the plugin serializes it: camelCase, string enums, and a .NET DateTimeOffset.
let episodeJSON = """
{"applicationId":"1234","itemId":"abc","kind":"Episode","name":"The Fire","year":2005,"seriesName":"The Office",
"seasonNumber":2,"episodeNumber":4,"album":null,"artists":[],"libraryName":"TV Shows",
"imageUrl":"https://example.com/poster.jpg","isPaused":false,"positionTicks":6000000000,"runTimeTicks":13200000000,
"sampledAt":"2026-10-02T12:00:00.1234567+00:00","links":[{"label":"IMDb","url":"https://imdb.com/a"},{"label":"TMDB","url":"https://tmdb.org/b"},{"label":"Extra","url":"https://x"}]}
"""

func episode(_ change: (inout PresenceState) -> Void = { _ in }) throws -> PresenceState {
	var state = try #require(try PresenceState.decode(Data(episodeJSON.utf8)))
	change(&state)
	return state
}

@Suite struct PresenceStateTests {
	@Test func decodesThePluginsJSON() throws {
		let state = try episode()
		#expect(state.kind == .episode)
		#expect(state.seriesName == "The Office")
		#expect(state.links.count == 3)
		#expect(abs(state.sampledAt.timeIntervalSince1970 - 1_790_942_400.123) < 0.001)
	}

	@Test func nullMeansNothingPlaying() throws {
		#expect(try PresenceState.decode(Data("null".utf8)) == nil)
	}

	@Test(arguments: ["2026-10-02T12:00:00Z", "2026-10-02T12:00:00.5Z", "2026-10-02T14:00:00.1234567+02:00"])
	func parsesDotNetDates(_ text: String) throws {
		let date = try #require(PresenceState.parseDate(text))
		#expect(abs(date.timeIntervalSince1970 - 1_790_942_400) < 1)
	}
}

@Suite struct ActivityTests {
	@Test func episodeReadsLikeTheCLI() throws {
		let activity = try #require(Activity.make(for: try episode(), config: Config()))
		#expect(activity.type == Activity.watching)
		#expect(activity.details == "The Office")
		#expect(activity.state == "S2E4 · The Fire")
		#expect(activity.assets?.largeImage == "https://example.com/poster.jpg")
		#expect(activity.buttons?.map(\.label) == ["IMDb", "TMDB"])
	}

	@Test func progressBarStartsWhereTheEpisodeBegan() throws {
		let activity = try #require(Activity.make(for: try episode(), config: Config()))
		// Sampled 600s in, at 1_790_942_400.123; 1320s long.
		#expect(activity.timestamps == .init(start: 1_790_941_800_123, end: 1_790_943_120_123))
	}

	@Test func pausedDropsTheProgressBar() throws {
		let activity = try #require(Activity.make(for: try episode { $0.isPaused = true }, config: Config()))
		#expect(activity.state == "S2E4 · The Fire · Paused")
		#expect(activity.timestamps == nil)
	}

	@Test func settingsHideThings() throws {
		var config = Config()
		config.showArtwork = false
		config.showProgress = false
		config.showButtons = false
		let activity = try #require(Activity.make(for: try episode(), config: config))
		#expect(activity.assets == nil && activity.timestamps == nil && activity.buttons == nil)

		config.showWhenPaused = false
		#expect(Activity.make(for: try episode { $0.isPaused = true }, config: config) == nil)

		config.hiddenLibraries = ["tv shows"]
		#expect(Activity.make(for: try episode(), config: config) == nil)
	}

	@Test func musicIsListening() throws {
		let song = try episode {
			$0.kind = .audio
			$0.name = "Song"
			$0.artists = ["A", "B"]
			$0.album = "Album"
		}
		let activity = try #require(Activity.make(for: song, config: Config()))
		#expect(activity.type == Activity.listening)
		#expect(activity.state == "A, B")
		#expect(activity.assets?.largeText == "Album")
	}

	@Test func clipsToDiscordsLimitWithoutSplittingCharacters() throws {
		let clipped = try #require(Activity.clip(String(repeating: "👩‍👩‍👧", count: 20)))
		#expect(clipped.utf8.count <= Activity.maxTextBytes)
		#expect(clipped.hasSuffix("…"))
		#expect(clipped.dropLast().allSatisfy { $0 == "👩‍👩‍👧" })
		#expect(Activity.clip("  ") == nil)
	}

	@Test func encodesDiscordsFieldNames() throws {
		let activity = try #require(Activity.make(for: try episode(), config: Config()))
		let json = try #require(String(data: DiscordConnection.encoder.encode(activity), encoding: .utf8))
		#expect(json.contains("\"status_display_type\":2"))
		#expect(json.contains("\"large_image\":\"https://example.com/poster.jpg\""))
	}
}

@Suite struct ConfigTests {
	@Test func readsTheCLIsFile() throws {
		let json = """
		{
		  "ServerUrl": "http://nas:8096",
		  "UserName": "chris",
		  "AccessToken": "token",
		  "DeviceId": "40aa5de355794556a772088ac2e23cc7",
		  "ShowWhenPaused": true,
		  "ShowArtwork": false,
		  "ShowProgress": true,
		  "ShowButtons": true,
		  "HiddenLibraries": ["Kids"]
		}
		"""
		let config = try JSONDecoder().decode(Config.self, from: Data(json.utf8))
		#expect(config.isSignedIn)
		#expect(config.deviceId == "40aa5de355794556a772088ac2e23cc7")
		#expect(!config.showArtwork)
		#expect(config.hiddenLibraries == ["Kids"])
	}

	@Test func missingKeysKeepTheirDefaults() throws {
		let config = try JSONDecoder().decode(Config.self, from: Data(#"{"ServerUrl":"http://nas:8096"}"#.utf8))
		#expect(config.showWhenPaused && config.showButtons)
		#expect(config.deviceId.count == 32)
		#expect(!config.isSignedIn)
	}

	@Test func savesOwnerOnly() throws {
		let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString).appending(path: "config.json")
		defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }

		var config = Config()
		config.accessToken = "secret"
		try config.save(to: url)
		#expect(try Config.load(from: url) == config)
		let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
		#expect(permissions == 0o600)
		// The CLI writes nulls rather than leaving keys out.
		#expect(try String(contentsOf: url, encoding: .utf8).contains("\"ServerUrl\" : null"))
	}
}

@Suite struct JellyfinClientTests {
	@Test(arguments: [
		("192.168.1.10:8096", "http://192.168.1.10:8096"),
		("  https://jellyfin.example.com/  ", "https://jellyfin.example.com"),
		("http://nas.local:8096/jellyfin/", "http://nas.local:8096/jellyfin"),
	])
	func acceptsWhatPeopleType(_ input: String, _ expected: String) {
		#expect(JellyfinClient.normalizeServerURL(input)?.absoluteString == expected)
	}

	@Test(arguments: ["", "ftp://nas", "http://"])
	func rejectsWhatIsntAServer(_ input: String) {
		#expect(JellyfinClient.normalizeServerURL(input) == nil)
	}

	@Test func keepsTheServersPathPrefix() throws {
		let client = JellyfinClient(serverURL: try #require(URL(string: "http://nas/jellyfin")), deviceId: "d", deviceName: "Mac", clientVersion: "1.0.0", token: nil)
		#expect(client.makeRequest("GET", "DiscordPresence/Me").url?.absoluteString == "http://nas/jellyfin/DiscordPresence/Me")
	}

	@Test func encodesTheAuthorizationHeader() throws {
		let client = JellyfinClient(serverURL: try #require(URL(string: "http://nas")), deviceId: "d1", deviceName: "Chris's \"Mac\", 2", clientVersion: "1.2.0", token: "t/k")
		#expect(client.authorizationHeader == #"MediaBrowser Client="jf-dp", Device="Chris%27s%20%22Mac%22%2C%202", DeviceId="d1", Version="1.2.0", Token="t%2Fk""#)
	}

	@Test func readsOnlyDataLines() {
		#expect(JellyfinClient.eventData("data: null") == Data(" null".utf8))
		#expect(JellyfinClient.eventData("event: presence") == nil)
		#expect(JellyfinClient.eventData(": keep-alive") == nil)
	}
}

@Suite struct DiscordTests {
	@Test func framesAreLittleEndianOpcodeAndLength() {
		let frame = DiscordConnection.frame(.frame, Data("{}".utf8))
		#expect(Array(frame) == [1, 0, 0, 0, 2, 0, 0, 0, 0x7B, 0x7D])
	}

	@Test func looksInTheTemporaryFolders() {
		let paths = DiscordConnection.socketPaths(environment: ["TMPDIR": "/var/folders/x/T/"])
		#expect(paths.first == "/var/folders/x/T/discord-ipc-0")
		#expect(paths.contains("/tmp/discord-ipc-9"))
		#expect(Set(paths).count == paths.count)
	}
}
