// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarApple",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CalendarApple", targets: ["CalendarApple"])],
    dependencies: [.package(url: "https://github.com/binary-companion/timetug-shared", from: "2.1.1")],
    targets: [
        .target(name: "CalendarApple", dependencies: [.product(name: "TimeTugKit", package: "timetug-shared")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CalendarAppleTests", dependencies: ["CalendarApple", .product(name: "TimeTugKit", package: "timetug-shared")],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
