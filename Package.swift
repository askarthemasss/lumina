// swift-tools-version: 6.0
import PackageDescription

// Lumina is also buildable directly from this Swift package. The canonical
// Xcode project is generated from project.yml (`xcodegen generate`).
let package = Package(
    name: "Lumina",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Lumina", targets: ["Lumina"])
    ],
    targets: [
        .executableTarget(
            name: "Lumina",
            path: "Sources/Lumina",
            linkerSettings: [
                .linkedFramework("Carbon"),
                .linkedFramework("Speech"),
                .linkedFramework("Vision"),
                .linkedFramework("PDFKit"),
                .linkedFramework("AVFoundation"),
                .linkedLibrary("sqlite3")
            ]
        ),
        .testTarget(
            name: "LuminaTests",
            dependencies: ["Lumina"],
            path: "Tests/LuminaTests"
        )
    ]
)
