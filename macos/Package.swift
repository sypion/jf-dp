// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "JFDP",
	platforms: [.macOS(.v14)],
	products: [
		.executable(name: "JFDP", targets: ["JFDP"]),
	],
	dependencies: [
		.package(url: "https://github.com/sparkle-project/Sparkle", from: "2.6.0"),
	],
	targets: [
		.target(name: "JFDPCore"),
		.executableTarget(
			name: "JFDP",
			dependencies: ["JFDPCore", .product(name: "Sparkle", package: "Sparkle")]
		),
		.testTarget(name: "JFDPCoreTests", dependencies: ["JFDPCore"]),
	]
)
