import Foundation

public struct Config: Codable, Equatable, Sendable {
	public var serverUrl: String?
	public var userName: String?
	public var accessToken: String?
	public var deviceId: String = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
	public var showWhenPaused = true
	public var showArtwork = true
	public var showProgress = true
	public var showButtons = true
	public var hiddenLibraries: [String] = []

	public init() {}

	public var isSignedIn: Bool { serverUrl != nil && accessToken != nil }

	enum CodingKeys: String, CodingKey {
		case serverUrl = "ServerUrl"
		case userName = "UserName"
		case accessToken = "AccessToken"
		case deviceId = "DeviceId"
		case showWhenPaused = "ShowWhenPaused"
		case showArtwork = "ShowArtwork"
		case showProgress = "ShowProgress"
		case showButtons = "ShowButtons"
		case hiddenLibraries = "HiddenLibraries"
	}

	// Missing keys keep their defaults
	public init(from decoder: Decoder) throws {
		let c = try decoder.container(keyedBy: CodingKeys.self)
		serverUrl = try c.decodeIfPresent(String.self, forKey: .serverUrl)
		userName = try c.decodeIfPresent(String.self, forKey: .userName)
		accessToken = try c.decodeIfPresent(String.self, forKey: .accessToken)
		deviceId = try c.decodeIfPresent(String.self, forKey: .deviceId) ?? deviceId
		showWhenPaused = try c.decodeIfPresent(Bool.self, forKey: .showWhenPaused) ?? showWhenPaused
		showArtwork = try c.decodeIfPresent(Bool.self, forKey: .showArtwork) ?? showArtwork
		showProgress = try c.decodeIfPresent(Bool.self, forKey: .showProgress) ?? showProgress
		showButtons = try c.decodeIfPresent(Bool.self, forKey: .showButtons) ?? showButtons
		hiddenLibraries = try c.decodeIfPresent([String].self, forKey: .hiddenLibraries) ?? hiddenLibraries
	}

	public func encode(to encoder: Encoder) throws {
		var c = encoder.container(keyedBy: CodingKeys.self)
		// Written as null rather than left out
		try c.encode(serverUrl, forKey: .serverUrl)
		try c.encode(userName, forKey: .userName)
		try c.encode(accessToken, forKey: .accessToken)
		try c.encode(deviceId, forKey: .deviceId)
		try c.encode(showWhenPaused, forKey: .showWhenPaused)
		try c.encode(showArtwork, forKey: .showArtwork)
		try c.encode(showProgress, forKey: .showProgress)
		try c.encode(showButtons, forKey: .showButtons)
		try c.encode(hiddenLibraries, forKey: .hiddenLibraries)
	}
}

extension Config {
	static let customDirectory = ProcessInfo.processInfo.environment["JF_DP_CONFIG"].flatMap { $0.isEmpty ? nil : URL(fileURLWithPath: $0, isDirectory: true) }

	public static let directoryURL = customDirectory
		?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0].appending(path: "jf-dp", directoryHint: .isDirectory)

	public static let fileURL = directoryURL.appending(path: "config.json")

	public static var isCustomDirectory: Bool { customDirectory != nil }

	public static func load(from url: URL = fileURL) throws -> Config {
		guard FileManager.default.fileExists(atPath: url.path) else {
			return Config()
		}
		return try JSONDecoder().decode(Config.self, from: Data(contentsOf: url))
	}

	public func save(to url: URL = Config.fileURL) throws {
		let encoder = JSONEncoder()
		encoder.outputFormatting = [.prettyPrinted, .withoutEscapingSlashes]
		try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
		try encoder.encode(self).write(to: url, options: .atomic)
		try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
	}
}
