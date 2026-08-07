// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "NeoLogger",
  platforms: [
    .macOS(.v14),
    .iOS(.v17),
    .tvOS(.v17),
    .watchOS(.v10),
    .visionOS(.v1),
  ],
  products: [
    .library(name: "NeoLogger", targets: ["NeoLogger"]),
    .library(name: "NeoLoggerSwiftLog", targets: ["NeoLoggerSwiftLog"]),
    .executable(name: "neo-logger-viewer", targets: ["neo-logger-viewer"]),
    .executable(name: "neo-logger-demo", targets: ["neo-logger-demo"]),
  ],
  dependencies: [
    // NeoLogHandler adopts the LogEvent-based handler API.
    .package(url: "https://github.com/apple/swift-log.git", from: "1.12.0")
  ],
  targets: [
    .target(
      name: "NeoLogger",
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
    .target(
      name: "NeoLoggerSwiftLog",
      dependencies: [
        "NeoLogger",
        .product(name: "Logging", package: "swift-log"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
    .executableTarget(
      name: "neo-logger-viewer",
      dependencies: ["NeoLogger"],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
    .executableTarget(
      name: "neo-logger-demo",
      dependencies: ["NeoLogger"],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
    .testTarget(
      name: "NeoLoggerTests",
      dependencies: [
        "NeoLogger",
        "NeoLoggerSwiftLog",
        .product(name: "Logging", package: "swift-log"),
      ],
      swiftSettings: [
        .swiftLanguageMode(.v6)
      ]
    ),
  ]
)
