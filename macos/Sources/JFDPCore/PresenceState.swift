import Foundation

/// What the user is playing, as the plugin sends it (src/Jellyfin.Plugin.DiscordPresence/Models/PresenceState.cs).
public struct PresenceState: Decodable, Equatable, Sendable {
	public enum Kind: String, Decodable, Sendable {
		case movie = "Movie"
		case episode = "Episode"
		case audio = "Audio"
		case video = "Video"
	}

	public struct Link: Decodable, Equatable, Sendable {
		public var label: String
		public var url: String
	}

	public var applicationId: String
	public var itemId: String
	public var kind: Kind
	public var name: String
	public var year: Int?
	public var seriesName: String?
	public var seasonNumber: Int?
	public var episodeNumber: Int?
	public var album: String?
	public var artists: [String]
	public var libraryName: String?
	public var imageUrl: String?
	public var isPaused: Bool
	public var positionTicks: Int64
	public var runTimeTicks: Int64?
	public var sampledAt: Date
	public var links: [Link]

	public static func decode(_ data: Data) throws -> PresenceState? {
		let decoder = JSONDecoder()
		decoder.dateDecodingStrategy = .custom { decoder in
			let container = try decoder.singleValueContainer()
			let text = try container.decode(String.self)
			guard let date = parseDate(text) else {
				throw DecodingError.dataCorruptedError(in: container, debugDescription: "Not an ISO 8601 date: \(text)")
			}
			return date
		}
		return try decoder.decode(PresenceState?.self, from: data)
	}

	static func parseDate(_ text: String) -> Date? {
		var trimmed = text
		if let dot = text.firstIndex(of: ".") {
			let digits = text[text.index(after: dot)...].prefix(while: \.isNumber)
			if digits.count > 3 {
				trimmed.replaceSubrange(digits.index(digits.startIndex, offsetBy: 3) ..< digits.endIndex, with: "")
			}
		}

		let formatter = ISO8601DateFormatter()
		formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
		if let date = formatter.date(from: trimmed) {
			return date
		}
		formatter.formatOptions = [.withInternetDateTime]
		return formatter.date(from: trimmed)
	}
}
