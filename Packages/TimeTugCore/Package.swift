// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TimeTugCore",
    platforms: [.macOS(.v14)],
    products: [.library(name: "TimeTugCore", targets: ["TimeTugCore"])],
    dependencies: [.package(url: "https://github.com/binary-companion/calendar-connectors", from: "1.0.0")],
    targets: [
        .target(name: "TimeTugCore", dependencies: [.product(name: "CalendarCore", package: "calendar-connectors")]),
        .executableTarget(name: "DedupBenchmark", dependencies: [
            "TimeTugCore", .product(name: "CalendarCore", package: "calendar-connectors"),
        ]),
        .testTarget(name: "TimeTugCoreTests", dependencies: [
            "TimeTugCore", .product(name: "CalendarCore", package: "calendar-connectors"),
        ]),
    ]
)
