import AppKit
import JFDPCore
import SwiftUI

@MainActor
enum AccountWindow {
	private static var window: NSWindow?

	static func show(model: AppModel) {
		if window == nil {
			let window = NSWindow(contentViewController: NSHostingController(rootView: AccountView(model: model)))
			window.title = "jf-dp"
			window.styleMask = [.titled, .closable, .fullSizeContentView]
			window.titlebarAppearsTransparent = true
			window.titleVisibility = .hidden
			window.isMovableByWindowBackground = true
			window.isReleasedWhenClosed = false
			window.center()
			self.window = window
		}
		NSApp.activate()
		window?.makeKeyAndOrderFront(nil)
	}

	static func close() {
		window?.close()
	}
}

private enum Brand {
	static let purple = Color(red: 0.67, green: 0.36, blue: 0.76)
	static let blue = Color(red: 0.0, green: 0.64, blue: 0.86)
	static let accent = Color(red: 0.25, green: 0.45, blue: 0.82)
}

struct AccountView: View {
	let model: AppModel

	var body: some View {
		Group {
			if model.config.isSignedIn, model.status != .signInExpired {
				SignedInView(model: model)
			} else {
				SignInForm(model: model)
			}
		}
		.padding(.horizontal, 32)
		.padding(.top, 8)
		.padding(.bottom, 28)
		.frame(width: 380)
		.tint(Brand.accent)
		.background { Backdrop() }
	}
}

private struct Backdrop: View {
	var body: some View {
		ZStack {
			Rectangle().fill(.background)
			RadialGradient(colors: [Brand.purple.opacity(0.32), .clear], center: .topLeading, startRadius: 0, endRadius: 340)
			RadialGradient(colors: [Brand.blue.opacity(0.28), .clear], center: .bottomTrailing, startRadius: 0, endRadius: 340)
		}
		.ignoresSafeArea()
	}
}

private struct Header: View {
	let title: String
	let message: Text
	var badge: String?

	var body: some View {
		VStack(spacing: 10) {
			Image(nsImage: NSApp.applicationIconImage)
				.resizable()
				.frame(width: 84, height: 84)
				.shadow(color: Brand.accent.opacity(0.3), radius: 12, y: 6)
				.overlay(alignment: .bottomTrailing) {
					if let badge {
						Image(systemName: badge)
							.font(.system(size: 22, weight: .semibold))
							.symbolRenderingMode(.palette)
							.foregroundStyle(.white, .green)
							.background(Circle().fill(.background).padding(2))
							.offset(x: -4, y: -4)
					}
				}
				.accessibilityHidden(true)
			Text(title)
				.font(.title2.weight(.semibold))
			message
				.font(.callout)
				.foregroundStyle(.secondary)
				.multilineTextAlignment(.center)
				.fixedSize(horizontal: false, vertical: true)
		}
		.frame(maxWidth: .infinity)
	}
}

private struct SignInForm: View {
	let model: AppModel

	private enum Field {
		case server, userName, password
	}

	@State private var server = ""
	@State private var userName = ""
	@State private var password = ""
	@State private var openAtLogin = true
	@State private var error: String?
	@State private var busy = false
	@FocusState private var focus: Field?

	var body: some View {
		VStack(spacing: 20) {
			Header(
				title: "Sign in to Jellyfin",
				message: Text(model.status == .signInExpired
					? "Jellyfin signed you out. Sign in again to keep your Discord status up to date."
					: "Show what you're watching or listening to on Jellyfin in your Discord status.")
			)

			GlassGroup {
				VStack(spacing: 10) {
					FieldRow(symbol: "server.rack", focused: focus == .server) {
						TextField("Server", text: $server, prompt: Text("Server address, like 192.168.1.10:8096"))
							.focused($focus, equals: .server)
					}
					FieldRow(symbol: "person", focused: focus == .userName) {
						TextField("Username", text: $userName, prompt: Text("Username"))
							.focused($focus, equals: .userName)
					}
					FieldRow(symbol: "lock", focused: focus == .password) {
						SecureField("Password", text: $password, prompt: Text("Password"))
							.focused($focus, equals: .password)
					}
				}
			}
			.disabled(busy)

			if let error {
				Label {
					Text(error)
						.fixedSize(horizontal: false, vertical: true)
				} icon: {
					Image(systemName: "exclamationmark.triangle.fill")
				}
				.font(.callout)
				.foregroundStyle(.red)
				.frame(maxWidth: .infinity, alignment: .leading)
				.padding(10)
				.background(.red.opacity(0.1), in: .rect(cornerRadius: 10))
				.transition(.opacity)
			}

			VStack(spacing: 14) {
				Button {
					Task { await signIn() }
				} label: {
					HStack(spacing: 8) {
						if busy {
							ProgressView()
								.controlSize(.small)
						}
						Text(busy ? "Signing In…" : "Sign In")
					}
					.frame(maxWidth: .infinity)
				}
				.prominentButtonStyle()
				.controlSize(.extraLarge)
				.keyboardShortcut(.defaultAction)
				.disabled(busy || server.isEmpty || userName.isEmpty)

				Toggle("Open jf-dp when I log in", isOn: $openAtLogin)
					.toggleStyle(.checkbox)
					.foregroundStyle(.secondary)
					.disabled(busy)
			}
		}
		.animation(.default, value: error)
		.onAppear {
			server = model.config.serverUrl ?? ""
			userName = model.config.userName ?? ""
			focus = server.isEmpty ? .server : userName.isEmpty ? .userName : .password
		}
	}

