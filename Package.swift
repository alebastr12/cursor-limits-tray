// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "CursorLimitsTray",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "CursorLimitsTray", targets: ["CursorLimitsTray"])
    ],
    targets: [
        .executableTarget(
            name: "CursorLimitsTray",
            path: "Sources/CursorLimitsTray"
        )
    ]
)
