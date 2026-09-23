// swift-tools-version:5.9
import PackageDescription

// the macOS menu-bar app: a bare executable that build.sh wraps into a .app.
// the shared core lives in its own package next door — see ClaudeUsageKit/Package.swift
// for why it isn't just another target here.
let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "ClaudeUsageKit")
    ],
    targets: [
        .executableTarget(
            name: "ClaudeUsage",
            dependencies: [.product(name: "ClaudeUsageKit", package: "ClaudeUsageKit")],
            path: "Sources/ClaudeUsage"
        )
    ]
)
