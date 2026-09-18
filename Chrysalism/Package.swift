// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Chrysalism",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "Chrysalism", targets: ["Chrysalism"])
    ],
    targets: [
        .executableTarget(name: "Chrysalism", path: "Sources/Chrysalism")
    ]
)