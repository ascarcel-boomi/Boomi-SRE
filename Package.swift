// swift-tools-version: 6.0
import PackageDescription

let testingFrameworkPath = "/Library/Developer/CommandLineTools/Library/Developer/Frameworks"

let package = Package(
    name: "BoomiSRE",
    platforms: [.macOS("15.0")],
    targets: [
        .executableTarget(
            name: "BoomiSRE",
            path: "BoomiSRE/Sources",
            resources: [
                .copy("Resources/default_product_maps.json"),
            ]
        ),
        .testTarget(
            name: "BoomiSRETests",
            dependencies: ["BoomiSRE"],
            path: "Tests",
            swiftSettings: [
                .unsafeFlags(["-F", testingFrameworkPath])
            ],
            linkerSettings: [
                .unsafeFlags(["-F", testingFrameworkPath,
                              "-framework", "Testing",
                              "-Xlinker", "-rpath",
                              "-Xlinker", testingFrameworkPath])
            ]
        ),
    ]
)
