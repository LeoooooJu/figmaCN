// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "FigmaCNStudioSwift",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .executable(name: "FigmaCNStudioSwift", targets: ["FigmaCNStudioSwift"])
    ],
    targets: [
        .executableTarget(
            name: "FigmaCNStudioSwift",
            path: "Sources/FigmaCNStudioSwift"
        )
    ]
)