	private func signIn() async {
		busy = true
		error = nil
		defer { busy = false }
		do {
			try await model.signIn(server: server, userName: userName, password: password, openAtLogin: openAtLogin)
			password = ""
		} catch let urlError as URLError {
			error = "Couldn't reach the server. Check the address, and that this Mac is on the same network. (\(urlError.localizedDescription))"
		} catch {
			self.error = error.localizedDescription
		}
	}
}

private struct FieldRow<Field: View>: View {
	let symbol: String
	let focused: Bool
	@ViewBuilder let field: Field

	var body: some View {
		HStack(spacing: 10) {
			Image(systemName: symbol)
				.foregroundStyle(focused ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary))
				.frame(width: 18)
				.accessibilityHidden(true)
			field
				.textFieldStyle(.plain)
		}
		.font(.body)
		.padding(.horizontal, 12)
		.frame(height: 38)
		.glassBackground(in: .rect(cornerRadius: 12))
		.overlay {
			RoundedRectangle(cornerRadius: 12)
				.strokeBorder(.tint, lineWidth: 1.5)
				.opacity(focused ? 1 : 0)
		}
		.animation(.easeOut(duration: 0.15), value: focused)
	}
}

private struct SignedInView: View {
	let model: AppModel

	var body: some View {
		VStack(spacing: 20) {
			Header(
				title: "You're all set",
				message: Text("Signed in as **\(model.config.userName ?? "")** on \(model.config.serverUrl ?? "")."),
				badge: "checkmark.circle.fill"
			)

			GlassGroup {
				VStack(spacing: 10) {
					Tip(symbol: "menubar.arrow.up.rectangle", text: "jf-dp runs in your menu bar, at the top right of the screen. Click it to choose what your status shows.")
					Tip(symbol: "bubble.left.and.bubble.right", text: "Keep the Discord app open while you watch or listen.")
				}
			}

			HStack(spacing: 10) {
				Button {
					model.signOut()
				} label: {
					Text("Sign Out").frame(maxWidth: .infinity)
				}
				.secondaryButtonStyle()

				Button {
					AccountWindow.close()
				} label: {
					Text("Done").frame(maxWidth: .infinity)
				}
				.prominentButtonStyle()
				.keyboardShortcut(.defaultAction)
			}
			.controlSize(.extraLarge)
		}
	}
}

private struct Tip: View {
	let symbol: String
	let text: String

	var body: some View {
		HStack(alignment: .top, spacing: 12) {
			Image(systemName: symbol)
				.font(.system(size: 15, weight: .medium))
				.foregroundStyle(.tint)
				.frame(width: 32, height: 32)
				.background(.tint.opacity(0.15), in: .circle)
				.accessibilityHidden(true)
			Text(text)
				.font(.callout)
				.fixedSize(horizontal: false, vertical: true)
				.frame(maxWidth: .infinity, alignment: .leading)
		}
		.padding(12)
		.glassBackground(in: .rect(cornerRadius: 14))
	}
}

private struct GlassGroup<Content: View>: View {
	@ViewBuilder let content: Content

	var body: some View {
		#if compiler(>=6.2)
		if #available(macOS 26, *) {
			GlassEffectContainer(spacing: 10) { content }
		} else {
			content
		}
		#else
		content
		#endif
	}
}

private extension View {
	@ViewBuilder
	func glassBackground(in shape: some Shape) -> some View {
		#if compiler(>=6.2)
		if #available(macOS 26, *) {
			glassEffect(.regular.interactive(), in: shape)
		} else {
			materialBackground(in: shape)
		}
		#else
		materialBackground(in: shape)
		#endif
	}

	private func materialBackground(in shape: some Shape) -> some View {
		background(.regularMaterial, in: shape)
			.overlay { shape.stroke(.separator, lineWidth: 0.5) }
	}

	@ViewBuilder
	func prominentButtonStyle() -> some View {
		#if compiler(>=6.2)
		if #available(macOS 26, *) {
			// Glass in the tint. On the Mac, .glassProminent comes out a dull navy.
			buttonStyle(.glass)
		} else {
			buttonStyle(.borderedProminent)
		}
		#else
		buttonStyle(.borderedProminent)
		#endif
	}

	@ViewBuilder
	func secondaryButtonStyle() -> some View {
		#if compiler(>=6.2)
		if #available(macOS 26, *) {
			buttonStyle(.glass).tint(nil)
		} else {
			buttonStyle(.bordered)
		}
		#else
		buttonStyle(.bordered)
		#endif
	}
}
