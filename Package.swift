// swift-tools-version: 5.9
// The iOS app is the Xcode project (project.yml). This package only runs the
// on-device parser and classifier tests with `swift test`.
import PackageDescription

let package = Package(
    name: "SavesSorterCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v13),
    ],
    products: [
        .library(name: "SavesSorterCore", targets: ["SavesSorterCore"]),
    ],
    targets: [
        .target(
            name: "SavesSorterCore",
            path: "SharedCore",
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "SavesSorterCoreTests",
            dependencies: ["SavesSorterCore"],
            path: "SavesSorterTests",
            resources: [
                .process("Fixtures"),
            ]
        ),
    ]
)
