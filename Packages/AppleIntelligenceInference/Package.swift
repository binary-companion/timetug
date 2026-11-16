// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleIntelligenceInference",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AppleIntelligenceInference", targets: ["AppleIntelligenceInference"])],
    dependencies: [.package(url: "https://github.com/binary-companion/timetug-shared", from: "2.1.1")],
    targets: [
        .target(
            name: "AppleIntelligenceInference",
            dependencies: [
                .product(name: "TimeTugKit", package: "timetug-shared"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AppleIntelligenceInferenceTests",
            dependencies: [
                "AppleIntelligenceInference",
                .product(name: "TimeTugKit", package: "timetug-shared"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
