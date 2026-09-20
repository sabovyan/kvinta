// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "sugerkey",
    platforms: [.macOS(.v13)],
    products: [
        .executable(name: "sugerkey", targets: ["sugerkey"]),
    ],
    targets: [
        .executableTarget(name: "sugerkey"),
    ],
    swiftLanguageModes: [.v5]
)
