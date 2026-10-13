// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleIntelligenceInference",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AppleIntelligenceInference", targets: ["AppleIntelligenceInference"])],
    dependencies: [.package(path: "../TimeTugCore"), .package(url: "https://github.com/binary-companion/calendar-connectors", from: "1.0.0")],
    targets: [
        .target(
            name: "AppleIntelligenceInference",
            dependencies: [.product(name: "TimeTugCore", package: "TimeTugCore")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AppleIntelligenceInferenceTests",
            dependencies: [
                "AppleIntelligenceInference",
                .product(name: "TimeTugCore", package: "TimeTugCore"),
                .product(name: "CalendarCore", package: "calendar-connectors"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
