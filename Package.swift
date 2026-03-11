// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "BoomiSRE",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "BoomiSRE",
            path: "BoomiSRE/Sources"
        ),
        .testTarget(
            name: "BoomiSRETests",
            dependencies: ["BoomiSRE"],
            path: "Tests"
        ),
    ]
)
