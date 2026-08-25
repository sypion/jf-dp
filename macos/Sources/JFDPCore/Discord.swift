import Darwin
import Foundation

public enum DiscordError: LocalizedError, Equatable {
	case notRunning
	case closed(String?)
	case rejected(String?)
	case io(Int32)

	public var errorDescription: String? {
		switch self {
		case .notRunning: "Discord isn't running (or isn't the desktop app)."
		case let .closed(message): "Discord closed the connection" + (message.map { ": \($0)" } ?? ".")
		case let .rejected(message): "Discord rejected the status" + (message.map { ": \($0)" } ?? ".")
		case let .io(code): "Lost the connection to Discord (\(String(cString: strerror(code))))."
		}
	}
}

public actor DiscordPresenter {
	private var connection: DiscordConnection?

	public init() {}

	public var isConnected: Bool { connection != nil }

	/// Shows `activity` under the Discord application `applicationID`, or clears it when nil.
	/// Returns whether Discord has it, when it doesn't, call again later to retry.
	@discardableResult
	public func show(_ activity: Activity?, applicationID: String?) -> Bool {
		do {
			guard let activity, let applicationID else {
				// Nothing to show: no need to start Discord's connection just to clear it.
				try connection?.setActivity(nil)
				return true
			}

			if connection?.clientID != applicationID {
				try? connection?.setActivity(nil)
				connection = nil
				connection = try DiscordConnection(clientID: applicationID)
			}
			try connection!.setActivity(activity)
			return true
		} catch {
			connection = nil
			return false
		}
	}

	public func disconnect() {
		try? connection?.setActivity(nil)
		connection = nil
	}
}

/// One connection to Discord's IPC socket
final class DiscordConnection {
	enum Opcode: UInt32 {
		case handshake = 0, frame, close, ping, pong
	}

	let clientID: String
	private let socket: Int32

	static let encoder: JSONEncoder = {
		let encoder = JSONEncoder()
		encoder.keyEncodingStrategy = .convertToSnakeCase
		encoder.outputFormatting = .withoutEscapingSlashes
		return encoder
	}()

	init(clientID: String) throws {
		// A loop, not lazy.compactMap(...).first, which calls connect twice and leaks a socket
		var found: Int32?
		for path in Self.socketPaths() {
			found = Self.connect(to: path)
			if found != nil {
				break
			}
		}
		guard let socket = found else {
			throw DiscordError.notRunning
		}
		self.clientID = clientID
		self.socket = socket

		struct Handshake: Encodable {
			var v = 1
			var clientId: String
		}
		try send(.handshake, Handshake(clientId: clientID))

		// READY, or a close frame saying why not (ex. an unknown application ID)
		let (op, reply) = try receive()
		if op == .close {
			throw DiscordError.closed(reply.data?.message)
		}
	}

	deinit {
		Darwin.close(socket)
	}

	func setActivity(_ activity: Activity?) throws {
		struct Args: Encodable {
			var pid = getpid()
			var activity: Activity?

			func encode(to encoder: Encoder) throws {
				var c = encoder.container(keyedBy: CodingKeys.self)
				try c.encode(pid, forKey: .pid)
				// null clears it.
				try c.encode(activity, forKey: .activity)
			}

			enum CodingKeys: CodingKey {
				case pid, activity
			}
		}

		struct Command: Encodable {
			var cmd = "SET_ACTIVITY"
			var args: Args
			var nonce = UUID().uuidString
		}

		let command = Command(args: Args(activity: activity))
		try send(.frame, command)

		// Read up to our reply, so replies never pile up unread in the socket
		while true {
			let (op, reply) = try receive()
			if op == .close {
				throw DiscordError.closed(reply.data?.message)
			}
			if reply.nonce == command.nonce {
				if reply.evt == "ERROR" {
					throw DiscordError.rejected(reply.data?.message)
				}
				return
			}
		}
	}

	struct Reply: Decodable {
		struct Payload: Decodable {
			var message: String?
		}

