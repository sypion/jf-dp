import Foundation

public enum JellyfinError: LocalizedError, Equatable {
	case invalidServerURL
	case wrongCredentials
	case sessionExpired
	case pluginMissing
	case unexpectedResponse(Int)

	public var errorDescription: String? {
		switch self {
		case .invalidServerURL:
			"Enter your server's address, like 192.168.1.10:8096 or https://jellyfin.example.com."
		case .wrongCredentials:
			"Wrong username or password."
		case .sessionExpired:
			"Jellyfin no longer accepts this sign-in. Sign in again."
		case .pluginMissing:
			"This server doesn't have the Discord Rich Presence plugin. Ask whoever runs it to install the plugin."
		case let .unexpectedResponse(status):
			"The server answered with an error (HTTP \(status))."
		}
	}
}

public final class JellyfinClient: Sendable {
	public let serverURL: URL
	let deviceId: String
	let deviceName: String
	let clientVersion: String
	let token: String?
	let session: URLSession

	public init(serverURL: URL, deviceId: String, deviceName: String, clientVersion: String, token: String?, session: URLSession = .shared) {
		self.serverURL = serverURL
		self.deviceId = deviceId
		self.deviceName = deviceName
		self.clientVersion = clientVersion
		self.token = token
		self.session = session
	}

	/// Accepts what people tend to type
	public static func normalizeServerURL(_ input: String) -> URL? {
		var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
		if !text.contains("://") {
			text = "http://" + text
		}
		while text.hasSuffix("/") {
			text.removeLast()
		}

		guard let url = URL(string: text),
		      let scheme = url.scheme?.lowercased(), scheme == "http" || scheme == "https",
		      let host = url.host(), !host.isEmpty
		else {
			return nil
		}
		return url
	}

	/// Signs in and returns the new access token.
	public func logIn(userName: String, password: String) async throws -> String {
		var request = makeRequest("POST", "Users/AuthenticateByName")
		request.setValue("application/json", forHTTPHeaderField: "Content-Type")
		request.httpBody = try JSONEncoder().encode(["Username": userName, "Pw": password])
		let (data, response) = try await session.data(for: request)
		if status(response) == 401 {
			throw JellyfinError.wrongCredentials
		}
		try check(response)

		struct Result: Decodable {
			var AccessToken: String?
		}
		guard let token = try JSONDecoder().decode(Result.self, from: data).AccessToken else {
			throw JellyfinError.unexpectedResponse(status(response))
		}
		return token
	}

	public func logOut() async throws {
		_ = try await session.data(for: makeRequest("POST", "Sessions/Logout"))
	}

	/// Checks that the token works and the plugin is installed
	public func checkPlugin() async throws {
		let (_, response) = try await session.data(for: makeRequest("GET", "DiscordPresence/Me"))
		try check(response)
	}

	/// The libraries the user can see, for choosing which to hide
	public func libraryNames() async throws -> [String] {
		let (data, response) = try await session.data(for: makeRequest("GET", "UserViews"))
		try check(response)

		struct Views: Decodable {
			struct Item: Decodable {
				var Name: String
				var CollectionType: String?
			}

			var Items: [Item]
		}
		// Playlists and collections aren't where items live. The plugin never reports them as the library.
		return try JSONDecoder().decode(Views.self, from: data).Items
			.filter { !["playlists", "boxsets"].contains($0.CollectionType?.lowercased()) }
			.map(\.Name)
	}

	public func streamPresence(onUpdate: @Sendable (PresenceState?) async -> Void) async throws {
		var request = makeRequest("GET", "DiscordPresence/Me/Stream")
		request.timeoutInterval = 60
		let (bytes, response) = try await session.bytes(for: request)
		try check(response)

		for try await line in bytes.lines {
			if let data = Self.eventData(line) {
				await onUpdate(try PresenceState.decode(data))
			}
		}
	}

	static func eventData(_ line: String) -> Data? {
		guard line.hasPrefix("data:") else {
			return nil
		}
		return Data(line.dropFirst("data:".count).utf8)
	}

	func makeRequest(_ method: String, _ path: String) -> URLRequest {
		var request = URLRequest(url: serverURL.appending(path: path))
		request.httpMethod = method
		request.setValue(authorizationHeader, forHTTPHeaderField: "Authorization")
		return request
	}

	var authorizationHeader: String {
		// Jellyfin URL-decodes each value, so encode them (device names can contain quotes and commas).
		var header = "MediaBrowser Client=\"jf-dp\", Device=\"\(Self.escape(deviceName))\", DeviceId=\"\(Self.escape(deviceId))\", Version=\"\(Self.escape(clientVersion))\""
		if let token {
			header += ", Token=\"\(Self.escape(token))\""
		}
		return header
	}
    
	static func escape(_ value: String) -> String {
		let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
		return value.addingPercentEncoding(withAllowedCharacters: unreserved) ?? value
	}

	private func status(_ response: URLResponse) -> Int {
		(response as? HTTPURLResponse)?.statusCode ?? 0
	}

	private func check(_ response: URLResponse) throws {
		switch status(response) {
		case 200 ..< 300:
			return
		case 401:
			throw JellyfinError.sessionExpired
		case 404:
			throw JellyfinError.pluginMissing
		case let code:
			throw JellyfinError.unexpectedResponse(code)
		}
	}
}
