// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "AppleIntelligenceInference",
    platforms: [.macOS(.v14)],
    products: [.library(name: "AppleIntelligenceInference", targets: ["AppleIntelligenceInference"])],
    dependencies: [.package(url: "https://github.com/binary-companion/timetug-shared", from: "1.0.0"), .package(url: "https://github.com/binary-companion/calendar-connectors", from: "1.0.0")],
    targets: [
        .target(
            name: "AppleIntelligenceInference",
            dependencies: [.product(name: "TimeTugCore", package: "timetug-shared")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "AppleIntelligenceInferenceTests",
            dependencies: [
                "AppleIntelligenceInference",
                .product(name: "TimeTugCore", package: "timetug-shared"),
                .product(name: "CalendarCore", package: "calendar-connectors"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
