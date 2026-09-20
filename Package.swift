// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "kvinta",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "kvinta", targets: ["kvinta"]),
    ],
    targets: [
        .executableTarget(name: "kvinta"),
    ],
    swiftLanguageModes: [.v5]
)
