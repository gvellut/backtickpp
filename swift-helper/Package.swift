// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "BacktickPlusPlusHelper",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "backtick-plus-plus-helper",
            targets: ["BacktickPlusPlusHelper"]
        ),
    ],
    targets: [
        .executableTarget(
            name: "BacktickPlusPlusHelper",
            dependencies: [],
            path: "Sources/BacktickPlusPlusHelper",
            swiftSettings: [
                .unsafeFlags(["-Xfrontend", "-disable-availability-checking"])
            ]
        ),
    ]
)
