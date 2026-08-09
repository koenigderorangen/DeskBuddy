// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeskBuddy",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "DeskBuddy", targets: ["DeskBuddy"])
    ],
    targets: [
        .executableTarget(
            name: "DeskBuddy",
            path: "Sources/DeskBuddy"
        ),
        .testTarget(
            name: "DeskBuddyTests",
            dependencies: ["DeskBuddy"],
            path: "Tests/DeskBuddyTests"
        )
    ]
)
