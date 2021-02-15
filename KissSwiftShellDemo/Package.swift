// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
	name: "KissSwiftShellDemo",
	platforms: [.macOS(.v10_13)], // Process. 'executableURL' is only available in macOS 10.13 or newer
	dependencies: [
		// Dependencies declare other packages that this package depends on.
		.package(path: "../../KissSwiftShell")
	],
	targets: [
		// Targets are the basic building blocks of a package. A target can define a module or a test suite.
		// Targets can depend on other targets in this package, and on products in packages this package depends on.
		.target(
			name: "KissSwiftShellDemo",
			dependencies: [
				"KissSwiftShell"
			]),
		.testTarget(
			name: "KissSwiftShellDemoTests",
			dependencies: ["KissSwiftShellDemo"]),
	]
)
