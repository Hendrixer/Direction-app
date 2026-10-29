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
    ],
    targets: [
        .target(name: "DirectionCore", dependencies: [.product(name: "GRDB", package: "GRDB.swift")]),
        .target(name: "DirectionMedia", dependencies: ["DirectionCore"], resources: [.copy("Graphics/Web")]),
        .target(name: "DirectionTools", dependencies: ["DirectionCore", "DirectionMedia", .product(name: "MCP", package: "swift-sdk")]),
        .executableTarget(name: "DirectionApp", dependencies: ["DirectionTools"], resources: [.process("Resources")]),
        .executableTarget(name: "DirectionCLI", dependencies: ["DirectionTools", .product(name: "ArgumentParser", package: "swift-argument-parser")]),
        .testTarget(name: "DirectionCoreTests", dependencies: ["DirectionCore"]),
        .testTarget(name: "DirectionMediaTests", dependencies: ["DirectionTools"]),
        .testTarget(name: "DirectionAppTests", dependencies: ["DirectionApp", "DirectionCore", "DirectionTools"]),
    ]
)
