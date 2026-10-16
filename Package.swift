// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmoothKeys",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "SmoothKeys", targets: ["SmoothKeys"])
    ],
    targets: [
        .executableTarget(
            name: "SmoothKeys",
            path: "Sources/SmoothKeys"
        )
    ]
)
