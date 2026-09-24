// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "TranscriberKit",
    platforms: [.macOS("26.0")],
    products: [.library(name: "TranscriberKit", targets: ["TranscriberKit"]),
               .executable(name: "MediaProbe", targets: ["MediaProbe"])],
    targets: [
        .target(name: "TranscriberKit"),
        .executableTarget(name: "MediaProbe", dependencies: ["TranscriberKit"], path: "Tools/MediaProbe"),
        .testTarget(name: "TranscriberKitTests", dependencies: ["TranscriberKit"])
    ]
)
