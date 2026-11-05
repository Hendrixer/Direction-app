// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Direction",
    platforms: [.macOS("26.0")],
    products: [
        .executable(name: "DirectionApp", targets: ["DirectionApp"]),
        .executable(name: "direction", targets: ["DirectionCLI"]),
        .library(name: "DirectionCore", targets: ["DirectionCore"]),
        .library(name: "DirectionMedia", targets: ["DirectionMedia"]),
    ],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/modelcontextprotocol/swift-sdk.git", from: "0.11.0"),
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.5.0"),
        // Updates for the copies we sign and hand out (docs/releasing.md). Pinned: every release is checked by hand.
        .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
    ],
    targets: [
        .target(name: "DirectionCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "DirectionMedia", dependencies: ["DirectionCore"], resources: [.copy("Graphics/Web")]),
        .target(name: "DirectionTools", dependencies: ["DirectionCore", "DirectionMedia", .product(name: "MCP", package: "swift-sdk")]),
        .executableTarget(name: "DirectionApp", dependencies: ["DirectionTools", .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")],
                          // Sparkle.framework sits in Contents/Frameworks of the app (scripts/build-app.sh).
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .executableTarget(name: "DirectionCLI", dependencies: ["DirectionTools", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .testTarget(name: "DirectionCoreTests", dependencies: ["DirectionCore"]),
        .testTarget(name: "DirectionMediaTests", dependencies: ["DirectionTools"]),
        .testTarget(name: "DirectionAppTests", dependencies: ["DirectionApp", "DirectionCore", "DirectionTools"]),
    ]
)
