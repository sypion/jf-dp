import AppKit

@MainActor
enum AboutPanel {
	static func show() {
		let centered = NSMutableParagraphStyle()
		centered.alignment = .center
		let attributes: [NSAttributedString.Key: Any] = [
			.font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize),
			.foregroundColor: NSColor.secondaryLabelColor,
			.paragraphStyle: centered,
		]

		let credits = NSMutableAttributedString(string: "Shows what you're playing on Jellyfin in your Discord status.\n", attributes: attributes)
		var link = attributes
		link[.link] = URL(string: "https://github.com/sypion/jf-dp")!
		credits.append(NSAttributedString(string: "github.com/sypion/jf-dp", attributes: link))

		NSApp.activate()
		NSApp.orderFrontStandardAboutPanel(options: [.credits: credits])
	}
}
