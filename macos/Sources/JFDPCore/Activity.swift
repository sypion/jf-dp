import Foundation

public struct Activity: Encodable, Equatable, Sendable {
	public struct Timestamps: Encodable, Equatable, Sendable {
		public var start: Int64
		public var end: Int64
	}

	public struct Assets: Encodable, Equatable, Sendable {
		public var largeImage: String
		public var largeText: String?
	}

	public struct Button: Encodable, Equatable, Sendable {
		public var label: String
		public var url: String
	}

	static let listening = 2
	static let watching = 3
	static let showDetails = 2

	public var type: Int
	public var statusDisplayType = showDetails
	public var details: String?
	public var state: String?
	public var timestamps: Timestamps?
	public var assets: Assets?
	public var buttons: [Button]?

	// Discord's limit for text fields
	static let maxTextBytes = 128

	/// What to show for `state`, or nil to clear the activity. Mirrors DiscordPresenter.cs.
	public static func make(for state: PresenceState?, config: Config) -> Activity? {
		guard let s = state,
		      !(s.isPaused && !config.showWhenPaused),
		      !(s.libraryName.map { name in config.hiddenLibraries.contains { $0.caseInsensitiveCompare(name) == .orderedSame } } ?? false)
		else {
			return nil
		}

		var (details, line): (String?, String?) = switch s.kind {
		case .episode: (s.seriesName ?? s.name, formatEpisode(s))
		case .movie: (s.name, s.year.map(String.init))
		case .audio: (s.name, s.artists.isEmpty ? s.album : s.artists.joined(separator: ", "))
		case .video: (s.name, s.libraryName)
		}

		if s.isPaused {
			line = line.map { "\($0) · Paused" } ?? "Paused"
		}

		var activity = Activity(type: s.kind == .audio ? listening : watching, details: clip(details), state: clip(line))

		if config.showArtwork, let image = s.imageUrl {
			activity.assets = Assets(largeImage: image, largeText: clip(s.album ?? s.seriesName ?? s.name))
		}

		// Start and end make Discord draw a progress bar; skipped while paused, since it would keep moving.
		if config.showProgress, !s.isPaused, let runTime = s.runTimeTicks, runTime > 0 {
			let start = s.sampledAt.addingTimeInterval(-seconds(ticks: s.positionTicks))
			activity.timestamps = Timestamps(
				start: milliseconds(start),
				end: milliseconds(start.addingTimeInterval(seconds(ticks: runTime)))
			)
		}

		if config.showButtons, !s.links.isEmpty {
			activity.buttons = s.links.prefix(2).map { Button(label: $0.label, url: $0.url) }
		}

		return activity
	}

	static func formatEpisode(_ s: PresenceState) -> String? {
		let number: String? = switch (s.seasonNumber, s.episodeNumber) {
		case let (season?, episode?): "S\(season)E\(episode)"
		case let (nil, episode?): "E\(episode)"
		default: nil
		}

		// Without a series name, the episode title is already the details line.
		guard s.seriesName != nil else {
			return number
		}
		return number.map { "\($0) · \(s.name)" } ?? s.name
	}

	static func clip(_ value: String?) -> String? {
		guard let value, !value.allSatisfy(\.isWhitespace) else {
			return nil
		}
		guard value.utf8.count > maxTextBytes else {
			return value
		}

		// Characters are grapheme clusters, so emoji and accented letters stay whole.
		var result = ""
		var budget = maxTextBytes - "…".utf8.count
		for character in value {
			budget -= String(character).utf8.count
			if budget < 0 {
				break
			}
			result.append(character)
		}
		return result + "…"
	}

	private static func seconds(ticks: Int64) -> TimeInterval {
		TimeInterval(ticks) / 10_000_000
	}

	private static func milliseconds(_ date: Date) -> Int64 {
		Int64((date.timeIntervalSince1970 * 1000).rounded())
	}
}
