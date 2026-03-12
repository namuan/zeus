// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "OpenZeus",
    platforms: [.macOS(.v15)],
    products: [
        .executable(name: "OpenZeus", targets: ["OpenZeus"])
    ],
    dependencies: [
        .package(url: "https://github.com/migueldeicaza/SwiftTerm", from: "1.2.0")
    ],
    targets: [
        .executableTarget(
            name: "OpenZeus",
            dependencies: [
                .product(name: "SwiftTerm", package: "SwiftTerm")
            ],
            path: "Sources/OpenZeus",
            resources: [
                .process("Resources")
            ]
        ),
        .testTarget(
            name: "OpenZeusTests",
            dependencies: ["OpenZeus"],
            path: "Tests/OpenZeusTests"
        )
    ]
)
