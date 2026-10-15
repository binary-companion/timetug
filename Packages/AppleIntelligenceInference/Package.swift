// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleIntelligenceInference",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AppleIntelligenceInference", targets: ["AppleIntelligenceInference"])],
    dependencies: [.package(url: "https://github.com/binary-companion/timetug-shared", from: "1.3.0")],
    targets: [
        .target(
            name: "AppleIntelligenceInference",
            dependencies: [
                .product(name: "TimeTugCore", package: "timetug-shared"),
                .product(name: "TimeTugEngine", package: "timetug-shared"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AppleIntelligenceInferenceTests",
            dependencies: [
                "AppleIntelligenceInference",
                .product(name: "TimeTugEngine", package: "timetug-shared"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
