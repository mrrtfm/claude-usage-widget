// swift-tools-version:5.9
import PackageDescription

// menu-bar app, built as a bare executable then wrapped into a .app by build.sh
let package = Package(
    name: "ClaudeUsage",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "ClaudeUsage",
            path: "Sources/ClaudeUsage"
        )
    ]
)
