// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarBridge",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CalendarBridge", targets: ["CalendarBridge"])],
    dependencies: [.package(path: "../TimeTugCore"), .package(url: "https://github.com/binary-companion/calendar-connectors", from: "1.0.0")],
    targets: [
        .target(name: "CalendarBridge", dependencies: [
            .product(name: "TimeTugCore", package: "TimeTugCore"),
            .product(name: "CalendarCore", package: "calendar-connectors"),
        ]),
        .testTarget(name: "CalendarBridgeTests", dependencies: [
            "CalendarBridge",
            .product(name: "TimeTugCore", package: "TimeTugCore"),
            .product(name: "CalendarCore", package: "calendar-connectors"),
        ]),
    ]
)
