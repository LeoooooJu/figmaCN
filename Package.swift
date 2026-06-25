// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FigCNStudioSwift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FigCNStudioSwift", targets: ["FigCNStudioSwift"])
    ],
    targets: [
        .executableTarget(
            name: "FigCNStudioSwift",
            path: "Sources/FigCNStudioSwift"
        )
    ]
)
