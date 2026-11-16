// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EventKitSource",
    platforms: [.macOS(.v14)],
    products: [.library(name: "EventKitSource", targets: ["EventKitSource"])],
    dependencies: [.package(url: "https://github.com/binary-companion/timetug-shared", from: "2.1.1")],
    targets: [
        .target(
            name: "EventKitSource",
            dependencies: [.product(name: "TimeTugKit", package: "timetug-shared")],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .testTarget(
            name: "EventKitSourceTests",
            dependencies: [
                "EventKitSource",
                .product(name: "TimeTugKit", package: "timetug-shared"),
            ],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
