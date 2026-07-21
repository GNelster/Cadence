// swift-tools-version:6.2
import PackageDescription

let package = Package(
    name: "Cadence",
    platforms: [.macOS(.v26)],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "1.0.0")
    ],
    targets: [
        .executableTarget(
            name: "Cadence",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit")
            ],
            path: "Sources/Cadence",
            swiftSettings: [.swiftLanguageMode(.v5)]
        )
    ]
)
