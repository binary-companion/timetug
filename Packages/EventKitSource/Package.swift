// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EventKitSource",
    platforms: [.macOS(.v14)],
    products: [.library(name: "EventKitSource", targets: ["EventKitSource"])],
    dependencies: [.package(url: "https://github.com/binary-companion/calendar-connectors", from: "1.0.0")],
    targets: [
        .target(
            name: "EventKitSource",
            dependencies: [.product(name: "CalendarCore", package: "calendar-connectors")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "EventKitSourceTests",
            dependencies: [
                "EventKitSource",
                .product(name: "CalendarCore", package: "calendar-connectors"),
                .product(name: "CalendarTestSupport", package: "calendar-connectors"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
