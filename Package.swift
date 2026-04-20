// swift-tools-version: 5.9
// This file exists only for IDE support (symbol resolution). Production builds use build.sh.
import PackageDescription

let package = Package(
    name: "OptWin",
    platforms: [.macOS("26.0")],
    targets: [.executableTarget(name: "OptWin", path: "Sources")]
)
