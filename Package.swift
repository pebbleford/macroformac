// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacroForMac",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "MacroForMac", targets: ["MacroForMac"]),
        .library(name: "MacroCore", targets: ["MacroCore"]),
    ],
    targets: [
        // Platform-independent model, storage, playback sequencing and recording logic.
        .target(name: "MacroCore"),
        // The macOS app: SwiftUI interface plus the CGEvent / Carbon engine.
        .executableTarget(
            name: "MacroForMac",
            dependencies: ["MacroCore"]
        ),
        .testTarget(
            name: "MacroCoreTests",
            dependencies: ["MacroCore"]
        ),
    ]
)
