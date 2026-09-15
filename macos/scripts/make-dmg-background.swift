import AppKit

let width: CGFloat = 640
let height: CGFloat = 400
let iconY: CGFloat = 180
let appX: CGFloat = 170
let applicationsX: CGFloat = 470

let purple = NSColor(srgbRed: 0.67, green: 0.36, blue: 0.76, alpha: 1)
let blue = NSColor(srgbRed: 0.0, green: 0.64, blue: 0.86, alpha: 1)

func render(scale: CGFloat) -> NSBitmapImageRep {
	let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int(width * scale), pixelsHigh: Int(height * scale), bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
	rep.size = NSSize(width: width, height: height)
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
	let bounds = NSRect(x: 0, y: 0, width: width, height: height)

	NSGradient(starting: NSColor(srgbRed: 0.97, green: 0.96, blue: 0.99, alpha: 1), ending: NSColor(srgbRed: 0.92, green: 0.94, blue: 0.98, alpha: 1))!
		.draw(in: bounds, angle: -90)

	for (color, center) in [(purple, NSPoint(x: appX - 40, y: height - iconY + 70)), (blue, NSPoint(x: applicationsX + 40, y: height - iconY - 70))] {
		NSGradient(colors: [color.withAlphaComponent(0.22), color.withAlphaComponent(0)])!
			.draw(fromCenter: center, radius: 0, toCenter: center, radius: 300, options: [])
	}

	let arrowY = height - iconY
	let start = appX + 90
	let end = applicationsX - 90
	let arrow = NSBezierPath()
	arrow.move(to: NSPoint(x: start, y: arrowY))
	arrow.line(to: NSPoint(x: end, y: arrowY))
	arrow.move(to: NSPoint(x: end - 16, y: arrowY + 16))
	arrow.line(to: NSPoint(x: end, y: arrowY))
	arrow.line(to: NSPoint(x: end - 16, y: arrowY - 16))
	arrow.lineWidth = 6
	arrow.lineCapStyle = .round
	arrow.lineJoinStyle = .round
	let stroke = NSBezierPath(cgPath: arrow.cgPath.copy(strokingWithWidth: 6, lineCap: .round, lineJoin: .round, miterLimit: 10))
	NSGradient(starting: purple, ending: blue)!.draw(in: stroke, angle: 0)

	let paragraph = NSMutableParagraphStyle()
	paragraph.alignment = .center
	let title = NSAttributedString(string: "Drag jf-dp into Applications to install it", attributes: [
		.font: NSFont.systemFont(ofSize: 15, weight: .medium),
		.foregroundColor: NSColor(srgbRed: 0.33, green: 0.34, blue: 0.42, alpha: 1),
		.paragraphStyle: paragraph,
	])
	title.draw(in: NSRect(x: 0, y: 58, width: width, height: 22))
	let subtitle = NSAttributedString(string: "Then open it from Applications to sign in.", attributes: [
		.font: NSFont.systemFont(ofSize: 12),
		.foregroundColor: NSColor(srgbRed: 0.50, green: 0.51, blue: 0.58, alpha: 1),
		.paragraphStyle: paragraph,
	])
	subtitle.draw(in: NSRect(x: 0, y: 38, width: width, height: 18))

	NSGraphicsContext.restoreGraphicsState()
	return rep
}

let image = NSImage(size: NSSize(width: width, height: height))
image.addRepresentation(render(scale: 1))
image.addRepresentation(render(scale: 2))
try image.tiffRepresentation(using: .lzw, factor: 0)!.write(to: URL(filePath: "packaging/dmg-background.tiff"))
print("Wrote packaging/dmg-background.tiff")
