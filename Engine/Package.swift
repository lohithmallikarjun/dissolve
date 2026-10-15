// swift-tools-version: 6.0
import PackageDescription

// Pure-Swift domain logic (dates, streaks, schedules, sync merging).
// No Apple-only frameworks, so `swift test` also runs on Linux.
let package = Package(
    name: "Engine",
    platforms: [.iOS("26.0"), .macOS("26.0")],
    products: [
        .library(name: "Engine", targets: ["Engine"])
    ],
    targets: [
        .target(name: "Engine"),
        .testTarget(name: "EngineTests", dependencies: ["Engine"]),
    ]
)
