// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacSnap",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "MacSnap", targets: ["MacSnap"])
    ],
    targets: [
        .executableTarget(
            name: "MacSnap",
            path: "Sources/MacSnap"
        ),
        .testTarget(
            name: "MacSnapTests",
            dependencies: ["MacSnap"],
            path: "Tests/MacSnapTests"
        ),
    ]
)
