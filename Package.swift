// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "OpenPaste",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "OpenPaste",
            path: "Sources/OpenPaste"
        )
    ]
)
