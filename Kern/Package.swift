// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Kern",
    platforms: [.iOS(.v17), .watchOS(.v10), .macOS(.v14)],
    products: [.library(name: "Kern", targets: ["Kern"])],
    targets: [
        .target(name: "Kern"),
        .testTarget(name: "KernTests", dependencies: ["Kern"]),
    ]
)