		var evt: String?
		var nonce: String?
		var data: Payload?
	}

	static func frame(_ op: Opcode, _ payload: Data) -> Data {
		var data = Data()
		withUnsafeBytes(of: op.rawValue.littleEndian) { data.append(contentsOf: $0) }
		withUnsafeBytes(of: UInt32(payload.count).littleEndian) { data.append(contentsOf: $0) }
		data.append(payload)
		return data
	}

	private func send(_ op: Opcode, _ payload: some Encodable) throws {
		try write(Self.frame(op, Self.encoder.encode(payload)))
	}

	private func receive() throws -> (Opcode, Reply) {
		while true {
			let header = try read(8)
			let op = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 0, as: UInt32.self)) }
			let length = header.withUnsafeBytes { UInt32(littleEndian: $0.loadUnaligned(fromByteOffset: 4, as: UInt32.self)) }
			let body = try read(Int(length))

			switch Opcode(rawValue: op) {
			case .ping:
				try write(Self.frame(.pong, body))
			case let opcode?:
				return (opcode, (try? JSONDecoder().decode(Reply.self, from: body)) ?? Reply())
			case nil:
				throw DiscordError.closed("unknown opcode \(op)")
			}
		}
	}

	private func write(_ data: Data) throws {
		try data.withUnsafeBytes { buffer in
			var offset = 0
			while offset < buffer.count {
				let written = Darwin.write(socket, buffer.baseAddress! + offset, buffer.count - offset)
				if written < 0 {
					if errno == EINTR { continue }
					throw DiscordError.io(errno)
				}
				offset += written
			}
		}
	}

	private func read(_ count: Int) throws -> Data {
		var data = Data(count: count)
		try data.withUnsafeMutableBytes { buffer in
			var offset = 0
			while offset < count {
				let received = Darwin.read(socket, buffer.baseAddress! + offset, count - offset)
				if received == 0 {
					throw DiscordError.closed(nil)
				}
				if received < 0 {
					if errno == EINTR { continue }
					throw DiscordError.io(errno)
				}
				offset += received
			}
		}
		return data
	}

	/// discord-ipc-0 to 9 in the temporary folders Discord might use; on macOS it's $TMPDIR.
	static func socketPaths(environment: [String: String] = ProcessInfo.processInfo.environment) -> [String] {
		var folders: [String] = []
		for folder in ["XDG_RUNTIME_DIR", "TMPDIR", "TMP", "TEMP"].compactMap({ environment[$0] }) + [NSTemporaryDirectory(), "/tmp"] {
			let trimmed = folder.hasSuffix("/") && folder.count > 1 ? String(folder.dropLast()) : folder
			if !trimmed.isEmpty, !folders.contains(trimmed) {
				folders.append(trimmed)
			}
		}
		return folders.flatMap { folder in (0 ... 9).map { "\(folder)/discord-ipc-\($0)" } }
	}

	private static func connect(to path: String) -> Int32? {
		var address = sockaddr_un()
		let pathBytes = Array(path.utf8)
		guard pathBytes.count < MemoryLayout.size(ofValue: address.sun_path) else {
			return nil
		}
		address.sun_family = sa_family_t(AF_UNIX)
		withUnsafeMutableBytes(of: &address.sun_path) { buffer in
			buffer.copyBytes(from: pathBytes)
			buffer[pathBytes.count] = 0
		}

		let fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
		guard fd >= 0 else {
			return nil
		}

		let size = socklen_t(MemoryLayout<sockaddr_un>.size)
		let connected = withUnsafePointer(to: &address) {
			$0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, size) }
		}
		guard connected == 0 else {
			Darwin.close(fd)
			return nil
		}

		// Report a closed socket as an error rather than killing the app with SIGPIPE,
		// and don't hang if Discord stops answering
		var on: Int32 = 1
		setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
		var timeout = timeval(tv_sec: 5, tv_usec: 0)
		setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
		setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
		return fd
	}
}
