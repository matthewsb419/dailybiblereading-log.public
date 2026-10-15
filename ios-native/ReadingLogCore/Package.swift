// swift-tools-version: 5.9
import PackageDescription

// Everything the app knows, with no UI: the plan, scoring, grades, sync merging and content.
// The app and (later) its widget both build on this, so they always agree.
let package = Package(
    name: "ReadingLogCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "ReadingLogCore", targets: ["ReadingLogCore"])
    ],
    targets: [
        .target(name: "ReadingLogCore", resources: [.process("Resources")]),
        .testTarget(name: "ReadingLogCoreTests", dependencies: ["ReadingLogCore"], resources: [.copy("Fixtures")])
    ]
)
