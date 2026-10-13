// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "CalendarApple",
    platforms: [.macOS(.v14)],
    products: [.library(name: "CalendarApple", targets: ["CalendarApple"])],
    dependencies: [.package(url: "https://github.com/binary-companion/calendar-connectors", from: "1.0.0")],
    targets: [
        .target(name: "CalendarApple", dependencies: [.product(name: "CalendarCore", package: "calendar-connectors"),
                               .product(name: "CalendarOAuth", package: "calendar-connectors")],
                swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CalendarAppleTests", dependencies: ["CalendarApple", .product(name: "CalendarCore", package: "calendar-connectors"),
                                   .product(name: "CalendarOAuth", package: "calendar-connectors"),
                                   .product(name: "GoogleCalendar", package: "calendar-connectors"),
                                   .product(name: "MicrosoftCalendar", package: "calendar-connectors")],
                    swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
