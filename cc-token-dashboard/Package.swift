// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "CCTokenDashboard",
    platforms: [.macOS(.v14)],
    targets: [
        // Pure logic: parsing, aggregation, pricing. No UI, fully unit-testable.
        .target(name: "CCTokenCore"),

        // M0 verification CLI: prints today's usage so we can cross-check numbers.
        .executableTarget(
            name: "cctoken-cli",
            dependencies: ["CCTokenCore"]
        ),

        // The menu bar app (M1–M3).
        .executableTarget(
            name: "CCTokenDashboard",
            dependencies: ["CCTokenCore"]
        ),

        .testTarget(
            name: "CCTokenCoreTests",
            dependencies: ["CCTokenCore"]
        ),
    ]
)
