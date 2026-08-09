// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeskBuddy",
    platforms: [.macOS(.v26)],
    products: [
        .executable(name: "DeskBuddy", targets: ["DeskBuddy"])
    ],
    dependencies: [
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.9.5")
    ],
    targets: [
        .executableTarget(
            name: "DeskBuddy",
            dependencies: [
                .product(name: "Sparkle", package: "Sparkle")
            ],
            path: "Sources/DeskBuddy",
            linkerSettings: [
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])
            ]
        ),
        .testTarget(
            name: "DeskBuddyTests",
            dependencies: ["DeskBuddy"],
            path: "Tests/DeskBuddyTests"
        )
    ]
)
