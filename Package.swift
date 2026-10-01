// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "SpaceShuttle",
    platforms: [.macOS(.v14)],
    products: [
        // REAPER only loads extensions named reaper_*.dylib; Scripts/install-extension.sh renames lib*.dylib on install.
        .library(name: "reaper_spaceshuttle", type: .dynamic, targets: ["SpaceShuttleExtension"]),
    ],
    targets: [
        // C mirror of the few REAPER SDK structs we need (ADR-0002).
        .target(name: "ReaperBridge"),
        // Typed REAPER API, main-actor isolated (ADR-0002).
        .target(name: "ReaperKit", dependencies: ["ReaperBridge"]),
        // The SpaceMouse: value types, native HID input, 3DxWare client input (ADR-0003).
        .target(name: "SpaceMouseKit"),
        // Pure navigation logic: shaping, arrange view motion, autoscroll guard, settings (ADR-0004 to ADR-0006).
        .target(name: "NavigationCore", dependencies: ["SpaceMouseKit"]),
        .target(name: "SpaceShuttleExtension", dependencies: ["ReaperBridge", "ReaperKit", "SpaceMouseKit", "NavigationCore"]),
        .testTarget(name: "NavigationCoreTests", dependencies: ["NavigationCore", "SpaceMouseKit"]),
        .testTarget(name: "SpaceMouseKitTests", dependencies: ["SpaceMouseKit"]),
    ]
)
