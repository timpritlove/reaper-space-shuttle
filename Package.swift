// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpaceShuttle",
    platforms: [.macOS(.v14)],
    products: [
        // REAPER only loads extensions named reaper_*.dylib; Scripts/install-extension.sh renames lib*.dylib on install.
        .library(name: "reaper_spaceshuttle", type: .dynamic, targets: ["SpaceShuttleExtension"]),
    ],
    dependencies: [
        // The SpaceMouse through Space Juggler (ADR-0017); from GitHub.
        .package(url: "https://github.com/metaebene/space-juggler.git", from: "0.5.2"),
    ],
    targets: [
        // C mirror of the few REAPER SDK structs we need (ADR-0002).
        .target(name: "ReaperBridge"),
        // Typed REAPER API, main-actor isolated (ADR-0002).
        .target(name: "ReaperKit", dependencies: ["ReaperBridge"]),
        // Pure navigation logic: shaping, arrange view motion, autoscroll guard, settings (ADR-0004 to ADR-0006).
        .target(name: "NavigationCore", dependencies: [.product(name: "SpaceMouseKit", package: "space-juggler")]),
        .target(name: "SpaceShuttleExtension", dependencies: [
            "ReaperBridge", "ReaperKit", "NavigationCore", .product(name: "SpaceJugglerClient", package: "space-juggler"),
        ]),
        .testTarget(name: "NavigationCoreTests", dependencies: [
            "NavigationCore", .product(name: "SpaceMouseKit", package: "space-juggler"),
        ]),
    ]
)
