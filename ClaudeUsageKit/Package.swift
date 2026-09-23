// swift-tools-version:5.9
import PackageDescription

// the cross-platform core, deliberately its own package: the iOS project links only this,
// so it never sees the AppKit/ServiceManagement executable in the root package — which it
// would otherwise try to index and build for iOS.
let package = Package(
    name: "ClaudeUsageKit",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "ClaudeUsageKit", targets: ["ClaudeUsageKit"])
    ],
    targets: [
        .target(name: "ClaudeUsageKit")
    ]
)
