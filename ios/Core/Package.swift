// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "PackRipCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [.library(name: "PackRipCore", targets: ["PackRipCore"])],
    targets: [
        .target(name: "PackRipCore"),
        .testTarget(name: "PackRipCoreTests", dependencies: ["PackRipCore"]),
    ]
)
