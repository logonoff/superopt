// swift-tools-version: 5.9
// This file exists only for IDE support (symbol resolution). Production builds use build.sh.
import PackageDescription

let package = Package(
    name: "SuperOpt",
    platforms: [.macOS("27.0")],
    targets: [.executableTarget(name: "SuperOpt", path: "Sources")]
)
