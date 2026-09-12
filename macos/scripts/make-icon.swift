// Draws packaging/AppIcon.icns: run `swift scripts/make-icon.swift` from macos/ after changing it.
import AppKit

func render(size: Int) -> Data {
	let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: size, pixelsHigh: size, bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
	NSGraphicsContext.saveGraphicsState()
	NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
	let scale = CGFloat(size) / 1024

	let tile = NSRect(x: 100, y: 100, width: 824, height: 824).applying(.init(scaleX: scale, y: scale))
	let shape = NSBezierPath(roundedRect: tile, xRadius: 185 * scale, yRadius: 185 * scale)
	NSGradient(starting: NSColor(srgbRed: 0.67, green: 0.36, blue: 0.76, alpha: 1), ending: NSColor(srgbRed: 0.0, green: 0.64, blue: 0.86, alpha: 1))!
		.draw(in: shape, angle: -45)

	let symbol = NSImage(systemSymbolName: "play.tv.fill", accessibilityDescription: nil)!
		.withSymbolConfiguration(.init(pointSize: 420 * scale, weight: .regular).applying(.init(paletteColors: [NSColor(srgbRed: 0.25, green: 0.45, blue: 0.82, alpha: 1), .white])))!
	let box = NSRect(x: (CGFloat(size) - symbol.size.width) / 2, y: (CGFloat(size) - symbol.size.height) / 2, width: symbol.size.width, height: symbol.size.height)
	symbol.draw(in: box)

	NSGraphicsContext.restoreGraphicsState()
	return rep.representation(using: .png, properties: [:])!
}

let iconset = URL(filePath: NSTemporaryDirectory()).appending(path: "AppIcon.iconset")
try? FileManager.default.removeItem(at: iconset)
try FileManager.default.createDirectory(at: iconset, withIntermediateDirectories: true)
for points in [16, 32, 128, 256, 512] {
	try render(size: points).write(to: iconset.appending(path: "icon_\(points)x\(points).png"))
	try render(size: points * 2).write(to: iconset.appending(path: "icon_\(points)x\(points)@2x.png"))
}

let iconutil = Process()
iconutil.executableURL = URL(filePath: "/usr/bin/iconutil")
iconutil.arguments = ["-c", "icns", iconset.path, "-o", "packaging/AppIcon.icns"]
try iconutil.run()
iconutil.waitUntilExit()
print(iconutil.terminationStatus == 0 ? "Wrote packaging/AppIcon.icns" : "iconutil failed")
